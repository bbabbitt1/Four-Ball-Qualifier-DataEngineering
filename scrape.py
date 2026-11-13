"""Scrape U.S. Amateur Four-Ball qualifying results into bronze CSVs.

    python scrape.py                      # all years the USGA API serves (2025+)
    python scrape.py --years 2027         # just the in-progress season
    python scrape.py --years 2026 --force # re-scrape sites already marked scraped

See RUNBOOK.md for the data layout and inventory statuses.
"""
import argparse, csv, json, os, re, time
from datetime import date, datetime
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from playwright.sync_api import sync_playwright

load_dotenv(Path(__file__).parent / ".env")

DATA = Path(__file__).parent / "data"
BRONZE, INVENTORY = DATA / "bronze", DATA / "inventory"
HOLES_CSV = BRONZE / "dim_golf_course_holes.csv"
USGA_ORIGIN = "https://championships.usga.org/usamateurfourball.html"
USGA_API = "https://ace-api.usga.org/scoring/v1/qualifying-page.json?championship=us4ball&championship-year={}"
USGA_KEY = os.getenv("USGA_KEY")  # from .env; the public data-api-key the USGA page itself sends
GG = "https://www.golfgenius.com"
HTTP = requests.Session()
HTTP.headers["User-Agent"] = "Mozilla/5.0"


def partition(year): return f"{year}-fourball"
def course_id(name, state): return re.sub(r"[^a-z0-9]+", "-", f"{name} {state}".lower()).strip("-")


def platform(url):
    if not url: return None
    return "golfgenius" if "golfgenius.com" in url else "bluegolf" if "bluegolf.com" in url else "other"


def fetch_usga(years, browser):
    """USGA's qualifying JSON sits behind Akamai, so call it from a real (headed) Chrome page."""
    pg = browser.new_page()
    pg.goto(USGA_ORIGIN, wait_until="domcontentloaded", timeout=90000)
    out = {}
    for y in years:
        status, text = pg.evaluate("""async ([u, k]) => { const r = await fetch(u, {headers: {'Ocp-Apim-Subscription-Key': k}});
                                       return [r.status, await r.text()]; }""", [USGA_API.format(y), USGA_KEY])
        if status != 200:
            print(f"{y}: USGA API returned {status}, skipping"); continue
        out[y] = json.loads(text)
        (BRONZE / "usga_api").mkdir(parents=True, exist_ok=True)
        (BRONZE / "usga_api" / f"{partition(y)}.json").write_text(text, encoding="utf8")
    pg.close()
    return out


def gg_widget(url, browser):
    """Golf Genius 'pages' build the results iframe client-side. Returns (page title, results iframe html)."""
    pg = browser.new_page()
    pg.goto(url if url.startswith("http") else f"https://{url}", wait_until="networkidle", timeout=90000)
    widgets = [f.url for f in pg.frames if "tournament_results" in f.url]
    results_nav = pg.locator("a[href*='/pages/']", has_text=re.compile("results", re.I))
    if not widgets and results_nav.count():  # USGA sometimes links the event home page; hop to its Results tab
        pg.goto(urljoin(pg.url, results_nav.first.get_attribute("href")), wait_until="networkidle", timeout=90000)
        widgets = [f.url for f in pg.frames if "tournament_results" in f.url]
    title = pg.title()
    pg.close()
    if not widgets: raise ValueError("no tournament_results widget on page")
    return title, HTTP.get(widgets[0], timeout=60).text


def gg_tournament_urls(url, browser):
    soup = BeautifulSoup(gg_widget(url, browser)[1], "lxml")
    links = [a for a in soup.select("a[href*='v2tournaments']") if "women" not in a.get_text().lower()]
    return [GG + a["href"] if a["href"].startswith("/") else a["href"] for a in links]


def parse_gg(html):
    """One row per side. Keeps the leaderboard's own columns plus the two players split out."""
    soup = BeautifulSoup(html, "lxml")
    headers = [th.get_text(strip=True) for th in soup.select("table thead th")] or \
              [td.get_text(strip=True) for td in soup.select_one("table tr").find_all(["td", "th"])]
    rows = []
    for tr in soup.select("tr.aggregate-row"):
        row = {h or f"col{i}": td.get_text(" ", strip=True) for i, (h, td) in enumerate(zip(headers, tr.find_all("td", recursive=False)))}
        names = [a.get_text(strip=True) for a in tr.select(".team a")] or [tr.get("data-aggregate-name", "")]
        froms = [d.get_text(strip=True) for d in tr.select(".team .affiliation")]
        row["Players"] = tr.get("data-aggregate-name", row.get("Players", ""))
        for i, n in enumerate(names[:2], 1):
            row[f"player{i}"], row[f"player{i}_from"] = n, froms[i - 1] if i <= len(froms) else ""
        row["gg_aggregate_id"] = tr.get("data-aggregate-id", "")
        rows.append(row)
    return rows


def gg_hole_pars(aggregate_ids):
    """Par per hole = gross - to-par on a side's scorecard; try a few sides until all 18 holes resolve."""
    pars = {}
    for aid in aggregate_ids[:5]:
        js = HTTP.get(f"{GG}/tournaments2/details/{aid}", headers={"X-Requested-With": "XMLHttpRequest", "Accept": "text/javascript"}, timeout=60).text
        m = re.search(r'toggleDetails\("\d+",\s*"(.*)"\)', js, re.S)
        if not m: continue
        html = m.group(1)
        for esc, ch in (("\\n", "\n"), ("\\'", "'"), ('\\"', '"'), ("\\/", "/")): html = html.replace(esc, ch)
        soup = BeautifulSoup(html, "lxml")
        table = {r[0]: r[1:] for r in ([c.get_text(strip=True) for c in tr.find_all("td")] for tr in soup.select("table tr")) if r}
        holes, gross, to_par = table.get(""), table.get("Gross Score"), table.get("To Par (gross)")
        if not (holes and gross and to_par): continue
        for h, g, t in zip(holes, gross, to_par):
            if h.isdigit() and g.lstrip("-").isdigit() and t.lstrip("-").isdigit():
                pars[int(h)] = int(g) - int(t)
        if len(pars) == 18: break
        time.sleep(0.3)
    return pars


def write_csv(path, rows, fields=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = fields or list(dict.fromkeys(k for r in rows for k in r))
    with path.open("w", newline="", encoding="utf8") as f:
        w = csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(rows)


def bg_html(url, browser):
    """BlueGolf sits behind an AWS WAF CAPTCHA. A human solves it in the open Chrome window (we never automate that);
    the cookie persists in .browser-profile so later pages load straight through."""
    pg = browser.new_page()
    pg.goto(url, timeout=90000)
    if "Human Verification" in pg.title(): print("  >> solve the BlueGolf CAPTCHA in the Chrome window (waiting up to 10 min)")
    for _ in range(120):
        if "Human Verification" not in pg.title(): break
        time.sleep(5)
    pg.wait_for_load_state("networkidle")
    title, html = pg.title(), pg.content()
    pg.close()
    time.sleep(3)  # polite pacing: these are human-verified sessions
    if "Human Verification" in title: raise ValueError("BlueGolf CAPTCHA not solved")
    return html


def parse_bg(html):
    """One row per side from the BlueGolf leaderboard; `section` = QUALIFIERS / ALTERNATES / DID NOT QUALIFY / DID NOT FINISH."""
    table = BeautifulSoup(html, "lxml").select_one("table.scores")
    if not table: return []
    headers = [th.get_text(" ", strip=True) for th in table.select("thead th")]
    rows, section = [], ""
    for tr in table.select("tbody tr"):
        if "divider" in (tr.get("class") or []): section = tr.get_text(" ", strip=True); continue
        if not tr.select_one("td.pos"): continue
        tds = tr.find_all("td", recursive=False)
        row = {h: td.get_text(" ", strip=True) for h, td in zip(headers, tds) if h and not h.startswith("Follow")}
        row["Team"] = tds[1].get("data-sort-value", row.get("Team", ""))
        names = [x.get_text(strip=True) for x in tr.select("td.name a span.d-md-inline")]
        froms = [x.get_text(" ", strip=True).replace(" ", " ") for x in tr.select("td.name small")]
        for i, n in enumerate(names[:2], 1):
            row[f"player{i}"], row[f"player{i}_from"] = n, froms[i - 1] if i <= len(froms) else ""
        row["section"], row["bg_scorecard"] = section, tr.select_one("td.name a")["href"]
        rows.append(row)
    return rows


def bg_holes(html):
    """Hole, yardage, stroke index and par from the first scorecard table (cols 1-9 front, 11-19 back)."""
    table = BeautifulSoup(html, "lxml").select_one("table.bg-tbl-scorecard")
    if not table: return []
    t = {r[0]: r for r in ([c.get_text(strip=True) for c in tr.find_all(["td", "th"])] for tr in table.find_all("tr")) if r}
    idx = list(range(1, 10)) + list(range(11, 20))
    get = lambda k, i: t[k][i] if k in t and len(t[k]) > i else ""
    return [{"hole": h, "par": get("Par", i), "yardage": get("Yards", i), "handicap": get("Handicap", i) or get("Hcp", i)}
            for h, i in enumerate(idx, 1)]


def upsert_holes(cid, holes):
    existing = list(csv.DictReader(HOLES_CSV.open(encoding="utf8"))) if HOLES_CSV.exists() else []
    if any(r["course_id"] == cid for r in existing): return
    # ponytail: holes come from the qualifier's tees (assumed back tees); Golf Genius cards have no yardage/handicap
    existing += [{"course_id": cid, "tees": "back", **h} for h in holes]
    write_csv(HOLES_CSV, existing, ["course_id", "tees", "hole", "par", "yardage", "handicap"])


def scrape_site(year, site, browser):
    url, rows, holes = site["scoring_url"] if site["scoring_url"].startswith("http") else f"https://{site['scoring_url']}", [], []
    if site["platform"] == "bluegolf":
        rows = parse_bg(bg_html(url, browser))
        if not rows: return "source_gone", 0, None  # BlueGolf posts same day; an empty page = association left BlueGolf / page removed
        if rows: holes = bg_holes(bg_html(urljoin(url, rows[0]["bg_scorecard"]), browser))
    else:
        for t_url in gg_tournament_urls(url, browser):
            rows += parse_gg(HTTP.get(t_url, timeout=60).text)
            time.sleep(0.3)
        if rows: holes = [{"hole": h, "par": p, "yardage": "", "handicap": ""} for h, p in sorted(gg_hole_pars([r["gg_aggregate_id"] for r in rows]).items())]
    if not rows: return "no_rows_yet", 0, None
    for r in rows:
        r.update(qualifier_date=site["qualifier_date"], course_id=site["course_id"], site_name=site["site_name"], source_url=site["scoring_url"])
    out = BRONZE / "scores" / partition(year) / f"{site['qualifier_date']}_{site['course_id']}.csv"
    write_csv(out, rows)
    if len(holes) == 18 and all(h["par"] for h in holes): upsert_holes(site["course_id"], holes)
    return "scraped", len(rows), out.relative_to(DATA.parent).as_posix()


def build_inventory(year, payload, previous):
    prev = {(s["qualifier_date"], s["course_id"]): s for s in previous.get("sites", [])}
    sites = []
    for s in payload["sites"]:
        url = (s.get("scoringUrl") or "").strip()
        site = {"qualifier_date": s["date"], "site_name": s["name"], "city": s.get("city"), "state": s.get("state"),
                "course_id": course_id(s["name"], s.get("state", "")), "scoring_url": url, "platform": platform(url),
                "usga_field_size_players": s.get("qualifiersCount"), "status": None, "rows": 0, "csv": None}
        old = prev.get((site["qualifier_date"], site["course_id"]), {})
        site.update({k: old[k] for k in ("status", "rows", "csv") if k in old})
        sites.append(site)
    return {"championship_year": year, "partition": partition(year), "sites": sorted(sites, key=lambda s: s["qualifier_date"])}


def save_inventory(inv, path):
    scraped = [s for s in inv["sites"] if s["status"] == "scraped"]
    inv.update(updated_at=datetime.now().isoformat(timespec="seconds"),
               latest_scraped_date=max((s["qualifier_date"] for s in scraped), default=None),
               status_counts={k: sum(s["status"] == k for s in inv["sites"]) for k in sorted({str(s["status"]) for s in inv["sites"]})})
    path.write_text(json.dumps(inv, indent=2), encoding="utf8")


def run(years, force):
    INVENTORY.mkdir(parents=True, exist_ok=True)
    today = date.today().isoformat()
    with sync_playwright() as p:
        # headed Chrome: headless gets Akamai 'Access Denied'. Persistent profile keeps the BlueGolf CAPTCHA cookie between runs.
        browser = p.chromium.launch_persistent_context(str(DATA.parent / ".browser-profile"), channel="chrome", headless=False)
        payloads = fetch_usga(years, browser)
        for y in years:  # USGA API only serves 2025+; older seasons come from hand-built seeds (see seed.py)
            seed = DATA / "seeds" / f"{partition(y)}.json"
            if y not in payloads and seed.exists(): payloads[y] = json.loads(seed.read_text(encoding="utf8"))
        for year, payload in sorted(payloads.items()):
            inv_path = INVENTORY / f"{partition(year)}.json"
            inv = build_inventory(year, payload, json.loads(inv_path.read_text()) if inv_path.exists() else {})
            for site in inv["sites"]:
                done = site["status"] == "source_gone" or (site["status"] == "scraped" and site["csv"] and (DATA.parent / site["csv"]).exists())
                if done and not force: continue
                if site["qualifier_date"] > today: site["status"] = "upcoming"
                elif not site["scoring_url"]: site["status"] = "no_results_link"
                elif site["platform"] == "other": site["status"] = "manual"
                else:
                    try: site["status"], site["rows"], site["csv"] = scrape_site(year, site, browser)
                    except Exception as e: site["status"] = f"error: {str(e)[:120]}"
                print(year, site["qualifier_date"], site["site_name"][:40], "->", site["status"], site["rows"])
                save_inventory(inv, inv_path)  # after every site, so an interrupted run keeps its progress
            save_inventory(inv, inv_path)
        browser.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--years", type=int, nargs="+", default=[2022, 2023, 2024, 2025, 2026, 2027])
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    run(a.years, a.force)
