# Runbook: U.S. Amateur Four-Ball qualifier scrape

## "Get the latest qualifiers"

```bash
pip install -r requirements.txt && playwright install chromium   # first time only (Chrome must be installed)
python scrape.py --years 2027      # in-progress season; a Chrome window opens. If BlueGolf shows a CAPTCHA, solve it there
python courses.py                  # adds any new courses to dim_golf_course.csv
python test_scrape.py              # parser sanity check (offline)
```

Then check `data/inventory/2027-fourball.json`:
- `latest_scraped_date`: the most recent qualifier we hold
- `status_counts`: how many sites are in each state (see the status table below)
- per-site `status`, `rows`, `csv`

Runs are incremental. A site with `status: scraped` whose CSV still exists is skipped. Everything else
(`upcoming`, `no_results_link`, `no_rows_yet`, `error: ...`) is retried, so a rerun after the next qualifier date
picks up new results. `--force` re-scrapes everything for the given years.

A new season starts in August, and its championship year is the season's calendar year + 1. Add the year:
`python scrape.py --years 2027 2028`.

## Where the data comes from

| Source | Used for | Notes |
|---|---|---|
| USGA API `ace-api.usga.org/scoring/v1/qualifying-page.json?championship=us4ball&championship-year=YYYY` | site list: date, course, city/state, field size, results link; also qualifiers and alternates | Behind Akamai, so it's called from inside a **headed** Chrome page (headless gets "Access Denied"). The key is the public one the USGA page sends. **Only 2025+ exist.** 2022–2024 return 404. |
| Golf Genius (`golfgenius.com/pages/...`) | full-field leaderboard, one row per side | Results iframe is built client-side (browser), then plain HTTP for the `v2tournaments` leaderboard. Headless gets 403. |
| Golf Genius scorecard (`/tournaments2/details/{id}`) | par per hole → `dim_golf_course_holes.csv` | par = gross − to-par on a side's card |
| BlueGolf (`*.bluegolf.com`) | full-field leaderboard + scorecard (par, **yardage**, stroke index per hole) | AWS WAF **CAPTCHA**. Never auto-solved: a person solves it once in the Chrome window, and the cookie persists in `.browser-profile/` (gitignored). The script waits up to 10 min, then paces 3s per page. |
| NCRDB (`ncrdb.usga.org`) | back-tee par / rating / slope | Back tees = the men's tee with the highest Course Rating |
| OSM Nominatim | address, lat, long | 1 req/sec |

## Layout

```
data/
  bronze/
    usga_api/{YYYY}-fourball.json                     raw USGA payload (incl. qualifiers/alternates for every site)
    scores/{YYYY}-fourball/{qualifier_date}_{course_id}.csv   full field, one row per side
    dim_golf_course.csv                               course_id, name, city, state, address, lat, long, tees, par, rating, slope,
                                                      ncrdb_course_id, ncrdb_name, ncrdb_match_score, geo_precision
    dim_golf_course_holes.csv                         course_id, tees, hole, par, yardage, handicap (yardage/handicap only for BlueGolf courses)
  inventory/{YYYY}-fourball.json                      what exists vs what we have (statuses below)
  seeds/                                              hand-built site lists for seasons the USGA API doesn't serve
```

`YYYY` is the **championship** year. `2027-fourball` = qualifiers played Aug–Dec 2026.

Score CSV columns are **not standardized**: they keep whatever Golf Genius shows (`Total` vs `TotalGross`, etc.).
Every file always has `qualifier_date`, `course_id`, `site_name`, `source_url`, `player1`, `player1_from`, `player2`,
`player2_from`, `gg_aggregate_id`. `Pos.` = `CUT` means the side didn't advance. `Details` holds Qualified / Alternate / playoff notes.

`course_id` = slug of USGA site name + state, e.g. `dataw-island-club-cotton-dike-course-sc`. Same course in different years = same id.

## Inventory statuses

| status | meaning | action |
|---|---|---|
| `scraped` | CSV written | none |
| `upcoming` | qualifier date is in the future | rerun later |
| `no_results_link` | past date, USGA hasn't posted a link yet | rerun later |
| `no_rows_yet` | link exists, leaderboard empty | rerun later |
| `manual` | other host (state-association site, PDF, CDGA live scoring) | manual, same as above |
| `source_gone` | BlueGolf page removed (e.g. WVGA left BlueGolf) | none; skipped on reruns unless `--force` |
| `error: BlueGolf CAPTCHA not solved` | nobody solved it within 10 min | rerun and solve it |
| `error: ...` | scrape failed | look at the message; often the link is the event home page and not its results page |

## Known gaps / TODO

- **2023 and 2024** come from `data/seeds/{YYYY}-fourball.json`. These were built from the earlier project
  `development/Four-Ball-Scores/golf_genius_all_years.csv` (Golf Genius URLs + dates), with state from our inventories,
  Nominatim, or fixed by hand (`state_source`). The seeds cover only Golf Genius sites; the 2023 BlueGolf links still
  sitting in `2023-fourball.candidates.txt` aren't seeded yet.
- **2022 (qualifiers in 2021) is not loaded.** No source has been found yet. In that old CSV, "2022" is a duplicate of 2023.
  To add sites, put entries in `data/seeds/2022-fourball.json` (`sites[]`: `name, city, state, date, scoringUrl`), or use
  `python seed.py 2022 <url>...`, then `python scrape.py --years 2022`.
- `dim_golf_course` is a fuzzy NCRDB name match. Rows with low `ncrdb_match_score` (< ~0.6) or a blank rating need a
  by-hand check: fix the row in the CSV (reruns keep existing course_ids). `geo_precision = city` means lat/long is the
  city centroid, because the course itself wasn't found in OSM.
- Hole **yardage** is blank: neither NCRDB nor Golf Genius exposes it. BlueGolf course pages have it, but they're behind the CAPTCHA.
- `usga_field_size_players` in the inventory counts entries, not starters, so it won't exactly equal `rows × 2`.
- Hole-by-hole scores per side are available (`/tournaments2/details/{gg_aggregate_id}`), but not pulled yet (about 1 request per side).
