from datetime import date

from wagr import wagr_week

assert wagr_week(date(2026, 11, 11)) == 202645   # Wed release day -> that release
assert wagr_week(date(2026, 11, 10)) == 202644   # Tue -> previous Wed's release
assert wagr_week(date(2026, 11, 15)) == 202645   # Sun -> same week's release
assert wagr_week(date(2023, 8, 16)) == 202332
assert wagr_week(date(2026, 1, 5)) == 202552     # year boundary: Mon 2026-01-05 -> Wed 2025-12-31 release
print("ok")
