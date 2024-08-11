//
//  Walls.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/25/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct Walls: View {
    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let scene = try? await Entity(named: "Wall", in: realityKitContentBundle) {
                content.add(scene)
            }
        }.gesture(TapGesture().targetedToAnyEntity().onEnded { value in
            print("Hello world!");
        }).onAppear {
                                        
            Task {
                let session = ARKitSession()
                let authorizationResult = await session.requestAuthorization(for: [.worldSensing])
                let planeData = PlaneDetectionProvider(alignments: [.horizontal])
                
                for (authorizationType, authorizationStatus) in authorizationResult {
                    print("Authorization status for \(authorizationType): \(authorizationStatus)")
                }
                
                print("b")

                try await session.run([planeData])
                
                print("a")
                                    
                var iterationCount = 0
                for await update in planeData.anchorUpdates {
                    print(update.anchor.classification, " ", update.description, " ", update.anchor.originFromAnchorTransform)
                    // Process the plane update
                    iterationCount += 1
                    if iterationCount >= 5 { // Process only the first 5 updates
                        break
                    }
                }
                
                print("c")
            }
        }
    }
}

#Preview {
    Walls()
}
