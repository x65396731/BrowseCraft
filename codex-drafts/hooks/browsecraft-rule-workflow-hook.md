# BrowseCraft Rule Workflow Hook Draft

This is a portable hook draft. Adapt it to the user's actual hook system before installing.

## Trigger Conditions

Trigger the BrowseCraft rule workflow when a prompt or changed file mentions any of:

```text
BrowseCraft
Yealico
Site Rule Wiki
site rule
custom rule
规则模型
自定义规则
二维码规则
RuleParsingService
SwiftSoupRuleParser
SiteRule.swift
BrowseCraftRuleV2_Model.drawio
```

## Required Reminders

When triggered, remind the agent to:

```text
1. Use the BrowseCraft Rule Workflow skill.
2. Treat Yealico Site Rule Wiki as the rule model baseline.
3. Prefer V2 tree DSL over patching the old flat SiteRule.
4. For drawio, use large canvases, sections, and minimal arrows.
5. For Excel, provide the edit plan first and modify only the requested sheet.
6. Validate drawio XML with xmllint.
7. Keep generated XcodeGen/CocoaPods output ignored when the user wants a clean fork.
```

## Example Hook Pseudocode

```bash
changed_or_prompt_text="$1"

if echo "$changed_or_prompt_text" | grep -Eiq 'BrowseCraft|Yealico|Site Rule|custom rule|自定义规则|规则模型|SwiftSoupRuleParser|SiteRule.swift|BrowseCraftRuleV2_Model.drawio'; then
  echo 'Use $browsecraft-rule-workflow before proceeding.'
fi
```
