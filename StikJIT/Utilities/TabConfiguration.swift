import Foundation

enum TabConfiguration {
    static let storageKey = "enabledTabIdentifiers"
    static let maxSelectableTabs = 4
    static let allowedIDs: [String] = ["home", "console", "scripts", "profiles", "processes", "deviceinfo", "location"]
    static let defaultIDs: [String] = ["home", "console", "scripts", "profiles"]
    static let defaultRawValue = serialize(defaultIDs)
    
    static func sanitize(raw: String) -> [String] {
        let ids = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return sanitize(ids: ids)
    }
    
    static func sanitize(ids: [String]) -> [String] {
        var result: [String] = []
        for id in ids {
            guard allowedIDs.contains(id) else { continue }
            if !result.contains(id) {
                result.append(id)
            }
            if result.count == maxSelectableTabs {
                break
            }
        }
        if result.isEmpty {
            result = defaultIDs
        }
        return result
    }
    
    static func serialize(_ ids: [String]) -> String {
        sanitize(ids: ids).joined(separator: ",")
    }
}
