//
//  ThemeManager.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI

class ThemeManager: ObservableObject {
    @Published var colorScheme: ColorScheme? = systemScheme()
}

func systemScheme() -> ColorScheme {
    UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
}
