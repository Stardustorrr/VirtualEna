r"""Prototype local embedding retrieval for short-term memories.

Usage:
    .\.venv\Scripts\python.exe tools\embedding_memory_probe.py
    .\.venv\Scripts\python.exe tools\embedding_memory_probe.py "我摸了摸头"

The first run may download BAAI/bge-small-zh-v1.5 into the Hugging Face cache.
After that, embedding generation and retrieval reuse the local cache.
"""

from __future__ import annotations

import argparse
import time
from dataclasses import dataclass

import numpy as np
from sentence_transformers import SentenceTransformer


DEFAULT_MODEL = "BAAI/bge-small-zh-v1.5"


@dataclass(frozen=True)
class Memory:
    content: str
    strength: float
    recency: float


SAMPLE_MEMORIES = [
    Memory("玩家摸了摸 Ena 的头，Ena 有点害羞，但很开心。", 0.90, 0.95),
    Memory("玩家说今天会陪 Ena 一会儿，Ena 感到安心。", 0.82, 0.80),
    Memory("玩家离开前没有告别，Ena 有些失落。", 0.72, 0.70),
    Memory("Ena 看见窗外下雨，想起了安静的下午。", 0.45, 0.50),
    Memory("玩家夸 Ena 很可爱，Ena 的好感度上升。", 0.86, 0.65),
]


def cosine_similarity(query_embedding: np.ndarray, memory_embeddings: np.ndarray) -> np.ndarray:
    return memory_embeddings @ query_embedding


def activation(semantic_score: float, memory: Memory) -> float:
    semantic_score = max(0.0, semantic_score)
    return 0.60 * semantic_score + 0.25 * memory.strength + 0.15 * memory.recency


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="本地 embedding 短期记忆检索原型。")
    parser.add_argument(
        "event",
        nargs="?",
        default="我摸了摸头",
        help="当前事件/当前输入，默认：我摸了摸头",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"sentence-transformers 模型名，默认 {DEFAULT_MODEL}",
    )
    parser.add_argument("--top-k", type=int, default=3, help="输出前几条记忆，默认 3")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    load_started = time.perf_counter()
    model = SentenceTransformer(args.model)
    load_seconds = time.perf_counter() - load_started

    texts = [args.event, *[memory.content for memory in SAMPLE_MEMORIES]]
    embed_started = time.perf_counter()
    embeddings = model.encode(texts, normalize_embeddings=True)
    embed_seconds = time.perf_counter() - embed_started

    query_embedding = embeddings[0]
    memory_embeddings = embeddings[1:]
    semantic_scores = cosine_similarity(query_embedding, memory_embeddings)

    ranked = sorted(
        (
            (
                activation(float(score), memory),
                float(score),
                memory,
            )
            for score, memory in zip(semantic_scores, SAMPLE_MEMORIES)
        ),
        reverse=True,
        key=lambda item: item[0],
    )

    print(f"模型: {args.model}")
    print(f"当前事件: {args.event}")
    print(f"embedding 维度: {len(query_embedding)}")
    print(f"模型加载耗时: {load_seconds:.2f}s")
    print(f"生成 {len(texts)} 条 embedding 耗时: {embed_seconds:.2f}s")
    print()
    print("检索结果:")

    for index, (active_score, semantic_score, memory) in enumerate(ranked[: args.top_k], start=1):
        print(f"{index}. activation={active_score:.4f} semantic={semantic_score:.4f}")
        print(f"   strength={memory.strength:.2f} recency={memory.recency:.2f}")
        print(f"   {memory.content}")


if __name__ == "__main__":
    main()
