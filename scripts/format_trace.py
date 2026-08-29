import json
import sys

BIZ = "vantia."

d = json.load(sys.stdin)
batches = d.get("batches") or d.get("resourceSpans") or []

rows = []
for b in batches:
    svc = ""
    for a in b.get("resource", {}).get("attributes", []):
        if a["key"] == "service.name":
            svc = a["value"].get("stringValue", "")
    for ss in b.get("scopeSpans") or b.get("instrumentationLibrarySpans") or []:
        for s in ss.get("spans", []):
            start = int(s["startTimeUnixNano"])
            dur = (int(s["endTimeUnixNano"]) - start) / 1e6
            attrs = {a["key"]: list(a["value"].values())[0] for a in s.get("attributes", [])}
            rows.append((start, svc, s["name"], dur, s.get("parentSpanId") or "", attrs))

if not rows:
    print("  no spans. either the trace id is wrong, or it aged out of retention.")
    raise SystemExit

rows.sort()
t0 = rows[0][0]
total = max(r[0] + r[3] * 1e6 for r in rows) - t0
width = 46

print(f"  {len(rows)} spans, {total / 1e6:.0f} ms end to end\n")
for start, svc, name, dur, parent, attrs in rows:
    offset = (start - t0) / 1e6
    lead = int(offset / (total / 1e6) * width) if total else 0
    bar = max(1, int(dur / (total / 1e6) * width)) if total else 1
    share = dur / (total / 1e6) * 100 if total else 0
    print(f"  {name:<18} {' ' * lead}{'█' * bar}")
    print(f"  {'':<18} {dur:>9.2f} ms  {share:>5.1f}%  [{svc}]")
    biz = {k[len(BIZ):]: v for k, v in sorted(attrs.items()) if k.startswith(BIZ)}
    interesting = {k: v for k, v in biz.items() if k not in ("request_id", "tenant", "scenario")}
    if interesting:
        print(f"  {'':<18} {'  '.join(f'{k}={v}' for k, v in interesting.items())}")
    print()
