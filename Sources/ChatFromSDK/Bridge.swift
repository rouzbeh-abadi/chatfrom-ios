import CryptoKit
import Foundation

// How the SDK talks to the chat page, /mobile/{id} on ChatFrom. The page's side
// is libs/app-bridge.ts in the app, and what an SDK must do is in the app's
// docs/api.md, Visitors. The SDK sets window.ChatFromApp before the page runs and
// calls the page by dispatching events on the window, once the page has said
// chatfrom:ready. The page tells the SDK things through the `chatfrom` handler.

/// The person using the app, as the page is told. `userKey` says who, `userToken` is what the app's own server signed for them.
struct Person: Equatable {
    let userKey: String
    let userToken: String?
}

/// What the SDK can tell a running page.
enum BridgeEvent: String {
    case newChat = "chatfrom:new-chat"
    case token = "chatfrom:token"
    case signOut = "chatfrom:sign-out"
    /// The text size changed on a running page, which measures again what it measured at the old size, such as the message box.
    case textSize = "chatfrom:text-size"
}

/// What a page tells the SDK.
enum BridgeMessage: Equatable {
    /// The newest bridge this SDK knows. It goes up only when a change would break an SDK already out, so a page on a newer one is not heard, and the chat offers to try again rather than getting something wrong.
    static let version = 1

    case config(ChatConfig)
    case ready
    case talking(Bool)
    case failed

    init?(body: Any) {
        guard let dictionary = body as? [String: Any], let type = dictionary["type"] as? String else { return nil }
        if let bridge = dictionary["bridge"] as? Int, bridge > Self.version { return nil }
        switch type {
        case "chatfrom:config":
            guard let config = ChatConfig(dictionary["config"]) else { return nil }
            self = .config(config)
        case "chatfrom:ready":
            self = .ready
        case "chatfrom:talking":
            self = .talking(dictionary["on"] as? Bool ?? false)
        case "chatfrom:failed":
            self = .failed
        default:
            return nil
        }
    }
}

enum BridgeScript {
    /// Runs before the page's own scripts, and sets the person on this chatbot's page only.
    static func userScript(for person: Person?, page: URL) -> String {
        "if (location.origin + location.pathname === \(quoted(page.absoluteString))) { window.ChatFromApp = \(json(person)); }"
    }

    /// Tells a running page who it is now, or that their token changed.
    static func setPerson(_ person: Person?) -> String {
        "window.ChatFromApp = \(json(person)); \(dispatch(.token))"
    }

    static func dispatch(_ event: BridgeEvent) -> String {
        "window.dispatchEvent(new Event(\"\(event.rawValue)\"));"
    }

    static let blur = "if (document.activeElement) { document.activeElement.blur(); }"

    /// The page's words at the phone's text size. Only the words: scaling the whole page leaves its layout at the old size, with the message box off the screen.
    /// In a style of its own, since anything set on the page's own elements is a difference React finds when it takes the page over.
    static func textSize(_ scale: CGFloat) -> String {
        "(document.getElementById(\"chatfrom-text-size\") || document.head.appendChild(Object.assign(document.createElement(\"style\"), { id: \"chatfrom-text-size\" }))).textContent = \"html { -webkit-text-size-adjust: \(Int((scale * 100).rounded()))% !important; }\";"
    }

    static func json(_ person: Person?) -> String {
        var fields: [String: String] = [:]
        if let person {
            fields["userKey"] = person.userKey
            if let token = person.userToken { fields["userToken"] = token }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]), let quoted = String(data: data, encoding: .utf8) else { return "\"\"" }
        return quoted
    }
}

/// The stand-in for the app's id for a person. The page only compares it, and it stays on the device.
enum PersonKey {
    private static let saltKey = "salt"

    static func make(userId: String, salt: String) -> String {
        SHA256.hash(data: Data("\(salt):\(userId)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// One random salt for this install, so an id that is easy to guess, such as an email, gives a key that is not.
    static func salt(in defaults: UserDefaults) -> String {
        if let salt = defaults.string(forKey: saltKey) { return salt }
        let salt = UUID().uuidString
        defaults.set(salt, forKey: saltKey)
        return salt
    }
}

/// What the page accepts as a user token, as cleanSiteToken in libs/site-token.ts has it. Anything else is dropped there without a word, so a debug build says so here.
enum UserToken {
    static func isAccepted(_ token: String) -> Bool {
        (1...1024).contains(token.count) && token.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._~-".unicodeScalars.contains(scalar))
        }
    }
}

/// Where the web view may go. It holds the chat page and nothing else: every other address, ChatFrom's own included, opens outside the app.
enum LinkPolicy {
    enum Decision: Equatable {
        case stay
        case openOutside(URL)
        case refuse
    }

    static func decide(url: URL?, isMainFrame: Bool, userTapped: Bool, page: URL) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .refuse }
        // A frame inside the page never gets the person: the script that sets them is for the main frame only.
        if !isMainFrame { return ["http", "https", "about"].contains(scheme) ? .stay : .refuse }
        if isPage(url, page: page) { return .stay }
        return userTapped && opensOutside(url) ? .openOutside(url) : .refuse
    }

    static func opensOutside(_ url: URL) -> Bool {
        ["http", "https", "mailto", "tel", "sms"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isPage(_ url: URL, page: URL) -> Bool {
        url.scheme?.lowercased() == page.scheme?.lowercased() && url.host?.lowercased() == page.host?.lowercased() && url.port == page.port && url.path == page.path
    }
}

/// When a page kept for the app's run should be loaded again. It reads the chatbot's settings once, as it loads.
enum Freshness {
    static let maxAway: TimeInterval = 60 * 60
    /// A chatbot that is closed has nothing on screen to tap, so this is how soon someone finds out it has opened.
    static let closedMaxAway: TimeInterval = 5 * 60

    static func isStale(lastOnScreen: Date, now: Date, maxAway: TimeInterval = Freshness.maxAway) -> Bool {
        now.timeIntervalSince(lastOnScreen) >= maxAway
    }
}
