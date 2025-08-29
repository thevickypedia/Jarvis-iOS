//
//  JarvisApp.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var themeManager = ThemeManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
        }
    }
}
