# F-Droid submission

`../metadata/app.kite.yml` is the proposed upstream F-Droid recipe. Copy it to
`fdroiddata/metadata/app.kite.yml` for the official F-Droid merge request.

The recipe uses the complete checked-in Matrix Rust SDK Git submodule, pins the
Rust and cargo-ndk tools, builds the arm64 release from source, excludes the
machine-specific Maven local cache, and asks F-Droid to verify the signed
GitHub APK against its own unsigned build. F-Droid should distribute the
existing upstream-signed APK **only if reproducible verification passes**.

Prerequisites before submitting:

1. Merge this source change into main and create the `1.0.95` source tag on that
   exact commit. The GitHub release workflow must publish
   `Kite-1.0.95-arm64-v8a.apk` using the existing certificate.
2. Validate the source-only build in an F-Droid buildserver environment with
   `fdroid readmeta`, `fdroid lint app.kite`, and `fdroid build app.kite`.
3. Compare the unsigned build and GitHub signed APK via F-Droid's reproducible
   verification and ensure the signature fingerprint is the exact expected one.
4. Fork `fdroid/fdroiddata`, copy the recipe, and open the F-Droid metadata MR.

Do not accept an F-Droid-signed replacement silently: it would use a different
signer and not update existing Kite installations in place. The F-Droid
buildserver must never use the private Kite release signing key.

For testing on Glass, the developer's Gradle init scripts may inject the local
release signer even without `KITE_RELEASE_*` environment variables. A build on
Glass is therefore **not** independent proof of an unsigned F-Droid build.
