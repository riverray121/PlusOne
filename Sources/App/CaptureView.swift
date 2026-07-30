import SwiftUI
import AVFoundation

// The unlock flow for one request: gate check, live two-face check, grant.
struct CaptureView: View {
    let target: UnlockTarget

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var faceCheck = FaceCheck()

    private enum Phase: Equatable {
        case refused(SessionManager.GateResult)
        case camera
        case granted
    }
    @State private var phase: Phase = .camera
    @State private var grantError = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .camera:
                    cameraView
                case .granted:
                    grantedView
                case .refused(let gate):
                    refusalView(for: gate)
                }
            }
            .navigationTitle(phase == .granted ? "" : "Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .granted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear {
            let gate = SessionManager.shared.gateCheck(for: target)
            guard gate == .allowed else {
                phase = .refused(gate)
                return
            }
            faceCheck.start()
        }
        .onDisappear { faceCheck.stop() }
        .onChange(of: faceCheck.passed) { passed in
            if passed { grant() }
        }
    }

    // MARK: Camera

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

                if faceCheck.depthActive {
                    Label("Depth check on: faces on photos or screens don't count.", systemImage: "cube.transparent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                #if DEBUG
                if !faceCheck.debugDepthInfo.isEmpty {
                    Text(faceCheck.debugDepthInfo)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                #endif
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

    // MARK: Granted

    private var grantedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("You're in")
                .font(.largeTitle.bold())
            Text("Return to your app. It's unlocked for \(pluralMinutes(SharedStore.shared.durationMinutes)) of use, then locks itself.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    // MARK: Refusals

    @ViewBuilder
    private func refusalView(for gate: SessionManager.GateResult) -> some View {
        switch gate {
        case .allowed:
            EmptyView()
        case .coolingDown(let remaining):
            refusalView(
                icon: "hourglass",
                title: "Cooling down",
                message: "Next unlock available in \(Self.minutesUp(remaining)) min."
            )
        case .capReached(let cap):
            refusalView(
                icon: "calendar.badge.exclamationmark",
                title: "Daily cap reached",
                message: "You've used all \(cap) unlock sessions today."
            )
        case .sessionActive:
            refusalView(
                icon: "lock.open",
                title: "Already unlocked",
                message: "This item has an active session. Open it directly."
            )
        }
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
        faceCheck.stop()
        // Screen Time calls are cross-process and can block for seconds;
        // keep them off the main thread so the UI stays responsive.
        Task.detached(priority: .userInitiated) {
            do {
                try SessionManager.shared.startSession(for: target)
                await MainActor.run {
                    appState.refresh()
                    phase = .granted
                }
            } catch {
                await MainActor.run { grantError = true }
            }
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
