import os

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.propagate import extract, inject
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

ROLE = os.getenv("VANTIA_ROLE", "unknown")
ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")

_tracer = None


def setup():
    global _tracer
    if _tracer is not None:
        return _tracer
    if ENDPOINT:
        provider = TracerProvider(
            resource=Resource.create(
                {"service.name": f"vantia-{ROLE}", "service.namespace": "vantia"}
            )
        )
        provider.add_span_processor(
            BatchSpanProcessor(OTLPSpanExporter(endpoint=ENDPOINT, insecure=True))
        )
        trace.set_tracer_provider(provider)
    _tracer = trace.get_tracer(f"vantia.{ROLE}")
    return _tracer


def tracer():
    return setup()


def carrier():
    out = {}
    inject(out)
    return out


def context_of(payload):
    return extract(payload.get("otel") or {})


def ids():
    ctx = trace.get_current_span().get_span_context()
    if not ctx.is_valid:
        return {}
    return {"trace_id": format(ctx.trace_id, "032x"), "span_id": format(ctx.span_id, "016x")}
