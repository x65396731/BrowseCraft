#!/bin/bash
# 中文注释：随包位图资产的构建前闸门。只读，从不修改任何文件。
# 资产目录里的位图不被任何既有用例覆盖：换错格式的表现是界面空白而不是报错，
# 塞进一张无损 PNG 的表现是包体悄悄变大而没人发现。这个闸门把两件事都挡住。
#
# 检查四条：
#   1. 资产目录里的每个 imageset / appiconset 都必须在声明文件里登记；
#   2. 声明里的每个条目都必须真的存在；
#   3. 每个条目的实际字节不超过声明上限；
#   4. 形态与像素尺寸符合声明。单档形态还要求恰好一张 .png、Contents.json 不带 scale 槽位，
#      并且 lossy 标记与声明的形态一致（该有的必须有，不该有的不许有）。
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
catalog="$repo_root/BrowseCraft/Assets.xcassets"
declaration="$repo_root/scripts/bundled-image-asset-budgets.txt"

if [ ! -d "$catalog" ]; then
    echo "error: 找不到资产目录 $catalog"
    exit 1
fi
if [ ! -f "$declaration" ]; then
    echo "error: 找不到声明文件 $declaration"
    exit 1
fi

failures=0
fail() {
    echo "error: $1"
    failures=$((failures + 1))
}

declared_names=""
while read -r name budget size form; do
    case "$name" in ''|\#*) continue ;; esac
    declared_names="$declared_names $name"

    dir=""
    for candidate in "$catalog/$name.imageset" "$catalog/$name.appiconset"; do
        if [ -d "$candidate" ]; then
            dir="$candidate"
        fi
    done
    if [ -z "$dir" ]; then
        fail "声明了 $name，但资产目录里没有对应的 imageset/appiconset"
        continue
    fi

    files=""
    while IFS= read -r file; do
        files="$files$file"$'\n'
    done < <(find "$dir" -type f ! -name '*.json' ! -name '.DS_Store' | sort)
    if [ -z "${files//[$'\n']/}" ]; then
        fail "$name 里没有任何图片文件"
        continue
    fi

    bytes=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        bytes=$((bytes + $(stat -f%z "$file")))
    done <<< "$files"
    if [ "$bytes" -gt "$budget" ]; then
        fail "$name 实际 $bytes 字节，超过声明上限 $budget。要么把图压回去，要么在 $(basename "$declaration") 里连同理由改上限"
    fi

    count=$(printf '%s' "$files" | grep -c . || true)
    case "$form" in
    single-scale-png|single-scale-lossy-png)
        if [ "$count" -ne 1 ]; then
            fail "$name 声明为 $form，却有 $count 个图片文件；单档资产只应有一张"
        fi
        if printf '%s' "$files" | grep -qv '\.png$'; then
            fail "$name 声明为 $form，却含非 .png 文件"
        fi
        if grep -q '"scale"' "$dir/Contents.json"; then
            fail "$name 的 Contents.json 仍带 scale 槽位；单档资产不应声明 scale"
        fi
        if grep -q '"compression-type" *: *"lossy"' "$dir/Contents.json"; then
            declared_lossy=yes
        else
            declared_lossy=no
        fi
        if [ "$form" = "single-scale-lossy-png" ] && [ "$declared_lossy" = "no" ]; then
            fail "$name 声明为 single-scale-lossy-png，Contents.json 却没有 \"compression-type\": \"lossy\"；少了它 Assets.car 会变大"
        fi
        if [ "$form" = "single-scale-png" ] && [ "$declared_lossy" = "yes" ]; then
            fail "$name 声明为 single-scale-png（按接近原生分辨率渲染，不接受有损），Contents.json 却标了 lossy"
        fi
        ;;
    esac

    first_file=$(printf '%s' "$files" | head -1)
    actual_size=$(sips -g pixelWidth -g pixelHeight "$first_file" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')
    if [ "$actual_size" != "$size" ]; then
        fail "$name 的像素尺寸是 $actual_size，声明为 $size"
    fi
done < "$declaration"

while IFS= read -r dir; do
    name=$(basename "$dir")
    name="${name%.imageset}"
    name="${name%.appiconset}"
    case " $declared_names " in
        *" $name "*) ;;
        *) fail "$name 没有在 $(basename "$declaration") 里登记。新增位图资产必须显式声明字节上限、像素尺寸与形态" ;;
    esac
done < <(find "$catalog" -type d \( -name '*.imageset' -o -name '*.appiconset' \) | sort)

if [ "$failures" -gt 0 ]; then
    echo "随包位图资产闸门失败：$failures 处"
    exit 1
fi

exit 0
