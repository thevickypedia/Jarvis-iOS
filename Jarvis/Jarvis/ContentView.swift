//
//  ContentView.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI
import Speech
import AVFoundation
struct ContentView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()

    var body: some View {
        VStack(spacing: 30) {
            Text(speechRecognizer.recognizedText)
                .padding()
                .multilineTextAlignment(.center)

            Button(action: {
                speechRecognizer.toggleRecording()
            }) {
                Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.circle")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .onAppear {
            speechRecognizer.requestPermissions()
        }
    }
}
