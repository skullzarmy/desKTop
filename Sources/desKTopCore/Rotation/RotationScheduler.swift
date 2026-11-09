import AppKit
import Foundation

public enum RotationInterval: Int, CaseIterable, Identifiable, Codable, Sendable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case sixHours = 21600
    case daily = 86400
    case onDisplayWake = 0

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .oneMinute: return "Every 1 Minute"
        case .fiveMinutes: return "Every 5 Minutes"
        case .fifteenMinutes: return "Every 15 Minutes"
        case .thirtyMinutes: return "Every 30 Minutes"
        case .oneHour: return "Every Hour"
        case .sixHours: return "Every 6 Hours"
        case .daily: return "Daily"
        case .onDisplayWake: return "On Display Wake Only"
        }
    }
}

/// Sleep-aware wallpaper rotation scheduler preventing darkwake GPU battery drain
public final class RotationScheduler: @unchecked Sendable {
    public var interval: RotationInterval {
        didSet {
            restartTimer()
        }
    }

    public var isPaused: Bool = false {
        didSet {
            if isPaused {
                stopTimer()
            } else {
                restartTimer()
            }
        }
    }

    private var timer: Timer?
    private let onRotate: @Sendable () -> Void
    private var sleepObservers: [NSObjectProtocol] = []

    public init(interval: RotationInterval = .oneHour, onRotate: @escaping @Sendable () -> Void) {
        self.interval = interval
        self.onRotate = onRotate

        setupSleepWakeObservers()
        restartTimer()
    }

    deinit {
        stopTimer()
        for obs in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // 1. Invalidate and destroy timer on screensDidSleep to prevent darkwake wake-locks
        let sleepObs1 = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopTimer()
        }

        let sleepObs2 = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopTimer()
        }

        // 2. Re-arm timer only on screensDidWake
        let wakeObs = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.interval == .onDisplayWake {
                self.onRotate()
            } else if !self.isPaused {
                self.restartTimer()
            }
        }

        self.sleepObservers = [sleepObs1, sleepObs2, wakeObs]
    }

    public func restartTimer() {
        stopTimer()
        guard !isPaused, interval.rawValue > 0 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isPaused else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(self.interval.rawValue), repeats: true) { [weak self] _ in
                self?.onRotate()
            }
        }
    }

    public func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    public func triggerManualRotation() {
        onRotate()
        if !isPaused {
            restartTimer()
        }
    }
}
