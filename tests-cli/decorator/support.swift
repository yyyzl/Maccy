import AppKit
import Foundation
import SwiftData

class ApplicationImage {
  let bundleIdentifier: String?
  init(bundleIdentifier: String?) { self.bundleIdentifier = bundleIdentifier }
}
struct KeyShortcut {
  static func create(character: String) -> [KeyShortcut] { [] }
}
extension NSScreen {
  static var forPopup: NSScreen? { NSScreen.main }
}
extension HistoryRecord {
  static var randomAvailablePin: String { "p" }
  var previewableText: String { title }
  var image: NSImage? {
    guard let context = modelContext else { return nil }
    let tag = String(title.split(separator: "/").first ?? "")
    let predicate = Predicate<HistoryContent> { content in
      PredicateExpressions.build_Equal(
        lhs: PredicateExpressions.build_KeyPath(root: PredicateExpressions.build_Arg(content), keyPath: \HistoryContent.tag),
        rhs: PredicateExpressions.build_Arg(tag)
      )
    }
    guard let content = try? context.fetch(FetchDescriptor<HistoryContent>(predicate: predicate)).first,
      let data = content.value else { return nil }
    return NSImage(data: data)
  }
}
