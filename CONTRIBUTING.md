<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Contributing to Kite

Kite accepts focused fixes and improvements through GitHub pull requests.

## Guidelines

1. Keep each pull request scoped to one coherent change.
2. Rebase instead of adding merge commits.
3. Use Conventional Commits for commit messages.
4. Preserve existing AGPL/SPDX attribution and licence notices.
5. Add or update tests when behavior changes.
6. Run formatting, flutter analyze, and the relevant tests before requesting review.
7. Keep Kite-specific behavior separate enough that future upstream FluffyChat changes remain practical to integrate.

## Project structure

Application code lives under lib/, with platform integrations under android/, ios/, linux/, macos/, web/, and windows/.

The Matrix protocol implementation is primarily provided by matrix-dart-sdk. Prefer small, maintainable changes in Kite over duplicating SDK behavior.

## Reporting issues

Use https://github.com/brandonp2412/Kite/issues for bugs and feature requests. Security issues should follow SECURITY.md.
