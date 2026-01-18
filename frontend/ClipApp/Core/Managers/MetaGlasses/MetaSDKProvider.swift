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
    private var isStartingStream = false // Guard against concurrent starts
    private var linkStateToken: (any AnyListenerToken)?
    private var registrationStateToken: (any AnyListenerToken)?
    private var videoFrameToken: (any AnyListenerToken)?
    private var streamStateToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?
    
    private var cancellables = Set<AnyCancellable>()
    
    // Track when streaming started to detect immediate stop (permission denial)
    private var streamingStartTime: Date?
    
    // MARK: - Registration/Permission Guardrails
    
    /// Prevents infinite loops of repeatedly launching Meta AI for registration/permission.
    private var lastMetaAILaunchAt: Date?
    
    /// Track whether we've ever observed at least one device from the SDK in this run.
    private var hasSeenAnyDevice: Bool = false
    
    // Device availability monitoring task (per SDK docs: monitor devicesMetadata for availability)
    private var deviceAvailabilityTask: Task<Void, Never>?
    
    // Serial queue for stream operations to prevent concurrent start attempts
    private let streamOperationQueue = DispatchQueue(label: "com.clip.metasdk.stream", qos: .userInitiated)
    
    // Actor-like lock for stream start
    private var streamStartTask: Task<Void, Error>?
    
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
        // Cancel device availability monitoring
        deviceAvailabilityTask?.cancel()
        
        // Cancel tokens
        Task { [linkStateToken, registrationStateToken, videoFrameToken, streamStateToken, errorToken] in
            await linkStateToken?.cancel()
            await registrationStateToken?.cancel()
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
            await errorToken?.cancel()
        }
    }
    
    // MARK: - SDK Configuration
    
    private func configureSDK() {
        // Wearables.configure() is called once in ClipApp.init() per SDK documentation
        // Here we just get the shared instance
        wearables = Wearables.shared
        // #region agent log H2,H3
        os_log("[DEBUG-H2H3] SDK configured. RegState=%{public}@ DeviceCount=%{public}d", log: debugLog, type: .error, String(describing: wearables?.registrationState), wearables?.devices.count ?? 0)
        // #endregion
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
        
        // Only set up device observation if this is a new device
        let isNewDevice = currentDevice?.identifier != device.identifier
        
        // #region agent log H5
        os_log("[DEBUG-H5] checkForDevices: found device '%{public}@' linkState=%{public}@ isNew=%{public}@", log: debugLog, type: .error, device.name, String(describing: device.linkState), isNewDevice ? "yes" : "no")
        // #endregion
        
        currentDevice = device
        deviceName = device.name
        
        // Only register listener for new devices (avoid duplicate listeners)
        if isNewDevice {
            // Cancel previous listener if any
            Task {
                await linkStateToken?.cancel()
            }
            linkStateToken = nil
            previousLinkState = nil // Reset state tracking for new device
            
            observeDeviceLinkState(device)
        }
        
        // Check current link state (handleLinkStateChange has its own dedup logic)
        handleLinkStateChange(device.linkState)
    }
    
    private func observeDeviceLinkState(_ device: Device) {
        linkStateToken = device.addLinkStateListener { [weak self] linkState in
            Task { @MainActor in
                self?.handleLinkStateChange(linkState)
            }
        }
        
        // Start device availability monitoring (per SDK docs)
        startDeviceAvailabilityMonitoring(device)
    }
    
    /// Monitor device availability per SDK documentation:
    /// "Use device metadata to detect availability. Hinge position is not exposed, but it influences connectivity."
    /// "Closing the hinges disconnects Bluetooth, stops active streams, and forces SessionState to STOPPED."
    ///
    /// Note: We only log here - actual cleanup is handled by linkState listener to avoid duplicate cleanup.
    private func startDeviceAvailabilityMonitoring(_ device: Device) {
        deviceAvailabilityTask?.cancel()
        deviceAvailabilityTask = Task { [weak self] in
            // Poll device availability periodically (iOS SDK may not expose async stream like Android)
            // This checks linkState which reflects availability (disconnected when hinges closed)
            var lastKnownState: LinkState = device.linkState
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Check every 10 seconds (reduced frequency)
                
                guard let self = self else { return }
                guard !Task.isCancelled else { return }
                
                // Only log state changes, don't trigger cleanup (linkState listener handles that)
                let currentState = device.linkState
                if currentState != lastKnownState {
                    print("[MetaSDK] 📊 Availability monitor: linkState changed from \(lastKnownState) to \(currentState)")
                    lastKnownState = currentState
                }
            }
        }
    }
    
    /// Track previous link state to avoid redundant handling
    private var previousLinkState: LinkState?
    
    private func handleLinkStateChange(_ linkState: LinkState) {
        // Skip if state hasn't actually changed, unless our public connectionState is out of sync.
        if linkState == previousLinkState {
            if linkState == .connected && connectionState != .connected {
                print("[MetaSDK] 🔁 LinkState is connected but connectionState isn't - resyncing")
            } else if linkState == .connecting && connectionState != .connecting {
                print("[MetaSDK] 🔁 LinkState is connecting but connectionState isn't - resyncing")
            } else if linkState == .disconnected && connectionState != .disconnected {
                print("[MetaSDK] 🔁 LinkState is disconnected but connectionState isn't - resyncing")
            } else {
                return
            }
        }
        
        let wasConnected = previousLinkState == .connected
        previousLinkState = linkState
        
        switch linkState {
        case .connected:
            connectionStateSubject.send(.connected)
            // Meta DAT SDK doesn't expose battery level
            // Use -1 to indicate "unknown" so UI can show a Preview pill instead
            batteryLevel = -1
            print("[MetaSDK] ✅ Device connected!")
            
        case .connecting:
            connectionStateSubject.send(.connecting)
            print("[MetaSDK] 🔄 Device connecting...")
            
        case .disconnected:
            connectionStateSubject.send(.disconnected)
            batteryLevel = 0
            
            // Only cleanup if we were previously connected (avoid spam on initial disconnected state)
            if wasConnected {
                print("[MetaSDK] 📴 Device disconnected (was connected) - cleaning up resources")
                cleanupStreamResources()
            } else {
                print("[MetaSDK] 📴 Device disconnected (initial state or already disconnected)")
            }
            
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
        // Allow link state to re-emit even if it matches a prior value.
        previousLinkState = nil
        
        // Check registration state first
        print("[MetaSDK] Registration state: \(wearables.registrationState)")
        print("[MetaSDK] Devices count: \(wearables.devices.count)")
        
        // If we have devices, try to connect to them
        if wearables.devices.count > 0 {
            hasSeenAnyDevice = true
            checkForDevices()
            if connectionState == .connected {
                print("[MetaSDK] Connected to existing device!")
                return
            }
            // If the SDK reports a connected device, trust linkState and avoid Meta AI loop.
            if currentDevice?.linkState == .connected {
                print("[MetaSDK] Device linkState is connected - forcing connection state")
                handleLinkStateChange(.connected)
                return
            }
            print("[MetaSDK] Devices present but not fully connected yet - waiting for linkState")
            return
        }
        
        // If we're already registered, do NOT keep launching Meta AI in a loop.
        // Devices can temporarily appear/disappear while the SDK stabilizes; give it time.
        if wearables.registrationState == .registered {
            print("[MetaSDK] Already registered - waiting briefly for devices to stabilize (avoiding Meta AI loop)...")
            for attempt in 1...10 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                let deviceCount = wearables.devices.count
                print("[MetaSDK] Registered wait \(attempt): devices=\(deviceCount)")
                if deviceCount > 0 {
                    hasSeenAnyDevice = true
                    checkForDevices()
                    if connectionState == .connected {
                        print("[MetaSDK] Connected after registered wait")
                        return
                    }
                    // Don't fail here; allow linkState listener / poller to settle.
                    return
                }
            }
        }
        
        // No devices found - may need to trigger the Meta AI app authorization flow
        // startRegistration() opens Meta AI app for the user to grant access
        print("[MetaSDK] No devices found. Registration state: \(wearables.registrationState)")
        print("[MetaSDK] Opening Meta AI app for authorization...")
        
        // Rate-limit Meta AI launches to avoid infinite loops / flapping.
        if let last = lastMetaAILaunchAt, Date().timeIntervalSince(last) < 30 {
            print("[MetaSDK] Skipping Meta AI launch (rate-limited). Last launch was \(Date().timeIntervalSince(last))s ago.")
        } else {
            lastMetaAILaunchAt = Date()
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
        }
        
        // Fallback: try requestPermission
        do {
            // If camera permission is already granted, don't bounce through Meta AI again.
            if (try? await wearables.checkPermissionStatus(.camera)) == .granted {
                print("[MetaSDK] Camera permission already granted - checking for devices without re-requesting")
                checkForDevices()
                return
            }
            
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
                
                // If we saw devices at any point, don't overwrite state with deviceNotFound.
                // The linkState listener / poller may still be settling.
                if wearables.devices.count > 0 {
                    hasSeenAnyDevice = true
                    print("[MetaSDK] Permission granted and devices are present - skipping deviceNotFound error")
                    checkForDevices()
                    return
                }
                
                if hasSeenAnyDevice {
                    print("[MetaSDK] Permission granted but devices temporarily unavailable - leaving state as connecting")
                    return
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
    
    /// Re-request camera permission from the SDK
    /// Returns a status message for the UI
    func reauthorize() async -> String {
        guard let wearables = wearables else {
            return "SDK not available"
        }
        
        print("[MetaSDK] Re-requesting camera permission...")
        
        // Check current status
        do {
            let currentStatus = try await wearables.checkPermissionStatus(.camera)
            print("[MetaSDK] Current camera permission status: \(currentStatus)")
            
            if currentStatus == .granted {
                return "Permission already granted. Try Preview."
            } else if currentStatus == .denied {
                return "Permission denied. Try disconnecting glasses in Meta AI app and reconnecting."
            }
        } catch {
            print("[MetaSDK] checkPermissionStatus error: \(error)")
        }
        
        // Try to request permission
        do {
            let result = try await wearables.requestPermission(.camera)
            print("[MetaSDK] Permission request result: \(result)")
            
            if result == .granted {
                return "Permission granted! Try Preview now."
            } else if result == .denied {
                return "Permission denied by Meta AI app."
            } else {
                return "Permission status: \(result). Try Preview."
            }
        } catch {
            let errorStr = String(describing: error)
            print("[MetaSDK] requestPermission error: \(errorStr)")
            
            if errorStr.contains("error 3") {
                return "Permission state locked. Try Preview - it may work."
            }
            return "Error: \(error.localizedDescription)"
        }
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
    
    /// Maps StreamSessionError to a meaningful GlassesError for UI display
    /// Note: nonisolated because it's a pure function with no state access
    nonisolated private func mapStreamError(_ error: StreamSessionError) -> GlassesError {
        switch error {
        case .deviceNotFound:
            return .deviceNotFound
        case .deviceNotConnected:
            return .notConnected
        case .permissionDenied:
            // More specific message about how to fix
            return .streamFailed("Camera permission denied. Tap glasses temple when prompted, or check Meta AI app permissions.")
        case .timeout:
            return .streamFailed("Timeout - tap glasses temple to wake them up")
        case .videoStreamingError:
            return .streamFailed("Video streaming error - ensure glasses are awake and try again")
        case .audioStreamingError:
            return .streamFailed("Audio streaming error")
        case .internalError:
            return .streamFailed("Internal SDK error - try disconnecting and reconnecting")
        @unknown default:
            return .streamFailed("Unknown streaming error - try again")
        }
    }
    
    func startVideoStream() async throws {
        print("[MetaSDK] startVideoStream called. ConnectionState: \(connectionState), isVideoStreaming: \(isVideoStreaming), isStartingStream: \(isStartingStream)")
        
        // If already streaming, return immediately
        guard !isVideoStreaming else {
            print("[MetaSDK] Already streaming - returning")
            return
        }
        
        // If another start is in progress, wait for it instead of starting another
        if let existingTask = streamStartTask, isStartingStream {
            print("[MetaSDK] Stream start already in progress - waiting for existing task...")
            do {
                try await existingTask.value
                print("[MetaSDK] Existing task completed - checking if now streaming")
                if isVideoStreaming {
                    return // Existing task succeeded
                }
                // Existing task failed, we'll start a new one below
            } catch {
                print("[MetaSDK] Existing task failed: \(error.localizedDescription)")
                // Existing task failed, we'll try starting a new one
            }
        }
        
        if connectionState != .connected {
            // If the SDK says the device link is connected, resync our state and proceed.
            if currentDevice?.linkState == .connected {
                print("[MetaSDK] ConnectionState out of sync - linkState is connected, resyncing")
                connectionStateSubject.send(.connected)
            } else {
                print("[MetaSDK] Cannot start stream - not connected")
                throw GlassesError.notConnected
            }
        }
        
        // Double-check streaming state after waiting
        guard !isVideoStreaming else {
            print("[MetaSDK] Already streaming after wait - returning")
            return
        }
        
        // Create and store the task so concurrent callers can wait on it
        let task = Task { @MainActor in
            try await performStreamStart()
        }
        streamStartTask = task
        
        // Await the task
        try await task.value
    }
    
    /// Internal implementation of stream start - should only be called from startVideoStream
    private func performStreamStart() async throws {
        // Final guard against concurrent execution
        guard !isStartingStream else {
            print("[MetaSDK] performStreamStart: Another start in progress, aborting")
            throw GlassesError.streamFailed("Stream start already in progress")
        }
        
        isStartingStream = true
        defer { 
            isStartingStream = false 
            streamStartTask = nil
        }
        
        guard let wearables = wearables else {
            print("[MetaSDK] No wearables instance")
            throw GlassesError.sdkNotAvailable
        }
        
        guard let device = currentDevice else {
            print("[MetaSDK] No current device")
            throw GlassesError.notConnected
        }
        
        // Verify device is still connected
        guard device.linkState == .connected else {
            print("[MetaSDK] Device linkState is not connected: \(device.linkState)")
            throw GlassesError.notConnected
        }
        
        print("[MetaSDK] Starting video stream from device: \(device.name), linkState: \(device.linkState)")
        
        // Check and request camera permission with proper error handling
        var permissionGranted = false
        
        // First check current status
        do {
            let currentStatus = try await wearables.checkPermissionStatus(.camera)
            print("[MetaSDK] Current camera permission status: \(currentStatus)")
            
            if currentStatus == .granted {
                permissionGranted = true
                print("[MetaSDK] Camera permission already granted")
            } else if currentStatus == .denied {
                print("[MetaSDK] Camera permission was previously denied - requesting again...")
                // Don't throw immediately - try to request permission first
                // The user might have denied it before but will grant it now
            }
        } catch let error as GlassesError {
            throw error
        } catch {
            print("[MetaSDK] Could not check permission status: \(error)")
            // Continue to request permission
        }
        
        // Request permission if not already granted
        if !permissionGranted {
            do {
                let status = try await wearables.requestPermission(.camera)
                print("[MetaSDK] Camera permission request result: \(status)")
                
                switch status {
                case .granted:
                    permissionGranted = true
                    print("[MetaSDK] Camera permission GRANTED")
                case .denied:
                    print("[MetaSDK] Camera permission DENIED by user")
                    throw GlassesError.permissionDenied
                default:
                    print("[MetaSDK] Camera permission status: \(status)")
                    // Try to proceed anyway if device is connected
                }
            } catch let error as GlassesError {
                throw error
            } catch {
                // Handle PermissionError from SDK
                let errorString = String(describing: error)
                print("[MetaSDK] Permission request error: \(errorString)")
                
                // "error 3" from PermissionError typically means one of:
                // - Permission already granted (proceed)
                // - SDK state issue (try anyway)
                // - Actual permission problem (will fail at stream start)
                if errorString.contains("error 3") {
                    print("[MetaSDK] PermissionError 3 - attempting stream (might already be authorized)")
                } else if errorString.contains("error 2") {
                    // error 2 typically means permission denied
                    print("[MetaSDK] PermissionError 2 - permission denied")
                    throw GlassesError.permissionDenied
                } else {
                    // For other errors, try to proceed if device is connected
                    print("[MetaSDK] Unknown permission error - attempting stream anyway")
                }
            }
        }
        
        // Clean up any existing session before creating a new one
        if streamSession != nil || videoFrameToken != nil {
            print("[MetaSDK] Cleaning up existing stream session...")
            isVideoStreaming = false
            await streamSession?.stop()
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
            await errorToken?.cancel()
            videoFrameToken = nil
            streamStateToken = nil
            errorToken = nil
            streamSession = nil
            previousStreamState = nil // Reset state tracking
            // Give SDK more time to fully clean up before starting new session
            print("[MetaSDK] Waiting 2 seconds for SDK to fully reset...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            print("[MetaSDK] Cleanup complete")
        }
        
        // Use SpecificDeviceSelector with the device we already connected to
        let deviceSelector = SpecificDeviceSelector(device: device.identifier)
        
        // Create stream session with config
        // Using .high resolution for best quality
        // Options: .low (640x480), .medium (1280x720), .high (1920x1080)
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 15
        )
        
        print("[MetaSDK] Creating stream session with device: \(device.name)...")
        
        // Give the glasses a moment to be ready (camera might need to wake up)
        // This helps prevent internalError when camera isn't ready yet
        // Increased to 3 seconds based on SDK behavior - glasses camera often needs time to wake
        print("[MetaSDK] Waiting 3 seconds for glasses camera to be ready...")
        print("[MetaSDK] 💡 TIP: Tap the glasses temple NOW to wake the camera")
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
        self.streamSession = session
        
        // Listen for video frames (this continues working after startup)
        videoFrameToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                self?.handleVideoFrame(frame)
            }
        }
        
        // Use CheckedContinuation to properly wait for streaming state or error
        print("[MetaSDK] Starting session and waiting for stream state...")
        
        do {
            try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
                // Track if we've already resumed to prevent multiple resumes
                var didResume = false
                let resumeLock = NSLock()
                
                func safeResume(with result: Result<Void, Error>) {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                // Listen for state changes - resume on streaming
                self?.streamStateToken = session.statePublisher.listen { [weak self] state in
                    print("[MetaSDK] Stream state during startup: \(state)")
                    switch state {
                    case .streaming:
                        print("[MetaSDK] Stream reached .streaming state!")
                        safeResume(with: .success(()))
                    case .stopped:
                        // If we immediately hit stopped without streaming, something went wrong
                        print("[MetaSDK] Stream stopped before reaching streaming state")
                        // Check flags on MainActor
                        Task { @MainActor in
                            guard let self = self else { return }
                            if self.isVideoStreaming == false && self.isStartingStream == true {
                                // Reset flag before resuming so retry can happen
                                self.isStartingStream = false
                                safeResume(with: .failure(GlassesError.streamFailed("Stream stopped unexpectedly - try tapping glasses temple to wake them")))
                            }
                        }
                    default:
                        break
                    }
                }
                
                // Listen for errors - resume with error
                self?.errorToken = session.errorPublisher.listen { [weak self] error in
                    print("[MetaSDK] Stream error during startup: \(error)")
                    let mappedError = self?.mapStreamError(error) ?? GlassesError.streamFailed("Unknown error")
                    
                    // Add more context to the error message
                    switch error {
                    case .permissionDenied:
                        print("[MetaSDK] ⚠️ Camera permission denied - user must grant permission via glasses tap or Meta AI app")
                    case .videoStreamingError:
                        print("[MetaSDK] ⚠️ Video streaming error - glasses may need to be woken up (tap temple)")
                    case .timeout:
                        print("[MetaSDK] ⚠️ Timeout - glasses may be asleep or out of range")
                    case .internalError:
                        print("[MetaSDK] ⚠️ Internal SDK error - this often means glasses need to be woken up")
                        print("[MetaSDK] ⚠️ Try: 1) Tap glasses temple 2) Wait 2 seconds 3) Retry")
                        // Reset flags immediately so retry can happen
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.isVideoStreaming = false
                            self.isStartingStream = false // CRITICAL: Reset flag so retry can happen
                            // Clean up session
                            await self.streamSession?.stop()
                            await self.videoFrameToken?.cancel()
                            await self.streamStateToken?.cancel()
                            await self.errorToken?.cancel()
                            self.streamSession = nil
                            self.videoFrameToken = nil
                            self.streamStateToken = nil
                            self.errorToken = nil
                            print("[MetaSDK] ✅ Cleanup complete, ready for retry")
                        }
                    default:
                        break
                    }
                    
                    safeResume(with: .failure(mappedError))
                }
                
                // Start the session
                Task {
                    print("[MetaSDK] Calling session.start()...")
                    await session.start()
                    print("[MetaSDK] session.start() completed, waiting for state change...")
                    
                    // Wait up to 15 seconds for streaming to start (increased from 10)
                    // The glasses may need time to wake up
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    
                    // If we haven't resumed yet, it's a timeout
                    safeResume(with: .failure(GlassesError.streamFailed("Stream startup timeout - tap glasses temple to wake them, then try again")))
                }
            }
            
            // If we get here, streaming started successfully
            isVideoStreaming = true
            print("[MetaSDK] ✅ Video stream started successfully!")
            
            // Set up ongoing state change handler (for later state changes like pause/stop)
            streamStateToken = session.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    print("[MetaSDK] Stream state changed: \(state)")
                    self?.handleStreamStateChange(state)
                }
            }
            
        } catch {
            // Clean up on failure
            print("[MetaSDK] ❌ Stream startup failed, cleaning up...")
            isVideoStreaming = false
            isStartingStream = false
            await streamSession?.stop()
            streamSession = nil
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
            await errorToken?.cancel()
            videoFrameToken = nil
            streamStateToken = nil
            errorToken = nil
            
            print("[MetaSDK] Failed to start video stream: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func handleVideoFrame(_ frame: VideoFrame) {
        // Extract pixel buffer from CMSampleBuffer
        // Note: The SDK provides frame.makeUIImage() for convenience, but we intentionally use
        // CVPixelBuffer here because:
        // 1. The timestamped frame publisher needs raw pixel buffers for video recording/export
        // 2. GlassesPreviewView handles UIImage conversion efficiently via GPU-accelerated CIContext
        // 3. This avoids creating unnecessary UIImage objects for frames that won't be displayed
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            return
        }
        
        // Send raw pixel buffer for preview and recording pipeline
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
    
    /// Track previous stream state to avoid redundant handling
    private var previousStreamState: StreamSessionState?
    
    private func handleStreamStateChange(_ state: StreamSessionState) {
        // Skip if state hasn't actually changed
        guard state != previousStreamState else {
            return
        }
        previousStreamState = state
        
        switch state {
        case .streaming:
            streamingStartTime = Date()
            isVideoStreaming = true
            print("[MetaSDK] ▶️ Stream is now streaming")
            
        case .stopped:
            // Detect if stream stopped immediately after starting (indicates permission denial by glasses)
            if let startTime = streamingStartTime {
                let duration = Date().timeIntervalSince(startTime)
                if duration < 2.0 {
                    print("[MetaSDK] WARNING: Stream stopped after only \(String(format: "%.1f", duration))s - camera permission likely denied by glasses")
                }
            }
            
            // Only cleanup if we were actually streaming or have a session
            if isVideoStreaming || streamSession != nil {
                print("[MetaSDK] 🛑 Stream stopped - releasing resources per SDK docs")
                isVideoStreaming = false
                streamingStartTime = nil
                cleanupStreamResources()
            }
            
        case .stopping:
            // Transitional state - don't cleanup yet, wait for stopped
            print("[MetaSDK] ⏹️ Stream stopping...")
            
        case .paused:
            // Per SDK docs: "Your app should not attempt to restart a device session while it is paused."
            // Keep isVideoStreaming = true so startVideoStream() guard prevents restart
            // The device keeps the connection alive and may resume automatically
            print("[MetaSDK] ⏸️ Stream paused - waiting for RUNNING or STOPPED (not restarting per SDK docs)")
            // Do NOT set isVideoStreaming = false here
            
        case .waitingForDevice, .starting:
            // Transitional states - no action needed
            break
            
        @unknown default:
            break
        }
    }
    
    /// Clean up all stream-related resources.
    /// Called on STOPPED state and when device becomes unavailable.
    /// Includes guard to prevent redundant cleanup calls.
    private var isCleaningUp = false
    
    private func cleanupStreamResources() {
        // Guard against redundant cleanup calls (prevents spam from multiple code paths)
        guard !isCleaningUp else {
            return // Already cleaning up
        }
        
        // Only clean up if there's actually something to clean
        guard streamSession != nil || videoFrameToken != nil || streamStateToken != nil || errorToken != nil || isVideoStreaming else {
            return // Nothing to clean up
        }
        
        isCleaningUp = true
        
        // Cancel listener tokens
        Task { [videoFrameToken, streamStateToken, errorToken, streamSession] in
            await videoFrameToken?.cancel()
            await streamStateToken?.cancel()
            await errorToken?.cancel()
            await streamSession?.stop()
        }
        
        // Clear references
        videoFrameToken = nil
        streamStateToken = nil
        errorToken = nil
        streamSession = nil
        
        // Reset state flags
        isVideoStreaming = false
        isStartingStream = false
        streamingStartTime = nil
        
        print("[MetaSDK] ✅ Stream resources cleaned up")
        
        // Reset cleanup flag after a short delay to allow pending operations to complete
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                self.isCleaningUp = false
            }
        }
    }
    
    private func handleStreamError(_ error: StreamSessionError) {
        print("[MetaSDK] ⚠️ Stream session error: \(error)")
        
        // Log detailed error for debugging
        switch error {
        case .deviceNotFound:
            print("[MetaSDK] Error: Device not found - glasses may have disconnected")
        case .deviceNotConnected:
            print("[MetaSDK] Error: Device not connected")
        case .permissionDenied:
            print("[MetaSDK] Error: Permission denied - check Meta AI app developer mode and permissions")
        case .timeout:
            print("[MetaSDK] Error: Stream timeout")
        case .videoStreamingError:
            print("[MetaSDK] Error: Video streaming error")
        case .audioStreamingError:
            print("[MetaSDK] Error: Audio streaming error")
        case .internalError:
            print("[MetaSDK] Error: Internal SDK error")
        @unknown default:
            print("[MetaSDK] Error: Unknown error")
        }
        
        // DON'T change connection state to error - that causes UI flash
        // The device is still connected, only the stream failed
        // Just mark streaming as stopped
        isVideoStreaming = false
        
        // Stop the session cleanly
        Task {
            await streamSession?.stop()
        }
    }
    
    func stopVideoStream() {
        guard isVideoStreaming || streamSession != nil else { return }
        
        print("[MetaSDK] 🛑 stopVideoStream called - cleaning up resources")
        cleanupStreamResources()
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
