import AppKit

setbuf(stdout, nil)
let mode = CommandLine.arguments.dropFirst().first ?? "unknown"
var thumbnails: [NSImage] = []

for i in 0..<20 {
  autoreleasepool {
    let width = 2048
    let height = 1024
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    memset(bitmap.bitmapData!, Int32(i + 128), bitmap.bytesPerRow * height)
    let original = NSImage(size: NSSize(width: width, height: height))
    original.addRepresentation(bitmap)
    thumbnails.append(original.resized(to: NSSize(width: 340, height: 200)))
  }
}

print("READY \(mode) thumbnails=\(thumbnails.count)")
withExtendedLifetime(thumbnails) { _ = sleep(20) }
