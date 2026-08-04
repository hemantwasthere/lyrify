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
    private let positionPreference: CaptionsPositionPreference

    init() {
        positionPreference = CaptionsPositionPreference()

        let frame = Self.onScreen(positionPreference.frame) ?? Self.defaultFrame()
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
        window.minSize = NSSize(width: 260, height: 120)

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

        background.addSubview(stack)
        background.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(
                equalTo: background.bottomAnchor, constant: -Self.verticalInset),
            stack.topAnchor.constraint(
                greaterThanOrEqualTo: background.topAnchor, constant: Self.verticalInset),
            statusLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: background.leadingAnchor, constant: 16),
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

    private static func defaultFrame() -> NSRect {
        let size = NSSize(width: 460, height: 200)
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
        for line in captions.lines.suffix(visibleLineCount) {
            let label = NSTextField(wrappingLabelWithString: line.text)
            label.font = .systemFont(ofSize: 15, weight: line.isSettled ? .regular : .medium)
            // A line still being revised is dimmer than one the transcriber has
            // committed to, so the reader can tell what is certain from what is
            // still arriving.
            label.textColor = line.isSettled ? .labelColor : .secondaryLabelColor
            label.isSelectable = false
            label.drawsBackground = false
            label.preferredMaxLayoutWidth = max(stack.bounds.width, 200)
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// How many lines the window has room for.
    ///
    /// Estimated from its height rather than fixed, so growing the window fills
    /// it with more of what was said. Deliberately generous about wrapping: a
    /// long sentence takes two rows, so this errs toward slightly too few
    /// rather than overflowing the top.
    private var visibleLineCount: Int {
        let available = (window.contentView?.bounds.height ?? 200) - Self.verticalInset * 2
        return max(1, Int(available / Self.approximateLineHeight))
    }

    /// One row of text plus the gap beneath it, near enough.
    private static let approximateLineHeight: CGFloat = 27
    private static let verticalInset: CGFloat = 14
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
