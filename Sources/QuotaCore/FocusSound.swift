import Foundation

public enum FocusSound {
    /// Use the approved quiet PCM assets without synthesis or normalization.
    public static func waveData(starting: Bool) -> Data? {
        let installed = Bundle.main.resourceURL?.appendingPathComponent("AIQuota_QuotaCore.bundle")
        let bundle = installed.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = bundle.url(forResource: starting ? "focus-on" : "focus-off", withExtension: "wav", subdirectory: "Sounds") else { return nil }
        return try? Data(contentsOf: url)
    }
}
