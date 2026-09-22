#!/usr/bin/env python3
# 中文注释：本地化闸门。只读，从不修改任何文件。
#
# 不变量：编译器认定为「要本地化」的每一个键，三份 Localizable.strings 里都必须有。
#
# 「要本地化」的键有两个来源，合起来才完整：
#   - SwiftUI 的 LocalizedStringKey 与 String(localized:)（Text / Label / Section / Button / .alert …）
#     不靠正则猜，取编译器自己的判断：开启 SWIFT_EMIT_LOC_STRINGS 后，swiftc 把这些字面量连同
#     源文件与行号写进 Objects-normal/<arch>/*.stringsdata。本脚本作为编译后阶段读这些文件。
#   - NSLocalizedString swiftc 不提取（2026-09-22 实测）。Xcode 自带的 extractLocStrings 能提取，
#     但遇到一处非字面量参数就整批中止，所以这里直接从源码取它的第一个字面量参数——
#     NSLocalizedString("键", comment: "…") 的写法是固定的。
#
# 检查三条：
#   1. en / zh-Hans / zh-Hant 三份 Localizable.strings 能解析，且键集合完全一致；
#   2. 源码里每个要本地化的键在三份文件里都有，除非登记在 localization-missing-baseline.txt；
#   3. 基线只许收敛：登记的键如果已经补上了，必须把那一行删掉，否则闸门失败。
#
# 看不到的一类：把字面量先放进 String 再交给 Text(someString) / .accessibilityValue(someString)，
# SwiftUI 会逐字显示、不查表，编译器也就不把它当成要本地化的串。这类必须在源头写成
# NSLocalizedString(...)，写对了它就自动进入本闸门的视野。
#
# 用法：scripts/check-localization.py [Objects-normal 目录]
#   不给参数时取 Xcode 构建环境里的 $OBJECT_FILE_DIR_normal。
import glob
import json
import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_SOURCES = os.path.join(REPO_ROOT, "BrowseCraft")
NS_LOCALIZED_STRING = re.compile(r'NSLocalizedString\(\s*"((?:[^"\\\n]|\\.)*)"')
SWIFT_ESCAPES = {'"': '"', "\\": "\\", "n": "\n", "t": "\t", "'": "'", "0": "\0"}
LANGUAGES = ["en", "zh-Hans", "zh-Hant"]
TABLE = "Localizable"
BASELINE = os.path.join(REPO_ROOT, "scripts", "localization-missing-baseline.txt")


def load_strings(language):
    path = os.path.join(REPO_ROOT, "BrowseCraft", f"{language}.lproj", f"{TABLE}.strings")
    output = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", path],
        capture_output=True, text=True,
    )
    if output.returncode != 0:
        sys.exit(f"error: {path} 解析失败：{output.stderr.strip()}")
    return set(json.loads(output.stdout))


def load_baseline():
    # 每行一个键；键里的换行写成 \n。空行与 # 开头的行忽略。
    keys = set()
    with open(BASELINE, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line == "" or line.startswith("#"):
                continue
            keys.add(line.replace("\\n", "\n"))
    return keys


def extracted_keys(objects_dir):
    usages = {}
    files = glob.glob(os.path.join(objects_dir, "*", "*.stringsdata"))
    for path in files:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        source = data.get("source", "")
        # 增量构建会留下已删除源文件的 stringsdata，跳过它们以免误报。
        if source and not os.path.exists(source):
            continue
        for entry in data.get("tables", {}).get(TABLE, []):
            line = entry.get("location", {}).get("startingLine", 0)
            usages.setdefault(entry["key"], []).append(f"{os.path.relpath(source, REPO_ROOT)}:{line}")
    return files, usages


def ns_localized_string_keys(usages):
    for path in sorted(glob.glob(os.path.join(APP_SOURCES, "**", "*.swift"), recursive=True)):
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        for match in NS_LOCALIZED_STRING.finditer(source):
            literal = match.group(1)
            if "\\(" in literal:
                # 插值出来的键在运行期才确定，查不了表；这种写法本身就是错的，交给评审。
                continue
            key = re.sub(r"\\(.)", lambda escape: SWIFT_ESCAPES.get(escape.group(1), escape.group(0)), literal)
            line = source.count("\n", 0, match.start()) + 1
            usages.setdefault(key, []).append(f"{os.path.relpath(path, REPO_ROOT)}:{line}")


def main():
    objects_dir = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("OBJECT_FILE_DIR_normal", "")
    if objects_dir == "":
        sys.exit("error: 没有 Objects-normal 目录；在 Xcode 构建阶段里运行，或把目录作为参数传入")

    failures = []
    tables = {language: load_strings(language) for language in LANGUAGES}
    reference = tables[LANGUAGES[0]]
    for language in LANGUAGES[1:]:
        for key in sorted(reference - tables[language]):
            failures.append(f"{language} 缺少 en 里有的键 \"{key}\"")
        for key in sorted(tables[language] - reference):
            failures.append(f"{language} 多出 en 里没有的键 \"{key}\"")

    files, usages = extracted_keys(objects_dir)
    if not files:
        sys.exit(
            f"error: {objects_dir} 下没有任何 .stringsdata。"
            "确认 project.yml 里开着 SWIFT_EMIT_LOC_STRINGS: YES"
        )
    ns_localized_string_keys(usages)

    baseline = load_baseline()
    everywhere = set.intersection(*tables.values())
    for key in sorted(usages):
        # 空键是有意留空的标题（例如 .alert("", …)），查不查表都是空串。
        if key == "" or key in everywhere or key in baseline:
            continue
        missing = [language for language in LANGUAGES if key not in tables[language]]
        failures.append(
            f"\"{key}\" 没有翻译（缺 {', '.join(missing)}），用在 {usages[key][0]}。"
            f"三份 {TABLE}.strings 都要加上这个键"
        )
    for key in sorted(baseline & everywhere):
        failures.append(
            f"\"{key}\" 已经翻译了，把它从 {os.path.basename(BASELINE)} 里删掉——基线只许收敛"
        )

    for failure in failures:
        print(f"error: {failure}")
    if failures:
        print(f"本地化闸门失败：{len(failures)} 处")
        sys.exit(1)


if __name__ == "__main__":
    main()
