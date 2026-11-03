import AppKit

setbuf(stdout, nil)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

func makeImage(width: Int, height: Int) -> NSImage {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
  )!
  let bytes = bitmap.bitmapData!
  for y in 0..<height {
    for x in 0..<width {
      let index = y * bitmap.bytesPerRow + x * 4
      bytes[index] = x < width / 2 && y < height / 2 ? 255 : 0
      bytes[index + 1] = x >= width / 2 && y < height / 2 ? 255 : 0
      bytes[index + 2] = x < width / 2 && y >= height / 2 ? 255 : 0
      bytes[index + 3] = x >= width / 2 && y >= height / 2 ? 0 : 255
    }
  }
  let image = NSImage(size: NSSize(width: width, height: height))
  image.addRepresentation(bitmap)
  return image
}

weak var original: NSImage?
var thumbnail: NSImage?
autoreleasepool {
  let image = makeImage(width: 800, height: 400)
  original = image
  thumbnail = image.resized(to: NSSize(width: 340, height: 200))
}
require(thumbnail != nil, "thumbnail was not generated")
require(original == nil, "thumbnail retains the full-sized source image")
require(thumbnail!.size == NSSize(width: 340, height: 170), "aspect ratio or size changed")

let bitmap = NSBitmapImageRep(data: thumbnail!.tiffRepresentation!)!
func pixel(_ x: Double, _ y: Double) -> NSColor {
  return bitmap.colorAt(
    x: Int(Double(bitmap.pixelsWide) * x),
    y: Int(Double(bitmap.pixelsHigh) * y)
  )!.usingColorSpace(.deviceRGB)!
}
let red = pixel(0.25, 0.25)
let green = pixel(0.75, 0.25)
let blue = pixel(0.25, 0.75)
let clear = pixel(0.75, 0.75)
require(red.redComponent > 0.8 && red.greenComponent < 0.4 && red.blueComponent < 0.2, "red quadrant changed")
require(green.greenComponent > 0.6 && green.redComponent < 0.2 && green.blueComponent < 0.2, "green quadrant changed")
require(blue.blueComponent > 0.8 && blue.redComponent < 0.2 && blue.greenComponent < 0.4, "blue quadrant changed")
require(clear.alphaComponent < 0.1, "transparent quadrant changed")

autoreleasepool {
  let small = makeImage(width: 100, height: 50)
  require(small.resized(to: NSSize(width: 340, height: 200)) === small, "small image was enlarged")
}
if CommandLine.arguments.count > 1 {
  weak var jpegSource: NSImage?
  var jpegThumbnail: NSImage?
  autoreleasepool {
    let jpeg = NSImage(contentsOfFile: CommandLine.arguments[1])!
    jpegSource = jpeg
    jpegThumbnail = jpeg.resized(to: NSSize(width: 120, height: 100))
  }
  require(jpegSource == nil, "JPEG thumbnail retains the source image")
  require(jpegThumbnail != nil, "JPEG thumbnail was not generated")
  require(abs(jpegThumbnail!.size.height - 100) < 0.01, "JPEG height changed")
  require(abs(jpegThumbnail!.size.width - 81.875) < 0.01, "JPEG aspect ratio changed")
  require(jpegThumbnail!.tiffRepresentation != nil, "JPEG thumbnail cannot be rendered")
}
print("PASS: thumbnails detach the source, preserve size, color, transparency and JPEG rendering; no upscaling")
