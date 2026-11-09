// PanoramaWindow — the panorama, fitted to the window, over a strip of the photos it's
// made from, with the settings in an inspector at the side. Drop photos (or a folder of
// them) anywhere on the window to add them.

import SwiftUI
import AppKit

struct PanoramaWindow: View {
    @ObservedObject var model: PanoramaModel
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("showInspector") private var showInspector = true
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.photos.isEmpty {
                Divider()
                Filmstrip(model: model)
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .background(Color(nsColor: .underPageBackgroundColor))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.add(files)
            return true
        } isTargeted: { targeted = $0 }
        .inspector(isPresented: $showInspector) {
            Controls(model: model)
                .inspectorColumnWidth(min: 250, ideal: 270, max: 340)
        }
        .toolbar { toolbar }
        .navigationTitle("Panorama")
        .navigationSubtitle(subtitle)
        .tint(accent.color)
        .environment(\.accent, accent.color)
    }

    private var subtitle: String {
        switch model.phase {
        case .empty: return ""
        case .working(let message): return message
        case .failed: return "\(model.photos.count) photos"
        case .ready:
            guard let size = model.outputSize else { return "" }
            return "\(model.photos.count) photos · \(size.width.formatted()) × \(size.height.formatted())"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .empty:
            Placeholder(symbol: "pano", title: "Drop photos here",
                        detail: "Overlapping photos taken from one spot, turning between shots. They're matched, lined up and blended into one panorama.",
                        highlighted: targeted)
        case .failed(let message):
            Placeholder(symbol: "exclamationmark.triangle", title: "No panorama yet", detail: message, highlighted: targeted)
        case .working(let message):
            ZStack {
                if let preview = model.preview {
                    Preview(image: preview).opacity(0.35)
                }
                ProgressView(message)
            }
        case .ready:
            if let preview = model.preview {
                Preview(image: preview)
                    .overlay {
                        if let saving = model.saving {
                            ProgressView("Saving…", value: saving)
                                .frame(width: 220)
                                .padding(16)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Projection", selection: $model.settings.projection) {
                ForEach(Projection.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("How the panorama is unrolled: on a cylinder, a sphere, or flat")
        }
        ToolbarItemGroup {
            Button { model.choose() } label: { Label("Add Photos", systemImage: "plus") }
                .help("Add photos to the panorama (⌘O)")
            Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .help("Save the panorama at full size (⌘S)")
                .disabled(!model.canSave)
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("Settings", systemImage: "sidebar.trailing") }
                .help("Show or hide the settings")
        }
    }
}

/// The panorama, fitted to the space with a margin and a shadow, on a checkerboard where
/// it's transparent.
struct Preview: View {
    var image: CGImage

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = 24
            let scale = min((geometry.size.width - margin * 2) / CGFloat(image.width),
                            (geometry.size.height - margin * 2) / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * max(scale, 0.01), height: CGFloat(image.height) * max(scale, 0.01))
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .background(Checkerboard())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            for row in 0..<Int((size.height / side).rounded(.up)) {
                for column in 0..<Int((size.width / side).rounded(.up)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                                 with: .color(Color(white: 0.7)))
                }
            }
        }
    }
}

/// The photos in the order they're taken, each with a button to take it out; those that
/// matched nothing are dimmed and marked.
struct Filmstrip: View {
    @ObservedObject var model: PanoramaModel
    @State private var hovered: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(model.photos) { photo in
                    let left = model.unplaced.contains(photo.id)
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let thumbnail = model.thumbnails[photo.id] {
                                    Image(decorative: thumbnail, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(width: 88, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .opacity(left ? 0.4 : 1)
                            .overlay {
                                if left {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                        .shadow(radius: 2)
                                }
                            }
                            if hovered == photo.id {
                                Button { model.remove(photo) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 16))
                                }
                                .buttonStyle(.plain)
                                .padding(3)
                                .help("Take this photo out")
                            }
                        }
                        Text(photo.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 88)
                    }
                    .onHover { hovered = $0 ? photo.id : (hovered == photo.id ? nil : hovered) }
                    .help(left ? "\(photo.name) didn't overlap enough with the others, so it's left out" : photo.name)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 122)
        .background(.bar)
    }
}

/// The inspector: how the panorama is shaped and saved, and what was found.
struct Controls: View {
    @ObservedObject var model: PanoramaModel

    var body: some View {
        Form {
            Section("Shape") {
                Picker("Projection", selection: $model.settings.projection) {
                    ForEach(Projection.allCases) { Text($0.name).tag($0) }
                }
                Text(projectionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Crop to the filled area", isOn: $model.settings.crop)
                    .help("Trim the ragged edges where no photo reached")
                Toggle("Even out exposure", isOn: $model.settings.balance)
                    .help("Brighten or darken each photo a little so they match where they overlap")
            }

            Section("Save") {
                Picker("Size", selection: $model.settings.size) {
                    ForEach(Settings.Size.allCases) { Text($0.name).tag($0) }
                }
                if let size = model.outputSize {
                    LabeledContent("Pixels", value: "\(size.width.formatted()) × \(size.height.formatted())")
                    LabeledContent("Megapixels", value: (Double(size.width * size.height) / 1e6).formatted(.number.precision(.fractionLength(1))))
                }
                Button("Save…") { model.save() }
                    .disabled(!model.canSave)
                Button("Save as Animation…") { model.saveAnimation() }
                    .disabled(!model.canAnimate)
                    .help("The photos one after another as a looping GIF, held steady on the background: for a burst of something moving")
            }

            if let alignment = model.alignment {
                Section("Found") {
                    if let layout = model.layout {
                        LabeledContent("View", value: "\(Int(layout.degrees.x.rounded()))° × \(Int(layout.degrees.y.rounded()))°")
                    }
                    LabeledContent("Photos", value: "\(alignment.cameras.count) of \(model.photos.count) placed")
                    LabeledContent("Focal length", value: "\(Int(alignment.focal35.rounded())) mm")
                    Text(focalNote(alignment))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("Alignment", value: "\(alignment.error.formatted(.number.precision(.fractionLength(1)))) px")
                        .help("How far matched points still miss each other, on average, in full-size pixels")
                    if !alignment.unplaced.isEmpty {
                        Text("Photos marked ⚠︎ in the strip didn't overlap enough with the others and are left out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var projectionNote: String {
        switch model.settings.projection {
        case .cylinder: "For a single sweep: straight up stays straight, and it can go all the way round."
        case .sphere: "For several rows, or a lot of sky and ground: angles both ways, as a 360° viewer expects."
        case .flat: "An ordinary wide-angle picture, with straight lines straight. Only for views under about 120°."
        }
    }

    private func focalNote(_ alignment: Placement) -> String {
        switch alignment.focalSource {
        case .exif: "As on a 35 mm camera, from the photos' EXIF and refined from the matches."
        case .estimated: "As on a 35 mm camera. The photos don't say, so it's worked out from the matches."
        case .guessed: "As on a 35 mm camera. The photos don't say and the matches couldn't tell, so this is a guess."
        }
    }
}

/// The empty and failed states: a symbol, a line or two, and an Add button.
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
            Button("Add Photos…") { PanoramaModel.shared.choose() }
                .padding(.top, 6)
        }
        .frame(maxWidth: 380)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
