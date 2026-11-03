// 独立合成探针：仅比较写入上下文寿命，不代替应用去重/OCR/界面验收。
import CryptoKit
import Darwin
import Foundation
import SwiftData

@Model
final class HistoryItem {
  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies = 1
  var pin: String?
  var title = ""
  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
  var contents: [HistoryItemContent] = []
  init(contents: [HistoryItemContent]) { self.contents = contents }
}

@Model
final class HistoryItemContent {
  var type: String
  var value: Data?
  var item: HistoryItem?
  init(type: String, value: Data?) { self.type = type; self.value = value }
}

let mode = CommandLine.arguments[1]
precondition(["main", "writer", "type", "value", "reader", "rollback"].contains(mode))
let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[2]))
let container = try ModelContainer(for: HistoryItem.self, configurations: config)
let metadataContext = MainActor.assumeIsolated { container.mainContext }
var items: [HistoryItem] = []
var hashes: [PersistentIdentifier: SHA256.Digest] = [:]
for index in 0..<20 {
  try autoreleasepool {
    var bytes = Data(count: 8 * 1024 * 1024)
    bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }
    let item = HistoryItem(contents: [HistoryItemContent(type: "public.tiff", value: bytes)])
    item.title = "Synthetic image \(index)"
    let writeContext = mode == "writer" ? ModelContext(container) : metadataContext
    writeContext.insert(item)
    try writeContext.save()
    hashes[item.persistentModelID] = SHA256.hash(data: bytes)
    let metadata = metadataContext.model(for: item.persistentModelID) as! HistoryItem
    precondition(metadata.title == "Synthetic image \(index)")
    items.append(metadata)
    if ["type", "value", "rollback"].contains(mode) {
      precondition(metadata.contents[0].type == "public.tiff")
      if mode != "type" { precondition(SHA256.hash(data: metadata.contents[0].value!) == hashes[item.persistentModelID]) }
    } else if mode == "reader" {
      autoreleasepool {
        let readContext = ModelContext(container)
        let stored = readContext.model(for: metadata.persistentModelID) as! HistoryItem
        precondition(SHA256.hash(data: stored.contents[0].value!) == hashes[item.persistentModelID])
      }
    }
  }
}
items[0].pin = "p"
items[0].numberOfCopies = 7
try metadataContext.save()
if mode == "rollback" {
  precondition(!metadataContext.hasChanges)
  metadataContext.rollback()
  precondition(items[0].pin == "p" && items[0].numberOfCopies == 7)
  precondition(items[19].title == "Synthetic image 19")
}
// 全部原始字节经另一个短上下文核验，避免验证本身加载到常驻模型。
for item in items {
  autoreleasepool {
    let context = ModelContext(container)
    let stored = context.model(for: item.persistentModelID) as! HistoryItem
    precondition(SHA256.hash(data: stored.contents[0].value!) == hashes[item.persistentModelID])
    if item === items[0] { precondition(stored.pin == "p" && stored.numberOfCopies == 7) }
  }
}
print("PROBE_READY mode=\(mode) items=\(items.count) bytes=167772160 pid=\(getpid())")
fflush(stdout)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 90))
precondition(items.count == 20)
