// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

import AppKit
import ImageIO

/// Applies the window capture style to a window just captured, before it
/// goes on to the preview, the clipboard or a file. Called from one line of
/// upstream's screenshot tool, and by the capture menu for a window it frames.
enum ForkWindowCaptureStyler {
    typealias Style = ForkWindowCaptureStyle

    /// The capture as the screenshot tool keeps it: in the window style when
    /// it is the window just clicked, untouched otherwise. Called from one
    /// line where upstream's screenshot tool receives a capture.
    static func styledIfWindow(_ capture: ScreenshotSelectionController.Capture) -> ScreenshotSelectionController.Capture {
        guard Style.takeWindowCaptureNote() else { return capture }
        let styled = styled(image: capture.image, scale: capture.scale)
        return ScreenshotSelectionController.Capture(image: styled.image, scale: styled.scale,
                                                     anchorRect: capture.anchorRect, sourceFormat: .png)
    }

    /// The window's picture in the chosen style, and its pixels per point;
    /// the picture as it came when the style is "as it is" or drawing fails.
    static func styled(image: CGImage, scale: CGFloat,
                       defaults: UserDefaults = .standard) -> (image: CGImage, scale: CGFloat) {
        switch Style.mode(stored: defaults.string(forKey: DefaultsKey.forkWindowCaptureStyle)) {
        case .plain:
            return (image, scale)
        case .shadow:
            return (shadowed(image, scale: scale) ?? image, scale)
        case .backdrop:
            guard let export = onBackdrop(image, scale: scale, defaults: defaults) else { return (image, scale) }
            return (export.image, export.scale)
        }
    }

    /// The window on a transparent picture a little larger, with the soft
    /// shadow macOS draws under windows.
    static func shadowed(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let factor = scale > 0 ? scale : 1
        let layout = Style.shadowLayout(windowSize: CGSize(width: image.width, height: image.height), scale: factor)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(layout.canvas.width), height: Int(layout.canvas.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.setShadow(offset: CGSize(width: 0, height: -Style.shadowDrop * factor),
                          blur: Style.shadowBlur * factor,
                          color: CGColor(gray: 0, alpha: Style.shadowOpacity))
        context.draw(image, in: layout.window)
        return context.makeImage()
    }

    /// The window set on the background last chosen in the screenshot editor,
    /// drawn by upstream's own renderer; a gradient when none was ever chosen.
    private static func onBackdrop(_ image: CGImage, scale: CGFloat,
                                   defaults: UserDefaults) -> ScreenshotRenderer.Export? {
        var style = ScreenshotSupport.BackdropStyle.decoded(defaults.string(forKey: DefaultsKey.screenshotBackdropStyle) ?? "")
        if style.kind == .none {
            style = ScreenshotSupport.BackdropStyle(kind: .preset, presetID: ScreenshotSupport.BackdropID.ocean.rawValue,
                                                    padding: 0.5, cornerRadius: 0.5)
        }
        return ScreenshotRenderer.renderExport(baseImage: image, annotations: [], blurSources: .none, scale: scale,
                                               annotationShadowsEnabled: false,
                                               watermark: ScreenshotSupport.WatermarkStyle(), watermarkImage: nil,
                                               style: style, fill: fill(for: style), downscaleTo1x: false)
    }

    /// The same reading of a background as the editor's.
    private static func fill(for style: ScreenshotSupport.BackdropStyle) -> ScreenshotRenderer.BackdropFill {
        switch style.kind {
        case .none:
            return .none
        case .preset:
            guard let id = style.presetID, let preset = ScreenshotSupport.BackdropID(rawValue: id) else { return .none }
            return .colors(preset.stops)
        case .solid, .gradient:
            let colors = (style.colors ?? []).compactMap { $0.count >= 3 ? (red: $0[0], green: $0[1], blue: $0[2]) : nil }
            return colors.isEmpty ? .none : .colors(colors)
        case .image:
            guard let path = style.imagePath,
                  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 4096,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { return .none }
            return .image(picture)
        }
    }
}
