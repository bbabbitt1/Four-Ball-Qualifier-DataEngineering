"""Snapshot alternates + their stats from the dbt marts into docs/data/ (read by the GitHub Pages site in docs/).

alternates.json     one row per alternate side, with the field context the page's breakdowns show
field_players.json  {qualifier_key: [rated players in that field]} for the WAGR strength-of-field breakdown
"""
import json
from pathlib import Path

import snowflake.connector
import yaml

ALTERNATES = """
with season_sof as (
    select championship_year, avg(wagr_points_per_side) as season_points_per_side, stddev_samp(wagr_points_per_side) as season_points_sd
    from agg_qualifier_field_strength group by 1
)
select s.side_id, s.qualifier_key, s.team_name, s.alternate_number, s.championship_year, s.qualifier_date, q.site_name, q.state,
       s.gross, s.to_par, s.field_size_scored, s.z_score, s.robust_z, s.season_z_score,
       s.strokes_from_qualifying, s.score_vs_rating, s.percentile_in_field, s.rank_in_field,
       s.field_mean_gross, s.field_median_gross, s.field_stddev_gross, s.season_mean_to_par,
       a.field_strength, a.mean_to_par as field_mean_to_par, a.qualifying_score, a.spots,
       fs.wagr_strength_z, fs.wagr_points_per_side, fs.wagr_points, fs.best_rank, fs.field_sides,
       fs.ranked_players, fs.pro_players, ss.season_points_per_side, ss.season_points_sd
from fct_side_score_stats s
join dim_qualifier q using (qualifier_key)
join agg_qualifier_score_stats a using (qualifier_key)
left join agg_qualifier_field_strength fs using (qualifier_key)
left join season_sof ss on ss.championship_year = s.championship_year
where s.outcome = 'alternate'
order by s.championship_year, s.qualifier_date, s.gross
"""

FIELD_PLAYERS = """
select p.qualifier_key, p.player_name, p.player_from, p.wagr_rank, p.pro_equiv_rank, p.is_pro_rank, p.points,
       r.team_name, r.outcome, r.gross
from fct_field_player_rank p
join fct_side_result r using (side_id)
where p.effective_rank is not null
  and p.qualifier_key in (select qualifier_key from fct_side_result where outcome = 'alternate')
order by p.qualifier_key, p.points desc
"""


def to_json(v):
    return float(v) if hasattr(v, "is_finite") else v.isoformat() if hasattr(v, "isoformat") else v


def fetch(con, sql):
    cur = con.cursor()
    cur.execute(sql)
    cols = [c[0].lower() for c in cur.description]
    return [{k: to_json(v) for k, v in zip(cols, r)} for r in cur]


def main(target="dev"):
    p = yaml.safe_load((Path.home() / ".dbt/profiles.yml").read_text())["dbt_fourball"]["outputs"][target]
    with snowflake.connector.connect(
        account=p["account"], user=p["user"], role=p["role"], warehouse=p["warehouse"],
        database=p["database"], schema=p["schema"], authenticator="SNOWFLAKE_JWT", private_key_file=p["private_key_path"],
    ) as con:
        alternates, players = fetch(con, ALTERNATES), fetch(con, FIELD_PLAYERS)
    fields = {}
    for r in players:
        fields.setdefault(r.pop("qualifier_key"), []).append(r)
    out = Path(__file__).parent / "docs/data"
    (out / "alternates.json").write_text(json.dumps(alternates, indent=1))
    (out / "field_players.json").write_text(json.dumps(fields, separators=(",", ":")))
    print(f"{len(alternates)} alternates, {len(players)} rated players in {len(fields)} fields -> {out}")


if __name__ == "__main__":
    main()
