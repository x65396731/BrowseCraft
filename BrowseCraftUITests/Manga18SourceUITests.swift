//  Manga18SourceUITests.swift
//  2026-09-18：验证线上生成来源 `manga18-club--list-manga`（显示名 manga18.club）。
//  读数以 `rule` 分类日志为准；本测试负责走到位并打印界面结构。

import XCTest

final class Manga18SourceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        print("=== TREE-\(tag)-BEGIN")
        print(app.debugDescription)
        print("=== TREE-\(tag)-END")
    }

    /// 列表项不是 cell，而是网格里的按钮/文字；用已知的作品标题定位。
    @MainActor
    func testDetailAndReader() throws {
        let app = XCUIApplication()
        app.launch()
        let skip = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "跳过")).firstMatch
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        Thread.sleep(forTimeInterval: 12)
        print("=== HOME images=\(app.images.count) buttons=\(app.buttons.count) statics=\(app.staticTexts.count)")

        // ① 点第一部作品。列表条目是按钮，标签形如「标题、标题 Chapter N 43 minutes ago …」；
        // 站点内容天天变，所以不认标题，只认「带章节信息且不是收藏/标签页」的条目按钮。
        let item = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND NOT (label BEGINSWITH %@) AND NOT (label CONTAINS %@)",
                "Chapter", "Read Latest", "Add Favorite"
            )
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 30), "列表里应有作品条目")
        print("=== TAP-COMIC: \(item.label.prefix(48)) hittable=\(item.isHittable)")
        if item.isHittable {
            item.tap()
        } else {
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        Thread.sleep(forTimeInterval: 18)
        dump(app, "DETAIL")
        print("=== DETAIL images=\(app.images.count) buttons=\(app.buttons.count) statics=\(app.staticTexts.count)")

        // ② 章节 → 阅读页：章节行是「1、Chapter 83」这种按钮；顶部另有「Read Latest · Chapter 83」
        // 「Read Latest · Chapter N」最稳：详情页头部固定存在，直接进阅读页。
        let readLatest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Read Latest")).firstMatch
        let chapterRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1、")).firstMatch
        if readLatest.waitForExistence(timeout: 30) {
            print("=== TAP-READ-LATEST: \(readLatest.label)")
            readLatest.tap()
        } else if chapterRow.waitForExistence(timeout: 15) {
            print("=== TAP-CHAPTER-ROW: \(chapterRow.label)")
            chapterRow.tap()
        } else {
            print("=== CHAPTER-NOT-FOUND buttons=\(app.buttons.count)")
            for index in 0..<min(app.buttons.count, 12) {
                print("===   button[\(index)]: \(app.buttons.element(boundBy: index).label)")
            }
        }
        Thread.sleep(forTimeInterval: 30)
        dump(app, "READER")
        print("=== READER images=\(app.images.count) buttons=\(app.buttons.count)")
        Thread.sleep(forTimeInterval: 10)
    }

    /// 单独一格：滚到列表底部，触发分页 `/list-manga/{page}`。
    /// 分页由网格底部一个 1pt 哨兵的 `onAppear` 触发（`VideoContentGridView`），所以必须真的滚到底；
    /// `app.swipeUp()` 不一定作用在滚动容器上，这里改用坐标拖拽。
    @MainActor
    func testPagination() throws {
        let app = XCUIApplication()
        app.launch()
        let skip = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "跳过")).firstMatch
        if skip.waitForExistence(timeout: 20) { skip.tap() }
        Thread.sleep(forTimeInterval: 12)

        let first = app.staticTexts["Rooftop Sex King"]
        print("=== BEFORE statics=\(app.staticTexts.count) firstExists=\(first.exists)")

        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
        for index in 0..<18 {
            bottom.press(forDuration: 0.05, thenDragTo: top)
            Thread.sleep(forTimeInterval: 1.5)
            if index % 4 == 0 {
                print("=== DRAG-\(index) statics=\(app.staticTexts.count) images=\(app.images.count) firstVisible=\(first.exists)")
            }
        }
        Thread.sleep(forTimeInterval: 10)
        print("=== AFTER statics=\(app.staticTexts.count) images=\(app.images.count)")
        dump(app, "AFTER-SCROLL")
    }
}
