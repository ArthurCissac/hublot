// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import SwiftUI

/// On the video editor's stage, the pictures laid over the recording are
/// taken by hand: a click selects one, dragging moves it, and the selected
/// one has a handle at each corner for its size. Upstream's panel on the
/// right keeps working; this is the same edit, made where the picture is.
///
/// Added to the stage by one line of upstream's editor view. The geometry is
/// in `ForkRecorderImagePlacement`, shared with the export.
struct ForkRecorderImageHandles: View {
    typealias Placement = ForkRecorderImagePlacement
    typealias Turn = ForkRecorderImageTurn

    @ObservedObject var model: RecorderEditorModel
    @ObservedObject private var drag = ForkRecorderImageDrag.shared
    let stage: CGSize

    /// The picture's center when the drag began.
    @State private var moveStart: CGPoint?
    /// The picture's size when a corner was taken, and how far from its center.
    @State private var resizeStart: ResizeStart?
    /// The rotation handle is being dragged.
    @State private var isRotating = false

    private struct ResizeStart {
        let size: Double
        let distance: CGFloat
    }

    private static let space = "fork-recorder-stage"
    private static let handleSide: CGFloat = 10
    /// From the picture's top edge to the rotation handle's center.
    private static let handleReach: CGFloat = 24
    private static let barSize = CGSize(width: 116, height: 28)

    var body: some View {
        let canvas = model.exportCanvasSize
        ZStack(alignment: .topLeading) {
            // Upstream's own gestures on the picture come first: aiming a zoom, drawing a blur.
            if !model.isAimingZoom, !model.isPickingBlurArea, canvas.width > 0 {
                ForEach(pictures) { overlay in
                    if let source = Self.sourceSize(of: overlay),
                       let frame = Placement.frame(of: overlay, source: source, canvas: canvas, stage: stage) {
                        picture(overlay, frame: frame, source: source, canvas: canvas)
                    }
                }
            }
        }
        .frame(width: stage.width, height: stage.height, alignment: .topLeading)
        .coordinateSpace(name: Self.space)
        .onChange(of: model.selectedImageID) { _, _ in showSelectedWhole() }
        .onAppear { showSelectedWhole() }
    }

    /// Before a gesture: the playhead goes where the picture is drawn whole,
    /// so it can be seen where it is dropped, then the video lets go of it
    /// while the stage draws it under the pointer.
    private func beginGesture(on overlay: RecorderImageOverlay) {
        if !model.isPlaying, let moment = Placement.visibleMoment(of: overlay, at: model.sourceTime) {
            model.seek(to: moment)
        }
        drag.begin(overlay.id, player: model.player)
    }

    /// A picture fades in from its first moment, and one is added at the
    /// playhead: the playhead moves to where the selected picture is drawn whole.
    private func showSelectedWhole() {
        guard !model.isPlaying, let overlay = model.selectedImage,
              let moment = Placement.visibleMoment(of: overlay, at: model.sourceTime)
        else { return }
        model.seek(to: moment)
    }

    /// The pictures on screen at this moment, the selected one last so it is on top.
    private var pictures: [RecorderImageOverlay] {
        let selected = model.selectedImageID
        // Pictures are timed on the recording's clock, not on the finished video's.
        let time = model.sourceTime
        let shown = model.document.images.filter { $0.id == selected || (time >= $0.start && time <= $0.end) }
        return shown.filter { $0.id != selected } + shown.filter { $0.id == selected }
    }

    private func picture(_ overlay: RecorderImageOverlay, frame: CGRect, source: CGSize, canvas: CGSize) -> some View {
        let isSelected = overlay.id == model.selectedImageID
        let turn = overlay.forkTurn ?? Turn()
        let angle = Turn.normalized(turn.degrees)
        // Held, or let go and waiting for the video to draw it at its new place.
        let isHeld = isSelected && (moveStart != nil || resizeStart != nil || isRotating) || drag.heldID == overlay.id
        return ZStack(alignment: .topLeading) {
            ZStack {
                // While it is held, the picture follows the pointer here; the video
                // takes the change as soon as it is let go.
                if isHeld, let picture = Self.picture(at: overlay.path) {
                    Image(nsImage: picture)
                        .resizable()
                        .scaleEffect(x: turn.mirrored ? -1 : 1, y: 1)
                        .opacity(overlay.opacity)
                        .allowsHitTesting(false)
                }
                // Nothing is drawn but the outline: the picture itself is in the video underneath.
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectLaneItem(.image, id: overlay.id) }
                    .gesture(move(overlay, source: source, canvas: canvas))
                if isSelected {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                    ForEach(0..<4, id: \.self) { corner in
                        handle(overlay, corner: corner, frame: frame, source: source, canvas: canvas)
                    }
                    rotationHandle(overlay, turn: turn, frame: frame)
                }
            }
            .frame(width: frame.width, height: frame.height)
            // The outline, its handles and the rotation handle turn with the picture.
            .rotationEffect(.degrees(angle))
            .offset(x: frame.minX, y: frame.minY)
            if isSelected {
                let origin = Turn.barOrigin(barSize: Self.barSize, pictureCenter: CGPoint(x: frame.midX, y: frame.midY),
                                            covered: Turn.coveredSize(of: frame.size, degrees: angle), stage: stage,
                                            clearance: Self.handleReach + 8)
                bar(turn: turn)
                    .offset(x: origin.x, y: origin.y)
            }
        }
    }

    /// Straight above the picture, a round handle to turn it. Shift turns it
    /// fifteen degrees at a time; a double click stands it upright again.
    private func rotationHandle(_ overlay: RecorderImageOverlay, turn: Turn, frame: CGRect) -> some View {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        let text = ForkStrings.current
        return ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: Self.handleReach - 7)
                .offset(y: -frame.height / 2 - (Self.handleReach - 7) / 2)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
                .frame(width: 13, height: 13)
                .padding(6)
                .contentShape(Circle())
                .offset(y: -frame.height / 2 - Self.handleReach)
                .help(text.imageRotate)
                .onTapGesture(count: 2) {
                    setTurn { $0.degrees = 0 }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            if !isRotating { beginGesture(on: overlay) }
                            isRotating = true
                            let wanted = Turn.degrees(handleAt: value.location, center: middle)
                            let fine = NSEvent.modifierFlags.contains(.shift)
                            let degrees = Turn.snapped(wanted, fine: fine)
                            model.updateSelectedImage {
                                var next = $0.forkTurn ?? Turn()
                                next.degrees = degrees
                                $0.forkTurn = next
                            }
                        }
                        .onEnded { _ in
                            isRotating = false
                            model.commitZoomEdit()
                            drag.end(player: model.player)
                        }
                )
        }
    }

    /// Above the selected picture: mirror it, its angle, stand it upright.
    private func bar(turn: Turn) -> some View {
        let text = ForkStrings.current
        return HStack(spacing: 2) {
            Button {
                setTurn { $0.mirrored.toggle() }
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .foregroundStyle(turn.mirrored ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help(text.imageMirror)
            .accessibilityLabel(text.imageMirror)

            Text("\(Int(Turn.normalized(turn.degrees).rounded()) % 360)°")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 40)

            Button {
                setTurn { $0.degrees = 0 }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(Turn.normalized(turn.degrees) == 0)
            .help(text.imageStraighten)
            .accessibilityLabel(text.imageStraighten)
        }
        .padding(.horizontal, 6)
        .frame(width: Self.barSize.width, height: Self.barSize.height)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
    }

    /// One change of the turn, saved as one undo step.
    private func setTurn(_ change: (inout Turn) -> Void) {
        model.updateSelectedImage {
            var next = $0.forkTurn ?? Turn()
            change(&next)
            $0.forkTurn = next.isIdentity ? nil : next
        }
        model.commitZoomEdit()
    }

    private func move(_ overlay: RecorderImageOverlay, source: CGSize, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if model.selectedImageID != overlay.id { model.selectLaneItem(.image, id: overlay.id) }
                if moveStart == nil { beginGesture(on: overlay) }
                guard let shown = Placement.shownRect(canvas: canvas, in: stage),
                      let drawn = RecorderImageOverlay.drawnSize(source: source, size: overlay.size, canvas: canvas)
                else { return }
                let start = moveStart ?? Placement.center(of: overlay, drawn: drawn, in: canvas)
                moveStart = start
                let center = Placement.moved(start, by: value.translation, shown: shown.size)
                model.updateSelectedImage { $0.forkCenter = center }
            }
            .onEnded { _ in
                moveStart = nil
                // One undo entry and one save for the whole drag, as for upstream's sliders.
                model.commitZoomEdit()
                drag.end(player: model.player)
            }
    }

    private func handle(_ overlay: RecorderImageOverlay, corner: Int, frame: CGRect,
                        source: CGSize, canvas: CGSize) -> some View {
        let side = Self.handleSide
        let x = corner % 2 == 0 ? -frame.width / 2 : frame.width / 2
        let y = corner < 2 ? -frame.height / 2 : frame.height / 2
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
            .overlay { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5) }
            .frame(width: side, height: side)
            // A larger target than the square that is drawn.
            .padding(6)
            .contentShape(Rectangle())
            .offset(x: x, y: y)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        guard let drawn = RecorderImageOverlay.drawnSize(source: source, size: overlay.size, canvas: canvas)
                        else { return }
                        if resizeStart == nil { beginGesture(on: overlay) }
                        let start = resizeStart ?? ResizeStart(
                            size: overlay.size,
                            distance: hypot(value.startLocation.x - middle.x, value.startLocation.y - middle.y))
                        resizeStart = start
                        // Pinned where it is first, so it grows around its center and the corner follows the pointer.
                        let center = Placement.center(of: overlay, drawn: drawn, in: canvas)
                        let size = Placement.resized(start.size, from: start.distance,
                                                     to: hypot(value.location.x - middle.x, value.location.y - middle.y),
                                                     source: source, canvas: canvas)
                        model.updateSelectedImage {
                            $0.forkCenter = center
                            $0.size = size
                        }
                    }
                    .onEnded { _ in
                        resizeStart = nil
                        model.commitZoomEdit()
                        drag.end(player: model.player)
                    }
            )
    }

    private static var pictures: [String: NSImage] = [:]

    private static func picture(at path: String) -> NSImage? {
        if let known = pictures[path] { return known }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        pictures[path] = image
        return image
    }

    // The picture's own size gives its proportions. Read once per file: the
    // stage redraws at every tick of the playhead.
    private static var sourceSizes: [String: CGSize] = [:]

    private static func sourceSize(of overlay: RecorderImageOverlay) -> CGSize? {
        if let known = sourceSizes[overlay.path] { return known }
        guard let size = MediaSupport.imageDisplaySize(at: URL(fileURLWithPath: overlay.path)) else { return nil }
        sourceSizes[overlay.path] = size
        return size
    }
}
