import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import UIKit

import MWDATCore
import MWDATCamera

/// Real implementation of GlassesStreamProvider using Meta Wearables DAT SDK.
/// This wraps the official Meta SDK for Ray-Ban Meta glasses integration.
///
/// ## Setup Requirements
/// 1. Add the Meta Wearables SDK via SPM: https://github.com/facebook/meta-wearables-dat-ios
/// 2. Configure Info.plist with MetaAppID and URL scheme
/// 3. Ensure the glasses are paired via Meta View app
///
/// ## SDK Documentation
/// - Docs: https://wearables.developer.meta.com/docs/develop
/// - GitHub: https://github.com/facebook/meta-wearables-dat-ios
///
/// ## Audio Limitation
/// Audio streaming from glasses microphone is NOT yet supported in the Meta DAT SDK.
/// Wake word detection should use the iPhone's microphone instead.
@MainActor
final class MetaSDKProvider: GlassesStreamProvider {
    
    // MARK: - Publishers
    
    private let connectionStateSubject = CurrentValueSubject<GlassesConnectionState, Never>(.disconnected)
    private let videoFrameSubject = PassthroughSubject<CVPixelBuffer, Never>()
    private let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    
    // MARK: - Connection
    
    nonisolated var connectionState: GlassesConnectionState {
        connectionStateSubject.value
    }
    
    nonisolated var connectionStatePublisher: AnyPublisher<GlassesConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Video
    
    nonisolated var videoFramePublisher: AnyPublisher<CVPixelBuffer, Never> {
        videoFrameSubject.eraseToAnyPublisher()
    }
    
    private(set) var isVideoStreaming = false
    
    // MARK: - Audio
    
    private(set) var audioFormat: AVAudioFormat?
    
    nonisolated var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }
    
    private(set) var isAudioStreaming = false
    
    // MARK: - Device Info
    
    private(set) var batteryLevel: Int = 0
    private(set) var deviceName: String = "Ray-Ban Meta"
    
    // MARK: - SDK State
    
    private var wearables: (any WearablesInterface)? {
        didSet {
            setupRegistrationObserver()
        }
    }
    private var currentDevice: Device?
    private var streamSession: StreamSession?
    private var linkStateToken: (any AnyListenerToken)?
    private var registrationStateToken: (any AnyListenerToken)?
    private var videoFrameToken: (any AnyListenerToken)?
    private var streamStateToken: (any AnyListenerToken)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize audio format for speech recognition (16kHz mono)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        // Configure the SDK
        configureSDK()
    }
    
    deinit {
        // Cancel tokens
        Task { [linkStateToken, registrationStateToken, videoFrameToken, streamStateToken] in
            await linkStateToken?.cancel()
            await registrationStateToken?.cancel()
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
        }
    }
    
    // MARK: - SDK Configuration
    
    private func configureSDK() {
        do {
            try Wearables.configure()
            wearables = Wearables.shared
        } catch {
            print("[MetaSDKProvider] Failed to configure SDK: \(error)")
            connectionStateSubject.send(.error(.sdkNotAvailable))
        }
    }
    
    private func setupRegistrationObserver() {
        guard let wearables = wearables else { return }
        
        // Listen for registration state changes
        registrationStateToken = wearables.addRegistrationStateListener { [weak self] state in
            Task { @MainActor in
                self?.handleRegistrationStateChange(state)
            }
        }
        
        // Check initial state
        handleRegistrationStateChange(wearables.registrationState)
    }
    
    private func handleRegistrationStateChange(_ state: RegistrationState) {
        switch state {
        case .registered:
            // User is registered, check for devices
            checkForDevices()
        case .registering:
            connectionStateSubject.send(.connecting)
        case .available, .unavailable:
            if connectionState == .connected {
                connectionStateSubject.send(.disconnected)
                currentDevice = nil
            }
        @unknown default:
            break
        }
    }
    
    private func checkForDevices() {
        guard let wearables = wearables else { return }
        
        let deviceIds = wearables.devices
        guard let firstDeviceId = deviceIds.first,
              let device = wearables.deviceForIdentifier(firstDeviceId) else {
            connectionStateSubject.send(.error(.deviceNotFound))
            return
        }
        
        currentDevice = device
        deviceName = device.name
        observeDeviceLinkState(device)
        
        // Check current link state
        handleLinkStateChange(device.linkState)
    }
    
    private func observeDeviceLinkState(_ device: Device) {
        linkStateToken = device.addLinkStateListener { [weak self] linkState in
            Task { @MainActor in
                self?.handleLinkStateChange(linkState)
            }
        }
    }
    
    private func handleLinkStateChange(_ linkState: LinkState) {
        switch linkState {
        case .connected:
            connectionStateSubject.send(.connected)
        case .connecting:
            connectionStateSubject.send(.connecting)
        case .disconnected:
            connectionStateSubject.send(.disconnected)
            stopVideoStream()
        @unknown default:
            break
        }
    }
    
    // MARK: - Connection
    
    func connect() async throws {
        guard connectionState != .connected else { return }
        
        guard let wearables = wearables else {
            connectionStateSubject.send(.error(.sdkNotAvailable))
            throw GlassesError.sdkNotAvailable
        }
        
        connectionStateSubject.send(.connecting)
        
        // Check registration state
        switch wearables.registrationState {
        case .registered:
            // Already registered, check for devices
            checkForDevices()
            
            // Wait briefly for connection
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            if connectionState != .connected {
                // Check if we need camera permission
                do {
                    let status = try await wearables.checkPermissionStatus(.camera)
                    if status == .denied {
                        connectionStateSubject.send(.error(.permissionDenied))
                        throw GlassesError.permissionDenied
                    }
                } catch {
                    // Permission check failed, but we might still be able to connect
                }
            }
            
        case .available:
            // Need to start registration
            do {
                try wearables.startRegistration()
                // Registration will redirect to Meta AI app
                // The connection will complete when handleUrl is called
            } catch {
                connectionStateSubject.send(.error(.connectionFailed(error.localizedDescription)))
                throw GlassesError.connectionFailed(error.localizedDescription)
            }
            
        case .registering:
            // Already registering, wait for completion
            break
            
        case .unavailable:
            connectionStateSubject.send(.error(.sdkNotAvailable))
            throw GlassesError.sdkNotAvailable
            
        @unknown default:
            break
        }
    }
    
    func disconnect() {
        stopVideoStream()
        
        // Clear device reference
        currentDevice = nil
        
        connectionStateSubject.send(.disconnected)
    }
    
    // MARK: - URL Handling
    
    /// Handle URL callback from Meta AI app after registration/permission flow
    func handleURL(_ url: URL) async -> Bool {
        guard let wearables = wearables else { return false }
        
        do {
            return try await wearables.handleUrl(url)
        } catch {
            print("[MetaSDKProvider] Failed to handle URL: \(error)")
            return false
        }
    }
    
    // MARK: - Video Streaming
    
    func startVideoStream() async throws {
        guard connectionState == .connected else {
            throw GlassesError.notConnected
        }
        
        guard !isVideoStreaming else { return }
        
        guard let device = currentDevice else {
            throw GlassesError.notConnected
        }
        
        // Request camera permission if needed
        if let wearables = wearables {
            do {
                let status = try await wearables.requestPermission(.camera)
                if status == .denied {
                    throw GlassesError.permissionDenied
                }
            } catch let error as PermissionError {
                throw GlassesError.connectionFailed(error.description)
            }
        }
        
        // Create device selector for this specific device
        let deviceSelector = SpecificDeviceSelector(device: device.identifier)
        
        // Create stream session with config
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .medium,
            frameRate: 30
        )
        
        let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
        self.streamSession = session
        
        // Listen for video frames
        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                self?.handleVideoFrame(frame)
            }
        }
        
        // Listen for state changes
        streamStateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.handleStreamStateChange(state)
            }
        }
        
        // Start the session
        await session.start()
        
        // Check if streaming started successfully
        if session.state == .streaming {
            isVideoStreaming = true
        } else {
            throw GlassesError.streamFailed("Failed to start video stream")
        }
    }
    
    private func handleVideoFrame(_ frame: VideoFrame) {
        // Extract pixel buffer from CMSampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            return
        }
        
        videoFrameSubject.send(pixelBuffer)
    }
    
    private func handleStreamStateChange(_ state: StreamSessionState) {
        switch state {
        case .streaming:
            isVideoStreaming = true
        case .stopped, .stopping:
            isVideoStreaming = false
        case .paused:
            // Still technically streaming but paused
            break
        case .waitingForDevice, .starting:
            // Transitional states
            break
        @unknown default:
            break
        }
    }
    
    func stopVideoStream() {
        guard isVideoStreaming || streamSession != nil else { return }
        
        Task {
            await streamSession?.stop()
        }
        
        // Cancel listeners
        Task {
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
        }
        videoFrameToken = nil
        streamStateToken = nil
        streamSession = nil
        
        isVideoStreaming = false
    }
    
    // MARK: - Audio Streaming
    
    /// Audio streaming is NOT yet supported by the Meta DAT SDK.
    /// This method will always throw `GlassesError.audioNotSupported`.
    /// Use the iPhone's microphone for wake word detection instead.
    func startAudioStream() async throws {
        guard connectionState == .connected else {
            throw GlassesError.notConnected
        }
        
        // Audio streaming from glasses microphone is not yet supported in Meta DAT SDK.
        // The SDK currently only provides video streaming capabilities.
        // Wake word detection should use the iPhone's built-in microphone.
        throw GlassesError.audioNotSupported
    }
    
    func stopAudioStream() {
        // No-op since audio streaming is not supported
        isAudioStreaming = false
    }
}
