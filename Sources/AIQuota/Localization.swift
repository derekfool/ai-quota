import Foundation
import QuotaCore

func L(_ chinese: String, _ english: String) -> String {
    AppLanguage.current.text(chinese, english)
}
func localized(_ value: String) -> String { AppLanguage.current.display(value) }
