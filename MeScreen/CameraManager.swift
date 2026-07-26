@preconcurrency import AVFoundation
import AppKit
import Combine
import SwiftUI

enum WindowSize: CGFloat, CaseIterable {
    case small = 100
    case medium = 150
    case large = 200

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

nonisolated enum CameraAuthorization: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

nonisolated protocol CameraAuthorizationProviding: Sendable {
    func authorizationStatus() -> CameraAuthorization
    func requestAccess() async -> Bool
}

nonisolated struct SystemCameraAuthorizationProvider: CameraAuthorizationProviding {
    func authorizationStatus() -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

enum CameraState: Equatable {
    case idle
    case checkingPermission
    case requestingPermission
    case permissionDenied
    case restricted
    case starting
    case running
    case unavailable
    case failed(String)

    var overlayTitle: String {
        switch self {
        case .idle, .checkingPermission: "Checking Camera"
        case .requestingPermission: "Allow Camera"
        case .permissionDenied: "Camera Denied"
        case .restricted: "Camera Restricted"
        case .starting: "Starting Camera"
        case .running: "Camera Ready"
        case .unavailable: "No Camera"
        case .failed: "Camera Error"
        }
    }

    var menuMessage: String? {
        switch self {
        case .idle: nil
        case .checkingPermission: "Checking camera permission…"
        case .requestingPermission: "Waiting for camera permission…"
        case .permissionDenied: "Camera access is denied."
        case .restricted: "Camera access is restricted by system policy."
        case .starting: "Starting camera…"
        case .running: nil
        case .unavailable: "No camera is currently available."
        case .failed(let message): message
        }
    }

    var symbolName: String {
        switch self {
        case .idle, .checkingPermission, .requestingPermission, .starting:
            "video"
        case .permissionDenied, .restricted:
            "video.slash"
        case .running:
            "video.fill"
        case .unavailable:
            "video.slash"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

enum CameraDeviceChange: Equatable {
    case connected
    case disconnected(cameraID: String?)
}

@MainActor
protocol CameraTransitionScheduling {
    func schedule(_ action: @escaping @MainActor @Sendable () -> Void)
}

@MainActor
struct MainQueueCameraTransitionScheduler: CameraTransitionScheduling {
    func schedule(_ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.05,
            execute: action
        )
    }
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var availableCameras: [CameraDescriptor] = []
    @Published private(set) var currentCamera: CameraDescriptor?
    @Published private(set) var cameraState: CameraState = .idle
    @Published private(set) var windowSize: WindowSize = .medium
    @Published private(set) var isTransitioning = false

    private let authorizationProvider: CameraAuthorizationProviding
    private let sessionController: CaptureSessionControlling
    private let notificationCenter: NotificationCenter
    private let transitionScheduler: CameraTransitionScheduling
    private var activeSessionIdentifier: ObjectIdentifier?
    private var activeRequestID = UUID()
    private var cameraOperation: Task<Void, Never>?
    private var discoveryOperation: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        startCamera: Bool = true,
        authorizationProvider: CameraAuthorizationProviding = SystemCameraAuthorizationProvider(),
        sessionController: CaptureSessionControlling = AVCaptureSessionController(),
        notificationCenter: NotificationCenter = .default,
        transitionScheduler: CameraTransitionScheduling? = nil
    ) {
        self.authorizationProvider = authorizationProvider
        self.sessionController = sessionController
        self.notificationCenter = notificationCenter
        self.transitionScheduler = transitionScheduler
            ?? MainQueueCameraTransitionScheduler()
        super.init()

        observeCameraEvents()
        if startCamera {
            schedulePermissionCheck()
        }
    }

    func checkPermissions() async {
        cameraState = .checkingPermission

        switch authorizationProvider.authorizationStatus() {
        case .authorized:
            await startCamera(preferredCameraID: currentCamera?.id)
        case .notDetermined:
            cameraState = .requestingPermission
            let granted = await authorizationProvider.requestAccess()
            guard !Task.isCancelled else { return }

            if granted {
                await startCamera(preferredCameraID: currentCamera?.id)
            } else {
                await stopSessionAndClear(state: .permissionDenied)
            }
        case .denied:
            await stopSessionAndClear(state: .permissionDenied)
        case .restricted:
            await stopSessionAndClear(state: .restricted)
        }
    }

    func switchCamera(to camera: CameraDescriptor) {
        scheduleCameraStart(preferredCameraID: camera.id)
    }

    func stopCamera() {
        cameraOperation?.cancel()
        discoveryOperation?.cancel()
        activeRequestID = UUID()

        let sessionIdentifier = activeSessionIdentifier
        clearSessionUI(state: .idle)

        Task { [sessionController] in
            await sessionController.stop(sessionIdentifier: sessionIdentifier)
        }
    }

    func refreshCameras() {
        schedulePermissionCheck()
    }

    func openCameraSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func changeSize(to newSize: WindowSize) {
        guard newSize != windowSize, !isTransitioning else { return }

        isTransitioning = true
        transitionScheduler.schedule {
            self.windowSize = newSize
        }
    }

    func finishTransition() {
        transitionScheduler.schedule {
            withAnimation(.easeOut(duration: 0.25)) {
                self.isTransitioning = false
            }
        }
    }

    private func schedulePermissionCheck() {
        cameraOperation?.cancel()
        discoveryOperation?.cancel()
        cameraOperation = Task { [weak self] in
            await self?.checkPermissions()
        }
    }

    private func scheduleCameraStart(preferredCameraID: String?) {
        cameraOperation?.cancel()
        discoveryOperation?.cancel()
        cameraOperation = Task { [weak self] in
            await self?.startCamera(preferredCameraID: preferredCameraID)
        }
    }

    private func startCamera(preferredCameraID: String?) async {
        let requestID = UUID()
        activeRequestID = requestID
        cameraState = .starting
        previewLayer = nil
        currentCamera = nil
        activeSessionIdentifier = nil

        let outcome = await sessionController.start(
            preferredCameraID: preferredCameraID
        )
        guard !Task.isCancelled, requestID == activeRequestID else { return }

        switch outcome {
        case .running(let snapshot):
            availableCameras = snapshot.cameras
            currentCamera = snapshot.selectedCamera
            let previewLayer = AVCaptureVideoPreviewLayer(
                session: snapshot.session
            )
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer
            activeSessionIdentifier = snapshot.sessionIdentifier
            cameraState = .running
        case .failed(let failure, let cameras):
            availableCameras = cameras
            currentCamera = nil
            previewLayer = nil
            activeSessionIdentifier = nil
            cameraState = failure == .noCameras
                ? .unavailable
                : .failed(failure.message)
        }
    }

    private func clearSessionUI(state: CameraState) {
        previewLayer = nil
        currentCamera = nil
        activeSessionIdentifier = nil
        availableCameras = []
        cameraState = state
    }

    private func stopSessionAndClear(state: CameraState) async {
        activeRequestID = UUID()
        clearSessionUI(state: state)
        await sessionController.stop(sessionIdentifier: nil)
    }

    private func observeCameraEvents() {
        notificationCenter.publisher(for: AVCaptureDevice.wasConnectedNotification)
            .merge(with: notificationCenter.publisher(
                for: AVCaptureDevice.wasDisconnectedNotification
            ))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let change: CameraDeviceChange
                if notification.name == AVCaptureDevice.wasDisconnectedNotification {
                    let cameraID = (notification.object as? AVCaptureDevice)?.uniqueID
                    change = .disconnected(cameraID: cameraID)
                } else {
                    change = .connected
                }
                self?.handleDeviceChange(change)
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: AVCaptureSession.runtimeErrorNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let session = notification.object as? AVCaptureSession else {
                    return
                }
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                self?.handleRuntimeError(
                    sessionIdentifier: ObjectIdentifier(session),
                    message: error?.localizedDescription
                )
            }
            .store(in: &cancellables)
    }

    func handleDeviceChange(_ change: CameraDeviceChange) {
        guard authorizationProvider.authorizationStatus() == .authorized else {
            return
        }

        let currentCameraWasDisconnected: Bool
        if case .disconnected(let cameraID) = change {
            currentCameraWasDisconnected = cameraID == nil || cameraID == currentCamera?.id
        } else {
            currentCameraWasDisconnected = false
        }

        if currentCamera == nil || currentCameraWasDisconnected {
            scheduleCameraStart(preferredCameraID: nil)
        } else {
            refreshCameraList()
        }
    }

    private func refreshCameraList() {
        discoveryOperation?.cancel()
        discoveryOperation = Task { [weak self] in
            guard let self else { return }
            let cameras = await sessionController.discoverCameras()
            guard !Task.isCancelled else { return }

            if let currentCamera,
               !cameras.contains(where: { $0.id == currentCamera.id }) {
                scheduleCameraStart(preferredCameraID: nil)
                return
            }
            availableCameras = cameras
        }
    }

    func handleRuntimeError(
        sessionIdentifier: ObjectIdentifier,
        message: String?
    ) {
        guard sessionIdentifier == activeSessionIdentifier else {
            return
        }

        cameraOperation?.cancel()
        discoveryOperation?.cancel()
        activeRequestID = UUID()

        let failedSessionIdentifier = activeSessionIdentifier
        previewLayer = nil
        currentCamera = nil
        activeSessionIdentifier = nil
        cameraState = .failed(
            message ?? "The camera session stopped unexpectedly."
        )

        Task { [sessionController] in
            await sessionController.stop(
                sessionIdentifier: failedSessionIdentifier
            )
        }
    }
}
