//
//  ContentView.swift
//  Endless Runner
//
//  Unused launcher — the app opens ImmersiveSpace directly.
//  Kept for SwiftUI previews only.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameModel: GameModel

    var body: some View {
        PlayHUDView()
            .environmentObject(gameModel)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(GameModel())
}
