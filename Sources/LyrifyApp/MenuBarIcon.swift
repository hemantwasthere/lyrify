import AppKit

/// The mark, reduced for the menu bar.
///
/// A redraw of `Resources/Brand/logo-mark.svg` rather than a render of it, and
/// so the second exception to "every raster comes from the one drawing" after
/// `LyrifyMark.tsx` — but for a different reason. A template image is read for
/// its alpha alone, and every shape in that SVG is opaque: rasterising it would
/// flatten the rim, the cream body and the groove into a single filled black
/// circle. A plain dot, with nothing left of the mark in it.
///
/// So what is drawn here is what the drawing *means* — a record: a rim, the
/// played arc with its stylus at the head, the label at the centre. The parts
/// that read as colour at 512px have to read as gaps at 18, which is why the
/// proportions are the SVG's but the stroke widths are not. Its rim is 30 units
/// of 512, which lands at 0.94pt here and antialiases to a grey smudge.
///
/// Template, so AppKit tints it black or white to match the menu bar and
/// inverts it when the item is highlighted. Full colour was the other option
/// and it is the wrong one: a pale cream disc against the light menu bar is
/// precisely the contrast this mark has never had.
///
/// Deliberately untested — a drawing, verified by eye.
enum MenuBarIcon {
    /// The square the menu bar gives a status item at standard height. Drawn to
    /// the point size and re-rasterised per scale factor by the drawing handler,
    /// so Retina crispness needs no @2x of its own.
    static let length: CGFloat = 18

    /// Centreline radius of the rim, leaving the stroke's outer half inside the
    /// square. Everything else is a fraction of it, taken from the SVG.
    private static let rimRadius: CGFloat = 7.5
    private static let strokeWidth: CGFloat = 1.5

    /// The played arc's sweep: 190 units of dash on a 2π×152 circumference,
    /// starting at twelve o'clock. The stylus sits on its head, so the two share
    /// this angle and cannot drift apart.
    private static let arcSweep: CGFloat = 71.6

    static func make() -> NSImage {
        let image = NSImage(
            size: NSSize(width: length, height: length),
            flipped: false
        ) { _ in
            let centre = NSPoint(x: length / 2, y: length / 2)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let rim = NSBezierPath()
            rim.appendArc(withCenter: centre, radius: rimRadius, startAngle: 0, endAngle: 360)
            rim.lineWidth = strokeWidth
            rim.stroke()

            // Twelve o'clock is 90° in AppKit's y-up degrees, and the arc runs
            // clockwise from there — the direction a record is played.
            let grooveRadius = rimRadius * 0.61
            let arcEnd = 90 - arcSweep
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: centre,
                radius: grooveRadius,
                startAngle: 90,
                endAngle: arcEnd,
                clockwise: true
            )
            arc.lineWidth = strokeWidth
            arc.lineCapStyle = .round
            arc.stroke()

            let head = NSPoint(
                x: centre.x + grooveRadius * cos(arcEnd * .pi / 180),
                y: centre.y + grooveRadius * sin(arcEnd * .pi / 180)
            )
            NSBezierPath(ovalIn: NSRect(x: head.x - 1, y: head.y - 1, width: 2, height: 2)).fill()

            let label = rimRadius * 0.22
            NSBezierPath(
                ovalIn: NSRect(
                    x: centre.x - label,
                    y: centre.y - label,
                    width: label * 2,
                    height: label * 2
                )
            ).fill()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lyrify"
        return image
    }
}
