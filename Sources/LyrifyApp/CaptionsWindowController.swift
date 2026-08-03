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
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let positionPreference: CaptionsPositionPreference

    init() {
        positionPreference = CaptionsPositionPreference()

        let frame = positionPreference.frame ?? Self.defaultFrame()
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

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(scrollView)
        background.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: background.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            statusLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: background.leadingAnchor, constant: 16),
        ])

        window.contentView = background
        observeFrameChanges()
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
            scrollView.isHidden = true
            return
        }

        statusLabel.isHidden = true
        scrollView.isHidden = false

        for line in captions.lines {
            let label = NSTextField(wrappingLabelWithString: line.text)
            label.font = .systemFont(ofSize: 15, weight: line.isSettled ? .regular : .medium)
            // A line still being revised is dimmer than one the transcriber has
            // committed to, so the reader can tell what is certain from what is
            // still arriving.
            label.textColor = line.isSettled ? .labelColor : .secondaryLabelColor
            label.isSelectable = false
            label.drawsBackground = false
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }

        stack.layoutSubtreeIfNeeded()
        // Follow along: the newest line is the one worth seeing.
        if let documentView = scrollView.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.maxY))
        }
    }
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
