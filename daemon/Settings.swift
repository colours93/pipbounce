import Foundation

class Settings {
    var enabled = true
    var cooldown: TimeInterval = 0.4
    var margin: CGFloat = 20
    var cornerSize: CGFloat = 100
    var glow = true
    var glowColor = "purple"         // purple, blue, red, green, rainbow
    var hotkeyCode: UInt16 = 2       // "d" key
    var hotkeyFlags: UInt32 = 0x108  // cmd+shift

    private static let legacyFilePath: String = {
        let legacyDir = NSString("~/.pipbounce").expandingTildeInPath
        return (legacyDir as NSString).appendingPathComponent("settings.json")
    }()

    private static let filePath: String = {
        let dir = NSString("~/.xpip").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("settings.json")
    }()

    private static func migrateLegacySettingsIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: filePath),
              fm.fileExists(atPath: legacyFilePath) else { return }

        do {
            try fm.copyItem(atPath: legacyFilePath, toPath: filePath)
            print("Migrated settings from \(legacyFilePath) to \(filePath)")
        } catch {
            print("Failed to migrate legacy settings: \(error)")
        }
    }

    func load() {
        Self.migrateLegacySettingsIfNeeded()
        guard let data = FileManager.default.contents(atPath: Self.filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = json["enabled"] as? Bool { enabled = v }
        if let v = json["cooldown"] as? Double { cooldown = v }
        if let v = json["margin"] as? Double { margin = CGFloat(v) }
        if let v = json["cornerSize"] as? Double { cornerSize = CGFloat(v) }
        if let v = json["glow"] as? Bool { glow = v }
        if let v = json["glowColor"] as? String { glowColor = v }
        if let v = json["hotkeyCode"] as? Int { hotkeyCode = UInt16(v) }
        if let v = json["hotkeyFlags"] as? Int { hotkeyFlags = UInt32(v) }
        print("Settings loaded from \(Self.filePath)")
    }

    func save() {
        let dict: [String: Any] = [
            "enabled": enabled,
            "cooldown": cooldown,
            "margin": Double(margin),
            "cornerSize": Double(cornerSize),
            "glow": glow,
            "glowColor": glowColor,
            "hotkeyCode": Int(hotkeyCode),
            "hotkeyFlags": Int(hotkeyFlags),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.filePath))
    }
}

let settings = Settings()
