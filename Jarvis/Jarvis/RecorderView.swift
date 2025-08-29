//
//  RecorderView.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI
import Speech
import AVFoundation

struct RecorderView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @EnvironmentObject var themeManager: ThemeManager
    let serverURL: String
    let password: String
    let transitProtection: Bool
    let handleLogout: (_ clearActiveServers: Bool) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                Text(speechRecognizer.recognizedText)
                    .padding()
                    .multilineTextAlignment(.center)

                Button(action: {
                    speechRecognizer.toggleRecording(serverURL: serverURL, password: password, transitProtection: transitProtection)
                }) {
                    Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.circle")
                        .resizable()
                        .frame(width: speechRecognizer.isRecording ? 60 : 80, height: 80)
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .onAppear {
                speechRecognizer.requestPermissions()
            }

            // 🔝 Logout Button at Top-Right
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        Log.info("Logged out!")
                        handleLogout(false)
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title2)
                            .padding()
                    }
                }
                Spacer()
            }

            // 🌗 Floating Theme Toggle Button at Bottom-Right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        themeManager.colorScheme = themeManager.colorScheme == .dark ? .light : .dark
                    }) {
                        Image(systemName: themeManager.colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}
