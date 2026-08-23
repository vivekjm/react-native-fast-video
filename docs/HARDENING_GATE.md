# Phase 1–5 hardening release gate

This file defines the merge boundary before Phase 6 begins.

Required gates:

- clean lockfile installation;
- source-claim audit;
- TypeScript typecheck and declaration build;
- public API contract checks;
- npm package-content validation;
- deterministic FastCore and C API edge tests;
- benchmark, QoE, predictive and device-result schema gates;
- Swift parser and podspec validation;
- Expo Android prebuild plus Gradle debug assembly;
- Expo iOS prebuild plus CocoaPods integration.

Physical-device 4K/HDR/DRM, power, thermal and competitor certification remain Phase 6 and are not inferred from host CI.
