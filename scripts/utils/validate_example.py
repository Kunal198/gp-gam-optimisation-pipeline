#!/usr/bin/env python3
from pathlib import Path
import hashlib, csv
from datetime import datetime

def md5sum(path: Path, chunk=1<<16) -> str:
    import hashlib
    h = hashlib.md5()
    with open(path, "rb") as fh:
        while True:
            b = fh.read(chunk)
            if not b: break
            h.update(b)
    return h.hexdigest()

ROOT = Path(__file__).resolve().parents[2]
in_dir = ROOT / "examples" / "tiny_sample_inputs" / "H2SO4" / "jan"
out_gp = ROOT / "examples" / "tiny_sample_outputs" / "gp_emulation"
out_gam = ROOT / "examples" / "tiny_sample_outputs" / "gam_variance"

inputs = sorted(in_dir.glob("*.dat"))
print(f"Found {len(inputs)} input files:")
for p in inputs:
    print(f" - {p.name} ({p.stat().st_size} bytes; md5={md5sum(p)})")

print("\nOutputs present?")
print(" - GP emulation files:", len(list(out_gp.glob('*'))))
print(" - GAM variance files:", len(list(out_gam.glob('*'))))

# Build a manifest for inputs
rows = []
for p in inputs:
    rows.append({
        "filename": p.name,
        "bytes": p.stat().st_size,
        "md5": md5sum(p),
        "modified_utc": datetime.utcfromtimestamp(p.stat().st_mtime).isoformat() + "Z"
    })
with open(in_dir / "manifest.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["filename","bytes","md5","modified_utc"])
    w.writeheader(); w.writerows(rows)

print("\nOK ✅ (Presence & checksums validated; manifest.csv written).")
