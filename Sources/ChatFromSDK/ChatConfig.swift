import OSLog
import UIKit

/// How a chatbot looks, as its page says. A chatbot that is not live says only that, so the rest has its defaults.
struct ChatConfig: Equatable {
    enum Position: String { case left, right }

    let live: Bool
    let displayName: String
    let accent: String
    let position: Position
    let icon: String
    let label: String
    /// The bubble's height in points, as the widget has them (BUBBLE_SIZES in libs/widget-icons.ts).
    let bubbleHeight: CGFloat

    init?(_ raw: Any?) {
        guard let raw = raw as? [String: Any], let live = raw["live"] as? Bool else { return nil }
        self.live = live
        displayName = (raw["display_name"] as? String) ?? ""
        accent = raw["accent"] as? String ?? ChatColor.defaultAccent
        position = Position(rawValue: raw["position"] as? String ?? "") ?? .right
        icon = raw["icon"] as? String ?? ChatIcon.defaultName
        label = raw["label"] as? String ?? ""
        switch raw["bubble_size"] as? String {
        case "small": bubbleHeight = 48
        case "large": bubbleHeight = 64
        default: bubbleHeight = 56
        }
    }

    /// As the web chat shows them in its header: the first letters of the first two words.
    var initials: String {
        let letters = displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap { $0.first?.uppercased() }.joined()
        return letters.isEmpty ? "CF" : letters
    }
}

enum ChatColor {
    static let defaultAccent = "#570DF8"
    /// The dark text colour, #0F172A.
    static let ink = UIColor(red: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1)

    static func components(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let n = Int(digits, radix: 16) else { return nil }
        return (CGFloat(n >> 16) / 255, CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255)
    }

    static func color(_ hex: String) -> UIColor {
        let c = components(hex) ?? components(defaultAccent)!
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    /// White or the dark text colour, whichever reads better on a colour, as readableOn in libs/widget-icons.ts decides.
    static func readableIsWhite(on hex: String) -> Bool {
        guard let c = components(hex) else { return true }
        let linear = [c.r, c.g, c.b].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return 1.05 / (luminance + 0.05) >= (luminance + 0.05) / (0.00882 + 0.05)
    }

    static func readable(on hex: String) -> UIColor {
        readableIsWhite(on: hex) ? .white : ink
    }
}

/// The words the SDK draws itself, in English unless you set your own with ``ChatFrom/strings``. `{name}` becomes the chatbot's name.
///
/// The chat's own words are the page's, and follow the chatbot's language.
public struct ChatFromStrings: Sendable, Equatable {
    /// A row, or the header, before the chatbot's name is known.
    public var chat = "Chat"
    /// A row, once the chatbot's name is known.
    public var chatWith = "Chat with {name}"
    /// What VoiceOver says for the bubble.
    public var openChatWith = "Open chat with {name}"
    /// What VoiceOver says for the header's close button.
    public var closeChat = "Close the chat"
    /// What VoiceOver says for the header's new conversation button.
    public var newConversation = "Start a new conversation"
    /// When the page could not load.
    public var couldNotLoad = "The chat could not load just now."
    /// The button under that.
    public var tryAgain = "Try again"

    public init() {}

    static func named(_ template: String, _ name: String) -> String {
        template.replacingOccurrences(of: "{name}", with: name)
    }
}

/// What the SDK has to say to a developer, in the Console under io.chatfrom.sdk. Never a token or who someone is.
let chatLog = Logger(subsystem: "io.chatfrom.sdk", category: "chat")
