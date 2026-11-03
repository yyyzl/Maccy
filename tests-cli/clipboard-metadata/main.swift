import Foundation

extension HistoryRecord {
  convenience init(application: String?, isRemote: Bool) {
    self.init(title: "synthetic")
    self.application = application
    self.fallbackRemote = isRemote
  }
}

final class ApplicationImage {
  let bundleIdentifier: String?
  init(bundleIdentifier: String?) { self.bundleIdentifier = bundleIdentifier }
}

func require(_ value: @autoclosure () -> Bool, _ message: String) {
  if !value() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

let normal = HistoryItem(application: "com.example.synthetic", isRemote: false)
#if BASELINE
let normalImage = ApplicationImageCache.shared.getImage(item: normal)
#else
let normalImage = ApplicationImageCache.shared.getImage(item: normal, universalClipboardHint: false)
#endif
require(normalImage.bundleIdentifier == "com.example.synthetic", "normal source app changed")
require(normal.clipboardReads == 0, "known local item traversed its contents")

#if !BASELINE
let remote = HistoryItem(application: "com.example.synthetic", isRemote: true)
let remoteImage = ApplicationImageCache.shared.getImage(item: remote, universalClipboardHint: true)
require(remoteImage.bundleIdentifier == "com.apple.finder.Open-iCloudDrive", "remote item lost its iCloud icon")
require(remote.clipboardReads == 0, "known remote item traversed its contents")
let fallback = HistoryItem(application: nil, isRemote: true)
let fallbackImage = ApplicationImageCache.shared.getImage(item: fallback, universalClipboardHint: nil)
require(fallbackImage.bundleIdentifier == "com.apple.finder.Open-iCloudDrive", "unknown status failed to fall back")
require(fallback.clipboardReads == 1, "unknown status skipped original lookup")

var hints = UniversalClipboardHints<Int>()
require(hints.hint(for: 1) == false, "absent marker must be local")
hints.add(itemID: 2, valueExists: true)
require(hints.hint(for: 2) == true, "non-nil marker must be remote")
hints.add(itemID: 3, valueExists: false)
require(hints.hint(for: 3) == false, "nil marker must be local")
hints.add(itemID: 3, valueExists: true)
require(hints.hint(for: 3) == nil, "duplicate markers must fall back to original logic")
#endif
print("PASS: metadata hints avoid content traversal and preserve remote and fallback behavior")
