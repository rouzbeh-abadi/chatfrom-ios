# ChatFrom iOS SDK

The iOS SDK for [ChatFrom](https://chatfrom.io), which builds AI chatbots that answer from your own documents and website. It puts your chatbot inside your own iPhone and iPad app: a chat bubble in the corner, or a row in a list. Tapping it opens the chat, full screen on iPhone and as a card on iPad. People can chat, attach files and carry on where they left off.

The bubble and the header are native, and take their look from what you set under Deploy. The chat itself is ChatFrom's chat page in a web view, so every improvement to it reaches your app without a new release.

The chat needs iOS 16.4 or later. The package links from iOS 15, so an app that still supports older versions can add it: there it shows no bubble, and rows are grey. It needs Swift 5.9 or later.

## Install

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/rouzbeh-abadi/chatfrom-ios`, set **Dependency Rule** to **Up to Next Minor Version**, and add the **ChatFromSDK** library. Before 1.0, a minor version may change the API, which Xcode's default rule would take in. Or in `Package.swift`:

```swift
.package(url: "https://github.com/rouzbeh-abadi/chatfrom-ios", .upToNextMinor(from: "0.2.0")),

// and in your target's dependencies:
.product(name: "ChatFromSDK", package: "chatfrom-ios"),
```

## Before you start

1. In ChatFrom, open your chatbot, go to **Deploy** and turn on **Mobile apps**. Then go live.
2. Copy the chatbot's id from its address in the dashboard.

The [guide on chatfrom.io](https://chatfrom.io/docs/ios) walks through the same steps for chatbot owners.

## Add the bubble

One line, as your app starts:

```swift
import ChatFromSDK

ChatFrom.start(botId: "your-chatbot-id")
```

It works from `application(_:didFinishLaunchingWithOptions:)` or from a SwiftUI `App`'s `init()`. The bubble appears once the chatbot's page has said how it looks, in the colour, icon, size and corner you chose. A chatbot that is not live, or not opened to mobile apps, shows no bubble. A chatbot set to the input bar under Deploy still shows a bubble in an app.

The bubble sits above a tab bar by itself, and steps aside while the keyboard is over it. Screens your app presents cover it, as they cover your other screens. A bar of your own does not move it: for one that comes and goes, such as a player or a timer, call `setBottomInset` as it does, and the bubble glides out of its way.

If your app has its own lock screen, hide the bubble with `setBubbleHidden(true)` until it is unlocked: a lock window at the normal level covers the bubble, but your own code can still open the chat over it. A first-run screen that is your app's root view, rather than presented over it, has the bubble over it too: call `start` once someone is past it, or hide the bubble there.

```swift
ChatFrom.start(botId: "your-chatbot-id", bottomInset: 60) // sit higher, above something of your own
ChatFrom.setBottomInset(110)                              // glide higher, for a bar of yours that has just come up
ChatFrom.setBubbleHidden(true)                            // for a screen where it would be in the way
ChatFrom.stop()                                           // take it away
```

## Or add it to a list

In SwiftUI, in a `List` or a `Form`:

```swift
ChatFromRow(botId: "your-chatbot-id")
ChatFromRow(botId: "your-chatbot-id", title: "Ask our assistant") // looked up in your app's strings, as a Button's title is
```

In a `UITableView`:

```swift
tableView.register(ChatFromCell.self, forCellReuseIdentifier: ChatFromCell.reuseIdentifier)

let cell = tableView.dequeueReusableCell(withIdentifier: ChatFromCell.reuseIdentifier, for: indexPath) as! ChatFromCell
cell.configure(botId: "your-chatbot-id")
```

In a `List` or a `Form` the row takes the list's insets; anywhere else, such as a card in a scroll view, give it your own padding. `ChatFromButton(botId:)` is the same row as a `UIControl`. To open the chat from something of your own, such as a menu item, or a row drawn like your app's other rows:

```swift
ChatFrom.open(botId: "your-chatbot-id")
```

The row goes grey for a chatbot that is not live. You can use the bubble and rows together, and neither needs the other. A row loads the chat page as soon as it is on screen, so the chat opens at once, and it opens the chat on a tap, with no step in between.

On iOS before 16.4, `ChatFrom.isSupported` is false: there is no bubble, rows are grey and `open` does nothing, so hide a button of your own there.

## Say who is using the app

Do this if people sign in to your app. Without it, the next person on a shared device could see the last person's chat.

```swift
// When they sign in, on each launch once you know, and whenever you have a new token.
ChatFrom.identify(userId: user.id, userToken: tokenFromYourServer)

// Whenever your app's own sign-in ends.
ChatFrom.logout()
```

- `userId` is your app's id for the person. It is hashed and stays on the device.
- `userToken` is optional. It is for chatbots whose tools act for the signed-in user, and reaches the tools you marked for it. Get it from your own server, and never sign it on the device. It may hold up to 1024 ASCII letters, digits and `. _ ~ -`; a token with any other character is dropped whole, so Base64 has to be URL-safe, with no padding. A debug build says so in the Console.
- It holds for every chatbot in the app. With chatbots from more than one ChatFrom account, each one's tool servers marked for it get the token.
- A different person from last time starts from nothing, even if nobody signed out.
- A chat begun before signing in carries over to whoever signs in first.

Call `logout()` every time the sign-in ends: when someone signs out, when a session expires or is revoked, and on a launch that finds nobody signed in. With nobody to forget it does nothing, so calling it too often does no harm. It forgets the chat, the visitor id and the token for every chatbot on the device. Stop any token refresh of your own first, and call `identify` for the next person only after it.

A token running out is not a sign-out: just call `identify` again with the new one, and the chat carries on.

If your app ends a session without calling `logout()`, and the next person opens the chat before your app has named them, they will see the last chat. The SDK cannot know the session ended, so this one is yours.

## Questions about subscriptions

With **RevenueCat** connected to the chatbot under Tools, a customer can ask about their own subscription: whether it is active or in a trial, when it renews or ends, a payment that failed, and where to manage it. The chatbot only reads, and only for the customer your app vouches for, never one someone names in the chat. Your app vouches in one of these ways, and ChatFrom checks each on every message:

```swift
// A token for the signed-in customer: from your server, or RevenueCat's own access token.
ChatFrom.identify(userId: user.id, userToken: userToken)

// RevenueCat's anonymous id, for a customer who has not signed in, if the chatbot's owner allowed anonymous ids.
ChatFrom.revenueCatAppUserId = Purchases.shared.isAnonymous ? Purchases.shared.appUserID : nil

// The App Store's own word on the subscriptions, if the owner entered your bundle id. Off unless you turn it on.
ChatFrom.sharesAppStoreSubscriptions = true
```

- **A token from your server** names the customer's RevenueCat app user id in `sub`, signed HS256 with the signing secret the RevenueCat card showed, with an `exp` at most 24 hours away. Sign it on your server, never in the app, and pass it as `userToken`. It also reaches the tool servers marked for the user token.
- **`revenueCatAppUserId`** is passed on only when it is one of RevenueCat's anonymous ids (`$RCAnonymousID:` and 32 hex digits), which nobody can guess. An id you chose could be anyone's, so for a signed-in customer use a token; a debug build says so in the Console. Set it again whenever RevenueCat's id changes. It goes with the person: `logout()` forgets it, and so does `identify` for someone else, since RevenueCat can join an anonymous id to whoever signs in. Set the next customer's after those calls; on a launch, call `logout()` first if nobody is signed in, then set it. A second `logout()` for the same sign-out leaves an id set after the first.
- **`sharesAppStoreSubscriptions`** reads the app's subscriptions with StoreKit 2, asking the person nothing, and passes on what Apple signed, which ChatFrom checks with Apple's own certificate. It reads them again when the app comes to the front and whenever the App Store says one changed, and only on a device that can show the chat. The chat sends them only to a chatbot with the RevenueCat tool on. They are about whoever is signed in to the App Store on the device, which signing out of your app does not change, so `logout()` leaves them. Purchases made with Xcode's StoreKit testing are signed by Xcode, not Apple, so ChatFrom does not take them: try it with a sandbox account.

The [RevenueCat guide on chatfrom.io](https://chatfrom.io/docs/connections/revenuecat) has the owner's side.

## What your app has to do

- **Camera:** on a device with a camera, the file picker can offer to take a photo. Add `NSCameraUsageDescription` to your `Info.plist`, since iOS ends an app that reaches for the camera without it. A debug build reminds you in the Console, as the app first uses the chat.
- **Consent:** the answers come from an AI model through ChatFrom, so Apple's rule on sharing personal data with a third party's AI (App Review Guideline 5.1.2(i)) is yours to meet: say so, and get consent before someone first uses the chat. The bubble and rows load the chat page and open it on a tap, so call `start`, or show a row, only once you have that consent. To ask on the tap itself, use a button of your own that asks first, then calls `ChatFrom.open`.
- **Privacy:** your privacy notice has to cover what people write to the chatbot, and what its tools ask for, such as a name, an email address or a phone number to book a call, and the subscriptions the chat reads when you share them. The SDK's privacy manifest declares these, purchase history among them, so Xcode's privacy report lists them; App Store Connect's privacy answers are yours.
- **App-Bound Domains:** if your `Info.plist` has `WKAppBoundDomains`, add `chatfrom.io` to it. WebKit runs no script in a page outside that list, in any of the app's web views, so the chat could not load. A debug build says so in the Console.
- **Other languages:** the chat's own words are the page's. For the few the SDK draws itself, set `ChatFrom.strings`.

## What it keeps

The chat and a random visitor id are kept in the web view's storage for ChatFrom's site, as they are in a browser, by your **Remember returning visitors** setting under Deploy: across launches when it is on, and for the app's run when it is off. A hash of the person's id sits beside them, to notice when the person changes.

The SDK itself stores two things in `UserDefaults`, in a store of its own: a random value for that hash, and whether someone is signed in. It never stores the token, the RevenueCat id or the App Store's subscriptions.

The web view's storage is the app's default one, shared with your other web views. Clearing all of it, with `WKWebsiteDataStore.default()`, also forgets remembered chats. `stop()` removes the bubble only: the chat page stays loaded for the app's run, for rows and `open`, and `logout()` is what forgets the person.

## Good to know

- **One web view per chatbot**, kept for the app's run, so the chat opens at once and an answer on its way still arrives after the chat is closed. It loads shortly after your app starts, and not during a launch in the background. A page that has been off screen for an hour is loaded again as the app comes back or the chat opens, so your changes under Deploy reach people. The conversation comes back by itself. A chatbot that is closed is looked at again at each launch, and when the app comes back to the front five minutes or more after the last look. An app that stays in front does not look again: after turning on **Mobile apps**, send the app to the background and back.
- **Links** open outside your app, in the browser or the mail app. The web view only ever holds the chat page.
- **Attaching files** depends on your settings under Deploy, as carrying on where someone left off depends on **Remember returning visitors**.
- **No download:** people cannot download the conversation in an app.
- **Light only:** the chat follows your colours, and is light even on a phone in dark mode. Its text grows with the text size set on the iPhone or iPad, up to a point.
- **Failures:** if the page cannot load, the chat offers to try again. It also tries by itself when the network comes back and when the app returns to the foreground. Why it failed is in the Console, under `io.chatfrom.sdk`.
- **Several windows on an iPad:** there is one bubble, on one window, and it stays there while that window is in front. A row opens the chat in its own window. If the chat is open in another, it moves.

## The example apps

`Example/` has two apps. `ChatFromExample` is SwiftUI, with the bubble and a row. `ChatFromExampleUIKit` is UIKit, with a sign-in screen that changes the window's root, and rows for the awkward cases.

```bash
brew install xcodegen
```

```bash
cd Example && xcodegen generate && open ChatFromExample.xcodeproj
```

Put your chatbot's id in `botId` in `Example/App/ExampleApp.swift`, or set `CHATFROM_BOT` in the scheme.

## Tests

```bash
xcodebuild test -scheme ChatFrom -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The UI tests run the SDK in a real app and web view, against a stand-in for the chat page that writes what it hears:

```bash
node Example/TestServer/server.mjs
```

```bash
xcodebuild test -project Example/ChatFromExample.xcodeproj -scheme ChatFromExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

```bash
xcodebuild test -project Example/ChatFromExample.xcodeproj -scheme ChatFromExampleUIKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`Example/UITests/RealPageTests.swift` runs against the real chat page, and says at its top how. Against chatfrom.io its answers use real credits.

## Contributing

Issues and pull requests are welcome. Run the unit tests, and for a change to the bubble or the chat screen the UI tests too (see Tests above), before you send one. To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Licence

MIT. See [LICENSE](LICENSE).
