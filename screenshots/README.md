# Kite screenshot suite

All screenshots are genuine Kite Android captures with fictional Matrix accounts, messages and media. The generator captures both themes, then selects exactly eight images for Fastlane. The app draws every message, reaction, emoji, menu and system bar; no renderer recreates its UI.

## Recreate on Glass

Start a disposable Synapse bound only to Waydroid's network (replace the temporary directory if required):

```sh
mkdir -p /tmp/kite-screenshots-synapse
docker run --rm -e SYNAPSE_SERVER_NAME=kite-screenshots.test -e SYNAPSE_REPORT_STATS=no -v /tmp/kite-screenshots-synapse:/data matrixdotorg/synapse:latest generate
docker run -d --name kite-screenshots-synapse -p 192.168.240.1:18887:8008 -v /tmp/kite-screenshots-synapse:/data matrixdotorg/synapse:latest
python3 scripts/screenshot_fixture.py --config /tmp/kite-screenshots-synapse/homeserver.yaml --output /tmp/kite-fixture-login.json
```

Seed a fresh server **once**; repeating the seeder would create duplicate rooms. `rsvg-convert` is needed to generate its fictional artwork. The login JSON contains dummy account credentials and must stay private.

Build with `/home/brandon/.local/bin/buildq --wait -- ./gradlew :androidApp:assemblePerfDebug -PandroidAbi=x86 --offline --no-daemon`, install the resulting APK onto the isolated Waydroid device, and sign into `http://192.168.240.1:18887` as `taylor` using the password in that JSON. Do not capture or sign into a production Matrix account.

```sh
python3 scripts/generate_screenshots.py --device 192.168.240.112:5555
python3 scripts/generate_screenshots.py --verify
```

The first command captures all states in `screenshots/generated/native/`, writes [the gallery](index.html) and `native-manifest.json`, then updates eight ordered `metadata/en-US/images/phoneScreenshots/` PNGs. `--curate-only` reselects eight existing captures. `--verify` checks image hashes and Fastlane identity without needing Android (also used by release CI).

Coverage includes the inbox, account switcher, settings categories, direct and group chats, reaction popups and full emoji picker, message selection/actions/reply, media, attachments, search, member details and themes. Captures represent actual supported app states; unavailable features are not fabricated.
