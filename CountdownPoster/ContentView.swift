//
//  ContentView.swift
//  CountdownPoster
//
//  Created by 落合遼梧 on 2026/06/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = CountdownPosterStore()

    var body: some View {
        Group {
            if store.shouldShowSignIn {
                SignInStartView()
            } else {
                TabView {
                    NavigationStack {
                        HomeView()
                    }
                    .tabItem {
                        Label("予定", systemImage: "calendar")
                    }

                    NavigationStack {
                        PosterGalleryView()
                    }
                    .tabItem {
                        Label("ポスター", systemImage: "sparkles.rectangle.stack")
                    }

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
        }
        .environmentObject(store)
    }
}

#Preview {
    ContentView()
}
