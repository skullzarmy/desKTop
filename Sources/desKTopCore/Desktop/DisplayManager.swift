import AppKit
import Foundation

/// Unique persistent representation of a physical connected display
public struct DisplayDevice: Identifiable, Hashable, Sendable {
    public var id: String { uuid }
    public let uuid: String
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isMain: Bool
    public let width: Int
    public let height: Int

    public init(
        uuid: String,
        displayID: CGDirectDisplayID,
        name: String,
        isMain: Bool,
        width: Int,
        height: Int
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.width = width
        self.height = height
    }
}

/// Actor managing active monitors keyed by persistent hardware UUID
public actor DisplayManager {
    public static func persistentUUID(for displayID: CGDirectDisplayID) -> String {
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let str = CFUUIDCreateString(nil, cfUUID.takeRetainedValue()) as String
            return str
        }
        return "display_\(displayID)"
    }

    /// Enumerates currently active displays, extracting persistent hardware UUIDs
    @MainActor
    public static func activeDisplays() -> [DisplayDevice] {
        return NSScreen.screens.compactMap { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            let uuid = persistentUUID(for: displayID)
            let isMain = screen == NSScreen.main
            let frame = screen.frame
            let name = screen.localizedName

            return DisplayDevice(
                uuid: uuid,
                displayID: displayID,
                name: name,
                isMain: isMain,
                width: Int(frame.width),
                height: Int(frame.height)
            )
        }
    }

    /// Finds the NSScreen corresponding to a persistent display UUID
    @MainActor
    public static func findScreen(for displayUUID: String) -> NSScreen? {
        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            return persistentUUID(for: displayID) == displayUUID
        }
    }
}
