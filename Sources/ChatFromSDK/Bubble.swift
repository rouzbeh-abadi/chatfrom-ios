import Combine
import UIKit

/// The round bubble, or the pill when the owner gave it words, drawn as the widget draws it: its proportions are those in app/w.js/route.ts.
final class BubbleView: UIControl {
    private let icon = UIImageView()
    private let label = UILabel()
    private let row = UIStackView()
    private var heightConstraint: NSLayoutConstraint!
    private var minWidthConstraint: NSLayoutConstraint!
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var iconSizeConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "chatfrom.bubble"
        accessibilityTraits = .button
        isAccessibilityElement = true
        layer.shadowColor = ChatColor.ink.cgColor
        layer.shadowOpacity = 0.32
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 7)

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        icon.contentMode = .scaleAspectFit
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Words too long for the screen are cut, not the bubble pushed off it.
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontForContentSizeCategory = true

        heightConstraint = heightAnchor.constraint(equalToConstant: 56)
        minWidthConstraint = widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor)
        leadingConstraint = row.leadingAnchor.constraint(equalTo: leadingAnchor)
        trailingConstraint = trailingAnchor.constraint(equalTo: row.trailingAnchor)
        iconSizeConstraint = icon.widthAnchor.constraint(equalToConstant: 26)
        NSLayoutConstraint.activate([
            heightConstraint, minWidthConstraint, leadingConstraint, trailingConstraint, iconSizeConstraint,
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ config: ChatConfig) {
        let height = config.bubbleHeight
        let words = config.label.isEmpty ? nil : config.label
        heightConstraint.constant = height
        layer.cornerRadius = height / 2
        backgroundColor = ChatColor.color(config.accent)
        let ink = ChatColor.readable(on: config.accent)
        let iconSize = (height * 0.46).rounded()
        iconSizeConstraint.constant = iconSize
        icon.image = ChatIcon.image(config.icon, size: iconSize)
        icon.tintColor = ink
        label.text = words
        label.isHidden = words == nil
        label.textColor = ink
        let fontSize = (height * 0.28).rounded()
        // It grows with the phone's text size as far as the bubble's height leaves room.
        label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: fontSize, weight: .semibold), maximumPointSize: fontSize * 1.3)
        if words == nil {
            // The icon in the middle of the circle.
            leadingConstraint.constant = (height - iconSize) / 2
            trailingConstraint.constant = (height - iconSize) / 2
        } else {
            leadingConstraint.constant = (height * 0.3).rounded()
            trailingConstraint.constant = (height * 0.38).rounded()
        }
        // A bubble that shows words is named by them, so the name a voice user says is the one on screen.
        accessibilityLabel = words ?? ChatFromStrings.named(Hub.shared.strings.openChatWith, config.displayName)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            }
        }
    }
}

/// Puts the bubble on the app's window, above its screens and below anything it presents.
@MainActor
final class BubbleController {
    let session: ChatSession
    private let view = BubbleView()
    private var sideConstraint: NSLayoutConstraint?
    private var sideIsLeft = false
    private var bottomConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()
    private var watch: Timer?
    private var shown = false
    private var wasOpen = false
    private static let margin: CGFloat = 16

    private(set) var bottomInset: CGFloat = 0

    var hiddenByApp: Bool {
        didSet { refresh() }
    }

    /// The keyboard is over the bubble. From iOS 26 it is see-through, so the bubble would show through it, where it cannot be tapped.
    private var underKeyboard = false {
        didSet { if underKeyboard != oldValue { refresh() } }
    }

    init(session: ChatSession, hidden: Bool) {
        self.session = session
        hiddenByApp = hidden
        view.alpha = 0
        view.isHidden = true
        view.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        session.$config.combineLatest(session.$isOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
        let center = NotificationCenter.default
        center.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: center.publisher(for: UIResponder.keyboardWillHideNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.keyboardMoved(note) }
            .store(in: &cancellables)
        // No look twice a second while the app runs in the background, as an audio or a navigation app can.
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stopWatching() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.shown else { return }
                self.startWatching()
                self.keepPlace(animated: false)
            }
            .store(in: &cancellables)
    }

    /// Moves the bubble for something of the app's own at the foot of the screen, gliding there when asked and while it shows.
    func setBottomInset(_ inset: CGFloat, animated: Bool) {
        bottomInset = inset
        keepPlace(animated: animated)
    }

    func attach() {
        guard let window = Windows.home(current: view.window) else { return }
        if view.superview !== window {
            view.removeFromSuperview()
            sideConstraint = nil
            bottomConstraint = nil
            window.addSubview(view)
            view.widthAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.widthAnchor, constant: -2 * Self.margin).isActive = true
            sendBelowWhatTheAppPresents(in: window)
        }
        keepPlace(animated: false)
    }

    func remove() {
        stopWatching()
        cancellables.removeAll()
        view.removeFromSuperview()
    }

    // MARK: Where it sits

    /// The window's child that holds the app's screens. It is not always the root view itself: iOS can wrap it in views of its own.
    private func screens(in window: UIWindow) -> UIView? {
        guard var view = window.rootViewController?.viewIfLoaded else { return nil }
        while let parent = view.superview, parent !== window {
            view = parent
        }
        return view.superview === window ? view : nil
    }

    private func isPresenting(in window: UIWindow) -> Bool {
        window.rootViewController?.presentedViewController != nil
    }

    /// Right above the app's screens, so what it presents goes over the bubble, as it goes over them. While it is presenting something, at the very back: a screen that fills the
    /// window can take the app's screens out, or put them in with itself, so nothing else here is sure to be under it. stayAboveTheScreens brings the bubble back afterwards.
    private func sendBelowWhatTheAppPresents(in window: UIWindow) {
        if isPresenting(in: window) {
            window.sendSubviewToBack(view)
        } else if let screens = screens(in: window), screens !== view {
            window.insertSubview(view, aboveSubview: screens)
        }
    }

    /// A new root view goes on top of what the window holds, and nothing says so. Anything of the app's that is above the bubble already stays there.
    private func stayAboveTheScreens(in window: UIWindow) {
        guard !isPresenting(in: window), let screens = screens(in: window), let mine = window.subviews.firstIndex(of: view), let theirs = window.subviews.firstIndex(of: screens), mine < theirs else { return }
        window.insertSubview(view, aboveSubview: screens)
    }

    private func keepPlace(animated: Bool) {
        guard let window = view.superview as? UIWindow else { return }
        stayAboveTheScreens(in: window)
        let guide = window.safeAreaLayoutGuide
        let left = session.config?.position == .left
        if sideConstraint == nil || left != sideIsLeft {
            sideConstraint?.isActive = false
            // Left and right as the owner set them, whichever way the phone's language runs.
            sideConstraint = left
                ? view.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: Self.margin)
                : guide.rightAnchor.constraint(equalTo: view.rightAnchor, constant: Self.margin)
            sideConstraint?.isActive = true
            sideIsLeft = left
        }
        let bottom = Self.margin + bottomInset + tabBarOverlap(in: window)
        if let constraint = bottomConstraint {
            let change = bottom - constraint.constant
            guard change != 0 else { return }
            constraint.constant = bottom
            if animated, shown, !UIAccessibility.isReduceMotionEnabled {
                // The bubble alone: laying out the window here would animate whatever else the app has waiting.
                view.transform = CGAffineTransform(translationX: 0, y: change)
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.view.transform = .identity
                }
            }
        } else {
            bottomConstraint = guide.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: bottom)
            bottomConstraint?.isActive = true
        }
    }

    /// How far a tab bar reaches above the foot of the safe area. On an iPad it can sit at the top, and then it is not in the way.
    private func tabBarOverlap(in window: UIWindow) -> CGFloat {
        guard let bar = visibleTabBar(from: window.rootViewController) else { return 0 }
        let frame = bar.convert(bar.bounds, to: window)
        guard frame.maxY >= window.bounds.height - 40 else { return 0 }
        return max(0, window.bounds.height - window.safeAreaInsets.bottom - frame.minY)
    }

    private func visibleTabBar(from controller: UIViewController?) -> UITabBar? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController, !tabs.tabBar.isHidden, tabs.tabBar.window != nil { return tabs.tabBar }
        for child in controller.children {
            if let bar = visibleTabBar(from: child) { return bar }
        }
        return nil
    }

    /// While it shows, a look twice a second. Nothing tells a bubble that a tab bar has come or gone, or that the app has changed its root.
    private func startWatching() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepPlace(animated: true) }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .default)
        watch = timer
    }

    private func stopWatching() {
        watch?.invalidate()
        watch = nil
    }

    // MARK: Whether it shows

    /// Whether the keyboard covers the bubble. Not any keyboard: on an iPad a floating one, or the bar a hardware keyboard leaves, can be somewhere else.
    private func keyboardMoved(_ note: Notification) {
        guard note.name != UIResponder.keyboardWillHideNotification else {
            underKeyboard = false
            return
        }
        guard let window = view.window, let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        underKeyboard = end.intersects(view.convert(view.bounds, to: window.screen.coordinateSpace))
    }

    private func refresh() {
        let config = session.config
        let visible = config?.live == true && !session.isOpen && !hiddenByApp && !underKeyboard
        let closedJustNow = wasOpen && !session.isOpen
        wasOpen = session.isOpen
        if let config, config.live {
            view.apply(config)
            keepPlace(animated: false)
        }
        guard visible != shown else { return }
        shown = visible
        let still = UIAccessibility.isReduceMotionEnabled
        if visible {
            startWatching()
            view.isHidden = false
            if !still { view.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.7, y: 0.7) }
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.view.alpha = 1
                self.view.transform = .identity
            }
            // VoiceOver goes back to where it came from.
            if closedJustNow { UIAccessibility.post(notification: .layoutChanged, argument: view) }
        } else {
            stopWatching()
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
                self.view.alpha = 0
                if !still { self.view.transform = CGAffineTransform(scaleX: 0.7, y: 0.7) }
            } completion: { _ in
                if !self.shown { self.view.isHidden = true }
            }
        }
    }

    @objc private func tapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Hub.shared.open(botId: session.botId, from: view.window)
    }
}
