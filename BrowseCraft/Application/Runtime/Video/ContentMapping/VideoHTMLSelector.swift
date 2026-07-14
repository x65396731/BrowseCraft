import Foundation
import SwiftSoup

// 中文注释：VideoHTMLSelector 是 video runtime 专用 HTML selector adapter，隔离 SwiftSoup 依赖边界。
struct VideoHTMLSelector {
    func parse(html: String, baseURL: String) throws -> Document {
        return try SwiftSoup.parse(html, baseURL)
    }

    func elements(in document: Document, selector: String) throws -> [Element] {
        return try document.select(selector).array()
    }

    func elements(in element: Element, selector: String) throws -> [Element] {
        return try element.select(selector).array()
    }

    func firstElement(in element: Element, selector: String) throws -> Element? {
        return try element.select(selector).first()
    }

    func firstElement(in document: Document, selector: String) throws -> Element? {
        return try document.select(selector).first()
    }
}
