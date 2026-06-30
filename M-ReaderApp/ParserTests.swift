import XCTest

final class ParserTests: XCTestCase {

    // MARK: - TXT 章节切分测试

    func testTXTChapterSplitting() {
        let parser = TXTParser()
        let text = """
        前言
        这是一段前言内容。

        第一章 开始
        这是第一章的内容，包含了多个段落。

        第二章 旅程
        这是第二章的内容。

        第三章 结束
        这是第三章的内容，故事结束了。
        """

        // 验证章节标题识别
        XCTAssertTrue(parser.isChapterTitle("第一章 开始"))
        XCTAssertTrue(parser.isChapterTitle("第 二 章 旅程"))
        XCTAssertFalse(parser.isChapterTitle("这是一段前言内容。"))

        let chapters = parser.splitChapters(from: text)
        XCTAssertGreaterThanOrEqual(chapters.count, 2, "应至少识别到 2 个章节")
    }

    func testTXTNoChapterTitle() {
        let parser = TXTParser()
        let text = """
        这是一段没有任何章节标题的纯文本内容。
        只有几个段落而已。
        没有第一章这种标记。
        """

        let chapters = parser.splitChapters(from: text)
        XCTAssertEqual(chapters.count, 1, "无章节标题时应返回 1 章全文")
        XCTAssertEqual(chapters.first?.title, "全文")
    }

    // MARK: - BookDocument offsetMap 测试

    func testBookDocumentOffsetMap() {
        let ch1 = MChapter(title: "第一章", content: "ABC", index: 0)
        let ch2 = MChapter(title: "第二章", content: "你好世界", index: 1)
        let ch3 = MChapter(title: "第三章", content: "123", index: 2)

        let doc = BookDocument(title: "测试书", chapters: [ch1, ch2, ch3])

        // chapterOffsetMap 应包含每个章节的 UTF-16 起始偏移
        XCTAssertEqual(doc.chapterOffsetMap[0], 0, "第一章从偏移 0 开始")
        XCTAssertEqual(doc.chapterOffsetMap[1], "ABC".utf16.count, "第二章从第一章长度之后开始")
        XCTAssertEqual(doc.chapterOffsetMap[2], "ABC".utf16.count + "你好世界".utf16.count, "第三章从累积偏移开始")

        // fullText 应是所有章节内容拼接
        XCTAssertEqual(doc.fullText, "ABC你好世界123")
    }

    // MARK: - DOCX SAX 解析测试

    func testDOCXSAXParsing() {
        // 测试 DOCXChapterDelegate 的基本逻辑
        let delegate = DOCXChapterDelegate()

        // 模拟 XML 解析过程：章节标题段落
        delegate.parser(XMLParser(), didStartElement: "pStyle", namespaceURI: nil, qualifiedName: nil, attributes: ["w:val": "Heading1"])
        delegate.parser(XMLParser(), foundCharacters: "第一章")
        delegate.parser(XMLParser(), didStartElement: "p", namespaceURI: nil, qualifiedName: nil, attributes: [:])
        delegate.parser(XMLParser(), foundCharacters: "正文内容")
        delegate.parser(XMLParser(), didEndElement: "p", namespaceURI: nil, qualifiedName: nil)

        // 验证至少能处理基本的 XML 事件
        XCTAssertEqual(delegate.currentTitle, "正文")
    }

    // MARK: - 章节标题正则测试

    func testChapterTitlePatterns() {
        let parser = TXTParser()

        let validTitles = [
            "第一章 序言",
            "第 二 章 启程",
            "第三章回",
            "Chapter 1 Introduction",
            "Chapter III The Journey",
            "1. 介绍",
            "一、概述",
            "二 详细说明"
        ]

        for title in validTitles {
            XCTAssertTrue(parser.isChapterTitle(title), "应识别为章节标题: \(title)")
        }

        let invalidTitles = [
            "",
            "这是一段普通的描述性文字它并不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题因为太长了不像是标题。"
        ]

        for title in invalidTitles {
            XCTAssertFalse(parser.isChapterTitle(title), "不应识别为章节标题: \(title.prefix(20))...")
        }
    }
}
