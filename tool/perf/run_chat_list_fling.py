#!/usr/bin/env python3
"""Install the signed profile test, capture a fresh launch, restore release APK."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=180, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args}\n{result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def grade_report(report):
    flings = report.get('flings', [])
    if (report.get('schema_version') != 2 or len(flings) != 4
            or any(not f.get('valid') or any(
                type(f.get(key)) is not int or f[key] < 0
                for key in ('slow_frames', 'cadence_gap_count')) for f in flings)):
        return 2
    return 1 if any(f['slow_frames'] > 0 or f['cadence_gap_count'] > 0 for f in flings) else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--profile-apk', type=Path, default=Path('build/app/outputs/flutter-apk/app-profile.apk'))
    parser.add_argument('--restore-apk', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('build/perf-results'))
    args = parser.parse_args()
    for apk in (args.profile_apk, args.restore_apk):
        if not apk.is_file():
            parser.error(f'APK not found: {apk}')
    args.output.mkdir(parents=True, exist_ok=True)
    run_id = time.strftime('fresh-fling-%Y%m%d-%H%M%S')
    adb = ['adb', '-s', args.serial]
    # If replacement fails (including signing mismatch), stop without uninstalling.
    installed = run([*adb, 'install', '-r', str(args.profile_apk.resolve())])
    if 'Success' not in installed:
        raise RuntimeError(installed)
    port = None
    try:
        run([*adb, 'shell', 'am', 'force-stop', 'app.kite'])
        launch = run([*adb, 'shell', 'am', 'start', '-W', '-n', 'app.kite/.MainActivity'])
        (args.output / f'{run_id}-launch.txt').write_text(launch + '\n')
        uri = None
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            pid = run([*adb, 'shell', 'pidof', 'app.kite'])
            logs = run([*adb, 'logcat', '-d', '--pid', pid, '-s', 'flutter:I'])
            match = re.search(r'http://127\.0\.0\.1:(\d+)/(\S+)', logs)
            if match:
                port = run([*adb, 'forward', 'tcp:0', f'tcp:{match[1]}'])
                uri = f'http://127.0.0.1:{port}/{match[2]}'
                break
            time.sleep(.25)
        if uri is None:
            raise RuntimeError('No profile VM service found; see device logs')
        env = {**os.environ, 'KITE_PERF_RESULT_DIR': str(args.output.resolve()),
               'KITE_PERF_RUN_ID': run_id}
        with (args.output / f'{run_id}.log').open('w') as log:
            result = subprocess.run([
                'flutter', 'drive', '--no-pub', '--no-dds', '--profile',
                '--driver=test_driver/performance_driver.dart',
                '--target=integration_test/chat_list_fling_test.dart',
                f'--use-existing-app={uri}', '-d', args.serial,
            ], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        report = args.output / f'kite-perf-{run_id}.json'
        print(f'Report: {report}\nDriver log: {args.output / (run_id + ".log")}')
        if not report.is_file():
            raise RuntimeError('Missing frame report: this is not a passing measurement')
        # Some integration-driver versions report success even when the device
        # test failed. The saved frame results must also satisfy the gate.
        measurement = json.loads(report.read_text())
        grade = grade_report(measurement)
        print(json.dumps({'measurement_exit_code': grade,
                          'flings': measurement.get('flings', [])}, indent=2))
        return result.returncode or grade
    finally:
        try:
            if port:
                run([*adb, 'forward', '--remove', f'tcp:{port}'])
        finally:
            print('Restoring normal release APK, preserving app data.', flush=True)
            restored = run([*adb, 'install', '-r', str(args.restore_apk.resolve())])
            if 'Success' not in restored:
                raise RuntimeError(f'Release restore failed: {restored}')


if __name__ == '__main__':
    sys.exit(main())
