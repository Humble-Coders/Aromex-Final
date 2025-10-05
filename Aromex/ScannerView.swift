import SwiftUI
import AVFoundation
import Vision
#if os(iOS)
import UIKit
#endif
import FirebaseFirestore

#if os(iOS)
struct ScannerView: View {
    // Optional close handler for when presented as a full-screen screen
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var captureSession: AVCaptureSession?
    @State private var cameraDelegate: CameraDelegate = CameraDelegate()
    @State private var detectedBarcodes: [String] = []
    @State private var showingBarcodeSelection = false
    @State private var currentVideoFrame: CMSampleBuffer?
    @State private var isCapturingPhoto = false
    @State private var capturedImage: UIImage?
    @State private var showingCapturedImage = false
    @State private var capturedImageBarcodes: [String] = []
    @State private var isFlashlightOn = true
    @State private var captureDevice: AVCaptureDevice?
    @State private var showConfirmation = false
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            ZStack {
                // Full screen background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with device-specific layout
                    Group {
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            // iPhone: Centered text with flashlight button on far right
                            ZStack {
                                // Centered text
                                VStack(spacing: 8) {
                                    Text("Scan Barcode")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Position the barcode within the frame")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                // Flashlight button on far right
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        toggleFlashlight()
                                    }) {
                                        Image(systemName: isFlashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                            .font(.system(size: 22, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                Circle()
                                                    .fill(Color.black.opacity(0.4))
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        } else {
                            // iPad: Centered layout without flashlight button
                            VStack(spacing: 8) {
                                Text("Scan Barcode")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Position the barcode within the frame")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 25)
                    .padding(.bottom, 25)
                    .padding(.horizontal, 20)
                    
                    // Camera preview area - responsive sizing
                    ZStack {
                        // Camera frame - larger on iPad
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.6), lineWidth: 3)
                            .frame(
                                width: UIDevice.current.userInterfaceIdiom == .pad ? 500 : 350,
                                height: UIDevice.current.userInterfaceIdiom == .pad ? 350 : 250
                            )
                        
                        // Camera preview - larger on iPad
                        if let session = captureSession {
                            CameraPreviewView(captureSession: .constant(session))
                                .frame(
                                    width: UIDevice.current.userInterfaceIdiom == .pad ? 480 : 330,
                                    height: UIDevice.current.userInterfaceIdiom == .pad ? 330 : 230
                                )
                                .cornerRadius(16)
                                .clipped()
                        }
                        
                        // Scanning overlay with corner indicators - responsive sizing
                        VStack {
                            HStack {
                                // Top-left corner
                                VStack(alignment: .leading, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                // Top-right corner
                                VStack(alignment: .trailing, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                }
                            }
                            Spacer()
                            HStack {
                                // Bottom-left corner
                                VStack(alignment: .leading, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                }
                                Spacer()
                                // Bottom-right corner
                                VStack(alignment: .trailing, spacing: 0) {
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30
                                        )
                                        .foregroundColor(.green)
                                    Rectangle()
                                        .frame(
                                            width: UIDevice.current.userInterfaceIdiom == .pad ? 40 : 30,
                                            height: UIDevice.current.userInterfaceIdiom == .pad ? 5 : 4
                                        )
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .frame(
                            width: UIDevice.current.userInterfaceIdiom == .pad ? 480 : 330,
                            height: UIDevice.current.userInterfaceIdiom == .pad ? 330 : 230
                        )
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 20 : 15) {
                        // Capture button
                        Button(action: {
                            capturePhoto()
                        }) {
                            HStack(spacing: 8) {
                                if isCapturingPhoto {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                Text(isCapturingPhoto ? "Processing..." : "Capture Photo")
                                    .font(.system(
                                        size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 16,
                                        weight: .semibold
                                    ))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 400 : .infinity)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 18 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12)
                                    .fill(Color.blue)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isCapturingPhoto)
                        
                        // Cancel button
                        Button(action: {
                            if let onClose = onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(
                                    size: UIDevice.current.userInterfaceIdiom == .pad ? 18 : 16,
                                    weight: .semibold
                                ))
                                .foregroundColor(.white)
                                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 400 : .infinity)
                                .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 18 : 14)
                                .background(
                                    RoundedRectangle(cornerRadius: UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12)
                                        .fill(Color.red.opacity(0.8))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    
                    Spacer()
                }
                
                // Captured image overlay
                if showingCapturedImage {
                    ScannerCapturedImageOverlay(
                        image: capturedImage,
                        barcodes: capturedImageBarcodes,
                        onSelect: { barcode in
                            saveBarcodeToFirestore(barcode)
                        },
                        onCancel: {
                            showingCapturedImage = false
                            capturedImage = nil
                            capturedImageBarcodes.removeAll()
                        },
                        onRetake: {
                            showingCapturedImage = false
                            capturedImage = nil
                            capturedImageBarcodes.removeAll()
                            isCapturingPhoto = false
                            // Turn flashlight back on for iPhone when retaking
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                ensureFlashlightOn()
                            }
                        }
                    )
                }
                
                // Barcode selection overlay
                if showingBarcodeSelection {
                    ScannerBarcodeSelectionOverlay(
                        barcodes: detectedBarcodes,
                        onCancel: {
                            showingBarcodeSelection = false
                            detectedBarcodes.removeAll()
                        }
                    )
                }
                
                // Confirmation overlay
                if showConfirmation {
                    ZStack {
                        Color.black.opacity(0.8).ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            
                            Text("Done")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Loading overlay
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.8).ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Saving...")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            setupCamera()
        }
        .onDisappear {
            stopCamera()
        }
    }
    
    private func setupCamera() {
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        // Get back camera device first
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to get camera device")
            return
        }
        
        self.captureDevice = device
        
        // Check device-specific preset support and set highest quality
        let deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        
        if device.supportsSessionPreset(.hd4K3840x2160) && captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
            print("Using 4K quality for \(deviceType) barcode scanning")
        } else if device.supportsSessionPreset(.hd1920x1080) && captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
            print("Using 1080p quality for \(deviceType) barcode scanning")
        } else if device.supportsSessionPreset(.hd1280x720) && captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
            print("Using 720p quality for \(deviceType) barcode scanning")
        } else {
            captureSession.sessionPreset = .high
            print("Using high quality preset for \(deviceType) barcode scanning")
        }
        
        captureSession.addInput(input)
        
        // Configure camera settings for highest quality
        do {
            try device.lockForConfiguration()
            
            // Set focus and exposure for barcode scanning
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Enable flashlight by default for iPhone only
            if UIDevice.current.userInterfaceIdiom == .phone && device.hasTorch && device.isTorchAvailable {
                device.torchMode = .on
                try device.setTorchModeOn(level: 1.0)
                print("Flashlight enabled for iPhone barcode scanning")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure camera: \(error)")
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        // Set video output to match session preset for highest quality
        let preset = captureSession.sessionPreset
        var width: Int = 1920
        var height: Int = 1080
        
        switch preset {
        case .hd4K3840x2160:
            width = 3840
            height = 2160
        case .hd1920x1080:
            width = 1920
            height = 1080
        case .hd1280x720:
            width = 1280
            height = 720
        default:
            width = 1920
            height = 1080
        }
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = false
        
        cameraDelegate.onBarcodeDetected = { (barcodes: [String]) in
            // Auto-scanning disabled - user must capture manually
        }
        
        cameraDelegate.onFrameReceived = { sampleBuffer in
            DispatchQueue.main.async {
                self.currentVideoFrame = sampleBuffer
            }
        }
        
        let videoQueue = DispatchQueue(label: "com.aromex.scanner.videoQueue", qos: .userInitiated)
        videoOutput.setSampleBufferDelegate(cameraDelegate, queue: videoQueue)
        
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
        
        DispatchQueue.main.async {
            self.captureSession = captureSession
            captureSession.startRunning()
            
            // Ensure flashlight is on after session starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.ensureFlashlightOn()
            }
        }
    }
    
    private func capturePhoto() {
        guard let videoFrame = currentVideoFrame else { return }
        
        isCapturingPhoto = true
        
        // Convert frame to image and freeze the display
        if let image = imageFromSampleBuffer(videoFrame) {
            DispatchQueue.main.async {
                self.capturedImage = image
                self.showingCapturedImage = true
                self.isCapturingPhoto = false
                // Turn off flashlight after capture (iPhone only)
                if UIDevice.current.userInterfaceIdiom == .phone,
                   let device = self.captureDevice, device.hasTorch {
                    do {
                        try device.lockForConfiguration()
                        device.torchMode = .off
                        device.unlockForConfiguration()
                        self.isFlashlightOn = false
                    } catch {
                        print("Failed to turn off flashlight after capture: \(error)")
                    }
                }
            }
            
            // Analyze the frame for barcodes in background
            analyzeFrameForBarcodes(videoFrame)
        } else {
            isCapturingPhoto = false
        }
    }
    
    private func analyzeFrameForBarcodes(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectBarcodesRequest { request, error in
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            let barcodes = results.compactMap { $0.payloadStringValue }
            
            DispatchQueue.main.async {
                self.capturedImageBarcodes = barcodes
                
                // Always show captured image so user can verify and retake if needed
                // The captured image overlay will handle single/multiple/no barcode scenarios
            }
        }
        
        request.revision = VNDetectBarcodesRequestRevision3
        request.symbologies = [.QR, .Aztec, .DataMatrix, .PDF417, .Code128, .Code93, .Code39, .EAN13, .EAN8, .UPCE]
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    private func stopCamera() {
        // Turn off flashlight before stopping camera (iPhone only)
        if UIDevice.current.userInterfaceIdiom == .phone,
           let device = captureDevice, device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                print("Flashlight turned off when stopping camera")
            } catch {
                print("Failed to turn off flashlight: \(error)")
            }
        }
        
        captureSession?.stopRunning()
        captureSession = nil
    }
    
    private func toggleFlashlight() {
        // Only allow flashlight toggle on iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let device = captureDevice, 
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            if isFlashlightOn {
                device.torchMode = .off
                isFlashlightOn = false
                print("Flashlight turned off")
            } else {
                if device.isTorchAvailable {
                    device.torchMode = .on
                    try device.setTorchModeOn(level: 1.0)
                    isFlashlightOn = true
                    print("Flashlight turned on")
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to toggle flashlight: \(error)")
        }
    }
    
    private func ensureFlashlightOn() {
        // Only ensure flashlight is on for iPhone
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let device = captureDevice, 
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Force flashlight to stay on
            if device.isTorchAvailable {
                device.torchMode = .on
                try device.setTorchModeOn(level: 1.0)
                isFlashlightOn = true
                print("Flashlight ensured to be on for iPhone")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Failed to ensure flashlight on: \(error)")
        }
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        // Create UIImage with correct orientation for iPhone
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        return image
    }
    
    private func saveBarcodeToFirestore(_ barcode: String) {
        isSaving = true
        
        let db = Firestore.firestore()
        
        db.collection("Data").document("scanner").setData([
            "barcode": barcode
        ], merge: true) { error in
            DispatchQueue.main.async {
                isSaving = false
                if let error = error {
                    print("Error saving barcode: \(error)")
                } else {
                    showConfirmation = true
                    // Auto-dismiss after 1 second and return to scanner screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showConfirmation = false
                        // Return to scanner screen by dismissing the captured image overlay
                        showingCapturedImage = false
                        capturedImage = nil
                        capturedImageBarcodes.removeAll()
                        // Turn flashlight back on for iPhone when returning to scanner
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            ensureFlashlightOn()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Scanner Captured Image Overlay

struct ScannerCapturedImageOverlay: View {
    let image: UIImage?
    let barcodes: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    let onRetake: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Captured Image")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    if barcodes.isEmpty {
                        Text("No barcodes detected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    } else if barcodes.count == 1 {
                        Text("1 barcode detected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("\(barcodes.count) barcodes detected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                // Image preview
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
                
                // Barcode list with refined UI
                if barcodes.count > 1 {
                    VStack(spacing: UIDevice.current.userInterfaceIdiom == .pad ? 8 : 16) {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(barcodes.enumerated()), id: \.offset) { index, barcode in
                                    Button(action: {
                                        onSelect(barcode)
                                    }) {
                                        HStack(spacing: 16) {
                                            // Number badge with gradient
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient(
                                                        colors: [.blue, .blue.opacity(0.8)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ))
                                                    .frame(width: 36, height: 36)
                                                
                                                Text("\(index + 1)")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                            
                                            // Barcode content
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(barcode)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(2)
                                                    .truncationMode(.tail)
                                                
                                                Text("Tap to use this barcode")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            
                                            Spacer()
                                            
                                            // Selection arrow
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                    }
                    .frame(maxHeight: UIDevice.current.userInterfaceIdiom == .pad ? 600 : 320)
                } else if barcodes.count == 1 {
                    // Single barcode display
                    VStack(spacing: 16) {
                        Text("Detected barcode:")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Button(action: {
                            onSelect(barcodes[0])
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                                
                                Text(barcodes[0])
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                
                                Spacer()
                                
                                Text("Tap to use")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 30 : 20)
                            .padding(.vertical, UIDevice.current.userInterfaceIdiom == .pad ? 20 : 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.green.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .pad ? 40 : 20)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 15) {
                    
                    // Retake button
                    Button(action: onRetake) {
                        Text("Retake Photo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Cancel button
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.8))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Scanner Barcode Selection Overlay

struct ScannerBarcodeSelectionOverlay: View {
    let barcodes: [String]
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Multiple Barcodes Detected")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Multiple barcodes were found in the image")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 40)
                .padding(.bottom, 20)
                
                // Barcode list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(barcodes.enumerated()), id: \.offset) { index, barcode in
                            VStack(spacing: 8) {
                                Text("Barcode \(index + 1)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text(barcode)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.8))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}


#endif
