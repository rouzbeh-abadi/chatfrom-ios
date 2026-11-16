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

    func testThePictureFillsTheCircleInPlaceOfTheInitials() throws {
        let avatar = AvatarLabel()
        avatar.font = .systemFont(ofSize: 12, weight: .semibold)
        avatar.text = "LL"
        avatar.frame = CGRect(origin: .zero, size: avatar.intrinsicContentSize)
        avatar.layoutIfNeeded()
        let shown = { avatar.subviews.compactMap { $0 as? UIImageView }.first { !$0.isHidden } }
        XCTAssertNil(shown())
        avatar.picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        avatar.layoutIfNeeded()
        let picture = try XCTUnwrap(shown())
        XCTAssertEqual(picture.frame, avatar.bounds)
        XCTAssertEqual(picture.contentMode, .scaleAspectFill)
        // The circle stays the size the initials give it.
        XCTAssertEqual(avatar.intrinsicContentSize, CGSize(width: 30, height: 30))
        avatar.picture = nil
        XCTAssertNil(shown())
    }
}

/// Answers every request with what the test set, as the network would.
final class PictureStub: URLProtocol {
    nonisolated(unsafe) static var answer: (status: Int, body: Data) = (200, Data())
    nonisolated(unsafe) static var asked: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.asked.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AvatarPictureTests: XCTestCase {
    private let url = URL(string: "https://chatfrom.io/api/public/bot/avatar/0123456789abcdef")!
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PictureStub.self]
        return URLSession(configuration: configuration)
    }

    /// Four pixels a side, whatever the screen's scale.
    private var png: Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData { _ in }
    }

    func testAPictureLoads() async {
        PictureStub.answer = (200, png)
        let image = await AvatarPicture.load(url, session: session)
        XCTAssertEqual(image?.size, CGSize(width: 4, height: 4))
    }

    func testNothingShowsForAMissingPictureSomethingElseOrTooMuch() async {
        PictureStub.answer = (404, png)
        let missing = await AvatarPicture.load(url, session: session)
        XCTAssertNil(missing)
        PictureStub.answer = (200, Data("<!doctype html>".utf8))
        let page = await AvatarPicture.load(url, session: session)
        XCTAssertNil(page)
        PictureStub.answer = (200, png + Data(count: AvatarPicture.maxBytes))
        let large = await AvatarPicture.load(url, session: session)
        XCTAssertNil(large)
    }

    func testTheRequestCarriesNothingOfTheApps() {
        let configuration = AvatarPicture.session.configuration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
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
