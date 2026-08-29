import json
import os
import random
import time

import redis

from .log import event, get_logger
from .simulate import cost_usd, llm_latency_ms, token_counts
from .tracing import context_of, tracer

logger = get_logger()
client = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://vantia-redis:6379/0"))

IN_QUEUE = "q:llm"


def handle(payload):
    with tracer().start_as_current_span(
        "llm.generate", context=context_of(payload)
    ) as span:
        _handle(payload, span)


def _handle(payload, span):
    started = time.time()
    scenario = payload["scenario"]
    tokens_in, tokens_out = token_counts(scenario, payload["docs_found"])
    model = "large" if tokens_in > 1600 or scenario == "token_spike" else "small"
    latency = llm_latency_ms(scenario, tokens_out)
    time.sleep(latency / 1000)

    span.set_attribute("vantia.request_id", payload["request_id"])
    span.set_attribute("vantia.tenant", payload["tenant"])
    span.set_attribute("vantia.scenario", scenario)
    span.set_attribute("vantia.stage", "generate")
    span.set_attribute("vantia.model", model)
    span.set_attribute("vantia.tokens_in", tokens_in)
    span.set_attribute("vantia.tokens_out", tokens_out)
    span.set_attribute("vantia.cost_usd", cost_usd(model, tokens_in, tokens_out))

    if scenario == "tenant_error" and random.random() < 0.6:
        span.set_attribute("vantia.status", "error")
        span.set_attribute("vantia.error", "upstream_timeout")
        event(
            logger,
            "model call failed, giving up after retries",
            level=40,
            request_id=payload["request_id"],
            tenant=payload["tenant"],
            stage="generate",
            status="error",
            scenario=scenario,
            model=model,
            error="upstream_timeout",
            attempts=3,
            latency_ms=round((time.time() - started) * 1000, 2),
            total_ms=round((time.time() - payload["t0"]) * 1000, 2),
        )
        return

    event(
        logger,
        "answer generated and returned to the customer",
        request_id=payload["request_id"],
        tenant=payload["tenant"],
        stage="generate",
        status="ok",
        scenario=scenario,
        model=model,
        tokens_in=tokens_in,
        tokens_out=tokens_out,
        cost_usd=cost_usd(model, tokens_in, tokens_out),
        latency_ms=round((time.time() - started) * 1000, 2),
        total_ms=round((time.time() - payload["t0"]) * 1000, 2),
    )


def run():
    event(logger, "llm worker started", stage="boot", status="ok", queue=IN_QUEUE)
    while True:
        item = client.blpop(IN_QUEUE, timeout=5)
        if item is None:
            continue
        handle(json.loads(item[1]))
