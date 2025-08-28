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
        recognizedText = "Listening..."
        
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        
        request = SFSpeechAudioBufferRecognitionRequest()
        
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
        
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request?.append(buffer)
        }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
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
