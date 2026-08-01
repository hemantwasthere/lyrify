import AppKit

/// The panel behind the chrome bar's sliders button, shaped after the one
/// Spotify's miniplayer shows: a heading, the switches, and an amber "Done"
/// pill, drawn over the card rather than in a menu.
///
/// Spotify offers two switches, "Background color" and "Queue". Only the first
/// has any meaning here — Lyrify shows one Track, never a queue — so rather
/// than a switch that would do nothing, the second row is Lyrify's own:
/// "Lyrics only", which has no counterpart in Spotify's panel because
/// Spotify's miniplayer is not primarily a lyrics window.
///
/// Deliberately untested — a layout and drawing leaf, verified by hand.
final class MiniplayerSettingsView: NSView {
    var onDone: (() -> Void)?
    var onBackgroundColorChanged: ((Bool) -> Void)?
    var onLyricsOnlyChanged: ((Bool) -> Void)?

    private let backgroundColorSwitch = ToggleSwitch(title: "Background color")
    private let lyricsOnlySwitch = ToggleSwitch(title: "Lyrics only")

    init() {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Miniplayer settings")
        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.textColor = .white

        backgroundColorSwitch.onToggled = { [weak self] isOn in
            self?.onBackgroundColorChanged?(isOn)
        }
        lyricsOnlySwitch.onToggled = { [weak self] isOn in
            self?.onLyricsOnlyChanged?(isOn)
        }

        let backgroundColorRow = Self.row(for: backgroundColorSwitch)
        let lyricsOnlyRow = Self.row(for: lyricsOnlySwitch)

        let done = DoneButton(target: self, action: #selector(doneTapped))

        let stack = NSStackView(views: [heading, backgroundColorRow, lyricsOnlyRow, done])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(20, after: heading)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            backgroundColorRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            lyricsOnlyRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heading.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The row a switch sits in: its name on the left, the switch itself on
    /// the right.
    ///
    /// The name is read off the switch rather than passed in beside it, so the
    /// words on screen and the words announced to accessibility are one string
    /// and cannot drift apart as rows are added.
    private static func row(for control: ToggleSwitch) -> NSStackView {
        let label = NSTextField(labelWithString: control.title)
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .white

        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    func update(backgroundColorEnabled: Bool) {
        backgroundColorSwitch.isOn = backgroundColorEnabled
    }

    func update(lyricsOnly: Bool) {
        lyricsOnlySwitch.isOn = lyricsOnly
    }

    /// Takes the card's colour, like every other surface on it.
    ///
    /// This was pinned to black, so opening settings over a tinted card dropped a
    /// black sheet across it. Spotify's own panel is not black either — with its
    /// "Background color" switch on it wears the same colour as the card behind
    /// it, which is the state you are in while looking at that very switch.
    func setTint(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }

    @objc private func doneTapped() {
        onDone?()
    }
}

/// A pill switch: grey when off, accent when on, with a white knob that slides
/// across. Shaped after Spotify's, but `NSSwitch` draws the system's blue one,
/// which would leave it the only control on the card not wearing the Overlay's
/// own colours.
final class ToggleSwitch: NSControl {
    var onToggled: ((Bool) -> Void)?

    /// What this switch is called — both the words beside it and the name it
    /// answers to over accessibility.
    ///
    /// Given at construction rather than baked in. It used to return the
    /// literal "Background color", which was harmless only while that was the
    /// panel's one switch: a second would have announced itself as the first
    /// to VoiceOver, and to the scripting that drives this app over the
    /// accessibility tree — the only way its UI is checked at all, the Overlay
    /// being unscreenshottable here. Two controls with one name is not a
    /// cosmetic fault; it makes the panel untestable.
    let title: String

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            animateKnob()
        }
    }

    private let knob = NSView()
    private var knobLeading: NSLayoutConstraint!

    private static let size = NSSize(width: 40, height: 22)
    private static let inset: CGFloat = 3

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(origin: .zero, size: Self.size))

        wantsLayer = true
        layer?.cornerRadius = Self.size.height / 2
        translatesAutoresizingMaskIntoConstraints = false

        knob.wantsLayer = true
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.cornerRadius = (Self.size.height - 2 * Self.inset) / 2
        knob.translatesAutoresizingMaskIntoConstraints = false
        addSubview(knob)

        knobLeading = knob.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),
            knob.widthAnchor.constraint(equalToConstant: Self.size.height - 2 * Self.inset),
            knob.heightAnchor.constraint(equalToConstant: Self.size.height - 2 * Self.inset),
            knob.centerYAnchor.constraint(equalTo: centerYAnchor),
            knobLeading,
        ])

        refreshTrack()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The Overlay is a non-activating panel and never becomes key, so every
    /// click into it is a *first* mouse, which AppKit drops unless the view asks
    /// for it. `NSButton` asks by default; a bare `NSControl` does not.
    ///
    /// This alone was not what stopped the switch working — see
    /// `OverlayInteractive`, which is what actually discarded the clicks — but it
    /// is needed just the same, and would have been the next thing in the way.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        flip()
    }

    private func flip() {
        isOn.toggle()
        onToggled?(isOn)
    }

    // Drawn from scratch, so none of this comes for free the way it would from an
    // `NSSwitch`: without it the switch is not in the accessibility tree at all —
    // no role, no label, nothing to press. VoiceOver cannot reach it, and neither
    // can a script driving the app to check that it works.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityValue() -> Any? { isOn }

    override func accessibilityPerformPress() -> Bool {
        flip()
        return true
    }

    private func animateKnob() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            knobLeading.animator().constant = isOn
                ? Self.size.width - Self.size.height + Self.inset
                : Self.inset
        }
        refreshTrack()
    }

    private func refreshTrack() {
        layer?.backgroundColor = isOn
            ? OverlayPalette.accent.cgColor
            : NSColor(calibratedWhite: 0.32, alpha: 1).cgColor
    }
}

/// The amber pill that closes the settings panel.
private final class DoneButton: NSButton {
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = OverlayPalette.accent.cgColor
        layer?.cornerRadius = 15
        translatesAutoresizingMaskIntoConstraints = false
        attributedTitle = NSAttributedString(
            string: "Done",
            attributes: [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            ]
        )
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 84),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
