import Foundation
import desKTopCore

public struct RotationAndEnergyTests {
    public static func run() throws {
        // 1. PowerGuardian
        let guardian = PowerGuardian.shared
        _ = guardian.isOnBattery
        _ = guardian.isLowPowerModeEnabled
        _ = guardian.isThermalThrottling
        _ = guardian.shouldSuspendLiveCanvas
        guardian.refreshPowerState()

        try assertFalse(PowerGuardian.evaluateShouldFreeze(disableAnimations: false, pauseOnBattery: false, isOnBattery: true, isLowPowerModeEnabled: false))
        try assertTrue(PowerGuardian.evaluateShouldFreeze(disableAnimations: false, pauseOnBattery: true, isOnBattery: true, isLowPowerModeEnabled: false))
        try assertFalse(PowerGuardian.evaluateShouldFreeze(disableAnimations: false, pauseOnBattery: true, isOnBattery: false, isLowPowerModeEnabled: false))
        try assertTrue(PowerGuardian.evaluateShouldFreeze(disableAnimations: false, pauseOnBattery: false, isOnBattery: false, isLowPowerModeEnabled: true))
        try assertTrue(PowerGuardian.evaluateShouldFreeze(disableAnimations: true, pauseOnBattery: false, isOnBattery: false, isLowPowerModeEnabled: false))

        // 2. Rotation intervals
        try assertEqual(RotationInterval.fiveMinutes.rawValue, 300)
        try assertEqual(RotationInterval.oneHour.rawValue, 3600)
        try assertEqual(RotationInterval.daily.rawValue, 86400)
        try assertEqual(RotationInterval.onDisplayWake.rawValue, 0)
        try assertTrue(!RotationInterval.oneHour.displayName.isEmpty)

        // 3. RotationScheduler
        final class RotationBox: @unchecked Sendable {
            var rotated = false
        }
        let box = RotationBox()
        let scheduler = RotationScheduler(interval: .fiveMinutes) {
            box.rotated = true
        }

        try assertFalse(scheduler.isPaused)
        scheduler.triggerManualRotation()
        try assertTrue(box.rotated, "Manual rotation trigger should execute rotation block")

        scheduler.isPaused = true
        try assertTrue(scheduler.isPaused)
        scheduler.stopTimer()
    }
}
