import CodexNotchShared
import SwiftUI

// Draws a fixed-size traffic-light status indicator for iOS dashboard and Live Activity surfaces.
struct StatusDot: View {
    let status: LANSessionStatus
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch status {
        case .red:
            return Color(red: 1.0, green: 0.24, blue: 0.22)
        case .yellow:
            return Color(red: 1.0, green: 0.74, blue: 0.18)
        case .green:
            return Color(red: 0.20, green: 0.82, blue: 0.42)
        }
    }
}
