// ViewerWindow — one window: the series found in its files down the sidebar, the image
// with a slider for the slices, and the tags in the inspector. Drop files or folders
// anywhere on the window to show them instead.

import SwiftUI
import AppKit

struct ViewerWindow: View {
    @Binding var urls: [URL]?
    @StateObject private var model = ViewerModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var active
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("showTags") private var showTags = true
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var targeted = false

    var body: some View {
        content
            .frame(minWidth: 640, minHeight: 440)
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.color, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(accent.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.notice)
            .dropDestination(for: URL.self) { dropped, _ in
                let files = dropped.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                urls = files
                return true
            } isTargeted: { targeted = $0 }
            .navigationTitle(title)
            .navigationSubtitle(model.selected?.study ?? "")
            .modifier(ProxyIcon(url: urls?.count == 1 ? urls?.first : nil))
            .task(id: urls) { await model.load(urls ?? []) }
            .onChange(of: model.series.count) { _, count in
                columns = count > 1 ? .all : .detailOnly
            }
            .onAppear {
                // Weakly, as the model keeps this closure.
                model.receive = { [$urls, openWindow, weak model] files in
                    guard let model else { return }
                    if model.isEmpty { $urls.wrappedValue = files } else { openWindow(value: files) }
                }
                if active == .key || !Inbox.shared.hasFront { Inbox.shared.makeFront(model) }
            }
            .onChange(of: active) { _, state in
                if state == .key { Inbox.shared.makeFront(model) }
            }
            .onDisappear { Inbox.shared.closed(model) }
            .tint(accent.color)
            .environment(\.accent, accent.color)
    }

    private var title: String {
        if let selected = model.selected { return selected.displayTitle }
        return urls?.first?.lastPathComponent ?? "DICOM Viewer"
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .empty:
            Placeholder(symbol: "photo.stack", title: "Drop DICOM files or a folder here",
                        detail: "Series are gathered from everything inside, with their images, window and level, and tags.",
                        highlighted: targeted)
        case .loading(let fraction):
            ProgressView(value: fraction) { Text("Reading \(urls?.first?.lastPathComponent ?? "the files")…") }
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Placeholder(symbol: "exclamationmark.triangle", title: "Nothing to show", detail: message, highlighted: targeted)
        case .ready:
            NavigationSplitView(columnVisibility: $columns) {
                SeriesList(model: model)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
            } detail: {
                ImagePane(display: model.display)
                    .toolbar { ImageToolbar(model: model) }
                    .inspector(isPresented: $showTags) {
                        TagInspector(tags: model.tags)
                            .inspectorColumnWidth(min: 320, ideal: 460, max: 800)
                    }
            }
        }
    }
}

/// The series, by study, with a picture of each one's middle slice.
struct SeriesList: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(studies, id: \.key) { study in
                Section(study.label) {
                    ForEach(study.series) { series in
                        SeriesRow(series: series, thumbnail: model.thumbnails[series.id])
                            .tag(series.id)
                    }
                }
            }
        }
    }

    private var studies: [(key: String, label: String, series: [Series])] {
        var out: [(key: String, label: String, series: [Series])] = []
        for series in model.series {
            if let i = out.firstIndex(where: { $0.key == series.studyKey }) {
                out[i].series.append(series)
            } else {
                out.append((series.studyKey, series.study.isEmpty ? "Study" : series.study, [series]))
            }
        }
        return out
    }
}

struct SeriesRow: View {
    let series: Series
    let thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.black
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFit()
                } else {
                    Image(systemName: series.hasImage ? "photo" : "list.bullet.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(series.displayTitle).lineLimit(2)
                Text(series.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// The image, its corner readouts and the slice slider. Only the pieces that change with
/// each slice watch the display, so scrolling through a series doesn't rebuild the window.
struct ImagePane: View {
    let display: Display

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SliceView(display: display)
                ProblemNote(display: display)
                Readouts(display: display)
                    .allowsHitTesting(false)
            }
            SliceBar(display: display)
        }
        .background(.black)
    }
}

/// The toolbar's window presets, invert and zoom buttons. It's built from the window's
/// model, which changes with the series, not with every slice and drag.
struct ImageToolbar: ToolbarContent {
    @ObservedObject var model: ViewerModel

    var body: some ToolbarContent {
        let display = model.display
        let canWindow = model.selected?.canWindow ?? false
        ToolbarItemGroup {
            Menu {
                ForEach(display.presets) { preset in
                    Button(preset.name) { display.apply(named: preset.name) }
                }
                Divider()
                Button("Reset Window") { display.resetWindow() }
            } label: {
                Label("Window", systemImage: "circle.lefthalf.filled")
            }
            .help("Window presets, from the file and for CT")
            .disabled(!canWindow)
            Button { display.invert.toggle() } label: { Label("Invert", systemImage: "circle.righthalf.filled") }
                .help("Invert the greyscale (⌘I)")
                .disabled(!canWindow)
            Button { display.zoomToFit() } label: { Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                .help("Fit the image to the window (⌘0)")
        }
    }
}

/// Why a slice can't be shown, over the black where it would be.
struct ProblemNote: View {
    @ObservedObject var display: Display

    var body: some View {
        if let problem = display.problem {
            VStack(spacing: 10) {
                Image(systemName: "eye.slash").font(.system(size: 40, weight: .light))
                Text(problem).multilineTextAlignment(.center)
                Text("The tags are still in the inspector.").font(.callout).opacity(0.7)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: 380)
            .padding()
            .allowsHitTesting(false)
        }
    }
}

/// Slice number, position, window and zoom in the image's corners.
struct Readouts: View {
    @ObservedObject var display: Display

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                if let slice = display.slice {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.series?.displayTitle ?? "")
                        Text(slice.file.name).opacity(0.7)
                    }
                }
                Spacer()
                if display.zoom != 1 {
                    Text("\(Int((display.zoom * 100).rounded()))%")
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if display.count > 0 {
                        Text("Image \(display.index + 1) of \(display.count)")
                    }
                    if let location { Text(location) }
                }
                Spacer()
                if display.canWindow {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let name = display.presetName { Text(name).opacity(0.7) }
                        Text("W \(Self.number(display.window.width))  L \(Self.number(display.window.center))")
                    }
                }
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
        .shadow(color: .black, radius: 1.5)
        .padding(10)
    }

    /// The slice's position along its normal, or its Slice Location.
    private var location: String? {
        guard let slice = display.slice else { return nil }
        if let info = slice.file.image?.frames[slice.frame], let p = info.position, let o = info.orientation {
            let n = [o[1] * o[5] - o[2] * o[4], o[2] * o[3] - o[0] * o[5], o[0] * o[4] - o[1] * o[3]]
            return "Position \(Self.number(p[0] * n[0] + p[1] * n[1] + p[2] * n[2])) mm"
        }
        return slice.file.number(0x0020_1041).map { "Location \(Self.number($0)) mm" }
    }

    static func number(_ x: Double) -> String {
        abs(x) >= 100 || x == x.rounded() ? String(Int(x.rounded())) : String(format: "%.1f", x)
    }
}

/// A slider through the slices, under the image.
struct SliceBar: View {
    @ObservedObject var display: Display

    var body: some View {
        if display.count > 1 { bar }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { Double(display.index) }, set: { display.index = Int($0.rounded()) }),
                   in: 0...Double(max(display.count - 1, 1)))
                .controlSize(.small)
            Text("\(display.index + 1) / \(display.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// The empty and failed states: a symbol, a line or two, and an Open button.
struct Placeholder: View {
    var symbol: String
    var title: String
    var detail: String
    var highlighted: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(highlighted ? accent : .secondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.title3.weight(.medium))
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open…") { Inbox.shared.choose() }
                .padding(.top, 6)
        }
        .frame(maxWidth: 360)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The file or folder's icon in the title bar, to drag or ⌘-click, when one was opened.
struct ProxyIcon: ViewModifier {
    var url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}
