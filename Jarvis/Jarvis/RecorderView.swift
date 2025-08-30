//
//  RecorderView.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI
import Speech
import AVFoundation

struct AdvancedSettings {
    let nativeAudio: Bool
    let speechTimeout: Int
    let requestTimeout: Int
}

struct RecorderView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @EnvironmentObject var themeManager: ThemeManager
    let serverURL: String
    let password: String
    let transitProtection: Bool
    let handleLogout: (_ clearActiveServers: Bool) -> Void

    @State private var nativeAudio = false
    @State private var speechTimeout = 0
    @State private var requestTimeout = 5

    let speechTimeoutRange = Array(0..<30)
    let requestTimeoutRange = Array(0..<60)
    @State private var statusMessage: String?

    private func setStatusMessage(_ text: String, _ clearDelay: Int = 3) {
        statusMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(clearDelay)) {
            statusMessage = nil
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 30) {
                Text(speechRecognizer.recognizedText)
                    .padding()
                    .multilineTextAlignment(.center)

                Button(action: {
                    speechRecognizer.toggleRecording(
                        serverURL: serverURL,
                        password: password,
                        transitProtection: transitProtection,
                        advancedSettings: AdvancedSettings(
                            nativeAudio: nativeAudio,
                            speechTimeout: speechTimeout,
                            requestTimeout: requestTimeout
                        )
                    )
                }) {
                    Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.circle")
                        .resizable()
                        .frame(width: speechRecognizer.isRecording ? 60 : 80, height: 80)
                        .foregroundColor(.blue)
                }

                Toggle("Native Audio", isOn: $nativeAudio)
                    .disabled(speechRecognizer.isRecording)
                    .foregroundColor(speechRecognizer.isRecording ? .gray : .primary) // Gray out when recording
                    .onChange(of: nativeAudio) { _, newValue in
                        // MARK: If nativeAudio is true, force speechTimeout to 0
                        if newValue {
                            setStatusMessage("⚠️ Disabled speech timeout!")
                            speechTimeout = 0
                        }
                    }

                HStack {
                    Text("Speech Timeout (Seconds)")
                        .foregroundColor(speechRecognizer.isRecording ? .gray : .primary) // Gray out when recording
                    Spacer()
                    Picker("", selection: $speechTimeout) {
                        ForEach(speechTimeoutRange, id: \.self) {
                            Text("\($0)").tag($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                    .disabled(speechRecognizer.isRecording)
                    .onChange(of: speechTimeout) { _, newValue in
                        // MARK: If speechTimeout has a value, force nativeAudio to false
                        if newValue > 0 {
                            setStatusMessage("⚠️ Disabled native audio!")
                            nativeAudio = false
                        }
                    }
                }

                HStack {
                    Text("Request Timeout (Seconds)")
                        .foregroundColor(speechRecognizer.isRecording ? .gray : .primary) // Gray out when recording
                    Spacer()
                    Picker("", selection: $requestTimeout) {
                        ForEach(requestTimeoutRange, id: \.self) {
                            Text("\($0)").tag($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 80)
                    .disabled(speechRecognizer.isRecording)
                }
            }
            .padding()
            .onAppear {
                speechRecognizer.requestPermissions()
            }

            if let displayMessage = statusMessage {
                Text(displayMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
                    .transition(.opacity)
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
        .alert("Error",
               isPresented: .constant(speechRecognizer.audioEngineError != nil || speechRecognizer.recognitionError != nil)) {
            Button("OK", role: .cancel) {
                speechRecognizer.audioEngineError = nil
                speechRecognizer.recognitionError = nil
            }
        } message: {
            Text(speechRecognizer.audioEngineError ?? speechRecognizer.recognitionError ?? "Unknown error")
        }
    }
}
