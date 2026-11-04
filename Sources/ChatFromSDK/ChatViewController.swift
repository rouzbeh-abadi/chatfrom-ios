import Combine
import UIKit

/// The chat screen: full screen on iPhone, a card on iPad. The header is native and in the chatbot's colours, the rest is the chat page.
@MainActor
final class ChatViewController: UIViewController {
    /// The header's words grow with the phone's text size as far as the page's do.
    private static let titleMaxScale = Hub.maxTextScale
    let session: ChatSession

    private let headerBackground = UIView()
    private let header = UIView()
    private let hairline = UIView()
    private let avatar = AvatarLabel()
    private let titleLabel = UILabel()
    private let newChatButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let content = UIView()
    private let cover = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let failure = UIStackView()
    private let failureLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var cancellables = Set<AnyCancellable>()
    private var darkStatusBar = true
    private var lastPhase: ChatSession.Phase?
    private var isCard: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    init(session: ChatSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        if UIDevice.current.userInterfaceIdiom == .pad {
            modalPresentationStyle = .formSheet
            preferredContentSize = CGSize(width: 440, height: 720)
        } else {
            // Over the app rather than instead of it, so pulling the header down shows what is underneath.
            modalPresentationStyle = .overFullScreen
            modalPresentationCapturesStatusBarAppearance = true
        }
        overrideUserInterfaceStyle = .light
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        // The app is still underneath, on an iPhone: VoiceOver stays in the chat, and its two-finger scrub closes it.
        view.accessibilityViewIsModal = true
        buildHeader()
        buildContent()
        session.$config.combineLatest(session.$talking)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.applyLook(animated: true) }
            .store(in: &cancellables)
        session.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in self?.applyPhase(phase) }
            .store(in: &cancellables)
        applyLook(animated: false)
        applyPhase(session.phase)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostWebView()
        session.setOpen(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Something on top of the chat, such as the camera from its file picker, leaves it open.
        guard presentedViewController == nil else { return }
        wentAway()
    }

    /// Whether this is still what someone could be looking at. A window that was hidden or replaced takes it away, with nothing to say so.
    var isOnScreen: Bool {
        if isBeingPresented || isBeingDismissed { return true }
        guard let window = viewIfLoaded?.window else { return false }
        return !window.isHidden
    }

    /// The chat is over, by being closed or by its window going. The web view goes back to wait, and the bubble comes back.
    func wentAway() {
        session.setOpen(false)
        Hub.shared.park(session)
        Hub.shared.chatDisappeared(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        darkStatusBar ? .darkContent : .lightContent
    }

    override func accessibilityPerformEscape() -> Bool {
        close()
        return true
    }

    /// Through what presented it, so that anything on top of the chat goes with it.
    func close(completion: (() -> Void)? = nil) {
        session.blurInput()
        view.endEditing(true)
        guard let presenting = presentingViewController else {
            completion?()
            return
        }
        presenting.dismiss(animated: true, completion: completion)
    }

    // MARK: Layout

    private func buildHeader() {
        let strings = Hub.shared.strings
        headerBackground.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = UIColor(white: 0, alpha: 0.1)
        view.addSubview(headerBackground)
        view.addSubview(header)
        view.addSubview(hairline)
        header.accessibilityIdentifier = "chatfrom.header"

        avatar.textAlignment = .center
        // It grows with the phone's text size as the title does, to the same cap, and its circle with it.
        avatar.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold), maximumPointSize: 12 * Self.titleMaxScale)
        avatar.adjustsFontForContentSizeCategory = true
        avatar.layer.masksToBounds = true
        avatar.setContentHuggingPriority(.required, for: .horizontal)
        avatar.setContentCompressionResistancePriority(.required, for: .horizontal)
        avatar.backgroundColor = UIColor(white: 1, alpha: 0.2)
        avatar.isAccessibilityElement = false

        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold), maximumPointSize: 16 * Self.titleMaxScale)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configure(newChatButton, image: ChatIcon.image(shapes: ChatIcon.newChat, size: 22), label: strings.newConversation, identifier: "chatfrom.new", action: #selector(newChatTapped))
        let closeSymbol = UIImage(systemName: isCard ? "xmark" : "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        configure(closeButton, image: closeSymbol, label: strings.closeChat, identifier: "chatfrom.close", action: #selector(closeTapped))

        let buttons = UIStackView(arrangedSubviews: [newChatButton, closeButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.spacing = 0
        // In a row, so a chatbot with no avatar has its title at the edge.
        let name = UIStackView(arrangedSubviews: [avatar, titleLabel])
        name.translatesAutoresizingMaskIntoConstraints = false
        name.spacing = 10
        name.alignment = .center
        [name, buttons].forEach(header.addSubview)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            headerBackground.topAnchor.constraint(equalTo: view.topAnchor),
            headerBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBackground.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            header.topAnchor.constraint(equalTo: guide.topAnchor),
            header.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
            hairline.topAnchor.constraint(equalTo: header.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            name.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            name.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 4),
            buttons.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            buttons.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        if !isCard {
            let pull = UIPanGestureRecognizer(target: self, action: #selector(headerPulled(_:)))
            header.addGestureRecognizer(pull)
        }
    }

    private func configure(_ button: UIButton, image: UIImage?, label: String, identifier: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func buildContent() {
        let strings = Hub.shared.strings
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = .white
        view.addSubview(content)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            // The foot of the safe area, or the top of the keyboard while it is up.
            content.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        cover.translatesAutoresizingMaskIntoConstraints = false
        cover.backgroundColor = .white
        content.addSubview(cover)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        cover.addSubview(spinner)

        failureLabel.text = strings.couldNotLoad
        failureLabel.font = .preferredFont(forTextStyle: .subheadline)
        failureLabel.adjustsFontForContentSizeCategory = true
        failureLabel.textColor = ChatColor.ink.withAlphaComponent(0.7)
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 0
        retryButton.setTitle(strings.tryAgain, for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        retryButton.accessibilityIdentifier = "chatfrom.retry"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        failure.axis = .vertical
        failure.spacing = 12
        failure.alignment = .center
        failure.translatesAutoresizingMaskIntoConstraints = false
        failure.addArrangedSubview(failureLabel)
        failure.addArrangedSubview(retryButton)
        cover.addSubview(failure)

        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: content.topAnchor),
            cover.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            cover.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            failure.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            failure.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: 32),
            failure.trailingAnchor.constraint(equalTo: cover.trailingAnchor, constant: -32),
        ])
    }

    private func hostWebView() {
        let webView = session.webView
        guard webView.superview !== content else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.insertSubview(webView, belowSubview: cover)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: What the page says

    private func applyLook(animated: Bool) {
        let config = session.config
        let live = config?.live == true
        let accent = config?.accent ?? ChatColor.defaultAccent
        let ink = live ? ChatColor.readable(on: accent) : ChatColor.ink
        titleLabel.text = live ? config?.displayName : Hub.shared.strings.chat
        avatar.text = config?.initials
        avatar.isHidden = !live
        darkStatusBar = !live || !ChatColor.readableIsWhite(on: accent)
        let change = {
            self.headerBackground.backgroundColor = live ? ChatColor.color(accent) : .white
            self.hairline.alpha = live ? 0 : 1
            self.titleLabel.textColor = ink
            self.avatar.textColor = ink
            self.newChatButton.tintColor = ink
            self.closeButton.tintColor = ink
            self.newChatButton.alpha = self.session.talking && live ? 1 : 0
            self.newChatButton.isEnabled = self.session.talking && live
            self.setNeedsStatusBarAppearanceUpdate()
        }
        spinner.color = ChatColor.color(accent)
        retryButton.tintColor = ChatColor.color(accent)
        if animated {
            UIView.animate(withDuration: 0.2, animations: change)
        } else {
            change()
        }
    }

    private func applyPhase(_ phase: ChatSession.Phase) {
        defer { lastPhase = phase }
        switch phase {
        case .ready:
            spinner.stopAnimating()
            failure.isHidden = true
            UIView.animate(withDuration: 0.15) { self.cover.alpha = 0 } completion: { _ in
                self.cover.isHidden = self.session.phase == .ready
            }
        case .idle, .loading:
            cover.isHidden = false
            cover.alpha = 1
            failure.isHidden = true
            spinner.startAnimating()
        case .failed:
            cover.isHidden = false
            cover.alpha = 1
            spinner.stopAnimating()
            failure.isHidden = false
            if lastPhase != .failed { UIAccessibility.post(notification: .announcement, argument: Hub.shared.strings.couldNotLoad) }
        }
    }

    // MARK: Actions

    @objc private func closeTapped() {
        close()
    }

    @objc private func newChatTapped() {
        session.startNewChat()
    }

    @objc private func retryTapped() {
        session.load()
    }

    /// Pulling the header down takes the chat away, as a sheet goes.
    @objc private func headerPulled(_ pull: UIPanGestureRecognizer) {
        let y = max(0, pull.translation(in: view).y)
        switch pull.state {
        case .began:
            session.blurInput()
            view.endEditing(true)
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: y)
        case .ended, .cancelled, .failed:
            let speed = pull.velocity(in: view).y
            if pull.state == .ended, y > 140 || speed > 900 {
                let height = view.bounds.height
                UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
                    self.view.transform = CGAffineTransform(translationX: 0, y: height)
                } completion: { _ in
                    self.dismiss(animated: false)
                }
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.view.transform = .identity
                }
            }
        default:
            break
        }
    }
}

/// The chatbot's initials in a circle that grows with them: UIKit sets a new font as the phone's text size changes, and the circle follows from it.
final class AvatarLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let side = (font.pointSize * 2.5).rounded()
        return CGSize(width: side, height: side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
