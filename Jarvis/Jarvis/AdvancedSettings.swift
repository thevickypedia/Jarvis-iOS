//
//  AdvancedSettings.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/29/25.
//

import SwiftUI

struct AdvancedSettings {
    let nativeAudio: Bool
    let speechTimeout: Int
}

struct AdvancedSettingsView: View {
    @Binding var nativeAudio: Bool
    @Binding var speechTimeout: Int

    var body: some View {
        DisclosureGroup("Advanced Settings") {
            Toggle("Native Audio", isOn: $nativeAudio)
            HStack {
                Text("Speech Timeout (Seconds)")
                Spacer()
                Picker("", selection: $speechTimeout) {
                    ForEach([0, 3, 5, 10, 30], id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 80)
            }
        }
    }
}
