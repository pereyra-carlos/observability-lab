import json
import sys

a = json.load(sys.stdin)["aggregations"]
print("%.4f %d" % (a["c"]["value"], int(a["n"]["value"])))
