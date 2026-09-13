import Foundation

public enum QuotaProvider: String, CaseIterable, Identifiable {
    case codex, cursor, claude, gemini
    public var id: String { rawValue }
    public var title: String {
        switch self { case .codex: return "Codex"; case .cursor: return "Cursor"; case .claude: return "Claude"; case .gemini: return "Gemini" }
    }
}

public enum ProviderOrder {
    public static func normalized(_ saved: [String]) -> [QuotaProvider] {
        var result: [QuotaProvider] = []
        for provider in saved.compactMap(QuotaProvider.init(rawValue:)) + QuotaProvider.allCases {
            if !result.contains(provider) { result.append(provider) }
        }
        return result
    }
    public static func moving(_ provider: QuotaProvider, by offset: Int, in order: [QuotaProvider]) -> [QuotaProvider] {
        guard let index = order.firstIndex(of: provider), abs(offset) == 1, order.indices.contains(index + offset) else { return order }
        var result = order
        result.swapAt(index, index + offset)
        return result
    }
}
