import AVFoundation
import UIKit
import Vision

// Live two-face verification. Pass requires `requiredFaces` faces, each large
// enough to indicate physical presence, held for `holdDuration` of continuous
// video. On TrueDepth hardware each face must also deviate from a flat plane,
// which rejects faces shown on photos and screens. Frames never leave the
// capture pipeline; with `savesPhoto` on, the pass also triggers one
// full-resolution still, published as `capturedPhoto` for the owner to store.
//
// Rotation: video and depth buffers are pinned to the sensor's native
// orientation, which differs between camera modules and is not assumed. On
// iOS 17+ a RotationCoordinator supplies the preview and capture angles for
// the actual device.
//
// Depth path: faces come from AVCaptureMetadataOutput, whose rects convert
// into video-buffer pixel space via outputRectConverted, the same space the
// depth map is aligned to because both connections share one rotation.
// 2D path (no TrueDepth: Macs, older devices): Vision detection only.
final class FaceCheck: NSObject, ObservableObject {
    static let requiredFaces = 2
    // Normalized face extent below which a face is treated as a background
    // face or a photo held at a distance.
    static let minFaceExtent: CGFloat = 0.12
    static let holdDuration: TimeInterval = 1.5
    // Longest gap in qualifying frames the hold survives. A blink, a blurred
    // frame or a dropped buffer is shorter than this; losing a face for real
    // is longer, and starts the hold over.
    static let holdGrace: TimeInterval = 0.35
    // Minimum deviation (meters) of a face region from its best-fit
    // plane. A tilted screen has depth spread but is still planar; a real
    // face has a nose. Screens and photos land near sensor noise.
    static let minDepthResidual: Float = 0.004
    // Minimum convexity (meters): how much closer the face's center sits than
    // its periphery. Real noses bulge toward the camera; flat and waved
    // screens don't, and curved photos rarely bulge in the right place.
    static let minDepthBump: Float = 0.005
    // Max frame-to-frame drift (normalized) for a face to count. Fast motion
    // smears depth/video alignment into fake curvature; a smear needs speed,
    // and speed means drift. Still-but-flat surfaces fail the metrics anyway,
    // so this only has to catch a swing fast enough to smear a frame, not
    // ordinary hand shake.
    static let maxDrift: CGFloat = 0.08

    @Published var validFaceCount = 0
    @Published var progress: Double = 0
    @Published var passed = false
    @Published var cameraUnavailable = false
    @Published var depthActive = false
    // JPEG of the still taken at the pass. Only set when `savesPhoto` was on
    // before `start()`.
    @Published var capturedPhoto: Data?
    var savesPhoto = false
    #if DEBUG
    // Per-face depth metrics, for threshold tuning on device.
    @Published var debugDepthInfo = ""
    #endif

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    // A still in flight when stop() is called: stopping the session would
    // cancel it, so the stop waits for the photo callback.
    private var photoPending = false
    private var stopAfterPhoto = false
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let processingQueue = DispatchQueue(label: "com.riverray.plusone.facecheck")
    private var isProcessing = false
    // Qualifying time banked so far, and when the last qualifying frame
    // arrived. Only time between two qualifying frames is banked, so a gap
    // never counts toward the hold.
    private var heldDuration: TimeInterval = 0
    private var lastQualifyingFrame: Date?
    // processingQueue's copy of `passed`. The published property is written on
    // the main queue for the UI; frame callbacks read this one so no value
    // crosses threads unsynchronized.
    private var hasPassed = false
    // Face centers from the previous depth-path frame, for the drift gate.
    private var previousCenters: [CGPoint] = []
    // Clockwise rotation (degrees) that makes a native buffer upright, used
    // for the 2D path's Vision orientation and the still's connection. Owned
    // by processingQueue; the depth path works in buffer space and never
    // reads it.
    private var captureAngle: CGFloat = 90
    // iOS 16 Vision orientation per interface orientation, used while no
    // rotation coordinator runs. Owned by processingQueue.
    private var legacyExif: CGImagePropertyOrientation?

    // Main-queue state for the iOS 17+ rotation coordinator, which needs both
    // the configured device and the preview layer.
    private var device: AVCaptureDevice?
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AnyObject?
    private var rotationObservations: [NSKeyValueObservation] = []

    // Called on the main queue once the preview view exists.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        startRotationCoordinatorIfReady()
    }

    // iOS 16 fallback: derive the angles from the interface orientation,
    // assuming a landscape-native front sensor. Called on the main queue.
    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard rotationCoordinator == nil else { return }
        // Interface landscape names are the reverse of device landscape
        // names, which is why interface landscapeLeft pairs with upMirrored.
        let angle: CGFloat
        let exif: CGImagePropertyOrientation
        switch orientation {
        case .portraitUpsideDown: angle = 270; exif = .rightMirrored
        case .landscapeLeft: angle = 180; exif = .upMirrored
        case .landscapeRight: angle = 0; exif = .downMirrored
        default: angle = 90; exif = .leftMirrored
        }
        applyPreviewAngle(angle)
        processingQueue.async {
            self.captureAngle = angle
            self.legacyExif = exif
        }
    }

    // Reapplies the current preview angle; the preview connection only
    // exists once the session is configured.
    func reapplyPreviewAngle() {
        if #available(iOS 17.0, *),
           let coordinator = rotationCoordinator as? AVCaptureDevice.RotationCoordinator {
            applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        previewLayer?.connection?.apply(rotationAngle: angle)
    }

    private func startRotationCoordinatorIfReady() {
        guard #available(iOS 17.0, *),
              rotationCoordinator == nil,
              let device, let previewLayer
        else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                self?.applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                self?.processingQueue.async {
                    self?.captureAngle = angle
                    self?.legacyExif = nil
                }
            },
        ]
    }

    func start() {
        processingQueue.async { [self] in
            configureIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        processingQueue.async { [self] in
            if photoPending {
                stopAfterPhoto = true
            } else if session.isRunning {
                session.stopRunning()
            }
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

        // Data outputs physically rotate their buffers, and the default angle
        // varies by camera module. Pinning both to 0 keeps the depth map
        // aligned with the video buffer and makes captureAngle the full
        // rotation to upright.
        if #available(iOS 17.0, *) {
            videoOutput.connection(with: .video)?.apply(rotationAngle: 0)
            if useDepth { depthOutput.connection(with: .depthData)?.apply(rotationAngle: 0) }
        }

        if useDepth {
            let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput, metadataOutput])
            sync.setDelegate(self, queue: processingQueue)
            synchronizer = sync
        } else {
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        }
        let photoAdded = savesPhoto && session.canAddOutput(photoOutput)
        if photoAdded { session.addOutput(photoOutput) }
        session.commitConfiguration()

        // The still size is a property of the active format, independent of
        // the 640x480 video preset. Read after commit, when the preset has
        // settled the format.
        if photoAdded,
           let largest = device.activeFormat.supportedMaxPhotoDimensions
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            photoOutput.maxPhotoDimensions = largest
        }

        DispatchQueue.main.async {
            self.depthActive = useDepth
            self.device = device
            self.startRotationCoordinatorIfReady()
        }
    }

    // MARK: Shared pass/hold logic

    // validCount is the number of qualifying faces this frame. The hold banks
    // qualifying time rather than measuring elapsed time since it began, so a
    // gap shorter than `holdGrace` pauses it and anything longer clears it.
    // Resetting on the first imperfect frame would make a blink cost the whole
    // hold and force both people to hold unnaturally still.
    private func updateHold(validCount: Int) {
        let qualifies = validCount >= Self.requiredFaces
        let now = Date()
        if qualifies {
            if let gap = lastQualifyingFrame.map({ now.timeIntervalSince($0) }) {
                heldDuration = gap <= Self.holdGrace ? heldDuration + gap : 0
            }
            lastQualifyingFrame = now
        } else if let last = lastQualifyingFrame, now.timeIntervalSince(last) > Self.holdGrace {
            heldDuration = 0
            lastQualifyingFrame = nil
        }
        let progress = min(1, heldDuration / Self.holdDuration)
        let passed = heldDuration >= Self.holdDuration
        if passed && !hasPassed {
            hasPassed = true
            capturePhotoIfEnabled()
        }

        DispatchQueue.main.async {
            self.validFaceCount = validCount
            self.progress = progress
            if passed && !self.passed { self.passed = true }
        }
    }

    // MARK: Still capture

    private func capturePhotoIfEnabled() {
        guard photoOutput.connection(with: .video) != nil else { return }
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        photoOutput.connection(with: .video)?.apply(rotationAngle: captureAngle)
        photoPending = true
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    #if DEBUG
    // Refreshed at most twice a second so the values can be read and
    // screenshotted during threshold tuning.
    private var lastDebugUpdate = Date.distantPast
    private func updateDebug(_ lines: [String]) {
        let now = Date()
        guard now.timeIntervalSince(lastDebugUpdate) > 0.5 else { return }
        lastDebugUpdate = now
        let text = lines.enumerated()
            .map { "face\($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
        DispatchQueue.main.async { self.debugDepthInfo = text }
    }
    #endif

    // MARK: Depth path evaluation

    private func evaluateDepthPath(faces: [AVMetadataFaceObject], videoBuffer: CVPixelBuffer, depth: CVPixelBuffer) {
        let videoW = CGFloat(CVPixelBufferGetWidth(videoBuffer))
        let videoH = CGFloat(CVPixelBufferGetHeight(videoBuffer))
        guard videoW > 0, videoH > 0 else { return }

        var validCount = 0
        var centers: [CGPoint] = []
        #if DEBUG
        var debugFaces: [String] = []
        #endif
        for norm in Self.faceRects(faces: faces, videoBuffer: videoBuffer, videoOutput: videoOutput) {
            // The buffer is landscape while the phone is portrait, so face
            // height can land on either axis; use the larger extent.
            let extent = max(norm.width, norm.height)
            guard extent >= Self.minFaceExtent else {
                #if DEBUG
                debugFaces.append(String(format: "SMALL ext %.2f", extent))
                #endif
                continue
            }

            let metrics = Self.depthMetrics(in: norm, depth: depth)
            let solid = metrics.residual >= Self.minDepthResidual && metrics.bump >= Self.minDepthBump

            // Stability: the face must match one from the previous frame
            // within the drift limit. First sighting doesn't count yet.
            let center = CGPoint(x: norm.midX, y: norm.midY)
            centers.append(center)
            let still = previousCenters.contains {
                hypot($0.x - center.x, $0.y - center.y) <= Self.maxDrift
            }

            if solid && still { validCount += 1 }
            #if DEBUG
            debugFaces.append(String(format: "%@ ext %.2f res %.1fmm bump %.1fmm",
                                     !still ? "MOVE" : solid ? "PASS" : "FAIL",
                                     extent, metrics.residual * 1000, metrics.bump * 1000))
            #endif
        }
        previousCenters = centers
        updateHold(validCount: validCount)
        #if DEBUG
        updateDebug(debugFaces)
        #endif
    }


    // Face rects in normalized top-left-origin video-buffer coordinates,
    // shared by the aligned depth map. Landscape buffers use the metadata
    // faces through Apple's rect conversion. Portrait buffers (front cameras
    // whose sensor is not landscape-native) get faces from Vision on the
    // buffer itself, because outputRectConverted maps metadata rects as if
    // the buffer were landscape and lands them transposed.
    private static func faceRects(faces: [AVMetadataFaceObject], videoBuffer: CVPixelBuffer, videoOutput: AVCaptureVideoDataOutput) -> [CGRect] {
        let videoW = CGFloat(CVPixelBufferGetWidth(videoBuffer))
        let videoH = CGFloat(CVPixelBufferGetHeight(videoBuffer))
        guard videoW < videoH else {
            return faces.map { face in
                let pixelRect = videoOutput.outputRectConverted(fromMetadataOutputRect: face.bounds)
                return CGRect(
                    x: pixelRect.minX / videoW,
                    y: pixelRect.minY / videoH,
                    width: pixelRect.width / videoW,
                    height: pixelRect.height / videoH
                )
            }
        }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: videoBuffer, orientation: .up).perform([request])
        // Vision's origin is bottom-left; buffer rows run top-down.
        return (request.results ?? []).map { face in
            let box = face.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    // MARK: 2D path evaluation

    private func detect2D(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !hasPassed, !isProcessing else { return }
        isProcessing = true

        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            let faces = (request.results as? [VNFaceObservation]) ?? []
            let valid = faces.filter { $0.boundingBox.height >= Self.minFaceExtent }
            self.updateHold(validCount: valid.count)
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
    // - residual: robust deviation from the best-fit plane. Separates a 3D
    //   face from any flat surface at any tilt.
    // - bump: median depth of the periphery minus the center. Positive
    //   when the region bulges toward the camera, as a nose does.
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

        // Background rejection: keep only the contiguous surface around the
        // median depth. At steep angles a face box can hang past a screen's
        // edge, and far background samples fake both metrics.
        let sorted = samples.map(\.z).sorted()
        let median = sorted[sorted.count / 2]
        samples.removeAll { abs($0.z - median) > 0.15 }
        guard samples.count > 20 else { return (0, 0) }

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

        // Robust residual: MAD-based sigma, not RMS. Specular noise on a
        // glossy screen shows up as scattered spikes that inflate RMS; the
        // median deviation ignores them while a face's broad smooth curvature
        // still registers.
        let deviations = samples.map { abs($0.z - (a * $0.x + b * $0.y + c)) }.sorted()
        let residual = 1.4826 * deviations[deviations.count / 2]

        // Convexity: periphery median depth minus center median depth. Grid
        // coords are normalized [0, 1]; the center block is the middle third.
        // Medians for the same spike-immunity reason.
        var center: [Float] = []
        var ring: [Float] = []
        for s in samples {
            if s.x > 0.33, s.x < 0.67, s.y > 0.33, s.y < 0.67 {
                center.append(s.z)
            } else {
                ring.append(s.z)
            }
        }
        guard !center.isEmpty, !ring.isEmpty else { return (residual, 0) }
        let bump = ring.sorted()[ring.count / 2] - center.sorted()[center.count / 2]
        return (residual, bump)
    }
}

extension FaceCheck: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        processingQueue.async { [self] in
            photoPending = false
            if stopAfterPhoto, session.isRunning { session.stopRunning() }
        }
        if let data {
            DispatchQueue.main.async { self.capturedPhoto = data }
        }
    }
}

extension AVCaptureConnection {
    // Rotates the connection's output clockwise by `angle` degrees (0, 90,
    // 180 or 270).
    func apply(rotationAngle angle: CGFloat) {
        if #available(iOS 17.0, *) {
            if isVideoRotationAngleSupported(angle) {
                videoRotationAngle = angle
            }
        } else if isVideoOrientationSupported {
            switch angle {
            case 0: videoOrientation = .landscapeRight
            case 180: videoOrientation = .landscapeLeft
            case 270: videoOrientation = .portraitUpsideDown
            default: videoOrientation = .portrait
            }
        }
    }
}

extension CGImagePropertyOrientation {
    // The orientation of a buffer that needs `angle` degrees of clockwise
    // rotation to display upright. Front-camera mirroring is ignored: a
    // mirrored face is still a face to the detector.
    init(clockwiseRotation angle: CGFloat) {
        switch angle {
        case 90: self = .right
        case 180: self = .down
        case 270: self = .left
        default: self = .up
        }
    }
}

// Depth path: synchronized video + depth + face metadata.
extension FaceCheck: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard !hasPassed,
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
        // A Mac's camera delivers upright landscape frames regardless of
        // window arrangement; on iPhone and iPad the rotation follows the
        // device.
        let orientation: CGImagePropertyOrientation =
            ProcessInfo.processInfo.isiOSAppOnMac
            ? .upMirrored
            : legacyExif ?? CGImagePropertyOrientation(clockwiseRotation: captureAngle)
        detect2D(in: pixelBuffer, orientation: orientation)
    }
}
