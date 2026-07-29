import AppKit

/// The panel behind the chrome bar's sliders button, shaped after the one
/// Spotify's miniplayer shows: a heading, the switches, and an amber "Done"
/// pill, drawn over the card rather than in a menu.
///
/// Spotify offers two switches, "Background color" and "Queue". Only the first
/// has any meaning here — Lyrify shows one Track, never a queue — so only the
/// first is offered rather than showing a switch that would do nothing.
///
/// Deliberately untested — a layout and drawing leaf, verified by hand.
final class MiniplayerSettingsView: NSView {
    var onDone: (() -> Void)?
    var onBackgroundColorChanged: ((Bool) -> Void)?

    private let backgroundColorSwitch = ToggleSwitch()

    init() {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Miniplayer settings")
        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.textColor = .white

        let label = NSTextField(labelWithString: "Background color")
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .white

        backgroundColorSwitch.onToggled = { [weak self] isOn in
            self?.onBackgroundColorChanged?(isOn)
        }

        let row = NSStackView(views: [label, NSView(), backgroundColorSwitch])
        row.orientation = .horizontal
        row.alignment = .centerY

        let done = DoneButton(target: self, action: #selector(doneTapped))

        let stack = NSStackView(views: [heading, row, done])
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
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heading.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(backgroundColorEnabled: Bool) {
        backgroundColorSwitch.isOn = backgroundColorEnabled
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

    init() {
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

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onToggled?(isOn)
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
