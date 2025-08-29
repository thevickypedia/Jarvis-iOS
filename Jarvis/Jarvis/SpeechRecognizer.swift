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

struct ServerResponse: Decodable {
    let detail: String
}

class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = "Tap the mic to speak..."
    @Published var isRecording = false
    @Published var audioEngineError: String?
    @Published var recognitionError: String?

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

    func parseServerResponse(data: Data?) -> String {
        if let data = data {
            do {
                let decoded = try JSONDecoder().decode(ServerResponse.self, from: data)
                return decoded.detail
            } catch {
                return String(data: data, encoding: .utf8) ?? "❌ JSON parsing failed and response is undecodable."
            }
        } else {
            return "❌ Empty response body."
        }
    }

    func makeServerRequestSync(
        serverURL: String,
        password: String,
        transitProtection: Bool,
        command: String
    ) -> String {
        guard let url = URL(string: "\(serverURL)/offline-communicator") else {
            return "❌ Invalid URL"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let authHeader = transitProtection ? "\\u" + convertStringToHex(password) : password
        request.setValue("Bearer \(authHeader)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "command": command,
            "native_audio": false,
            "speech_timeout": 0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return "❌ Failed to encode JSON: \(error.localizedDescription)"
        }

        var result = "❌ Request timed out after 5 seconds"
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = "❌ Network error: \(error.localizedDescription)"
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                result = "❌ Invalid response"
                return
            }

            if httpResponse.statusCode == 200 {
                Log.debug("✅ Server request successful")
                result = self.parseServerResponse(data: data)
            } else {
                result = "❌ Server response: [\(httpResponse.statusCode)]: \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            }
        }.resume()

        // ⏱ Block for up to 5 seconds
        let timeoutResult = semaphore.wait(timeout: .now() + 5)
        if timeoutResult == .timedOut {
            result = "❌ Request timed out after 5 seconds"
        }
        return result
    }

    func startRecording(serverURL: String, password: String, transitProtection: Bool) {
        #if targetEnvironment(simulator)
        Log.error("Simulator can't use microphone input.")
        DispatchQueue.main.async {
            self.audioEngineError = "Simulator can't record audio"
        }
        return
        #endif

        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)

        do {
            // STEP 1: Configure & activate audio session first
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // STEP 2: NOW fetch input format
            let format = node.inputFormat(forBus: 0)
            Log.info("Input Format: sampleRate = \(format.sampleRate), channels = \(format.channelCount)")

            guard format.sampleRate > 0, format.channelCount > 0 else {
                Log.error("Invalid input format. Cannot start recording.")
                DispatchQueue.main.async {
                    self.audioEngineError = "Invalid microphone input format."
                }
                return
            }

            // STEP 3: Install tap
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            self.startNoSpeechTimer()

            self.recognizedText = "Listening..."
            self.isRecording = true

            // ✅ STEP 4: NOW create the recognition request & task
            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true

            recognitionTask = speechRecognizer?.recognitionTask(with: request!) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    if !result.bestTranscription.formattedString.isEmpty {
                        self.cancelNoSpeechTimer()
                    }
                    if result.isFinal {
                        self.stopRecording(true)
                        self.recognizedText = "Processing..."
                        let command = result.bestTranscription.formattedString
                        Log.info("Server request: \(command)")
                        let response = self.makeServerRequestSync(
                            serverURL: serverURL,
                            password: password,
                            transitProtection: transitProtection,
                            command: command
                        )
                        Log.info("Server response: \(response)")
                        self.recognizedText = response
                    } else {
                        DispatchQueue.main.async {
                            self.recognizedText = result.bestTranscription.formattedString
                            Log.debug("Partial: \(result.bestTranscription.formattedString)")
                        }
                    // Only reset silence timer if listener is still active
                        self.resetSilenceTimer()
                    }
                }

                if let error = error {
                    Log.error("Recognition error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.recognitionError = error.localizedDescription
                    }
                    self.stopRecording()
                }
            }

        } catch {
            Log.error("Audio engine error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.audioEngineError = error.localizedDescription
            }
        }
    }

    func stopRecording(_ isProcessing: Bool = false) {
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
            if !isProcessing {
                self.recognizedText = "Tap the mic to speak..."
            }
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
