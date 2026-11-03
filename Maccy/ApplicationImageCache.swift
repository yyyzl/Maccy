import Foundation
import SwiftData

// A duplicate marker needs the original lookup because relationship ordering may matter.
struct UniversalClipboardHints<ItemID: Hashable> {
  private var seen: Set<ItemID> = []
  private var present: Set<ItemID> = []
  private var ambiguous: Set<ItemID> = []

  init() {}

  mutating func add(itemID: ItemID, valueExists: Bool) {
    if !seen.insert(itemID).inserted {
      ambiguous.insert(itemID)
    } else if valueExists {
      present.insert(itemID)
    }
  }

  func hint(for itemID: ItemID) -> Bool? {
    guard !ambiguous.contains(itemID) else { return nil }
    return present.contains(itemID)
  }
}

@MainActor
func loadUniversalClipboardHints(
  context: ModelContext,
  markerType: String
) throws -> UniversalClipboardHints<PersistentIdentifier> {
  let predicate = Predicate<HistoryItemContent> { marker in
    PredicateExpressions.build_Equal(
      lhs: PredicateExpressions.build_KeyPath(
        root: PredicateExpressions.build_Arg(marker),
        keyPath: \HistoryItemContent.type
      ),
      rhs: PredicateExpressions.build_Arg(markerType)
    )
  }
  let markers = try context.fetch(FetchDescriptor<HistoryItemContent>(predicate: predicate))
  var hints = UniversalClipboardHints<PersistentIdentifier>()
  for marker in markers {
    if let item = marker.item {
      hints.add(itemID: item.persistentModelID, valueExists: marker.value != nil)
    }
  }
  return hints
}

class ApplicationImageCache {
  static let shared = ApplicationImageCache()

  private let universalClipboardIdentifier: String =
  "com.apple.finder.Open-iCloudDrive"
  private let fallback = ApplicationImage(bundleIdentifier: nil)
  private var cache: [String: ApplicationImage] = [:]

  func getImage(item: HistoryItem, universalClipboardHint: Bool? = nil) -> ApplicationImage {
    guard let bundleIdentifier = bundleIdentifier(for: item, universalClipboardHint: universalClipboardHint) else {
      return fallback
    }

    if let image = cache[bundleIdentifier] {
      return image
    }

    let image = ApplicationImage(bundleIdentifier: bundleIdentifier)
    cache[bundleIdentifier] = image

    return image
  }

  private func bundleIdentifier(for item: HistoryItem, universalClipboardHint: Bool?) -> String? {
    if universalClipboardHint ?? item.universalClipboard {
      return universalClipboardIdentifier
    }

    if let bundleIdentifier = item.application {
      return bundleIdentifier
    }

    return nil
  }
}
