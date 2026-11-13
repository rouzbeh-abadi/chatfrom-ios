import ChatFromSDK
import SwiftUI
import UIKit

// A small shop with ChatFrom in it, both ways: the bubble on every screen, and a
// row under Account. Set your chatbot's id in `botId`, and turn on Mobile apps for
// it under Deploy. The tests point this at Example/TestServer with the environment.

private let launchSettings = ProcessInfo.processInfo.environment
private let botId = launchSettings["CHATFROM_BOT"] ?? "your-chatbot-id"

@main
struct ExampleApp: App {
    init() {
        TestHooks.apply(launchSettings)
        if launchSettings["CHATFROM_NO_BUBBLE"] == nil {
            ChatFrom.start(botId: botId)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootScreen()
        }
    }
}

/// With CHATFROM_GATE set, a screen before the tabs, as an app with a sign-in has: SwiftUI swaps it for the tabs with no change of the window's root.
struct RootScreen: View {
    @State private var past = launchSettings["CHATFROM_GATE"] == nil

    var body: some View {
        if past {
            TabView {
                NavigationView { ShopScreen() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Shop", systemImage: "bag") }
                NavigationView { AccountScreen() }
                    .navigationViewStyle(.stack)
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
        } else {
            Button("Past the gate") { past = true }
        }
    }
}

struct ShopScreen: View {
    private let products = ["Stoneware mug", "Linen apron", "Oak board", "Ceramic bowl", "Enamel jug", "Wool throw", "Copper pan", "Glass carafe", "Rattan tray", "Beeswax candle"]

    var body: some View {
        List(products, id: \.self) { product in
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product).font(.body.weight(.medium))
                    Text("In stock").font(.footnote).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Shop")
    }
}

struct AccountScreen: View {
    @State private var signedIn = "Nobody"
    @State private var bubble = launchSettings["CHATFROM_NO_BUBBLE"] == nil
    @State private var signedOutCount = 0
    @State private var sharesAppStore = false

    var body: some View {
        Form {
            Section("Help") {
                ChatFromRow(botId: botId)
                NavigationLink("In a UIKit table") { TableScreen().navigationTitle("Help") }
            }
            Section("Signed in as \(signedIn)") {
                Button("Sign in as Sara") {
                    ChatFrom.identify(userId: "sara@example.com", userToken: "token-sara")
                    signedIn = "Sara"
                }
                Button("Sign in as Tom") {
                    ChatFrom.identify(userId: "tom@example.com", userToken: "token-tom")
                    signedIn = "Tom"
                }
                Button("Refresh the token") {
                    if signedIn == "Sara" { ChatFrom.identify(userId: "sara@example.com", userToken: "token-sara-2") }
                }
                Button("Sign out") {
                    ChatFrom.logout {
                        signedOutCount += 1
                    }
                    signedIn = "Nobody"
                }
                // The next person in the same moment, as an app that switches accounts does.
                Button("Switch to Tom") {
                    ChatFrom.logout()
                    ChatFrom.identify(userId: "tom@example.com", userToken: "token-tom")
                    signedIn = "Tom"
                }
                // Killed before the sign-out can finish, as iOS can do to an app going to the background.
                Button("Sign out and quit") {
                    ChatFrom.logout()
                    exit(0)
                }
                if signedOutCount > 0 {
                    Text("Signed out \(signedOutCount) time\(signedOutCount == 1 ? "" : "s")")
                }
            }
            Section("Bubble") {
                Toggle("Show the bubble", isOn: $bubble)
                    .onChange(of: bubble) { on in
                        ChatFrom.setBubbleHidden(!on)
                    }
            }
            if UIApplication.shared.supportsMultipleScenes {
                Section("Windows") {
                    Button("Open another window") {
                        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
                    }
                }
            }
            // Last, so the rows the other tests tap stay where they were.
            // For a chatbot with the RevenueCat tool: in an app of your own, the id is Purchases.shared.appUserID.
            Section("Subscriptions") {
                Button("Use an anonymous RevenueCat id") {
                    ChatFrom.revenueCatAppUserId = "$RCAnonymousID:" + String(repeating: "0123abcd", count: 4)
                }
                Button("Use a RevenueCat id of the app's own") {
                    ChatFrom.revenueCatAppUserId = "user-42"
                }
                Toggle("Share App Store subscriptions", isOn: $sharesAppStore)
                    .onChange(of: sharesAppStore) { on in
                        ChatFrom.sharesAppStoreSubscriptions = on
                    }
            }
        }
        .navigationTitle("Account")
    }
}

/// The row in a plain table view, for an app built with UIKit.
struct TableScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITableViewController { TableController(style: .insetGrouped) }
    func updateUIViewController(_ controller: UITableViewController, context: Context) {}
}

final class TableController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(ChatFromCell.self, forCellReuseIdentifier: ChatFromCell.reuseIdentifier)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatFromCell.reuseIdentifier, for: indexPath)
        (cell as? ChatFromCell)?.configure(botId: botId)
        return cell
    }
}
