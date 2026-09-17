import AppKit
import SwiftUI

/// Keeps decoded images alive across recycling.
///
/// A LazyVStack throws a row away as soon as it scrolls off and rebuilds it on the way back.
/// With AsyncImage that meant re-reading and re-decoding the file every single time the image
/// passed the viewport — the main cause of stutter while scrolling an image-heavy document.
/// NSCache is thread-safe and evicts itself under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let images = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? { images.object(forKey: url as NSURL) }

    func store(_ image: NSImage, for url: URL) { images.setObject(image, forKey: url as NSURL) }
}

struct ImageBlockView: View {
    let url: URL?
    let alt: String
    let theme: Theme

    /// Seeded from the cache so a row that scrolls back into view draws the image on its first frame
    @State private var image: NSImage?
    @State private var failed = false

    init(url: URL?, alt: String, theme: Theme) {
        self.url = url
        self.alt = alt
        self.theme = theme
        _image = State(initialValue: url.flatMap { ImageCache.shared.image(for: $0) })
    }

    var body: some View {
        content
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            // The alt text becomes a caption only when the image actually loaded;
            // on failure it already appears in the placeholder, so don't repeat it.
            VStack(alignment: .leading, spacing: theme.base * 0.4) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if !alt.isEmpty {
                    Text(alt)
                        .font(theme.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if failed || url == nil {
            placeholder("photo.badge.exclamationmark", alt.isEmpty ? "Couldn’t load image" : alt)
        } else {
            placeholder("photo", "Loading…")
        }
    }

    private func load() async {
        guard let url, image == nil else { return }

        // Only the bytes cross the thread boundary; NSImage is built back on the main actor
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data, let loaded = NSImage(data: data) else {
            failed = true
            return
        }
        ImageCache.shared.store(loaded, for: url)
        image = loaded
        failed = false
    }

    private func placeholder(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: theme.base * 0.5) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(theme.caption)
        .foregroundStyle(.secondary)
        .padding(theme.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}
