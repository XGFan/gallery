import Kingfisher
import SwiftUI

/// One cell on the wall: a folder, an image, or a video.
struct WallCell: View {
    let entry: WallEntry
    let size: CGSize
    let imageURL: URL?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnail
            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Stable identifiers so the UI tests can find and tap specific cells.
    static func identifier(for entry: WallEntry) -> String {
        switch entry {
        case .folder(let f): "folder-cell:\(f.path)"
        case .media(let m): "media-cell:\(m.path)"
        }
    }

    private var thumbnail: some View {
        KFImage(imageURL)
            // Decoding at display size is what keeps memory bounded — the source
            // tier is 1920px on the long edge (docs/adr/0005), which would cost
            // ~10MB of bitmap per cell if decoded full-size.
            .setProcessor(
                DownsamplingImageProcessor(
                    size: CGSize(
                        width: size.width * displayScale,
                        height: size.height * displayScale
                    )
                )
            )
            .cacheOriginalImage()
            .fade(duration: 0.15)
            .placeholder {
                Rectangle().fill(.quaternary)
            }
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    @ViewBuilder
    private var overlay: some View {
        switch entry {
        case .folder(let folder):
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                Text(folder.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.55))

        case .media(let media) where media.isVideo:
            ZStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let duration = media.durationSec, duration > 0 {
                    Text(Self.formatDuration(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }

        case .media:
            EmptyView()
        }
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
