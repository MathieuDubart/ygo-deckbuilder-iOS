import SwiftUI
import UIKit

/// Chargement des visuels (cartes, boîtes). Comme le web, on passe par l'optimiseur d'images
/// du serveur (`/_next/image`) : images redimensionnées et mises en cache chez soi, sans
/// solliciter YGOPRODeck à chaque affichage. Cache mémoire + cache disque HTTP.
final class ImagePipeline {
    static let shared = ImagePipeline()

    /// Largeurs acceptées par Next (deviceSizes + imageSizes par défaut).
    enum Width: Int {
        case thumb = 256, tile = 384, medium = 640, large = 828
    }

    var server: URL?

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.countLimit = 400
    }

    /// URL servie par l'optimiseur du serveur (repli : URL d'origine).
    func url(for source: URL, width: Width, quality: Int = 75) -> URL {
        guard let server,
              var components = URLComponents(url: server.appending(path: "_next/image"), resolvingAgainstBaseURL: false)
        else { return source }
        components.queryItems = [
            .init(name: "url", value: source.absoluteString),
            .init(name: "w", value: String(width.rawValue)),
            .init(name: "q", value: String(quality)),
        ]
        return components.url ?? source
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task { [session] () -> UIImage? in
            guard let result = try? await session.data(from: url) else { return nil }
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status), let image = UIImage(data: result.0) else { return nil }
            // Décodage hors du fil principal
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Image distante via l'optimiseur du serveur, avec repli si la première URL échoue.
struct RemoteImage<Placeholder: View>: View {
    let sources: [URL]
    var width: ImagePipeline.Width = .tile
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        _ sources: [URL?], width: ImagePipeline.Width = .tile, contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.sources = sources.compactMap { $0 }
        self.width = width
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    private var resolved: [URL] { sources.map { ImagePipeline.shared.url(for: $0, width: width) } }

    var body: some View {
        Group {
            if let image = image ?? resolved.first.flatMap(ImagePipeline.shared.cached) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: resolved) {
            image = nil
            for url in resolved {
                if let loaded = await ImagePipeline.shared.image(for: url) {
                    image = loaded
                    return
                }
            }
        }
    }
}
