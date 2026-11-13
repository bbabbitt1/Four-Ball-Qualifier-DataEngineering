"""Add qualifier results URLs to data/seeds/{year}-fourball.json for seasons the USGA API no longer serves (2022-2024).

    python seed.py 2023 https://www.golfgenius.com/pages/3799625 https://iga.bluegolf.com/...

Golf Genius URLs get name/date filled from the page; everything else is added with blanks to fill by hand.
Review the file afterwards: city/state are guessed from the event title.
"""
import json, re, sys
from datetime import datetime

from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright

from scrape import DATA, gg_widget, partition, platform

STATES = {"Ala": "AL", "Ariz": "AZ", "Ark": "AR", "Calif": "CA", "Colo": "CO", "Conn": "CT", "Del": "DE", "Fla": "FL", "Ga": "GA",
          "Ill": "IL", "Ind": "IN", "Kan": "KS", "Ky": "KY", "La": "LA", "Md": "MD", "Mass": "MA", "Mich": "MI", "Minn": "MN",
          "Miss": "MS", "Mo": "MO", "Mont": "MT", "Neb": "NE", "Nev": "NV", "N.H": "NH", "N.J": "NJ", "N.M": "NM", "N.Y": "NY",
          "N.C": "NC", "N.D": "ND", "Okla": "OK", "Ore": "OR", "Pa": "PA", "R.I": "RI", "S.C": "SC", "S.D": "SD", "Tenn": "TN",
          "Va": "VA", "Vt": "VT", "Wash": "WA", "W.Va": "WV", "Wis": "WI", "Wisc": "WI", "Wyo": "WY"}


def gg_meta(url, year, browser):
    title, widget = gg_widget(url, browser)
    event = re.sub(r"\s*Event\s*::.*$", "", title).strip()
    label = BeautifulSoup(widget, "lxml").get_text(" ", strip=True)
    m = re.search(r"\((?:\w{3}, )?([A-Z][a-z]+ \d{1,2})\)", label)  # "Round 1 (Wed, August 20)" -> qualifying ran the year before
    when = datetime.strptime(f"{m.group(1)} {year - 1}", "%B %d %Y").date().isoformat() if m else ""
    loc = re.search(r"-\s*([A-Za-z .']+),\s*([A-Z][A-Za-z.]+?)\.?$", event)  # "... - Narragansett, R.I."
    city, state = (loc.group(1).strip(), STATES.get(loc.group(2).rstrip("."), loc.group(2))) if loc else ("", "")
    name = re.search(r"\(([^)]+)\)", event)  # "2023 U.S. Amateur Four-Ball Qualifying (Monarch Dunes)"
    return {"name": name.group(1) if name else event, "city": city, "state": state, "date": when, "gg_title": event}


def main(year, urls):
    path = DATA / "seeds" / f"{partition(year)}.json"
    seed = json.loads(path.read_text(encoding="utf8")) if path.exists() else {"year": year, "sites": []}
    known = {s["scoringUrl"] for s in seed["sites"]}
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=False)  # headless gets 403
        for url in (u for u in urls if u not in known):
            site = {"name": "", "city": "", "state": "", "date": "", "scoringUrl": url}
            if platform(url) == "golfgenius":
                try: site.update(gg_meta(url, year, browser))
                except Exception as e: print("  meta error:", str(e)[:100])
            print(site)
            seed["sites"].append(site)
        browser.close()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(seed, indent=2), encoding="utf8")


if __name__ == "__main__":
    main(int(sys.argv[1]), sys.argv[2:])
