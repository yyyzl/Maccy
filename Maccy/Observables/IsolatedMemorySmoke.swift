#if DEBUG || MEMORY_LIFECYCLE
import AppKit
import Foundation
import Observation
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
      let cycleCount = Int(args.first(where: { $0.hasPrefix("--cycles=") }).map {
        String($0.dropFirst("--cycles=".count))
      } ?? "60"), [60, 240].contains(cycleCount),
      let scenario = args.first(where: { $0.hasPrefix("--scenario=") })?.split(separator: "=").last.map(String.init),
      ["seed", "idle", "text", "duplicate", "image", "preview", "browse", "visibility", "contracts", "interaction", "copy", "long"].contains(scenario),
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
            item.showPreview = true
            item.ensurePreviewImage()
          }
          try await Task.sleep(nanoseconds: 1_000_000_000)
          AppState.shared.popup.close()
          NSLog("[MaccyLifecycle] CLOSED previews=%d thumbnails=%d",
                History.shared.all.filter({ $0.previewImage != nil }).count,
                History.shared.all.filter({ $0.thumbnailImage != nil }).count)
        case "visibility":
          guard let panel = AppState.shared.appDelegate?.panel else { throw LifecycleError.invalidFixture }
          panel.contentView?.layoutSubtreeIfNeeded()
          try await Task.sleep(nanoseconds: 500_000_000)
          for cycle in 1...3 {
            // Simulate our custom scene phase without showing a window or taking focus.
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 500_000_000)
            guard !panel.isVisible, !panel.isKeyWindow,
              History.shared.all.contains(where: { $0.thumbnailImage != nil }),
              let selection = AppState.shared.selection
            else { throw LifecycleError.invalidFixture }
            AppState.shared.highlightNext()
            guard AppState.shared.selection != selection else { throw LifecycleError.invalidFixture }
            AppState.shared.highlightPrevious()
            guard AppState.shared.selection == selection else { throw LifecycleError.invalidFixture }
            AppState.shared.popup.close()
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
            try await Task.sleep(nanoseconds: 500_000_000)
            guard History.shared.all.allSatisfy({ $0.thumbnailImage == nil && $0.previewImage == nil }) else {
              throw LifecycleError.invalidFixture
            }
            NSLog("[MaccyLifecycle] VISIBILITY_OK cycle=%d simulated_focus=YES", cycle)
          }
        case "contracts":
          @MainActor
          func add(_ item: HistoryItem) -> HistoryItemDecorator {
            Clipboard.shared.changeCount += 1
            return History.shared.add(item)
          }
          let stringType = NSPasteboard.PasteboardType.string.rawValue
          let modifiedType = NSPasteboard.PasteboardType.modified.rawValue
          let plain = Data("Dedup contract original".utf8)
          let first = HistoryItem(contents: [HistoryItemContent(type: stringType, value: plain)])
          first.title = "Contract original title"
          first.application = "synthetic.original"
          first.firstCopiedAt = Date(timeIntervalSince1970: 1000)
          first.numberOfCopies = 4
          let firstDecorator = add(first)
          first.pin = "b"
          guard let pinnedPosition = History.shared.all.firstIndex(where: { $0.id == firstDecorator.id }) else {
            throw LifecycleError.invalidFixture
          }
          let duplicate = add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: plain)]))
          guard duplicate.item.pin == "b", duplicate.item.title == "Contract original title",
            duplicate.item.application == "synthetic.original", duplicate.item.numberOfCopies == 5,
            duplicate.item.firstCopiedAt == Date(timeIntervalSince1970: 1000),
            History.shared.all.firstIndex(where: { $0.id == duplicate.id }) == pinnedPosition
          else { throw LifecycleError.originalMismatch }
          let transient = add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: plain),
            HistoryItemContent(type: modifiedType, value: Data("unmapped".utf8))]))
          guard transient.item.numberOfCopies == 6, transient.item.pin == "b",
            transient.item.contents.count == 1, transient.item.contents.first?.value == plain
          else { throw LifecycleError.originalMismatch }

          let richText = Data("Dedup contract rich".utf8)
          let html = Data("<b>Dedup contract rich</b>".utf8)
          add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: richText),
            HistoryItemContent(type: NSPasteboard.PasteboardType.html.rawValue, value: html)]))
          let superseded = add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: richText)]))
          guard superseded.item.contents.count == 2,
            superseded.item.contents.contains(where: { $0.type == NSPasteboard.PasteboardType.html.rawValue && $0.value == html })
          else { throw LifecycleError.originalMismatch }

          let original = add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: Data("Modify original".utf8))]))
          let originalDate = original.item.firstCopiedAt
          let originalChange = Clipboard.shared.changeCount
          let edited = Data("Modify edited".utf8)
          let modified = add(HistoryItem(contents: [HistoryItemContent(type: stringType, value: edited),
            HistoryItemContent(type: modifiedType, value: Data(String(originalChange).utf8))]))
          guard modified.item.firstCopiedAt == originalDate, modified.item.numberOfCopies == 2,
            modified.item.contents.contains(where: { $0.type == stringType && $0.value == edited }),
            modified.item.contents.contains(where: { $0.type == modifiedType })
          else { throw LifecycleError.originalMismatch }
          NSLog("[MaccyLifecycle] CONTRACTS_OK pin=YES metadata=YES transient=YES supersedes=YES modified=YES")
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
        case "long", "interaction":
          guard let panel = AppState.shared.appDelegate?.panel else { throw LifecycleError.invalidFixture }
          // 仅远端一次性 CI 桌面显示合成窗口，本机始终保持隐藏。
          let visibleCIWindow = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
          NSLog("[MaccyLifecycle] INTERACTION_MODE visible_ci=%@", visibleCIWindow ? "YES" : "NO")
          if scenario == "interaction" { traceSelection() }
          NSLog("[MaccyLifecycle] BEGIN long");
          try await Task.sleep(nanoseconds: 20_000_000_000)
          var imageIDs = Set(History.shared.all.filter({ $0.title.contains("image") }).map { $0.item.persistentModelID })
          var newImageIDs = Set<PersistentIdentifier>()
          var previewedNewImages = Set<PersistentIdentifier>()
          let operationCount = scenario == "long" ? cycleCount : 12
          for cycle in 1...operationCount {
            var captureMilliseconds = 0.0
            var capturedImageID: PersistentIdentifier?
            autoreleasepool {
              Clipboard.shared.changeCount += 1
              let textStarted = Date.timeIntervalSinceReferenceDate
              History.shared.add(text(1_000 + cycle))
              captureMilliseconds = (Date.timeIntervalSinceReferenceDate - textStarted) * 1000
              if cycle % 3 == 0 {
                Clipboard.shared.changeCount += 1
                let captured = image(1_000 + cycle)
                captured.title = captured.generateTitle()
                let added = History.shared.add(captured)
                imageIDs.insert(added.item.persistentModelID)
                newImageIDs.insert(added.item.persistentModelID)
                if scenario == "interaction" { capturedImageID = added.item.persistentModelID }
              }
              if cycle % 5 == 0 {
                Clipboard.shared.changeCount += 1
                let captured = image(0)
                captured.title = captured.generateTitle()
                let added = History.shared.add(captured)
                imageIDs.insert(added.item.persistentModelID)
              }
            }
            let displayedIDs = Set(History.shared.items.map(\.id))
            let images = History.shared.all.filter {
              displayedIDs.contains($0.id) && imageIDs.contains($0.item.persistentModelID)
            }
            guard !images.isEmpty else {
              NSLog("[MaccyLifecycle] STAGE_FAIL no_images cycle=%d", cycle)
              throw LifecycleError.invalidFixture
            }
            let item = capturedImageID.flatMap { id in images.first { $0.item.persistentModelID == id } } ??
              images[(cycle - 1) % min(6, images.count)]
            let initialSelection = History.shared.unpinnedItems.first?.id ?? History.shared.pinnedItems.first?.id
            if visibleCIWindow {
              AppState.shared.popup.open(height: 600, at: .center)
            } else {
              NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: panel)
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            // 等待列表的激活回调完成，避免它随后覆盖本次明确选择。
            for _ in 0..<200 where History.shared.selectedItem?.id != initialSelection {
              try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard initialSelection != nil, History.shared.selectedItem?.id == initialSelection else {
              NSLog("[MaccyLifecycle] STAGE_FAIL activation_selection cycle=%d", cycle)
              throw LifecycleError.invalidFixture
            }
            // 搜索框初始化会再排一个 0.2 秒回调，先让它完成再模拟用户选图。
            try await Task.sleep(nanoseconds: 500_000_000)
            guard panel.isVisible == visibleCIWindow, panel.isKeyWindow == visibleCIWindow else {
              NSLog("[MaccyLifecycle] STAGE_FAIL window_state cycle=%d visible=%d key=%d", cycle,
                    panel.isVisible ? 1 : 0, panel.isKeyWindow ? 1 : 0)
              throw LifecycleError.invalidFixture
            }
            AppState.shared.selection = item.id
            guard item.isSelected else {
              NSLog("[MaccyLifecycle] STAGE_FAIL target_selection cycle=%d", cycle)
              throw LifecycleError.invalidFixture
            }
            _ = item.application
            _ = item.text
            item.ensureThumbnailImage()
            if visibleCIWindow {
              // 等待应用默认的 1500 ms 预览调度，避免滚动途中强制呈现后被关闭。
              for _ in 0..<300 where !item.showPreview {
                try await Task.sleep(nanoseconds: 10_000_000)
              }
              guard item.isSelected, item.showPreview else {
                NSLog("[MaccyLifecycle] STAGE_FAIL automatic_preview cycle=%d selected=%d show=%d", cycle,
                      item.isSelected ? 1 : 0, item.showPreview ? 1 : 0)
                throw LifecycleError.invalidFixture
              }
            } else {
              item.showPreview = true
            }
            item.ensurePreviewImage()
            for _ in 0..<100 where item.thumbnailImage == nil || item.previewImage == nil {
              try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard item.isSelected, item.showPreview, item.thumbnailImage != nil, item.previewImage != nil else {
              NSLog("[MaccyLifecycle] STAGE_FAIL image_ready cycle=%d thumbnail=%d preview=%d selected=%d show=%d thumbnail_task=%d preview_task=%d deleted=%d", cycle,
                    item.thumbnailImage != nil ? 1 : 0, item.previewImage != nil ? 1 : 0,
                    item.isSelected ? 1 : 0, item.showPreview ? 1 : 0,
                    item.thumbnailImageGenerationTask != nil ? 1 : 0,
                    item.previewImageGenerationTask != nil ? 1 : 0, item.item.isDeleted ? 1 : 0)
              NSLog("[MaccyLifecycle] STAGE_DETAIL window_visible=%d window_key=%d global_selected=%d selection_matches=%d", panel.isVisible ? 1 : 0,
                    panel.isKeyWindow ? 1 : 0, History.shared.selectedItem != nil ? 1 : 0,
                    AppState.shared.selection == item.id ? 1 : 0)
              let readContext = ModelContext(Storage.shared.container)
              if let stored = readContext.model(for: item.item.persistentModelID) as? HistoryItem {
                let formats = stored.contents.map { "\($0.type):\($0.value?.count ?? -1)" }.joined(separator: ",")
                NSLog("[MaccyLifecycle] STAGE_DETAIL synthetic_formats=%@", formats)
              }
              throw LifecycleError.invalidFixture
            }
            if newImageIDs.contains(item.item.persistentModelID) {
              previewedNewImages.insert(item.item.persistentModelID)
            }
            try autoreleasepool {
              let board = NSPasteboard(name: .init("org.yyyzl.MaccyMemoryLifecycle.\(UUID().uuidString)"))
              defer { board.releaseGlobally() }
              Clipboard(pasteboard: board, notifyOnCopy: false).copy(item.item)
              let context = ModelContext(Storage.shared.container)
              guard let stored = context.model(for: item.item.persistentModelID) as? HistoryItem else {
                throw LifecycleError.originalMismatch
              }
              let expectedTypes: Set<String> = item.isPinned ?
                [NSPasteboard.PasteboardType.tiff.rawValue, NSPasteboard.PasteboardType.png.rawValue] :
                [NSPasteboard.PasteboardType.tiff.rawValue]
              guard Set(stored.contents.map(\.type)) == expectedTypes,
                stored.contents.allSatisfy({ $0.value != nil })
              else { throw LifecycleError.originalMismatch }
              for content in stored.contents {
                guard board.data(forType: .init(content.type)) == content.value else {
                  throw LifecycleError.originalMismatch
                }
              }
            }
            AppState.shared.popup.close()
            if !visibleCIWindow {
              NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            try Storage.shared.context.save()
            // Existing pinned deduplication can temporarily leave 199 unpinned items.
            guard (200...201).contains(History.shared.all.count),
              History.shared.pinnedItems.count == 1,
              History.shared.pinnedItems.first?.item.pin == "p"
            else {
              NSLog("[MaccyLifecycle] STAGE_FAIL item_counts cycle=%d items=%d pins=%d", cycle,
                    History.shared.all.count, History.shared.pinnedItems.count)
              throw LifecycleError.invalidFixture
            }
            NSLog("[MaccyLifecycle] CYCLE_READY cycle=%d previews=%d thumbnails=%d text_capture_ms=%.1f", cycle,
                  History.shared.all.filter({ $0.previewImage != nil }).count,
                  History.shared.all.filter({ $0.thumbnailImage != nil }).count, captureMilliseconds)
            try await Task.sleep(nanoseconds: scenario == "long" ? 15_000_000_000 : 500_000_000)
          }
          guard previewedNewImages.count >= (scenario == "long" ? 10 : 4) else {
            NSLog("[MaccyLifecycle] STAGE_FAIL new_image_coverage count=%d", previewedNewImages.count)
            throw LifecycleError.invalidFixture
          }
          NSLog("[MaccyLifecycle] NEW_IMAGES_PREVIEWED count=%d", previewedNewImages.count)
          if scenario == "interaction" {
            NSLog("[MaccyLifecycle] INTERACTION_OK cycles=%d selected=YES formats=YES", operationCount)
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

  @MainActor
  private static func traceSelection() {
    _ = withObservationTracking {
      _ = AppState.shared.selection
      _ = History.shared.selectedItem
    } onChange: {
      NSLog("[MaccyLifecycle] SELECTION_CHANGED stack=%@", Thread.callStackSymbols.joined(separator: " | "))
      DispatchQueue.main.async { traceSelection() }
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
