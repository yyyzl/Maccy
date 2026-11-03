import AppKit
import SwiftData

// Keep persisted payload reads out of the long-lived editing context. Pending
// changes to this item must still be read from their original context.
enum HistoryItemReader {
  // Return values must not retain persisted models after this read context ends.
  static func read<Result>(_ item: HistoryItem, _ body: (HistoryItem) -> Result) -> Result {
    guard let originalContext = item.modelContext,
      !item.isDeleted,
      item.persistentModelID.storeIdentifier != nil
    else {
      return body(item)
    }

    if originalContext.hasChanges {
      let pending = originalContext.insertedModelsArray + originalContext.changedModelsArray +
        originalContext.deletedModelsArray
      let identifier = item.persistentModelID
      let hasPendingContent = pending.contains { model in
        if model.persistentModelID == identifier { return true }
        guard let content = model as? HistoryItemContent else { return false }
        // A deleted child's inverse may already be cleared, so retain the safe fallback.
        return content.isDeleted || content.item?.persistentModelID == identifier
      }
      if hasPendingContent { return body(item) }
    }

    return autoreleasepool {
      let readContext = ModelContext(originalContext.container)
      guard let stored = readContext.model(for: item.persistentModelID) as? HistoryItem else {
        return body(item)
      }
      return body(stored)
    }
  }
}

enum HistoryImageLoader {
  @MainActor
  static func resizedImage(for item: HistoryItem, maxSize: NSSize) -> NSImage? {
    HistoryItemReader.read(item) { source in
      source.image?.resized(to: maxSize)
    }
  }
}
