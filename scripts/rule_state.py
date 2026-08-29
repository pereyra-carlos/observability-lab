import json
import sys

for group in json.load(sys.stdin)["data"]["groups"]:
    for rule in group["rules"]:
        if "bill" in rule["name"]:
            print(rule.get("state", "?"))
