# Phase 5 — Predictive runtime and diagnostics

Phase 5 converts Phase 4's reactive policies into a predictive control loop while keeping all high-frequency work native.

## Completion tracks

1. **Bandwidth prediction** — FastCore EWMA prediction, volatility and confidence; ABR consumes the prediction rather than one noisy platform sample.
2. **Viewport intent** — C++ scroll-velocity prediction shifts native preload pressure toward the likely destination without rebuilding the list in JS.
3. **Multi-CDN health** — per-origin reliability/TTFF health scoring reorders fallback candidates; diagnostics expose only origins, never paths/query tokens.
4. **Frame diagnostics** — platform observations feed native frame-processing and dropped-frame telemetry so renderer pressure is visible before stalls occur.
5. **Benchmark lab** — predictive regression gates plus a physical-device result schema/gate. Sample fixtures are explicitly synthetic.

Codec forcing, custom decoders, and offline DRM licenses are not claimed in this phase because they require device/provider-specific certification rather than portable heuristics.
