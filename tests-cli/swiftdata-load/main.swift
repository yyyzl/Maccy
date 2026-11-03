import Foundation
import SwiftData

// Stub required only because the production metadata lookup shares a file with
// ApplicationImageCache. No system pasteboard or user data is accessed.
final class ApplicationImage {
  init(bundleIdentifier: String?) {}
}

setbuf(stdout, nil)
guard CommandLine.arguments.count == 3 else {
  fputs("Usage: swiftdata-test <prepare|legacy|metadata|payload> <store path>\n", stderr)
  exit(2)
}
let mode = CommandLine.arguments[1]
let url = URL(fileURLWithPath: CommandLine.arguments[2])
let itemCount = 10
let payloadMiB = 4
let markerType = "com.apple.is-remote-clipboard"
let imageType = "public.tiff"
let container = try ModelContainer(
  for: HistoryRecord.self, HistoryContent.self,
  configurations: ModelConfiguration(url: url)
)

if mode == "prepare" {
  for index in 0..<itemCount {
    autoreleasepool {
      let context = ModelContext(container)
      let record = HistoryRecord(title: "synthetic-\(index)")
      context.insert(record)
      var bytes = Data(count: payloadMiB * 1024 * 1024)
      _ = bytes.withUnsafeMutableBytes { memset($0.baseAddress!, Int32(index + 1), $0.count) }
      let image = HistoryContent(type: imageType, value: bytes)
      image.tag = "synthetic-\(index)"
      context.insert(image)
      image.item = record
      if index == 2 || index == 7 || index == 4 || index == 5 {
        let marker = HistoryContent(type: markerType, value: index == 4 || index == 5 ? nil : Data())
        context.insert(marker)
        marker.item = record
      }
      if index == 5 {
        let duplicate = HistoryContent(type: markerType, value: Data())
        context.insert(duplicate)
        duplicate.item = record
      }
      try! context.save()
    }
  }
  print("READY prepared items=10 image_payload=40MiB")
  exit(0)
}

func predicate(for value: String) -> Predicate<HistoryContent> {
  Predicate<HistoryContent> { content in
    PredicateExpressions.build_Equal(
      lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(content), keyPath: \HistoryContent.type),
      rhs: PredicateExpressions.build_Arg(value)
    )
  }
}
func tagPredicate(for value: String) -> Predicate<HistoryContent> {
  Predicate<HistoryContent> { content in
    PredicateExpressions.build_Equal(
      lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(content), keyPath: \HistoryContent.tag),
      rhs: PredicateExpressions.build_Arg(value)
    )
  }
}
func require(_ ok: @autoclosure () -> Bool, _ message: String) {
  if !ok() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let context = ModelContext(container)
let records = try context.fetch(FetchDescriptor<HistoryRecord>())
var heldContents: [HistoryContent] = []
var verified = 0
if mode == "legacy" {
  heldContents = try context.fetch(FetchDescriptor<HistoryContent>())
  for record in records {
    let contents = heldContents.filter { $0.item?.persistentModelID == record.persistentModelID }
    _ = contents.first(where: { $0.type == markerType })?.value != nil
  }
} else if mode == "metadata" {
  let hints = try MainActor.assumeIsolated {
    try loadUniversalClipboardHints(context: context, markerType: markerType)
  }
  for record in records {
    switch record.title {
    case "synthetic-2", "synthetic-7":
      require(hints.hint(for: record.persistentModelID) == true, "remote marker not found")
    case "synthetic-5":
      require(hints.hint(for: record.persistentModelID) == nil, "duplicate marker must use legacy fallback")
    default:
      require(hints.hint(for: record.persistentModelID) == false, "normal or nil-marker item changed")
    }
  }
} else if mode == "main-thumbs" || mode == "scratch-thumbs" {
  for index in 0..<itemCount {
    try autoreleasepool {
      let readContext = mode == "scratch-thumbs" ? ModelContext(container) : context
      let descriptor = FetchDescriptor<HistoryContent>(predicate: tagPredicate(for: "synthetic-\(index)"))
      let content = try readContext.fetch(descriptor).first!
      let bytes = content.value!
      require(bytes.count == payloadMiB * 1024 * 1024 && bytes.first == UInt8(index + 1), "bad synthetic payload")
      if mode == "main-thumbs" { heldContents.append(content) }
      verified += 1
    }
  }
} else if mode == "payload" {
  heldContents = try context.fetch(FetchDescriptor<HistoryContent>(predicate: predicate(for: imageType)))
  for content in heldContents {
    let bytes = content.value!
    let title = content.item!.title
    let index = Int(title.split(separator: "-").last!)!
    require(bytes.count == payloadMiB * 1024 * 1024 && bytes.allSatisfy({ $0 == UInt8(index + 1) }),
            "synthetic original data changed on disk")
    verified += 1
  }
  require(verified == itemCount, "not all synthetic images were restored")
} else {
  fputs("Unknown mode\n", stderr)
  exit(2)
}
print("READY \(mode) items=\(records.count) fetched_contents=\(heldContents.count) verified=\(verified)")
withExtendedLifetime((container, context, records, heldContents)) { _ = sleep(20) }
