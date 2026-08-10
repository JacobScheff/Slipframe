//
//  GameCenterAuthWindow.swift
//  Slipframe
//
//  Presents GameKit’s sign-in UI from a real window scene.
//  Immersive attachments cannot reliably host UIKit modal presentation,
//  so authenticateHandler’s view controller is shown from this WindowGroup.
//

import SwiftUI
import UIKit

enum GameCenterAuthScene {
    static let id = "gameCenterAuth"
}

/// Clear UIKit host that presents GameKit’s authentication controller with
/// `present(_:animated:)`, matching Game Center’s expected presentation path.
final class GameCenterAuthHostController: UIViewController {
    private weak var presentedAuthViewController: UIViewController?
    private var pendingAuthViewController: UIViewController?
    private var isPresentingAuth = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPendingIfPossible()
    }

    func presentAuth(_ viewController: UIViewController?) {
        pendingAuthViewController = viewController
        presentPendingIfPossible()
    }

    private func presentPendingIfPossible() {
        guard isViewLoaded, view.window != nil else { return }
        guard !isPresentingAuth else { return }

        guard let pending = pendingAuthViewController else {
            if let presentedAuthViewController,
               presentedViewController === presentedAuthViewController {
                dismiss(animated: true)
                self.presentedAuthViewController = nil
            }
            return
        }

        // Already presenting this controller.
        if presentedViewController === pending || pending.presentingViewController != nil {
            presentedAuthViewController = pending
            return
        }

        // Replace any unexpected presented content first.
        if let presentedViewController {
            isPresentingAuth = true
            presentedViewController.dismiss(animated: false) { [weak self] in
                guard let self else { return }
                self.isPresentingAuth = false
                self.presentedAuthViewController = nil
                self.presentPendingIfPossible()
            }
            return
        }

        isPresentingAuth = true
        present(pending, animated: true) { [weak self] in
            guard let self else { return }
            self.isPresentingAuth = false
            self.presentedAuthViewController = pending
        }
    }
}

struct GameCenterAuthPresenter: UIViewControllerRepresentable {
    let authViewController: UIViewController?

    func makeUIViewController(context: Context) -> GameCenterAuthHostController {
        GameCenterAuthHostController()
    }

    func updateUIViewController(_ host: GameCenterAuthHostController, context: Context) {
        host.presentAuth(authViewController)
    }
}

/// Small plain window used only as a UIKit presentation anchor for Game Center sign-in.
struct GameCenterAuthWindow: View {
    @EnvironmentObject private var gameCenter: GameCenterService
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GameCenterAuthPresenter(authViewController: gameCenter.authenticationViewController)
            .frame(width: 40, height: 40)
            .onChange(of: gameCenter.needsSignInPresentation) { _, needsSignIn in
                if !needsSignIn {
                    dismissWindow(id: GameCenterAuthScene.id)
                }
            }
            .onChange(of: gameCenter.isAuthenticated) { _, authenticated in
                if authenticated {
                    dismissWindow(id: GameCenterAuthScene.id)
                }
            }
            .onDisappear {
                // User closed the host window before finishing sign-in.
                if !gameCenter.isAuthenticated, gameCenter.needsSignInPresentation {
                    gameCenter.clearAuthenticationPresentation()
                    gameCenter.refreshAuthState()
                }
            }
    }
}
