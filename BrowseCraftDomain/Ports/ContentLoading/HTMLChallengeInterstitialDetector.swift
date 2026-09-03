import Foundation

/// 中文注释：挑战过渡页（anti-bot interstitial）判据的唯一定义点（`BC-EVIDENCE-081`）。
///
/// 预检分类器的 `antiBotChallenge`、RSS 加载器的 `antiBot`、以及 WebView 文档加载器
/// 「过渡页不是文档、继续等待后续导航」三处都只消费这里的判定，不各自维护词表。
/// 强标记任一命中即挑战页（Cloudflare 挑战平台的结构性标识）；弱标记是自然语言文案，
/// 单独出现太容易误伤正文，要求至少两条同时命中。
public enum HTMLChallengeInterstitialDetector: Sendable {
    /// 中文注释：`/cdn-cgi/challenge-platform/scripts/jsd/` 是 Cloudflare 注入到每个正常页的 JS 检测探针，
    /// 不是过渡页；过渡页的结构标识是 `cf_chl_opt` 与挑战编排路径 `/cdn-cgi/challenge-platform/h/`
    /// （`BC-EVIDENCE-081` 09-03 晚修订）。
    public static let strongMarkers: [String] = [
        "cf-chl",
        "cf_chl_opt",
        "challenge-platform/h/"
    ]

    public static let weakMarkers: [String] = [
        "just a moment",
        "captcha",
        "verify you are human",
        "access denied",
        "cloudflare challenge",
        "attention required"
    ]

    public static func isChallengeInterstitial(_ html: String) -> Bool {
        let normalized: String = html.lowercased()
        if self.strongMarkers.contains(where: { normalized.contains($0) }) {
            return true
        }
        let weakHits: Int = self.weakMarkers.filter { normalized.contains($0) }.count
        return weakHits >= 2
    }
}
