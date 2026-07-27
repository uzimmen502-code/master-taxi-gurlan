# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
files = [
    "lib/features/analytics/widgets/kpi_card.dart",
    "lib/features/analytics/widgets/top_list.dart",
    "lib/features/analytics/tabs/finance_tab.dart",
    "lib/features/analytics/tabs/dashboard_tab.dart",
    "lib/features/admin_web/screens/payout_management_screen.dart",
]
for rel in files:
    p = root / rel
    t = p.read_text(encoding="utf-8")
    o = t
    t = re.sub(
        r"\n\s*static final _fmt = NumberFormat\.decimalPattern\('en'\);\n",
        "\n",
        t,
    )
    t = re.sub(
        r"\n\s*static final _fmt = intl\.NumberFormat\.decimalPattern\('en'\);\n",
        "\n",
        t,
    )
    t = re.sub(
        r"\n\s*final fmt = NumberFormat\.decimalPattern\('en'\);\n",
        "\n",
        t,
    )
    if "NumberFormat" not in t and "DateFormat" not in t:
        t = re.sub(r"import 'package:intl/intl.dart';\n", "", t)
        t = re.sub(r"import 'package:intl/intl.dart' as intl;\n", "", t)
    if t != o:
        p.write_text(t, encoding="utf-8")
        print("cleaned", rel)
