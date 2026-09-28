#!/usr/bin/env python3
"""Run Kite profile-mode performance scenarios repeatedly on Nox Waydroid."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from pathlib import Path
from typing import IO, Iterator

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "integration_test/performance/fixtures/real_chat_shape.json"
SEEDER = ROOT / "tool/perf/seed_synapse.py"
DEFAULT_STATE_DIR = Path.home() / ".local/state/kite-perf"
DEFAULT_RESULT_DIR = Path.home() / ".local/state/kite-perf/results"
SYNAPSE_PYTHON = Path("/opt/matrix/synapse-venv/bin/python")
REGISTER_USER = Path("/opt/matrix/synapse-venv/bin/register_new_matrix_user")
SERVER_NAME = "kite-perf.test"
ADMIN_USER = "perf"
PASSWORD = "kite-perf-local-only"
WAYDROID_IP = "192.168.240.2"
WAYDROID_HOST_IP = "192.168.240.1"
PERF_PACKAGE = "app.kite.perf"


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    capture: bool = False,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        env=env,
        check=check,
        text=True,
        capture_output=capture,
        timeout=timeout,
    )


def fixture_hash() -> str:
    return hashlib.sha256(FIXTURE.read_bytes()).hexdigest()


def wait_http(url: str, timeout: float = 60.0) -> None:
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                if 200 <= response.status < 300:
                    return
        except Exception as error:  # noqa: BLE001 - surfaced after retry window
            last_error = error
        time.sleep(0.5)
    raise RuntimeError(f"timed out waiting for {url}: {last_error}")


def patch_synapse_config(config: Path) -> None:
    text = config.read_text(encoding="utf-8")
    text = text.replace(
        "  - bind_addresses:\n    - ::1\n    - 127.0.0.1\n",
        "  - bind_addresses:\n    - 0.0.0.0\n",
    )
    text = re.sub(
        r"trusted_key_servers:\n(?:  - .*\n(?:    .*\n)*)?",
        "trusted_key_servers: []\n",
        text,
        count=1,
    )
    config.write_text(text, encoding="utf-8")


def ensure_synapse_config(synapse_dir: Path) -> Path:
    config = synapse_dir / "homeserver.yaml"
    if config.exists():
        return config
    synapse_dir.mkdir(parents=True, exist_ok=True)
    if not SYNAPSE_PYTHON.exists():
        raise RuntimeError(f"Synapse runtime missing: {SYNAPSE_PYTHON}")
    run(
        [
            str(SYNAPSE_PYTHON),
            "-m",
            "synapse.app.homeserver",
            "--generate-config",
            "-H",
            SERVER_NAME,
            "-c",
            str(config),
            "--report-stats=no",
        ],
        cwd=synapse_dir,
    )
    patch_synapse_config(config)
    return config


def seed_marker(state_dir: Path) -> Path:
    return state_dir / "synapse" / "kite-perf-seed.json"


def reset_stale_state_if_needed(state_dir: Path, force_reset: bool) -> bool:
    marker = seed_marker(state_dir)
    reset = force_reset
    if marker.exists() and not reset:
        try:
            existing = json.loads(marker.read_text(encoding="utf-8"))
            reset = existing.get("fixtureSha256") != fixture_hash()
        except (OSError, json.JSONDecodeError):
            reset = True
    if reset:
        shutil.rmtree(state_dir / "synapse", ignore_errors=True)
    return reset


def start_synapse(state_dir: Path) -> tuple[subprocess.Popen[str], Path]:
    synapse_dir = state_dir / "synapse"
    config = ensure_synapse_config(synapse_dir)
    log_path = state_dir / "synapse.log"
    log_file = log_path.open("a", encoding="utf-8")
    process = subprocess.Popen(
        [
            str(SYNAPSE_PYTHON),
            "-m",
            "synapse.app.homeserver",
            "--config-path",
            str(config),
        ],
        cwd=synapse_dir,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        wait_http("http://127.0.0.1:8008/_matrix/client/versions", timeout=90)
    except Exception:
        process.terminate()
        process.wait(timeout=10)
        log_file.close()
        raise
    return process, config


def ensure_admin(config: Path) -> None:
    login_body = json.dumps(
        {
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": ADMIN_USER},
            "password": PASSWORD,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:8008/_matrix/client/v3/login",
        method="POST",
        data=login_body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status == 200:
                return
    except urllib.error.HTTPError:
        pass

    result = run(
        [
            str(REGISTER_USER),
            "-c",
            str(config),
            "-u",
            ADMIN_USER,
            "-p",
            PASSWORD,
            "-a",
            "http://127.0.0.1:8008",
        ],
        check=False,
        capture=True,
        timeout=30,
    )
    if result.returncode != 0:
        combined = f"{result.stdout}\n{result.stderr}".lower()
        if "already" not in combined and "taken" not in combined and "exists" not in combined:
            raise RuntimeError(f"failed to register perf admin: {combined[-1200:]}")


def ensure_seeded(state_dir: Path) -> None:
    run(
        [
            sys.executable,
            str(SEEDER),
            "--fixture",
            str(FIXTURE),
            "--marker",
            str(seed_marker(state_dir)),
            "--base-url",
            "http://127.0.0.1:8008",
            "--server-name",
            SERVER_NAME,
            "--admin-user",
            ADMIN_USER,
            "--password",
            PASSWORD,
        ],
        cwd=ROOT,
        timeout=1800,
    )


def adb_devices() -> list[tuple[str, str]]:
    result = run(["adb", "devices", "-l"], capture=True, check=False)
    devices: list[tuple[str, str]] = []
    for line in result.stdout.splitlines()[1:]:
        if "\tdevice" not in line:
            continue
        serial = line.split()[0]
        devices.append((serial, line))
    return devices


def waydroid_serial() -> str | None:
    for serial, line in adb_devices():
        if "model:WayDroid" in line:
            return serial
    return None


def waydroid_running() -> bool:
    result = run(["waydroid", "status"], capture=True, check=False)
    return "Session:\tRUNNING" in result.stdout or "Session: RUNNING" in result.stdout


def start_waydroid_session(state_dir: Path) -> subprocess.Popen[str] | None:
    if waydroid_running():
        return None
    log = (state_dir / "waydroid-session.log").open("a", encoding="utf-8")
    process = subprocess.Popen(
        ["waydroid", "session", "start"],
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if waydroid_running():
            return process
        if process.poll() is not None:
            break
        time.sleep(1)
    raise RuntimeError("Waydroid session failed to start; see waydroid-session.log")


def enable_waydroid_adb() -> None:
    commands = [
        ["waydroid", "shell", "setprop", "service.adb.tcp.port", "5555"],
        ["waydroid", "shell", "stop", "adbd"],
        ["waydroid", "shell", "start", "adbd"],
    ]
    for command in commands:
        run(command, check=False, timeout=15)


def connect_waydroid_adb(timeout: float = 45.0) -> str:
    existing = waydroid_serial()
    if existing:
        return existing

    enable_waydroid_adb()
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        run(["adb", "connect", f"{WAYDROID_IP}:5555"], check=False, capture=True, timeout=5)
        existing = waydroid_serial()
        if existing:
            return existing
        time.sleep(1)
    devices = "\n".join(line for _, line in adb_devices())
    raise RuntimeError(f"Waydroid ADB device unavailable; connected devices:\n{devices}")


def verify_waydroid(serial: str) -> None:
    result = run(
        ["adb", "-s", serial, "shell", "getprop", "ro.product.model"],
        capture=True,
        timeout=10,
    )
    if "WayDroid" not in result.stdout:
        raise RuntimeError(f"refusing non-Waydroid device {serial}: {result.stdout.strip()}")


@contextmanager
def device_lock(serial: str, wait_seconds: float) -> Iterator[None]:
    safe_serial = re.sub(r"[^A-Za-z0-9._-]", "_", serial)
    path = Path(f"/tmp/kite-waydroid-{safe_serial}.lock")
    lock: IO[str] = path.open("w", encoding="utf-8")
    deadline = time.monotonic() + wait_seconds
    while True:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                lock.close()
                raise RuntimeError(f"timed out waiting for exclusive Waydroid access: {serial}")
            time.sleep(0.25)
    try:
        yield
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()


def clear_perf_app_data(serial: str) -> None:
    run(
        ["adb", "-s", serial, "shell", "pm", "clear", PERF_PACKAGE],
        check=False,
        capture=True,
        timeout=20,
    )


def capture_failure(serial: str, result_dir: Path, run_id: str) -> None:
    logcat = run(
        ["adb", "-s", serial, "logcat", "-d", "-t", "1000"],
        check=False,
        capture=True,
        timeout=30,
    )
    (result_dir / f"{run_id}-logcat.txt").write_text(
        logcat.stdout + "\n" + logcat.stderr,
        encoding="utf-8",
    )
    screenshot = subprocess.run(
        ["adb", "-s", serial, "exec-out", "screencap", "-p"],
        check=False,
        capture_output=True,
        timeout=30,
    )
    if screenshot.returncode == 0 and screenshot.stdout.startswith(b"\x89PNG"):
        (result_dir / f"{run_id}-failure.png").write_bytes(screenshot.stdout)


def append_summary(
    result_dir: Path,
    *,
    run_id: str,
    returncode: int,
    elapsed_seconds: float,
    result_file: Path,
) -> None:
    record: dict[str, object] = {
        "runId": run_id,
        "returncode": returncode,
        "elapsedSeconds": round(elapsed_seconds, 3),
        "resultFile": str(result_file),
        "hostLoad": list(os.getloadavg()),
        "unixTime": int(time.time()),
    }
    if result_file.exists():
        try:
            record["performance"] = json.loads(result_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            record["resultParseError"] = True
    with (result_dir / "soak-summary.jsonl").open("a", encoding="utf-8") as output:
        output.write(json.dumps(record, separators=(",", ":")) + "\n")


def run_iteration(
    *,
    flutter: str,
    serial: str,
    result_dir: Path,
    iteration: int,
) -> int:
    run_id = time.strftime("%Y%m%d-%H%M%S") + f"-{iteration:04d}"
    result_file = result_dir / f"kite-perf-{run_id}.json"
    log_file = result_dir / f"{run_id}.log"

    env = os.environ.copy()
    env.update(
        {
            "ORG_GRADLE_PROJECT_kitePerfBuild": "true",
            "KITE_PERF_RESULT_DIR": str(result_dir),
            "KITE_PERF_RUN_ID": run_id,
        }
    )
    command = [
        flutter,
        "drive",
        "--profile",
        "--driver=test_driver/performance_driver.dart",
        "--target=integration_test/performance_test.dart",
        "-d",
        serial,
        f"--dart-define=HOMESERVER={WAYDROID_HOST_IP}:8008",
        f"--dart-define=USER1_NAME={ADMIN_USER}",
        f"--dart-define=USER1_PW={PASSWORD}",
        f"--dart-define=KITE_PERF_RUN_ID={run_id}",
    ]

    start = time.monotonic()
    with log_file.open("w", encoding="utf-8") as log:
        process = subprocess.run(
            command,
            cwd=ROOT,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
    elapsed = time.monotonic() - start

    if process.returncode != 0:
        capture_failure(serial, result_dir, run_id)
    append_summary(
        result_dir,
        run_id=run_id,
        returncode=process.returncode,
        elapsed_seconds=elapsed,
        result_file=result_file,
    )
    return process.returncode


def stop_process(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=float, default=8.0)
    parser.add_argument("--iterations", type=int, default=0)
    parser.add_argument("--sleep-seconds", type=float, default=5.0)
    parser.add_argument("--state-dir", type=Path, default=DEFAULT_STATE_DIR)
    parser.add_argument("--result-dir", type=Path, default=DEFAULT_RESULT_DIR)
    parser.add_argument("--device")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--lock-wait-seconds", type=float, default=120.0)
    parser.add_argument("--reset-fixture", action="store_true")
    parser.add_argument("--reset-app-data", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--fail-fast", action="store_true")
    args = parser.parse_args()

    if not FIXTURE.exists():
        raise RuntimeError(f"missing anonymized fixture: {FIXTURE}")

    args.state_dir.mkdir(parents=True, exist_ok=True)
    args.result_dir.mkdir(parents=True, exist_ok=True)

    reset_state = reset_stale_state_if_needed(args.state_dir, args.reset_fixture)
    synapse_process: subprocess.Popen[str] | None = None
    waydroid_process: subprocess.Popen[str] | None = None
    try:
        synapse_process, config = start_synapse(args.state_dir)
        ensure_admin(config)
        ensure_seeded(args.state_dir)

        if args.prepare_only:
            print("performance fixture prepared successfully")
            return 0

        waydroid_process = start_waydroid_session(args.state_dir)
        serial = args.device or connect_waydroid_adb()
        verify_waydroid(serial)

        with device_lock(serial, args.lock_wait_seconds):
            if reset_state or args.reset_app_data:
                clear_perf_app_data(serial)

            deadline = time.monotonic() + max(0.0, args.hours) * 3600
            iteration = 0
            failures = 0
            while True:
                if args.iterations > 0 and iteration >= args.iterations:
                    break
                if args.iterations == 0 and time.monotonic() >= deadline:
                    break

                iteration += 1
                print(f"[kite-perf] iteration {iteration} on {serial}")
                returncode = run_iteration(
                    flutter=args.flutter,
                    serial=serial,
                    result_dir=args.result_dir,
                    iteration=iteration,
                )
                if returncode != 0:
                    failures += 1
                    print(f"[kite-perf] iteration {iteration} failed with {returncode}")
                    if args.fail_fast:
                        return returncode
                else:
                    print(f"[kite-perf] iteration {iteration} passed")

                if args.iterations == 0 and time.monotonic() >= deadline:
                    break
                time.sleep(max(0.0, args.sleep_seconds))

            print(f"[kite-perf] completed {iteration} iterations with {failures} failures")
            return 0 if failures == 0 else 1
    finally:
        stop_process(synapse_process)
        # Intentionally leave Waydroid running. Nox shares it with other device
        # workflows, and the exclusive lock is released when this process exits.


if __name__ == "__main__":
    raise SystemExit(main())
