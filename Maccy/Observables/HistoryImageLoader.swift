import AppKit
import SwiftData

// Read image data in a short-lived context so list previews do not keep the
// original data in the long-lived history context. Unsaved edits must use the
// original context to avoid showing a stale image.
enum HistoryImageLoader {
  @MainActor
  static func resizedImage(for item: HistoryItem, maxSize: NSSize) -> NSImage? {
    func resize(_ source: HistoryItem) -> NSImage? {
      source.image?.resized(to: maxSize)
    }

    guard let originalContext = item.modelContext,
      !originalContext.hasChanges,
      !item.isDeleted,
      item.persistentModelID.storeIdentifier != nil
    else {
      return resize(item)
    }

    return autoreleasepool {
      let readContext = ModelContext(originalContext.container)
      guard let stored = readContext.model(for: item.persistentModelID) as? HistoryItem else {
        return resize(item)
      }
      return resize(stored)
    }
  }
}
