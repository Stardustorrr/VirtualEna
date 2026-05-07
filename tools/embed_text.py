"""Generate normalized sentence embeddings as JSON.

Input JSON on stdin:
{"texts":["..."],"model":"BAAI/bge-small-zh-v1.5"}

Output JSON on stdout:
{"ok":true,"model":"...","dimension":512,"embeddings":[[...]]}

Server mode:
python tools/embed_text.py --server --model BAAI/bge-small-zh-v1.5
Then write one JSON object per line to stdin: {"texts":["..."]}
The process writes one JSON object per line to stdout.
"""

from __future__ import annotations

import json
import argparse
import sys
from typing import Any

from sentence_transformers import SentenceTransformer


DEFAULT_MODEL = "BAAI/bge-small-zh-v1.5"


def encode_payload(model: SentenceTransformer, model_name: str, payload: dict[str, Any]) -> dict[str, Any]:
    texts = payload.get("texts") or []
    if not isinstance(texts, list) or not all(isinstance(text, str) for text in texts):
        raise ValueError("texts must be a list of strings")

    embeddings = model.encode(texts, normalize_embeddings=True)
    serializable = embeddings.astype(float).tolist()
    dimension = len(serializable[0]) if serializable else 0
    return {
        "ok": True,
        "model": model_name,
        "dimension": dimension,
        "embeddings": serializable,
    }


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def run_server(model_name: str) -> int:
    try:
        model = SentenceTransformer(model_name, local_files_only=True)
        emit({"ok": True, "ready": True, "model": model_name})
    except Exception as exc:
        emit({"ok": False, "ready": False, "error": f"{type(exc).__name__}: {exc}"})
        return 1

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line == "__quit__":
            emit({"ok": True, "quit": True})
            return 0
        try:
            payload = json.loads(line)
            emit(encode_payload(model, model_name, payload))
        except Exception as exc:  # pragma: no cover - command-line diagnostics
            emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", action="store_true")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()

    if args.server:
        return run_server(args.model)

    try:
        payload: dict[str, Any] = json.load(sys.stdin)
        model_name = payload.get("model") or args.model
        model = SentenceTransformer(model_name, local_files_only=True)
        emit(encode_payload(model, model_name, payload))
        return 0
    except Exception as exc:  # pragma: no cover - command-line diagnostics
        emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
