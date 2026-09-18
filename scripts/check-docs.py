#!/usr/bin/env python3
"""BrowseCraft 文档闸门。

形态与条款规则的定义点在 docs/README.md 第 3–5 节；本脚本只执行，不定义。
十一项检查 A1–A11 的口径见 docs/history/2026-09-19-docs-architecture-audit.md 第 6 节 D4。
提交任何 C 类文档、docs/STATUS.md 或 AGENTS.md 的改动前跑一次；任一项失败即不得提交。

用法：python3 scripts/check-docs.py [--fwq <path>]
退出码：0 全过（跳过的跨仓检查会如实报告），1 有失败。
"""
import argparse
import os
import re
import sys
from glob import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- 文档分类。与 docs/README.md 第 1 节的表一一对应，改一处要同时改那里。----
def rglob(pattern):
    """仓库相对的 glob。不用 glob(root_dir=) —— 那要 Python 3.10+。"""
    n = len(ROOT) + 1
    return sorted(p[n:] for p in glob(os.path.join(ROOT, pattern)))


def sibling(pkg, pattern):
    """兄弟包里的文档。包不在同级目录时返回空——闸门跳过而不是报错。"""
    base = os.path.join(os.path.dirname(ROOT), pkg)
    if not os.path.isdir(base):
        return []
    n = len(ROOT) + 1
    return sorted(os.path.relpath(x, ROOT) for x in glob(os.path.join(base, pattern)))


# 五个仓库共用一套条款命名空间、一张状态表、一个闸门，不各建一份。
# 兄弟包的 C 类文档进同一个扫描集；它们的条款定义点也在同一个 BCA-* 号段里。
SIBLING_DOC_PACKAGES = ["BrowseCraftCore"]

C_FILES = (
    ["AGENTS.md", "README.md", "docs/README.md", "docs/architecture.md", "scripts/README.md"]
    + rglob("docs/design/*.md")
    + rglob("BrowseCraft/*/README.md")
    + rglob("BrowseCraft/*/*/README.md")
    + [f for pkg in SIBLING_DOC_PACKAGES
       for f in sibling(pkg, "docs/README.md") + sibling(pkg, "docs/design/*.md")]
)
S_FILES = ["docs/STATUS.md"]
# HANDOFF.md 按 BCA-DOC-011 属 H 类：不适用 C 类形态约束，但参与 A1（不得承载定义点）、
# A2（引用的 ID 要有定义点）、A7（链接可解析）与 A9（只承载四样东西，规模是信号）。
HANDOFF = "HANDOFF.md"
H_FILES = (rglob("docs/history/*.md") + [HANDOFF]
           + [f for pkg in SIBLING_DOC_PACKAGES for f in sibling(pkg, "docs/history/*.md")])
ALL_FILES = C_FILES + S_FILES + H_FILES

# BCA-DOC-011 的规模阈值。唯一声明点在此，文档只说「有上限」不复述数值——写两处必然漂移。
HANDOFF_MAX_LINES = 250
HANDOFF_MAX_HASHES = 5

# A10：C 类文档点名的代码符号必须真的存在。白名单只许收敛，见文件头部。
EXTERNAL_SYMBOLS_FILE = "scripts/docs-external-symbols.txt"
# 至少两个驼峰节，避免把 RUNTIME、HTTP、JSON 这类全大写词与单节词当成类型名。
CAMEL_RE = re.compile(r"\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+)\b")
INLINE_SPAN_RE = re.compile(r"`([^`]+)`")
# 路径形状的记号不是类型名：迁移对照表会列已不存在的旧路径，那是历史事实不是漂移。
PATH_SPAN_RE = re.compile(r"[\w./-]+\.(?:swift|md|sh|py|yml|json|plist|strings|txt)\b|^[\w.-]+/")
SOURCE_GLOBS = [
    "BrowseCraft/**/*.swift", "BrowseCraftTests/**/*.swift", "BrowseCraftUITests/**/*.swift",
    "project.yml",
]
SIBLING_PACKAGES = ["BrowseCraftCore", "BrowseCraftDomain", "BrowseCraftRuntime", "BrowseCraftAPIKit"]

# ---- docs/README.md 第 4 节的受控词表。新增域必须先改那里，再改这里。----
DOMAINS = {"ARCH", "BUILD", "RUNTIME", "PARSE", "DB", "SYNC", "BOOK", "UI", "DOC"}

# ---- docs/README.md 第 5 节的列规格。C9/C14/C15 由同一份声明驱动，不各写一处判断。----
STATUS_COLUMNS = [
    ("工作项", None, False),
    ("条款", None, False),
    ("决策", {"required", "optional", "rejected"}, True),
    ("设计", {"draft", "pending-review", "approved", "superseded"}, True),
    ("实施", {"not-started", "in-progress", "implemented", "reverted"}, True),
    ("验证", {"not-run", "static-audit-passed", "targeted-passed", "full-suite-passed",
              "simulator-passed", "device-passed", "failed"}, True),
    ("检查点", re.compile(r"[0-9a-f]{7,40}"), False),
    ("更新日期", re.compile(r"\d{4}-\d{2}-\d{2}"), False),
]

DEF_RE = re.compile(r"^(?:- |\d+\. )`(BCA-([A-Z]+)-\d{3})`")
BCA_RE = re.compile(r"`(BCA-[A-Z]+-\d+)`")
BC_RE = re.compile(r"`(BC-[A-Z]+-\d+)`")
FWQ_DEF_RE = re.compile(r"^- `(BC-[A-Z]+-\d+(?:\.\d+)?)`")

# A4：状态串头部。「影响范围 / 影响源 / 问题类型」是范围声明，按三分法留在 C 类，不在此列。
STATUS_HEADER_RE = re.compile(r"^(更新时间|状态|前置)[:：]")
# A5：commit 哈希要求含至少一个数字，否则 a-f 组成的英文词会误报。
HASH_RE = re.compile(r"\b(?=[0-9a-f]{7,40}\b)(?=[a-f]*\d)[0-9a-f]{7,40}\b")
TESTCOUNT_RE = re.compile(r"\d+ 项 ?[/+] ?\d+|Swift Testing \d+|Ran \d+ tests|\d+ suites")
# A6：日志式章节标题 = 标题里带日期。
DATED_HEADING_RE = re.compile(r"^#{2,6} .*(20\d\d-\d\d-\d\d|20\d\d 年|20\d{5,6})")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
# 行内代码里的 `[...](...)` 是示例或正则，不是链接（归档里有一段 m3u8 正则会误报）。
INLINE_CODE_RE = re.compile(r"`[^`]*`")
FENCE_RE = re.compile(r"^\s*```")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def lines_outside_fences(text):
    """产出 (行号, 行)，跳过围栏代码块——里面的 ID 是语法示例，哈希是命令输出。"""
    inside = False
    for n, line in enumerate(text.split("\n"), 1):
        if FENCE_RE.match(line):
            inside = not inside
            continue
        if not inside:
            yield n, line


class Report:
    def __init__(self):
        self.failures = []
        self.skipped = []
        self.counts = {}

    def fail(self, check, where, msg):
        self.failures.append((check, where, msg))

    def skip(self, check, why):
        self.skipped.append((check, why))

    def note(self, check, text):
        self.counts[check] = text


def collect_definitions(rep):
    """A1：每个 BCA ID 恰有一个定义点，域在受控词表内，H 类不得承载定义点。"""
    seen = {}
    for rel in ALL_FILES:
        for n, line in lines_outside_fences(read(rel)):
            m = DEF_RE.match(line)
            if not m:
                continue
            cid, domain = m.group(1), m.group(2)
            where = f"{rel}:{n}"
            if rel in H_FILES:
                rep.fail("A1", where, f"H 类归档承载了定义点 {cid}（BCA-DOC-009：归档不构成生产约束）")
                continue
            if domain not in DOMAINS:
                rep.fail("A1", where, f"{cid} 的域 {domain} 不在受控词表内（docs/README.md 第 4 节）")
            if cid in seen:
                rep.fail("A1", where, f"{cid} 第二个定义点，首个在 {seen[cid]}（BCA-DOC-002）")
            else:
                seen[cid] = where
    rep.note("A1", f"{len(seen)} 个 BCA 定义点")
    return seen


def check_references(rep, defs, fwq_defs):
    """A2：引用到的 ID 必须有定义点。A3：本仓库不得为 fwq 已定义的 ID 写定义点。"""
    bca_refs, bc_refs = {}, {}
    for rel in ALL_FILES:
        for n, line in lines_outside_fences(read(rel)):
            for cid in BCA_RE.findall(line):
                bca_refs.setdefault(cid, f"{rel}:{n}")
            for cid in BC_RE.findall(line):
                bc_refs.setdefault(cid, f"{rel}:{n}")
    for cid, where in sorted(bca_refs.items()):
        if cid not in defs:
            rep.fail("A2", where, f"{cid} 没有定义点")
    if fwq_defs is None:
        rep.skip("A2", f"fwq 不可达，{len(bc_refs)} 个 BC-* 引用未核对")
        rep.skip("A3", "fwq 不可达，未核对本仓库是否为 fwq 已定义的 ID 另写定义点")
    else:
        for cid, where in sorted(bc_refs.items()):
            if cid not in fwq_defs:
                rep.fail("A2", where, f"{cid} 在 fwq 的 C 类文档里没有定义点")
        for rel in ALL_FILES:
            for n, line in lines_outside_fences(read(rel)):
                m = re.match(r"^(?:- |\d+\. )`(BC-[A-Z]+-\d+)`", line)
                if m and m.group(1) in fwq_defs:
                    rep.fail("A3", f"{rel}:{n}",
                             f"{m.group(1)} 的定义点在 fwq，本仓库只允许写引用点（BCA-DOC-001）")
    rep.note("A2", f"{len(bca_refs)} 个 BCA 引用 / {len(bc_refs)} 个 BC 引用")


def check_c_form(rep):
    """A4 状态串头部、A5 commit 哈希与测试计数、A6 带日期的章节标题。只查 C 类。"""
    a4 = a5 = a6 = 0
    for rel in C_FILES:
        for n, line in lines_outside_fences(read(rel)):
            where = f"{rel}:{n}"
            if STATUS_HEADER_RE.match(line):
                rep.fail("A4", where, f"C 类出现状态串头部行：{line.strip()[:60]}")
                a4 += 1
            for h in HASH_RE.findall(line):
                rep.fail("A5", where, f"C 类出现 commit 哈希 {h}（状态进 STATUS.md，纪事进 history）")
                a5 += 1
            if TESTCOUNT_RE.search(line):
                rep.fail("A5", where, f"C 类出现测试计数：{TESTCOUNT_RE.search(line).group(0)}")
                a5 += 1
            if DATED_HEADING_RE.match(line):
                rep.fail("A6", where, f"C 类出现带日期的章节标题：{line.strip()[:60]}")
                a6 += 1
    rep.note("A4", f"扫 {len(C_FILES)} 份 C 类")
    rep.note("A5", f"扫 {len(C_FILES)} 份 C 类")
    rep.note("A6", f"扫 {len(C_FILES)} 份 C 类")


def check_links(rep):
    """A7：相对链接可解析，禁止绝对主机路径。全部文档都查（含 H 类）。

    围栏代码块一并剥掉：里面的 `[](…)` 不会被渲染成链接，归档里的 JSON 正则会误报。
    """
    total = 0
    for rel in ALL_FILES:
        base = os.path.dirname(os.path.join(ROOT, rel))
        for n, line in lines_outside_fences(read(rel)):
            for target in LINK_RE.findall(INLINE_CODE_RE.sub("", line)):
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                total += 1
                where = f"{rel}:{n}"
                if target.startswith("/"):
                    rep.fail("A7", where, f"绝对主机路径：{target}（BCA-DOC-013 要求仓库相对路径）")
                    continue
                if not os.path.exists(os.path.join(base, target.split("#")[0])):
                    rep.fail("A7", where, f"链接解析不到：{target}")
    rep.note("A7", f"{total} 条仓库内链接")


def check_handoff(rep):
    """A9：HANDOFF.md 只承载四样东西，规模超限即说明它开始承载别的（BCA-DOC-011）。

    阈值是信号不是精确边界，故意留有余量。定义点归属由 A1 管，这里只看规模。
    """
    text = read(HANDOFF)
    n_lines = len(text.split("\n"))
    n_hashes = sum(len(HASH_RE.findall(line)) for _, line in lines_outside_fences(text))
    if n_lines > HANDOFF_MAX_LINES:
        rep.fail("A9", HANDOFF,
                 f"{n_lines} 行超过 {HANDOFF_MAX_LINES}：它只许承载四样东西，超限说明又开始记别的了")
    if n_hashes > HANDOFF_MAX_HASHES:
        rep.fail("A9", HANDOFF,
                 f"{n_hashes} 个 commit 哈希超过 {HANDOFF_MAX_HASHES}：状态性数字应现查，不该记死在这里")
    rep.note("A9", f"{n_lines} 行 / {n_hashes} 个哈希")


def load_tracked_files():
    """本仓库与兄弟包里被 git 跟踪的文档路径（仓库相对）。git 不可用时返回 None。"""
    import subprocess
    tracked = set()
    repos = [(ROOT, "")] + [
        (os.path.join(os.path.dirname(ROOT), pkg), os.path.join("..", pkg))
        for pkg in SIBLING_DOC_PACKAGES
    ]
    for base, prefix in repos:
        if not os.path.isdir(os.path.join(base, ".git")):
            continue
        try:
            out = subprocess.run(
                ["git", "-C", base, "ls-files", "--", "*.md"],
                capture_output=True, text=True, check=True
            ).stdout
        except (OSError, subprocess.CalledProcessError):
            return None
        for line in out.split("\n"):
            if line.strip():
                tracked.add(os.path.normpath(os.path.join(prefix, line.strip())))
    return tracked or None


def check_tracked(rep, defs):
    """A11：承载定义点的文档必须被 git 跟踪（BCA-DOC-015）。

    2026-09-19 实测：九条 BCA 定义点写在被 .gitignore 的 AGENTS.md 里，A1–A10 全绿而
    仓库里那九条合同根本不存在。不被跟踪的文档只能写引用点。
    """
    tracked = load_tracked_files()
    if tracked is None:
        rep.skip("A11", "git 不可用，未核对承载定义点的文档是否被跟踪")
        return
    untracked_with_defs = {}
    for cid, where in defs.items():
        rel = os.path.normpath(where.rsplit(":", 1)[0])
        if rel not in tracked:
            untracked_with_defs.setdefault(rel, []).append(cid)
    for rel, ids in sorted(untracked_with_defs.items()):
        rep.fail("A11", rel,
                 f"未被 git 跟踪却承载 {len(ids)} 个定义点（{', '.join(sorted(ids)[:4])}…）"
                 f"——它在别的机器上不存在，只能写引用点")
    scanned = {os.path.normpath(f) for f in C_FILES + S_FILES}
    rep.note("A11", f"{len(scanned & tracked)}/{len(scanned)} 份 C/S 类被跟踪")


def load_source_symbols():
    """本仓库与四个兄弟包里出现过的全部标识符。只读源码，不读构建产物。"""
    files = []
    for pattern in SOURCE_GLOBS:
        files += sorted(glob(os.path.join(ROOT, pattern), recursive=True))
    for pkg in SIBLING_PACKAGES:
        base = os.path.join(os.path.dirname(ROOT), pkg)
        if not os.path.isdir(base):
            return None, pkg
        files += sorted(glob(os.path.join(base, "Sources/**/*.swift"), recursive=True))
        files += sorted(glob(os.path.join(base, "Tests/**/*.swift"), recursive=True))
        files.append(os.path.join(base, "Package.swift"))
    words = set()
    token = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    # 路径段与文件名也算数据源：文档引用 `TestDoubles/`、`UseCases/`、`RuntimeAdFilter-Design.md`
    # 这类目录名与文件名是合法的，它们不是类型名。
    for base in [ROOT] + [os.path.join(os.path.dirname(ROOT), p) for p in SIBLING_PACKAGES]:
        for dirpath, dirnames, filenames in os.walk(base):
            if any(x in dirpath for x in (".git", ".build", ".derivedData", "node_modules")):
                dirnames[:] = []
                continue
            for name in dirnames + filenames:
                words.update(token.findall(name))
    for f in files:
        try:
            with open(f, encoding="utf-8") as fh:
                words.update(token.findall(fh.read()))
        except OSError:
            continue
    return words, None


def load_external_whitelist():
    path = os.path.join(ROOT, EXTERNAL_SYMBOLS_FILE)
    if not os.path.exists(path):
        return set()
    out = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#")[0].strip()
            if line:
                out.add(line.split()[0])
    return out


def check_symbols(rep):
    """A10：C 类文档反引号内点名的类型必须在源码里存在，或登记在白名单里。

    这一类漂移 A1–A9 一个都抓不到：2026-09-19 手工扫出 BCA-ARCH-001 正文点名了三个
    全仓零命中的类型，而九项闸门全绿。
    """
    symbols, missing_pkg = load_source_symbols()
    if symbols is None:
        rep.skip("A10", f"兄弟包 {missing_pkg} 不在同级目录，未核对文档点名的符号")
        return
    allowed = load_external_whitelist()
    seen = {}
    for rel in C_FILES:
        for n, line in lines_outside_fences(read(rel)):
            for span in INLINE_SPAN_RE.findall(line):
                if PATH_SPAN_RE.search(span):
                    continue
                wildcard = span.lstrip("`").startswith("*")
                for name in CAMEL_RE.findall(span):
                    seen.setdefault((name, wildcard), f"{rel}:{n}")
    suffixed = None
    bad = 0
    for (name, wildcard), where in sorted(seen.items()):
        if name in symbols or name in allowed:
            continue
        if wildcard:
            # `*Foo` 是家族通配，不是某一个类型名：源码里有任一以它结尾的符号即成立。
            if suffixed is None:
                suffixed = symbols
            if any(w.endswith(name) for w in suffixed):
                continue
        rep.fail("A10", where,
                 f"文档点名的 `{name}` 在源码里零命中；若确属外部符号，登记到 {EXTERNAL_SYMBOLS_FILE}")
        bad += 1
    rep.note("A10", f"{len(seen)} 个记号 / 白名单 {len(allowed)} 条")


def check_status(rep):
    """A8：STATUS.md 每格取值落枚举或形态，枚举列禁止 / 拼接。"""
    rows = 0
    for rel in S_FILES:
        for n, line in enumerate(read(rel).split("\n"), 1):
            if not line.startswith("| ") or line.startswith(("| ---", "| 工作项")):
                continue
            rows += 1
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            where = f"{rel}:{n}"
            if len(cells) != len(STATUS_COLUMNS):
                rep.fail("A8", where, f"列数 {len(cells)}，应为 {len(STATUS_COLUMNS)}")
                continue
            for cell, (name, rule, no_join) in zip(cells, STATUS_COLUMNS):
                if rule is None:
                    continue
                if no_join and "/" in cell:
                    rep.fail("A8", where, f"「{name}」列拼接了多值：{cell}（BCA-DOC-004）")
                    continue
                ok = cell in rule if isinstance(rule, set) else bool(rule.fullmatch(cell))
                if not ok:
                    rep.fail("A8", where, f"「{name}」列取值不合规：{cell}")
    rep.note("A8", f"{rows} 行")


def load_fwq_definitions(path):
    if not path or not os.path.isdir(path):
        return None
    files = sorted(glob(os.path.join(path, "docs/rules/*.md")))
    if not files:
        return None
    ids = set()
    for f in files:
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                m = FWQ_DEF_RE.match(line)
                if m:
                    ids.add(m.group(1))
    return ids or None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fwq", default=os.path.expanduser("~/Desktop/fwq"),
                    help="fwq 仓库路径；不可达时 A2 的 BC-* 部分与 A3 跳过并如实报告")
    args = ap.parse_args()

    rep = Report()
    fwq_defs = load_fwq_definitions(args.fwq)
    defs = collect_definitions(rep)
    check_references(rep, defs, fwq_defs)
    check_c_form(rep)
    check_links(rep)
    check_status(rep)
    check_handoff(rep)
    check_symbols(rep)
    check_tracked(rep, defs)

    titles = {
        "A1": "定义点唯一、域在词表内、H 类不承载定义点",
        "A2": "引用到的 ID 都有定义点",
        "A3": "不为 fwq 已定义的 ID 另写定义点",
        "A4": "C 类无状态串头部行",
        "A5": "C 类无 commit 哈希与测试计数",
        "A6": "C 类无带日期的章节标题",
        "A7": "链接可解析、无绝对主机路径",
        "A8": "STATUS.md 每格落枚举",
        "A9": "HANDOFF.md 只承载四样东西",
        "A10": "文档点名的代码符号都存在",
        "A11": "承载定义点的文档被 git 跟踪",
    }
    failed = {c for c, _, _ in rep.failures}
    skipped = {c for c, _ in rep.skipped}
    for code in sorted(titles, key=lambda c: int(c[1:])):
        if code in failed:
            mark = "FAIL"
        elif code in skipped:
            mark = "SKIP"
        else:
            mark = "ok  "
        print(f"  {mark}  {code}  {titles[code]}  {rep.counts.get(code, '')}")
    for code, why in rep.skipped:
        print(f"\n  SKIP {code}：{why}")
    if rep.failures:
        print(f"\n{len(rep.failures)} 处不合规：")
        for code, where, msg in rep.failures:
            print(f"  {code}  {where}\n        {msg}")
        return 1
    print("\n文档闸门全过。" + ("（有跳过项，见上）" if rep.skipped else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
