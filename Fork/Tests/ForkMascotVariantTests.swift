// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import CoreGraphics
import Foundation

/// More styles for the companion: which variant applies, silhouettes that
/// stay in its square, the pixel grid, and the cat's parts.
enum ForkMascotVariantTests {
    typealias Logic = ForkMascotVariantLogic

    private static func inside(_ rect: CGRect, _ s: CGFloat, margin: CGFloat = 0.001) -> Bool {
        rect.minX >= -margin && rect.minY >= -margin && rect.maxX <= s + margin && rect.maxY <= s + margin
    }

    static func run(_ suite: TestSuite) {
        suite.expect(Logic.variant("cat") == .cat && Logic.variant("") == .classic && Logic.variant(nil) == .classic
            && Logic.variant("unicorn") == .classic && Logic.Variant.allCases.allSatisfy { Logic.variant($0.rawValue) == $0 },
                     "a stored variant reads back; anything else is the classic one")
        suite.expect(Logic.effective(.ghost, minimal: true) == .ghost && Logic.effective(.ghost, minimal: false) == .classic,
                     "only the minimal style takes a variant")
        suite.expect(Logic.Variant.cat.keepsShape && Logic.Variant.pixel.keepsShape && Logic.Variant.classic.keepsShape
            && !Logic.Variant.ghost.keepsShape && !Logic.Variant.blob.keepsShape,
                     "the cat and the pixel one keep the chosen shape; the ghost and the blob have their own")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.forkMascotVariant] as? String == Logic.Variant.classic.rawValue,
                     "the classic companion by default")

        for s: CGFloat in [12, 20, 30] {
            let ghost = Logic.ghostBody(size: s), blob = Logic.blobBody(size: s)
            suite.expect(inside(ghost.boundingBoxOfPath, s) && inside(blob.boundingBoxOfPath, s)
                && ghost.contains(CGPoint(x: s / 2, y: s / 2)) && blob.contains(CGPoint(x: s / 2, y: s / 2))
                && !ghost.contains(CGPoint(x: s * 0.5, y: s * 0.99)),
                         "the ghost and the blob stay in their square around their middle (size \(Int(s)))")
        }

        let s: CGFloat = 20
        let ball = CGPath(ellipseIn: CGRect(x: 0.08 * s, y: 0.12 * s, width: 0.84 * s, height: 0.84 * s), transform: nil)
        let pixels = Logic.pixelated(ball, size: s)
        let cell = s / CGFloat(Logic.pixelsAcross)
        let box = pixels.boundingBoxOfPath
        suite.expect(!pixels.isEmpty && inside(box, s)
            && abs(box.minX / cell - (box.minX / cell).rounded()) < 0.001 && abs(box.width / cell - (box.width / cell).rounded()) < 0.001
            && pixels.contains(CGPoint(x: s / 2, y: s / 2)) && !pixels.contains(CGPoint(x: 0.3, y: 0.3)),
                     "the pixel one is whole cells of a 12 by 12 grid inside the shape")
        suite.expect(Logic.pixelated(ball, size: 0).isEmpty && Logic.pixelated(ball, size: s, pixels: 0).isEmpty,
                     "no grid, no pixels")
        suite.expect(abs(Logic.rasterScale(size: 20) - 0.6) < 0.0001 && abs(Logic.rasterScale(size: 30) - 0.4) < 0.0001
            && Logic.rasterScale(size: 0) == 1,
                     "drawn at 12 pixels across, whatever its size")

        let top: CGFloat = 0.12
        let left = Logic.ear(left: true, top: top, size: s).boundingBoxOfPath
        let right = Logic.ear(left: false, top: top, size: s).boundingBoxOfPath
        suite.expect(left.minY < top * s && left.maxX <= s / 2 && right.minX >= s / 2
            && abs(left.minX - (s - right.maxX)) < 0.001
            && left.contains(Logic.ear(left: true, top: top, size: s, inner: true).boundingBoxOfPath),
                     "the ears stand above the head, one each side, the inner within the outer")
        let raised = Logic.tail(outward: -1, curled: false, size: s).boundingBoxOfPath
        let curled = Logic.tail(outward: 1, curled: true, size: s).boundingBoxOfPath
        suite.expect(raised.maxX <= s / 2 && raised.minY < s * 0.5 && curled.minY >= s * 0.8,
                     "the tail rises on the side away from the camera, and wraps round its feet asleep")
        suite.expect(inside(Logic.whiskers(eyeY: 0.5, size: s).boundingBoxOfPath, s)
            && abs(Logic.nose(eyeY: 0.5, size: s).boundingBoxOfPath.midX - s / 2) < 0.001,
                     "the whiskers stay beside the face, the nose in its middle")
        suite.expect(Logic.blobWobble.first == 0 && Logic.blobWobble.last == 0 && Logic.blobSplat.first == 0
            && Logic.blobSplat.last == 0 && (Logic.blobSplat.map(abs).max() ?? 0) > (Logic.blobWobble.map(abs).max() ?? 1),
                     "the blob's wobbles end where they start, the jump's stronger than at rest")
    }
}
