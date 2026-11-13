"""Download the men's WAGR ranking in effect on each qualifier date into bronze CSVs.

    python wagr.py    # fetches every needed week not already in data/bronze/wagr/

One file per ranking week: data/bronze/wagr/{YYYYWW}.csv. Weeks never change once published, so files are skipped if present.
"""
import csv, json, time
from datetime import date, timedelta
from pathlib import Path

import requests

DATA = Path(__file__).parent / "data"
OUT = DATA / "bronze" / "wagr"
API = ("https://worldgolfranking2021api.wagr.com/api/wagr/rankings/getRankings?rankingsType=0&pageNumber=1&pageSize=10000"
       "&week={}&year={}&region=0&countries=&playerName=&county=&playerIDs=&age=&asOfDate=&includeFirstStats=false"
       "&sortString=&isRangeUnder=false&isRangeOver=false&isThisAgeOnly=false")
COLS = ["wagr_week", "player_id", "rank", "first_name", "last_name", "full_name", "nationality", "points_avg"]


def wagr_week(d):
    """Ranking in effect on date d. WAGR publishes Wednesdays, labelled one ISO week back (Wed 2026-11-11 = 202645),
    so the release in effect is the ISO week of d - 9 days. Keep in sync with stg_wagr / agg_qualifier_field_strength."""
    y, w, _ = (d - timedelta(days=9)).isocalendar()
    return y * 100 + w


def needed_weeks():
    dates = {date.fromisoformat(s["qualifier_date"]) for f in (DATA / "inventory").glob("*-fourball.json")
             for s in json.loads(f.read_text(encoding="utf8"))["sites"] if s.get("qualifier_date")}
    return sorted({wagr_week(d) for d in dates if d <= date.today()})


def fetch(week):
    r = requests.get(API.format(week % 100, week // 100), headers={"User-Agent": "Mozilla/5.0"}, timeout=60)
    r.raise_for_status()
    body = r.json()
    hdrs = {h["key"]: h["value"][0] for h in body["rankingsTableSettings"]["headers"]}
    assert int(hdrs["X-WagrWeekFilter"]) == week, f"asked for {week}, got {hdrs['X-WagrWeekFilter']}"
    return [[week, p["playerId"], p["rankThisWeek"], p["firstName"], p["lastName"], p["playerFullName"],
             p["nationality"], p["pointsAverage"]] for p in body["rankingLandingModels"]]


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    todo = [w for w in needed_weeks() if not (OUT / f"{w}.csv").exists()]
    print(f"{len(todo)} week(s) to fetch")
    for w in todo:
        rows = fetch(w)
        if not rows:
            print(f"{w}: no rows, skipping"); continue
        with open(OUT / f"{w}.csv", "w", newline="", encoding="utf8") as f:
            csv.writer(f).writerows([COLS, *rows])
        print(f"{w}: {len(rows)} players")
        time.sleep(1)
