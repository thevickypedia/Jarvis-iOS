//
//  SpeechRecognizer.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import Foundation
import AVFoundation
import Speech
import Combine

class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = "Tap the mic to speak..."
    @Published var isRecording = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var noSpeechTimer: Timer?

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if authStatus != .authorized {
                Log.error("Speech recognition not authorized")
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    Log.error("Microphone access denied")
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    Log.error("Microphone access denied")
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Log.info("Silence detected, stopping...")
            self?.stopRecording()
        }
    }

    private func startNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Log.info("No speech detected. Auto-stopping.")
            self?.stopRecording()
        }
    }

    private func cancelNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
    }

    func makeServerRequest(serverURL: String, password: String, transitProtection: Bool) {
        guard let url = URL(string: "\(serverURL)/offline-communicator") else {
            Log.error("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let authHeader = transitProtection ? "\\u" + convertStringToHex(password) : password
        request.setValue("Bearer \(authHeader)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "command": self.recognizedText,
            "native_audio": false,
            "speech_timeout": 0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            Log.error("Failed to encode JSON: \(error.localizedDescription)")
            return
        }

        // Use URLSession dataTask with a completion handler
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.error("Network error: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                Log.error("Invalid response")
                return
            }

            if httpResponse.statusCode == 200 {
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    Log.info("📦 Server Response: \(responseString)")
                    // TODO: Dispatch and display
                } else {
                    Log.info("📦 Empty response body or decoding failed.")
                }
            } else {
                Log.error("❌ Server responded with status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

    func startRecording(serverURL: String, password: String, transitProtection: Bool) {
        #if targetEnvironment(simulator)
        Log.error("Simulator can't use microphone input.")
        recognizedText = "Simulator can't record audio"
        return
        #endif

        recognizedText = "Listening..."

        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                if !result.bestTranscription.formattedString.isEmpty {
                    self.cancelNoSpeechTimer()
                }
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.recognizedText = result.bestTranscription.formattedString
                        Log.info("Final recognized: \(self.recognizedText)")
                        self.makeServerRequest(serverURL: serverURL, password: password, transitProtection: transitProtection)
                    }
                    self.stopRecording()
                } else {
                    DispatchQueue.main.async {
                        self.recognizedText = result.bestTranscription.formattedString
                        Log.debug("Partial: \(result.bestTranscription.formattedString)")
                    }
                }

                // Reset silence timer every time speech is detected
                self.resetSilenceTimer()
            }

            if let error = error {
                Log.error("Recognition error: \(error.localizedDescription)")
                self.stopRecording()
            }
        }

        do {
            // STEP 1: Configure & activate audio session first
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // STEP 2: NOW fetch input format (will be valid)
            let format = node.inputFormat(forBus: 0)
            Log.info("Input Format: sampleRate = \(format.sampleRate), channels = \(format.channelCount)")

            guard format.sampleRate > 0, format.channelCount > 0 else {
                Log.error("Invalid input format. Cannot start recording.")
                return
            }

            // STEP 3: Install tap
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            self.startNoSpeechTimer()

            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            Log.error("Audio engine error: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Flush final result instead of killing early
        recognitionTask?.finish()
        recognitionTask = nil
        request = nil

        silenceTimer?.invalidate()
        silenceTimer = nil
        cancelNoSpeechTimer()

        DispatchQueue.main.async {
            self.isRecording = false
            self.recognizedText = "Tap the mic to speak..."
        }
    }

    func toggleRecording(serverURL: String, password: String, transitProtection: Bool) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(serverURL: serverURL, password: password, transitProtection: transitProtection)
        }
    }
}
