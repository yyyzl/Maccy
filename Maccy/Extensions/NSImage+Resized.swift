import AppKit.NSImage

// Based on https://stackoverflow.com/questions/73062803/resizing-nsimage-keeping-aspect-ratio-reducing-the-image-size-while-trying-to-sc.
extension NSImage {
  func resized(to newSize: NSSize) -> NSImage {
    let ratioX = newSize.width / size.width
    let ratioY = newSize.height / size.height
    let ratio = ratioX < ratioY ? ratioX : ratioY
    let newHeight = size.height * ratio
    let newWidth = size.width * ratio
    let newSize = NSSize(width: newWidth, height: newHeight)

    // Don't attempt to size up.
    if newSize.height >= size.height {
      return self
    }

    // Draw into a standalone bitmap: a drawing handler would retain the original image.
    guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
    let scale = min(NSScreen.main?.backingScaleFactor ?? 2,
                    CGFloat(source.width) / newSize.width, CGFloat(source.height) / newSize.height)
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: min(source.width, max(1, Int(ceil(newSize.width * scale)))),
      pixelsHigh: min(source.height, max(1, Int(ceil(newSize.height * scale)))),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      return self
    }

    let cgContext = context.cgContext
    cgContext.interpolationQuality = .high
    cgContext.draw(source, in: CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    bitmap.size = newSize

    let image = NSImage(size: newSize)
    image.addRepresentation(bitmap)
    return image
  }
}
