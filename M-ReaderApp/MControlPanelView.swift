import SwiftUI
import AVFoundation

/// 朗读控制面板：播放/暂停/停止/下一句、语速、音色、睡眠定时、章节进度、搜索
struct MControlPanelView: View {
    @ObservedObject var playerVM: PlayerViewModel

    var body: some View {
        InnerControlPanelView(playerVM: playerVM, ttsManager: playerVM.ttsManager)
    }
}

private struct InnerControlPanelView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var ttsManager: TTSManager

    var body: some View {
        VStack(spacing: 10) {
            // 章节进度条
            chapterProgressSection

            // 播放控制
            HStack(spacing: 16) {
                Button(action: { playerVM.togglePlayPause() }) {
                    Image(systemName: ttsManager.playbackState == .playing
                          ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Button(action: { playerVM.stopSpeaking() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)

                Button(action: { playerVM.nextSentence() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .help("下一句 (→)")

                Spacer()

                // 搜索按钮
                Button(action: { playerVM.showSearchSheet = true }) {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)

                // 添加书签
                Button(action: { playerVM.addBookmark() }) {
                    Label("书签", systemImage: "bookmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(playerVM.selectedChapter == nil)
            }

            // 语速 + 语音规则
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("语速：\(String(format: "%.2f", ttsManager.rate))")
                        .font(.caption)
                    Spacer()
                    voiceRuleToggle
                    quoteRuleToggle
                }
                Slider(value: $ttsManager.rate, in: 0.1...1.0, step: 0.05)
            }

            // 音色 + 睡眠定时
            HStack {
                Text("音色：").font(.caption)
                Picker("", selection: $ttsManager.selectedVoice) {
                    ForEach(ttsManager.availableVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice as AVSpeechSynthesisVoice?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()

                sleepTimerMenu
            }

            // 朗读状态提示
            HStack {
                if ttsManager.playbackState == .playing {
                    Text("正在朗读：第 \(playerVM.selectedChapter?.index ?? 0) 章")
                        .font(.caption)
                        .foregroundColor(Color.mSecondary)

                    if !playerVM.sleepRemainingFormatted.isEmpty {
                        Text("· 定时 \(playerVM.sleepRemainingFormatted)")
                            .font(.caption)
                            .foregroundColor(Color.mOrange)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - 章节进度条

    private var chapterProgressSection: some View {
        let total = ttsManager.totalSentences
        let current = ttsManager.currentSentenceIndex

        return Group {
            if ttsManager.playbackState != .stopped && total > 0 {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: Double(current), total: Double(max(total, 1)))
                        .tint(Color.mAccent)
                    HStack {
                        Text("本章进度：\(current)/\(total) 句")
                            .font(.caption2)
                            .foregroundColor(Color.mSecondary)
                        Spacer()
                        if total > 0 {
                            Text("\(Int(Double(current) / Double(total) * 100))%")
                                .font(.caption2)
                                .foregroundColor(Color.mSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 语音规则开关

    private var voiceRuleToggle: some View {
        let dialogueEnabled = ttsManager.voiceRules.first(where: { $0.name == "中文对话" })?.enabled ?? false

        return Button(action: {
            var rules = ttsManager.voiceRules
            if let idx = rules.firstIndex(where: { $0.name == "中文对话" }) {
                rules[idx].enabled.toggle()
            }
            ttsManager.voiceRules = rules
        }) {
            HStack(spacing: 4) {
                Image(systemName: dialogueEnabled ? "waveform.and.mic" : "mic.slash")
                    .font(.caption)
                Text(dialogueEnabled ? "角色区分：开" : "角色区分：关")
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .help("开启后，遇到「」内的对话文本将自动调整音高，实现角色区分")
    }

    // MARK: - 引号规则开关

    private var quoteRuleToggle: some View {
        let enabled = ttsManager.treatQuotesAsInnerThought
        return Button(action: {
            ttsManager.treatQuotesAsInnerThought.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: enabled ? "quote.bubble.fill" : "quote.bubble")
                    .font(.caption)
                Text(enabled ? "内心独白：开" : "内心独白：关")
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .help("开启后，英文引号 \"...\" 内的文本将以较低音量、稍低沉的音色朗读")
    }

    // MARK: - 睡眠定时菜单

    private var sleepTimerMenu: some View {
        Menu {
            ForEach(SleepTimerOption.allCases) { option in
                Button(option.label) {
                    playerVM.setSleepTimer(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: playerVM.sleepTimerOption.seconds != nil
                      ? "timer" : "timer.square")
                    .font(.caption)
                Text(playerVM.sleepTimerOption == .off ? "睡眠定时" : "睡眠定时")
                    .font(.caption)
            }
        }
        .menuIndicator(.hidden)
        .help("设定时间后自动停止朗读")
    }
}
