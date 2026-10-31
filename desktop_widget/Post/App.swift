// SDF Post — a floating pad that posts what's in it to an SDF member's site: the web blog
// at user.sdf.org/blog/, the phlog in the gopher hole, and a gemlog in the Gemini capsule,
// all at once, over ssh with the key SDF already knows.

import SwiftUI

@main
enum SDFPostApp {
    @MainActor static func main() {
        // Starts below Scratch Pad, beside Command Bar, and floats on top until turned off.
        DesktopClock.run(size: CGSize(width: 340, height: 280), defaultTop: 24 + 170 + 20 + 250 + 20 + 240 + 20,
                         defaultRight: 24 + 420 + 20, interactive: true) {
            PostView()
        } options: {
            PostOptions()
        }
    }
}

struct PostOptions: View {
    @ObservedObject var poster = Poster.shared

    var body: some View {
        let site = poster.site
        Button("Open Blog") { NSWorkspace.shared.open(URL(string: site.blog)!) }
        Button("Open Phlog") { NSWorkspace.shared.open(URL(string: site.phlog)!) }
        Button("Open Gemlog") { NSWorkspace.shared.open(URL(string: site.gemlog)!) }
        Divider()
        Button("SDF Login: \(poster.login)…") { poster.setLogin() }
        Toggle("Link the Blog from My Homepage", isOn: $poster.linkHomepage)
        Divider()
        Button("Clear") { poster.clear() }
            .disabled(poster.title.isEmpty && poster.body.isEmpty)
        Divider()
    }
}
