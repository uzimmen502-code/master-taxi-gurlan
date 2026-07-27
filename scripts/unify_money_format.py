# -*- coding: utf-8 -*-
"""One-shot: unify money display toward formatPrice / formatMoney + сўм."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
LANG = Path(__file__).resolve().parents[1] / "assets" / "lang"

SKIP_DIRS = {"oil_change"}  # km uses formatPrice — still OK to change so'm there if any


def ensure_formatters_import(text: str) -> str:
    if "core/utils/formatters.dart" in text or "core\\utils\\formatters.dart" in text:
        return text
    if "formatPrice(" not in text and "formatMoney(" not in text:
        return text
    # Guess relative import depth from package imports style
    m = re.search(r"^import 'package:ava_gurlan/", text, re.M)
    if m:
        # Prefer package import
        if "package:ava_gurlan/core/utils/formatters.dart" not in text:
            text = text.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/material.dart';\n"
                "import 'package:ava_gurlan/core/utils/formatters.dart';",
                1,
            )
        return text
    # Relative: count features depth — insert after first import
    if "import '../../../core/utils/formatters.dart';" in text:
        return text
    if "import '../../core/utils/formatters.dart';" in text:
        return text
    if "import '../../../../core/utils/formatters.dart';" in text:
        return text
    # Heuristic by path later — caller passes hint
    return text


def patch_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text

    # Currency word variants → сўм (display + labels)
    text = text.replace("so\\'m", "сўм")
    text = text.replace('so\'m', "сўм")
    text = text.replace("so'm", "сўм")
    text = text.replace("so‘m", "сўм")
    text = text.replace(" so'm", " сўм")

    # NumberFormat('#,###').format(expr) → formatPrice(expr)
    text = re.sub(
        r"NumberFormat\('#,###'\)\.format\(([^)]+)\)",
        r"formatPrice(\1)",
        text,
    )

    # Common money NumberFormat locals
    text = re.sub(
        r"NumberFormat\.decimalPattern\('en'\)\.format\(([^)]+)\)",
        r"formatPrice(\1)",
        text,
    )
    text = re.sub(
        r"NumberFormat\.decimalPattern\('uz'\)\.format\(([^)]+)\)",
        r"formatPrice(\1)",
        text,
    )

    # _money.format(x) / money.format(x) / fmt.format(x) when used with сўм nearby
    # Safer: only _money.format and money.format (known money formatters)
    text = re.sub(r"\b_money\.format\(([^)]+)\)", r"formatPrice(\1)", text)
    text = re.sub(r"\bmoney\.format\(([^)]+)\)", r"formatPrice(\1)", text)
    text = re.sub(r"\b_fmt\.format\(([^)]+)\)", r"formatPrice(\1)", text)
    text = re.sub(r"\bfmt\.format\(([^)]+)\)", r"formatPrice(\1)", text)

    # Standalone `${formatPrice(x)} сўм` → formatMoney(x)
    text = re.sub(
        r"\$\{formatPrice\(([^)]+)\)\} сўм",
        r"${formatMoney(\1)}",
        text,
    )
    # '…' + formatPrice(x) + ' сўм' patterns less common

    # Raw ad/item price displays
    replacements = [
        ("'${ad.price} сўм'", "formatMoney(ad.price)"),
        ('"${ad.price} сўм"', "formatMoney(ad.price)"),
        ("'${item.price} сўм'", "formatMoney(item.price)"),
        ("'${r.price} сўм'", "formatMoney(r.price)"),
        (
            "'${ad.price} сўм · ${ad.sellerName} · ${ad.phone}'",
            "('${formatMoney(ad.price)} · ${ad.sellerName} · ${ad.phone}')",
        ),
    ]
    for a, b in replacements:
        text = text.replace(a, b)

    # Multiline market moderation style
    text = text.replace(
        "'${ad.price} сўм · ${ad.sellerName} · ${ad.phone}'",
        "'${formatMoney(ad.price)} · ${ad.sellerName} · ${ad.phone}'",
    )

    if text == orig:
        return False

    # Ensure formatters import when formatPrice/formatMoney used
    if ("formatPrice(" in text or "formatMoney(" in text) and "formatters.dart" not in text:
        rel = path.relative_to(ROOT).as_posix()
        depth = rel.count("/")
        prefix = "../" * depth
        imp = f"import '{prefix}core/utils/formatters.dart';\n"
        # After first import block line
        m = re.search(r"^import .+;\n", text, re.M)
        if m:
            text = text[: m.end()] + imp + text[m.end() :]
        else:
            text = imp + text

    # Drop unused intl if no NumberFormat left
    if "NumberFormat" not in text and "package:intl/intl.dart" in text:
        text = re.sub(r"import 'package:intl/intl.dart';\n", "", text)

    # Drop unused static _money fields if no longer referenced
    text = re.sub(
        r"\n\s*static final _money = NumberFormat\.decimalPattern\('en'\);\n",
        "\n",
        text,
    )

    path.write_text(text, encoding="utf-8")
    return True


def patch_langs() -> None:
    for name in ("uz_Cyrl.json", "uz_Latn.json", "ru.json"):
        p = LANG / name
        t = p.read_text(encoding="utf-8")
        t2 = t
        t2 = re.sub(r'"currency_sum"\s*:\s*"[^"]*"', '"currency_sum": "сўм"', t2)
        t2 = re.sub(r'"sum"\s*:\s*"[^"]*"', '"sum": "сўм"', t2)
        if t2 != t:
            p.write_text(t2, encoding="utf-8")
            print("lang", name)


def main() -> None:
    patch_langs()
    changed = []
    for path in ROOT.rglob("*.dart"):
        if patch_file(path):
            changed.append(str(path.relative_to(ROOT)))
    print(f"changed {len(changed)} dart files")
    for c in sorted(changed)[:80]:
        print(" ", c)
    if len(changed) > 80:
        print(f"  ... +{len(changed) - 80} more")


if __name__ == "__main__":
    main()
