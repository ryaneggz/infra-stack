#!/usr/bin/env python3
"""Check documentation links and operator commands against the repository."""

from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
MARKDOWN = [ROOT / "README.md", ROOT / "CHANGELOG.md", ROOT / "CONTRIBUTING.md", *sorted((ROOT / "docs").glob("*.md"))]
MAKE_TARGETS = set(re.findall(r"^([a-zA-Z0-9_-]+):", (ROOT / "Makefile").read_text(), re.MULTILINE))
COMPOSE_SERVICES = set(re.findall(r"^  ([a-zA-Z0-9_-]+):$", (ROOT / "compose.yml").read_text(), re.MULTILINE))
COMPOSE_SERVICES |= set(re.findall(r"^  ([a-zA-Z0-9_-]+):$", (ROOT / "compose.clients.yml").read_text(), re.MULTILINE))


def check_links(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    for target in re.findall(r"(?<!!)\[[^]]+\]\(([^)]+)\)", text):
        target = target.strip().split("#", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:")):
            continue
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            errors.append(f"{path.relative_to(ROOT)}: missing link target {target}")
    return errors


def check_commands(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    for target in re.findall(r"(?:^|[;&|]\s*|`)(?:[A-Z_][A-Z0-9_]*=[^\s`]+\s+)*make\s+([a-zA-Z0-9_-]+)", text, re.MULTILINE):
        if target not in MAKE_TARGETS:
            errors.append(f"{path.relative_to(ROOT)}: unknown make target {target}")
    for script in re.findall(r"(?:^|[ `(])((?:\./)?scripts/[a-zA-Z0-9_./-]+\.sh)\b", text, re.MULTILINE):
        relative = script.removeprefix("./")
        if not (ROOT / relative).is_file():
            errors.append(f"{path.relative_to(ROOT)}: missing script {script}")
    for service in re.findall(r"docker compose (?:exec|logs)\s+(?:-T\s+)?([a-zA-Z0-9_-]+)", text):
        if service not in COMPOSE_SERVICES:
            errors.append(f"{path.relative_to(ROOT)}: unknown Compose service {service}")
    return errors


def main() -> int:
    errors: list[str] = []
    for path in MARKDOWN:
        text = path.read_text()
        errors.extend(check_links(path, text))
        errors.extend(check_commands(path, text))
    index = (ROOT / "docs" / "README.md").read_text()
    for path in MARKDOWN:
        if path.parent == ROOT / "docs" and path.name != "README.md" and f"]({path.name})" not in index:
            errors.append(f"docs/README.md: missing index entry for {path.name}")
    if errors:
        raise RuntimeError("documentation lint failed:\n" + "\n".join(errors))
    print(f"Documentation lint passed: {len(MARKDOWN)} files, links and commands resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
