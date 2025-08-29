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

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if authStatus != .authorized {
                print("Speech recognition not authorized")
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                if !granted {
                    print("Microphone access denied")
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    print("Microphone access denied")
                }
            }
        }
    }

    func startRecording() {
        #if targetEnvironment(simulator)
        print("Simulator can't use microphone input.")
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
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                    print("Recognized: \(self.recognizedText)")
                }
            }

            if error != nil || (result?.isFinal ?? false) {
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
            print("Input Format: sampleRate = \(format.sampleRate), channels = \(format.channelCount)")

            guard format.sampleRate > 0, format.channelCount > 0 else {
                print("Invalid input format. Cannot start recording.")
                return
            }

            // STEP 3: Install tap
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                self.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Audio engine error: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil

        DispatchQueue.main.async {
            self.isRecording = false
            self.recognizedText = "Tap the mic to speak..."
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}
