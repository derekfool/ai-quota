import Foundation

public enum QuotaSoundTheme: String, CaseIterable {
    case chimes, handpan
    public var title: String { self == .chimes ? "经典钟琴" : "Handpan 合奏" }
    public static func handpanName(for change: QuotaChange) -> String {
        // The celebratory ascending cue is reserved for recovery, never a large loss.
        if change.dominantDelta >= 20 { return "03-recovery-lift" }
        return change.intensity == .small ? "01-small-dialogue" : "02-medium-dialogue"
    }
    public static func handpanData(named name: String) -> Data? {
        let installed = Bundle.main.resourceURL?.appendingPathComponent("AIQuota_QuotaCore.bundle")
        let bundle = installed.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") else { return nil }
        return try? Data(contentsOf: url)
    }
}
