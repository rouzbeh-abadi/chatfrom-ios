import Combine
import SwiftUI
import UIKit

/// A row that opens the chat, for a cell or anywhere else in your own layout: the chatbot's icon in its colour, the words, and a chevron.
///
/// It goes grey for a chatbot that is not live or not opened to mobile apps, and below iOS 16.4, where the chat cannot run.
@MainActor
public final class ChatFromButton: UIControl {
    /// The chatbot this opens.
    @IBInspectable public var botId: String? {
        didSet {
            if botId != oldValue { connect() }
        }
    }

    /// The words on the row. Left empty, it says "Chat with" and the chatbot's name.
    @IBInspectable public var title: String? {
        didSet { refresh() }
    }

    private let highlight = UIView()
    private let tile = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let chevron = UIImageView()
    private var session: ChatSession?
    private var watching: AnyCancellable?

    public init(botId: String? = nil, title: String? = nil) {
        self.botId = botId
        self.title = title
        super.init(frame: .zero)
        build()
        connect()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
        connect()
    }

    private func build() {
        accessibilityIdentifier = "chatfrom.button"
        isAccessibilityElement = true
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        highlight.backgroundColor = .systemFill
        highlight.isHidden = true
        highlight.isUserInteractionEnabled = false
        tile.layer.cornerRadius = 8
        tile.layer.cornerCurve = .continuous
        tile.isUserInteractionEnabled = false
        icon.contentMode = .scaleAspectFit
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        chevron.tintColor = .tertiaryLabel
        [highlight, tile, icon, label, chevron].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(highlight)
        addSubview(tile)
        tile.addSubview(icon)
        addSubview(label)
        addSubview(chevron)
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 19),
            label.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func connect() {
        watching = nil
        session = nil
        if let botId, Hub.isSupported {
            let session = Hub.shared.session(for: botId)
            self.session = session
            watching = session.$config
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
            if window != nil { session.loadSoon() }
        }
        refresh()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { session?.loadSoon() }
    }

    private func refresh() {
        let config = session?.config
        let closed = config?.live == false || !Hub.isSupported
        let accent = config?.accent ?? ChatColor.defaultAccent
        tile.backgroundColor = closed ? .systemGray3 : ChatColor.color(accent)
        icon.tintColor = closed ? .white : ChatColor.readable(on: accent)
        icon.image = ChatIcon.image(config?.icon ?? ChatIcon.defaultName, size: 19)
        label.text = RowTitle.make(title: title, config: config)
        label.textColor = closed ? .secondaryLabel : .label
        chevron.isHidden = closed
        isEnabled = !closed
        accessibilityLabel = label.text
        accessibilityTraits = closed ? [.button, .notEnabled] : .button
    }

    public override var isHighlighted: Bool {
        didSet { highlight.isHidden = !isHighlighted }
    }

    @objc private func tapped() {
        guard let botId else { return }
        Hub.shared.open(botId: botId, from: window)
    }
}

/// The words on a row: the app's own, or the chatbot's name once its page has said.
private enum RowTitle {
    @MainActor
    static func make(title: String?, config: ChatConfig?) -> String {
        if let title, !title.isEmpty { return title }
        let strings = Hub.shared.strings
        let name = config?.displayName ?? ""
        return name.isEmpty ? strings.chat : ChatFromStrings.named(strings.chatWith, name)
    }
}

/// A table view cell holding a ``ChatFromButton``. Register it, dequeue it, and give it the chatbot.
@MainActor
public final class ChatFromCell: UITableViewCell {
    public static let reuseIdentifier = "ChatFromCell"

    /// The row in the cell, for its title.
    public let button = ChatFromButton()

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        selectionStyle = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    public func configure(botId: String, title: String? = nil) {
        button.botId = botId
        button.title = title
    }
}

/// The same row for SwiftUI, to put in a `List` or a `Form`. A title written as a literal is looked up in your app's strings, as a `Button`'s is.
@MainActor
public struct ChatFromRow: View {
    private let botId: String
    private let title: String?
    private let titleKey: LocalizedStringKey?
    @ObservedObject private var session: ChatSession
    @State private var anchor = WindowAnchor()

    /// The row with the chatbot's name, once its page has said it.
    public init(botId: String) {
        self.init(botId: botId, title: nil, titleKey: nil)
    }

    /// The row with words of your own, looked up in your app's strings.
    public init(botId: String, title: LocalizedStringKey) {
        self.init(botId: botId, title: nil, titleKey: title)
    }

    /// The row with words of your own, shown as they are.
    @_disfavoredOverload
    public init<S: StringProtocol>(botId: String, title: S) {
        self.init(botId: botId, title: String(title), titleKey: nil)
    }

    private init(botId: String, title: String?, titleKey: LocalizedStringKey?) {
        self.botId = botId
        self.title = title
        self.titleKey = titleKey
        session = Hub.shared.session(for: botId)
    }

    public var body: some View {
        let config = session.config
        let closed = config?.live == false || !Hub.isSupported
        let accent = config?.accent ?? ChatColor.defaultAccent
        Button {
            Hub.shared.open(botId: botId, from: anchor.window)
        } label: {
            HStack(spacing: 12) {
                Image(uiImage: ChatIcon.image(config?.icon ?? ChatIcon.defaultName, size: 19))
                    .foregroundColor(closed ? .white : Color(ChatColor.readable(on: accent)))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(closed ? Color(.systemGray3) : Color(ChatColor.color(accent))))
                Group {
                    if let titleKey {
                        Text(titleKey)
                    } else {
                        Text(RowTitle.make(title: title, config: config))
                    }
                }
                .foregroundColor(closed ? .secondary : .primary)
                Spacer(minLength: 8)
                if !closed {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .disabled(closed)
        .accessibilityIdentifier("chatfrom.row")
        .background(WindowReader(anchor: anchor))
        .onAppear {
            if Hub.isSupported { session.loadSoon() }
        }
    }
}

/// Which window a SwiftUI row is in, so the chat opens in that one when an iPad has several.
private final class WindowAnchor {
    weak var window: UIWindow?
}

private struct WindowReader: UIViewRepresentable {
    let anchor: WindowAnchor

    final class Reader: UIView {
        var anchor: WindowAnchor?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            anchor?.window = window
        }
    }

    func makeUIView(context: Context) -> Reader {
        let view = Reader()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.anchor = anchor
        return view
    }

    func updateUIView(_ view: Reader, context: Context) {
        view.anchor = anchor
        anchor.window = view.window
    }
}
