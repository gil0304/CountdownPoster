import SwiftUI
import UIKit

@MainActor
enum PosterRenderer {
    static func image(for poster: Poster) -> UIImage? {
        let content = PosterCanvasView(poster: poster)
            .frame(width: 1080, height: 1920)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
