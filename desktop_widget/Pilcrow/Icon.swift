// The Pilcrow icon: a white page with a black ¶ on it, under a strip of the Ribbon, in
// System 7's black and white.

import SwiftUI

struct IconFace: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 150, style: .continuous).fill(Color(white: 0.85))
            // The page, with the black border and drop shadow of a System 7 window.
            Rectangle().fill(.black).frame(width: 560, height: 680).offset(x: 18, y: 18)
            Rectangle().fill(.white).frame(width: 560, height: 680)
                .overlay(Rectangle().stroke(.black, lineWidth: 12))
            VStack(spacing: 0) {
                // The Ribbon: three buttons, the first on.
                HStack(spacing: 18) {
                    Text("B").font(.custom("Times-Bold", size: 70)).foregroundStyle(.white)
                        .frame(width: 92, height: 82).background(.black)
                    Text("I").font(.custom("Times-Italic", size: 70)).frame(width: 92, height: 82)
                        .overlay(Rectangle().stroke(.black, lineWidth: 8))
                    Text("¶").font(.custom("Times-Roman", size: 70)).frame(width: 92, height: 82)
                        .overlay(Rectangle().stroke(.black, lineWidth: 8))
                }
                .foregroundStyle(.black)
                .padding(.top, 40)
                Rectangle().fill(.black).frame(width: 536, height: 8).padding(.top, 30)
                Text("¶").font(.custom("Times-Roman", size: 400)).foregroundStyle(.black).offset(y: -20)
            }
            .frame(width: 560, height: 680, alignment: .top)
        }
        .frame(width: 824, height: 824)
    }
}
