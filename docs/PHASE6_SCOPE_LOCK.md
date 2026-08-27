# Phase 6 Scope Lock

Phase 6 implements:

- durable offline state and protected metadata;
- Widevine and FairPlay persistent-license coordinators;
- route-neutral transport ownership, AirPlay, and optional Cast adapter boundaries;
- codec inventory and signed Android profile infrastructure;
- certification schemas, evidence generation, secret scanning, and release gates.

Provider-specific credentials and physical-device certification evidence are external inputs. The generic runtime must remain provider-neutral and must not expose raw DRM material across the React Native boundary.
