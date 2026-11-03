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

    weak var discarded: HistoryItemDecorator?
    autoreleasepool {
      let temporary = HistoryItemDecorator(record, universalClipboardHint: false)
      discarded = temporary
    }
    require(discarded == nil, "observation callbacks retain a discarded decorator")
    print("PASS: observation callbacks release a discarded decorator")

    let decorator = HistoryItemDecorator(record, universalClipboardHint: false)
    require(record.clipboardReads == 0, "hint caused original-content lookup")
    record.title += "/edited"
    try await Task.sleep(nanoseconds: 30_000_000)
    require(decorator.title == record.title, "weak observation stopped updating a live decorator")
    try context.save()
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
    decorator.ensurePreviewImage()
    for _ in 0..<30 where decorator.previewImage == nil {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    require(decorator.previewImage != nil, "preview did not generate")
    decorator.showPreview = true
    decorator.showPreview = false
    require(decorator.previewImage == nil && decorator.previewImageGenerationTask == nil,
            "dismissing the preview retains its bitmap or task")
    decorator.ensurePreviewImage()
    decorator.showPreview = false
    try await Task.sleep(nanoseconds: 30_000_000)
    require(decorator.previewImage == nil, "a cancelled preview regenerated after dismissal")
    decorator.cleanupImages()
    print("PASS: decorator generates, releases and regenerates an isolated thumbnail")
  }
}
