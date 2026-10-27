// Chime — the timer's alarm: a bright two-note bell (C6 then E6, where hearing is most
// sensitive) synthesised at full level, since the system's own alert sounds are quiet.
// Built once into an in-memory WAV and played with NSSound.

import AppKit

enum Chime {
    static let sound: NSSound? = NSSound(data: wav())

    /// One ring: two bell strikes, about 1.3 seconds long.
    static func ring() {
        guard let sound else { return }
        sound.stop()
        sound.volume = 1
        sound.play()
    }

    private static func wav() -> Data {
        let rate = 44_100.0
        let length = Int(rate * 1.3)
        var samples = [Double](repeating: 0, count: length)

        // A struck bell: a fundamental plus two inharmonic-ish partials, fast attack,
        // exponential decay.
        func strike(_ frequency: Double, at start: Double) {
            let partials: [(ratio: Double, amplitude: Double, decay: Double)] = [(1, 1, 2.2), (2.01, 0.45, 3.5), (3.02, 0.2, 5)]
            for i in Int(start * rate)..<length {
                let t = Double(i) / rate - start
                let attack = min(1, t / 0.004)
                for p in partials {
                    samples[i] += p.amplitude * attack * exp(-p.decay * t) * sin(2 * .pi * frequency * p.ratio * t)
                }
            }
        }
        strike(1046.5, at: 0)
        strike(1318.5, at: 0.22)

        // Normalise to just under full scale, and fade the very end to avoid a click.
        let peak = samples.map(abs).max() ?? 1
        let fade = Int(rate * 0.05)
        let pcm: [Int16] = samples.enumerated().map { i, s in
            let tail = i > length - fade ? Double(length - i) / Double(fade) : 1
            return Int16(s / peak * 0.97 * tail * Double(Int16.max))
        }

        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        pcm.forEach { put($0) }
        return data
    }
}
