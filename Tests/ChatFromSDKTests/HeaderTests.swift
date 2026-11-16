import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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

    /// The label as it draws itself, its own layer only, so the picture's view over it is left out.
    private func drawn(_ avatar: AvatarLabel) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: avatar.bounds, format: format).pngData { context in
            avatar.layer.draw(in: context.cgContext)
        }
    }

    func testThePictureFillsTheCircleOnWhiteWithTheInitialsLeftOut() throws {
        let avatar = AvatarLabel()
        avatar.font = .systemFont(ofSize: 12, weight: .semibold)
        avatar.textColor = .black
        avatar.frame = CGRect(origin: .zero, size: avatar.intrinsicContentSize)
        let empty = AvatarLabel()
        empty.font = avatar.font
        empty.frame = avatar.frame
        avatar.text = "LL"
        XCTAssertNotEqual(drawn(avatar), drawn(empty), "the initials are drawn without a picture")

        // A see-through logo: the initials must not show through it.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        avatar.picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in }
        avatar.layoutIfNeeded()
        XCTAssertEqual(drawn(avatar), drawn(empty), "the initials are left out under a picture")
        let picture = try XCTUnwrap(avatar.subviews.compactMap { $0 as? UIImageView }.first { !$0.isHidden })
        XCTAssertEqual(picture.frame, avatar.bounds)
        XCTAssertEqual(picture.contentMode, .scaleAspectFill)
        XCTAssertEqual(picture.backgroundColor, .white)

        avatar.picture = nil
        XCTAssertTrue(avatar.subviews.compactMap { $0 as? UIImageView }.allSatisfy(\.isHidden))
        XCTAssertNotEqual(drawn(avatar), drawn(empty), "the initials come back with no picture")
    }
}

/// Answers a request by its address alone, so nothing is shared between tests: `/png/<w>x<h>` a PNG of that size, `/gif` a GIF, `/page` a web page, `/large` more than a picture may be, `/missing` a 404, and `/echo` the request's own headers.
final class PictureStub: URLProtocol {
    static func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static var gif: Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, UIImage(data: png(width: 4, height: 4))!.cgImage!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let parts = request.url!.pathComponents
        var status = 200
        let body: Data
        switch parts.dropFirst().first {
        case "png":
            let size = parts.last!.split(separator: "x").compactMap { Int($0) }
            body = Self.png(width: size[0], height: size[1])
        case "gif": body = Self.gif
        case "page": body = Data("<!doctype html><p>Not a picture".utf8)
        case "large": body = Self.png(width: 4, height: 4) + Data(count: AvatarPicture.maxBytes)
        case "echo": body = try! JSONSerialization.data(withJSONObject: request.allHTTPHeaderFields ?? [:])
        default:
            status = 404
            body = Data()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class AvatarPictureTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        session = AvatarPicture.makeSession(protocolClasses: [PictureStub.self])
    }

    override func tearDown() {
        session.invalidateAndCancel()
        super.tearDown()
    }

    private func load(_ path: String) async -> UIImage? {
        await AvatarPicture.load(URL(string: "https://chatfrom.io\(path)")!, session: session)
    }

    func testAPictureLoadsAsASmallOneToDraw() async throws {
        let small = await load("/png/4x4")
        XCTAssertEqual(try XCTUnwrap(small).size, CGSize(width: 4, height: 4))
        // A larger one is drawn at the header's own size, its shorter side covering the circle, never unpacked whole.
        let loaded = await load("/png/1000x600")
        let large = try XCTUnwrap(loaded)
        XCTAssertEqual(min(large.size.width, large.size.height), CGFloat(AvatarPicture.drawnSide))
        XCTAssertLessThan(max(large.size.width, large.size.height), 1000)
    }

    func testAPictureThatIsNotSquareCoversTheCircleSharply() async throws {
        // The circle shows its middle, so its shorter side is the one drawn at the header's size.
        let loaded = await load("/png/1024x256")
        XCTAssertEqual(try XCTUnwrap(loaded).size, CGSize(width: 512, height: 128))
    }

    func testTheCacheKeepsAPictureOnDisk() throws {
        let url = try XCTUnwrap(URL(string: "https://chatfrom.io/api/public/6f1c0000-0000-4000-8000-000000000001/avatar/0123456789abcdef"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "private, max-age=31536000, immutable", "Content-Type": "image/webp"]))
        // Larger than the memory part keeps, so only the disk can hold it: below 5 MiB URLCache keeps nothing there.
        let picture = Data(count: 100 * 1024)
        AvatarPicture.cache.storeCachedResponse(CachedURLResponse(response: response, data: picture, userInfo: nil, storagePolicy: .allowed), for: request)
        defer { AvatarPicture.cache.removeCachedResponse(for: request) }
        XCTAssertEqual(AvatarPicture.cache.cachedResponse(for: request)?.data.count, picture.count)
    }

    func testNothingShowsForWhatIsNotAPictureTheHeaderDraws() async {
        let missing = await load("/missing")
        let page = await load("/page")
        let gif = await load("/gif")
        let large = await load("/large")
        // A picture that says it is larger than any ChatFrom keeps is not unpacked at all.
        let wide = await load("/png/\(AvatarPicture.maxSide + 1)x8")
        XCTAssertNil(missing)
        XCTAssertNil(page)
        XCTAssertNil(gif)
        XCTAssertNil(large)
        XCTAssertNil(wide)
    }

    func testTheRequestNamesTheSDKAndTakesNothingOfTheApps() async throws {
        let url = try XCTUnwrap(URL(string: "https://chatfrom.io/echo"))
        let sent = try JSONSerialization.jsonObject(with: try await session.data(from: url).0) as? [String: String]
        XCTAssertEqual(sent?["User-Agent"], "ChatFromSDK-iOS/\(ChatFrom.version)")
        // URLSession adds cookies and stored credentials in its own HTTP loader, past where a stub can see the request,
        // so what is checked is that the session has neither to add, nor a place to keep what an answer sets.
        let configuration = AvatarPicture.session.configuration
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertTrue(configuration.urlCache === AvatarPicture.cache, "the SDK's own cache, not the app's")
    }
}

/// Loads that finish when the test says, in any order.
@MainActor
final class HeldLoads {
    private(set) var asked: [URL] = []
    private var waiting: [URL: CheckedContinuation<UIImage?, Never>] = [:]

    func load(_ url: URL) async -> UIImage? {
        asked.append(url)
        return await withCheckedContinuation { waiting[url] = $0 }
    }

    /// Waits for the load to have been asked for, finishes it, and lets what follows run.
    func finish(_ url: URL, with image: UIImage?) async {
        for _ in 0..<100 where waiting[url] == nil { await Task.yield() }
        waiting.removeValue(forKey: url)?.resume(returning: image)
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
final class HeaderPictureTests: XCTestCase {
    private let a = URL(string: "https://chatfrom.io/api/public/6f1c0000-0000-4000-8000-000000000001/avatar/aaaaaaaaaaaaaaaa")!
    private let b = URL(string: "https://chatfrom.io/api/public/6f1c0000-0000-4000-8000-000000000001/avatar/bbbbbbbbbbbbbbbb")!
    private let image = UIImage()
    private let other = UIImage()
    private var loads: HeldLoads!
    private var shown: [UIImage?] = []
    private var picture: HeaderPicture!

    override func setUp() async throws {
        loads = HeldLoads()
        shown = []
        picture = HeaderPicture(load: { [loads] in await loads!.load($0) }, display: { [unowned self] in self.shown.append($0) })
    }

    func testAPictureShowsOnceLoadedAndIsNotAskedForAgain() async {
        picture.show(a)
        await Task.yield()
        XCTAssertTrue(shown.isEmpty, "nothing changes while it loads")
        await loads.finish(a, with: image)
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(shown[0] === image)
        // The page saying the same again, as when it loads again, asks for nothing.
        picture.show(a)
        XCTAssertEqual(loads.asked, [a])
        XCTAssertEqual(shown.count, 1)
    }

    func testANewerAddressWinsOverOneStillLoading() async {
        picture.show(a)
        picture.show(b)
        await loads.finish(a, with: other)
        XCTAssertTrue(shown.isEmpty, "the older picture never shows")
        await loads.finish(b, with: image)
        XCTAssertTrue(shown.last! === image)
    }

    func testAChangedPictureStaysUntilTheNewOneIsInWithNoInitialsBetween() async {
        picture.show(a)
        await loads.finish(a, with: other)
        picture.show(b)
        await Task.yield()
        XCTAssertEqual(shown.count, 1, "the old picture stays while the new one loads")
        await loads.finish(b, with: image)
        XCTAssertEqual(shown.map { $0 === image }, [false, true])
    }

    func testOneThatDidNotLoadShowsTheInitialsAndIsAskedForAgainNextTime() async {
        picture.show(a)
        await loads.finish(a, with: nil)
        XCTAssertNil(shown.last!)
        XCTAssertNil(picture.wanted)
        picture.show(a)
        await loads.finish(a, with: image)
        XCTAssertEqual(loads.asked, [a, a])
        XCTAssertTrue(shown.last! === image)
    }

    func testNoPictureShowsTheInitialsAtOnce() async {
        picture.show(a)
        await loads.finish(a, with: image)
        picture.show(nil)
        XCTAssertNil(shown.last!)
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
