# Changelog

## 0.2.1

- The header shows the chatbot's own picture, when it has one under Deploy, Appearance, in place of its initials, on white. It is loaded as the chat page loads, before the chat opens, and a new picture takes the old one's place without the initials showing between them.
- The picture is loaded only from its own address on the chat page's site, with no cookie or stored credential of the app's, and kept in a cache of the SDK's own in the app's Caches folder. A PNG, JPEG or WebP is drawn at the header's size, off the main thread; anything else, or one that says it is larger than 2048 pixels a side, is never unpacked.

## 0.2.0

- For a chatbot with the RevenueCat tool, a customer can ask about their own subscription. `ChatFrom.revenueCatAppUserId` passes on RevenueCat's anonymous id, and `ChatFrom.sharesAppStoreSubscriptions` the App Store's signed word on the app's subscriptions, read with StoreKit 2. A token from your server, passed to `identify(userId:userToken:)`, works for a signed-in customer.
- `logout()` also forgets the RevenueCat id, each time it is called, and `identify` for someone else does too.
- The privacy manifest declares purchase history.

## 0.1.0

The first release.

- `ChatFrom.start(botId:)` shows the chatbot's bubble on the app's window, in the look set under Deploy, above a tab bar, and out of the keyboard's way. `setBottomInset(_:animated:)` moves it for a bar of the app's own, and `setBubbleHidden(_:)` and `stop()` hide and remove it.
- `ChatFromRow`, `ChatFromCell` and `ChatFromButton` open the chat from a list, and `ChatFrom.open(botId:)` from anything else.
- The chat opens full screen on iPhone and as a card on iPad, with a native header, files, links that open outside the app, and the phone's text size.
- `identify(userId:userToken:)` and `logout()` say who is signed in, so the next person on a shared device does not see the last one's chat.
- `ChatFrom.isSupported` says whether the device can show the chat: iOS 16.4 or later.
