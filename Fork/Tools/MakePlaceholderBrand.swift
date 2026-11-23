// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Arthur Cissac

// Draws the fork's provisional brand assets into Fork/Brand:
//   - logo.png             the monochrome mark (menu bar glyph, in-app mark)
//   - AppIcon-Default.png  the finished app icon
//   - AppIcon.icon/        the adaptive icon source compiled by actool
//
// Everything is drawn from the geometry below: no upstream artwork is read or
// traced. Run it again after changing the design, then commit the outputs:
//
//   swift Fork/Tools/MakePlaceholderBrand.swift
//
// Tools/MakeIcon.swift turns these into the .icns, the menu bar glyph and the
// in-app mark at build time, exactly as it does for upstream's assets.
import AppKit

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let brandDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Brand")
let canvas: CGFloat = 1024

// MARK: - The mark: a porthole
//
// All measures are fractions of the mark's box, whose origin is its center.
// A porthole reads at 12 pt because it is one bold ring: the bolts, the inner
// bezel and the glint are details that only show at larger sizes.
enum Porthole {
    static let ringOuter: CGFloat = 0.440
    static let ringInner: CGFloat = 0.318
    static let boltOrbit: CGFloat = 0.379
    static let boltRadius: CGFloat = 0.026
    static let boltCount = 6
    static let bezelOuter: CGFloat = 0.268
    static let bezelInner: CGFloat = 0.236
    static let glintRadius: CGFloat = 0.172
    static let glintWidth: CGFloat = 0.040
    static let glintStart: CGFloat = 112   // degrees, counter-clockwise from +x
    static let glintEnd: CGFloat = 158
    // The hinge on the left and the latch on the right make the silhouette
    // wider than tall, so it holds its own next to other menu bar icons.
    static let hinge = CGRect(x: -0.500, y: -0.085, width: 0.100, height: 0.170)
    static let latch = CGRect(x: 0.410, y: -0.055, width: 0.090, height: 0.110)
    static let tabCorner: CGFloat = 0.028

    static func boltCenters() -> [CGPoint] {
        (0..<boltCount).map { index in
            let angle = (CGFloat(index) * 360 / CGFloat(boltCount) + 30) * .pi / 180
            return CGPoint(x: cos(angle) * boltOrbit, y: sin(angle) * boltOrbit)
        }
    }
}

func circle(_ radius: CGFloat, at center: CGPoint = .zero) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2))
}

/// Draws the mark in the current context, centered in `box`, in `color`.
/// `glass`, when given, fills the window behind the bezel.
func drawPorthole(in box: CGRect, color: NSColor, glass: NSGradient? = nil) {
    guard let context = NSGraphicsContext.current else { return }
    context.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: box.midX, yBy: box.midY)
    transform.scale(by: min(box.width, box.height))
    transform.concat()

    if let glass {
        glass.draw(in: circle(Porthole.ringInner), relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
    }

    color.setFill()
    color.setStroke()
    for tab in [Porthole.hinge, Porthole.latch] {
        NSBezierPath(roundedRect: tab, xRadius: Porthole.tabCorner, yRadius: Porthole.tabCorner).fill()
    }

    // Even-odd: the ring is the outer disc minus the inner one, and each bolt
    // is a hole punched through it.
    let ring = NSBezierPath()
    ring.windingRule = .evenOdd
    ring.append(circle(Porthole.ringOuter))
    ring.append(circle(Porthole.ringInner))
    for center in Porthole.boltCenters() {
        ring.append(circle(Porthole.boltRadius, at: center))
    }
    ring.fill()

    let bezel = NSBezierPath()
    bezel.windingRule = .evenOdd
    bezel.append(circle(Porthole.bezelOuter))
    bezel.append(circle(Porthole.bezelInner))
    bezel.fill()

    let glint = NSBezierPath()
    glint.appendArc(withCenter: .zero, radius: Porthole.glintRadius,
                    startAngle: Porthole.glintStart, endAngle: Porthole.glintEnd)
    glint.lineWidth = Porthole.glintWidth
    glint.lineCapStyle = .round
    glint.stroke()
    context.restoreGraphicsState()
}

// MARK: - Rendering

func render(_ draw: () -> Void) -> Data {
    let pixels = Int(canvas)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("could not create the drawing canvas")
    }
    bitmap.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the PNG")
    }
    return png
}

func write(_ data: Data, to name: String) {
    let url = brandDir.appendingPathComponent(name)
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
        print("wrote \(url.path)")
    } catch {
        fatalError("could not write \(url.path): \(error)")
    }
}

// The mark alone, black on transparent. It is only ever used as a template
// image, so its alpha channel is what matters.
let logo = render {
    drawPorthole(in: CGRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 12, dy: 12),
                 color: .black)
}
write(logo, to: "logo.png")

// The finished icon on the macOS grid: an 824 pt body centered in the 1024 pt
// canvas, corners at 22.5 % of its side, with its own soft shadow.
let appIcon = render {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 22
    shadow.set()
    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.27, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.11, green: 0.25, blue: 0.40, alpha: 1),
               ending: NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.17, alpha: 1))?
        .draw(in: shape, angle: -90)

    let glass = NSGradient(starting: NSColor(calibratedRed: 0.62, green: 0.86, blue: 1.0, alpha: 0.95),
                           ending: NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.68, alpha: 0.95))
    drawPorthole(in: body.insetBy(dx: 96, dy: 96),
                 color: NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.99, alpha: 1),
                 glass: glass)
}
write(appIcon, to: "AppIcon-Default.png")

// MARK: - Adaptive icon source (Icon Composer format, compiled by actool)

func svgNumber(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}

/// The same geometry as `drawPorthole`, as an SVG in a 1000-unit box. SVG's y
/// axis points down, so vertical positions and angles are mirrored.
func portholeSVG() -> String {
    let unit: CGFloat = 1000
    let center = unit / 2
    func x(_ value: CGFloat) -> String { svgNumber(center + value * unit) }
    func y(_ value: CGFloat) -> String { svgNumber(center - value * unit) }
    func length(_ value: CGFloat) -> String { svgNumber(value * unit) }
    func disc(_ radius: CGFloat, at point: CGPoint = .zero) -> String {
        // Two half arcs: a full circle as a closed subpath.
        let left = x(point.x - radius), right = x(point.x + radius), middle = y(point.y)
        let r = length(radius)
        return "M \(left) \(middle) A \(r) \(r) 0 1 0 \(right) \(middle) A \(r) \(r) 0 1 0 \(left) \(middle) Z"
    }
    func tab(_ rect: CGRect) -> String {
        "<rect x=\"\(x(rect.minX))\" y=\"\(y(rect.maxY))\" width=\"\(length(rect.width))\" "
            + "height=\"\(length(rect.height))\" rx=\"\(length(Porthole.tabCorner))\"/>"
    }
    let ring = ([disc(Porthole.ringOuter), disc(Porthole.ringInner)]
        + Porthole.boltCenters().map { disc(Porthole.boltRadius, at: $0) }).joined(separator: " ")
    let bezel = [disc(Porthole.bezelOuter), disc(Porthole.bezelInner)].joined(separator: " ")
    func glintPoint(_ degrees: CGFloat) -> String {
        let angle = degrees * .pi / 180
        return "\(x(cos(angle) * Porthole.glintRadius)) \(y(sin(angle) * Porthole.glintRadius))"
    }
    let glintRadius = length(Porthole.glintRadius)
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
      <g fill="#000000">
        \(tab(Porthole.hinge))
        \(tab(Porthole.latch))
        <path fill-rule="evenodd" d="\(ring)"/>
        <path fill-rule="evenodd" d="\(bezel)"/>
      </g>
      <path fill="none" stroke="#000000" stroke-width="\(length(Porthole.glintWidth))" stroke-linecap="round"
            d="M \(glintPoint(Porthole.glintStart)) A \(glintRadius) \(glintRadius) 0 0 0 \(glintPoint(Porthole.glintEnd))"/>
    </svg>

    """
}

/// The window alone, as a second layer behind the mark so it can carry its
/// own colour: the mark's SVG is a single-colour shape.
func glassSVG() -> String {
    let radius = svgNumber(Porthole.ringInner * 1000)
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
      <circle cx="500" cy="500" r="\(radius)" fill="#000000"/>
    </svg>

    """
}

// Layers are listed front to back. Both use the same scale and no offset, so
// the two SVGs, drawn in the same 1000-unit box, stay registered.
let iconDescription = """
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.11000,0.25000,0.40000,1.00000",
      "srgb:0.03000,0.09000,0.17000,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "fill" : {
            "solid" : "srgb:0.95000,0.97000,0.99000,1.00000"
          },
          "image-name" : "hublot-mark.svg",
          "name" : "Mark",
          "position" : {
            "scale" : 0.8,
            "translation-in-points" : [
              0,
              0
            ]
          }
        },
        {
          "fill" : {
            "solid" : "srgb:0.38000,0.66000,0.88000,1.00000"
          },
          "image-name" : "hublot-glass.svg",
          "name" : "Glass",
          "position" : {
            "scale" : 0.8,
            "translation-in-points" : [
              0,
              0
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""

write(Data(portholeSVG().utf8), to: "AppIcon.icon/Assets/hublot-mark.svg")
write(Data(glassSVG().utf8), to: "AppIcon.icon/Assets/hublot-glass.svg")
write(Data(iconDescription.utf8), to: "AppIcon.icon/icon.json")
