@_spi(Testing) import ChatFromSDK
import Foundation

// For the UI tests alone, which point this app at Example/TestServer. An app of
// your own needs none of it, and what this file imports is not the SDK's API.
@MainActor
enum TestHooks {
    static func apply(_ settings: [String: String]) {
        if let base = settings["CHATFROM_BASE_URL"], let url = URL(string: base) {
            ChatFrom.baseURL = url
        }
        if let age = settings["CHATFROM_MAX_AGE"].flatMap(TimeInterval.init) {
            ChatFrom.setPageMaxAge(age)
        }
        // Apple's signed word, stood in for: only a purchase Apple signed holds at ChatFrom, and a simulator has none.
        if settings["CHATFROM_FAKE_APP_STORE"] != nil {
            ChatFrom.setAppStoreReader { [(transaction: "jws-from-the-test", renewal: "jws-renewal-from-the-test")] }
        }
    }
}
