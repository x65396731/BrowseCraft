import Testing
@testable import BrowseCraft

// 中文注释：章节标题解析（`docs/design/Comic-Detail-Page-Redesign-Design.md` 第七节）：
// 编号柱、话名与「纯编号 / 带名」版式判断只看标题形状，用四个站的真实章节名做样本。
struct ComicChapterTitleParserTests {
    @Test func parsesNumberAndName() {
        let parsed = ComicChapterTitleParser.parse("第1249话 乌云乌云别找我麻烦。")
        #expect(parsed.numberLabel == "1249")
        #expect(parsed.name == "乌云乌云别找我麻烦。")
    }

    @Test func parsesPureNumberTitles() {
        let parsed = ComicChapterTitleParser.parse("第94话")
        #expect(parsed.numberLabel == "94")
        #expect(parsed.name.isEmpty)
    }

    @Test func skipsNonDigitPrefixLikeVIP() {
        let parsed = ComicChapterTitleParser.parse("VIP第993话")
        #expect(parsed.numberLabel == "993")
        #expect(parsed.name.isEmpty)
    }

    @Test func parsesSubPartAndSeparator() {
        let parsed = ComicChapterTitleParser.parse("1話(1):あるまじき瞳の色")
        #expect(parsed.numberLabel == "1-1")
        #expect(parsed.name == "あるまじき瞳の色")

        let half = ComicChapterTitleParser.parse("第5話前半")
        #expect(half.numberLabel == "5-前半")
        #expect(half.name.isEmpty)
    }

    @Test func parsesEnglishChapterPrefix() {
        let parsed = ComicChapterTitleParser.parse("Chapter 12: The End")
        #expect(parsed.numberLabel == "12")
        #expect(parsed.name == "The End")
    }

    @Test func parsesChineseNumerals() {
        let biquhua = ComicChapterTitleParser.parse("第八百六十二章 普罗万修！（大结局）")
        #expect(biquhua.numberLabel == "862")
        #expect(biquhua.name == "普罗万修！（大结局）")

        let first = ComicChapterTitleParser.parse("第一章 大唐亡了？")
        #expect(first.numberLabel == "1")
        #expect(first.name == "大唐亡了？")

        #expect(ComicChapterTitleParser.chineseNumber("十二") == 12)
        #expect(ComicChapterTitleParser.chineseNumber("一千零一") == 1001)
        #expect(ComicChapterTitleParser.chineseNumber("二零一") == 201)
        #expect(ComicChapterTitleParser.chineseNumber("两万三千") == 23000)
    }

    @Test func leavesTitlesWithoutNumberUntouched() {
        let parsed = ComicChapterTitleParser.parse("短篇 [完]")
        #expect(parsed.numberLabel == nil)
        #expect(parsed.name == "短篇 [完]")
    }

    @Test func pureNumberCatalogAllowsFewExceptions() {
        var titles: [String] = (1...30).map { "第\($0)话" }
        titles.append("番外")
        let parsed = titles.map(ComicChapterTitleParser.parse)
        #expect(ComicChapterTitleParser.isPureNumberCatalog(parsed))
    }

    @Test func namedCatalogUsesRows() {
        let titles: [String] = ["第1话 开始", "第2话 相遇", "第3话", "第4话 离别"]
        let parsed = titles.map(ComicChapterTitleParser.parse)
        #expect(ComicChapterTitleParser.isPureNumberCatalog(parsed) == false)
        #expect(ComicChapterTitleParser.isPureNumberCatalog([]) == false)
    }
}
