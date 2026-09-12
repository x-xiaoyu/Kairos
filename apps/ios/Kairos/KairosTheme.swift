import SwiftUI

extension Color {
    static let kairosGreen = Color(red: 0.12, green: 0.43, blue: 0.34)
    static let kairosCream = Color(red: 1.00, green: 0.97, blue: 0.91)
    static let kairosCoral = Color(red: 0.94, green: 0.42, blue: 0.35)
    static let kairosSun = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let kairosBlue = Color(red: 0.26, green: 0.56, blue: 0.91)
    static let kairosPurple = Color(red: 0.52, green: 0.38, blue: 0.82)
    static let kairosIndigo = Color(red: 0.28, green: 0.30, blue: 0.72)
    static let kairosMint = Color(red: 0.39, green: 0.76, blue: 0.61)
    static let kairosInk = Color(red: 0.10, green: 0.16, blue: 0.22)
}

enum KairosTheme {
    static let background = LinearGradient(colors: [.kairosCream, Color(red: 0.95, green: 0.97, blue: 1), Color(red: 1, green: 0.93, blue: 0.91)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let focus = LinearGradient(colors: [.kairosIndigo, .kairosPurple, .kairosBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accents: [Color] = [.kairosBlue, .kairosPurple, .kairosCoral, .kairosMint, .kairosSun]
}
