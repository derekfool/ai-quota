import AppKit
import QuotaCore

@MainActor final class QuotaFeedback {
    private var focusSound: NSSound?
    private var pending: QuotaChange?
    private var delivery: Task<Void, Never>?
    private var sound: NSSound?
    private var ensemble: [String: NSSound] = [:]
    private var theme = QuotaSoundTheme.handpan
    private var chimes: [Int: NSSound] = [:]
    init() {
        for name in ["01-small-dialogue", "02-medium-dialogue", "03-recovery-lift"] {
            if let data = QuotaSoundTheme.handpanData(named: name) { ensemble[name] = NSSound(data: data) }
        }
        for intensity in [ChangeIntensity.small, .large, .major] {
            for increasing in [false, true] {
                let key = intensity.rawValue * 2 + (increasing ? 1 : 0)
                chimes[key] = NSSound(data: QuotaChime.waveData(intensity: intensity, increasing: increasing))
            }
        }
    }
    func play(_ change: QuotaChange, theme: QuotaSoundTheme) {
        self.theme = theme
        if pending == nil || change.intensity > pending!.intensity { pending = change }
        guard delivery == nil else { return }
        // A refresh can complete both providers together; play the strongest cue once.
        delivery = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self, let change = self.pending else { return }
            self.pending = nil; self.delivery = nil
            let key = change.intensity.rawValue * 2 + (change.dominantDelta > 0 ? 1 : 0)
            self.sound?.stop()
            self.sound = self.theme == .handpan
                ? (self.ensemble[QuotaSoundTheme.handpanName(for: change)] ?? self.chimes[key])
                : self.chimes[key]
            self.sound?.currentTime = 0
            self.sound?.volume = 0.8
            self.sound?.play()
        }
    }
    func playFocus(starting: Bool) {
        focusSound?.stop()
        focusSound = FocusSound.waveData(starting: starting).flatMap { NSSound(data: $0) }
        focusSound?.volume = 1.0
        focusSound?.play()
    }
    func stop() { focusSound?.stop(); focusSound = nil; delivery?.cancel(); delivery = nil; pending = nil; sound?.stop(); sound = nil }
}
