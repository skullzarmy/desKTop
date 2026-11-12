import AppKit
import Combine
import Foundation
import IOKit.ps

/// Monitors system power state, battery status, Low Power Mode, and thermal state
public final class PowerGuardian: ObservableObject, @unchecked Sendable {
    public static let shared = PowerGuardian()
    public static let powerStateDidChangeNotification = Notification.Name("desKTopPowerStateDidChange")

    @Published public private(set) var isOnBattery: Bool
    @Published public private(set) var isLowPowerModeEnabled: Bool
    @Published public private(set) var isThermalThrottling: Bool

    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var notificationTokens: [NSObjectProtocol] = []

    public init() {
        self.isOnBattery = Self.readIsOnBattery()
        self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        self.isThermalThrottling = Self.readIsThermalThrottling()
        startMonitoring()
    }

    deinit {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Reads current system power source from IOKit
    public static func readIsOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return false
        }

        if let providingType = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            return providingType == kIOPMBatteryPowerKey
        }

        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String,
               state == (kIOPSBatteryPowerValue as String) {
                return true
            }
        }
        return false
    }

    private static func readIsThermalThrottling() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    private func startMonitoring() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let guardian = Unmanaged<PowerGuardian>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                guardian.refreshPowerState()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.powerSourceRunLoopSource = runLoopSource
        }

        let lowPowerToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPowerState()
        }
        notificationTokens.append(lowPowerToken)

        let thermalToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPowerState()
        }
        notificationTokens.append(thermalToken)
    }

    /// Refreshes power state on the main thread and notifies observers only when a state actually changes
    public func refreshPowerState() {
        let newBattery = Self.readIsOnBattery()
        let newLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let newThermal = Self.readIsThermalThrottling()

        let changed = (newBattery != isOnBattery)
            || (newLowPower != isLowPowerModeEnabled)
            || (newThermal != isThermalThrottling)

        guard changed else { return }

        isOnBattery = newBattery
        isLowPowerModeEnabled = newLowPower
        isThermalThrottling = newThermal
        NotificationCenter.default.post(name: Self.powerStateDidChangeNotification, object: self)
    }

    /// Determines whether dynamic animations should be frozen into static mode
    public static func evaluateShouldFreeze(
        disableAnimations: Bool,
        pauseOnBattery: Bool,
        isOnBattery: Bool,
        isLowPowerModeEnabled: Bool
    ) -> Bool {
        return disableAnimations || (pauseOnBattery && isOnBattery) || isLowPowerModeEnabled
    }

    /// Whether live generative / video canvas should be suspended to conserve energy
    public var shouldSuspendLiveCanvas: Bool {
        return isOnBattery || isLowPowerModeEnabled || isThermalThrottling
    }
}
