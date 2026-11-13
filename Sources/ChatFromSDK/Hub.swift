import Network
import UIKit
import WebKit

/// What the public calls in ChatFrom.swift work through: the chat pages, the person, the bubble and the open chat.
@MainActor
final class Hub {
    static let shared = Hub()

    /// The chat page needs iOS 16.4: it is built for Safari 16.4 and up, and one script it runs does not even parse before that. An app that supports older
    /// versions can still link this package, and there it shows no bubble and grey rows, rather than a page that spends a load to fail every launch.
    static var isSupported: Bool {
        if #available(iOS 16.4, *) { return true }
        return false
    }

    var baseURL = URL(string: "https://chatfrom.io")!
    var pageMaxAge = Freshness.maxAway
    var strings = ChatFromStrings()
    private(set) var person: Person?
    /// What the app shows of its customer's subscriptions, as pages get it.
    private(set) var purchases = Purchases()
    /// Everything a page is told of whoever is using the app.
    var user: AppUser { AppUser(person: person, purchases: purchases) }
    /// A sign-out is removing stored data, and nothing is told anything until that has finished.
    var isForgetting: Bool { forgetting > 0 }

    /// RevenueCat's id for the customer, as the app set it.
    private var revenueCatIdSet: String?
    /// Sign-outs begun in this run, and how many had begun when the id was set: one set after a sign-out began is the next customer's.
    private var signOuts = 0
    private var revenueCatIdSince = 0

    /// As the app set it. Only an anonymous one reaches a page.
    var revenueCatAppUserId: String? {
        get { revenueCatIdSet }
        set {
            guard newValue != revenueCatIdSet else { return }
            revenueCatIdSet = newValue
            revenueCatIdSince = signOuts
            let anonymous = newValue.flatMap { RevenueCatId.isAnonymous($0) ? $0 : nil }
            #if DEBUG
            if newValue != nil, anonymous == nil {
                chatLog.error("revenueCatAppUserId is not one of RevenueCat's anonymous ids, so it was not passed on. For a customer who has signed in, sign a token on your server and pass it to identify(userId:userToken:).")
            }
            #endif
            changePurchases { $0.revenueCatId = anonymous }
        }
    }

    var sharesAppStoreSubscriptions = false {
        didSet {
            guard sharesAppStoreSubscriptions != oldValue else { return }
            if sharesAppStoreSubscriptions {
                readAppStore()
            } else {
                appStoreRead?.cancel()
                appStoreRead = nil
                changePurchases { $0.appStore = [] }
            }
        }
    }

    /// How the App Store's word is read: StoreKit's, or a stand-in in this package's tests, which have no purchase Apple signed.
    var readAppStoreSubscriptions: () async -> [AppStoreProof]? = { await AppStoreSubscriptions.read() }
    private var appStoreRead: Task<Void, Never>?

    private var sessions: [String: ChatSession] = [:]
    private var bubble: BubbleController?
    private var bubbleHidden = false
    private var bubbleInset: CGFloat = 0
    private weak var openChat: ChatViewController?
    private var pendingOpen: (botId: String, origin: UIWindow?)?
    private var openTries = 0
    private var forgetting = 0
    private var waitingForForgetting: [() -> Void] = []
    private let pathMonitor = NWPathMonitor()
    private var networkWasDown = false
    /// Its own store, so an app that clears its defaults does not take away the note that someone still has to be forgotten.
    private let defaults = UserDefaults(suiteName: "io.chatfrom.sdk") ?? .standard

    /// Where a web view waits while its chat is closed. It has to be in a window for its page to keep running, so an answer on its way still arrives, and behind everything so nobody sees it.
    private let parking: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.alpha = 0
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    /// Set when someone is named, and cleared only once their data has been removed. So a sign-out with nobody to forget leaves a chat begun before signing in alone, and one the app did not live to finish is finished by the next.
    private let someoneNamedKey = "someone-named"

    /// How much larger the chat's words can grow with the phone's text size: what the page's layout can take, and the header's with it.
    static let maxTextScale: CGFloat = 1.4

    /// How much larger the chat page's words are, following the phone's text size, within what its layout can take.
    var textScale: CGFloat {
        min(Self.maxTextScale, max(1, UIFontMetrics(forTextStyle: .body).scaledValue(for: 1)))
    }

    private init() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sceneActivated(_:)), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(windowsChanged), name: UIScene.didDisconnectNotification, object: nil)
        center.addObserver(self, selector: #selector(windowsChanged), name: UIScene.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(windowsChanged), name: UIWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowsChanged), name: UIWindow.didBecomeHiddenNotification, object: nil)
        center.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(textSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(up: up) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "io.chatfrom.sdk.network"))
    }

    // MARK: Chat pages

    func session(for botId: String) -> ChatSession {
        if let session = sessions[botId] { return session }
        if sessions.isEmpty { checkTheApp() }
        let session = ChatSession(botId: botId, baseURL: baseURL, hub: self)
        sessions[botId] = session
        return session
    }

    func park(_ session: ChatSession) {
        guard let webView = session.webViewIfMade else { return }
        attachParking()
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.frame = parking.bounds
        parking.addSubview(webView)
    }

    private func attachParking() {
        guard let window = Windows.home(current: parking.window), parking.window !== window else { return }
        parking.frame = window.bounds
        window.insertSubview(parking, at: 0)
    }

    @objc private func sceneActivated(_ note: Notification) {
        // A scene on an external display can come to the front after the app's own, and nobody can tap it.
        if let scene = note.object as? UIWindowScene, scene.session.role == .windowApplication { Windows.lastActivated = scene }
        windowsChanged()
    }

    @objc private func windowsChanged() {
        if let chat = openChat, !chat.isOnScreen { chat.wentAway() }
        attachParking()
        bubble?.attach()
        if let pending = pendingOpen {
            pendingOpen = nil
            open(botId: pending.botId, from: pending.origin)
        }
    }

    @objc private func willEnterForeground() {
        readAppStore()
        sessions.values.forEach { $0.appWillEnterForeground() }
    }

    @objc private func didEnterBackground() {
        sessions.values.forEach { $0.appDidEnterBackground() }
    }

    @objc private func textSizeChanged() {
        sessions.values.forEach { $0.textSizeChanged() }
    }

    private func networkChanged(up: Bool) {
        if up, networkWasDown { sessions.values.forEach { $0.networkCameBack() } }
        networkWasDown = !up
    }

    // MARK: The bubble

    func startBubble(botId: String, bottomInset: CGFloat?) {
        guard Hub.isSupported else { return sayUnsupported() }
        let session = session(for: botId)
        session.loadSoon()
        if bubble?.session !== session {
            bubble?.remove()
            bubble = BubbleController(session: session, hidden: bubbleHidden)
        }
        if let bottomInset { bubbleInset = bottomInset }
        bubble?.setBottomInset(bubbleInset, animated: false)
        bubble?.attach()
    }

    /// Kept, as whether it is hidden is, so an inset set before the bubble starts, or across a stop, is not lost.
    func setBubbleInset(_ inset: CGFloat, animated: Bool) {
        bubbleInset = inset
        bubble?.setBottomInset(inset, animated: animated)
    }

    func stopBubble() {
        bubble?.remove()
        bubble = nil
    }

    func setBubbleHidden(_ hidden: Bool) {
        bubbleHidden = hidden
        bubble?.hiddenByApp = hidden
    }

    /// What a debug build says about the app's Info.plist, once, as the app first uses the chat.
    private func checkTheApp() {
        #if DEBUG
        let info = Bundle.main
        if info.object(forInfoDictionaryKey: "NSCameraUsageDescription") == nil {
            chatLog.notice("Add NSCameraUsageDescription to your Info.plist. The chat's file picker can offer the camera, and iOS ends an app that reaches for it without one.")
        }
        // An app limited to its App-Bound Domains runs no script in a page outside them, in any of its web views, so the chat could not load.
        if let bound = info.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String], let host = baseURL.host?.lowercased(), !bound.contains(where: { $0.lowercased() == host }) {
            chatLog.error("Your Info.plist lists WKAppBoundDomains without \(host, privacy: .public). Add it, or the chat cannot load in this app.")
        }
        #endif
    }

    private var saidUnsupported = false

    private func sayUnsupported() {
        #if DEBUG
        guard !saidUnsupported else { return }
        saidUnsupported = true
        chatLog.notice("The chat needs iOS 16.4 or later. On this device ChatFrom shows no bubble and does not open; ChatFrom.isSupported says so.")
        #endif
    }

    // MARK: The chat

    /// Opens the chat in the window it was asked from, or the one in front. The web view can be in one place at a time, so asked from somewhere else, the chat moves there.
    func open(botId: String, from origin: UIWindow? = nil) {
        guard Hub.isSupported else { return sayUnsupported() }
        let session = session(for: botId)
        if let chat = openChat {
            // On its way out: asked to close again, UIKit would drop it, so this waits until it has gone.
            if chat.isBeingDismissed {
                openLater(botId: botId, from: origin)
                return
            }
            if chat.isOnScreen {
                if chat.session === session, origin == nil || chat.viewIfLoaded?.window?.windowScene === origin?.windowScene { return }
                chat.close { [weak self] in self?.open(botId: botId, from: origin) }
                return
            }
            chat.wentAway()
        }
        guard let window = origin ?? Windows.active(), let root = window.rootViewController else {
            // Asked before the app has a window to show it in, as a link opened at launch is: windowsChanged brings it back.
            pendingOpen = (botId, origin)
            return
        }
        let top = Windows.top(from: root)
        // The app is in the middle of showing or hiding something, or the screen on top is not up yet: UIKit would drop this, so it waits.
        if top.presentedViewController?.isBeingDismissed == true || top.isBeingPresented || top.viewIfLoaded?.window == nil {
            openLater(botId: botId, from: origin)
            return
        }
        openTries = 0
        session.refreshIfNeeded()
        // A purchase made a moment ago is what someone opening the chat is likely to ask about. StoreKit's update streams are left to the
        // app: Apple does not say each listener gets every update, and the SDK must never take one from the app's own.
        readAppStore()
        let chat = ChatViewController(session: session)
        openChat = chat
        top.present(chat, animated: true)
        // UIKit says no without saying so, if something else is on its way up that this could not see.
        if chat.presentingViewController == nil {
            openChat = nil
            openLater(botId: botId, from: origin)
        }
    }

    private func openLater(botId: String, from origin: UIWindow?) {
        guard openTries < 20 else {
            openTries = 0
            chatLog.error("The chat could not open: something else in the app is on screen, or on its way.")
            return
        }
        openTries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.open(botId: botId, from: origin) }
    }

    func close(completion: (() -> Void)?) {
        guard let chat = openChat else {
            completion?()
            return
        }
        chat.close(completion: completion)
    }

    func chatDisappeared(_ chat: ChatViewController) {
        if openChat === chat { openChat = nil }
    }

    // MARK: The person

    func identify(userId: String, userToken: String?) {
        guard !userId.isEmpty else {
            chatLog.error("identify was given an empty userId, so nobody was named.")
            return
        }
        #if DEBUG
        if let userToken, !UserToken.isAccepted(userToken) {
            chatLog.error("This userToken will be dropped: the chat takes up to 1024 letters, digits and . _ ~ - only. Base64 needs to be URL-safe, with no padding.")
        }
        #endif
        let next = Person(userKey: PersonKey.make(userId: userId, salt: PersonKey.salt(in: defaults)), userToken: userToken)
        guard next != person else { return }
        // The RevenueCat id was the last person's: someone else, even without a sign-out between them, starts without it.
        if let last = person, last.userKey != next.userKey { dropRevenueCatId() }
        person = next
        defaults.set(true, forKey: someoneNamedKey)
        userChanged()
    }

    /// So a reload finds who it should, and a page that hears is told now, unless a sign-out is still removing data.
    private func userChanged() {
        sessions.values.forEach { $0.personChanged() }
        if !isForgetting { sessions.values.forEach { $0.tellPagePerson() } }
    }

    private func changePurchases(_ change: (inout Purchases) -> Void) {
        var next = purchases
        change(&next)
        guard next != purchases else { return }
        purchases = next
        userChanged()
    }

    /// The RevenueCat id gone with the person it was for, without a word to the pages: the caller tells them.
    private func dropRevenueCatId() {
        revenueCatIdSet = nil
        purchases.revenueCatId = nil
    }

    /// Reads the App Store's word again, while the app shares it and the chat can be shown. A newer read takes over from one still on its way,
    /// and one that failed keeps what was read before.
    private func readAppStore() {
        guard sharesAppStoreSubscriptions, Hub.isSupported else { return }
        appStoreRead?.cancel()
        let read = readAppStoreSubscriptions
        appStoreRead = Task { [weak self] in
            let proofs = await read()
            guard !Task.isCancelled, let self, self.sharesAppStoreSubscriptions, let proofs else { return }
            self.changePurchases { $0.appStore = proofs }
        }
    }

    func logout(completion: (() -> Void)?) {
        // The RevenueCat id goes at every call, with someone to forget or not: once a customer signs in, RevenueCat can join their anonymous id
        // to them, so it would name them to the next person. The app sets the next customer's after this, and one it set after a sign-out still
        // under way began, with nobody named since, is that next customer's: a second call for the same sign-out leaves it. The App Store's
        // word stays, since it is about the Apple ID on the device, which signing out of the app does not change.
        let forTheNext = isForgetting && person == nil && revenueCatIdSince == signOuts
        let droppedId = revenueCatIdSet != nil && !forTheNext
        if droppedId { dropRevenueCatId() }
        let someone = person != nil || defaults.bool(forKey: someoneNamedKey)
        guard someone || isForgetting else {
            if droppedId { userChanged() }
            completion?()
            return
        }
        if let completion { waitingForForgetting.append(completion) }
        guard someone else {
            // A sign-out is still removing data; the pages hear once it has finished.
            if droppedId { sessions.values.forEach { $0.personChanged() } }
            return
        }
        person = nil
        // Calls while one sign-out is still removing data are part of it, so an id set after the first holds through all of them.
        if !isForgetting { signOuts += 1 }
        forgetting += 1
        // Nothing is told until the data is removed.
        sessions.values.forEach { $0.personChanged() }
        // Removed first, and only then is a running page told, or the removal takes the new visitor id the page has just written.
        removeSiteData { [weak self] removed in
            guard let self else { return }
            self.forgetting -= 1
            guard !self.isForgetting else { return }
            self.sessions.values.forEach { $0.signedOut() }
            // Only once WebKit has said it removed the data: otherwise the next logout removes it again.
            if self.person == nil, removed { self.defaults.set(false, forKey: self.someoneNamedKey) }
            // Whoever signed in while that was happening, and the subscriptions the app still shows, which the page dropped with the person.
            self.sessions.values.forEach { $0.tellPagePerson() }
            let waiting = self.waitingForForgetting
            self.waitingForForgetting = []
            waiting.forEach { $0() }
        }
    }

    /// This site's stored data and nothing else: the store is shared with the app's other web views. WebKit has always answered, but a person
    /// must not stay on a running page if it ever does not, so after a few seconds the page is told regardless, with `removed` false, and the
    /// note that someone was named stays for the next logout.
    private func removeSiteData(completion: @escaping @MainActor (_ removed: Bool) -> Void) {
        var answered = false
        let finish: @MainActor (Bool) -> Void = { removed in
            guard !answered else { return }
            answered = true
            completion(removed)
        }
        let host = baseURL.host?.lowercased() ?? ""
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let ours = records.filter { host == $0.displayName.lowercased() || host.hasSuffix("." + $0.displayName.lowercased()) }
            store.removeData(ofTypes: types, for: ours) {
                MainActor.assumeIsolated { finish(true) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { finish(false) }
        }
    }
}

@MainActor
enum Windows {
    /// The scene last brought to the front, which is the one someone is using when several are.
    weak static var lastActivated: UIWindowScene?

    /// The window of the scene in front that the app's own screens are in. A scene on an external display is not one: it shows what the app sends it, and nobody can tap it.
    static func active() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        let last = lastActivated.flatMap { scene in scene.activationState == .foregroundActive && scene.session.role == .windowApplication ? [scene] : nil } ?? []
        let ordered = last + scenes.filter { $0.activationState == .foregroundActive } + scenes.filter { $0.activationState == .foregroundInactive } + scenes.filter { $0.activationState == .background }
        for scene in ordered {
            let normal = scene.windows.filter { $0.windowLevel == .normal && !$0.isHidden }
            // Not a window of something else's that fills only a corner.
            let filling = normal.filter { $0.bounds.size == scene.coordinateSpace.bounds.size }
            let candidates = filling.isEmpty ? normal : filling
            if let window = candidates.first(where: \.isKeyWindow) ?? candidates.first { return window }
        }
        return nil
    }

    /// The window to be on: the one it is on already, while that is in front. A window that comes up over it is the app's to say about, and may be a lock screen, which a bubble must not follow onto.
    static func home(current: UIWindow?) -> UIWindow? {
        if let current, !current.isHidden, let state = current.windowScene?.activationState, state == .foregroundActive || state == .foregroundInactive { return current }
        return active()
    }

    /// The screen on top, which is what can present something.
    static func top(from root: UIViewController) -> UIViewController {
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
