import AppKit
import Foundation
import SwiftData

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@main
struct DecoratorTest {
  @MainActor
  static func main() async throws {
    let container = try ModelContainer(
      for: HistoryRecord.self, HistoryContent.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)
    let record = HistoryRecord(title: "synthetic-0")
    context.insert(record)
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 400,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    memset(bitmap.bitmapData!, 255, bitmap.bytesPerRow * bitmap.pixelsHigh)
    let content = HistoryContent(type: "public.tiff", value: bitmap.representation(using: .tiff, properties: [:])!)
    content.tag = record.title
    context.insert(content)
    content.item = record
    try context.save()

    let decorator = HistoryItemDecorator(record, universalClipboardHint: false)
    require(record.clipboardReads == 0, "hint caused original-content lookup")
    decorator.ensureThumbnailImage()
    for _ in 0..<30 where decorator.thumbnailImage == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    require(decorator.thumbnailImage != nil, "thumbnail did not generate")
    require(decorator.thumbnailImage!.size == NSSize(width: 80, height: 40), "thumbnail dimensions changed")
    decorator.cleanupImages()
    require(decorator.thumbnailImage == nil && decorator.thumbnailImageGenerationTask == nil,
            "cleanup did not release the thumbnail or task")
    decorator.ensureThumbnailImage()
    for _ in 0..<30 where decorator.thumbnailImage == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    require(decorator.thumbnailImage != nil, "thumbnail did not regenerate after cleanup")
    decorator.cleanupImages()
    print("PASS: decorator generates, releases and regenerates an isolated thumbnail")
  }
}
