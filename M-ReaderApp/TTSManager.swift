import Foundation
import AVFoundation
import Combine
import NaturalLanguage

/// 朗读管理器：逐句朗读，didFinish 切句并高亮整句。
///
/// 设计决策 — 为什么放弃 willSpeakRangeOfSpeechString：
///   1. 文本归一化偏移：合成器内部可能转换全角/半角标点，range 与原始文本错位
///   2. 中文分词粒度：回调按词组/短语，不是逐字，UI 闪烁且位置不连续
///   3. 线程地狱：回调在 AVSpeechSynthesizer 私有队列，直接写 @Published 不安全
///
/// 替代方案：解析阶段用 NLTokenizer 把文本切成句子数组，
/// 每句一个 AVSpeechUtterance，didFinish 时高亮下一整句。
///
/// 语音替换规则：遇「」等中文对话标记时自动切换音高/语速，实现角色区分。
@MainActor
final class TTSManager: NSObject, ObservableObject {
    // MARK: - Published 状态

    @Published var playbackState: PlaybackState = .stopped
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var selectedVoice: AVSpeechSynthesisVoice?
    @Published var availableVoices: [AVSpeechSynthesisVoice] = []

    /// 当前高亮句子的 UTF-16 范围（在原始完整文本中）
    @Published var highlightedRange: NSRange = NSRange(location: 0, length: 0)

    /// 当前高亮句子的文本（供菜单栏显示 15 字摘要用）
    @Published var highlightedText: String = ""

    /// 当前章节读到第几句 / 共多少句（供进度条用）
    @Published var currentSentenceIndex: Int = 0
    @Published var totalSentences: Int = 0

    /// 当前章节读完时发送信号，ViewModel 订阅此 Publisher 自动推进
    let chapterFinishedPublisher = PassthroughSubject<Void, Never>()

    // MARK: - 语音替换规则

    /// 当前生效的语音替换规则列表
    var voiceRules: [VoiceRule] = VoiceRulePresets.all {
        didSet {
            // 重建已编译的正则缓存
            compiledRules = voiceRules.filter(\.enabled).compactMap { rule -> CompiledRule? in
                guard let openR = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: rule.openMark), options: []),
                      let closeR = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: rule.closeMark), options: []) else {
                    return nil
                }
                return CompiledRule(rule: rule, openRegex: openR, closeRegex: closeR)
            }
        }
    }

    private struct CompiledRule {
        let rule: VoiceRule
        let openRegex: NSRegularExpression
        let closeRegex: NSRegularExpression
    }
    private var compiledRules: [CompiledRule] = []

    // MARK: - 私有状态

    private let synthesizer = AVSpeechSynthesizer()

    /// 当前章节的句子数组（由 NLTokenizer 切分）
    private var sentences: [String] = []

    /// 每句在完整文本中的 NSRange（UTF-16 坐标）
    private var sentenceRanges: [NSRange] = []

    /// 暂停时记录的句子索引，resume 时恢复
    private var pausedSentenceIndex: Int?

    /// 当前章节完整文本
    private var currentFullText: String = ""

    // MARK: - 初始化

    override init() {
        super.init()
        synthesizer.delegate = self
        voiceRules = VoiceRulePresets.all  // 触发 didSet 编译
        Task { @MainActor in
            loadVoices()
        }
    }

    private func loadVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let preferredLocales = ["zh-CN", "zh-HK", "zh-TW", "en-US", "en-GB", "en-AU"]
        availableVoices = allVoices.sorted { a, b in
            let aPreferred = preferredLocales.firstIndex(of: a.language) ?? Int.max
            let bPreferred = preferredLocales.firstIndex(of: b.language) ?? Int.max
            if aPreferred != bPreferred { return aPreferred < bPreferred }
            return a.language < b.language
        }
        selectedVoice = availableVoices.first { $0.language.hasPrefix("zh") }
            ?? availableVoices.first { $0.language.hasPrefix("en") }
            ?? availableVoices.first
    }

    // MARK: - 公开接口

    /// 朗读文本，内部切句后逐句播放
    func speak(text: String, from sentenceIdx: Int = 0) {
        synthesizer.stopSpeaking(at: .immediate)
        playbackState = .stopped

        currentFullText = text
        let pairs = splitIntoSentences(text)
        sentences = pairs.map { $0.sentence }
        sentenceRanges = pairs.map { $0.range }
        totalSentences = sentences.count
        let idx = max(0, min(sentenceIdx, max(0, sentences.count - 1)))
        currentSentenceIndex = idx

        if selectedVoice == nil {
            NSLog("[阻只读书] 警告：系统未安装中文语音，将使用英文语音。"
                  + "建议在 系统设置 → 辅助功能 → 语音内容 中下载中文语音。")
        }

        speakCurrentSentence()
    }

    /// 从指定字符偏移开始朗读（书签跳转用）
    func speak(fromCharacterOffset offset: Int, text: String) {
        let sentenceIdx = sentenceIndex(forCharacterOffset: offset, in: text)
        speak(text: text, from: sentenceIdx)
    }

    /// 计算指定字符偏移落在第几个句子（供恢复进度、书签跳转复用）
    func sentenceIndex(forCharacterOffset offset: Int, in text: String) -> Int {
        let pairs = splitIntoSentences(text)
        let ranges = pairs.map { $0.range }
        var sentenceIdx = 0
        for (i, range) in ranges.enumerated() {
            if range.location + range.length > offset {
                sentenceIdx = i
                break
            }
            if i == ranges.count - 1 { sentenceIdx = i }
        }
        return sentenceIdx
    }

    /// 暂停朗读（保留当前句子位置）
    func pause() {
        guard playbackState == .playing else { return }
        pausedSentenceIndex = currentSentenceIndex
        synthesizer.pauseSpeaking(at: .word)
        playbackState = .paused
    }

    /// 恢复朗读
    func resume() {
        guard playbackState == .paused else { return }
        synthesizer.continueSpeaking()
        playbackState = .playing
    }

    /// 停止朗读
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        playbackState = .stopped
        currentFullText = ""
        sentences = []
        sentenceRanges = []
        currentSentenceIndex = 0
        totalSentences = 0
        pausedSentenceIndex = nil
        highlightedRange = NSRange(location: 0, length: 0)
        highlightedText = ""
    }

    /// 跳到下一句播放
    func nextSentence() {
        guard playbackState == .playing || playbackState == .paused else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let next = min(currentSentenceIndex + 1, max(0, sentences.count - 1))
        currentSentenceIndex = next
        speakCurrentSentence()
    }

    /// 返回上一句播放
    func previousSentence() {
        guard playbackState == .playing || playbackState == .paused else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let prev = max(currentSentenceIndex - 1, 0)
        currentSentenceIndex = prev
        speakCurrentSentence()
    }

    /// 当前全局 UTF-16 偏移
    func currentGlobalOffset() -> Int {
        guard currentSentenceIndex < sentenceRanges.count else { return currentFullText.utf16.count }
        return sentenceRanges[currentSentenceIndex].location
    }

    /// 准备恢复位置：加载文本并定位到指定句子，但不播放（App 重启恢复进度用）
    func prepareForRestore(text: String, sentenceIndex: Int) {
        synthesizer.stopSpeaking(at: .immediate)
        playbackState = .stopped
        currentFullText = text
        let pairs = splitIntoSentences(text)
        sentences = pairs.map { $0.sentence }
        sentenceRanges = pairs.map { $0.range }
        totalSentences = sentences.count
        let idx = max(0, min(sentenceIndex, max(0, sentences.count - 1)))
        currentSentenceIndex = idx
        if idx < sentenceRanges.count {
            highlightedRange = sentenceRanges[idx]
            highlightedText = sentences[idx]
        }
    }

    /// 引号内心独白规则（通过控制面板开关）— 引号内文本降低音量和音高
    var treatQuotesAsInnerThought: Bool {
        get { UserDefaults.standard.bool(forKey: "TTSEngine.treatQuotesAsInnerThought") }
        set { UserDefaults.standard.set(newValue, forKey: "TTSEngine.treatQuotesAsInnerThought") }
    }

    // MARK: - 内部逻辑

    private func speakCurrentSentence() {
        guard currentSentenceIndex < sentences.count else {
            playbackState = .stopped
            chapterFinishedPublisher.send()
            return
        }

        let sentence = sentences[currentSentenceIndex]
        // 跳过空句，避免 AVSpeechUtterance 空字符串产生异常或立即回调导致深层递归
        guard !sentence.isEmpty else {
            currentSentenceIndex += 1
            speakCurrentSentence()
            return
        }

        let range = sentenceRanges[currentSentenceIndex]

        highlightedRange = range
        highlightedText = sentence

        let utterance = AVSpeechUtterance(string: sentence)
        utterance.rate = rate

        // 语音替换规则 — 检测对话标记，调整音高/语速（优先级高于引号规则）
        let matchingRule = findMatchingRule(for: sentence)
        if let matchingRule = matchingRule {
            utterance.pitchMultiplier = matchingRule.rule.pitchMultiplier
            utterance.rate = rate * matchingRule.rule.rateMultiplier
        } else if treatQuotesAsInnerThought, sentence.isWrappedInQuotes {
            utterance.pitchMultiplier = 0.9
            utterance.volume = 0.7
        } else {
            utterance.pitchMultiplier = 1.0
        }

        if !(treatQuotesAsInnerThought && sentence.isWrappedInQuotes && matchingRule == nil) {
            utterance.volume = 1.0
        }
        if let voice = selectedVoice {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
        playbackState = .playing
    }

    /// 在已编译规则中查找匹配当前句子的第一条
    private func findMatchingRule(for text: String) -> CompiledRule? {
        for compiled in compiledRules {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if compiled.openRegex.firstMatch(in: text, options: [], range: range) != nil,
               compiled.closeRegex.firstMatch(in: text, options: [], range: range) != nil {
                return compiled
            }
        }
        return nil
    }

    /// NLTokenizer 切句 + NSRange
    private func splitIntoSentences(_ text: String) -> [(sentence: String, range: NSRange)] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var results: [(String, NSRange)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let nsRange = NSRange(tokenRange, in: text)
            let sentence = String(text[tokenRange])
            results.append((sentence, nsRange))
            return true
        }
        if results.isEmpty {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            results.append((text, range))
        }
        return results
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSManager: AVSpeechSynthesizerDelegate {

    /// Delegate 回调在 AVSpeechSynthesizer 私有队列执行，
    /// 使用非隔离标记 + Task 跳回 @MainActor
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.playbackState = .playing
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentSentenceIndex += 1
            self.speakCurrentSentence()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.highlightedRange = NSRange(location: 0, length: 0)
            self?.highlightedText = ""
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.playbackState = .paused
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.playbackState = .playing
        }
    }
}
