import SwiftUI

// 中文注释：RuleBasicFieldsEditorView 提供 P2-1.4 的基础字段表单，深层抽取规则仍交给 JSON 编辑器。

/// 中文注释：只编辑 SiteConfig、root baseURL 和 PageRule 基础字段，避免在 P2-1 提前实现完整规则构建器。
struct RuleBasicFieldsEditorView: View {
    @Binding var rule: SiteRule

    private let displayModes: [DisplayMode] = [
        .list,
        .grid,
        .webcomic,
        .verticalReader,
        .pagedReader
    ]
    private let pageTypes: [PageType] = [
        .home,
        .series,
        .list,
        .category,
        .detail,
        .gallery,
        .search,
        .reader
    ]

    var body: some View {
        Section("Rule") {
            TextField("Rule Name", text: self.$rule.name)
            TextField("Base URL", text: self.$rule.baseUrl)
                .autocapitalization(.none)
                .keyboardType(.URL)
        }

        Section("Site") {
            TextField("Site Name", text: self.siteTextBinding(\.name))
            TextField("Domain", text: self.siteTextBinding(\.domain))
                .autocapitalization(.none)
            TextField("Site Base URL", text: self.siteTextBinding(\.baseURL))
                .autocapitalization(.none)
                .keyboardType(.URL)
            TextField("Language", text: self.optionalSiteTextBinding(\.language))
            self.displayModePicker(
                title: "Display",
                selection: self.siteDisplayModeBinding()
            )
        }

        Section("Pages") {
            let pages: [PageRule] = self.rule.pages ?? []
            if pages.isEmpty {
                Text("This rule has no V2 pages. Use JSON editing to add page definitions.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(pages.indices, id: \.self) { index in
                    RulePageBasicFieldsEditorView(
                        page: self.pageBinding(index: index),
                        pageTypes: self.pageTypes,
                        displayModes: self.displayModes
                    )
                }
            }
        }
    }

    private func siteTextBinding(_ keyPath: WritableKeyPath<SiteConfig, String>) -> Binding<String> {
        return Binding<String>(
            get: {
                return self.rule.site?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.ensureSite()
                self.rule.site?[keyPath: keyPath] = newValue
            }
        )
    }

    private func optionalSiteTextBinding(_ keyPath: WritableKeyPath<SiteConfig, String?>) -> Binding<String> {
        return Binding<String>(
            get: {
                return self.rule.site?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.ensureSite()
                self.rule.site?[keyPath: keyPath] = self.nilIfBlank(newValue)
            }
        )
    }

    private func siteDisplayModeBinding() -> Binding<DisplayMode?> {
        return Binding<DisplayMode?>(
            get: {
                return self.rule.site?.displayMode
            },
            set: { newValue in
                self.ensureSite()
                self.rule.site?.displayMode = newValue
            }
        )
    }

    private func pageBinding(index: Int) -> Binding<PageRule> {
        return Binding<PageRule>(
            get: {
                return self.rule.pages?[index] ?? PageRule(
                    id: "",
                    title: "",
                    type: .list,
                    url: nil,
                    displayMode: nil,
                    request: nil,
                    tabGroup: nil,
                    sections: nil,
                    ruleRefs: nil,
                    flags: nil
                )
            },
            set: { newValue in
                guard self.rule.pages?.indices.contains(index) == true else {
                    return
                }

                self.rule.pages?[index] = newValue
            }
        )
    }

    private func displayModePicker(title: String, selection: Binding<DisplayMode?>) -> some View {
        Picker(title, selection: selection) {
            Text("Unset").tag(nil as DisplayMode?)
            ForEach(self.displayModes, id: \.self) { displayMode in
                Text(displayMode.rawValue).tag(displayMode as DisplayMode?)
            }
        }
    }

    private func ensureSite() {
        if self.rule.site == nil {
            self.rule.site = SiteConfig(
                name: self.rule.name,
                domain: "",
                baseURL: self.rule.baseUrl,
                iconURL: nil,
                displayMode: nil,
                loginURL: nil,
                language: nil
            )
        }
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmedValue: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private struct RulePageBasicFieldsEditorView: View {
    @Binding var page: PageRule
    let pageTypes: [PageType]
    let displayModes: [DisplayMode]

    var body: some View {
        DisclosureGroup {
            TextField("ID", text: self.$page.id)
                .autocapitalization(.none)
            TextField("Title", text: self.$page.title)
            Picker("Type", selection: self.$page.type) {
                ForEach(self.pageTypes, id: \.self) { pageType in
                    Text(pageType.rawValue).tag(pageType)
                }
            }
            TextField("URL", text: self.optionalTextBinding(\.url))
                .autocapitalization(.none)
                .keyboardType(.URL)
            self.displayModePicker()

            TextField("List Rule Ref", text: self.ruleRefBinding(\.list))
                .autocapitalization(.none)
            TextField("Detail Rule Ref", text: self.ruleRefBinding(\.detail))
                .autocapitalization(.none)
            TextField("Gallery Rule Ref", text: self.ruleRefBinding(\.gallery))
                .autocapitalization(.none)
            TextField("Search Rule Ref", text: self.ruleRefBinding(\.search))
                .autocapitalization(.none)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.page.title.isEmpty ? self.page.id : self.page.title)
                Text("\(self.page.id) · \(self.page.type.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func displayModePicker() -> some View {
        Picker("Display", selection: self.$page.displayMode) {
            Text("Unset").tag(nil as DisplayMode?)
            ForEach(self.displayModes, id: \.self) { displayMode in
                Text(displayMode.rawValue).tag(displayMode as DisplayMode?)
            }
        }
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<PageRule, String?>) -> Binding<String> {
        return Binding<String>(
            get: {
                return self.page[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.page[keyPath: keyPath] = self.nilIfBlank(newValue)
            }
        )
    }

    private func ruleRefBinding(_ keyPath: WritableKeyPath<RuleRefs, String?>) -> Binding<String> {
        return Binding<String>(
            get: {
                return self.page.ruleRefs?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                self.ensureRuleRefs()
                self.page.ruleRefs?[keyPath: keyPath] = self.nilIfBlank(newValue)
                self.removeEmptyRuleRefsIfNeeded()
            }
        )
    }

    private func ensureRuleRefs() {
        if self.page.ruleRefs == nil {
            self.page.ruleRefs = RuleRefs(
                series: nil,
                list: nil,
                detail: nil,
                gallery: nil,
                search: nil
            )
        }
    }

    private func removeEmptyRuleRefsIfNeeded() {
        guard let ruleRefs: RuleRefs = self.page.ruleRefs else {
            return
        }

        if ruleRefs.series == nil,
           ruleRefs.list == nil,
           ruleRefs.detail == nil,
           ruleRefs.gallery == nil,
           ruleRefs.search == nil {
            self.page.ruleRefs = nil
        }
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmedValue: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
