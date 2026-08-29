import json
import sys

EXTRA = ("docs_found", "tokens_in", "tokens_out", "cost_usd", "model", "error", "attempts")

d = json.load(sys.stdin)
hits = d["hits"]["hits"]
total = d["hits"]["total"]["value"]

print(f"  {total} lines for this request\n")
if not hits:
    print("  nothing. either the id is wrong, or the logs aged out of retention.")
    raise SystemExit

for h in hits:
    s = h["_source"]
    k = s.get("kubernetes", {})
    mark = "!" if s.get("status") not in ("ok", None) else " "
    ts = s.get("ts", "")[11:23]
    print(f" {mark} {ts}  {s.get('service',''):<11} {s.get('stage',''):<9} "
          f"{s.get('status',''):<9} {s.get('latency_ms', 0):>9.2f} ms")
    print(f"     pod {k.get('pod_name','?')}  node {k.get('host','?')}")
    extra = [f"{f}={s[f]}" for f in EXTRA if s.get(f) is not None]
    if extra:
        print("     " + "  ".join(extra))
    if s.get("total_ms"):
        print(f"     customer waited {s['total_ms']:.0f} ms in total")
    print()
