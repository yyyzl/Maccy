#if DEBUG || MEMORY_LIFECYCLE
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
    #if MEMORY_LIFECYCLE
    if CommandLine.arguments.contains("--isolated-lifecycle") {
      IsolatedMemoryLifecycle.run()
      return
    }
    #endif
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

// These operations exercise the real History and Clipboard implementations using
// synthetic stores only. They must never run in either of the user's app bundles.
#if MEMORY_LIFECYCLE
enum IsolatedMemoryLifecycle {
  @MainActor
  static func run() {
    let args = CommandLine.arguments
    guard Bundle.main.bundleIdentifier == "org.yyyzl.MaccyMemoryLifecycle",
      UserDefaults.standard.bool(forKey: "ignoreEvents"),
      !UserDefaults.standard.bool(forKey: "clearOnQuit"),
      let scenario = args.first(where: { $0.hasPrefix("--scenario=") })?.split(separator: "=").last.map(String.init),
      ["seed", "idle", "text", "duplicate", "image", "preview", "browse", "copy", "long"].contains(scenario),
      let store = args.first(where: { $0.hasPrefix("--store=") })?.split(separator: "=").last.map(String.init),
      !store.isEmpty, store.count < 80,
      store.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    else {
      NSLog("[MaccyLifecycle] FAIL isolation flags"); exit(2)
    }

    Task { @MainActor in
      do {
        let directory = URL.applicationSupportDirectory.appending(path: "Maccy/Lifecycle/\(store)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Storage.shared.container = try ModelContainer(
          for: HistoryItem.self,
          configurations: ModelConfiguration(url: directory.appending(path: "Storage.sqlite"))
        )
        if scenario == "seed" {
          guard try Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>()) == 0 else {
            throw LifecycleError.invalidFixture
          }
          for index in 0..<200 {
            try autoreleasepool {
              let context = ModelContext(Storage.shared.container)
              let item = index % 10 == 0 ? image(index) : text(index)
              context.insert(item)
              try context.save()
            }
          }
          NSLog("[MaccyLifecycle] SEED_OK items=200"); exit(0)
        }

        try await History.shared.load()
        guard History.shared.all.count == 200,
          History.shared.all.allSatisfy({ $0.item.title.hasPrefix("Lifecycle synthetic ") })
        else { throw LifecycleError.invalidFixture }

        switch scenario {
        case "text":
          for index in 200..<220 {
            Clipboard.shared.changeCount += 1
            History.shared.add(text(index))
          }
        case "image":
          for index in 200..<220 {
            Clipboard.shared.changeCount += 1
            autoreleasepool { History.shared.add(image(index)) }
          }
        case "duplicate":
          for _ in 0..<20 {
            Clipboard.shared.changeCount += 1
            let item = image(0)
            History.shared.add(item)
          }
        case "preview":
          for item in History.shared.all {
            autoreleasepool {
              _ = item.application
              _ = item.text
              item.sizeImages()
              item.cleanupImages()
            }
          }
        case "browse":
          // Keep six rows mounted, as a list does while moving between previews.
          // Closing the popup must release these caches without a row disappearing.
          for item in History.shared.all.filter({ $0.title.contains("image") }).prefix(6) {
            item.ensureThumbnailImage()
            item.ensurePreviewImage()
          }
          try await Task.sleep(nanoseconds: 1_000_000_000)
          AppState.shared.popup.close()
          NSLog("[MaccyLifecycle] CLOSED previews=%d thumbnails=%d",
                History.shared.all.filter({ $0.previewImage != nil }).count,
                History.shared.all.filter({ $0.thumbnailImage != nil }).count)
        case "copy":
          let board = NSPasteboard(name: .init("org.yyyzl.MaccyMemoryLifecycle.\(UUID().uuidString)"))
          defer { board.releaseGlobally() }
          let clipboard = Clipboard(pasteboard: board, notifyOnCopy: false)
          for decorator in History.shared.all.prefix(40) {
            try autoreleasepool {
              clipboard.copy(decorator.item)
              let context = ModelContext(Storage.shared.container)
              guard let stored = context.model(for: decorator.item.persistentModelID) as? HistoryItem else {
                throw LifecycleError.originalMismatch
              }
              for content in stored.contents {
                guard board.data(forType: .init(content.type)) == content.value else {
                  throw LifecycleError.originalMismatch
                }
              }
            }
          }
        case "long":
          NSLog("[MaccyLifecycle] BEGIN long");
          try await Task.sleep(nanoseconds: 20_000_000_000)
          for cycle in 1...60 {
            autoreleasepool {
              Clipboard.shared.changeCount += 1
              History.shared.add(text(1_000 + cycle))
              if cycle % 3 == 0 {
                Clipboard.shared.changeCount += 1
                History.shared.add(image(1_000 + cycle))
              }
              if cycle % 5 == 0 {
                Clipboard.shared.changeCount += 1
                History.shared.add(image(0))
              }
            }
            let images = History.shared.all.filter({ $0.title.contains("image") })
            guard !images.isEmpty else { throw LifecycleError.invalidFixture }
            let item = images[(cycle - 1) % min(6, images.count)]
            History.shared.selectedItem = item
            _ = item.application
            _ = item.text
            item.ensureThumbnailImage()
            item.ensurePreviewImage()
            try await Task.sleep(nanoseconds: 300_000_000)
            try autoreleasepool {
              let board = NSPasteboard(name: .init("org.yyyzl.MaccyMemoryLifecycle.\(UUID().uuidString)"))
              defer { board.releaseGlobally() }
              Clipboard(pasteboard: board, notifyOnCopy: false).copy(item.item)
              let context = ModelContext(Storage.shared.container)
              guard let stored = context.model(for: item.item.persistentModelID) as? HistoryItem else {
                throw LifecycleError.originalMismatch
              }
              for content in stored.contents {
                guard board.data(forType: .init(content.type)) == content.value else {
                  throw LifecycleError.originalMismatch
                }
              }
            }
            AppState.shared.popup.close()
            try Storage.shared.context.save()
            guard History.shared.all.count == 201,
              History.shared.pinnedItems.count == 1,
              History.shared.pinnedItems.first?.item.pin == "p"
            else { throw LifecycleError.invalidFixture }
            NSLog("[MaccyLifecycle] CYCLE_READY cycle=%d previews=%d thumbnails=%d", cycle,
                  History.shared.all.filter({ $0.previewImage != nil }).count,
                  History.shared.all.filter({ $0.thumbnailImage != nil }).count)
            try await Task.sleep(nanoseconds: 15_000_000_000)
          }
        default: break
        }
        try Storage.shared.context.save()
        NSLog("[MaccyLifecycle] READY scenario=%@ items=%d", scenario, History.shared.all.count)
      } catch {
        NSLog("[MaccyLifecycle] FAIL %@", String(describing: error)); exit(2)
      }
    }
  }

  private static func text(_ index: Int) -> HistoryItem {
    let item = HistoryItem(contents: [HistoryItemContent(type: "public.utf8-plain-text", value: Data("Lifecycle text \(index)".utf8))])
    item.title = "Lifecycle synthetic text \(index)"
    return item
  }

  private static func image(_ index: Int) -> HistoryItem {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1280,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    var state = UInt64(index + 1)
    let pixels = bitmap.bitmapData!
    for offset in stride(from: 0, to: bitmap.bytesPerRow * bitmap.pixelsHigh, by: 4) {
      state ^= state << 13; state ^= state >> 7; state ^= state << 17
      pixels[offset] = UInt8(truncatingIfNeeded: state)
      pixels[offset + 1] = UInt8(truncatingIfNeeded: state >> 8)
      pixels[offset + 2] = UInt8(truncatingIfNeeded: state >> 16)
      pixels[offset + 3] = 255
    }
    var contents = [HistoryItemContent(type: "public.tiff", value: bitmap.representation(using: .tiff, properties: [:])!)]
    if index == 0 { contents.append(HistoryItemContent(type: "public.png", value: bitmap.representation(using: .png, properties: [:])!)) }
    let item = HistoryItem(contents: contents)
    item.title = "Lifecycle synthetic image \(index)"
    if index == 0 { item.pin = "p" }
    return item
  }

  private enum LifecycleError: Error {
    case invalidFixture
    case originalMismatch
  }
}
#endif
#endif
