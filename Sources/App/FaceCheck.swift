import AVFoundation
import Vision
import UIKit

// Live two-face verification. Pass requires `requiredFaces` faces, each tall
// enough to indicate physical presence, held for `holdDuration` of continuous
// video. Frames never leave the capture pipeline.
final class FaceCheck: NSObject, ObservableObject {
    static let requiredFaces = 2
    // Normalized bounding-box height below which a face is treated as a
    // background face or a photo held at a distance.
    static let minFaceHeight: CGFloat = 0.12
    static let holdDuration: TimeInterval = 1.5

    @Published var validFaceCount = 0
    @Published var progress: Double = 0
    @Published var passed = false
    @Published var cameraUnavailable = false

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.riverray.plusone.facecheck")
    private var isProcessing = false
    private var holdStart: Date?

    func start() {
        processingQueue.async { [self] in
            configureIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        processingQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private var configured = false
    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            DispatchQueue.main.async { self.cameraUnavailable = true }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    private func evaluate(faces: [VNFaceObservation]) {
        let valid = faces.filter { $0.boundingBox.height >= Self.minFaceHeight }
        let qualifies = valid.count >= Self.requiredFaces

        let now = Date()
        if qualifies {
            if holdStart == nil { holdStart = now }
        } else {
            holdStart = nil
        }
        let elapsed = holdStart.map { now.timeIntervalSince($0) } ?? 0
        let progress = min(1, elapsed / Self.holdDuration)
        let passed = elapsed >= Self.holdDuration

        DispatchQueue.main.async {
            self.validFaceCount = valid.count
            self.progress = progress
            if passed && !self.passed { self.passed = true }
        }
    }
}

extension FaceCheck: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !passed, !isProcessing,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        isProcessing = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            self.evaluate(faces: (request.results as? [VNFaceObservation]) ?? [])
            self.isProcessing = false
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        do {
            try handler.perform([request])
        } catch {
            isProcessing = false
        }
    }
}
