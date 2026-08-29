import os
import random
import time

import requests

from .log import event, get_logger
from .simulate import TENANTS, pick_scenario

logger = get_logger()

GATEWAY = os.getenv("GATEWAY_URL", "http://vantia-gateway:8080")
RPS = float(os.getenv("LOADGEN_RPS", "0.5"))
WEIGHTS = [float(x) for x in os.getenv("LOADGEN_WEIGHTS", "88,5,5,2").split(",")]

QUESTIONS = [
    "how do I reset my password",
    "why was my invoice charged twice",
    "can I export my data to csv",
    "the integration stopped syncing yesterday",
    "how do I add a seat to my plan",
    "what does error VN-402 mean",
    "is there an audit log for admin actions",
]


def run():
    event(logger, "load generator started", stage="boot", status="ok", target=GATEWAY, rps=RPS)
    while True:
        tenant = random.choice(TENANTS)
        scenario = pick_scenario(WEIGHTS)
        body = {
            "tenant": tenant,
            "question": random.choice(QUESTIONS),
            "scenario": scenario,
        }
        try:
            r = requests.post(f"{GATEWAY}/ask", json=body, timeout=10)
            event(
                logger,
                "question sent",
                request_id=r.json().get("request_id"),
                tenant=tenant,
                stage="submit",
                status="ok",
                scenario=scenario,
                http_status=r.status_code,
            )
        except Exception as exc:
            event(
                logger,
                "could not reach the gateway",
                level=40,
                tenant=tenant,
                stage="submit",
                status="error",
                error=type(exc).__name__,
            )
        time.sleep(random.expovariate(RPS))
