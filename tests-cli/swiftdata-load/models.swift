// Manual PersistentModel implementations let this isolated test exercise the
// system SwiftData runtime with the Command Line Tools, without macro plugins.
// The production models use @Model and have an inverse to-many relationship;
// this synthetic model intentionally keeps only the child-to-parent relation.
import Foundation
import SwiftData
import Observation

typealias HistoryItem = HistoryRecord
typealias HistoryItemContent = HistoryContent

final class HistoryRecord: PersistentModel {
  // Non-persistent fields used only by the application-icon mock.
  var application: String?
  var pin: String?
  var fallbackRemote = false
  var clipboardReads = 0
  // Mimics a loaded to-many relationship held by a history item in the preview benchmark.
  var retainedContent: HistoryContent?
  var universalClipboard: Bool {
    clipboardReads += 1
    return fallbackRemote
  }
  var persistentBackingData: any BackingData<HistoryRecord> = HistoryRecord.createBackingData()
  static var schemaMetadata: [Schema.PropertyMetadata] {
    [Schema.PropertyMetadata(name: "title", keypath: \HistoryRecord.title, defaultValue: "")]
  }
  required init(backingData: any BackingData<HistoryRecord>) { persistentBackingData = backingData }
  init(title: String) { self.title = title }
  var title: String {
    get { getValue(forKey: \HistoryRecord.title) }
    set { setValue(forKey: \HistoryRecord.title, to: newValue) }
  }
}

final class HistoryContent: PersistentModel {
  var persistentBackingData: any BackingData<HistoryContent> = HistoryContent.createBackingData()
  static var schemaMetadata: [Schema.PropertyMetadata] {
    [
      Schema.PropertyMetadata(name: "type", keypath: \HistoryContent.type, defaultValue: ""),
      Schema.PropertyMetadata(name: "tag", keypath: \HistoryContent.tag, defaultValue: ""),
      Schema.PropertyMetadata(name: "value", keypath: \HistoryContent.value),
      Schema.PropertyMetadata(name: "item", keypath: \HistoryContent.item, metadata: Schema.Relationship())
    ]
  }
  required init(backingData: any BackingData<HistoryContent>) { persistentBackingData = backingData }
  init(type: String, value: Data?) { self.type = type; self.tag = ""; self.value = value }
  var type: String {
    get { getValue(forKey: \HistoryContent.type) }
    set { setValue(forKey: \HistoryContent.type, to: newValue) }
  }
  var tag: String {
    get { getValue(forKey: \HistoryContent.tag) }
    set { setValue(forKey: \HistoryContent.tag, to: newValue) }
  }
  var value: Data? {
    get { getValue(forKey: \HistoryContent.value) }
    set { setValue(forKey: \HistoryContent.value, to: newValue) }
  }
  var item: HistoryRecord? {
    get { getValue(forKey: \HistoryContent.item) }
    set { setValue(forKey: \HistoryContent.item, to: newValue) }
  }
}
