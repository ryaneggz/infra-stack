#!/usr/bin/env python3
"""Prove operator arguments never become Make or shell recipe source."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SENTINEL = Path(f"/tmp/infra-stack-make-injection-{os.getpid()}")

CASES = {
    "backup-db": {"DB": "INFRA_ARG_DB"},
    "download-backup": {"NAME": "INFRA_ARG_NAME"},
    "restore-db": {"FILE": "INFRA_ARG_FILE", "TARGET": "INFRA_ARG_TARGET"},
    "restore-all": {"FILE": "INFRA_ARG_FILE", "CONTAINER": "INFRA_ARG_CONTAINER"},
    "reset": {"CONFIRM": "INFRA_CONFIRM_RESET"},
}


def payloads() -> list[str]:
    marker = str(SENTINEL)
    return [
        f"'; touch {marker}; #",
        f'"; touch {marker}; #',
        f";touch {marker};",
        f"$(touch {marker})",
        f"$(shell touch {marker})",
        f"`touch {marker}`",
        "value with whitespace",
        "../../../../etc/passwd",
    ]


def run_and_assert_blocked(command: list[str], environment: dict[str, str], label: str) -> None:
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        timeout=15,
    )
    if SENTINEL.exists():
        raise RuntimeError(f"command execution via {label}")
    if result.returncode == 0:
        raise RuntimeError(f"unsafe value accepted via {label}")


def main() -> int:
    SENTINEL.unlink(missing_ok=True)
    tested = 0
    base_environment = os.environ.copy()
    for target, variables in CASES.items():
        for legacy_name, environment_name in variables.items():
            for payload in payloads():
                # Legacy Make assignments fail during parse without expanding their values.
                run_and_assert_blocked(
                    ["make", "--no-print-directory", target, f"{legacy_name}={payload}"],
                    base_environment,
                    f"legacy {target} {legacy_name}={payload!r}",
                )
                tested += 1

                # Supported values travel unchanged through the inherited environment.
                environment = base_environment.copy()
                for required_environment_name in variables.values():
                    environment[required_environment_name] = "definitely-invalid"
                environment[environment_name] = payload
                run_and_assert_blocked(
                    ["make", "--no-print-directory", target],
                    environment,
                    f"environment {target} {environment_name}={payload!r}",
                )
                tested += 1
    print(f"Make argument security tests passed: {tested} adversarial invocations, no command execution")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
    finally:
        SENTINEL.unlink(missing_ok=True)
