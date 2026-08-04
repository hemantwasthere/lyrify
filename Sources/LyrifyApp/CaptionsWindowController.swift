import AppKit
import LyrifyCore

/// Whether Live Captions is switched on, persisted across launches.
///
/// Off by default and deliberately so: nothing is captured, transcribed or
/// asked permission for until the listener turns it on, and someone who never
/// wants this is never prompted.
///
/// Deliberately untested — a thin `UserDefaults` wrapper.
final class LiveCaptionsPreference {
    private static let key = "LiveCaptionsEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// The captions window: what is being said, and nothing else.
///
/// No title, no channel, no application name, no artwork, no transport, no
/// progress. Naming the source would defeat half the point — this says what is
/// being said, and a listener who wants to know what is playing has the Overlay
/// for that.
///
/// A separate window rather than a third view of the Expanded card, so it can be
/// open while the Overlay is closed and sit wherever it is useful.
///
/// Deliberately untested — built and verified by hand, like the Overlay.
@MainActor
final class CaptionsWindowController {
    private let window: NSPanel
    private let stack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let resizer = WindowResizer()
    private let positionPreference: CaptionsPositionPreference

    /// Once the listener has sized the window themselves, it is theirs: it
    /// stops growing on its own and keeps whatever they chose.
    private var isSizedByListener: Bool

    init() {
        positionPreference = CaptionsPositionPreference()
        let remembered = Self.onScreen(positionPreference.frame)
        isSizedByListener = remembered != nil

        let frame = remembered ?? Self.defaultFrame()
        window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle,
        ]
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = true
        window.minSize = Self.minimumSize

        let background = CaptionsBackgroundView()

        // The most recent lines, newest at the bottom, sitting on the floor of
        // the window so they grow upward as they arrive. Scrolling back through
        // a whole session is a separate concern and a later ticket; a scroll
        // view here only cost the words their layout.
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // The same edge-and-corner resizing the Overlay has, from the same
        // view — this window should feel like the other one.
        resizer.minimumSize = Self.minimumSize
        resizer.maximumSize = NSSize(width: 1400, height: 900)
        resizer.onResized = { [weak self] in
            guard let self else { return }
            self.isSizedByListener = true
            self.positionPreference.frame = self.window.frame
        }

        background.addSubview(stack)
        background.addSubview(statusLabel)
        background.addSubview(resizer)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: background.leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(
                equalTo: background.trailingAnchor, constant: -Self.horizontalInset),
            stack.bottomAnchor.constraint(
                equalTo: background.bottomAnchor, constant: -Self.verticalInset),
            stack.topAnchor.constraint(
                greaterThanOrEqualTo: background.topAnchor, constant: Self.verticalInset),
            statusLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: background.leadingAnchor, constant: 16),
            resizer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            resizer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            resizer.topAnchor.constraint(equalTo: background.topAnchor),
            resizer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        window.contentView = background
        observeFrameChanges()
    }

    /// A remembered frame is only usable if it is somewhere the listener can
    /// actually see. Displays get unplugged and arrangements change, and a
    /// window restored onto a screen that is no longer there is invisible while
    /// behaving perfectly — which is exactly how this first appeared to do
    /// nothing at all while captioning happily off the edge of the world.
    private static func onScreen(_ frame: NSRect?) -> NSRect? {
        guard let frame else { return nil }
        let visible = NSScreen.screens.contains { screen in
            // Some of it, not all: a window nudged part-way off an edge is
            // still reachable.
            screen.visibleFrame.intersects(frame)
        }
        return visible ? frame : nil
    }

    /// Small enough to start as a strip of one or two lines, and no smaller
    /// than the resizer will allow.
    static let minimumSize = NSSize(width: 300, height: 64)

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 460, height: minimumSize.height)
        guard let screen = NSScreen.main else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 80,
            width: size.width, height: size.height)
    }

    private func observeFrameChanges() {
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.positionPreference.frame = self.window.frame
                }
            }
        }
    }

    func show() { window.orderFrontRegardless() }

    func hide() { window.orderOut(nil) }

    /// Draws what has been said, or says why nothing has.
    func update(captions: Captions, status: String?) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if captions.lines.isEmpty {
            statusLabel.stringValue = status ?? ""
            statusLabel.isHidden = false
            stack.isHidden = true
            return
        }

        statusLabel.isHidden = true
        stack.isHidden = false

        // As many as the window has room for. A fixed count left a tall window
        // mostly empty above the words, which reads as a layout mistake rather
        // than as breathing room — and a taller window should show more of what
        // was said, not more nothing.
        for line in captions.lines.suffix(Self.lineCap) {
            let label = NSTextField(wrappingLabelWithString: line.text)
            label.font = .systemFont(ofSize: 15, weight: line.isSettled ? .regular : .medium)
            // A line still being revised is dimmer than one the transcriber has
            // committed to, so the reader can tell what is certain from what is
            // still arriving.
            label.textColor = line.isSettled ? .labelColor : .secondaryLabelColor
            label.isSelectable = false
            label.drawsBackground = false
            label.preferredMaxLayoutWidth = max(
                window.frame.width - Self.horizontalInset * 2, 200)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        growToFitContent()
    }

    /// Grows the window to hold what is on screen, and stops.
    ///
    /// It starts as a strip and opens up as the first captions arrive, rather
    /// than reserving a large empty card for words that have not been said yet.
    /// Past the cap it stops growing and the oldest line drops off instead, so
    /// a long talk does not slowly eat the screen.
    ///
    /// Does nothing once the listener has sized it themselves — at that point
    /// the window is theirs.
    private func growToFitContent() {
        guard isSizedByListener == false else { return }

        stack.layoutSubtreeIfNeeded()
        let wanted = max(
            Self.minimumSize.height,
            stack.fittingSize.height + Self.verticalInset * 2)
        guard abs(wanted - window.frame.height) > 1 else { return }

        // Grows upward: the newest line stays where the eye already is.
        var frame = window.frame
        frame.origin.y -= wanted - frame.height
        frame.size.height = wanted
        window.setFrame(frame, display: true)
    }

    /// The most captions kept on screen at once. Past this the oldest drops
    /// off rather than the window growing without end — four is enough to
    /// follow a thought without becoming a wall of text.
    private static let lineCap = 4

    private static let verticalInset: CGFloat = 14
    private static let horizontalInset: CGFloat = 16
}

/// Draws the card the captions sit on.
///
/// Drawn rather than layer-backed: a content view is handed a fresh layer when
/// it becomes the window's, so anything written to the old one is lost — which
/// is how this first appeared almost entirely transparent.
final class CaptionsBackgroundView: DraggableBackgroundView {
    override func draw(_ dirtyRect: NSRect) {
        OverlayPalette.base.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }
}

/// Where the captions window was left, so it comes back there.
///
/// Deliberately untested — a thin `UserDefaults` wrapper.
final class CaptionsPositionPreference {
    private static let key = "CaptionsWindowFrame"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var frame: NSRect? {
        get {
            guard let string = defaults.string(forKey: Self.key) else { return nil }
            let rect = NSRectFromString(string)
            return rect.width > 0 && rect.height > 0 ? rect : nil
        }
        set {
            guard let newValue else { return }
            defaults.set(NSStringFromRect(newValue), forKey: Self.key)
        }
    }
}
