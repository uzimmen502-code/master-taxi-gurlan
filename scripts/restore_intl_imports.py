# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / "lib"
imp = "import 'package:intl/intl.dart';\n"
fixed = []
for p in root.rglob("*.dart"):
    t = p.read_text(encoding="utf-8")
    needs = "DateFormat" in t or "NumberFormat" in t
    has = "package:intl/intl.dart" in t
    if needs and not has:
        m = re.search(r"^import .+;\n", t, re.M)
        if m:
            t = t[: m.end()] + imp + t[m.end() :]
            p.write_text(t, encoding="utf-8")
            fixed.append(str(p.relative_to(root)))
print(len(fixed))
for f in fixed:
    print(f)
