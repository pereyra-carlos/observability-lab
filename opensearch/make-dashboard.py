import json
import os

IP = "logs-k8s"
REF = "kibanaSavedObjectMeta.searchSourceJSON.index"
OUT = os.path.join(os.path.dirname(__file__), "vantia-dashboard.ndjson")

objs = [{
    "id": IP,
    "type": "index-pattern",
    "attributes": {"title": "logs-k8s*", "timeFieldName": "@timestamp"},
    "references": [],
}]


PALETTE = {
    "gateway": "#2478CC", "retrieval": "#E8833A", "llm-worker": "#16A34A",
    "accept": "#2478CC", "retrieve": "#E8833A", "generate": "#16A34A",
    "ok": "#16A34A", "error": "#DC2626", "rejected": "#B45309",
}

NO_LOADGEN = "not service:loadgen"


def vis(vid, title, vis_state, query="", colors=None):
    search_source = {
        "query": {"query": query, "language": "kuery"},
        "filter": [],
        "indexRefName": REF,
    }
    objs.append({
        "id": vid,
        "type": "visualization",
        "attributes": {
            "title": title,
            "description": "",
            "visState": json.dumps(vis_state),
            "uiStateJSON": json.dumps(
                {"vis": {"colors": {k: PALETTE[k] for k in colors}}} if colors else {}),
            "version": 1,
            "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(search_source)},
        },
        "references": [{"name": REF, "type": "index-pattern", "id": IP}],
    })


def category_axis():
    return [{"id": "CategoryAxis-1", "type": "category", "position": "bottom", "show": True,
             "style": {}, "scale": {"type": "linear"}, "title": {},
             "labels": {"show": True, "filter": True, "truncate": 100}}]


def value_axis(text, scale="linear"):
    return [{"id": "ValueAxis-1", "name": "LeftAxis-1", "type": "value", "position": "left",
             "show": True, "style": {}, "scale": {"type": scale, "mode": "normal"},
             "labels": {"show": True, "rotate": 0, "filter": False, "truncate": 100},
             "title": {"text": text}}]


vis("vantia-volume", "Log volume by service (the assistant only)", {
    "title": "Log volume by service (the assistant only)", "type": "histogram",
    "params": {"type": "histogram", "grid": {"categoryLines": False},
               "categoryAxes": category_axis(), "valueAxes": value_axis("lines"),
               "seriesParams": [{"show": True, "type": "histogram", "mode": "stacked",
                                 "data": {"label": "lines", "id": "1"},
                                 "valueAxis": "ValueAxis-1", "drawLinesBetweenPoints": True,
                                 "lineWidth": 2, "showCircles": True}],
               "addTooltip": True, "addLegend": True, "legendPosition": "right",
               "times": [], "addTimeMarker": False, "labels": {}, "thresholdLine": {"show": False}},
    "aggs": [
        {"id": "1", "enabled": True, "type": "count", "schema": "metric",
         "params": {"customLabel": "lines"}},
        {"id": "2", "enabled": True, "type": "date_histogram", "schema": "segment",
         "params": {"field": "@timestamp", "interval": "auto",
                    "useNormalizedOpenSearchInterval": True, "scaleMetricValues": False,
                    "drop_partials": False, "min_doc_count": 1, "extended_bounds": {}}},
        {"id": "3", "enabled": True, "type": "terms", "schema": "group",
         "params": {"field": "service", "orderBy": "1", "order": "desc", "size": 5,
                    "otherBucket": False, "otherBucketLabel": "Other",
                    "missingBucket": False, "missingBucketLabel": "Missing",
                    "customLabel": "service"}},
    ]}, query=NO_LOADGEN, colors=["gateway", "retrieval", "llm-worker"])

vis("vantia-status", "Outcome of every request", {
    "title": "Outcome of every request", "type": "pie",
    "params": {"type": "pie", "addTooltip": True, "addLegend": True, "legendPosition": "right",
               "isDonut": True,
               "labels": {"show": True, "values": True, "last_level": True, "truncate": 100}},
    "aggs": [
        {"id": "1", "enabled": True, "type": "count", "schema": "metric", "params": {}},
        {"id": "2", "enabled": True, "type": "terms", "schema": "segment",
         "params": {"field": "status", "orderBy": "1", "order": "desc", "size": 5,
                    "otherBucket": False, "otherBucketLabel": "Other",
                    "missingBucket": False, "missingBucketLabel": "Missing",
                    "customLabel": "status"}},
    ]}, query="stage:generate or stage:validate", colors=["ok", "error", "rejected"])

vis("vantia-latency", "Where the time goes — p95 per stage, log scale", {
    "title": "Where the time goes — p95 per stage, log scale", "type": "line",
    "params": {"type": "line", "grid": {"categoryLines": False},
               "categoryAxes": category_axis(), "valueAxes": value_axis("ms (log)", scale="log"),
               "seriesParams": [{"show": True, "type": "line", "mode": "normal",
                                 "data": {"label": "p95 latency", "id": "1"},
                                 "valueAxis": "ValueAxis-1", "drawLinesBetweenPoints": True,
                                 "interpolate": "linear", "lineWidth": 2, "showCircles": True}],
               "addTooltip": True, "addLegend": True, "legendPosition": "right",
               "times": [], "addTimeMarker": False, "labels": {}, "thresholdLine": {"show": False}},
    "aggs": [
        {"id": "1", "enabled": True, "type": "percentiles", "schema": "metric",
         "params": {"field": "latency_ms", "percents": [95], "customLabel": "p95 latency"}},
        {"id": "2", "enabled": True, "type": "date_histogram", "schema": "segment",
         "params": {"field": "@timestamp", "interval": "auto",
                    "useNormalizedOpenSearchInterval": True, "scaleMetricValues": False,
                    "drop_partials": False, "min_doc_count": 1, "extended_bounds": {}}},
        {"id": "3", "enabled": True, "type": "terms", "schema": "group",
         "params": {"field": "stage", "orderBy": "_key", "order": "asc", "size": 6,
                    "otherBucket": False, "otherBucketLabel": "Other",
                    "missingBucket": False, "missingBucketLabel": "Missing",
                    "customLabel": "stage"}},
    ]}, query=f"latency_ms > 0 and {NO_LOADGEN}", colors=["accept", "retrieve", "generate"])

vis("vantia-tenants", "Cost and volume per tenant", {
    "title": "Cost and volume per tenant", "type": "table",
    "params": {"perPage": 10, "showPartialRows": False, "showMetricsAtAllLevels": False,
               "showTotal": False, "totalFunc": "sum", "percentageCol": "",
               "sort": {"columnIndex": None, "direction": None}},
    "aggs": [
        {"id": "1", "enabled": True, "type": "count", "schema": "metric",
         "params": {"customLabel": "answers"}},
        {"id": "2", "enabled": True, "type": "sum", "schema": "metric",
         "params": {"field": "cost_usd", "customLabel": "total cost (USD)"}},
        {"id": "3", "enabled": True, "type": "avg", "schema": "metric",
         "params": {"field": "total_ms", "customLabel": "avg wait (ms)"}},
        {"id": "4", "enabled": True, "type": "terms", "schema": "bucket",
         "params": {"field": "tenant", "orderBy": "1", "order": "desc", "size": 10,
                    "otherBucket": False, "otherBucketLabel": "Other",
                    "missingBucket": False, "missingBucketLabel": "Missing",
                    "customLabel": "tenant"}},
    ]}, query="stage:generate")

panels = [
    ("vantia-volume", 0, 0, 32, 14),
    ("vantia-status", 32, 0, 16, 14),
    ("vantia-latency", 0, 14, 32, 15),
    ("vantia-tenants", 32, 14, 16, 15),
]

objs.append({
    "id": "vantia-assistant",
    "type": "dashboard",
    "attributes": {
        "title": "Vantia — support assistant",
        "description": "One request leaves lines in three services. Search by request_id to rebuild a conversation.",
        "panelsJSON": json.dumps([
            {"version": "3.8.0",
             "gridData": {"x": x, "y": y, "w": w, "h": h, "i": str(n + 1)},
             "panelIndex": str(n + 1), "embeddableConfig": {},
             "panelRefName": f"panel_{n}"}
            for n, (_, x, y, w, h) in enumerate(panels)]),
        "optionsJSON": json.dumps({"hidePanelTitles": False, "useMargins": True}),
        "version": 1,
        "timeRestore": True, "timeTo": "now", "timeFrom": "now-1h",
        "refreshInterval": {"pause": False, "value": 30000},
        "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(
            {"query": {"query": "", "language": "kuery"}, "filter": []})},
    },
    "references": [{"name": f"panel_{n}", "type": "visualization", "id": vid}
                   for n, (vid, *_rest) in enumerate(panels)],
})

with open(OUT, "w") as f:
    for o in objs:
        f.write(json.dumps(o) + "\n")

print(f"{len(objs)} objects written to {OUT}")
