//
//  ContentView.swift
//  Jarvis
//
//  Created by Vignesh Rao on 8/28/25.
//

import SwiftUI

struct ContentView: View {
    @State private var knownServers: [String] = []
    @State private var showAddServerAlert = false
    @State private var newServerURL = ""
    @State private var serverURL = ""
    @State private var password = ""
    @AppStorage("useFaceID") private var useFaceID: Bool = false
    @EnvironmentObject var themeManager: ThemeManager
    @AppStorage("transitProtection") private var transitProtection = false

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isLoggedIn = false
    @State private var showLogoutMessage = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoggedIn {
                    RecorderView(serverURL: serverURL, password: password, transitProtection: transitProtection, handleLogout: handleLogout)
                } else {
                    loginView
                }
            }
        }
    }

    // FIXME: loadSession is being called redundantly
    var loginView: some View {
        VStack(spacing: 20) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .padding(.bottom, 10)

            Text("J.A.R.V.I.S")
                .font(.largeTitle)
                .bold()
                .padding(.top, 1)

            ServerURLMenu(
                serverURL: $serverURL,
                showAddServerAlert: $showAddServerAlert,
                knownServers: knownServers,
                newServerURL: $newServerURL,
                addNewServer: addNewServer
            ).padding(.top, 1)

            if useFaceID,
               let existingSession = KeychainHelper.loadSession(),
               existingSession["serverURL"] == serverURL {
                // Face ID mode with saved session
                Toggle("Login with Face ID", isOn: $useFaceID)
                    .padding(.top, 8)
                Toggle("Transit Protection", isOn: $transitProtection)

                Button(action: {
                    biometricSignIn()
                }) {
                    let username = existingSession["username"]
                    let labelText = (username?.isEmpty == false) ? "Login as \(username!)" : "Login with FaceID"
                    Label(labelText, systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .font(.headline)
                }
                .padding(.top, 6)
                Spacer().frame(height: 8)
                Button(action: {
                    KeychainHelper.deleteSession()
                    useFaceID = false
                }) {
                    Label("Switch User", systemImage: "person.crop.circle.badge.checkmark")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.gray)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .font(.headline)
                }
                .padding(.top, 4)
            } else {
                // Normal credential-based login
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Toggle("Use Face ID", isOn: $useFaceID)
                Toggle("Transit Protection", isOn: $transitProtection)

                Button(action: {
                    Task {
                        await login()
                    }
                }) {
                    if isLoading { ProgressView() } else {
                        // key.fill || person.badge.key.fill
                        Label("Login", systemImage: "person.badge.key.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .font(.headline)
                    }
                }
                .disabled(isLoading)
            }

            if let statusMessage = statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusMessage.contains("Logout") ? .orange : .green)
                    .padding()
                    .transition(.opacity)
            }

            Spacer()

            // 🌗 Theme toggle
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
            .padding(.bottom, 20)

            // Footer
            VStack(spacing: 2) {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let url = URL(string: "https://github.com/thevickypedia/Jarvis-iOS/releases/tag/v\(version)") {
                    Link("Version: \(version)", destination: url)
                        .font(.footnote)
                        .foregroundColor(.blue)
                } else {
                    Link("Version: unknown", destination: URL(string: "https://github.com/thevickypedia/Jarvis-iOS/releases")!)
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                Link("© 2025 Vignesh Rao", destination: URL(string: "https://vigneshrao.com")!)
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .onAppear {
            knownServers = KeychainHelper.loadKnownServers()
            if let session = KeychainHelper.loadSession(), let lastLoggedInURL = session["serverURL"] {
                serverURL = lastLoggedInURL
            } else if !knownServers.isEmpty {
                serverURL = knownServers.first ?? ""
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: { error in
            Text(error)
        }
    }

    func addNewServer() {
        // This should not happen since the button will not be visible (but just in case)
        if knownServers.count == 5 {
            errorMessage = "Server limit reached (5). Delete one to add a new server."
            return
        }
        let trimmed = newServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("http") else {
            if !trimmed.isEmpty { errorMessage = "Invalid URL: \(trimmed)" }
            return
        }

        if !knownServers.contains(trimmed) {
            knownServers.insert(trimmed, at: 0)
            KeychainHelper.saveKnownServers(knownServers)
        }

        serverURL = trimmed
        newServerURL = ""
        // Reset all auth state for better security
        password = ""
        useFaceID = false
    }

    func handleLogout(_ clearActiveServers: Bool = false) {

        isLoggedIn = false
        statusMessage = "⚠️ Logout successful!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            statusMessage = nil
        }
        // If neither remember nor useFaceID is enabled, remove any saved session
        if !useFaceID {
            KeychainHelper.deleteSession()
            KeychainHelper.deleteKnownServers()
        }
        // This is a temporary solution
        // Clears current serverURL and knownServers immediately
        if clearActiveServers {
            knownServers.removeAll()
            serverURL = ""
        }
    }

    func login() async -> Bool {
        if serverURL.isEmpty || password.isEmpty {
            Log.error("Missing credentials. URL: \(serverURL), Password Empty: \(password.isEmpty)")
            errorMessage = "Credentials are required to login!"
            return false
        }

        isLoading = true
        errorMessage = nil

        if serverURL.hasSuffix("/") {
            serverURL.removeLast()
        }

        guard let url = URL(string: "\(serverURL)/offline-communicator") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // condition ? valueIfTrue : valueIfFalse
        let authHeader = transitProtection ? "\\u" + convertStringToHex(password) : password

        // Add Authorization header
        request.setValue("Bearer \(authHeader)", forHTTPHeaderField: "Authorization")

        // Construct the JSON body with a test message to validate auth
        let payload: [String: Any] = [
            "command": "test",
            "native_audio": false,
            "speech_timeout": 0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            errorMessage = "Failed to encode JSON body"
            isLoading = false
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            isLoading = false

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                return false
            }

            if httpResponse.statusCode == 200 {
                isLoggedIn = true
                statusMessage = "✅ Login successful!"
                Log.info("✅ Login successful!")
                if useFaceID {
                    KeychainHelper.saveSession(serverURL: serverURL, password: password)
                } else {
                    // ensure any existing saved session is removed when the user opts out
                    KeychainHelper.deleteSession()
                    KeychainHelper.deleteKnownServers()
                }
                return true
            } else {
                errorMessage = "Request failed: \(httpResponse.statusCode)"
                return false
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    func biometricSignIn() {
        Log.info("🔐 Starting biometric authentication")
        KeychainHelper.authenticateWithBiometrics { success in
            guard success,
                  let session = KeychainHelper.loadSession(),
                  let serverURL = session["serverURL"],
                  let password = session["password"],
                  self.serverURL == serverURL
            else {
                DispatchQueue.main.async {
                    useFaceID = false
                }
                return
            }

            DispatchQueue.main.async {
                self.password = password
            }

            Task {
                Log.info("🔁 Initiating server handshake")
                let loginSuccess = await login()

                DispatchQueue.main.async {
                    if loginSuccess {
                        isLoggedIn = true
                        statusMessage = "✅ Face ID login successful!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            statusMessage = nil
                        }
                    } else {
                        useFaceID = false
                    }
                }
            }
        }
    }
}
