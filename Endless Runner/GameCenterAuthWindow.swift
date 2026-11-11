import SwiftUI
import UIKit

/// GameKit presents its sign-in controller from a UIKit window, outside the attachment.
struct GameCenterAuthWindow: View {
    static let id = "gameCenterAuth"

    @ObservedObject var center: GameCenterService
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GameCenterPresenter(controller: center.authenticationViewController)
            .frame(width: 280, height: 100)
            .overlay {
                Text("Game Center")
                    .font(.title3)
                    .allowsHitTesting(false)
            }
            .glassBackgroundEffect()
            .onChange(of: center.needsSignInPresentation, initial: true) { _, needsSignIn in
                if !needsSignIn { dismissWindow(id: Self.id) }
            }
    }
}

private struct GameCenterPresenter: UIViewControllerRepresentable {
    let controller: UIViewController?

    func makeUIViewController(context: Context) -> GameCenterPresenterHost {
        GameCenterPresenterHost()
    }

    func updateUIViewController(_ host: GameCenterPresenterHost, context: Context) {
        host.pending = controller
    }
}

private final class GameCenterPresenterHost: UIViewController {
    var pending: UIViewController? {
        didSet { presentIfReady() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentIfReady()
    }

    private func presentIfReady() {
        guard isViewLoaded, view.window != nil, presentedViewController == nil,
              let pending, pending.presentingViewController == nil else { return }
        present(pending, animated: true)
    }
}
