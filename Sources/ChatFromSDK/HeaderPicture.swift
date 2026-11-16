import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The chatbot's own picture for the header, loaded apart from the chat page, which in an app draws no header of its own.
enum AvatarPicture {
    /// The most read of an answer. ChatFrom keeps none over 256 KB; the room above that lets it keep larger ones later without this release turning them away.
    static let maxBytes = 1024 * 1024
    /// The most pixels a side a picture may say it has before it is read: ChatFrom keeps none over 1024, and a small file can say it unpacks to gigabytes.
    static let maxSide = 2048
    /// The side the picture is drawn at, in pixels: three times the largest circle the header draws (42 points).
    static let drawnSide = 128
    /// What ChatFrom serves. ImageIO reads many more, none of which a picture's address should answer with.
    static let types: Set<String> = [UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier]

    /// A cache of the SDK's own in the app's Caches folder, which the system may empty when space runs low: the app's own cache keeps its size and its rules. URLCache writes nothing to disk below 5 MiB, and keeps an answer only up to a twentieth of each part, so 20 MiB keeps a picture of up to 1 MiB on disk, and 1 MiB one of up to 50 KB in memory.
    static let cache = URLCache(
        memoryCapacity: 1024 * 1024,
        diskCapacity: 20 * 1024 * 1024,
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("ChatFromSDK/Pictures", isDirectory: true)
    )

    /// A session for pictures that takes nothing of the app's: no cookie sent or kept, no stored credential, and the SDK's name where the app's would be. `protocolClasses` come first, for a test.
    static func makeSession(protocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = cache
        configuration.httpAdditionalHeaders = ["User-Agent": "ChatFromSDK-iOS/\(ChatFrom.version)"]
        configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }

    static let session = makeSession()

    /// The picture at `url`, ready to draw; nil when it does not load or is not a picture this header draws. The answer is read only up to `maxBytes`, and the picture's size checked before anything is unpacked, off the main thread.
    static func load(_ url: URL, session: URLSession = session) async -> UIImage? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= Int64(maxBytes) else {
                bytes.task.cancel()
                return nil
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes {
                    bytes.task.cancel()
                    return nil
                }
            }
            let read = data
            return await Task.detached(priority: .utility) { picture(from: read) }.value
        } catch {
            return nil
        }
    }

    /// A PNG, JPEG or WebP as a small picture to draw, the way up a phone stored it followed; nil for anything else, or for one that says it is larger than `maxSide`, which is never unpacked.
    static func picture(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?, types.contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maxSide).contains(width), (1...maxSide).contains(height) else { return nil }
        // The circle shows the middle of a picture that is not square, so its shorter side is the one drawn at drawnSide.
        let longer = max(width, height), shorter = min(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longer, (drawnSide * longer + shorter - 1) / shorter),
        ]
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: small)
    }
}

/// Which picture the chat's header shows: the chatbot's own once it has loaded, or its initials. The session holds one for as long as the app runs, and asks it as soon as the page says which picture is the chatbot's, so the chat opens with the picture there, a picture changed while the chat was closed is in by the time it opens, and a load is never lost with a screen that closed. A picture that changes stays until the new one is in, so the initials never show between them. A newer address, or none, takes the place of one still loading; one that did not load shows the initials, and is asked for again the next time the page says it, as when the page loads again.
@MainActor
final class HeaderPicture {
    private let load: (URL) async -> UIImage?
    private let display: (UIImage?) -> Void
    /// The address shown or loading; nil while the initials show.
    private(set) var wanted: URL?
    private var loading: Task<Void, Never>?

    init(load: @escaping (URL) async -> UIImage? = { await AvatarPicture.load($0) }, display: @escaping (UIImage?) -> Void) {
        self.load = load
        self.display = display
    }

    func show(_ url: URL?) {
        guard url != wanted else { return }
        wanted = url
        loading?.cancel()
        guard let url else {
            display(nil)
            return
        }
        let load = self.load
        loading = Task { [weak self] in
            let image = await load(url)
            guard let self, !Task.isCancelled, self.wanted == url else { return }
            if image == nil { self.wanted = nil }
            self.display(image)
        }
    }
}
