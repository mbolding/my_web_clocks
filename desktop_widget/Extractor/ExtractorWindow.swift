// ExtractorWindow — one window: the file's text, or a note to drop a file on it. Drop a
// file anywhere on the window to show it; the toolbar copies the text or saves it.

import SwiftUI
import AppKit

struct ExtractorWindow: View {
    @Binding var url: URL?
    @StateObject private var model = ExtractorModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var active
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @State private var targeted = false

    var body: some View {
        content
            .frame(minWidth: 380, minHeight: 300)
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
            .toolbar {
                ToolbarItemGroup {
                    Button { model.copyAll() } label: { Label("Copy All", systemImage: "doc.on.doc") }
                        .help("Copy all the text (⇧⌘C)")
                        .disabled(!model.canExport)
                    Button { model.save() } label: { Label("Save as Text", systemImage: "square.and.arrow.down") }
                        .help("Save the text as a plain text file (⌘S)")
                        .disabled(!model.canExport)
                }
            }
            .navigationTitle(url?.lastPathComponent ?? "Text Extractor")
            .navigationSubtitle(model.phase == .ready ? model.counts : "")
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
            .onDisappear { Inbox.shared.closed(model) }
            .tint(accent.color)
            .environment(\.accent, accent.color)
            .focusedSceneObject(model)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .empty:
            Placeholder(symbol: "doc.text.magnifyingglass", title: "Drop a PDF or Word document here",
                        detail: "Its text shows here, ready to select, copy or save as plain text.",
                        highlighted: targeted)
        case .reading:
            ProgressView("Reading \(url?.lastPathComponent ?? "the file")…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Placeholder(symbol: "exclamationmark.triangle", title: "No text to show",
                        detail: message, highlighted: targeted)
        case .ready:
            PlainTextView(text: $model.text)
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

/// A plain-text view that can be edited before saving, with the Find bar (⌘F). It doesn't
/// take drops itself, so a file dropped on the text goes to the window and replaces it.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DropThroughTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

final class DropThroughTextView: NSTextView {
    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }

    // Takes the focus as the text comes up, so Find and Select All work straight away.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}
