import JavaScriptCore
import UIKit
import XCTest
@testable import ChatFromSDK

final class BridgeMessageTests: XCTestCase {
    func testReadsWhatThePageSays() {
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:ready", "bridge": 1]), .ready)
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:failed", "bridge": 1]), .failed)
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:talking", "on": true, "bridge": 1]), .talking(true))
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:talking", "on": false, "bridge": 1]), .talking(false))
    }

    func testDoesNotHearAPageOnANewerBridge() {
        XCTAssertNil(BridgeMessage(body: ["type": "chatfrom:ready", "bridge": BridgeMessage.version + 1]))
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:ready", "bridge": BridgeMessage.version]), .ready)
        XCTAssertEqual(BridgeMessage(body: ["type": "chatfrom:ready"]), .ready)
    }

    func testIgnoresWhatItDoesNotKnow() {
        XCTAssertNil(BridgeMessage(body: ["type": "chatfrom:later", "bridge": 1]))
        XCTAssertNil(BridgeMessage(body: "chatfrom:ready"))
        XCTAssertNil(BridgeMessage(body: ["type": "chatfrom:config"]))
    }

    func testAChatbotThatIsNotLiveSaysOnlyThat() throws {
        let message = try XCTUnwrap(BridgeMessage(body: ["type": "chatfrom:config", "config": ["id": "bot", "live": false]]))
        guard case .config(let config) = message else { return XCTFail("not a config") }
        XCTAssertFalse(config.live)
        XCTAssertEqual(config.accent, ChatColor.defaultAccent)
        XCTAssertEqual(config.position, .right)
        XCTAssertEqual(config.bubbleHeight, 56)
    }

    func testALiveChatbotsLook() throws {
        let raw: [String: Any] = ["live": true, "display_name": "Lumen Ceramics", "accent": "#2563EB", "position": "left", "icon": "mail", "label": "Ask us", "bubble_size": "large"]
        let config = try XCTUnwrap(ChatConfig(raw))
        XCTAssertEqual(config.displayName, "Lumen Ceramics")
        XCTAssertEqual(config.initials, "LC")
        XCTAssertEqual(config.position, .left)
        XCTAssertEqual(config.icon, "mail")
        XCTAssertEqual(config.label, "Ask us")
        XCTAssertEqual(config.bubbleHeight, 64)
    }

    func testInitialsAsTheWebChatHasThem() throws {
        XCTAssertEqual(try XCTUnwrap(ChatConfig(["live": true, "display_name": "acme"])).initials, "A")
        XCTAssertEqual(try XCTUnwrap(ChatConfig(["live": true, "display_name": "  one two three "])).initials, "OT")
        XCTAssertEqual(try XCTUnwrap(ChatConfig(["live": true, "display_name": ""])).initials, "CF")
    }
}

final class BridgeScriptTests: XCTestCase {
    private let page = URL(string: "https://chatfrom.io/mobile/bot-1")!

    /// Runs a script as the page would, with this address, and gives back what it left on the window.
    private func run(_ script: String, origin: String = "https://chatfrom.io", path: String = "/mobile/bot-1") throws -> JSValue {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("var events = []; var window = { dispatchEvent: function (e) { events.push(e.type); } }; function Event(type) { this.type = type; } var location = { origin: \(json(origin)), pathname: \(json(path)) };")
        context.evaluateScript(script)
        XCTAssertNil(failure)
        return try XCTUnwrap(context.objectForKeyedSubscript("window"))
    }

    private func json(_ text: String) -> String {
        "\"\(text)\""
    }

    func testSetsThePersonBeforeThePageRunsOnThatChatbotsPageOnly() throws {
        let script = BridgeScript.userScript(for: AppUser(person: Person(userKey: "abc", userToken: "t1")), page: page)
        let onThePage = try run(script).objectForKeyedSubscript("ChatFromApp")
        XCTAssertEqual(onThePage?.objectForKeyedSubscript("userKey").toString(), "abc")
        XCTAssertEqual(onThePage?.objectForKeyedSubscript("userToken").toString(), "t1")

        for (origin, path) in [("https://chatfrom.io", "/"), ("https://chatfrom.io", "/mobile/another-bot"), ("https://chatfrom.io", "/mobile/bot-1/more"), ("https://chatfrom.evil.example", "/mobile/bot-1"), ("http://chatfrom.io", "/mobile/bot-1")] {
            let elsewhere = try run(script, origin: origin, path: path).objectForKeyedSubscript("ChatFromApp")
            XCTAssertEqual(elsewhere?.isUndefined, true, "\(origin)\(path) got the person")
        }
    }

    func testAPortIsPartOfTheAddress() throws {
        let local = try XCTUnwrap(URL(string: "http://localhost:4599/mobile/bot-1"))
        let script = BridgeScript.userScript(for: AppUser(person: Person(userKey: "abc", userToken: nil)), page: local)
        XCTAssertEqual(try run(script, origin: "http://localhost:4599").objectForKeyedSubscript("ChatFromApp")?.objectForKeyedSubscript("userKey").toString(), "abc")
        XCTAssertEqual(try run(script, origin: "http://localhost:80").objectForKeyedSubscript("ChatFromApp")?.isUndefined, true)
    }

    func testTheTextSizeIsAStyleOfItsOwnAndUpdatesInPlace() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var added = []; var found = null; var document = { getElementById: function () { return found; }, createElement: function () { return {}; }, head: { appendChild: function (e) { added.push(e); found = e; return e; } } };")
        context.evaluateScript(BridgeScript.textSize(1.35))
        context.evaluateScript(BridgeScript.textSize(1.4))
        XCTAssertEqual(context.evaluateScript("added.length")?.toInt32(), 1, "a second style instead of updating the first")
        XCTAssertEqual(context.evaluateScript("found.id")?.toString(), "chatfrom-text-size")
        XCTAssertEqual(context.evaluateScript("found.textContent")?.toString(), "html { -webkit-text-size-adjust: 140% !important; }")
    }

    func testNobodyIsAnEmptyObject() {
        XCTAssertEqual(BridgeScript.json(AppUser()), "{}")
        XCTAssertEqual(BridgeScript.json(AppUser(person: Person(userKey: "abc", userToken: nil))), "{\"userKey\":\"abc\"}")
    }

    func testSubscriptionsAreThereWithOrWithoutAPerson() {
        let proofs = [AppStoreProof(transaction: "t1", renewal: "r1"), AppStoreProof(transaction: "t2", renewal: nil)]
        XCTAssertEqual(
            BridgeScript.json(AppUser(purchases: Purchases(revenueCatId: "rc", appStore: proofs))),
            "{\"appStore\":[{\"renewal\":\"r1\",\"transaction\":\"t1\"},{\"transaction\":\"t2\"}],\"revenueCatId\":\"rc\"}"
        )
        XCTAssertEqual(
            BridgeScript.json(AppUser(person: Person(userKey: "abc", userToken: "t"), purchases: Purchases(revenueCatId: "rc"))),
            "{\"revenueCatId\":\"rc\",\"userKey\":\"abc\",\"userToken\":\"t\"}"
        )
    }

    func testATokenCannotBreakOutOfTheScript() throws {
        // Run as the script it becomes: the words come back whole, and nothing in them ran.
        for hostile in ["\"; window.ran = true; //", "\\\"; window.ran = true; //", "</script><script>window.ran = true</script>", "line\nbreak", "\u{2028}window.ran = true"] {
            let script = BridgeScript.userScript(for: AppUser(person: Person(userKey: "k", userToken: hostile), purchases: Purchases(revenueCatId: hostile, appStore: [AppStoreProof(transaction: hostile, renewal: hostile)])), page: page)
            let window = try run(script)
            let app = window.objectForKeyedSubscript("ChatFromApp")
            XCTAssertEqual(app?.objectForKeyedSubscript("userToken").toString(), hostile)
            XCTAssertEqual(app?.objectForKeyedSubscript("revenueCatId").toString(), hostile)
            XCTAssertEqual(app?.objectForKeyedSubscript("appStore").atIndex(0).objectForKeyedSubscript("transaction").toString(), hostile)
            XCTAssertEqual(app?.objectForKeyedSubscript("appStore").atIndex(0).objectForKeyedSubscript("renewal").toString(), hostile)
            XCTAssertEqual(window.objectForKeyedSubscript("ran")?.isUndefined, true, hostile)
        }
    }

    func testATokenCannotBreakOutOfARunningPageEither() throws {
        for hostile in ["\"; window.ran = true; //", "</script><script>window.ran = true</script>", "\u{2028}window.ran = true"] {
            let user = AppUser(person: Person(userKey: "k", userToken: hostile), purchases: Purchases(revenueCatId: hostile, appStore: [AppStoreProof(transaction: hostile, renewal: hostile)]))
            let window = try run(BridgeScript.setUser(user))
            let app = window.objectForKeyedSubscript("ChatFromApp")
            XCTAssertEqual(app?.objectForKeyedSubscript("userToken").toString(), hostile)
            XCTAssertEqual(app?.objectForKeyedSubscript("revenueCatId").toString(), hostile)
            XCTAssertEqual(app?.objectForKeyedSubscript("appStore").atIndex(0).objectForKeyedSubscript("renewal").toString(), hostile)
            XCTAssertEqual(window.objectForKeyedSubscript("ran")?.isUndefined, true, hostile)
        }
    }

    func testEvents() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var events = []; var window = { dispatchEvent: function (e) { events.push(e.type); } }; function Event(type) { this.type = type; }")
        context.evaluateScript(BridgeScript.dispatch(.signOut))
        context.evaluateScript(BridgeScript.dispatch(.newChat))
        context.evaluateScript(BridgeScript.setUser(AppUser()))
        context.evaluateScript(BridgeScript.dispatch(.textSize))
        XCTAssertEqual(context.evaluateScript("events.join()")?.toString(), "chatfrom:sign-out,chatfrom:new-chat,chatfrom:token,chatfrom:text-size")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(window.ChatFromApp)")?.toString(), "{}")
    }
}

final class UserTokenTests: XCTestCase {
    func testTakesWhatThePageTakes() {
        // The same table as cleanSiteToken in libs/site-token.ts.
        for good in ["a", "lhct1.eyJzdWIiOiJ4In0.c2lnbmF0dXJl", "A-z_0~9.", String(repeating: "a", count: 1024)] {
            XCTAssertTrue(UserToken.isAccepted(good), good)
        }
        for bad in ["", "has spaces in it", "base64+with/padding==", "caf\u{00E9}", String(repeating: "a", count: 1025), "\u{0661}"] {
            XCTAssertFalse(UserToken.isAccepted(bad), bad)
        }
    }
}

final class RevenueCatIdTests: XCTestCase {
    func testTakesOnlyRevenueCatsAnonymousIds() {
        // The same as ANONYMOUS_ID in libs/app-subscriber.ts.
        for good in ["$RCAnonymousID:" + String(repeating: "0123abcd", count: 4), "$RCAnonymousID:" + String(repeating: "ABCDEF09", count: 4)] {
            XCTAssertTrue(RevenueCatId.isAnonymous(good), good)
        }
        for bad in ["", "user-42", "sara@example.com", "$RCAnonymousID:", "$RCAnonymousID:" + String(repeating: "a", count: 31), "$RCAnonymousID:" + String(repeating: "a", count: 33), "$RCAnonymousID:" + String(repeating: "g", count: 32), "$rcanonymousid:" + String(repeating: "a", count: 32), " $RCAnonymousID:" + String(repeating: "a", count: 32), "$RCAnonymousID:" + String(repeating: "a", count: 31) + "\u{0661}", "$RCAnonymousID:" + String(repeating: "a", count: 31) + "a\u{0301}"] {
            XCTAssertFalse(RevenueCatId.isAnonymous(bad), bad)
        }
    }
}

final class StringsTests: XCTestCase {
    func testPutsTheNameInTheWords() {
        XCTAssertEqual(ChatFromStrings.named(ChatFromStrings().chatWith, "Lumen"), "Chat with Lumen")
        XCTAssertEqual(ChatFromStrings.named("Mit {name} chatten", "Lumen"), "Mit Lumen chatten")
        XCTAssertEqual(ChatFromStrings.named("100% {name}", "50%d"), "100% 50%d")
    }
}

final class PersonKeyTests: XCTestCase {
    func testIsAHashThatStaysTheSameLength() {
        let key = PersonKey.make(userId: "sara@example.com", salt: "s")
        XCTAssertEqual(key.count, 64)
        XCTAssertFalse(key.contains("sara"))
        XCTAssertEqual(PersonKey.make(userId: "a-much-longer-identifier-than-the-one-before-it@example.com", salt: "s").count, 64)
    }

    func testDependsOnThePersonAndTheInstall() {
        XCTAssertEqual(PersonKey.make(userId: "a", salt: "s"), PersonKey.make(userId: "a", salt: "s"))
        XCTAssertNotEqual(PersonKey.make(userId: "a", salt: "s"), PersonKey.make(userId: "b", salt: "s"))
        XCTAssertNotEqual(PersonKey.make(userId: "a", salt: "s"), PersonKey.make(userId: "a", salt: "t"))
    }

    func testKeepsOneSalt() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "chatfrom-tests-\(UUID().uuidString)"))
        XCTAssertEqual(PersonKey.salt(in: defaults), PersonKey.salt(in: defaults))
    }
}

final class LinkPolicyTests: XCTestCase {
    private let page = URL(string: "https://chatfrom.io/mobile/bot-1")!

    private func decide(_ url: String?, mainFrame: Bool = true, tapped: Bool = false) -> LinkPolicy.Decision {
        LinkPolicy.decide(url: url.flatMap(URL.init(string:)), isMainFrame: mainFrame, userTapped: tapped, page: page)
    }

    func testStaysOnTheChatPage() {
        XCTAssertEqual(decide("https://chatfrom.io/mobile/bot-1"), .stay)
        XCTAssertEqual(decide("https://chatfrom.io/mobile/bot-1?x=1"), .stay)
        XCTAssertEqual(decide("https://CHATFROM.io/mobile/bot-1", tapped: true), .stay)
    }

    func testEverythingElseOpensOutsideWhenTapped() {
        for link in ["https://example.com/", "https://chatfrom.io/", "https://chatfrom.io/mobile/another-bot", "http://chatfrom.io/mobile/bot-1", "https://chatfrom.io:8443/mobile/bot-1", "mailto:hi@example.com", "tel:+123"] {
            XCTAssertEqual(decide(link, tapped: true), .openOutside(URL(string: link)!), link)
        }
    }

    func testNothingLeavesWithoutATap() {
        XCTAssertEqual(decide("https://example.com/"), .refuse)
        XCTAssertEqual(decide("https://chatfrom.io/"), .refuse)
    }

    func testRefusesSchemesThatAreNotLinks() {
        XCTAssertEqual(decide("javascript:alert(1)", tapped: true), .refuse)
        XCTAssertEqual(decide("file:///etc/passwd", tapped: true), .refuse)
        XCTAssertEqual(decide("other-app://steal", tapped: true), .refuse)
        XCTAssertEqual(decide(nil, tapped: true), .refuse)
    }

    func testFramesInsideThePageStayAndAreNotTheChat() {
        XCTAssertEqual(decide("https://example.com/frame", mainFrame: false), .stay)
        XCTAssertEqual(decide("about:blank", mainFrame: false), .stay)
        XCTAssertEqual(decide("other-app://x", mainFrame: false), .refuse)
    }
}

final class FreshnessTests: XCTestCase {
    func testAPageIsStaleAfterAnHourOffScreen() {
        let then = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(Freshness.isStale(lastOnScreen: then, now: then.addingTimeInterval(3599)))
        XCTAssertTrue(Freshness.isStale(lastOnScreen: then, now: then.addingTimeInterval(3600)))
        XCTAssertTrue(Freshness.isStale(lastOnScreen: then, now: then.addingTimeInterval(2), maxAway: 2))
        XCTAssertTrue(Freshness.isStale(lastOnScreen: then, now: then.addingTimeInterval(Freshness.closedMaxAway), maxAway: Freshness.closedMaxAway))
    }
}

final class ChatColorTests: XCTestCase {
    func testPicksTheSameInkAsTheWidget() {
        // The values libs/widget-icons.ts readableOn gives.
        XCTAssertTrue(ChatColor.readableIsWhite(on: "#570DF8"))
        XCTAssertTrue(ChatColor.readableIsWhite(on: "#2563EB"))
        XCTAssertFalse(ChatColor.readableIsWhite(on: "#FFFFFF"))
        XCTAssertFalse(ChatColor.readableIsWhite(on: "#FACC15"))
        XCTAssertTrue(ChatColor.readableIsWhite(on: "not-a-colour"))
    }

    func testAColourItCannotReadIsTheDefaultAccent() {
        XCTAssertEqual(ChatColor.color("not-a-colour"), ChatColor.color(ChatColor.defaultAccent))
    }
}

final class ChatIconTests: XCTestCase {
    func testDrawsEveryIconWithInkInIt() {
        for name in ChatIcon.all.keys {
            let image = ChatIcon.image(name, size: 24)
            XCTAssertEqual(image.size, CGSize(width: 24, height: 24), name)
            XCTAssertGreaterThan(inkedPixels(image), 20, name)
        }
    }

    func testAnIconItDoesNotKnowIsTheChatBubble() {
        XCTAssertEqual(ChatIcon.image("from-the-future", size: 24).pngData(), ChatIcon.image("chat", size: 24).pngData())
    }

    func testReadsAbsoluteAndRelativeCommands() {
        let path = SVGPath.make("M2 2h10v5H4l-2 3z")
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 2, y: 2, width: 10, height: 8))
    }

    func testReadsNumbersRunTogether() {
        // "1.8.7" is 1.8 then .7, and "8.5-6" is 8.5 then -6.
        let path = SVGPath.make("M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7Z")
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minX, 16, accuracy: 0.001)
        XCTAssertEqual(box.maxX, 21, accuracy: 0.001)
        XCTAssertEqual(box.minY, 15.5, accuracy: 0.001)
        XCTAssertEqual(box.maxY, 20.5, accuracy: 0.001)
    }

    func testArcsMakeACircle() {
        let box = SVGPath.make("M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z").boundingBoxOfPath
        XCTAssertEqual(box.minX, 3, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 21, accuracy: 0.01)
        XCTAssertEqual(box.minY, 3, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 21, accuracy: 0.01)
    }

    func testTheChatBubbleIsWhereTheBrowserDrawsIt() {
        // The tail's tip is (3.5, 20.5). The large arc runs from (4.85, 15.95) to (20.5, 11.5) with a radius of 8.5,
        // which puts its centre at (12, 11.355), worked out by hand from the chord, so its top is 2.855.
        let box = SVGPath.make(ChatIcon.all["chat"]![0].d).boundingBoxOfPath
        XCTAssertEqual(box.minX, 3.5, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 20.5, accuracy: 0.01)
        XCTAssertEqual(box.minY, 2.855, accuracy: 0.01)
        XCTAssertEqual(box.maxY, 20.5, accuracy: 0.01)
    }

    func testStopsAtSomethingItCannotRead() {
        XCTAssertFalse(SVGPath.make("M1 1L2").isEmpty)
        XCTAssertTrue(SVGPath.make("").isEmpty)
    }

    private func inkedPixels(_ image: UIImage) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        var count = 0
        let alphaOffset = cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first ? 0 : 3
        for y in 0..<cg.height {
            for x in 0..<cg.width where bytes[y * cg.bytesPerRow + x * cg.bitsPerPixel / 8 + alphaOffset] > 0 {
                count += 1
            }
        }
        return count
    }
}

@MainActor
final class PurchasesTests: XCTestCase {
    private let anonymous = "$RCAnonymousID:" + String(repeating: "0123abcd", count: 4)
    private let proof = AppStoreProof(transaction: "t1", renewal: "r1")
    private var hub: Hub { Hub.shared }

    override func tearDown() async throws {
        hub.sharesAppStoreSubscriptions = false
        hub.readAppStoreSubscriptions = { await AppStoreSubscriptions.read() }
        let forgotten = expectation(description: "forgotten")
        hub.logout { forgotten.fulfill() }
        await fulfillment(of: [forgotten], timeout: 10)
    }

    /// Waits for something the hub does on its own time, such as a read of the App Store.
    private func eventually(_ what: String, _ holds: @escaping () -> Bool) async {
        for _ in 0..<200 where !holds() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(holds(), what)
    }

    func testOnlyAnAnonymousRevenueCatIdReachesAPage() {
        hub.revenueCatAppUserId = "user-42"
        XCTAssertEqual(hub.revenueCatAppUserId, "user-42", "the app's own value, as it set it")
        XCTAssertNil(hub.user.purchases.revenueCatId)
        hub.revenueCatAppUserId = anonymous
        XCTAssertEqual(hub.user.purchases.revenueCatId, anonymous)
        hub.revenueCatAppUserId = nil
        XCTAssertNil(hub.user.purchases.revenueCatId)
    }

    func testASignOutForgetsTheRevenueCatIdAtOnceAndANewOneSetAfterItStays() async {
        hub.identify(userId: "sara@example.com", userToken: nil)
        hub.revenueCatAppUserId = anonymous
        let forgotten = expectation(description: "forgotten")
        hub.logout { forgotten.fulfill() }
        XCTAssertNil(hub.revenueCatAppUserId)
        XCTAssertNil(hub.user.purchases.revenueCatId)
        let next = "$RCAnonymousID:" + String(repeating: "fedc9876", count: 4)
        hub.revenueCatAppUserId = next
        await fulfillment(of: [forgotten], timeout: 10)
        XCTAssertNil(hub.person)
        XCTAssertEqual(hub.user.purchases.revenueCatId, next)
    }

    func testASecondCallForTheSameSignOutLeavesTheNextCustomersId() async {
        hub.identify(userId: "sara@example.com", userToken: nil)
        hub.revenueCatAppUserId = anonymous
        let first = expectation(description: "the first call")
        let second = expectation(description: "the second call")
        hub.logout { first.fulfill() }
        let next = "$RCAnonymousID:" + String(repeating: "fedc9876", count: 4)
        hub.revenueCatAppUserId = next
        // Another part of the app that reacts to the same sign-out.
        hub.logout { second.fulfill() }
        XCTAssertEqual(hub.user.purchases.revenueCatId, next)
        await fulfillment(of: [first, second], timeout: 10)
        XCTAssertEqual(hub.user.purchases.revenueCatId, next)
    }

    func testEverySignOutForgetsTheRevenueCatIdEvenWithNobodyToForget() async {
        let first = expectation(description: "nobody left")
        hub.logout { first.fulfill() }
        await fulfillment(of: [first], timeout: 10)
        hub.revenueCatAppUserId = anonymous
        let again = expectation(description: "nothing to forget")
        hub.logout { again.fulfill() }
        await fulfillment(of: [again], timeout: 10)
        XCTAssertNil(hub.revenueCatAppUserId)
        XCTAssertNil(hub.user.purchases.revenueCatId)
    }

    func testSomeoneElseSigningInStartsWithoutTheLastOnesRevenueCatId() {
        hub.identify(userId: "sara@example.com", userToken: nil)
        hub.revenueCatAppUserId = anonymous
        hub.identify(userId: "sara@example.com", userToken: "a-newer-token")
        XCTAssertEqual(hub.user.purchases.revenueCatId, anonymous, "the same person with a new token keeps it")
        hub.identify(userId: "tom@example.com", userToken: nil)
        XCTAssertNil(hub.revenueCatAppUserId)
        XCTAssertNil(hub.user.purchases.revenueCatId)
    }

    func testTheAppStoresWordIsReadWhenSharingTurnsOnAndGoesWhenItTurnsOff() async {
        hub.readAppStoreSubscriptions = { [self] in [proof] }
        hub.sharesAppStoreSubscriptions = true
        await eventually("read once sharing is on") { self.hub.user.purchases.appStore == [self.proof] }
        hub.sharesAppStoreSubscriptions = false
        XCTAssertEqual(hub.user.purchases.appStore, [])
    }

    func testAReadThatFailedKeepsWhatWasReadBefore() async {
        var reads = 0
        hub.readAppStoreSubscriptions = { [self] in
            reads += 1
            return reads == 1 ? [proof] : nil
        }
        hub.sharesAppStoreSubscriptions = true
        await eventually("the first read") { self.hub.user.purchases.appStore == [self.proof] }
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await eventually("a second read at the foreground") { reads == 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(hub.user.purchases.appStore, [proof])
    }

    func testAReadStillOnItsWayWhenSharingTurnsOffChangesNothing() async {
        hub.readAppStoreSubscriptions = { [self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return [proof]
        }
        hub.sharesAppStoreSubscriptions = true
        hub.sharesAppStoreSubscriptions = false
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(hub.user.purchases.appStore, [])
    }

    func testTheAppStoresWordOutlastsASignOut() async {
        hub.readAppStoreSubscriptions = { [self] in [proof] }
        hub.sharesAppStoreSubscriptions = true
        await eventually("read once sharing is on") { self.hub.user.purchases.appStore == [self.proof] }
        hub.identify(userId: "sara@example.com", userToken: nil)
        let forgotten = expectation(description: "forgotten")
        hub.logout { forgotten.fulfill() }
        await fulfillment(of: [forgotten], timeout: 10)
        XCTAssertEqual(hub.user.purchases.appStore, [proof])
    }
}
