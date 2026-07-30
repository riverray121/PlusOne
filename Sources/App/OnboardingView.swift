import SwiftUI
import AVFoundation
import FamilyControls
import UserNotifications

// One-pass setup: the three permissions, then the blocked list.
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    @State private var screenTimeGranted = false
    @State private var screenTimeError: String?
    @State private var cameraGranted = false
    @State private var notificationsGranted = false
    @State private var showPicker = false
    @State private var pickerBuffer = FamilyActivitySelection()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PlusOne blocks the apps you choose. To get in, take a selfie with someone; two faces buy you a timed session.")
                        .padding(.vertical, 4)
                }

                Section("Permissions") {
                    permissionRow(
                        done: screenTimeGranted,
                        title: "Screen Time",
                        detail: "Lets PlusOne block apps and websites."
                    ) { requestScreenTime() }
                    if let screenTimeError {
                        Text(screenTimeError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    permissionRow(
                        done: cameraGranted,
                        title: "Camera",
                        detail: "Runs the selfie check. Nothing is saved."
                    ) { requestCamera() }

                    permissionRow(
                        done: notificationsGranted,
                        title: "Notifications",
                        detail: "The blocked screen's unlock button reaches you through one."
                    ) { requestNotifications() }
                }

                Section {
                    Button {
                        showPicker = true
                    } label: {
                        Label(
                            appState.selfieBlockItemCount == 0
                                ? "Choose apps and websites to block"
                                : "\(pluralItems(appState.selfieBlockItemCount)) selected",
                            systemImage: "list.bullet"
                        )
                    }
                    .disabled(!screenTimeGranted)
                } footer: {
                    Text("You can change this list anytime.")
                }

                Section {
                    Button {
                        appState.protectionEnabled = true
                        appState.onboarded = true
                    } label: {
                        Text("Start protecting")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .disabled(!screenTimeGranted || appState.selfieBlockItemCount == 0)
                }
            }
            .navigationTitle("Welcome")
            // Same buffered-picker pattern as SelectionEditor: the picker
            // never holds a live binding to canonical state.
            .familyActivityPicker(isPresented: $showPicker, selection: $pickerBuffer)
            .onChange(of: showPicker) { presented in
                if presented {
                    pickerBuffer = appState.selection
                } else {
                    appState.selection = pickerBuffer
                }
            }
        }
    }

    private func permissionRow(done: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Permission requests

    private func requestScreenTime() {
        #if targetEnvironment(simulator)
        // Screen Time authorization always fails in the simulator; grant a
        // stub so the rest of the flow can be exercised there.
        screenTimeGranted = true
        #else
        Task {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                screenTimeGranted = true
                screenTimeError = nil
            } catch {
                screenTimeError = "Screen Time permission failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { cameraGranted = granted }
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { notificationsGranted = granted }
        }
    }
}
