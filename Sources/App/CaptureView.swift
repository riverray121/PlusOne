import SwiftUI
import AVFoundation

// The unlock flow: gate check, live two-face check, then session grant.
struct CaptureView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var faceCheck = FaceCheck()

    @State private var gate: SessionManager.GateResult = .allowed
    @State private var granted = false
    @State private var grantError = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.pendingUnlock == nil {
                    noPendingView
                } else if granted {
                    grantedView
                } else {
                    switch gate {
                    case .allowed: cameraView
                    case .coolingDown(let remaining): refusalView(
                        icon: "hourglass",
                        title: "Cooling down",
                        message: "Next unlock available in \(Self.minutesUp(remaining)) min."
                    )
                    case .capReached(let cap): refusalView(
                        icon: "calendar.badge.exclamationmark",
                        title: "Daily cap reached",
                        message: "You've used all \(cap) unlock sessions today."
                    )
                    case .sessionActive: refusalView(
                        icon: "lock.open",
                        title: "Session already active",
                        message: "An unlock session is already running."
                    )
                    }
                }
            }
            .navigationTitle("Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        appState.clearPendingUnlock()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear {
            gate = SessionManager.shared.gateCheck()
            if gate == .allowed { faceCheck.start() }
        }
        .onDisappear { faceCheck.stop() }
        .onChange(of: faceCheck.passed) { passed in
            if passed { grant() }
        }
    }

    // MARK: Subviews

    private var cameraView: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreview(session: faceCheck.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                if faceCheck.cameraUnavailable {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.largeTitle)
                        Text("Camera unavailable")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                Label(
                    "\(faceCheck.validFaceCount) of \(FaceCheck.requiredFaces) people in frame",
                    systemImage: faceCheck.validFaceCount >= FaceCheck.requiredFaces ? "person.2.fill" : "person.2"
                )
                .font(.headline)
                .foregroundStyle(faceCheck.validFaceCount >= FaceCheck.requiredFaces ? .green : .primary)

                ProgressView(value: faceCheck.progress)
                    .tint(.green)

                Text("Get both faces close to the camera and hold still.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            #if targetEnvironment(simulator)
            // Simulator has no camera; this stub exists only for flow testing
            // and cannot be compiled into a device build.
            Button("Simulate two-face pass") { grant() }
                .buttonStyle(.borderedProminent)
            #endif
        }
        .padding()
        .alert("Couldn't start the session", isPresented: $grantError) {
            Button("OK") { dismiss() }
        } message: {
            Text("Screen Time monitoring refused the request. Try again.")
        }
    }

    private var grantedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Unlocked for \(SharedStore.shared.durationMinutes) minutes")
                .font(.title2.bold())
            Text("Reopen the app you were trying to use. It re-locks automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var noPendingView: some View {
        refusalView(
            icon: "app.badge",
            title: "Nothing to unlock",
            message: "Tap a blocked app first, then choose \u{201C}Unlock with a selfie.\u{201D}"
        )
    }

    private func refusalView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Grant

    private func grant() {
        guard let target = appState.pendingUnlock else { return }
        faceCheck.stop()
        do {
            try SessionManager.shared.startSession(for: target)
            appState.refresh()
            granted = true
        } catch {
            grantError = true
        }
    }

    private static func minutesUp(_ seconds: TimeInterval) -> Int {
        max(1, Int((seconds / 60).rounded(.up)))
    }
}

// Thin wrapper exposing the capture session's preview layer to SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
