import SwiftUI
import UIKit
import XCTest
@testable import ChatFromSDK

@MainActor
final class AvatarLabelTests: XCTestCase {
    func testTheCircleGrowsWithTheInitials() {
        let avatar = AvatarLabel()
        avatar.font = .systemFont(ofSize: 12, weight: .semibold)
        XCTAssertEqual(avatar.intrinsicContentSize, CGSize(width: 30, height: 30))
        // As far as the page's words grow, and no further: the header is 52 points high.
        avatar.font = .systemFont(ofSize: 12 * Hub.maxTextScale, weight: .semibold)
        XCTAssertEqual(avatar.intrinsicContentSize, CGSize(width: 42, height: 42))
        XCTAssertLessThan(avatar.intrinsicContentSize.height, 52)
    }
}

@MainActor
final class RowTitleTests: XCTestCase {
    /// As a Button's title is: a literal is looked up in the app's strings, a String is shown as it is, and both compile without help.
    func testATitleIsLookedUpOrShownAsItIs() {
        let looked = ChatFromRow(botId: "row-bot", title: "Ask our assistant")
        let words = "Ask our assistant"
        let shown = ChatFromRow(botId: "row-bot", title: words)
        let named = ChatFromRow(botId: "row-bot")
        XCTAssertNotNil(Mirror(reflecting: looked).descendant("titleKey") as? LocalizedStringKey)
        XCTAssertEqual(Mirror(reflecting: shown).descendant("title") as? String, words)
        XCTAssertNil(Mirror(reflecting: named).descendant("title") as? String)
        XCTAssertNil(Mirror(reflecting: named).descendant("titleKey") as? LocalizedStringKey)
    }
}
