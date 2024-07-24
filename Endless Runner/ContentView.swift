//
//  ContentView.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/23/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ContentView: View {

//    @State private var showImmersiveSpace = false
//    @State private var immersiveSpaceIsShown = false

//    @Environment(\.openImmersiveSpace) var openImmersiveSpace
//    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)

            Text("Hello, world!")

//            Toggle("Show ImmersiveSpace", isOn: $showImmersiveSpace)
//                .font(.title)
//                .frame(width: 360)
//                .padding(24)
//                .glassBackgroundEffect()
        }
        .padding()
//        .onChange(of: showImmersiveSpace) { _, newValue in
//            Task {
//                if newValue {
//                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
//                    case .opened:
//                        immersiveSpaceIsShown = true
//                    case .error, .userCancelled:
//                        fallthrough
//                    @unknown default:
//                        immersiveSpaceIsShown = false
//                        showImmersiveSpace = false
//                    }
//                } else if immersiveSpaceIsShown {
//                    await dismissImmersiveSpace()
//                    immersiveSpaceIsShown = false
//                }
//            }
//        }
        
        RealityView { content in
            // Add the initial RealityKit content
            if let scene = try? await Entity(named: "Wall", in: realityKitContentBundle) {
                content.add(scene)
            }
        }.gesture(TapGesture().targetedToAnyEntity().onEnded { value in
            print("Hello world!");
        })
        
        EmptyView()
            .onAppear {
                let session = ARKitSession()
                let planeData = PlaneDetectionProvider(alignments: [.horizontal])


                Task {
                    try await session.run([planeData])
                    
                    for await update in planeData.anchorUpdates {
                        
                        print(update.anchor.classification, " ", update.description, " ", update.anchor.originFromAnchorTransform)
                        
                    }
                }
            }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
