#!/usr/bin/env python3
"""Validate readable fixed image tags and required Linux architectures."""

from __future__ import annotations

import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REQUIRED = {
    "POSTGRES_IMAGE",
    "REDIS_IMAGE",
    "MINIO_IMAGE",
    "AWS_CLI_IMAGE",
    "MONGO_IMAGE",
    "CLOUDBEAVER_IMAGE",
    "PGADMIN_IMAGE",
    "REDISINSIGHT_IMAGE",
    "MONGO_EXPRESS_IMAGE",
}


def load_images() -> dict[str, str]:
    images: dict[str, str] = {}
    for line in (ROOT / ".example.env").read_text().splitlines():
        match = re.fullmatch(r"([A-Z0-9_]+_IMAGE)=(\S+)", line)
        if match:
            images[match.group(1)] = match.group(2)
    if images.keys() != REQUIRED:
        raise RuntimeError(f"image variables differ: {sorted(images)} != {sorted(REQUIRED)}")
    return images


def repository_and_tag(reference: str) -> tuple[str, str]:
    if "@" in reference or reference.endswith(":latest") or ":" not in reference:
        raise RuntimeError(f"image must use a concise fixed tag, never a digest or latest: {reference}")
    repository, tag = reference.rsplit(":", 1)
    if not tag or tag == "latest":
        raise RuntimeError(f"non-fixed image tag: {reference}")
    if "/" not in repository:
        repository = f"library/{repository}"
    return repository, tag


def fetch_tag(repository: str, tag: str) -> dict[str, object]:
    url = f"https://hub.docker.com/v2/repositories/{repository}/tags/{tag}"
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "infra-stack-ci/1"})
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == 2:
                raise
            time.sleep(2**attempt)
    raise AssertionError("unreachable")


def main() -> int:
    images = load_images()
    compose_sources = (ROOT / "compose.yml").read_text() + (ROOT / "compose.clients.yml").read_text()
    for variable, reference in sorted(images.items()):
        if f"${{{variable}:-{reference}}}" not in compose_sources:
            raise RuntimeError(f"Compose default does not match .example.env: {variable}={reference}")
        repository, tag = repository_and_tag(reference)
        payload = fetch_tag(repository, tag)
        architectures = {
            item.get("architecture")
            for item in payload.get("images", [])
            if isinstance(item, dict) and item.get("os") == "linux"
        }
        missing = {"amd64", "arm64"} - architectures
        if missing:
            raise RuntimeError(f"{reference} lacks Linux manifests: {sorted(missing)}")
        print(f"PASS {reference}: linux/amd64, linux/arm64")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
