# -*- coding: utf-8 -*-
"""Normalize currency words in lang JSON to Cyrillic сўм."""
from pathlib import Path
import re

lang = Path(__file__).resolve().parents[1] / "assets" / "lang"
for name in ("uz_Cyrl.json", "uz_Latn.json", "ru.json"):
    p = lang / name
    t = p.read_text(encoding="utf-8")
    orig = t
    # so'm variants in JSON strings
    t = t.replace("so'm", "сўм")
    t = t.replace("so‘m", "сўм")
    # Russian сум as whole word currency (avoid accidental Latin)
    t = re.sub(r"(?<![А-Яа-яЁёЎўҚқҒғҲҳ])сум(?![А-Яа-яЁёЎўҚқҒғҲҳ])", "сўм", t)
    if t != orig:
        p.write_text(t, encoding="utf-8")
        print("updated", name)
    else:
        print("unchanged", name)
