// StippleWindow — one window: the drawing on its sheet of paper, the settings in an
// inspector at the side, or a note to drop a picture on it. Drop a picture anywhere on the
// window to stipple it; the toolbar switches dots and line, pauses, and saves.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StippleWindow: View {
    @Binding var url: URL?
    @StateObject private var model = StippleModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var active
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @AppStorage("showInspector") private var showInspector = true
    @State private var targeted = false

    var body: some View {
        content
            .frame(minWidth: 420, minHeight: 360)
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.color, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(accent.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.notice)
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard let first = files.first else { return false }
                url = first
                files.dropFirst().forEach { openWindow(value: $0) }
                return true
            } isTargeted: { targeted = $0 }
            .inspector(isPresented: $showInspector) {
                Controls(model: model)
                    .inspectorColumnWidth(min: 250, ideal: 280, max: 360)
            }
            .toolbar { toolbar }
            .navigationTitle(url?.lastPathComponent ?? "Stipple")
            .navigationSubtitle(model.status)
            .modifier(ProxyIcon(url: url))
            .task(id: url) { await model.load(url) }
            .onAppear {
                model.receive = { [$url, openWindow] urls in
                    var files = urls[...]
                    if $url.wrappedValue == nil, let first = files.popFirst() { $url.wrappedValue = first }
                    files.forEach { openWindow(value: $0) }
                }
                if active == .key || !Inbox.shared.hasFront { Inbox.shared.makeFront(model) }
            }
            .onChange(of: active) { _, state in
                if state == .key { Inbox.shared.makeFront(model) }
            }
            .onDisappear {
                model.stop()
                Inbox.shared.closed(model)
            }
            .tint(accent.color)
            .environment(\.accent, accent.color)
            .focusedSceneObject(model)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .empty:
            Placeholder(symbol: "circle.dotted", title: "Drop a picture here",
                        detail: "It's redrawn in dots that gather where it's dark, or as one continuous line, to save as SVG or PNG.",
                        highlighted: targeted)
        case .reading:
            ProgressView("Reading \(url?.lastPathComponent ?? "the picture")…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Placeholder(symbol: "exclamationmark.triangle", title: "Nothing to stipple",
                        detail: message, highlighted: targeted)
        case .ready:
            Paper(stipples: model.stipples, path: model.path, style: model.settings.style,
                  picture: model.settings.showPicture ? model.picture : nil)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Draw As", selection: $model.settings.style.mode) {
                ForEach(Style.Mode.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("Draw separate dots, or one line through them all")
        }
        ToolbarItemGroup {
            Button { model.pauseOrResume() } label: {
                model.busy ? Label("Pause", systemImage: "pause.fill") : Label("Keep Settling", systemImage: "play.fill")
            }
            .help(model.busy ? "Stop moving the dots" : "Let the dots settle some more")
            .disabled(model.phase != .ready)
            Button { model.restart() } label: { Label("Start Over", systemImage: "arrow.clockwise") }
                .help("Scatter a fresh set of dots (⌘R)")
                .disabled(model.phase != .ready)
            Menu {
                Button("Save as SVG…") { model.save(.svg) }
                Button("Save as PNG…") { model.save(.png) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save the drawing as SVG (⌘S) or PNG (⇧⌘S)")
            .disabled(!model.canExport)
        }
        ToolbarItem {
            Button { showInspector.toggle() } label: { Label("Settings", systemImage: "sidebar.trailing") }
                .help("Show or hide the settings")
        }
    }
}

/// The drawing, fitted to the window on a sheet of paper. Light ink on black when inverted.
struct Paper: View {
    var stipples: Stipples
    var path: [Int32]?
    var style: Style
    var picture: CGImage?

    var body: some View {
        Canvas { context, size in
            let margin: CGFloat = 24
            let scale = min((size.width - margin * 2) / CGFloat(stipples.width),
                            (size.height - margin * 2) / CGFloat(stipples.height))
            guard scale > 0 else { return }
            let sheet = CGRect(x: (size.width - CGFloat(stipples.width) * scale) / 2,
                               y: (size.height - CGFloat(stipples.height) * scale) / 2,
                               width: CGFloat(stipples.width) * scale, height: CGFloat(stipples.height) * scale)

            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.25), radius: 6, y: 2))
            shadowed.fill(Path(sheet), with: .color(Color(cgColor: style.paper)))

            context.clip(to: Path(sheet))
            if let picture {
                context.opacity = 0.35
                context.draw(Image(decorative: picture, scale: 1), in: sheet)
                context.opacity = 1
            }
            context.withCGContext { cg in
                cg.translateBy(x: sheet.minX, y: sheet.minY)
                cg.scaleBy(x: scale, y: scale)
                Drawing.draw(stipples, path: path, style: style, paper: false, in: cg)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

/// The inspector: what the dots are made from, how they look, and how long they settle.
struct Controls: View {
    @ObservedObject var model: StippleModel

    var body: some View {
        Form {
            Section("Dots") {
                LabeledSlider("Number", value: Binding(get: { Double(model.settings.dots) },
                                                       set: { model.settings.dots = Int($0) }),
                              range: 500...30_000, step: 500) { Int($0).formatted() }
                LabeledSlider("White cut-off", value: $model.settings.cutoff, range: 0.5...1, step: 0.01) {
                    $0 >= 1 ? "Off" : "\(Int(($0 * 100).rounded()))%"
                }
                .help("Parts of the picture lighter than this get no dots")
                Toggle("Light on black", isOn: $model.settings.style.invert)
                    .help("Stipple the light parts, in white ink on black paper")
            }

            if model.settings.style.mode == .dots {
                Section("Size") {
                    LabeledSlider("Smallest", value: smallest, range: 0.5...20, step: 0.5) { size($0) }
                    LabeledSlider("Largest", value: largest, range: 0.5...30, step: 0.5) { size($0) }
                }
            } else {
                Section("Line") {
                    LabeledSlider("Width", value: $model.settings.style.lineWidth, range: 0.25...8, step: 0.25) { size($0) }
                }
            }

            Section("Settling") {
                LabeledSlider("Steps", value: Binding(get: { Double(model.settings.steps) },
                                                      set: { model.settings.steps = Int($0) }),
                              range: 5...300, step: 5) { "\(Int($0))" }
                    .help("How many times the dots move before stopping. Keep Settling runs as many again.")
                HStack {
                    Button(model.busy ? "Pause" : "Keep Settling") { model.pauseOrResume() }
                    Button("Start Over") { model.restart() }
                }
                .disabled(model.phase != .ready)
            }

            Section("View") {
                Toggle("Show the picture underneath", isOn: $model.settings.showPicture)
            }

            Section("Export") {
                Picker("PNG size", selection: $model.settings.pngSide) {
                    ForEach([2400, 4800, 9600], id: \.self) { Text("\($0.formatted()) px").tag($0) }
                }
                Text("SVGs are in drawing units, \(DensityMap.side.formatted()) on the long side. Black-on-white SVGs have no background, ready for a pen plotter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func size(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // The two sizes push each other along, so the smallest is never the larger.
    private var smallest: Binding<Double> {
        Binding(get: { model.settings.style.smallest }, set: {
            model.settings.style.smallest = $0
            if model.settings.style.largest < $0 { model.settings.style.largest = $0 }
        })
    }

    private var largest: Binding<Double> {
        Binding(get: { model.settings.style.largest }, set: {
            model.settings.style.largest = $0
            if model.settings.style.smallest > $0 { model.settings.style.smallest = $0 }
        })
    }
}

/// A slider with its name on the left and its value on the right, above it.
struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
         format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .labelsHidden()
        }
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

/// The file's icon in the title bar, to drag or ⌘-click, once there is a file.
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
