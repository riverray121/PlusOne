import AVFoundation
import Vision
import UIKit

// Live two-face verification. Pass requires `requiredFaces` faces, each tall
// enough to indicate physical presence, held for `holdDuration` of continuous
// video. On TrueDepth hardware each face must also be a 3D surface, which
// rejects faces shown on photos and screens. Frames never leave the capture
// pipeline.
final class FaceCheck: NSObject, ObservableObject {
    static let requiredFaces = 2
    // Normalized bounding-box height below which a face is treated as a
    // background face or a photo held at a distance.
    static let minFaceHeight: CGFloat = 0.12
    static let holdDuration: TimeInterval = 1.5
    // Minimum RMS deviation (meters) of a face region from its best-fit
    // plane. A tilted screen has depth spread but is still planar; a real
    // face has a nose. Screens and photos land near sensor noise.
    static let minDepthResidual: Float = 0.004

    @Published var validFaceCount = 0
    @Published var progress: Double = 0
    @Published var passed = false
    @Published var cameraUnavailable = false
    @Published var depthActive = false
    #if DEBUG
    // Per-frame depth spreads, for threshold tuning on device.
    @Published var debugDepthInfo = ""
    #endif

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
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

    // MARK: Configuration

    private var configured = false
    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        // Prefer TrueDepth for the liveness check; fall back to any camera.
        let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        let device = trueDepth
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            DispatchQueue.main.async { self.cameraUnavailable = true }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        var useDepth = false
        if trueDepth != nil, session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            if depthOutput.connection(with: .depthData) != nil {
                useDepth = true
            } else {
                session.removeOutput(depthOutput)
            }
        }

        if useDepth {
            // Deliver both streams portrait so Vision rects map onto the depth
            // map without a coordinate transform.
            for output in [videoOutput as AVCaptureOutput, depthOutput] {
                if let conn = output.connections.first, conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
            }
            let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
            sync.setDelegate(self, queue: processingQueue)
            synchronizer = sync
        } else {
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        }
        session.commitConfiguration()

        DispatchQueue.main.async { self.depthActive = useDepth }
    }

    // MARK: Detection

    private func detectFaces(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, depth: CVPixelBuffer?) {
        guard !passed, !isProcessing else { return }
        isProcessing = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            self.evaluate(faces: (request.results as? [VNFaceObservation]) ?? [], depth: depth)
            self.isProcessing = false
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            isProcessing = false
        }
    }

    private func evaluate(faces: [VNFaceObservation], depth: CVPixelBuffer?) {
        let bigEnough = faces.filter { $0.boundingBox.height >= Self.minFaceHeight }

        var spreads: [Float] = []
        let valid = bigEnough.filter { face in
            guard let depth else { return true }
            let residual = Self.depthPlaneResidual(in: face.boundingBox, depth: depth)
            spreads.append(residual)
            return residual >= Self.minDepthResidual
        }
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
            #if DEBUG
            self.debugDepthInfo = spreads.isEmpty
                ? ""
                : spreads.map { String(format: "%.1fmm", $0 * 1000) }.joined(separator: "  ")
            #endif
        }
    }

    // RMS deviation (meters) of the central face region from its best-fit
    // plane. Distinguishes a 3D face from any flat surface at any tilt.
    // Vision rects are normalized with a bottom-left origin; the depth map
    // shares the video stream's portrait orientation.
    private static func depthPlaneResidual(in boundingBox: CGRect, depth: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depth) else { return 0 }
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        let format = CVPixelBufferGetPixelFormatType(depth)

        // Central region only, so background pixels at the box edges don't
        // inflate the spread of a flat photo.
        let inset = boundingBox.insetBy(
            dx: boundingBox.width * 0.2,
            dy: boundingBox.height * 0.2
        )
        let x0 = max(0, Int(inset.minX * CGFloat(width)))
        let x1 = min(width - 1, Int(inset.maxX * CGFloat(width)))
        // Flip y: Vision origin is bottom-left, buffer rows start at the top.
        let y0 = max(0, Int((1 - inset.maxY) * CGFloat(height)))
        let y1 = min(height - 1, Int((1 - inset.minY) * CGFloat(height)))
        guard x1 > x0, y1 > y0 else { return 0 }

        // 9x9 sample grid: (x, y, depth) triples for the plane fit.
        var samples: [(x: Float, y: Float, z: Float)] = []
        let steps = 8
        for iy in 0...steps {
            let y = y0 + (y1 - y0) * iy / steps
            let row = base.advanced(by: y * rowBytes)
            for ix in 0...steps {
                let x = x0 + (x1 - x0) * ix / steps
                var v: Float
                switch format {
                case kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32:
                    v = row.assumingMemoryBound(to: Float32.self)[x]
                case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DisparityFloat16:
                    v = Float(row.assumingMemoryBound(to: Float16.self)[x])
                default:
                    return 0
                }
                // Disparity is 1/meters; convert so the threshold is metric.
                if format == kCVPixelFormatType_DisparityFloat32 || format == kCVPixelFormatType_DisparityFloat16 {
                    v = v > 0 ? 1 / v : .nan
                }
                if v.isFinite {
                    samples.append((Float(ix) / Float(steps), Float(iy) / Float(steps), v))
                }
            }
        }
        guard samples.count > 8 else { return 0 }

        // Least-squares plane z = a*x + b*y + c via the 3x3 normal equations.
        let n = Float(samples.count)
        var sx: Float = 0, sy: Float = 0, sz: Float = 0
        var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
        var sxz: Float = 0, syz: Float = 0
        for s in samples {
            sx += s.x; sy += s.y; sz += s.z
            sxx += s.x * s.x; syy += s.y * s.y; sxy += s.x * s.y
            sxz += s.x * s.z; syz += s.y * s.z
        }
        let det = sxx * (syy * n - sy * sy)
            - sxy * (sxy * n - sy * sx)
            + sx * (sxy * sy - syy * sx)
        guard abs(det) > .ulpOfOne else { return 0 }
        let a = (sxz * (syy * n - sy * sy)
            - sxy * (syz * n - sy * sz)
            + sx * (syz * sy - syy * sz)) / det
        let b = (sxx * (syz * n - sy * sz)
            - sxz * (sxy * n - sx * sy)
            + sx * (sxy * sz - syz * sx)) / det
        let c = (sxx * (syy * sz - syz * sy)
            - sxy * (sxy * sz - syz * sx)
            + sxz * (sxy * sy - syy * sx)) / det

        // RMS of residuals from the fitted plane.
        let sumSq = samples.reduce(Float(0)) {
            let r = $1.z - (a * $1.x + b * $1.y + c)
            return $0 + r * r
        }
        return (sumSq / n).squareRoot()
    }
}

// Depth path: synchronized video + depth frames.
extension FaceCheck: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !videoData.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer)
        else { return }

        let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData
        let depthMap = (depthData?.depthDataWasDropped == false) ? depthData?.depthData.depthDataMap : nil

        // Connection is already portrait; only mirroring remains, which does
        // not affect detection.
        detectFaces(in: pixelBuffer, orientation: .upMirrored, depth: depthMap)
    }
}

// 2D-only path: hardware without TrueDepth (older devices, Macs).
extension FaceCheck: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // iPhone front camera delivers rotated portrait frames; a Mac's camera
        // delivers upright landscape ones.
        let orientation: CGImagePropertyOrientation =
            ProcessInfo.processInfo.isiOSAppOnMac ? .upMirrored : .leftMirrored
        detectFaces(in: pixelBuffer, orientation: orientation, depth: nil)
    }
}
