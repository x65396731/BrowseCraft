---
name: browsecraft-rule-workflow
description: Use when working on BrowseCraft custom site rules, Yealico Site Rule Wiki comparisons, rule-engine DSL design, rule parser implementation, rule-related drawio documents, or workflow guardrails for this project. Also use when the user asks to update project-specific skills/hooks for BrowseCraft, mentions Yealico rules/QR/site-rule wiki, or asks for rule model phases, custom rule structs, selector pipelines, WebView/headers/cookie handling, or rule import/export design.
---

# BrowseCraft Rule Workflow

Use this skill to keep BrowseCraft rule-engine work aligned with the user's project conventions and the Yealico-informed rule model.

## Core Rules

- Reply in Chinese unless the user explicitly requests Japanese review comments or another language.
- Treat Yealico's Site Rule Wiki as the design baseline when discussing custom rule models.
- Do not keep patching the old flat `SiteRule` model when the request is about rule capabilities. Prefer the V2 tree model.
- For Excel edits, provide the plan first and modify only the explicitly requested sheet.
- For drawio documents, prioritize readable structure over dense arrows. Use multiple pages/sheets and large canvases when needed.
- Before changing files, inspect the current file and briefly tell the user what edit will be made.

## Rule Model Guidance

When designing or reviewing BrowseCraft rules, use this hierarchy:

```text
BrowseCraftRule
  SiteConfig
  URLPatterns
  Pages[]
  RuleSets
    Series/List/Detail/Gallery/Search
  RequestConfig
  ExtractRule
```

The minimum V2 model should include:

- `ExtractRule`: `selector`, `function`, `param`, `regex`, `replacement`, `fallback`.
- `PageRule`: page id/title/type/url/display mode/request/rule refs.
- `RequestConfig`: method, headers, body, cookie policy, charset, WebView flag, auto-scroll, image headers.
- `PaginationRule`: URL placeholder pagination and next-page-link pagination.
- `DetailRule` child rules: chapter, picture, tag, comment, video as nested rules.

For detailed fields and phase split, read `references/rule-v2-model.md`.

## Yealico Comparison Workflow

When the task mentions Yealico:

1. Check whether the user is asking about the QR format, the Site Rule Wiki model, a site rule tutorial, or a real site rule example.
2. If using web information, prefer official Yealico pages first:
   - `https://yealico.app/site-rule-wiki/`
   - official Yealico tutorial/blog pages when relevant.
3. Keep the conclusion clear:
   - Yealico QR payload is private/opaque unless a public decoder or export format is available.
   - The useful part to copy is the rule model, not the QR encoding.
   - Third-party HTML parsers can parse DOM but cannot infer full site semantics.
4. Compare capabilities in terms of pages, selectors, request context, JS/WebView, pagination, and import/export.

For the condensed comparison checklist, read `references/yealico-comparison.md`.

## Drawio Workflow

When creating or editing rule-design drawio files:

1. Use separate diagrams/pages for phases or major concerns.
2. Use large canvases and section backgrounds.
3. Prefer grouped zones and placement over crossing arrows.
4. If arrows are needed, keep only high-signal parent-child or flow arrows.
5. Validate XML with `xmllint --noout <file>`.
6. If the target path is outside the workspace, ask or use an approved copy command.

## Hook Draft Workflow

If the user asks to rewrite hooks:

1. Ask for or inspect the actual hook format if available.
2. If unavailable, create a portable draft under the workspace first.
3. Hooks should enforce/remind:
   - Yealico-related rule work should use this skill.
   - Excel edits require a plan and single-sheet scope.
   - Drawio outputs should be XML-validated and readable.
   - Generated iOS projects/pods should remain ignored if the user wants a clean fork.

See `../../hooks/browsecraft-rule-workflow-hook.md` for the portable draft created with this skill.
