// The DICOM Viewer app icon: a stack of slices, the front one an axial head (skull, brain
// and ventricles) framed by corner marks in the accent colour.

import SwiftUI

struct IconFace: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.24, blue: 0.3), Color(red: 0.07, green: 0.08, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)

            // The slices behind, further back and dimmer.
            ForEach([2, 1], id: \.self) { k in
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color(white: 0.1 + 0.04 * Double(2 - k)))
                    .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color(white: 0.32), lineWidth: 4))
                    .frame(width: 520, height: 520)
                    .offset(x: CGFloat(k) * 44, y: CGFloat(-k) * 44)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous).fill(.black)
                RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(Color(white: 0.4), lineWidth: 4)
                Head()
                Corners()
                    .stroke(accent, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    .padding(46)
            }
            .frame(width: 520, height: 520)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
            .offset(x: -44, y: 44)
        }
    }

    /// An axial slice through a head: the skull's bright ring, the brain, and the dark
    /// ventricles in the middle.
    private struct Head: View {
        var body: some View {
            ZStack {
                Ellipse().fill(Color(white: 0.95)).frame(width: 300, height: 370)
                Ellipse().fill(Color(white: 0.5)).frame(width: 262, height: 332)
                Ellipse().fill(Color(white: 0.58)).frame(width: 200, height: 270).offset(y: 10)
                // The lateral ventricles, their front horns spreading apart.
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse()
                        .fill(Color(white: 0.16))
                        .frame(width: 30, height: 120)
                        .rotationEffect(.degrees(side * 18))
                        .offset(x: side * 26, y: -4)
                }
            }
            .shadow(color: .white.opacity(0.15), radius: 10)
        }
    }

    /// Four corner marks, like a viewer's frame around the image.
    private struct Corners: Shape {
        func path(in rect: CGRect) -> Path {
            let arm: CGFloat = 70
            return Path { p in
                for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1, 1),
                                       (rect.minX, rect.maxY, 1, -1), (rect.maxX, rect.maxY, -1, -1)] {
                    p.move(to: CGPoint(x: x, y: y + dy * arm))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx * arm, y: y))
                }
            }
        }
    }
}
