# Kite icon showcase

This is deliberately not the Kite application. It is a minimal Android Java shell
whose ten product flavors exist only to make launcher-icon concepts installable
side-by-side.

Each flavor has:
- a unique package id: nz.presley.kite.icon01 through nz.presley.kite.icon10
- a unique launcher label: Kite Icon 01 through Kite Icon 10
- an adaptive icon using the padded artwork under assets/branding/icon_variants_safe
- the same tiny one-screen shell

Build all installable, minified APKs with:

    ./gradlew assembleRelease

The release variants intentionally use the local Android debug signing key because
these APKs are disposable design-test artifacts, not production Kite releases.
