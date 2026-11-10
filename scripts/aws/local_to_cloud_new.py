"""Upload score CSVs that aren't already in the bucket, then overwrite the dims (small, and they change in place)."""
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
