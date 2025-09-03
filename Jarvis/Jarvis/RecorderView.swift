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
    let pauseThreshold: Double
    let nonSpeakingDuration: Double
}

let defaultPauseThreshold = 1.5
let defaultNonSpeakingDuration = 3.0

struct RecorderView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @EnvironmentObject var themeManager: ThemeManager
    let serverURL: String
    let password: String
    let transitProtection: Bool
    let handleLogout: (_ clearActiveServers: Bool) -> Void

    @AppStorage("nativeAudio") private var nativeAudio = false
    @AppStorage("speechTimeout") private var speechTimeout = 0
    @AppStorage("requestTimeout") private var requestTimeout = 5
    @AppStorage("pauseThreshold") private var pauseThreshold: Double = defaultPauseThreshold
    @AppStorage("nonSpeakingDuration") private var nonSpeakingDuration: Double = defaultNonSpeakingDuration

    let speechTimeoutRange = Array(0..<30)
    let requestTimeoutRange = Array(0..<60)

    @State private var viewError: String?
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
                            requestTimeout: requestTimeout,
                            pauseThreshold: pauseThreshold,
                            nonSpeakingDuration: nonSpeakingDuration
                        )
                    )
                }) {
                    Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.circle")
                        .resizable()
                        .frame(width: speechRecognizer.isRecording ? 60 : 80, height: 80)
                        .foregroundColor(.blue)
                }

                DisclosureGroup("Server Settings") {
                    // Use Server's Native Audio
                    Toggle("Native Audio", isOn: $nativeAudio)
                        .disabled(speechRecognizer.isRecording)
                        .foregroundColor(speechRecognizer.isRecording ? .gray : .primary)
                        .onChange(of: nativeAudio) { newValue in
                            // MARK: If nativeAudio is true, force speechTimeout to 0
                            if newValue && speechTimeout != 0 {
                                setStatusMessage("⚠️ Disabled speech synthesis!")
                                speechTimeout = 0
                            }
                        }

                    // Speech Synthesis Timeout
                    HStack {
                        Text("Speech Synthesis Timeout (Seconds)")
                            .foregroundColor(speechRecognizer.isRecording ? .gray : .primary)
                        Spacer()
                        Picker("", selection: $speechTimeout) {
                            ForEach(speechTimeoutRange, id: \.self) {
                                Text("\($0)").tag($0)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 80)
                        .disabled(speechRecognizer.isRecording)
                        .onChange(of: speechTimeout) { newValue in
                            // MARK: If speechTimeout has a value, force nativeAudio to false
                            if newValue > 0 && nativeAudio {
                                setStatusMessage("⚠️ Disabled native audio!")
                                nativeAudio = false
                            }
                        }
                    }

                    // Request Timeout
                    HStack {
                        Text("Request Timeout (Seconds)")
                            .foregroundColor(speechRecognizer.isRecording ? .gray : .primary)
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

                DisclosureGroup("Recognizer Settings") {
                    // Seconds of non-speaking audio before a phrase is considered complete
                    HStack {
                        Text("Pause Threshold (Seconds)")
                            .foregroundColor(speechRecognizer.isRecording ? .gray : .primary)
                        Spacer()
                        TextField("Enter value", value: $pauseThreshold, format: .number)
                            .keyboardType(.decimalPad) // To allow decimal inputs
                            .disabled(speechRecognizer.isRecording)
                            .frame(width: 80)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: pauseThreshold) { newValue in
                                if newValue < 1 {
                                    viewError = "Pause threshold cannot be less than 1s"
                                    pauseThreshold = defaultPauseThreshold
                                }
                            }
                    }

                    // Seconds of non-speaking audio to keep on both sides of the recording
                    HStack {
                        Text("Non Speaking Duration (Seconds)")
                            .foregroundColor(speechRecognizer.isRecording ? .gray : .primary)
                        Spacer()
                        TextField("Enter value", value: $nonSpeakingDuration, format: .number)
                            .keyboardType(.decimalPad) // To allow decimal inputs
                            .disabled(speechRecognizer.isRecording)
                            .frame(width: 80)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: nonSpeakingDuration) { newValue in
                                if newValue < 1 {
                                    viewError = "Non speaking durationg cannot be less than 1s"
                                    nonSpeakingDuration = defaultNonSpeakingDuration
                                }
                            }
                    }
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
               isPresented: .constant(
                speechRecognizer.audioEngineError != nil || speechRecognizer.recognitionError != nil || viewError != nil
               )
        ) {
            Button("OK", role: .cancel) {
                speechRecognizer.audioEngineError = nil
                speechRecognizer.recognitionError = nil
                viewError = nil
            }
        } message: {
            Text(viewError ?? speechRecognizer.audioEngineError ?? speechRecognizer.recognitionError ?? "Unknown error")
        }
    }
}
