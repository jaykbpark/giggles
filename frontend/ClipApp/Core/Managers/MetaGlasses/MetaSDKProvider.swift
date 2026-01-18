import AVFoundation
import Combine
import CoreLocation
import CoreMedia
import CoreVideo
import UIKit
import os.log

import MWDATCore
import MWDATCamera

// #region agent log
private let debugLog = OSLog(subsystem: "me.lin.erik.nw2026", category: "MetaSDK")
// #endregion

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
    private let timestampedVideoFrameSubject = PassthroughSubject<TimestampedVideoFrame, Never>()
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
    
    nonisolated var timestampedVideoFramePublisher: AnyPublisher<TimestampedVideoFrame, Never> {
        timestampedVideoFrameSubject.eraseToAnyPublisher()
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
    
    /// Debug status for UI display
    var debugStatus: String {
        guard let wearables = wearables else {
            return "SDK:nil"
        }
        let regState: String
        switch wearables.registrationState {
        case .available: regState = "avail"
        case .registered: regState = "reg"
        case .registering: regState = "reg..."
        case .unavailable: regState = "unavail"
        @unknown default: regState = "?"
        }
        let devCount = wearables.devices.count
        if devCount == 0 && wearables.registrationState == .registered {
            return "\(regState) Dev:\(devCount) - Tap Retry to authorize"
        }
        return "\(regState) Dev:\(devCount)"
    }
    
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
    
    // Location manager for BLE device discovery (iOS requires location for BLE scanning)
    private let locationManager = CLLocationManager()
    
    // MARK: - Initialization
    
    init() {
        // Initialize audio format for speech recognition (16kHz mono)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
        
        // Request location permission (required for BLE device discovery on iOS)
        locationManager.requestWhenInUseAuthorization()
        
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
            // #region agent log H2,H3
            os_log("[DEBUG-H2H3] SDK configured. RegState=%{public}@ DeviceCount=%{public}d", log: debugLog, type: .error, String(describing: wearables?.registrationState), wearables?.devices.count ?? 0)
            // #endregion
        } catch {
            // #region agent log H2
            os_log("[DEBUG-H2] SDK config FAILED: %{public}@", log: debugLog, type: .error, String(describing: error))
            // #endregion
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
        
        // Start periodic device checking (devices may appear asynchronously)
        startDevicePolling()
    }
    
    private var devicePollTask: Task<Void, Never>?
    
    private func startDevicePolling() {
        devicePollTask?.cancel()
        devicePollTask = Task { [weak self] in
            // Poll for devices every 2 seconds for 30 seconds
            for _ in 0..<15 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                guard let self = self else { return }
                let deviceCount = self.wearables?.devices.count ?? 0
                print("[MetaSDK] Device poll: \(deviceCount) devices")
                
                if deviceCount > 0 && self.connectionState != .connected {
                    self.checkForDevices()
                    if self.connectionState == .connected {
                        return // Stop polling once connected
                    }
                }
            }
        }
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
        // #region agent log H1,H5
        os_log("[DEBUG-H1H5] checkForDevices: found %{public}d device(s)", log: debugLog, type: .error, deviceIds.count)
        // #endregion
        guard let firstDeviceId = deviceIds.first,
              let device = wearables.deviceForIdentifier(firstDeviceId) else {
            // #region agent log H1,H5
            os_log("[DEBUG-H1H5] checkForDevices: NO devices found - sending deviceNotFound error", log: debugLog, type: .error)
            // #endregion
            connectionStateSubject.send(.error(.deviceNotFound))
            return
        }
        
        // #region agent log H5
        os_log("[DEBUG-H5] checkForDevices: found device '%{public}@' linkState=%{public}@", log: debugLog, type: .error, device.name, String(describing: device.linkState))
        // #endregion
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
        
        // Check registration state first
        print("[MetaSDK] Registration state: \(wearables.registrationState)")
        print("[MetaSDK] Devices count: \(wearables.devices.count)")
        
        // If we have devices, try to connect to them
        if wearables.devices.count > 0 {
            checkForDevices()
            if connectionState == .connected {
                print("[MetaSDK] Connected to existing device!")
                return
            }
        }
        
        // No devices found - need to trigger the Meta AI app authorization flow
        // startRegistration() opens Meta AI app for the user to grant access
        print("[MetaSDK] No devices found. Registration state: \(wearables.registrationState)")
        print("[MetaSDK] Opening Meta AI app for authorization...")
        
        do {
            // startRegistration() should open Meta AI app
            try wearables.startRegistration()
            print("[MetaSDK] startRegistration called - Meta AI app should open")
            // The app will redirect back via URL scheme, handled by handleURL()
            return
        } catch {
            print("[MetaSDK] startRegistration error: \(error)")
            print("[MetaSDK] Trying requestPermission as fallback...")
        }
        
        // Fallback: try requestPermission
        do {
            let status = try await wearables.requestPermission(.camera)
            print("[MetaSDK] Permission status: \(status)")
            
            if status == .granted {
                // Permission granted, check for devices
                print("[MetaSDK] Permission granted! Checking for devices...")
                
                // Give SDK time to discover devices after permission grant
                for attempt in 1...5 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    print("[MetaSDK] Device check attempt \(attempt), count: \(wearables.devices.count)")
                    
                    if wearables.devices.count > 0 {
                        checkForDevices()
                        if connectionState == .connected {
                            print("[MetaSDK] Connected!")
                            return
                        }
                    }
                }
                
                // Still no devices after permission granted
                print("[MetaSDK] Permission granted but no devices found")
                connectionStateSubject.send(.error(.deviceNotFound))
                
            } else if status == .denied {
                print("[MetaSDK] Permission denied by user")
                connectionStateSubject.send(.error(.permissionDenied))
                throw GlassesError.permissionDenied
                
            } else {
                print("[MetaSDK] Permission status: \(status)")
                connectionStateSubject.send(.disconnected)
            }
        } catch let error as PermissionError {
            print("[MetaSDK] Permission error: \(error)")
            connectionStateSubject.send(.disconnected)
        } catch {
            print("[MetaSDK] Unexpected error: \(error)")
            connectionStateSubject.send(.disconnected)
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
        print("[MetaSDK] handleURL called: \(url)")
        guard let wearables = wearables else { return false }
        
        do {
            let handled = try await wearables.handleUrl(url)
            print("[MetaSDK] URL handled: \(handled)")
            
            if handled {
                // After successful URL handling, poll for devices
                print("[MetaSDK] URL callback successful! Checking for devices...")
                
                connectionStateSubject.send(.connecting)
                
                // Poll for devices - they may take a moment to appear
                for attempt in 1...10 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    
                    let deviceCount = wearables.devices.count
                    print("[MetaSDK] Poll \(attempt): RegState=\(wearables.registrationState), Devices=\(deviceCount)")
                    
                    if deviceCount > 0 {
                        print("[MetaSDK] Devices found after URL callback!")
                        checkForDevices()
                        
                        if connectionState == .connected {
                            return true
                        }
                    }
                }
                
                // If still no devices after polling
                if wearables.devices.count == 0 {
                    print("[MetaSDK] No devices found after URL callback")
                    print("[MetaSDK] Make sure glasses are on and connected in Meta AI app")
                    connectionStateSubject.send(.error(.deviceNotFound))
                }
            }
            
            return handled
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
        
        // Send raw pixel buffer for backward compatibility
        videoFrameSubject.send(pixelBuffer)
        
        // Extract timing information and send timestamped frame
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(frame.sampleBuffer)
        let hostTime = mach_absolute_time()
        
        let timestampedFrame = TimestampedVideoFrame(
            pixelBuffer: pixelBuffer,
            hostTime: hostTime,
            presentationTime: presentationTime
        )
        timestampedVideoFrameSubject.send(timestampedFrame)
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
