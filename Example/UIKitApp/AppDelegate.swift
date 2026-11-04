import ChatFromSDK
import UIKit

// An app built with UIKit, with a sign-in screen that gives way to tabs by changing
// the window's root. It is here for what that does to a bubble. The tests point it
// at Example/TestServer. It has scenes because iOS 27 ends an app built with its SDK
// that has none.

private let settings = ProcessInfo.processInfo.environment
let botId = settings["CHATFROM_BOT"] ?? "your-chatbot-id"
private let secondBotId = "second-bot"

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TestHooks.apply(settings)
        if settings["CHATFROM_GERMAN"] != nil {
            var strings = ChatFromStrings()
            strings.chatWith = "Mit {name} chatten"
            ChatFrom.strings = strings
        }
        if settings["CHATFROM_HIDE_FIRST"] != nil {
            ChatFrom.setBubbleHidden(true)
        }
        // Before there is a window, as an app does when it sets up its SDKs first.
        ChatFrom.start(botId: botId, bottomInset: settings["CHATFROM_INSET"].flatMap(Double.init).map { CGFloat($0) } ?? 0)
        // A link that opens the app and asks for the chat, before there is a window to show it in.
        if settings["CHATFROM_OPEN_AT_LAUNCH"] != nil {
            ChatFrom.open(botId: botId)
        }
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = SignInController { [weak window] in
            window?.rootViewController = MainTabs()
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class SignInController: UIViewController {
    private let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system)
        button.setTitle("Continue", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func tapped() {
        onContinue()
    }
}

final class MainTabs: UITabBarController {
    /// This app holds its main screens upright, as many do, and the chat should follow.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let help = UINavigationController(rootViewController: HelpController(style: .insetGrouped))
        help.tabBarItem = UITabBarItem(title: "Help", image: UIImage(systemName: "questionmark.circle"), tag: 0)
        let other = UIViewController()
        other.view.backgroundColor = .systemBackground
        other.tabBarItem = UITabBarItem(title: "Other", image: UIImage(systemName: "square"), tag: 1)
        viewControllers = [help, other]
    }
}

final class HelpController: UITableViewController {
    private let rows = ["Open from code", "Show a sheet", "Show a full screen", "Stop the bubble", "Hide the bubble", "Show the bubble", "Open two chatbots", "Close then open again", "Close with something on top", "Replace the window with the chat open", "Show a lock window", "Lift the bubble", "Lower the bubble", "Close and at once open another"]

    /// A window of the app's own that came up over the others, kept here so it stays.
    private var lockWindow: UIWindow?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Help"
        tableView.register(ChatFromCell.self, forCellReuseIdentifier: ChatFromCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        // A field of the app's own, for what its keyboard does to the bubble.
        let note = UITextField(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        note.placeholder = "A note of your own"
        note.accessibilityIdentifier = "note"
        note.borderStyle = .roundedRect
        note.returnKeyType = .done
        note.addTarget(note, action: #selector(UIResponder.resignFirstResponder), for: .editingDidEndOnExit)
        tableView.tableHeaderView = note
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatFromCell.reuseIdentifier, for: indexPath) as! ChatFromCell
            cell.configure(botId: botId, title: "Ask our assistant")
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        cell.textLabel?.text = rows[indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        switch rows[indexPath.row] {
        case "Open from code":
            ChatFrom.open(botId: botId)
        case "Show a sheet":
            present(SheetController(), animated: true)
        case "Show a full screen":
            let screen = SheetController()
            screen.modalPresentationStyle = .fullScreen
            present(screen, animated: true)
        case "Stop the bubble":
            ChatFrom.stop()
        case "Hide the bubble":
            ChatFrom.setBubbleHidden(true)
        case "Show the bubble":
            ChatFrom.setBubbleHidden(false)
        case "Open two chatbots":
            ChatFrom.open(botId: botId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ChatFrom.open(botId: secondBotId) }
        case "Close then open again":
            ChatFrom.open(botId: botId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                ChatFrom.close { ChatFrom.open(botId: botId) }
            }
        case "Close with something on top":
            ChatFrom.open(botId: botId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                var top: UIViewController? = self?.view.window?.rootViewController
                while let presented = top?.presentedViewController { top = presented }
                top?.present(SheetController(), animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ChatFrom.close() }
            }
        case "Replace the window with the chat open":
            ChatFrom.open(botId: botId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let old = self?.view.window, let scene = old.windowScene else { return }
                let window = UIWindow(windowScene: scene)
                window.rootViewController = MainTabs()
                window.makeKeyAndVisible()
                old.isHidden = true
                (scene.delegate as? SceneDelegate)?.window = window
            }
        case "Close and at once open another":
            ChatFrom.open(botId: botId)
            // Asked while the first is still on its way out, not in close's completion.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                ChatFrom.close()
                ChatFrom.open(botId: secondBotId)
            }
        case "Lift the bubble":
            ChatFrom.setBottomInset(80)
        case "Lower the bubble":
            ChatFrom.setBottomInset(0)
        case "Show a lock window":
            guard let scene = view.window?.windowScene else { return }
            let window = UIWindow(windowScene: scene)
            let lock = LockController()
            lock.onUnlock = { [weak self] in
                self?.lockWindow?.isHidden = true
                self?.lockWindow = nil
                self?.view.window?.makeKey()
            }
            window.rootViewController = lock
            window.makeKeyAndVisible()
            lockWindow = window
        default:
            break
        }
    }
}

/// An app's own lock screen, in a window of its own at the normal level.
final class LockController: UIViewController {
    var onUnlock: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let unlock = UIButton(type: .system)
        unlock.setTitle("Unlock", for: .normal)
        unlock.addTarget(self, action: #selector(unlockTapped), for: .touchUpInside)
        unlock.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unlock)
        NSLayoutConstraint.activate([
            unlock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unlock.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func unlockTapped() {
        onUnlock?()
    }
}

/// A screen of the app's own that the app presented, with the row in it.
final class SheetController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let row = ChatFromButton(botId: botId)
        let done = UIButton(type: .system)
        done.setTitle("Done with the sheet", for: .normal)
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        [row, done].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            done.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 24),
            done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
