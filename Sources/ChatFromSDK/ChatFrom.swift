import UIKit

/// ChatFrom's chat in your app.
///
/// Add it as a bubble with `ChatFrom.start(botId:)`, or as a row with ``ChatFromButton``,
/// ``ChatFromCell`` or ``ChatFromRow``. The chat opens full screen on iPhone and as a card
/// on iPad. Tell it who is using the app with ``identify(userId:userToken:)`` and when
/// they have gone with ``logout(completion:)``.
///
/// The chat needs iOS 16.4. On older versions the package still links: there is no bubble, and rows are grey.
@MainActor
public enum ChatFrom {
    public nonisolated static let version = "0.2.0"

    /// The words the SDK draws itself: the rows' default, what VoiceOver says, and what shows when the page cannot load. Set them before anything else here if your app is not in English.
    public static var strings: ChatFromStrings {
        get { Hub.shared.strings }
        set { Hub.shared.strings = newValue }
    }

    /// Where ChatFrom runs. Only for this package's own tests; set it before anything else here.
    @_spi(Testing) public static var baseURL: URL {
        get { Hub.shared.baseURL }
        set { Hub.shared.baseURL = newValue }
    }

    /// How long a page may stay off screen before it is loaded again. Only for this package's own tests, which have no hour to wait.
    @_spi(Testing) public static func setPageMaxAge(_ seconds: TimeInterval) {
        Hub.shared.pageMaxAge = seconds
    }

    /// Whether this device can show the chat: iOS 16.4 or later. Below that, ``start(botId:bottomInset:)`` shows no bubble, ``open(botId:)``
    /// does nothing and rows are grey, so a button of your own can stay hidden.
    public static var isSupported: Bool {
        Hub.isSupported
    }

    /// Shows the chatbot's bubble in the corner its owner chose under Deploy, in the look they chose, once its page has said so.
    /// A chatbot that is not live, or not opened to mobile apps, shows no bubble.
    ///
    /// The bubble sits above a tab bar by itself, and steps aside while the keyboard is over it. Screens your app presents cover it, as they
    /// cover your other screens. There is one bubble, on one window: with several open on an iPad, it stays on the one it is on while that is in front.
    /// - Parameter bottomInset: How much higher to sit, for anything of your own at the foot of the screen. Left out, it is what
    ///   ``setBottomInset(_:animated:)`` or an earlier start set, or nothing at first.
    public static func start(botId: String, bottomInset: CGFloat? = nil) {
        Hub.shared.startBubble(botId: botId, bottomInset: bottomInset)
    }

    /// Moves the bubble up, or back down, for something of your own at the foot of the screen that comes and goes, such as a player or a timer bar.
    /// It glides there, unless the person has Reduce Motion on. It holds across ``start(botId:bottomInset:)`` and ``stop()``, until you set it again.
    public static func setBottomInset(_ inset: CGFloat, animated: Bool = true) {
        Hub.shared.setBubbleInset(inset, animated: animated)
    }

    /// Removes the bubble. A chat that is open stays open, and the chat page stays loaded for the app's run, for rows and ``open(botId:)``.
    /// To forget what the chat keeps about the person, call ``logout(completion:)``.
    public static func stop() {
        Hub.shared.stopBubble()
    }

    /// Hides the bubble or brings it back, for a screen where it would be in the way, such as your own lock screen. It holds across ``start(botId:bottomInset:)`` and ``stop()``.
    public static func setBubbleHidden(_ hidden: Bool) {
        Hub.shared.setBubbleHidden(hidden)
    }

    /// Opens the chat from anything of your own, such as a menu item or a link. Asked before your app has a window, it opens as soon as there is one.
    public static func open(botId: String) {
        Hub.shared.open(botId: botId)
    }

    /// Closes the chat if it is open.
    public static func close(completion: (() -> Void)? = nil) {
        Hub.shared.close(completion: completion)
    }

    /// Says who is using the app, and refreshes their token. Call it when they sign in, on each launch once you know, and when you have a new token.
    ///
    /// A different person from last time starts from nothing, even if nobody signed out. A chat begun before signing in carries over to whoever signs in first.
    /// It holds for every chatbot in the app: with chatbots from more than one ChatFrom account, each one's tool servers marked for it get the token.
    /// - Parameters:
    ///   - userId: Your app's id for this person. It is hashed and stays on the device.
    ///   - userToken: What your own server signed for them, for chatbots whose tools act for the signed-in user, or that tell customers about
    ///     their RevenueCat subscription. Never sign it on the device.
    ///     It may hold up to 1024 ASCII letters, digits and `. _ ~ -`. A token with any other character is dropped whole, so Base64 has to be
    ///     URL-safe, with no padding; a debug build says so in the Console.
    public static func identify(userId: String, userToken: String? = nil) {
        Hub.shared.identify(userId: userId, userToken: userToken)
    }

    /// Forgets the person: their chat, their visitor id, their token and their ``revenueCatAppUserId``, for every chatbot on this device.
    ///
    /// Call it whenever your app's own sign-in ends: signing out, a session that expired or was revoked, or a launch that finds nobody signed in.
    /// With nobody to forget it does nothing, so a chat begun before signing in stays. Stop any token refresh first, and call
    /// ``identify(userId:userToken:)`` for the next person, or set the next ``revenueCatAppUserId``, only after this.
    /// - Parameter completion: Called once it has all been forgotten.
    public static func logout(completion: (() -> Void)? = nil) {
        Hub.shared.logout(completion: completion)
    }

    /// RevenueCat's id for the customer, for a chatbot with the RevenueCat tool whose owner allowed anonymous ids under Tools. Set it to
    /// `Purchases.shared.appUserID`, and again whenever that changes, so the chat can tell the customer about their subscription.
    ///
    /// Only RevenueCat's anonymous ids are passed on, the ones it makes for a customer you have not named, since nobody can guess one. An id
    /// you chose could be anyone's: for a customer who has signed in, your server signs a token for them, and you pass it to
    /// ``identify(userId:userToken:)``. A debug build says so in the Console. ``logout(completion:)`` forgets it.
    public static var revenueCatAppUserId: String? {
        get { Hub.shared.revenueCatAppUserId }
        set { Hub.shared.revenueCatAppUserId = newValue }
    }

    /// Whether the chat may have the App Store's word on your app's subscriptions, for a chatbot with the RevenueCat tool and your app's
    /// bundle id under Tools. Off unless you turn it on.
    ///
    /// The SDK reads the subscriptions with StoreKit 2, asking the person nothing, and passes on what Apple signed, which ChatFrom checks
    /// with Apple's own certificate. So the chat can say when a subscription renews or ends, even while RevenueCat cannot be reached. It reads
    /// them again when the app comes to the front and when the chat opens. They belong to whoever is signed in to the App Store on the device,
    /// which signing out of your app does not change, so ``logout(completion:)`` leaves them.
    public static var sharesAppStoreSubscriptions: Bool {
        get { Hub.shared.sharesAppStoreSubscriptions }
        set { Hub.shared.sharesAppStoreSubscriptions = newValue }
    }
}
