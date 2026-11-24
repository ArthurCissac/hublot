// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import SwiftUI

/// The parts of the simpler crop that need the editor itself: applying the
/// crop when another tool is picked, the ratio menu, and the views drawn over
/// the canvas and in the bar. See `ForkCropTool`.
extension ForkCropTool {
    /// Another tool was picked with a crop drawn: the crop is applied, then
    /// the new tool is back. Escape and Cancel drop the crop first, so they
    /// leave the picture as it was.
    static func commitOnLeave(_ model: ScreenshotEditorModel, draft: CGRect?, next: ScreenshotSupport.Tool) {
        guard isEnabled, let draft, draft.standardized != CGRect(origin: .zero, size: model.imageSize) else { return }
        // Once the tool change is done: applying sets the tool too.
        DispatchQueue.main.async { [weak model] in
            guard let model, model.tool == next, model.cropDraft == nil else { return }
            model.cropDraft = draft
            model.applyCrop()
            model.tool = next
        }
    }

    // MARK: - Ratio

    static func choose(_ ratio: ForkCropGeometry.Ratio, model: ScreenshotEditorModel) {
        self.ratio = ratio
        guard let draft = model.cropDraft else { return }
        let fitted = ForkCropGeometry.fitted(ratio: ratio.value(imageSize: model.imageSize), in: draft)
        model.cropDraft = ScreenshotSupport.pixelSnappedCropRect(fitted, within: CGRect(origin: .zero, size: model.imageSize))
    }

    static func name(of ratio: ForkCropGeometry.Ratio) -> String {
        let text = ForkCropStrings.current
        switch ratio {
        case .free: return text.free
        case .original: return text.original
        default: return ratio.label ?? text.free
        }
    }
}

/// The crop as drawn over the canvas: the picture dimmed outside it, its
/// frame, the grips, and the thirds with the size while it is pulled. In
/// view points, so the grips keep their size whatever the zoom. It takes no
/// clicks: the canvas under it does.
struct ForkCropOverlay: View {
    @ObservedObject var model: ScreenshotEditorModel
    let zoom: CGFloat
    let canvasSize: CGSize

    var body: some View {
        if ForkCropTool.isEnabled, model.tool == .crop, let draft = model.cropDraft {
            let pad = model.backdropPaddingPixels
            let frame = CGRect(x: (draft.minX + pad) * zoom, y: (draft.minY + pad) * zoom,
                               width: draft.width * zoom, height: draft.height * zoom)
            let adjusting = ForkCropTool.isAdjusting
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var dim = Path(CGRect(origin: .zero, size: size))
                    dim.addRect(frame)
                    context.fill(dim, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    context.stroke(Path(frame), with: .color(.white.opacity(0.9)), lineWidth: 1)
                    if adjusting {
                        var grid = Path()
                        let thirds = ForkCropGeometry.thirds(of: frame)
                        for x in thirds.vertical {
                            grid.move(to: CGPoint(x: x, y: frame.minY))
                            grid.addLine(to: CGPoint(x: x, y: frame.maxY))
                        }
                        for y in thirds.horizontal {
                            grid.move(to: CGPoint(x: frame.minX, y: y))
                            grid.addLine(to: CGPoint(x: frame.maxX, y: y))
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.55)), lineWidth: 0.75)
                    }
                    var grips = Path()
                    for rect in ForkCropGeometry.gripRects(in: frame) { grips.addRect(rect) }
                    var shadowed = context
                    shadowed.addFilter(.shadow(color: .black.opacity(0.45), radius: 2))
                    shadowed.fill(grips, with: .color(.white))
                }
                .frame(width: canvasSize.width, height: canvasSize.height)

                if adjusting {
                    Text(ForkCropGeometry.sizeLabel(draft))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .offset(x: max(4, frame.minX + 10), y: max(4, frame.minY + 10))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The bar under the canvas while cropping: Cancel, the ratio, the size, Crop.
struct ForkCropBar: View {
    @ObservedObject var model: ScreenshotEditorModel
    let strings: ScreenshotFeatureStrings
    @State private var ratio = ForkCropTool.ratio

    var body: some View {
        let text = ForkCropStrings.current
        HStack(spacing: 10) {
            Button(strings.cancel) {
                // Dropped first, so leaving the tool does not apply it.
                model.cropDraft = nil
                model.tool = .select
            }
            Menu {
                ForEach(ForkCropGeometry.Ratio.allCases, id: \.self) { choice in
                    Button {
                        ratio = choice
                        ForkCropTool.choose(choice, model: model)
                    } label: {
                        if choice == ratio {
                            Label(ForkCropTool.name(of: choice), systemImage: "checkmark")
                        } else {
                            Text(ForkCropTool.name(of: choice))
                        }
                    }
                }
            } label: {
                Label(ForkCropTool.name(of: ratio), systemImage: "aspectratio")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(text.ratio)
            if let draft = model.cropDraft {
                Text(ForkCropGeometry.sizeLabel(draft))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button(strings.cropApply) {
                model.applyCrop()
            }
            .buttonStyle(.borderedProminent)
            .screenshotSafeHelp("⏎")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 3)
    }
}
