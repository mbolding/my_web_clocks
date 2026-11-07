// Activity — what Map Browser is asking a server for in the background, so the status bar
// can show it: searches and naming spots through Nominatim, and state parks through
// Overpass. Map tiles are left out, since they load all the time and the map shows them
// arriving anyway. Shared by every window.

import SwiftUI

@MainActor
final class Activity: ObservableObject {
    static let shared = Activity()

    /// What's out now, oldest first, by token.
    @Published private(set) var running: [(token: Int, label: String)] = []
    private var next = 0

    /// The newest request's label, or nil when nothing is out.
    var label: String? { running.last?.label }

    func begin(_ label: String) -> Int {
        next += 1
        running.append((next, label))
        return next
    }

    func end(_ token: Int) {
        running.removeAll { $0.token == token }
    }
}

/// A spinner and what it's waiting for, while anything is.
struct ActivityLabel: View {
    @ObservedObject private var activity = Activity.shared

    var body: some View {
        if let label = activity.label {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(label).foregroundStyle(.secondary)
            }
            .help(activity.running.map(\.label).joined(separator: "\n"))
            Divider().frame(height: 10)
        }
    }
}
