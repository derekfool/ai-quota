import Foundation

/// Original major-pentatonic chimes; generated locally without audio files or system alert sounds.
public enum QuotaChime {
    public static let sampleRate = 44_100

    public static func samples(intensity: ChangeIntensity, increasing: Bool) -> [Double] {
        let notes: [Int]
        let spacing: Double
        switch intensity {
        case .small: notes = [76, 79]; spacing = 0.16
        case .large: notes = [72, 76, 79]; spacing = 0.17
        case .major: notes = [72, 74, 76, 79, 84]; spacing = 0.15
        }
        let melody = increasing ? notes : Array(notes.reversed())
        let tail = intensity == .major ? 1.15 : 0.85
        let duration = Double(notes.count - 1) * spacing + tail
        var result = [Double](repeating: 0, count: Int(duration * Double(sampleRate)))
        for (index, midi) in melody.enumerated() {
            let frequency = 440 * pow(2, Double(midi - 69) / 12)
            let offset = Int(Double(index) * spacing * Double(sampleRate))
            let length = result.count - offset
            for frame in 0..<length {
                let time = Double(frame) / Double(sampleRate)
                let phase = 2 * Double.pi * frequency * time
                // Soft attack avoids clicks; harmonic overtones decay sooner than the warm fundamental.
                let attack = min(1, time / 0.018)
                let release = min(1, Double(length - 1 - frame) / (0.12 * Double(sampleRate)))
                let tone = sin(phase) * exp(-time * 4.2)
                    + 0.24 * sin(phase * 2) * exp(-time * 7)
                    + 0.08 * sin(phase * 3) * exp(-time * 11)
                result[offset + frame] += tone * attack * release
            }
        }
        let peak = result.map { abs($0) }.max() ?? 1
        let level: Double = intensity == .small ? 0.48 : intensity == .large ? 0.62 : 0.76
        return result.map { $0 / max(peak, 0.001) * level }
    }

    public static func waveData(intensity: ChangeIntensity, increasing: Bool) -> Data {
        let pcm = samples(intensity: intensity, increasing: increasing)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); word(UInt32(36 + pcm.count * 2)); text("WAVEfmt ")
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2)); word(UInt16(2)); word(UInt16(16))
        text("data"); word(UInt32(pcm.count * 2))
        for sample in pcm { word(Int16((sample * Double(Int16.max)).rounded())) }
        return data
    }
}
