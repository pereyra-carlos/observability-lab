import json
import os
import time

import redis

from .log import event, get_logger
from .simulate import docs_found, retrieval_latency_ms
from .tracing import carrier, context_of, tracer

logger = get_logger()
client = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://vantia-redis:6379/0"))

IN_QUEUE = "q:retrieval"
OUT_QUEUE = "q:llm"


def handle(payload):
    with tracer().start_as_current_span(
        "retrieval.search", context=context_of(payload)
    ) as span:
        _handle(payload, span)


def _handle(payload, span):
    started = time.time()
    scenario = payload["scenario"]
    found = docs_found(scenario)
    latency = retrieval_latency_ms(scenario)
    time.sleep(latency / 1000)

    span.set_attribute("vantia.request_id", payload["request_id"])
    span.set_attribute("vantia.tenant", payload["tenant"])
    span.set_attribute("vantia.scenario", scenario)
    span.set_attribute("vantia.stage", "retrieve")
    span.set_attribute("vantia.docs_found", found)
    span.set_attribute("vantia.index", "kb-v3")

    payload["docs_found"] = found
    payload["otel"] = carrier()
    client.rpush(OUT_QUEUE, json.dumps(payload))

    event(
        logger,
        "knowledge base searched, context built",
        request_id=payload["request_id"],
        tenant=payload["tenant"],
        stage="retrieve",
        status="ok",
        scenario=scenario,
        docs_found=found,
        index="kb-v3",
        latency_ms=round((time.time() - started) * 1000, 2),
    )


def run():
    event(logger, "retrieval worker started", stage="boot", status="ok", queue=IN_QUEUE)
    while True:
        item = client.blpop(IN_QUEUE, timeout=5)
        if item is None:
            continue
        handle(json.loads(item[1]))
