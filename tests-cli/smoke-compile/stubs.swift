import AppKit
import Foundation
import SwiftData
import Observation

final class HistoryItemContent {
  var type: String
  var value: Data?
  init(type: String, value: Data?) { self.type = type; self.value = value }
}
final class HistoryItem: PersistentModel {
  var persistentBackingData: any BackingData<HistoryItem> = HistoryItem.createBackingData()
  static var schemaMetadata: [Schema.PropertyMetadata] {
    [Schema.PropertyMetadata(name: "title", keypath: \HistoryItem.title, defaultValue: "")]
  }
  required init(backingData: any BackingData<HistoryItem>) { persistentBackingData = backingData }
  init(contents: [HistoryItemContent]) { self.contents = contents; self.title = "" }
  var contents: [HistoryItemContent] = []
  var firstCopiedAt = Date()
  var lastCopiedAt = Date()
  var title: String {
    get { getValue(forKey: \HistoryItem.title) }
    set { setValue(forKey: \HistoryItem.title, to: newValue) }
  }
}
@MainActor
final class Storage {
  static let shared = Storage()
  let container: ModelContainer
  var context: ModelContext { container.mainContext }
  init() {
    container = try! ModelContainer(for: HistoryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  }
}
@MainActor
final class HistoryItemDecorator {
  let item: HistoryItem
  var thumbnailImage: NSImage?
  init(item: HistoryItem) { self.item = item }
  func ensureThumbnailImage() {}
}
@MainActor
final class History {
  static let shared = History()
  var items: [HistoryItemDecorator] = []
  func load() async throws {}
}
@MainActor
final class Clipboard {
  init(pasteboard: NSPasteboard = .general, notifyOnCopy: Bool = true) {}
  func copy(_ item: HistoryItem?) {}
}
