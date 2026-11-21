// Trims the empty rows below a screenshot's content, in place: the status strip snapshots are rendered
// taller than their text. Usage: swift scripts/trim-bottom.swift <png>...
//
// "Empty" means the same color as the bottom-left pixel (the background), within a small tolerance.
// Keeps `padding` pixels of background below the last row with content.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let padding = 24 // pixels: 12 points at 2x
let tolerance = 6 // per channel, 0–255

func trim(_ path: String) throws {
  let url = URL(fileURLWithPath: path)
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else { throw NSError(domain: "trim", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't read \(path)"]) }

  let width = image.width, height = image.height
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  let space = CGColorSpaceCreateDeviceRGB()
  guard let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else { throw NSError(domain: "trim", code: 2, userInfo: [NSLocalizedDescriptionKey: "no context"]) }
  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

  // Row 0 of the buffer is the top of the image.
  func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
    pixels[(y * width + x) * 4 ..< (y * width + x) * 4 + 4]
  }
  let background = Array(pixel(0, height - 1))
  func isBackground(_ x: Int, _ y: Int) -> Bool {
    zip(pixel(x, y), background).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
  }

  var lastContentRow = -1
  for y in stride(from: height - 1, through: 0, by: -1) where (0 ..< width).contains(where: { !isBackground($0, y) }) {
    lastContentRow = y
    break
  }
  let newHeight = min(height, lastContentRow + 1 + padding)
  guard lastContentRow >= 0, newHeight < height else {
    print("\(path): nothing to trim")
    return
  }

  guard let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: newHeight)),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw NSError(domain: "trim", code: 3, userInfo: [NSLocalizedDescriptionKey: "can't crop \(path)"]) }
  CGImageDestinationAddImage(destination, cropped, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw NSError(domain: "trim", code: 4, userInfo: [NSLocalizedDescriptionKey: "can't write \(path)"])
  }
  print("\(path): \(height) → \(newHeight) px")
}

for path in CommandLine.arguments.dropFirst() {
  do {
    try trim(path)
  } catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
  }
}
