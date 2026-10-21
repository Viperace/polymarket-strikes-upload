"""Write a short Markdown summary of the strike CSVs to stdout."""
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

data = Path(sys.argv[1] if len(sys.argv) > 1 else "data")
print("### Strike files\n")
print("| file | rows | first bucket (UTC) | last bucket (UTC) | blank strikes |")
print("|---|---:|---|---|---:|")
for name in ("btc_5m_strikes.csv", "eth_5m_strikes.csv"):
    path = data / name
    if not path.exists():
        print(f"| {name} | – | – | – | – |")
        continue
    df = pd.read_csv(path, usecols=["bucket_start_ts", "strike"])
    ts = pd.to_numeric(df["bucket_start_ts"], errors="coerce").dropna()
    fmt = lambda t: datetime.fromtimestamp(int(t), tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    print(
        f"| {name} | {len(df):,} | {fmt(ts.min())} | {fmt(ts.max())} "
        f"| {int(df['strike'].isna().sum())} |"
    )
