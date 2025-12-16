import Foundation

enum FeatureFlags {
    /// Global toggle for exposing location spoofing UI/logic.
    static let isLocationSpoofingEnabled = false
    /// Controls visibility of beta-quality tabs and UI.
    static let showBetaTabs = false
    /// Forces the Theme Expansion to be unlocked and visible everywhere.
    static let alwaysUnlockThemeExpansion = false
    /// Controls visibility of the Mini Tools tab and related UI.
    static let isMiniToolsEnabled = false
}
