import json
import logging
import os
import sys
import time

from .tracing import ids

SERVICE = os.getenv("VANTIA_ROLE", "unknown")


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + ".%03dZ" % record.msecs,
            "level": record.levelname.lower(),
            "service": SERVICE,
            "msg": record.getMessage(),
        }
        payload.update(ids())
        payload.update(getattr(record, "fields", {}))
        return json.dumps(payload, separators=(",", ":"))


def get_logger():
    logger = logging.getLogger("vantia")
    if logger.handlers:
        return logger
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger


def event(logger, msg, level=logging.INFO, **fields):
    logger.log(level, msg, extra={"fields": fields})
