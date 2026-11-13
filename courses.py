"""Build dim_golf_course.csv for every course in data/inventory: address + lat/long (OSM Nominatim)
and back-tee par / rating / slope (USGA Course Rating Database). Incremental: existing course_ids are kept.

    python courses.py
"""
import csv, difflib, json, re, time

import requests
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

from scrape import BRONZE, INVENTORY, write_csv

DIM_CSV = BRONZE / "dim_golf_course.csv"
FIELDS = ["course_id", "course_name", "city", "state", "address", "lat", "long", "tees", "par", "rating", "slope", "ncrdb_course_id", "ncrdb_name", "ncrdb_match_score", "geo_precision"]
NOMINATIM = "https://nominatim.openstreetmap.org/search"
UA = {"User-Agent": "fourball-qualifier-de/0.1 (personal data project)"}
GENERIC = r"\b(the|country|golf|club|course|cc|gc|g\.c\.|c\.c\.|and|&|at|of|resort|links|championship)\b"


def geocode(name, city, state):
    tries = [(f"{name}, {city}, {state}", "course"), (f"{re.sub(r'\(.*?\)', '', name).strip()}, {city}, {state}", "course"),
             (f"{city}, {state}", "city")]  # ponytail: city centroid fallback (~miles off); fine for a US map, flagged in geo_precision
    for q, precision in tries:
        r = requests.get(NOMINATIM, params={"q": q, "format": "json", "countrycodes": "us", "limit": 1}, headers=UA, timeout=30).json()
        time.sleep(1.1)  # Nominatim policy: max 1 req/s
        if r: return r[0]["display_name"], r[0]["lat"], r[0]["lon"], precision
    return "", "", "", ""


def ncrdb_back_tees(pg, name, city, state):
    """Search NCRDB by the distinctive part of the name, pick the closest course, return its highest-rated men's tee."""
    key = re.sub(r"\s+", " ", re.sub(GENERIC, " ", re.sub(r"\(.*?\)", "", name.lower()))).strip() or name
    pg.goto("https://ncrdb.usga.org/", wait_until="domcontentloaded", timeout=90000)
    pg.fill("#clubName", key.split(" ")[0] if len(key) > 25 else key)
    pg.select_option("#ddlStates", value=f"US-{state}")
    with pg.expect_response(lambda r: "LoadCourses" in r.url, timeout=60000) as resp:
        pg.click("#myButton")
    courses = [c for c in resp.value.json() if not re.search(r"par 3|executive|9 hole", c["fullName"], re.I)]
    if not courses: return None
    score = lambda c: difflib.SequenceMatcher(None, name.lower(), c["fullName"].lower()).ratio()
    best = max(courses, key=lambda c: score(c) + 0.3 * ((c["city"] or "").lower() == (city or "").lower()))  # same city wins ties
    pg.goto(f"https://ncrdb.usga.org/courseTeeInfo?CourseID={best['courseID']}", wait_until="domcontentloaded", timeout=90000)
    rows = [[td.get_text(strip=True) for td in tr.find_all("td")] for tr in BeautifulSoup(pg.content(), "lxml").select("table tr")]
    men = [r for r in rows if len(r) > 5 and r[1] == "M" and re.fullmatch(r"[\d.]+", r[3]) and float(r[3]) > 50 and r[5].isdigit()]  # >50 drops 9-hole ratings
    if not men: return None
    tee = max(men, key=lambda r: float(r[3]))
    return {"tees": tee[0], "par": tee[2], "rating": tee[3], "slope": tee[5], "ncrdb_course_id": best["courseID"], "ncrdb_name": best["fullName"],
            "ncrdb_match_score": round(score(best), 2)}  # low score = check the match by hand


def main():
    existing = list(csv.DictReader(DIM_CSV.open(encoding="utf8"))) if DIM_CSV.exists() else []
    have = {r["course_id"] for r in existing}
    todo = {}
    for f in sorted(INVENTORY.glob("*.json")):
        for s in json.loads(f.read_text(encoding="utf8"))["sites"]:
            if s["course_id"] not in have and s["state"]: todo[s["course_id"]] = s
    print(f"{len(todo)} new courses")
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=False)  # NCRDB is behind the same Akamai as usga.org
        pg = browser.new_page()
        for cid, s in todo.items():
            row = {"course_id": cid, "course_name": s["site_name"], "city": s["city"], "state": s["state"]}
            row["address"], row["lat"], row["long"], row["geo_precision"] = geocode(s["site_name"], s["city"], s["state"])
            try: row.update(ncrdb_back_tees(pg, s["site_name"], s["city"], s["state"]) or {})
            except Exception as e: print("  ncrdb error:", str(e)[:100])
            print(cid, "|", row.get("ncrdb_name"), row.get("rating"), row.get("slope"), "| geo:", bool(row["lat"]))
            existing.append(row)
            write_csv(DIM_CSV, existing, FIELDS)  # write as we go so a crash keeps progress
        browser.close()


if __name__ == "__main__":
    main()
