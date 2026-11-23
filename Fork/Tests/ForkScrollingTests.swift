// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// Horizontal scrolling captures, turned to fit upstream's vertical matching.
enum ForkScrollingTests {
    typealias Direction = ForkScrollingDirection

    static func run(_ suite: TestSuite) {
        // A 3×2 picture whose pixels are all different.
        let width = 3, height = 2
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) { pixels[index * 4] = UInt8(index * 40) }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            suite.expect(false, "the test picture is built")
            return
        }
        func red(_ picture: CGImage, _ x: Int, _ yFromTop: Int) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            guard let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            probe.interpolationQuality = .none
            probe.draw(picture, in: CGRect(x: -x, y: yFromTop - picture.height + 1, width: picture.width, height: picture.height))
            return pixel[0]
        }
        guard let turned = Direction.rotated(image, clockwise: true),
              let back = Direction.rotated(turned, clockwise: false) else {
            suite.expect(false, "the picture turns")
            return
        }
        suite.expect(turned.width == height && turned.height == width, "a quarter turn swaps width and height")
        suite.expect(red(turned, height - 1, 0) == red(image, 0, 0) && red(turned, 0, width - 1) == red(image, width - 1, height - 1),
               "clockwise: the top left corner goes to the top right, the bottom right to the bottom left")
        suite.expect(red(turned, height - 1, width - 1) == red(image, width - 1, 0),
               "what scrolls in on the right comes in at the bottom, where upstream expects new content")
        var identical = true
        for x in 0..<width { for y in 0..<height where red(back, x, y) != red(image, x, y) { identical = false } }
        suite.expect(identical && back.width == width, "turned back, the picture is the same pixel for pixel")

        // Armed by the capture menu, decided at the first frame.
        let now = Date(timeIntervalSince1970: 9_000)
        Direction.armHorizontal(at: now)
        _ = Direction.first(image, at: now.addingTimeInterval(0.5))
        suite.expect(Direction.isHorizontal, "a capture started just after being armed goes sideways")
        suite.expect(Direction.oriented(image)?.width == height && Direction.restored(turned)?.width == width,
               "its frames are turned, and its picture turned back")
        _ = Direction.first(image, at: now.addingTimeInterval(1))
        suite.expect(!Direction.isHorizontal, "the next capture, not armed, stays vertical")
        suite.expect(Direction.oriented(image) === image, "and its frames pass untouched")
        Direction.armHorizontal(at: now)
        _ = Direction.first(image, at: now.addingTimeInterval(Direction.armLifetime + 1))
        suite.expect(!Direction.isHorizontal, "an arming that no capture followed goes stale")
        Direction.disarm()

        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkScrollingHorizontal] as? Bool == false,
               "scrolling captures are vertical by default")
    }
}
