import AppKit
import Foundation
import IOKit.ps

/// Monitors system power state, battery status, Low Power Mode, and thermal state
public final class PowerGuardian: Sendable {
    public static let shared = PowerGuardian()

    public init() {}

    /// Checks if device is currently running on battery power
    public var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
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

    /// Checks if macOS Low Power Mode is currently active
    public var isLowPowerModeEnabled: Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Checks if the thermal state requires throttling/pausing
    public var isThermalThrottling: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    /// Whether live generative / video canvas should be suspended to conserve energy
    public var shouldSuspendLiveCanvas: Bool {
        return isOnBattery || isLowPowerModeEnabled || isThermalThrottling
    }
}
