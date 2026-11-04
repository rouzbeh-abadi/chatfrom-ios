import Combine
import UIKit
import WebKit

/// One chatbot's chat page in one web view, kept for the app's run so the chat opens at once and the bubble knows how to look.
@MainActor
final class ChatSession: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        /// The page on screen has said chatfrom:ready.
        case ready
        case failed
    }

    let botId: String
    let pageURL: URL

    /// Made when it is first needed, not when an app starts: making one takes a while.
    private(set) var webViewIfMade: WKWebView?

    var webView: WKWebView {
        if let webViewIfMade { return webViewIfMade }
        let made = makeWebView()
        webViewIfMade = made
        hub.park(self)
        return made
    }

    @Published private(set) var phase: Phase = .idle {
        // While a cover is up, what is under it is not for VoiceOver either: it can be a page that is on its way out.
        didSet { webViewIfMade?.accessibilityElementsHidden = phase != .ready }
    }
    @Published private(set) var config: ChatConfig?
    @Published private(set) var talking = false
    @Published private(set) var isOpen = false

    private unowned let hub: Hub
    /// The document now in the web view has said chatfrom:ready, and not chatfrom:failed: it hears events. A load that is on its way, or that failed, leaves it running until another takes its place.
    private var hears = false
    /// Who that document was last told is using the app.
    private var pagePerson: Person?
    /// Who was in the script when the newest load began, which is who its document starts with.
    private var loadPerson: Person?
    private var latestLoad: WKNavigation?
    /// A load has begun and its document has not replaced the last one. What is heard meanwhile comes from the old document, which must not lift the cover.
    private var awaitingCommit = false
    private var wanted = false
    private var lastOnScreen = Date()
    private var needsReload = false
    private var watchdog: Task<Void, Never>?
    private var deaths: [Date] = []

    /// How long a page may take to say it is ready before the chat offers to try again. A later word from the page still counts.
    private static let readyWait: UInt64 = 20_000_000_000
    /// A page that dies this many times in a minute is left, until someone asks for it or the app comes back.
    private static let deathsBeforeGivingUp = 3

    init(botId: String, baseURL: URL, hub: Hub) {
        self.botId = botId
        self.hub = hub
        pageURL = baseURL.appendingPathComponent("mobile").appendingPathComponent(botId)
        super.init()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Added to, not replacing, the "Mobile/..." it would otherwise end with.
        configuration.applicationNameForUserAgent = "Mobile/15E148 ChatFromSDK-iOS/\(ChatFrom.version)"
        // The page is made for a phone. Left to choose, an iPad shows it as a desktop site, which ignores the text size set on the iPad.
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []
        configuration.userContentController.add(MessageForwarder(self), name: "chatfrom")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        // The chat page is drawn light, whatever the phone is set to.
        webView.overrideUserInterfaceStyle = .light
        webView.isOpaque = false
        webView.backgroundColor = .white
        // The page fills the view and scrolls its own conversation: the view around it stays put.
        let scroll = webView.scrollView
        scroll.backgroundColor = .white
        scroll.isScrollEnabled = false
        scroll.scrollsToTop = false
        scroll.bounces = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = self
        scroll.pinchGestureRecognizer?.isEnabled = false
        KeyboardBar.remove(from: webView)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        return webView
    }

    // MARK: Loading

    /// Soon, but not as the app starts, and not at all until it is in front: it may have been launched in the background for something else.
    func loadSoon() {
        guard phase == .idle, !wanted else { return }
        wanted = true
        guard UIApplication.shared.applicationState != .background else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.load()
        }
    }

    func load() {
        watchdog?.cancel()
        wanted = true
        needsReload = false
        phase = .loading
        loadPerson = hub.person
        installScripts()
        lastOnScreen = Date()
        awaitingCommit = true
        latestLoad = webView.load(URLRequest(url: pageURL))
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.readyWait)
            guard !Task.isCancelled, let self, self.phase == .loading else { return }
            chatLog.notice("The chat page did not say it was ready in time.")
            self.phase = .failed
        }
    }

    /// The page is loaded again if it failed, or if it has not been on screen for a long while, since it reads the chatbot's settings once.
    func refreshIfNeeded(now: Date = Date()) {
        let maxAway = config?.live == false ? min(hub.pageMaxAge, Freshness.closedMaxAway) : hub.pageMaxAge
        if phase == .idle || phase == .failed || needsReload || Freshness.isStale(lastOnScreen: lastOnScreen, now: now, maxAway: maxAway) { load() }
    }

    func appWillEnterForeground() {
        if phase == .idle {
            if wanted { load() }
            return
        }
        refreshIfNeeded()
    }

    func appDidEnterBackground() {
        if isOpen { lastOnScreen = Date() }
    }

    func networkCameBack() {
        if phase == .failed { load() }
    }

    func textSizeChanged() {
        guard webViewIfMade != nil else { return }
        installScripts()
        run(BridgeScript.textSize(hub.textScale) + " " + BridgeScript.dispatch(.textSize))
    }

    // MARK: The person

    private func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(source: BridgeScript.userScript(for: hub.person, page: pageURL), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Nothing added at all at the phone's usual size.
        if hub.textScale != 1 {
            controller.addUserScript(WKUserScript(source: BridgeScript.textSize(hub.textScale), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    /// So a reload finds who it should, even before the page can be told.
    func personChanged() {
        guard webViewIfMade != nil else { return }
        installScripts()
    }

    func tellPagePerson() {
        guard hears, pagePerson != hub.person else { return }
        pagePerson = hub.person
        run(BridgeScript.setPerson(hub.person))
    }

    /// The person is gone from the stored data by now. A document that hears forgets what it holds, even one a failed load has left running under the cover. Any page not ready is loaded afresh.
    func signedOut() {
        if hears {
            pagePerson = nil
            run(BridgeScript.dispatch(.signOut))
        }
        if phase == .loading || phase == .failed { load() }
    }

    // MARK: On screen

    func startNewChat() {
        guard phase == .ready else { return }
        run(BridgeScript.dispatch(.newChat))
    }

    func blurInput() {
        run(BridgeScript.blur)
    }

    func setOpen(_ open: Bool) {
        isOpen = open
        lastOnScreen = Date()
    }

    private func run(_ script: String) {
        webViewIfMade?.evaluateJavaScript(script, completionHandler: nil)
    }

    fileprivate func hear(_ message: WKScriptMessage) {
        // Only the chat page itself, on ChatFrom, may say how the bubble looks or that it is ready: its scheme, host and port.
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == pageURL.scheme, origin.host.lowercased() == pageURL.host?.lowercased(), origin.port == (pageURL.port ?? 0) else { return }
        guard let heard = BridgeMessage(body: message.body) else {
            if let body = message.body as? [String: Any], let bridge = body["bridge"] as? Int, bridge > BridgeMessage.version {
                chatLog.error("The chat page speaks bridge \(bridge, privacy: .public), and this SDK knows \(BridgeMessage.version, privacy: .public). Update the ChatFrom package.")
            }
            return
        }
        switch heard {
        case .config(let config):
            guard !awaitingCommit else { return }
            self.config = config
            if !config.live {
                chatLog.notice("Chatbot \(self.botId, privacy: .public) is not live, or not opened to mobile apps. Turn on Mobile apps under Deploy.")
            }
        case .ready:
            hears = true
            if !awaitingCommit {
                watchdog?.cancel()
                phase = .ready
            }
            if !hub.isForgetting { tellPagePerson() }
        case .talking(let on):
            guard !awaitingCommit else { return }
            talking = on
        case .failed:
            hears = false
            guard !awaitingCommit else { return }
            chatLog.notice("The chat page says it could not load.")
            watchdog?.cancel()
            phase = .failed
        }
    }
}

// MARK: - Where the web view may go

extension ChatSession: WKNavigationDelegate {
    /// A link leaves the app only from a chat someone is looking at. WebKit calls a click from a script a link too, and a page with the chat closed has no business sending anyone anywhere.
    private var someoneCouldHaveTapped: Bool {
        isOpen && UIApplication.shared.applicationState == .active
    }

    // Named outright: a delegate method is optional, so one whose type drifts from the SDK's in another Xcode would
    // otherwise never be called, and the web view would go anywhere with nothing to say so.
    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let decision = LinkPolicy.decide(url: action.request.url, isMainFrame: action.targetFrame?.isMainFrame ?? true, userTapped: action.navigationType == .linkActivated && someoneCouldHaveTapped, page: pageURL)
        if case .openOutside(let url) = decision {
            UIApplication.shared.open(url)
        }
        decisionHandler(decision == .stay ? .allow : .cancel)
    }

    @objc(webView:decidePolicyForNavigationResponse:decisionHandler:)
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            chatLog.notice("The chat page answered \(http.statusCode, privacy: .public).")
            watchdog?.cancel()
            awaitingCommit = false
            phase = .failed
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === latestLoad else { return }
        awaitingCommit = false
        hears = false
        pagePerson = loadPerson
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(navigation, error)
    }

    private func failed(_ navigation: WKNavigation?, _ error: Error) {
        // A load that a newer one took over is not a failure.
        guard navigation === latestLoad, (error as NSError).code != NSURLErrorCancelled else { return }
        // Nothing here for a page's answer, which has said so already and cancelled itself.
        guard phase != .failed else { return }
        chatLog.notice("The chat page could not load: \(error.localizedDescription, privacy: .public)")
        watchdog?.cancel()
        awaitingCommit = false
        phase = .failed
    }

    /// The system ended the page's process, which leaves the view blank. The chat comes back by itself, since storage outlasts it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        hears = false
        awaitingCommit = false
        let now = Date()
        deaths = deaths.filter { now.timeIntervalSince($0) < 60 } + [now]
        if deaths.count >= Self.deathsBeforeGivingUp {
            chatLog.error("The chat page's process keeps ending, so it is not being loaded again for now.")
            watchdog?.cancel()
            phase = .failed
        } else if UIApplication.shared.applicationState == .background {
            needsReload = true
            phase = .loading
        } else {
            load()
        }
    }
}

extension ChatSession: WKUIDelegate {
    /// A link that opens a new window, such as Powered by, opens outside the app.
    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if someoneCouldHaveTapped, let url = action.request.url, LinkPolicy.opensOutside(url) {
            UIApplication.shared.open(url)
        }
        return nil
    }
}

extension ChatSession: UIScrollViewDelegate {
    /// A focused field can ask the view to scroll to it. It is above the keyboard already.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset != .zero { scrollView.contentOffset = .zero }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// A web view puts a bar of up, down and done above the keyboard, for moving through a form. A chat has one box, and the bar makes it feel like a web page.
/// There is no setting for it, so this web view alone gets a subclass of its content view with no bar. If a later iOS builds the view differently, this finds
/// nothing to change and the bar simply shows.
@MainActor
private enum KeyboardBar {
    static func remove(from webView: WKWebView) {
        guard let content = webView.scrollView.subviews.first(where: { String(describing: type(of: $0)).hasPrefix("WKContent") }), let original: AnyClass = object_getClass(content) else { return }
        let name = "ChatFrom_\(NSStringFromClass(original))"
        var subclass: AnyClass? = NSClassFromString(name)
        if subclass == nil, let made = objc_allocateClassPair(original, name, 0) {
            let noBar: @convention(block) (AnyObject) -> UIView? = { _ in nil }
            class_addMethod(made, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(noBar), "@@:")
            objc_registerClassPair(made)
            subclass = made
        }
        if let subclass { object_setClass(content, subclass) }
    }
}

/// The content controller keeps its handler alive, which would otherwise keep the session alive for good.
private final class MessageForwarder: NSObject, WKScriptMessageHandler {
    private weak var session: ChatSession?

    @MainActor init(_ session: ChatSession) {
        self.session = session
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            session?.hear(message)
        }
    }
}
