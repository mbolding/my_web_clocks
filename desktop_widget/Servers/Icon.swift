// The Server List app icon: three server rows, the top one picked out, on a slate tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.29, blue: 0.35), Color(red: 0.08, green: 0.1, blue: 0.13)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 40) {
                row("display", text: 300, picked: true)
                row("display", text: 240)
                row("terminal", text: 340)
            }
        }
    }

    private func row(_ symbol: String, text: CGFloat, picked: Bool = false) -> some View {
        HStack(spacing: 40) {
            Image(systemName: symbol)
                .font(.system(size: 92, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 130)
            Capsule()
                .fill(Color.white.opacity(0.8))
                .frame(width: text, height: 40)
        }
        .padding(.horizontal, 40)
        .frame(width: 680, height: 170, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(picked ? Color.orange.opacity(0.25) : Color.white.opacity(0.08)))
    }
}
