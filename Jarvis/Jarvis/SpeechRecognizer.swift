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

    func parseTextResponse(data: Data?) -> String {
        guard let textData = data else {
            return "❌ Empty response body."
        }
        do {
            let decoded = try JSONDecoder().decode(ServerResponse.self, from: textData)
            return decoded.detail
        } catch {
            return String(data: textData, encoding: .utf8) ?? "❌ JSON parsing failed and response is undecodable."
        }
    }

    func parseAudioResponse(data: Data?) -> String {
        guard let audioData = data else {
            return "❌ Empty response body."
        }
        var result = ""
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        let audioFileURL = tempDirectory.appendingPathComponent("speech_file.wav")

        do {
            // Debugging: Ensure the file is saved
            try audioData.write(to: audioFileURL)
            Log.debug("✅ Audio file saved to \(audioFileURL)")

            // Ensure the file exists
            if fileManager.fileExists(atPath: audioFileURL.path) {
                Log.debug("✅ Audio file exists: \(audioFileURL.path)")
            } else {
                Log.debug("❌ Audio file does not exist.")
            }

            // Set up the audio session to allow playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)

            // Keep player as a class-level variable to avoid it being deallocated
            var player: AVAudioPlayer?
            player = try AVAudioPlayer(contentsOf: audioFileURL)
            player?.volume = 1.0 // Max volume (0.0 to 1.0)
            player?.play()

            // ✅ Block until audio finishes playing
            while let p = player, p.isPlaying {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            Log.debug("✅ Audio finished playing.")

            // Clean up file
            do {
                try fileManager.removeItem(at: audioFileURL)
                Log.debug("✅ Audio file deleted after playback.")
            } catch {
                Log.debug("❌ Failed to delete audio file: \(error.localizedDescription)")
            }
            result = "✅ Played and deleted audio file"
        } catch {
            result = "❌ Audio error: \(error.localizedDescription)"
        }
        return result
    }

    func makeServerRequestSync(
        serverURL: String,
        password: String,
        transitProtection: Bool,
        command: String,
        advancedSettings: AdvancedSettings
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

        // TODO: Set these args via advancedSettings
        let payload: [String: Any] = [
            "command": command,
            "native_audio": advancedSettings.nativeAudio,
            "speech_timeout": advancedSettings.speechTimeout
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
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "NO MATCH"
                if contentType == "application/octet-stream", let data = data {
                    result = self.parseAudioResponse(data: data)
                } else {
                    result = self.parseTextResponse(data: data)
                }
            } else {
                result = "❌ Server response: [\(httpResponse.statusCode)]: \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"
            }
        }.resume()

        let delay: DispatchTimeInterval = (
            advancedSettings.nativeAudio || advancedSettings.speechTimeout != 0
        ) ? .seconds(30) : .seconds(5)
        let timeoutResult = semaphore.wait(timeout: .now() + delay)
        if timeoutResult == .timedOut {
            result = "❌ Request timed out after 5 seconds"
        }

        return result
    }

    func startRecording(serverURL: String, password: String, transitProtection: Bool, advancedSettings: AdvancedSettings) {
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
                        self.recognizedText = "Processing..."
                        self.stopRecording(true)
                        let command = result.bestTranscription.formattedString
                        Log.info("Server request: \(command)")
                        DispatchQueue.global(qos: .userInitiated).async {
                            let response = self.makeServerRequestSync(
                                serverURL: serverURL,
                                password: password,
                                transitProtection: transitProtection,
                                command: command,
                                advancedSettings: advancedSettings
                            )
                            // TODO: Move display logic to `makeServerRequestSync`
                            Log.info("Server response: \(response)")
                            DispatchQueue.main.async {
                                self.recognizedText = response
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                                self.recognizedText = "Tap the mic to speak..."
                            }
                        }
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

    func toggleRecording(
        serverURL: String,
        password: String,
        transitProtection: Bool,
        advancedSettings: AdvancedSettings
    ) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(
                serverURL: serverURL,
                password: password,
                transitProtection: transitProtection,
                advancedSettings: advancedSettings
            )
        }
    }
}
