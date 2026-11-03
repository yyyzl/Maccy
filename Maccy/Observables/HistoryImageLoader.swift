import AppKit
import SwiftData
import Vision

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
  static func recognizedText(in image: CGImage) -> String? {
    // 后台任务的 Objective-C 临时对象在识别完成后释放，只返回文字。
    autoreleasepool {
      let handler = VNImageRequestHandler(cgImage: image)
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .fast
      do {
        try handler.perform([request])
      } catch {
        print("Unable to perform the request: \(error).")
      }
      return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
  }

  @MainActor
  static func resizedImage(for item: HistoryItem, maxSize: NSSize) -> NSImage? {
    HistoryItemReader.read(item) { source in
      source.image?.resized(to: maxSize)
    }
  }
}
