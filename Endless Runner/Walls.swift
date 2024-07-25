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

//                try await session.run([planeData])
                                    
//                for await update in planeData.anchorUpdates {
//                    
//                    print(update.anchor.classification, " ", update.description, " ", update.anchor.originFromAnchorTransform)
//                    
//                }
            }
        }
    }
}

#Preview {
    Walls()
}
