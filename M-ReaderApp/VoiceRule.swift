import Foundation
import AVFoundation

/// 语音替换规则：定义一组标记（如「」、""）及对应的语音/音高参数，
/// 用于在朗读时实现"角色区分"效果。
struct VoiceRule: Codable, Equatable {
    /// 规则名称，供 UI 显示
    var name: String

    /// 开启标记的正则表达式（如：「）
    var openMark: String

    /// 关闭标记的正则表达式（如：」）
    var closeMark: String

    /// 是否启用此规则
    var enabled: Bool

    /// 对话句使用的音高倍率（0.5~2.0），默认 1.2
    var pitchMultiplier: Float

    /// 对话句使用的语速倍率（0.5~2.0），默认 1.0
    var rateMultiplier: Float

    init(name: String,
         openMark: String,
         closeMark: String,
         enabled: Bool = true,
         pitchMultiplier: Float = 1.2,
         rateMultiplier: Float = 1.0) {
        self.name = name
        self.openMark = openMark
        self.closeMark = closeMark
        self.enabled = enabled
        self.pitchMultiplier = pitchMultiplier
        self.rateMultiplier = rateMultiplier
    }

    /// 判断给定文本是否被此规则覆盖（即包含 begin/end 标记对）
    func matches(text: String) -> Bool {
        guard let openRegex = try? NSRegularExpression(pattern: openMark, options: []),
              let closeRegex = try? NSRegularExpression(pattern: closeMark, options: []) else {
            return false
        }
        let hasOpen = openRegex.firstMatch(in: text, options: [],
                                           range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        let hasClose = closeRegex.firstMatch(in: text, options: [],
                                             range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        return hasOpen && hasClose
    }
}

/// 预设规则集合
enum VoiceRulePresets {
    /// 默认规则：「」= 中文对话标记，音高提升 20%
    static let chineseDialogue = VoiceRule(
        name: "中文对话",
        openMark: "「",
        closeMark: "」",
        enabled: true,
        pitchMultiplier: 1.15,
        rateMultiplier: 1.0
    )

    /// 英文双引号对话
    static let englishQuote = VoiceRule(
        name: "英文引号对话",
        openMark: "\"",
        closeMark: "\"",
        enabled: false,
        pitchMultiplier: 1.2,
        rateMultiplier: 1.0
    )

    /// 全部预设
    static let all: [VoiceRule] = [VoiceRulePresets.chineseDialogue, VoiceRulePresets.englishQuote]
}
