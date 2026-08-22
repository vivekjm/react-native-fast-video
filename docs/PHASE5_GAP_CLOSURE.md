# Phase 5 gap-closure pass

This branch closes correctness, parity, packaging, lifecycle, test, and CI gaps discovered after publishing the Phase 1–5 source tree.

The release gate is deliberately stricter than the previous source-smoke checks:

- TypeScript API and web fallback type-check against the public contract.
- Android and Apple module APIs have matching commands and events.
- Native player/session accounting cannot double-count pooled or background players.
- Preload intent radii are actually applied by both native runtimes.
- Offline non-DRM downloads correctly retain request metadata and authenticated headers where the platform supports it.
- C++ counters saturate safely and QoE does not report a perfect score before first frame.
- Package, Gradle, podspec, user-agent, changelog, and docs versions agree.
- CI validates package contents and platform generation, not only parser-level syntax.
