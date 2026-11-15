import SwiftUI

/// The "field notebook" colours at night: the iPhone app's dark variants on the watch's black.
enum WatchPalette {
    static let card = Color(red: 0x1E / 255, green: 0x23 / 255, blue: 0x1B / 255)
    static let cardBorder = Color(red: 0x2E / 255, green: 0x35 / 255, blue: 0x29 / 255)
    static let ink = Color(red: 0xE3 / 255, green: 0xE8 / 255, blue: 0xDA / 255)
    static let inkMuted = Color(red: 0x9A / 255, green: 0xA8 / 255, blue: 0x8F / 255)
    /// Light moss: ticks, rings, accents.
    static let moss = Color(red: 0xA9 / 255, green: 0xC4 / 255, blue: 0x93 / 255)
    /// Deep moss: filled buttons.
    static let mossDeep = Color(red: 0x4F / 255, green: 0x6B / 255, blue: 0x4A / 255)
}
