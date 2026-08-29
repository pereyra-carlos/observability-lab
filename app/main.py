import os
import sys

ROLE = os.getenv("VANTIA_ROLE", "")

if ROLE == "retrieval":
    from vantia.retrieval import run

    run()
elif ROLE == "llm-worker":
    from vantia.llm_worker import run

    run()
elif ROLE == "loadgen":
    from vantia.loadgen import run

    run()
else:
    print(f"unknown VANTIA_ROLE: {ROLE!r}", file=sys.stderr)
    sys.exit(1)
