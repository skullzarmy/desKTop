import Foundation

extension Notification.Name {
    public static let didChangeDesktopIconsVisibility = Notification.Name("desKTop.didChangeDesktopIconsVisibility")
}

/// Manages Finder's CreateDesktop preference for distraction-free Clean Frame mode
public enum DesktopIconsManager {
    public static var isDesktopIconsHidden: Bool {
        if let value = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString) as? Bool {
            return !value
        }
        return false
    }

    public static func setDesktopIconsHidden(_ hidden: Bool) {
        Task.detached(priority: .userInitiated) {
            let defaultsProc = Process()
            defaultsProc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            if hidden {
                defaultsProc.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]
            } else {
                defaultsProc.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", "true"]
            }
            try? defaultsProc.run()
            defaultsProc.waitUntilExit()

            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProc.arguments = ["Finder"]
            try? killProc.run()
            killProc.waitUntilExit()

            await MainActor.run {
                NotificationCenter.default.post(name: .didChangeDesktopIconsVisibility, object: hidden)
            }
        }
    }

    public static func toggleDesktopIcons() -> Bool {
        let nextHidden = !isDesktopIconsHidden
        setDesktopIconsHidden(nextHidden)
        return nextHidden
    }
}
