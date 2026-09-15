import BrowseCraftCore
import BrowseCraftDomain
import Foundation

// 中文注释：与来源类型无关的用例（同步、CloudKit、数据库、账户合并）用的来源配置。
// 这些用例原先拿 RSS 来源当样例；RSS 于 2026-09-16 整体下线后改用不执行的插件配置——构造不抛错，也不牵涉规则解码。
enum TestSourceFixtures {
    static func pluginConfiguration(id: String = "test.plugin") -> SourceConfiguration {
        return .plugin(
            PluginSourceConfiguration(
                definition: PluginSourceDefinition(
                    id: id,
                    manifestVersion: 1,
                    displayName: "Test Plugin",
                    runtime: .javaScript,
                    entrypoint: "index.js",
                    permissions: [.network],
                    checksum: nil,
                    isExecutable: false,
                    disabledReason: "Test fixture."
                )
            )
        )
    }
}
