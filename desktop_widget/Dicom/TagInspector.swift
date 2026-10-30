// TagInspector — the current file's tags: tag, name, VR and value, with sequence items
// indented under their sequence. The field at the top filters by any of them, and
// selected rows copy as text.

import SwiftUI
import AppKit

struct TagInspector: View {
    @ObservedObject var tags: Tags
    @State private var query = ""
    @State private var selection = Set<TagRow.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Table(filtered, selection: $selection) {
                TableColumn("Tag") { row in
                    Text(row.tag).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                .width(min: 76, ideal: 78, max: 90)
                TableColumn("Name") { row in
                    Text(row.name)
                        .foregroundStyle(row.tag.isEmpty ? .secondary : .primary)
                        .padding(.leading, CGFloat(row.depth) * 10)
                        .help(row.name)
                }
                .width(min: 80, ideal: 130)
                TableColumn("VR") { row in
                    Text(row.vr).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                .width(min: 22, ideal: 24, max: 30)
                TableColumn("Value") { row in
                    Text(row.value).help(row.value)
                }
                .width(min: 80, ideal: 120)
            }
            .contextMenu(forSelectionType: TagRow.ID.self) { ids in
                Button("Copy") { copy(ids) }.disabled(ids.isEmpty)
                Button("Copy Value") { copyValue(ids) }.disabled(ids.count != 1)
                Divider()
                Button("Copy All Tags") { tags.copyAll() }
            }
            .onCopyCommand {
                let text = lines(selection)
                return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
            }
        }
        .onChange(of: tags.file?.url) { selection = [] }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let file = tags.file {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(TransferSyntax.name(file.transferSyntax)) · \(TagRows.size(file.size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if file.truncated {
                        Label("The file ends early; some values may be cut short.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter tags", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear the filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
    }

    private var filtered: [TagRow] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return tags.rows }
        return tags.rows.filter { row in words.allSatisfy { row.search.contains($0) } }
    }

    private func lines(_ ids: Set<TagRow.ID>) -> String {
        tags.rows.filter { ids.contains($0.id) }.map(\.line).joined(separator: "\n")
    }

    private func copy(_ ids: Set<TagRow.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines(ids), forType: .string)
    }

    private func copyValue(_ ids: Set<TagRow.ID>) {
        guard let row = tags.rows.first(where: { ids.contains($0.id) }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.value, forType: .string)
    }
}
