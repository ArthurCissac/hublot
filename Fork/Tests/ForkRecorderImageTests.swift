// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A picture laid over a recording, placed and resized by hand.
enum ForkRecorderImageTests {
    typealias Placement = ForkRecorderImagePlacement

    /// Fitting a frame to the stage divides and multiplies back: equal to within a hair.
    private static func near(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 0.01 && abs(first.minY - second.minY) < 0.01
            && abs(first.width - second.width) < 0.01 && abs(first.height - second.height) < 0.01
    }

    static func run(_ suite: TestSuite) {
        let canvas = CGSize(width: 1920, height: 1080)
        let drawn = CGSize(width: 400, height: 200)
        var overlay = RecorderImageOverlay(path: "/tmp/logo.png", start: 0, end: 5, anchor: .bottomTrailing)

        // Never dragged: exactly where upstream puts it.
        for anchor in RecorderImageOverlay.Anchor.allCases {
            overlay.anchor = anchor
            suite.expect(Placement.origin(of: overlay, drawn: drawn, in: canvas) == anchor.origin(of: drawn, in: canvas),
                   "a picture never dragged stays at its \(anchor.rawValue) place")
        }

        // Dragged: its center decides, counted from the top left.
        overlay.forkCenter = CGPoint(x: 0.5, y: 0.5)
        suite.expect(Placement.origin(of: overlay, drawn: drawn, in: canvas) == CGPoint(x: 760, y: 440),
               "a picture dragged to the middle is centered on the frame")
        overlay.forkCenter = CGPoint(x: 0.25, y: 0.25)
        suite.expect(Placement.origin(of: overlay, drawn: drawn, in: canvas) == CGPoint(x: 280, y: 710),
               "a center in the upper left quarter is drawn there: Core Image counts up from the bottom")
        overlay.forkCenter = CGPoint(x: 4, y: -2)
        suite.expect(Placement.origin(of: overlay, drawn: drawn, in: canvas) == CGPoint(x: 1720, y: 980),
               "a center outside the frame is brought back to its edge")
        overlay.forkCenter = CGPoint(x: CGFloat.nan, y: 0.2)
        suite.expect(Placement.center(of: overlay, drawn: drawn, in: canvas) == CGPoint(x: 0.5, y: 0.5),
               "a center that is no point at all means the middle")

        // A drag starts where the picture is, anchored or not.
        overlay.forkCenter = nil
        overlay.anchor = .center
        suite.expect(Placement.center(of: overlay, drawn: drawn, in: canvas) == CGPoint(x: 0.5, y: 0.5),
               "the center anchor is the middle of the frame")
        overlay.anchor = .bottomTrailing
        let start = Placement.center(of: overlay, drawn: drawn, in: canvas)
        overlay.forkCenter = start
        let pinned = Placement.origin(of: overlay, drawn: drawn, in: canvas)
        let anchored = RecorderImageOverlay.Anchor.bottomTrailing.origin(of: drawn, in: canvas)
        suite.expect(abs(pinned.x - anchored.x) <= 1 && abs(pinned.y - anchored.y) <= 1,
               "taking hold of an anchored picture does not make it jump")

        // The stage shows the frame fitted and centered.
        let stage = CGSize(width: 1000, height: 800)
        let shown = Placement.shownRect(canvas: canvas, in: stage)
        suite.expect(shown.map { near($0, CGRect(x: 0, y: 118.75, width: 1000, height: 562.5)) } == true,
               "a wide frame fills the stage's width and is centered in its height")
        suite.expect(Placement.shownRect(canvas: CGSize(width: 1080, height: 1920), in: stage)?.height == 800,
               "a tall frame fills the stage's height")
        suite.expect(Placement.shownRect(canvas: .zero, in: stage) == nil, "no frame, nothing shown")

        overlay.forkCenter = CGPoint(x: 0.5, y: 0.5)
        overlay.size = 0.25
        let source = CGSize(width: 800, height: 400)
        let frame = Placement.frame(of: overlay, source: source, canvas: canvas, stage: stage)
        suite.expect(frame.map { near($0, CGRect(x: 375, y: 337.5, width: 250, height: 125)) } == true,
               "on the stage the picture is where the export will draw it, at the stage's scale")

        // Moving.
        let moved = Placement.moved(CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 100, height: -56.25),
                                    shown: CGSize(width: 1000, height: 562.5))
        suite.expect(abs(moved.x - 0.6) < 0.0001 && abs(moved.y - 0.4) < 0.0001,
               "a drag moves the center by as much, in the frame's own proportions")
        suite.expect(Placement.moved(CGPoint(x: 0.9, y: 0.1), by: CGSize(width: 900, height: -900),
                                     shown: CGSize(width: 1000, height: 562.5)) == CGPoint(x: 1, y: 0),
               "a drag past the frame stops at its edge")

        // Resizing.
        suite.expect(abs(Placement.resized(0.2, from: 100, to: 150, source: source, canvas: canvas) - 0.3) < 0.0001,
               "pulling a corner half as far again makes the picture half as large again")
        suite.expect(Placement.resized(0.2, from: 100, to: 1, source: source, canvas: canvas)
            == RecorderImageOverlay.sizeRange.lowerBound,
               "a picture never shrinks below upstream's smallest size")
        suite.expect(RecorderImageOverlay.sizeRange.upperBound == Placement.largestSize && Placement.largestSize == 1,
               "a picture may now be asked to be as wide as the frame")
        suite.expect(abs(Placement.largestUsefulSize(source: source, canvas: canvas) - (1920 - 108) / 1920) < 0.0001,
               "a wide picture grows until it touches the frame's side margins")
        let tall = CGSize(width: 400, height: 800)
        suite.expect(abs(Placement.largestUsefulSize(source: tall, canvas: canvas) - (1080 - 108) * 0.5 / 1920) < 0.0001,
               "a tall picture grows until it touches the top and bottom margins")
        suite.expect(Placement.resized(0.2, from: 100, to: 5_000, source: tall, canvas: canvas)
            == Placement.largestUsefulSize(source: tall, canvas: canvas),
               "a corner pulled far away stops where the picture stops growing")
        suite.expect(Placement.resized(0.2, from: 0.5, to: 300, source: source, canvas: canvas) == 0.2,
               "a drag that began on the center itself changes nothing")

        // The center travels with the edit, and an edit without one reads as before.
        overlay.forkCenter = CGPoint(x: 0.3, y: 0.7)
        let data = try? JSONEncoder().encode(overlay)
        let back = data.flatMap { try? JSONDecoder().decode(RecorderImageOverlay.self, from: $0) }
        suite.expect(back == overlay, "a hand-placed picture is saved and read back with its center")
        let legacy = Data(#"{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","path":"/tmp/logo.png","start":0,"end":5,"anchor":"top","size":0.18,"opacity":1}"#.utf8)
        let old = try? JSONDecoder().decode(RecorderImageOverlay.self, from: legacy)
        suite.expect(old != nil && old?.forkCenter == nil && old?.anchor == .top,
               "an edit saved before free placement still opens, at its anchor")
        suite.expect(overlay.sanitized(duration: 10)?.forkCenter == CGPoint(x: 0.3, y: 0.7),
               "checking an edit keeps the hand-placed center")

        // A picture being edited is shown whole on the stage.
        let timed = RecorderImageOverlay(path: "/tmp/logo.png", start: 2, end: 8)
        let fade = RecorderImageOverlay.fade
        suite.expect(Placement.visibleMoment(of: timed, at: 2) == 2 + fade,
               "a picture added at the playhead is not drawn there yet: the playhead moves to where it is whole")
        suite.expect(Placement.visibleMoment(of: timed, at: 5) == nil, "a picture already shown whole leaves the playhead alone")
        suite.expect(Placement.visibleMoment(of: timed, at: 0.5) == 2 + fade
            && Placement.visibleMoment(of: timed, at: 9) == 8 - fade,
               "a playhead before or after the picture moves to its nearest whole moment")
        let brief = RecorderImageOverlay(path: "/tmp/logo.png", start: 1, end: 1.3)
        suite.expect(Placement.visibleMoment(of: brief, at: 1) == 1.15 && Placement.visibleMoment(of: brief, at: 1.15) == nil,
               "a picture too short to be whole is seen in its middle")

        turns(suite)
        rendersThePicture(suite)
        exportsThePicture(suite)
    }

    // MARK: - Mirror and rotation

    private static func turns(_ suite: TestSuite) {
        typealias Turn = ForkRecorderImageTurn
        suite.expect(Turn.normalized(370) == 10 && Turn.normalized(-90) == 270 && Turn.normalized(720) == 0
            && Turn.normalized(.nan) == 0,
               "an angle is always read between 0 and 360 degrees")
        suite.expect(Turn().isIdentity && Turn(mirrored: false, degrees: 360).isIdentity
            && !Turn(mirrored: true).isIdentity && !Turn(degrees: 10).isIdentity,
               "only an unmirrored picture at a full turn is drawn as upstream draws it")

        let center = CGPoint(x: 100, y: 100)
        suite.expect(Turn.degrees(handleAt: CGPoint(x: 100, y: 40), center: center) == 0,
               "the rotation handle straight above the picture means upright")
        suite.expect(abs(Turn.degrees(handleAt: CGPoint(x: 160, y: 100), center: center) - 90) < 0.0001
            && abs(Turn.degrees(handleAt: CGPoint(x: 100, y: 160), center: center) - 180) < 0.0001
            && abs(Turn.degrees(handleAt: CGPoint(x: 40, y: 100), center: center) - 270) < 0.0001,
               "dragging the handle round to the right, down and left turns the picture clockwise")
        suite.expect(Turn.degrees(handleAt: center, center: center) == 0, "a handle on the center itself asks for nothing")

        suite.expect(Turn.snapped(93, fine: false) == 90 && Turn.snapped(358, fine: false) == 0
            && Turn.snapped(37, fine: false) == 37,
               "a rotation settles on a quarter turn within five degrees of it, and stays free elsewhere")
        suite.expect(Turn.snapped(37, fine: true) == 30 && Turn.snapped(353, fine: true) == 0,
               "with Shift held it moves by fifteen degrees")

        let size = CGSize(width: 200, height: 100)
        let quarter = Turn.coveredSize(of: size, degrees: 90)
        suite.expect(abs(quarter.width - 100) < 0.001 && abs(quarter.height - 200) < 0.001,
               "a picture turned a quarter covers its height across and its width down")
        let eighth = Turn.coveredSize(of: CGSize(width: 100, height: 100), degrees: 45)
        suite.expect(abs(eighth.width - 141.42) < 0.01, "a square turned by 45 degrees covers its diagonal")

        let origin = CGPoint(x: 50, y: 30)
        suite.expect(Turn.transform(nil, size: size, origin: origin) == CGAffineTransform(translationX: 50, y: 30)
            && Turn.transform(Turn(), size: size, origin: origin) == CGAffineTransform(translationX: 50, y: 30),
               "an unturned picture is only moved into place, exactly as upstream does")
        func mapped(_ point: CGPoint, _ turn: Turn) -> CGPoint { point.applying(Turn.transform(turn, size: size, origin: origin)) }
        let middle = CGPoint(x: 100, y: 50)
        let turnedMiddle = mapped(middle, Turn(mirrored: true, degrees: 37))
        suite.expect(abs(turnedMiddle.x - 150) < 0.001 && abs(turnedMiddle.y - 80) < 0.001,
               "mirror and rotation keep the picture's center where it was placed")
        let mirroredLeft = mapped(CGPoint(x: 0, y: 50), Turn(mirrored: true))
        suite.expect(abs(mirroredLeft.x - 250) < 0.001 && abs(mirroredLeft.y - 80) < 0.001,
               "a mirrored picture shows its left edge on the right")
        let rightEdge = mapped(CGPoint(x: 200, y: 50), Turn(degrees: 90))
        suite.expect(abs(rightEdge.x - 150) < 0.001 && abs(rightEdge.y - (80 - 100)) < 0.001,
               "a quarter turn clockwise brings the right edge down, as on screen")

        let stage = CGSize(width: 1000, height: 600)
        let bar = CGSize(width: 120, height: 28)
        let topBar = Turn.barOrigin(barSize: bar, pictureCenter: CGPoint(x: 500, y: 300), covered: CGSize(width: 200, height: 100),
                                    stage: stage, clearance: 36)
        suite.expect(topBar == CGPoint(x: 440, y: 186), "the bar sits centered above the picture, clear of its handle")
        let lowBar = Turn.barOrigin(barSize: bar, pictureCenter: CGPoint(x: 20, y: 40), covered: CGSize(width: 200, height: 60),
                                    stage: stage, clearance: 36)
        suite.expect(lowBar.y == 106 && lowBar.x == 4, "without room above, it goes under the picture and stays on the stage")

        var overlay = RecorderImageOverlay(path: "/tmp/logo.png", start: 0, end: 5)
        overlay.forkTurn = Turn(mirrored: true, degrees: 30)
        let data = try? JSONEncoder().encode(overlay)
        suite.expect(data.flatMap { try? JSONDecoder().decode(RecorderImageOverlay.self, from: $0) }?.forkTurn
            == Turn(mirrored: true, degrees: 30),
               "the turn is saved with the edit and read back")
    }

    // MARK: - Drawn for real

    /// The picture is drawn by the same composer as the editor's preview and
    /// the export: a red square on a grey recording, read back pixel by pixel.
    private static func rendersThePicture(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fork-image-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pictureURL = folder.appendingPathComponent("red.png")
        guard writeRedSquare(to: pictureURL) else {
            suite.expect(false, "the red test picture is written")
            return
        }
        let source = CGSize(width: 400, height: 200)
        let recording = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(origin: .zero, size: source))

        func render(_ overlay: RecorderImageOverlay) -> (CGImage, CGSize)? {
            var document = RecorderEditDocument()
            document.showsPointer = false
            document.zoomEnabled = false
            document.images = [overlay]
            guard let plan = RecorderComposer.makePlan(document: document, track: RecorderPointerTrack(),
                                                       sourceSize: source, frameRate: 30, duration: 4)
            else { return nil }
            let composer = RecorderComposer(plan: plan)
            let frame = composer.render(recording, at: 2)
            guard let image = CIContext().createCGImage(frame, from: CGRect(origin: .zero, size: composer.canvasSize))
            else { return nil }
            return (image, composer.canvasSize)
        }

        /// The colour at a point given with a top-left origin, as on screen.
        func color(_ image: CGImage, at point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8) {
            var pixel = [UInt8](repeating: 0, count: 4)
            guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
            context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1,
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
            return (pixel[0], pixel[1], pixel[2])
        }
        func isRed(_ c: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { c.r > 200 && c.g < 60 && c.b < 60 }

        var anchored = RecorderImageOverlay(path: pictureURL.path, start: 0, end: 4, anchor: .center, size: 0.2)
        if let (image, canvas) = render(anchored) {
            suite.expect(isRed(color(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2))),
                   "a picture at upstream's center place is drawn in the middle of the frame: \(color(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2)))")
        } else {
            suite.expect(false, "the anchored picture is rendered")
        }
        // Held on the stage, the picture is left out of the video, then comes back.
        ForkRecorderImageVisibility.hide(anchored.id)
        if let (image, canvas) = render(anchored) {
            suite.expect(!isRed(color(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2))),
                   "a picture held on the stage is not drawn in the video: only one copy shows")
        }
        ForkRecorderImageVisibility.show(anchored.id)
        suite.expect(!ForkRecorderImageVisibility.isHidden(anchored.id), "let go, it is drawn again")

        // A picture half red, half blue, mirrored: red is now on the right.
        let halvesURL = folder.appendingPathComponent("halves.png")
        if writeHalves(to: halvesURL) {
            var halves = RecorderImageOverlay(path: halvesURL.path, start: 0, end: 4, anchor: .center, size: 0.3)
            if let (image, canvas) = render(halves) {
                let left = color(image, at: CGPoint(x: canvas.width / 2 - canvas.width * 0.1, y: canvas.height / 2))
                suite.expect(isRed(left), "the test picture is red on its left as drawn: \(left)")
            }
            halves.forkTurn = ForkRecorderImageTurn(mirrored: true)
            if let (image, canvas) = render(halves) {
                let right = color(image, at: CGPoint(x: canvas.width / 2 + canvas.width * 0.1, y: canvas.height / 2))
                suite.expect(isRed(right), "mirrored, its red half is drawn on the right: \(right)")
            } else {
                suite.expect(false, "the mirrored picture is rendered")
            }
            halves.forkTurn = ForkRecorderImageTurn(degrees: 90)
            if let (image, canvas) = render(halves) {
                let top = color(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2 - canvas.width * 0.04))
                suite.expect(isRed(top), "turned a quarter clockwise, its left half is drawn on top: \(top)")
            } else {
                suite.expect(false, "the rotated picture is rendered")
            }
        } else {
            suite.expect(false, "the half red, half blue test picture is written")
        }

        anchored.forkCenter = CGPoint(x: 0.25, y: 0.25)
        if let (image, canvas) = render(anchored) {
            let there = color(image, at: CGPoint(x: canvas.width * 0.25, y: canvas.height * 0.25))
            let middle = color(image, at: CGPoint(x: canvas.width / 2, y: canvas.height / 2))
            suite.expect(isRed(there) && !isRed(middle),
                   "a picture dragged to the upper left quarter is drawn there, and no longer in the middle: \(there) \(middle)")
        } else {
            suite.expect(false, "the hand-placed picture is rendered")
        }
    }

    /// The same picture through a real export: the file the exporter writes,
    /// one of its frames read back.
    static func exportsThePicture(_ suite: TestSuite) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("fork-image-export-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let take = RecorderTakeStore.Take(id: UUID(), folder: folder)
                try await ForkRecorderMusicTests.writeSilentVideo(to: take.videoURL, seconds: 2)
                let pictureURL = folder.appendingPathComponent("red.png")
                guard writeRedSquare(to: pictureURL) else { throw CocoaError(.fileWriteUnknown) }
                var document = RecorderEditDocument()
                document.showsPointer = false
                document.zoomEnabled = false
                var overlay = RecorderImageOverlay(path: pictureURL.path, start: 0, end: 2, anchor: .center, size: 0.3)
                overlay.forkCenter = CGPoint(x: 0.3, y: 0.3)
                document.images = [overlay]
                let output = folder.appendingPathComponent("image.mp4")
                let failure = await RecorderExporter().export(take: take, document: document, output: .video,
                                                              to: output, progress: { _ in })
                suite.expect(failure == nil, "a recording with a picture exports")
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                let frame = try await generator.image(at: CMTime(value: 1, timescale: 1)).image
                let size = CGSize(width: frame.width, height: frame.height)
                let there = sample(frame, at: CGPoint(x: size.width * 0.3, y: size.height * 0.3))
                let corner = sample(frame, at: CGPoint(x: size.width * 0.9, y: size.height * 0.9))
                suite.expect(there.r > 180 && there.g < 90 && there.b < 90,
                       "the exported video shows the picture where it was dragged: \(there)")
                suite.expect(!(corner.r > 180 && corner.g < 90), "and not elsewhere: \(corner)")
            } catch {
                suite.expect(false, "the picture export fixture is built: \(error)")
            }
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 120) == .success, "the export with a picture finishes within its deadline")
    }

    /// The colour at a point given with a top-left origin.
    static func sample(_ image: CGImage, at point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
        context.draw(image, in: CGRect(x: -point.x, y: point.y - CGFloat(image.height) + 1,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (pixel[0], pixel[1], pixel[2])
    }

    /// Red on the left half, blue on the right.
    private static func writeHalves(to url: URL) -> Bool {
        guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 64))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func writeRedSquare(to url: URL) -> Bool {
        guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
