import XCTest

final class TTSManagerTests: XCTestCase {

    // MARK: - PlaybackState 转换测试

    func testPlaybackStateTransitions() {
        // PlaybackState 枚举值语义测试
        let state1 = PlaybackState.stopped
        let state2 = PlaybackState.playing
        let state3 = PlaybackState.paused

        XCTAssertEqual(state1, .stopped)
        XCTAssertEqual(state2, .playing)
        XCTAssertEqual(state3, .paused)
        XCTAssertNotEqual(state1, state2)
        XCTAssertNotEqual(state2, state3)
    }

    func testPlaybackStateInitialValue() {
        let manager = TTSManager()
        XCTAssertEqual(manager.playbackState, .stopped, "初始状态应为 stopped")
        XCTAssertEqual(manager.rate, AVSpeechUtteranceDefaultSpeechRate, "初始语速为默认值")
    }

    // MARK: - GlobalOffset 计算测试

    func testGlobalOffsetCalculation() {
        let manager = TTSManager()
        // 初始偏移应为 0
        XCTAssertEqual(manager.currentGlobalOffset(), 0, "初始全局偏移应为 0")

        // 停止后偏移应重置
        manager.stop()
        XCTAssertEqual(manager.currentGlobalOffset(), 0, "停止后偏移应重置为 0")
    }

    // MARK: - 高亮范围测试

    func testHighlightedRangeInitialValue() {
        let manager = TTSManager()
        XCTAssertEqual(manager.highlightedRange.location, 0, "初始高亮位置应为 0")
        XCTAssertEqual(manager.highlightedRange.length, 0, "初始高亮长度应为 0")
        XCTAssertEqual(manager.highlightedText, "", "初始高亮文本应为空")
    }

    func testPlaybackStateAfterStop() {
        let manager = TTSManager()
        manager.stop()
        XCTAssertEqual(manager.playbackState, .stopped, "停止后状态应为 stopped")
        XCTAssertEqual(manager.highlightedRange.length, 0, "停止后高亮应清除")
        XCTAssertEqual(manager.highlightedText, "", "停止后高亮文本应清除")
    }

    // MARK: - 语音加载测试

    func testVoiceLoading() {
        let manager = TTSManager()
        // availableVoices 应不为空（系统至少有英文语音）
        XCTAssertFalse(manager.availableVoices.isEmpty, "可用语音列表不应为空")
    }

    // MARK: - 章末检测逻辑测试

    func testChapterFinishedLogic() {
        let manager = TTSManager()

        // 初始状态：未播放
        XCTAssertEqual(manager.playbackState, .stopped)

        // 停止不应发出 chapterFinished 信号（通过状态验证）
        manager.stop()
        XCTAssertEqual(manager.playbackState, .stopped)
    }
}
