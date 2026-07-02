# Yealico Comparison Checklist

Use this when comparing BrowseCraft rule design to Yealico.

## Confirmed Design Lessons

- Yealico rules are tree-shaped, not flat.
- A Site contains multiple Rules; a Rule contains multiple Selectors.
- Selectors are structured pipelines with selector/function/param/regex/replacement.
- Page types can have different URLs, headers, cookies, JS requirements, and parsing rules.
- Detail pages may contain child rules for chapters, pictures, tags, comments, and videos.
- Pagination can be URL placeholder based or next-link based.
- Headers can be scoped and inherited.
- WebView/JS rendering is necessary for some sites.
- QR publishing is useful as a distribution model, but Yealico QR payload is private/opaque unless a public decoder/export is available.

## BrowseCraft Gap Checklist

Check whether BrowseCraft supports:

```text
Site metadata
Multiple pages
Per-page display mode
Per-page URL patterns
Rule references
RequestConfig inheritance
ExtractRule five-parameter pipeline
Regex replacement
Fallback extraction
Chapter child rules
Picture/gallery child rules
Search rules
Next-page link pagination
WebView ready selector
Cookie policy
Charset handling
QR import/export for BrowseCraft's own format
Rule debugger
Candidate node analyzer
```

## Recommended Framing

When explaining decisions to the user:

- Say "third-party parsers help with DOM, but not business semantics."
- Say "the useful part to copy from Yealico is the rule model and editor workflow."
- Avoid saying Yealico QR is impossible to decode forever; say it is not usable without public format details or exported clear rules.
- Prefer "Phase 1/Phase 2" rollout to avoid boiling the ocean.
