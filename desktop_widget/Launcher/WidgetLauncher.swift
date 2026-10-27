// WidgetLauncher — finds the installed widgets (apps whose Info.plist has DesktopWidget,
// which build.sh adds) in ~/Applications and /Applications, tracks which are running and
// which float on top, and opens, shows or quits them, or flips their Float on Top.

import AppKit

struct Widget: Identifiable {
    let id: String // bundle identifier
    let name: String
    let url: URL
    let icon: NSImage
}

@MainActor
final class WidgetLauncher: ObservableObject {
    static let shared = WidgetLauncher()

    @Published private(set) var widgets: [Widget]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var floating: Set<String> = []

    private var launches: NSKeyValueObservation?
    private var floatCheck: Timer?
    // Each running widget, held so it outlives its observation; KVO throws if an observed
    // object is freed with observers still attached.
    private var quits: [(app: NSRunningApplication, observation: NSKeyValueObservation)] = []

    private init() {
        widgets = Self.findWidgets()
        // NSWorkspace's launch and quit notifications skip apps without a Dock icon, which
        // is all of these. Instead, the running-apps list reports launches, and each
        // running widget's isTerminated reports its quit.
        launches = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshRunning() } }
        }
        refreshRunning()
        // A widget's own pin or menu can change its setting too, and nothing reports that
        // across apps, so look every couple of seconds.
        floatCheck = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFloating() }
        }
    }

    /// Every widget except this one, by name. A copy in ~/Applications wins over one in
    /// /Applications.
    static func findWidgets() -> [Widget] {
        let fm = FileManager.default
        let folders = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                       URL(fileURLWithPath: "/Applications")]
        var found: [String: Widget] = [:]
        for folder in folders {
            let apps = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in apps where url.pathExtension == "app" {
                guard let info = Bundle(url: url)?.infoDictionary,
                      info["DesktopWidget"] as? Bool == true,
                      let id = info["CFBundleIdentifier"] as? String,
                      id != Bundle.main.bundleIdentifier,
                      found[id] == nil else { continue }
                let name = info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                found[id] = Widget(id: id, name: name, url: url, icon: NSWorkspace.shared.icon(forFile: url.path))
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshRunning() {
        let ids = Set(widgets.map(\.id))
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(ids.contains) ?? false }
        running = Set(apps.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        refreshFloating()
        quits.forEach { $0.observation.invalidate() }
        quits = apps.map { app in
            (app, app.observe(\.isTerminated) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshRunning() } }
            })
        }
    }

    // Each widget keeps floatOnTop in its own preferences domain (its bundle id) and
    // watches it, so writing it here moves the widget's window straight away.
    private static func floats(_ id: String) -> Bool {
        CFPreferencesAppSynchronize(id as CFString)
        return CFPreferencesCopyAppValue("floatOnTop" as CFString, id as CFString) as? Bool ?? false
    }

    private func refreshFloating() {
        let now = Set(running.filter(Self.floats))
        if now != floating { floating = now }
    }

    /// A running widget's Float on Top, flipped.
    func toggleFloat(_ widget: Widget) {
        CFPreferencesSetAppValue("floatOnTop" as CFString, !Self.floats(widget.id) as CFBoolean, widget.id as CFString)
        CFPreferencesAppSynchronize(widget.id as CFString)
        refreshFloating()
    }

    /// Opens a widget, or, if it's running, brings its window up for a moment.
    func open(_ widget: Widget) {
        NSWorkspace.shared.openApplication(at: widget.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func quit(_ widget: Widget) {
        NSRunningApplication.runningApplications(withBundleIdentifier: widget.id).forEach { $0.terminate() }
    }
}
