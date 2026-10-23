import Foundation

/// 登录输入的全角字符检测（与 Android util/TextValidation.kt 范围一致）：
/// 中文输入法很容易混入全角数字/字母/标点/空格，而教务系统只认半角原文。
/// 只提示、不自动转换（不替用户改密码内容）。
private let fullWidthRanges: [ClosedRange<UInt32>] = [
    0x3000...0x3000, // 全角空格
    0xFF01...0xFF60, // 全角 ASCII 变体（！＂＃０９ＡＺａｚ等）
    0xFFE0...0xFFE6, // 全角货币/符号（￠￡￥等）
]

func findFullWidthChars(in text: String) -> [Character] {
    text.unicodeScalars
        .filter { scalar in fullWidthRanges.contains { $0.contains(scalar.value) } }
        .map { Character($0) }
}

func hasFullWidthChars(_ text: String) -> Bool {
    !findFullWidthChars(in: text).isEmpty
}

/// 错误提示里展示前几个全角字符（全角空格显示成 ␣ 才看得见）
func describeFullWidthChars(_ text: String) -> String {
    findFullWidthChars(in: text)
        .prefix(3)
        .map { $0 == "\u{3000}" ? "␣" : "'\($0)'" }
        .joined(separator: " ")
}
