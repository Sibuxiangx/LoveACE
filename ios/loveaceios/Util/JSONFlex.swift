import Foundation

// 教务接口的 JSON 字段既可能是数字也可能是字符串，Android 端的 jsonPrimitive.intOrNull 同样兼容两者。

/// 整数：数字或数字字符串；取不到返回 nil。
nonisolated func jsonInt(_ value: Any?) -> Int? {
    switch value {
    case let number as NSNumber:
        return number.intValue
    case let text as String:
        return Int(text.trimmingCharacters(in: .whitespaces))
    default:
        return nil
    }
}

/// 文本：字符串或数字；空串视为缺失。
nonisolated func jsonText(_ value: Any?) -> String? {
    switch value {
    case let text as String:
        return text.isEmpty ? nil : text
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

/// 顶层为对象数组的 JSON；格式不对时抛出解析错误。
nonisolated func jsonObjectArray(_ data: Data) throws -> [[String: Any]] {
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw ServiceError.parseError("返回格式异常")
    }
    return array
}
