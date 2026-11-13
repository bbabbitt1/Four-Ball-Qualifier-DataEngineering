"""Find qualifier entrants with pro tour experience (pgatour.com) and write a review seed for dbt.

    python pro.py                 # 2027 entrants
    python pro.py --years 2026 2027

Name-matches entrants against every pgatour.com tour directory, pulls career starts per tour for each match,
and writes dbt_fourball/seeds/pro_experience.csv. Matches are by name only, so each row needs review:
set is_match = y (same person) or n. Only y rows count. Re-runs keep existing is_match answers.
"""
import argparse, csv, glob, re, time
from pathlib import Path

import requests

ROOT = Path(__file__).parent
SEED = ROOT / "dbt_fourball" / "seeds" / "pro_experience.csv"
# Public key the pgatour.com site itself sends with every request.
HTTP = requests.Session()
HTTP.headers.update({"x-api-key": "da2-gsrx5bibzbb4njvhl7t37wqyl4", "x-pgat-platform": "web",
                     "user-agent": "Mozilla/5.0", "referer": "https://www.pgatour.com/"})
# R PGA Tour, H Korn Ferry, Y PGA Tour Americas, C PGA Tour Canada (pre-2024), M PGA Tour Latinoamerica (pre-2024)
TOURS = ["R", "H", "Y", "C", "M"]
COLS = ["player_name", "entrant_from", "pga_player_id", "country", "birthplace", "college", "turned_pro",
        "pga_tour_starts", "korn_ferry_starts", "americas_starts", "is_match"]


def key(name): return re.sub(r"\s+", " ", name).strip().lower()


def directory():
    q = "query($t: TourCode!){ playerDirectory(tourCode:$t){ players { id firstName lastName country } } }"
    out = {}
    for t in TOURS:
        r = HTTP.post("https://orchestrator.pgatour.com/graphql", json={"query": q, "variables": {"t": t}}, timeout=60)
        r.raise_for_status()
        for p in r.json()["data"]["playerDirectory"]["players"]:
            out.setdefault(key(f"{p['firstName']} {p['lastName']}"), {})[p["id"]] = p["country"]
    return out


def entrants(years):
    """Same split as stg_scores: 'A | B', 'A + B', 'A / B', 'A - B' in player1 when player2 is empty."""
    names = {}   # name -> hometowns seen in the score files (for review)
    for y in years:
        for f in glob.glob(str(ROOT / f"data/bronze/scores/{y}-fourball/*.csv")):
            for r in csv.DictReader(open(f, encoding="utf8")):
                for v, frm in ((r.get("player1"), r.get("player1_from")), (r.get("player2"), r.get("player2_from"))):
                    for n in re.split(r"\s*[|+/]\s*|\s+-\s+", v or ""):
                        if n.strip(): names.setdefault(key(n), set()).update({frm.strip()} if frm and frm.strip() else set())
    return names


def career(pid):
    """Starts per tour from the profile's Career tab, plus summary bio fields for review."""
    get = lambda path: HTTP.get(f"https://data-api.pgatour.com/player/profiles/{pid}{path}", timeout=60).json()
    starts = {}
    for tour in get("/career").get("career", []):
        for block in tour.get("careerData", []):
            for stat in block.get("stats", []):
                if stat.get("title") == "Starts":
                    starts[tour["tourCode"]] = int(re.sub(r"\D", "", stat["data"][0]["data"]) or 0)
    s = get("").get("summaryData", {}).get("summaryData", {}) or {}
    return starts, s


def main(years):
    pros, names = directory(), entrants(years)
    old = {(r["player_name"], r["pga_player_id"]): r["is_match"] for r in csv.DictReader(open(SEED, encoding="utf8"))} if SEED.exists() else {}
    rows = []
    for name in sorted(n for n in names if n in pros):
        for pid, country in pros[name].items():
            starts, s = career(pid)
            display = " ".join(w.capitalize() for w in name.split())
            rows.append([display, "; ".join(sorted(names[name])), pid, country, s.get("birthplace", ""), s.get("college", ""), s.get("turnedPro", ""),
                         starts.get("R", 0), starts.get("H", 0), starts.get("Y", 0) + starts.get("C", 0) + starts.get("M", 0),
                         old.get((display, pid), "")])
            time.sleep(0.5)
    SEED.parent.mkdir(parents=True, exist_ok=True)
    with open(SEED, "w", newline="", encoding="utf8") as f:
        csv.writer(f).writerows([COLS, *rows])
    print(f"{len(rows)} candidate(s) -> {SEED}; {sum(1 for r in rows if not r[-1])} need review")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", nargs="+", type=int, default=[2027])
    main(ap.parse_args().years)
