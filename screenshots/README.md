# Kite screenshot scenarios

`python3 scripts/generate_screenshots.py` renders 98 deterministic, fictional UI states (49 scenarios × light/dark) to `screenshots/generated/` and curates exactly eight for `metadata/en-US/images/phoneScreenshots/`.

Coverage: inbox filters, pinned/unread/empty/offline/syncing, direct and group chats, reactions, media/video/voice/files, polls, replies, selection, typing, send failure, search modes, settings, multiple accounts, room details and members, onboarding and sign-in.

Use `--store-only` to update the eight curated images. Change `CURATED` in the generator to choose a different selection. Browse the local searchable gallery at [index.html](index.html). The PNG library is ignored by Git but uploaded as a downloadable release workflow artifact. All content is illustrative—not screenshots of actual app state.

Emoji artwork: Kite-designed reaction glyphs mirror the Compose shapes in `KiteReactionGlyph.kt`; inline emoji PNGs are rendered from Kite’s bundled Noto Color Emoji font. No live content is used.
