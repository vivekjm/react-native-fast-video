# Contributing

- Keep decoding, adaptation and high-frequency work native.
- Add a benchmark or measurement plan for performance changes.
- Do not add per-frame JavaScript callbacks.
- Label device/OS-dependent behavior explicitly.
- Add deterministic FastCore tests for state or metric changes.
- Avoid unrelated formatting changes in native files.

Before opening a PR:

```bash
npm run typecheck
npm run test:core
npm run benchmark:sample
```
