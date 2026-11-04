# Changelog

## 0.1.0

The first release.

- `ChatFrom.start(botId:)` shows the chatbot's bubble on the app's window, in the look set under Deploy, above a tab bar, and out of the keyboard's way. `setBottomInset(_:animated:)` moves it for a bar of the app's own, and `setBubbleHidden(_:)` and `stop()` hide and remove it.
- `ChatFromRow`, `ChatFromCell` and `ChatFromButton` open the chat from a list, and `ChatFrom.open(botId:)` from anything else.
- The chat opens full screen on iPhone and as a card on iPad, with a native header, files, links that open outside the app, and the phone's text size.
- `identify(userId:userToken:)` and `logout()` say who is signed in, so the next person on a shared device does not see the last one's chat.
- `ChatFrom.isSupported` says whether the device can show the chat: iOS 16.4 or later.
