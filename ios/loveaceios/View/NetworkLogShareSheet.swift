import SwiftUI
import UIKit

struct NetworkLogShareSheet: UIViewControllerRepresentable {
    let archiveURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [archiveURL], applicationActivities: nil)
    }

    func updateUIViewController(_ viewController: UIActivityViewController, context: Context) {}
}
