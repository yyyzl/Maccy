#if DEBUG
import AppKit
import Foundation
import SwiftData

// This test only runs when explicitly requested in the isolated test bundle.
// It never reads or writes NSPasteboard.general.
enum IsolatedMemorySmoke {
  private static let testBundleID = "org.yyyzl.MaccyMemoryTest"
  private static let itemCount = 10
  private static let prefix = "[MaccyMemorySmoke]"

  @MainActor
  static func runIfRequested() {
    let args = CommandLine.arguments
    let modes = ["--isolated-seed", "--isolated-load", "--isolated-paste"]
    guard let mode = modes.first(where: args.contains) else { return }

    // Refuse to touch any real Maccy container or the general pasteboard.
    guard Bundle.main.bundleIdentifier == testBundleID,
      UserDefaults.standard.bool(forKey: "ignoreEvents"),
      !args.contains("enable-testing")
    else {
      NSLog("%@ FAIL: isolated bundle, disabled clipboard and disk fixture are required", prefix)
      NSApp.terminate(nil)
      return
    }

    Task { @MainActor in
      do {
        switch mode {
        case "--isolated-seed":
          try seed()
          NSLog("%@ SEED_OK items=%d", prefix, itemCount)
          NSApp.terminate(nil)
        case "--isolated-load":
          try await load()
          NSLog("%@ LOAD_OK items=%d", prefix, itemCount)
        case "--isolated-paste":
          try await testPrivatePasteboard()
          NSLog("%@ PASTE_OK tiff_and_png_match_original", prefix)
          NSApp.terminate(nil)
        default:
          break
        }
      } catch {
        NSLog("%@ FAIL: %@", prefix, String(describing: error))
        NSApp.terminate(nil)
      }
    }
  }

  @MainActor
  private static func seed() throws {
    let context = Storage.shared.context
    guard try context.fetchCount(FetchDescriptor<HistoryItem>()) == 0 else {
      throw SmokeError.fixtureAlreadyExists
    }

    for index in 0..<itemCount {
      try autoreleasepool {
        guard let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil,
          pixelsWide: 1600,
          pixelsHigh: 900,
          bitsPerSample: 8,
          samplesPerPixel: 4,
          hasAlpha: true,
          isPlanar: false,
          colorSpaceName: .deviceRGB,
          bytesPerRow: 0,
          bitsPerPixel: 0
        ), let pixels = bitmap.bitmapData else { throw SmokeError.imageGenerationFailed }

        let byteCount = bitmap.bytesPerRow * bitmap.pixelsHigh
        arc4random_buf(pixels, byteCount)
        for offset in stride(from: 3, to: byteCount, by: 4) {
          pixels[offset] = 255
        }
        guard let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
          throw SmokeError.imageGenerationFailed
        }
        var contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: tiff)]
        if index == 0 {
          guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeError.imageGenerationFailed
          }
          contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: png))
        }
        let item = HistoryItem(contents: contents)
        item.title = "Synthetic image \(index)"
        item.firstCopiedAt = Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
        item.lastCopiedAt = item.firstCopiedAt
        context.insert(item)
      }
    }
    try context.save()
  }

  @MainActor
  private static func load() async throws {
    try await History.shared.load()
    guard History.shared.items.count == itemCount else { throw SmokeError.wrongItemCount }
    for item in History.shared.items {
      item.ensureThumbnailImage()
    }
    for _ in 0..<100 {
      if History.shared.items.allSatisfy({ $0.thumbnailImage != nil }) { return }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw SmokeError.thumbnailTimeout
  }

  @MainActor
  private static func testPrivatePasteboard() async throws {
    try await History.shared.load()
    guard let item = History.shared.items.first(where: { item in
      item.item.contents.contains { $0.type == NSPasteboard.PasteboardType.png.rawValue }
    })?.item else { throw SmokeError.missingMultiFormatImage }

    let types: [NSPasteboard.PasteboardType] = [.tiff, .png]
    var originals: [NSPasteboard.PasteboardType: Data] = [:]
    for type in types {
      guard let data = item.contents.first(where: { $0.type == type.rawValue })?.value else {
        throw SmokeError.missingMultiFormatImage
      }
      originals[type] = data
    }

    let name = NSPasteboard.Name("org.yyyzl.MaccyMemoryTest.\(UUID().uuidString)")
    let board = NSPasteboard(name: name)
    let clipboard = Clipboard(pasteboard: board, notifyOnCopy: false)
    clipboard.copy(item)
    for type in types {
      guard board.data(forType: type) == originals[type] else { throw SmokeError.pasteMismatch }
    }
    try await Task.sleep(nanoseconds: 300_000_000)
    board.releaseGlobally()
  }

  private enum SmokeError: Error {
    case fixtureAlreadyExists
    case imageGenerationFailed
    case wrongItemCount
    case thumbnailTimeout
    case missingMultiFormatImage
    case pasteMismatch
  }
}
#endif
