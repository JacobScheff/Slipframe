//
//  ContentView.swift
//  Endless Runner
//
//  Created by Jacob Scheff on 7/23/24.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button("Start ARKit experience") {
            Task {
                await openImmersiveSpace(id: "appSpace")
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}
