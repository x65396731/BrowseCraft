#!/usr/bin/env python3
import re
import sys

TRIGGERS = [
    r"BrowseCraft",
    r"Yealico",
    r"Site Rule",
    r"custom rule",
    r"自定义规则",
    r"规则模型",
    r"二维码规则",
    r"RuleParsingService",
    r"SwiftSoupRuleParser",
    r"SiteRule\\.swift",
    r"BrowseCraftRuleV2_Model\\.drawio",
]

text = sys.stdin.read() if not sys.argv[1:] else " ".join(sys.argv[1:])
matched = [pattern for pattern in TRIGGERS if re.search(pattern, text, re.IGNORECASE)]

if matched:
    print("Use $browsecraft-rule-workflow before proceeding.")
    print("Matched triggers: " + ", ".join(matched))
    print("Guardrails: Yealico wiki baseline; V2 tree DSL; readable drawio; Excel plan first.")
