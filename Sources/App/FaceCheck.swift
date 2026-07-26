import AVFoundation
import Vision
import UIKit

// Live two-face verification. Pass requires `requiredFaces` faces, each large
// enough to indicate physical presence, held for `holdDuration` of continuous
// video. On TrueDepth hardware each face must also deviate from a flat plane,
// which rejects faces shown on photos and screens. Frames never leave the
// capture pipeline.
//
// Depth path: faces come from AVCaptureMetadataOutput, whose rects convert
// into video-buffer pixel space via outputRectConverted, the same space the
// depth map is aligned to. No hand-rolled orientation math.
// 2D path (no TrueDepth: Macs, older devices): Vision detection only.
final class FaceCheck: NSObject, ObservableObject {
    static let requiredFaces = 2
    // Normalized face extent below which a face is treated as a background
    // face or a photo held at a distance.
    static let minFaceExtent: CGFloat = 0.12
    static let holdDuration: TimeInterval = 1.5
    // Minimum RMS deviation (meters) of a face region from its best-fit
    // plane. A tilted screen has depth spread but is still planar; a real
    // face has a nose. Screens and photos land near sensor noise.
    static let minDepthResidual: Float = 0.004
    // Minimum convexity (meters): how much closer the face's center sits than
    // its periphery. Real noses bulge toward the camera; flat and waved
    // screens don't, and curved photos rarely bulge in the right place.
    static let minDepthBump: Float = 0.005

    @Published var validFaceCount = 0
    @Published var progress: Double = 0
    @Published var passed = false
    @Published var cameraUnavailable = false
    @Published var depthActive = false
    #if DEBUG
    // Per-face plane residuals, for threshold tuning on device.
    @Published var debugDepthInfo = ""
    #endif

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
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
        if trueDepth != nil,
           session.canAddOutput(depthOutput),
           session.canAddOutput(metadataOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            session.addOutput(metadataOutput)
            if depthOutput.connection(with: .depthData) != nil,
               metadataOutput.availableMetadataObjectTypes.contains(.face) {
                metadataOutput.metadataObjectTypes = [.face]
                useDepth = true
            } else {
                session.removeOutput(depthOutput)
                session.removeOutput(metadataOutput)
            }
        }

        if useDepth {
            let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput, metadataOutput])
            sync.setDelegate(self, queue: processingQueue)
            synchronizer = sync
        } else {
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        }
        session.commitConfiguration()

        DispatchQueue.main.async { self.depthActive = useDepth }
    }

    // MARK: Shared pass/hold logic

    // validCount is the number of qualifying faces this frame.
    private func updateHold(validCount: Int, residuals: [Float]) {
        let qualifies = validCount >= Self.requiredFaces
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
            self.validFaceCount = validCount
            self.progress = progress
            if passed && !self.passed { self.passed = true }
            #if DEBUG
            self.debugDepthInfo = residuals.isEmpty
                ? ""
                : residuals.map { String(format: "%.1fmm", $0 * 1000) }.joined(separator: "  ")
            #endif
        }
    }

    // MARK: Depth path evaluation

    private func evaluateDepthPath(faces: [AVMetadataFaceObject], videoBuffer: CVPixelBuffer, depth: CVPixelBuffer) {
        let videoW = CGFloat(CVPixelBufferGetWidth(videoBuffer))
        let videoH = CGFloat(CVPixelBufferGetHeight(videoBuffer))
        guard videoW > 0, videoH > 0 else { return }

        var residuals: [Float] = []
        var validCount = 0
        for face in faces {
            // Metadata rect -> video-buffer pixel rect (Apple-provided
            // conversion), then normalized top-left-origin coordinates shared
            // by the aligned depth map.
            let pixelRect = videoOutput.outputRectConverted(fromMetadataOutputRect: face.bounds)
            let norm = CGRect(
                x: pixelRect.minX / videoW,
                y: pixelRect.minY / videoH,
                width: pixelRect.width / videoW,
                height: pixelRect.height / videoH
            )
            // The buffer is landscape while the phone is portrait, so face
            // height can land on either axis; use the larger extent.
            guard max(norm.width, norm.height) >= Self.minFaceExtent else { continue }

            let metrics = Self.depthMetrics(in: norm, depth: depth)
            residuals.append(contentsOf: [metrics.residual, metrics.bump])
            if metrics.residual >= Self.minDepthResidual, metrics.bump >= Self.minDepthBump {
                validCount += 1
            }
        }
        updateHold(validCount: validCount, residuals: residuals)
    }

    // MARK: 2D path evaluation

    private func detect2D(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !passed, !isProcessing else { return }
        isProcessing = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            let faces = (request.results as? [VNFaceObservation]) ?? []
            let valid = faces.filter { $0.boundingBox.height >= Self.minFaceExtent }
            self.updateHold(validCount: valid.count, residuals: [])
            self.isProcessing = false
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            isProcessing = false
        }
    }

    // MARK: Depth plane fit

    // Two liveness metrics for a face region, both in meters:
    // - residual: RMS deviation from the best-fit plane. Separates a 3D face
    //   from any flat surface at any tilt.
    // - bump: mean depth of the periphery minus the center. Positive when the
    //   region bulges toward the camera, as a nose does.
    // `normRect` is normalized with a top-left origin, matching buffer rows.
    private static func depthMetrics(in normRect: CGRect, depth: CVPixelBuffer) -> (residual: Float, bump: Float) {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depth) else { return (0, 0) }
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        let format = CVPixelBufferGetPixelFormatType(depth)

        // Central region only, so background pixels at the box edges don't
        // inflate the residual of a flat photo.
        let inset = normRect.insetBy(
            dx: normRect.width * 0.2,
            dy: normRect.height * 0.2
        )
        let x0 = max(0, Int(inset.minX * CGFloat(width)))
        let x1 = min(width - 1, Int(inset.maxX * CGFloat(width)))
        let y0 = max(0, Int(inset.minY * CGFloat(height)))
        let y1 = min(height - 1, Int(inset.maxY * CGFloat(height)))
        guard x1 > x0, y1 > y0 else { return (0, 0) }

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
                    return (0, 0)
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
        guard samples.count > 8 else { return (0, 0) }

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
        guard abs(det) > .ulpOfOne else { return (0, 0) }
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
        let residual = (sumSq / n).squareRoot()

        // Convexity: periphery depth minus center depth. Grid coords are
        // normalized [0, 1]; the center block is the middle third.
        var centerSum: Float = 0, centerN: Float = 0
        var ringSum: Float = 0, ringN: Float = 0
        for s in samples {
            if s.x > 0.33, s.x < 0.67, s.y > 0.33, s.y < 0.67 {
                centerSum += s.z; centerN += 1
            } else {
                ringSum += s.z; ringN += 1
            }
        }
        guard centerN > 0, ringN > 0 else { return (residual, 0) }
        let bump = ringSum / ringN - centerSum / centerN
        return (residual, bump)
    }
}

// Depth path: synchronized video + depth + face metadata.
extension FaceCheck: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard !passed,
              let videoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !videoData.sampleBufferWasDropped,
              let videoBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer),
              let depthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
              !depthData.depthDataWasDropped
        else { return }

        let faces = (synchronizedDataCollection.synchronizedData(for: metadataOutput) as? AVCaptureSynchronizedMetadataObjectData)?
            .metadataObjects.compactMap { $0 as? AVMetadataFaceObject } ?? []

        evaluateDepthPath(faces: faces, videoBuffer: videoBuffer, depth: depthData.depthData.depthDataMap)
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
        detect2D(in: pixelBuffer, orientation: orientation)
    }
}
