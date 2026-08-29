"""Rebuild the alerting block of grafana/values.yaml from grafana/alerting.yaml.

Hand-editing a deeply nested YAML block with text substitution broke the file twice.
This parses and re-emits instead, so indentation is never a question.
"""
import os
import yaml

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VALUES = os.path.join(HERE, "grafana", "values.yaml")
ALERTING = os.path.join(HERE, "grafana", "alerting.yaml")

alerting = yaml.safe_load(open(ALERTING))
body = yaml.dump(alerting, sort_keys=False, default_flow_style=False, width=100, allow_unicode=True)
block = "\nalerting:\n" + "\n".join("  " + l if l.strip() else l for l in body.split("\n")) + "\n"

vals = open(VALUES).read()
marker = "\nalerting:\n"
vals = vals[: vals.index(marker)] if marker in vals else vals.rstrip() + "\n"
open(VALUES, "w").write(vals + block)

yaml.safe_load(open(VALUES))
print(f"values.yaml rebuilt · alerting files: {list(alerting)}")
