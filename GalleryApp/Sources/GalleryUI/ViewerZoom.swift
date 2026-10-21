import Kingfisher
import SwiftUI

/// Makes a wall cell something the player opens out of and closes back into,
/// the way Photos does.
///
/// iOS only. On macOS the player fades over the whole window (docs/adr/0007),
/// and a cell flying out from under a sidebar would cross it.
struct ZoomSource: ViewModifier {
    let entry: WallEntry

    @Environment(ViewerPresenter.self) private var presenter

    func body(content: Content) -> some View {
        #if os(iOS)
        if case .media(let media) = entry {
            content
                // The picture is out of the cell while the player shows it.
                // Leaving it would double the picture as the player closes
                // over the wall.
                .opacity(presenter.isShowing(media) ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    presenter.noteFrame($0, of: media)
                }
                // A cell scrolled out of the lazy stack has no frame worth
                // flying to; closing falls back to the plain dismiss.
                .onDisappear { presenter.forgetFrame(of: media) }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The picture in flight between its cell and the player.
struct ViewerFlight {
    let item: MediaItem
    /// The cell, in window coordinates.
    let cell: CGRect
    /// Which end the picture is at. Toggled inside an animation to fly.
    var atCell: Bool
    /// Where a drag-to-dismiss had already taken the picture at the player's
    /// end, so the flight back starts from under the finger.
    var scale: CGFloat = 1
    var offset: CGFloat = 0
}

/// Draws a flight. Both ends are plain rects, so SwiftUI interpolates the frame,
/// the position and the mask between them on its own.
struct ViewerFlightLayer: View {
    let flight: ViewerFlight
    let url: URL

    var body: some View {
        GeometryReader { proxy in
            let window = proxy.frame(in: .global)
            let screen = CGRect(origin: .zero, size: proxy.size)
            let aspect = flight.item.aspectRatio
            let cell = flight.cell.offsetBy(dx: -window.minX, dy: -window.minY)
            let image = flight.atCell
                ? ViewerZoom.fill(aspect: aspect, in: cell)
                : lifted(ViewerZoom.fit(aspect: aspect, in: screen), in: screen)
            let clip = flight.atCell ? cell : image

            KFImage(url)
                // The wall has already cached this file. Reading it on the spot
                // is what puts the picture in the cell on the very first frame
                // instead of an empty box flying out.
                .loadDiskFileSynchronously()
                .resizable()
                .frame(width: image.width, height: image.height)
                .position(x: image.midX, y: image.midY)
                .mask {
                    Rectangle()
                        .frame(width: clip.width, height: clip.height)
                        .position(x: clip.midX, y: clip.midY)
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The same scale-about-the-centre and downward offset the pager is drawn
    /// with during a drag-to-dismiss.
    private func lifted(_ rect: CGRect, in screen: CGRect) -> CGRect {
        let width = rect.width * flight.scale
        let height = rect.height * flight.scale
        return CGRect(
            x: screen.midX + (rect.midX - screen.midX) * flight.scale - width / 2,
            y: screen.midY + (rect.midY - screen.midY) * flight.scale - height / 2 + flight.offset,
            width: width,
            height: height
        )
    }
}
