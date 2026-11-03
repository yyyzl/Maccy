import AppKit
import Foundation
import SwiftData

setbuf(stdout, nil)
guard CommandLine.arguments.count == 3 else { exit(2) }
let mode = CommandLine.arguments[1]
let url = URL(fileURLWithPath: CommandLine.arguments[2])
let itemCount = 10
let imageType = "public.tiff"
let container = try ModelContainer(
  for: HistoryRecord.self, HistoryContent.self,
  configurations: ModelConfiguration(url: url)
)

enum Probe {
  static var mainContextID: ObjectIdentifier?
  static var mainReads = 0
  static var scratchReads = 0
}

func tagPredicate(_ tag: String) -> Predicate<HistoryContent> {
  Predicate<HistoryContent> { content in
    PredicateExpressions.build_Equal(
      lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(content), keyPath: \HistoryContent.tag),
      rhs: PredicateExpressions.build_Arg(tag)
    )
  }
}

// Test-only image access via a one-way relation. Holding the content mimics
// the production item's to-many relationship in the long-lived context.
extension HistoryRecord {
  var image: NSImage? {
    guard let context = modelContext else { return nil }
    if ObjectIdentifier(context) == Probe.mainContextID { Probe.mainReads += 1 } else { Probe.scratchReads += 1 }
    guard let content = try? context.fetch(FetchDescriptor<HistoryContent>(predicate: tagPredicate(title))).first,
      let value = content.value else { return nil }
    retainedContent = content
    return NSImage(data: value)
  }
}

if mode == "prepare" {
  var totalBytes = 0
  for index in 0..<itemCount {
    autoreleasepool {
      let context = ModelContext(container)
      let record = HistoryRecord(title: "synthetic-\(index)")
      context.insert(record)
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      )!
      let bytes = bitmap.bitmapData!
      arc4random_buf(bytes, bitmap.bytesPerRow * bitmap.pixelsHigh)
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          bytes[y * bitmap.bytesPerRow + x * 4 + 3] = 255
        }
      }
      let data = bitmap.representation(using: .tiff, properties: [:])!
      totalBytes += data.count
      let content = HistoryContent(type: imageType, value: data)
      content.tag = record.title
      context.insert(content)
      content.item = record
      try! context.save()
    }
  }
  print("READY prepared images=\(itemCount) encoded_mib=\(totalBytes / 1048576)")
  exit(0)
}

let context = ModelContext(container)
let records = try context.fetch(FetchDescriptor<HistoryRecord>())
Probe.mainContextID = ObjectIdentifier(context)
var thumbnails: [NSImage] = []
MainActor.assumeIsolated {
  for record in records {
    let image: NSImage?
    if mode == "before" {
      image = record.image?.resized(to: NSSize(width: 340, height: 200))
    } else if mode == "after" {
      image = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
    } else {
      fputs("Unknown mode\n", stderr)
      exit(2)
    }
    guard let image, image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
      fputs("FAIL missing or unrenderable thumbnail\n", stderr)
      exit(1)
    }
    thumbnails.append(image)
  }
}
if mode == "before" && Probe.mainReads != itemCount { exit(1) }
if mode == "after" && Probe.scratchReads != itemCount { exit(1) }
print("READY \(mode) thumbnails=\(thumbnails.count) main_reads=\(Probe.mainReads) scratch_reads=\(Probe.scratchReads)")
withExtendedLifetime((context, records, thumbnails)) { _ = sleep(20) }
