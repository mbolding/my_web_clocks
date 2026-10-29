// The scratch pad app icon: a few lines of writing under an orange heading, on a sheet
// of paper.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.99), Color(white: 0.88)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 62) {
                Capsule().fill(Color.orange).frame(width: 360, height: 56)
                ForEach([560, 500, 600, 420, 280], id: \.self) { width in
                    Capsule().fill(Color(white: 0.55)).frame(width: CGFloat(width), height: 34)
                }
            }
            .padding(.leading, 190)
            .padding(.top, 205)
        }
    }
}
