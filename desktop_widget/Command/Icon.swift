// The command bar app icon: a prompt over a folder, on a dark tile.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "folder")
                .font(.system(size: 520, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.16))
                .offset(y: 20)
            Text("›_")
                .font(.system(size: 300, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .shadow(color: .orange.opacity(0.5), radius: 30)
                .offset(y: 30)
        }
    }
}
