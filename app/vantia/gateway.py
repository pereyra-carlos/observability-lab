import json
import os
import time
import uuid

import redis
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .log import event, get_logger
from .simulate import TENANTS
from .tracing import carrier, tracer

logger = get_logger()
app = FastAPI(title="vantia-gateway")
client = redis.Redis.from_url(os.getenv("REDIS_URL", "redis://vantia-redis:6379/0"))

QUEUE = "q:retrieval"


class Ask(BaseModel):
    tenant: str
    question: str
    scenario: str = "normal"


@app.get("/healthz")
def healthz():
    client.ping()
    return {"status": "ok"}


@app.post("/ask")
def ask(body: Ask):
    started = time.time()
    request_id = uuid.uuid4().hex[:12]

    with tracer().start_as_current_span("gateway.ask") as span:
        span.set_attribute("vantia.request_id", request_id)
        span.set_attribute("vantia.tenant", body.tenant)
        span.set_attribute("vantia.scenario", body.scenario)
        span.set_attribute("vantia.stage", "accept")
        return _ask(body, request_id, started, span)


def _ask(body, request_id, started, span):
    if body.tenant not in TENANTS:
        span.set_attribute("vantia.status", "rejected")
        event(
            logger,
            "unknown tenant, request rejected",
            level=40,
            request_id=request_id,
            tenant=body.tenant,
            stage="validate",
            status="rejected",
            latency_ms=round((time.time() - started) * 1000, 2),
        )
        raise HTTPException(status_code=404, detail="unknown tenant")

    payload = {
        "request_id": request_id,
        "tenant": body.tenant,
        "question": body.question,
        "scenario": body.scenario,
        "t0": started,
        "otel": carrier(),
    }
    client.rpush(QUEUE, json.dumps(payload))

    event(
        logger,
        "question accepted and queued for retrieval",
        request_id=request_id,
        tenant=body.tenant,
        stage="accept",
        status="ok",
        scenario=body.scenario,
        queue=QUEUE,
        question_chars=len(body.question),
        latency_ms=round((time.time() - started) * 1000, 2),
    )
    return {"request_id": request_id}
