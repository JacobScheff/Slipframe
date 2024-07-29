//
//  Endless_RunnerApp.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/23/24.
//

import SwiftUI
import ARKit
import RealityKit

/// The root entity for entities placed during the game.
let spaceOrigin = Entity()

/// An anchor that helps calculate the position of clouds relative to the player.
let cameraAnchor = AnchorEntity(.head)

@main
struct Endless_RunnerApp: App {
    @State var session = ARKitSession()
    @State var immersionState: ImmersionStyle = .mixed

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: "appSpace") {
            RealityView { content in
                // The root entity.
                content.add(spaceOrigin)
                content.add(cameraAnchor)
            }
                .task {
                    let planeData = PlaneDetectionProvider(alignments: [.horizontal])
                    print("planeData: \(planeData)")

                    if PlaneDetectionProvider.isSupported {
                        do {
                            try await session.run([planeData])
                            print("ARKit session is running...")
                            for await update in planeData.anchorUpdates {
                                // Update app state
                                print("hoge")
                            }
                        } catch {
                            print("ARKit session error \(error)")
                        }
                    } else {
                        print("PlaneDetectionProvider is NOT supported.")
                    }
                }
        }
        .immersionStyle(selection: $immersionState, in: .mixed)
    }
}
