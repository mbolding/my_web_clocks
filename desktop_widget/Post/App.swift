// SDF Post — a drawer at the edge of the screen that posts what's in it to an SDF member's
// site: the web blog at user.sdf.org/blog/, the phlog in the gopher hole, and a gemlog in
// the Gemini capsule, all at once, over ssh with the key SDF already knows. A thin tab
// peeks in from the edge; hover or click it to slide out the pad, or drop text or a text
// file on it to open the pad with that in it.

import SwiftUI
import UniformTypeIdentifiers

@main
enum SDFPostApp {
    @MainActor static func main() {
        // Lower on the edge than Text Drawer's tab, so the two sit apart on one edge. It
        // stays open while you type in it, until you click elsewhere or press Esc.
        EdgeDrawer.run(panelSize: CGSize(width: 340, height: 300), position: 0.62,
                       stayOpenWhileTyping: true,
                       dropTypes: [.fileURL, .plainText],
                       onDrop: { Poster.shared.take($0) }) {
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
