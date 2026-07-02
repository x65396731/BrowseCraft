# BrowseCraft Rule V2 Model

Use this reference when designing structs, JSON schemas, drawio diagrams, or migration plans for BrowseCraft custom rules.

## Phase 1

Phase 1 should replace the flat parser model with a usable tree model.

```text
BrowseCraftRule
- version: Int
- site: SiteConfig
- urlPatterns: URLPatterns
- pages: [PageRule]
- ruleSets: RuleSets
- sharedRequest: RequestConfig?
- flags: [SiteFlag]
```

```text
SiteConfig
- name: String
- domain: String
- baseURL: String
- iconURL: String?
- displayMode: DisplayMode
- loginURL: String?
- language: String?
```

```text
URLPatterns
- series: String?
- list: String?
- detail: String?
- gallery: String?
- search: String?
```

Support placeholders:

```text
{page:start:step}
{idCode:}
{cidCode:}
{keyword:}
{url}
```

```text
PageRule
- id: String
- title: String
- type: PageType
- url: String?
- displayMode: DisplayMode?
- request: RequestConfig?
- ruleRefs: RuleRefs
- flags: [PageFlag]
```

```text
RuleRefs
- series: String?
- list: String?
- detail: String?
- gallery: String?
- search: String?
```

```text
RuleSets
- seriesRules: [ListRule]
- listRules: [ListRule]
- detailRules: [DetailRule]
- galleryRules: [GalleryRule]
```

```text
ExtractRule
- selector: String?
- function: ExtractFunction
- param: String?
- regex: String?
- replacement: String?
- fallback: [ExtractRule]
```

Required extraction functions for Phase 1:

```text
text
html
attr
raw
url
```

```text
RequestConfig
- method: HTTPMethod
- headers: [String: String]
- body: RequestBody?
- cookiePolicy: CookiePolicy
- charset: Charset
- needsWebView: Bool
- autoScroll: Bool
- imageHeaders: [String: String]?
```

Request inheritance:

```text
Rule request > Page request > Site sharedRequest
```

```text
ListRule
- id: String
- text: ExtractRule?
- item: ExtractRule
- fields: ListFields
- pagination: PaginationRule?
- ready: ExtractRule?
- request: RequestConfig?
- js: String?
```

```text
ListFields
- idCode: ExtractRule?
- title: ExtractRule
- cover: ExtractRule?
- detailURL: ExtractRule
- latestText: ExtractRule?
- coverWidth: ExtractRule?
- coverHeight: ExtractRule?
- category: ExtractRule?
- author: ExtractRule?
- publishedAt: ExtractRule?
- rating: ExtractRule?
- totalImages: ExtractRule?
```

```text
DetailRule
- id: String
- fields: DetailFields
- tagRule: NestedItemRule?
- chapterRule: ChapterRule?
- pictureRule: PictureRule?
- commentRule: NestedItemRule?
- videoRule: PictureRule?
- ready: ExtractRule?
- request: RequestConfig?
- js: String?
```

```text
ChapterRule
- item: ExtractRule
- idCode: ExtractRule?
- title: ExtractRule
- url: ExtractRule
- datetime: ExtractRule?
- sort: ChapterSort
```

```text
GalleryRule
- id: String
- secondLevelPageURL: ExtractRule?
- totalPages: ExtractRule?
- item: ExtractRule?
- image: ExtractRule
- thumbnail: ExtractRule?
- link: ExtractRule?
- pagination: PaginationRule?
- request: RequestConfig?
- js: String?
```

```text
PaginationRule
- nextPage: ExtractRule?
- pagePlaceholder: String?
- maxPages: Int?
- stopWhenEmpty: Bool
```

## Phase 2

Phase 2 adds advanced Yealico-like capabilities without blocking Phase 1.

```text
SelectorEngine
- kind: SelectorKind
- css: SwiftSoupEngine
- xpath: KannaEngine?
- jsonPath: JSONPathEngine?
- currentElement: NodeRef
```

```text
FunctionChain
- functions: [ExtractFunction]
- input: String
- output: String
```

Additional functions:

```text
decodeBase64
removingPercentEncoding
addingPercentEncoding
replace
decompressFromBase64
reversed
regexReplacement
```

```text
WebViewFetchRule
- enabled: Bool
- readySelector: ExtractRule?
- autoScroll: Bool
- timeoutSeconds: Double
- waitStrategy: WaitStrategy
- injectJavaScript: String?
- outputMode: WebViewOutputMode
```

```text
CookieStore
- browserCookie: String
- customCookie: String
- mergedCookie: String
- priority: CookiePriority
- storageScope: CookieScope
```

```text
SearchRule
- id: String
- keywordEncoding: KeywordEncoding
- url: String
- method: HTTPMethod
- request: RequestConfig?
- listRuleRef: String?
- item: ExtractRule
- fields: ListFields
- pagination: PaginationRule?
```

```text
RulePackageQR
- format: String
- version: Int
- compression: CompressionKind
- payload: BrowseCraftRule
- signature: String?
- remoteURL: String?
- checksum: String?
```

Recommended QR format:

```text
BrowseCraft Rule:v1:base64(gzip(json))
```

```text
CandidateAnalyzer
- inputURL: String
- renderedHTML: String?
- domSnapshot: String
- candidateItems: [NodeCandidate]
- candidateTitles: [NodeCandidate]
- candidateCovers: [NodeCandidate]
- candidateLinks: [NodeCandidate]
- confidence: Double
```

Do not promise full automatic site-rule inference. Present this as candidate recommendation plus user confirmation.
