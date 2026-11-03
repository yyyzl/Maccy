import AppKit
import Foundation
import SwiftData

setbuf(stdout, nil)
enum LoaderProbe { static var lastContext: ObjectIdentifier? }

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

// Test-only image access. The production HistoryItem reads its related
// pasteboard content directly; this one-way synthetic model uses a tag query.
extension HistoryRecord {
  var image: NSImage? {
    guard let context = modelContext else { return nil }
    LoaderProbe.lastContext = ObjectIdentifier(context)
    let tag = String(title.split(separator: "/").first ?? "")
    let predicate = Predicate<HistoryContent> { content in
      PredicateExpressions.build_Equal(
        lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(content), keyPath: \HistoryContent.tag),
        rhs: PredicateExpressions.build_Arg(tag)
      )
    }
    guard let content = try? context.fetch(FetchDescriptor<HistoryContent>(predicate: predicate)).first,
      let value = content.value
    else { return nil }
    return NSImage(data: value)
  }
}

try MainActor.assumeIsolated {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try ModelContainer(for: HistoryRecord.self, HistoryContent.self, configurations: config)
  let context = ModelContext(container)
  let record = HistoryRecord(title: "synthetic-0")
  context.insert(record)

  let source = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  memset(source.bitmapData!, 255, source.bytesPerRow * source.pixelsHigh)
  let originalBytes = source.representation(using: .tiff, properties: [:])!
  let content = HistoryContent(type: "public.tiff", value: originalBytes)
  content.tag = record.title
  context.insert(content)
  content.item = record
  try context.save()
  require(!context.hasChanges, "synthetic fixture was not saved")

  LoaderProbe.lastContext = nil
  let thumbnail = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
  require(thumbnail?.size == NSSize(width: 340, height: 170), "saved thumbnail dimensions changed")
  require(LoaderProbe.lastContext != nil && LoaderProbe.lastContext != ObjectIdentifier(context),
          "saved image was loaded in the long-lived context")

  let fresh = ModelContext(container)
  let preserved = try fresh.fetch(FetchDescriptor<HistoryContent>()).first!.value!
  require(preserved == originalBytes, "source image bytes changed")

  let unrelated = HistoryRecord(title: "another-item")
  context.insert(unrelated)
  try context.save()
  unrelated.title += "/edited"
  LoaderProbe.lastContext = nil
  _ = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
  require(LoaderProbe.lastContext != ObjectIdentifier(context),
          "an unrelated edit loaded a saved image in the long-lived context")
  try context.save()

  record.title += "/edited"
  require(context.hasChanges, "fixture did not create unsaved changes")
  LoaderProbe.lastContext = nil
  let changedThumbnail = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
  require(changedThumbnail != nil, "unsaved item lost its preview")
  require(LoaderProbe.lastContext == ObjectIdentifier(context), "unsaved edits were read from a stale context")
  try context.save()
  content.value = originalBytes
  content.tag += "-edited"
  LoaderProbe.lastContext = nil
  _ = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
  require(LoaderProbe.lastContext == ObjectIdentifier(context),
          "unsaved content changes were read from a stale context")
  try context.save()
  context.delete(content)
  LoaderProbe.lastContext = nil
  _ = HistoryImageLoader.resizedImage(for: record, maxSize: NSSize(width: 340, height: 200))
  require(LoaderProbe.lastContext == ObjectIdentifier(context),
          "an unsaved content deletion was read from a stale context")

  let uninserted = HistoryRecord(title: "not-in-a-context")
  require(HistoryImageLoader.resizedImage(for: uninserted, maxSize: NSSize(width: 340, height: 200)) == nil,
          "uninserted item changed behavior")

  let ocrBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 200,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  memset(ocrBitmap.bitmapData!, 255, ocrBitmap.bytesPerRow * ocrBitmap.pixelsHigh)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: ocrBitmap)
  ("Memory 123" as NSString).draw(at: NSPoint(x: 30, y: 55), withAttributes: [
    .font: NSFont.systemFont(ofSize: 80), .foregroundColor: NSColor.black
  ])
  NSGraphicsContext.restoreGraphicsState()
  let pixels = Data(bytes: ocrBitmap.bitmapData!, count: ocrBitmap.bytesPerRow * ocrBitmap.pixelsHigh)
  let recognized = HistoryImageLoader.recognizedText(in: ocrBitmap.cgImage!)
  require(recognized?.contains("Memory") == true && recognized?.contains("123") == true,
          "OCR no longer returns recognized text")
  require(Data(bytes: ocrBitmap.bitmapData!, count: pixels.count) == pixels, "OCR changed source pixels")
  print("PASS: saved images use a temporary context; unsaved changes fall back; original bytes preserved")
  print("PASS: OCR returns recognized text and preserves source pixels")
}
