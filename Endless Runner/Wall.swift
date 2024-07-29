//
//  Wall.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/29/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct Wall: View {
    var body: some View {
        @State var session = ARKitSession()
        @State var immersionState: ImmersionStyle = .mixed
                
//        RealityView { content in
//            // Add the initial RealityKit content
//            if let scene = try? await Entity(named: "Wall", in: realityKitContentBundle) {
//                content.add(scene)
//            }
//            
//            let session = ARKitSession()
//
//            Task {
//                let authorizationResult = await session.requestAuthorization(for: [.worldSensing])
//                let planeData = PlaneDetectionProvider(alignments: [.horizontal])
//
//                for (authorizationType, authorizationStatus) in authorizationResult {
//                    print("Authorization status for \(authorizationType): \(authorizationStatus)")
//                }
//
//                try await session.run([planeData])
//                                                    
//                for await update in planeData.anchorUpdates {
//
//                    print(update.anchor.classification, " ", update.description, " ", update.anchor.originFromAnchorTransform)
//
//                }
//            }
//        }
    }
}

#Preview(immersionStyle: .automatic) {
    Wall()
}
