"""Snapshot every alternate side + its stats from the dbt marts into docs/data/alternates.json (read by the GitHub Pages site in docs/)."""
import json
from pathlib import Path

import snowflake.connector
import yaml

SQL = """
select s.side_id, s.team_name, s.alternate_number, s.championship_year, s.qualifier_date, q.site_name, q.state,
       s.gross, s.to_par, s.field_size_scored, s.z_score, s.robust_z, s.season_z_score,
       s.strokes_from_qualifying, s.score_vs_rating, s.percentile_in_field,
       a.field_strength, a.qualifying_score, fs.wagr_strength_z, fs.wagr_points_per_side, fs.best_rank
from fct_side_score_stats s
join dim_qualifier q using (qualifier_key)
join agg_qualifier_score_stats a using (qualifier_key)
left join agg_qualifier_field_strength fs using (qualifier_key)
where s.outcome = 'alternate'
order by s.championship_year, s.qualifier_date, s.gross
"""


def to_json(v):
    return float(v) if hasattr(v, "is_finite") else v.isoformat() if hasattr(v, "isoformat") else v


def main(target="dev"):
    p = yaml.safe_load((Path.home() / ".dbt/profiles.yml").read_text())["dbt_fourball"]["outputs"][target]
    with snowflake.connector.connect(
        account=p["account"], user=p["user"], role=p["role"], warehouse=p["warehouse"],
        database=p["database"], schema=p["schema"], authenticator="SNOWFLAKE_JWT", private_key_file=p["private_key_path"],
    ) as con:
        cur = con.cursor()
        cur.execute(SQL)
        cols = [c[0].lower() for c in cur.description]
        rows = [{k: to_json(v) for k, v in zip(cols, r)} for r in cur]
    out = Path(__file__).parent / "docs/data/alternates.json"
    out.write_text(json.dumps(rows, indent=1))
    print(f"{len(rows)} alternates -> {out}")


if __name__ == "__main__":
    main()
