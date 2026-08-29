import json
import os
import urllib.parse

OUT = os.path.join(os.path.dirname(__file__), "vantia-request.json")
OS_DS = {"type": "grafana-opensearch-datasource", "uid": "opensearch-logs"}
TEMPO_DS = {"type": "tempo", "uid": "tempo-traces"}


def os_target(query, metrics, bucket_aggs, ref="A"):
    return {
        "refId": ref,
        "datasource": OS_DS,
        "query": query,
        "queryType": "lucene",
        "metrics": metrics,
        "bucketAggs": bucket_aggs,
        "timeField": "@timestamp",
    }


TOKEN = "__TRACEID__"
_panes = {
    "logs": {
        "datasource": "opensearch-logs",
        "queries": [
            {
                "refId": "A",
                "datasource": OS_DS,
                "query": f'trace_id:"{TOKEN}"',
                "queryType": "lucene",
                "metrics": [{"id": "1", "type": "logs"}],
                "bucketAggs": [],
                "timeField": "@timestamp",
            }
        ],
        "range": {"from": "now-6h", "to": "now"},
    },
    "trace": {
        "datasource": "tempo-traces",
        "queries": [{"refId": "A", "datasource": TEMPO_DS, "queryType": "traceql", "query": TOKEN}],
        "range": {"from": "now-6h", "to": "now"},
    },
}
EXPLORE_SPLIT = (
    "/explore?schemaVersion=1&orgId=1&panes="
    + urllib.parse.quote(json.dumps(_panes), safe="")
).replace(urllib.parse.quote(TOKEN, safe=""), "${__value.raw}")


slowest = {
    "id": 1,
    "type": "table",
    "title": "Slowest requests — click a trace_id to fill the two panels below",
    "datasource": OS_DS,
    "gridPos": {"h": 9, "w": 24, "x": 0, "y": 0},
    "targets": [
        os_target(
            "stage:generate AND _exists_:trace_id",
            [{"id": "1", "type": "raw_data", "settings": {"size": "20"}}],
            [],
        )
    ],
    "options": {"showHeader": True},
    "fieldConfig": {
        "defaults": {"custom": {"align": "auto", "filterable": True}},
        "overrides": [
            {
                "matcher": {"id": "byName", "options": "total_ms"},
                "properties": [
                    {"id": "unit", "value": "ms"},
                    {"id": "custom.cellOptions", "value": {"type": "color-background"}},
                    {
                        "id": "thresholds",
                        "value": {
                            "mode": "absolute",
                            "steps": [
                                {"color": "green", "value": None},
                                {"color": "orange", "value": 8000},
                                {"color": "red", "value": 20000},
                            ],
                        },
                    },
                ],
            },
            {
                "matcher": {"id": "byName", "options": "latency_ms"},
                "properties": [{"id": "unit", "value": "ms"}],
            },
            {
                "matcher": {"id": "byName", "options": "cost_usd"},
                "properties": [{"id": "unit", "value": "currencyUSD"}, {"id": "decimals", "value": 5}],
            },
            {
                # Clicking a trace_id fills the dashboard variable, which is what
                # makes the two panels below light up. Without this the table is a
                # list you have to copy from by hand.
                "matcher": {"id": "byName", "options": "trace_id"},
                "properties": [
                    {
                        "id": "links",
                        "value": [
                            {
                                "title": "Ver abajo, en esta pantalla",
                                "url": "d/vantia-request?var-trace_id=${__value.raw}",
                            },
                            {
                                # Explore does not go through dashboard variables at
                                # all, so this route works even if interpolation does
                                # not. Logs on the left, the waterfall on the right.
                                "title": "Abrir en Explore (logs + traza)",
                                "url": EXPLORE_SPLIT,
                            },
                        ],
                    }
                ],
            },
        ],
    },
    "transformations": [
        # Allow-list, not deny-list. With raw_data the field set is large and
        # changes as the app adds fields, so naming what to drop never keeps up.
        {
            "id": "filterFieldsByName",
            "options": {
                "include": {
                    "names": [
                        "@timestamp", "request_id", "trace_id", "tenant", "scenario",
                        "model", "status", "latency_ms", "total_ms", "tokens_out", "cost_usd",
                    ]
                }
            },
        },
        # Sort before the rename: sorting on a renamed field fails silently if the
        # rename ever stops matching.
        {"id": "sortBy", "options": {"fields": {}, "sort": [{"field": "total_ms", "desc": True}]}},
        {
            "id": "organize",
            "options": {
                "excludeByName": {},
                "includeByName": {},
                "indexByName": {
                    "@timestamp": 0, "total_ms": 1, "latency_ms": 2, "tenant": 3,
                    "scenario": 4, "model": 5, "tokens_out": 6, "cost_usd": 7,
                    "status": 8, "request_id": 9, "trace_id": 10,
                },
                "renameByName": {
                    "total_ms": "el cliente esperó",
                    "latency_ms": "tardó la etapa",
                    "tokens_out": "tokens",
                    "cost_usd": "costo",
                },
            },
        },
    ],
}

EMPTY = "Pick a request above: click its trace_id."

logs = {
    "id": 2,
    "type": "logs",
    "title": "The logs of this request — click a trace_id above",
    "description": "Empty until a trace_id is chosen. Every log line carries one.",
    "fieldConfig": {"defaults": {"noValue": EMPTY}, "overrides": []},
    "datasource": OS_DS,
    "gridPos": {"h": 10, "w": 24, "x": 0, "y": 9},
    "targets": [
        os_target('trace_id:"${trace_id}"', [{"id": "1", "type": "logs", "settings": {"limit": "50"}}], [])
    ],
    "options": {
        "showTime": True,
        "wrapLogMessage": True,
        "sortOrder": "Ascending",
        "enableLogDetails": True,
    },
}

trace = {
    "id": 3,
    "type": "traces",
    "title": "The same request, drawn — click a trace_id above",
    "description": "Empty until a trace_id is chosen. Same request as the panel above, as a waterfall.",
    "fieldConfig": {"defaults": {"noValue": EMPTY}, "overrides": []},
    "datasource": TEMPO_DS,
    "gridPos": {"h": 13, "w": 24, "x": 0, "y": 19},
    # queryType is traceql, not traceId. traceId is what the *backend* accepts;
    # the panel UI only knows Search / TraceQL / Service Graph, so traceId falls
    # back to Search and the panel queries for nothing. With traceql the frontend
    # recognises a 32-hex string and does the by-id lookup itself.
    "targets": [{"refId": "A", "datasource": TEMPO_DS, "queryType": "traceql", "query": "${trace_id}"}],
}

dashboard = {
    "uid": "vantia-request",
    "title": "Vantia — one request, both signals",
    "description": (
        "Click a trace_id in the table and the two panels below fill with the same request: "
        "once as log lines, once as a waterfall. The trace_id in every log line is the entire "
        "link between them."
    ),
    "tags": ["vantia", "correlation"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "",
    "time": {"from": "now-3h", "to": "now"},
    "templating": {
        "list": [
            {
                "name": "trace_id",
                "label": "trace_id",
                "type": "textbox",
                "query": "",
                # Grafana's own shape for a textbox: it needs an options entry and
                # skipUrlSync false, or a value arriving from the URL is not picked up.
                "current": {"selected": False, "text": "", "value": ""},
                "options": [{"selected": True, "text": "", "value": ""}],
                "skipUrlSync": False,
                "hide": 0,
            }
        ]
    },
    "panels": [slowest, logs, trace],
}

with open(OUT, "w") as f:
    json.dump(dashboard, f, indent=2)
print(f"dashboard written to {OUT}")
