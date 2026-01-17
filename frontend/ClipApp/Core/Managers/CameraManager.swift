import AVFoundation
import UIKit
import Combine

@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?

    func requestAuthorization() async {
        let status = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = status ? .authorized : .denied
    }

    func setupSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let audioDevice = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.deviceNotFound
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        let audioInput = try AVCaptureDeviceInput(device: audioDevice)

        if session.canAddInput(videoInput) { session.addInput(videoInput) }
        if session.canAddInput(audioInput) { session.addInput(audioInput) }

        let output = AVCaptureMovieFileOutput()
        output.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)

        if session.canAddOutput(output) {
            session.addOutput(output)
            videoOutput = output
        }

        captureSession = session
    }

    func startSession() {
        captureSession?.startRunning()
    }

    func stopSession() {
        captureSession?.stopRunning()
    }
}

enum CameraError: Error {
    case deviceNotFound
    case configurationFailed
}
