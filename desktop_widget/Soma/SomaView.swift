// SomaView — the player's window: channel art, a channel menu, the current artist and
// track, and a play/stop button with the stream's state beside it.

import SwiftUI

struct SomaView: View {
    @ObservedObject var player = SomaPlayer.shared
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            art
            VStack(alignment: .leading, spacing: 2) {
                channelMenu
                Text(player.song?.artist ?? player.channel?.description ?? " ")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(player.song?.title ?? " ")
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    playButton
                    status
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .rounded))
        .padding(14)
    }

    private var art: some View {
        AsyncImage(url: player.channel?.largeimage ?? player.channel?.image) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var channelMenu: some View {
        Menu {
            ForEach(player.channels) { channel in
                Button(channel.title) { player.select(channel) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(player.channel?.title ?? "SomaFM")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(player.channel?.description ?? "Choose a channel")
    }

    private var playButton: some View {
        let on = player.state == .playing || player.state == .connecting
        return Button { player.toggle() } label: {
            Image(systemName: on ? "stop.fill" : "play.fill")
                .font(.system(size: 11))
                .foregroundStyle(accent.readableText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
        .disabled(player.channel == nil)
        .help(on ? "Stop" : "Play")
    }

    @ViewBuilder private var status: some View {
        switch player.state {
        case .playing:
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(player.isMuted ? "LIVE · muted" : "LIVE")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
        case .connecting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Connecting…")
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.red)
                .lineLimit(1)
        case .stopped:
            Text(player.channel?.listeners.map { "\($0) listening" } ?? "")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }
}
