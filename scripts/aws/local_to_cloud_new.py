"""Upload score CSVs that aren't already in the bucket, then overwrite the dims + inventory (small, and they change in place)."""
from pathlib import Path

import boto3

BUCKET = "fourball-qualifying-342262164553-us-east-1-an"
BRONZE = Path(__file__).resolve().parents[2] / "data/bronze"
SCORES = BRONZE / "scores"

s3 = boto3.client("s3")
pages = s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix="scores/")
existing = {obj["Key"] for page in pages for obj in page.get("Contents", [])}


new = [p for p in SCORES.glob("*-fourball/**/*.csv") if f"scores/{p.relative_to(SCORES).as_posix()}" not in existing]
for path in new:
    key = f"scores/{path.relative_to(SCORES).as_posix()}"
    s3.upload_file(str(path), BUCKET, key)
    print(f"Uploaded {path.name} -> s3://{BUCKET}/{key}")
print(f"{len(new)} new file(s) uploaded, {len(existing)} already in bucket.")

for name in ("dim_golf_course.csv", "dim_golf_course_holes.csv"):
    s3.upload_file(str(BRONZE / name), BUCKET, f"dims/{name}")
    print(f"Uploaded {name} -> s3://{BUCKET}/dims/{name}")

# Every known site per season incl. ones without results yet (upcoming / manual / source_gone)
for path in sorted((BRONZE.parent / "inventory").glob("*-fourball.json")):
    s3.upload_file(str(path), BUCKET, f"inventory/{path.name}")
    print(f"Uploaded {path.name} -> s3://{BUCKET}/inventory/{path.name}")

# WAGR weekly rankings: published weeks never change, so only upload new files
WAGR = BRONZE / "wagr"
wagr_existing = {o["Key"] for p in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix="wagr/") for o in p.get("Contents", [])}
for path in sorted(WAGR.glob("*.csv")):
    if f"wagr/{path.name}" not in wagr_existing:
        s3.upload_file(str(path), BUCKET, f"wagr/{path.name}")
        print(f"Uploaded {path.name} -> s3://{BUCKET}/wagr/{path.name}")
