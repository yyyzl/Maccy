import Foundation
import SwiftData

@Model
class HistoryItem {
  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies = 1
  var pin: String?
  var title = ""
  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
  var contents: [HistoryItemContent] = []
  init(contents: [HistoryItemContent] = []) {
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.contents = contents
  }
}

@Model
class HistoryItemContent {
  var type: String = ""
  var value: Data?
  @Relationship
  var item: HistoryItem?
  init(type: String, value: Data? = nil) { self.type = type; self.value = value }
}
