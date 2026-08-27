# Phase 6 Implementation Status

> **Authoritative PR:** #6  
> **Status:** draft — consolidation complete; Phase 6 runtime implementation has not started  
> **Last audited:** 2026-08-27  
> **Supersedes:** #4 and #5

## Consolidation result

- PRs #4 and #5 point to the same head commit (`ad5fc482f395b8df49229b6afd170236fca2ac81`). Their apparent size difference comes from different base branches.
- The reviewed Phase 6 master plan, API proposal, threat model, certification matrix, decision register, implementation backlog, and roadmap updates are already present on `main`.
- The only branch change from #4/#5 that was not already on `main` was `.github/workflows/export-phase6-source.yml`.
- That workflow is preserved here in consolidated form: strict shell failure handling and the established `phase6-source` artifact name from #4/#5, combined with a deterministic tracked-files-only `git archive` implementation from #6.
- #4 and #5 contained no Phase 6 runtime, native, C++, TypeScript, Cast-package, test-lab, or certification implementation that needed to be cherry-picked.

## What exists on this branch

- the merged Phase 1–5 hardening baseline;
- the approved Phase 6 planning documents already inherited from `main`;
- a scope lock;
- a deterministic source-export workflow;
- this auditable readiness record.

## What does not yet exist

The implementation packages P6-01 through P6-72 remain unlanded, including:

- durable offline schemas, transition validators, protected storage, redaction, and provider contracts;
- Android Widevine acquire/query/renew/release and atomic media/license reconciliation;
- Apple FairPlay persistable-key lifecycle and atomic asset/key reconciliation;
- the unified public offline API and account/logout/delete policy implementation;
- codec inventory, signed exact-device profiles, Android selector policy, and Apple pipeline diagnostics;
- route-neutral ownership, AirPlay integration, optional Cast packaging, sender runtimes, and receiver authorization fixture;
- physical-device lab harnesses, deterministic DRM/fault fixtures, evidence schemas, statistical reports, SBOM/provenance, and release attestations;
- Phase 6-specific contract, security, restart, fault-injection, native integration, provider, route, and physical-device tests.

## Merge-readiness gates

| Gate | State | Required before ready for review |
|---|---|---|
| Phase 1–5 baseline ancestry | Met | Keep rebased/merged with `main`. |
| Existing host CI | Baseline green | Re-run after every Phase 6 source change; baseline CI alone does not certify Phase 6. |
| Planning corpus | Met | Preserve the reviewed master plan, API, threat model, matrix, decisions, and backlog. |
| P6-D2xx/P6-D3xx/P6-D4xx decisions | **Blocked** | Accept the decisions required by the declared beta scope through reviewed ADRs. |
| Beta scope and ownership | **Blocked** | Approve P6-D217; assign owners/issues for each included work package. |
| Runtime implementation | **Blocked** | Land the dependency-ordered P6 work packages with rollback/feature flags. |
| Phase 6 CI and security gates | **Blocked** | Add and pass Phase 6 contract, native, restart, corruption, redaction, secret-scan, fixture, package, and evidence tests. |
| Real DRM providers | **External blocker** | Select Widevine/FairPlay providers, test accounts, credential rotation, and responsible owners. |
| Cast receiver and packaging | **Blocked** | Resolve receiver ownership and optional dependency packaging before sender implementation. |
| Physical-device certification | **External blocker** | Run the frozen DRM/HDR/route/decoder/power/thermal matrix on named devices and receivers. |
| Evidence and release integrity | **Blocked** | Produce raw evidence, hashes, SBOM, provenance attestations, claim-policy validation, and independent verification. |
| Review and branch governance | **Blocked** | Require reviewers/status checks and resolve all review threads before merge. |

## Authoritative-PR policy

PR #6 is the single integration and readiness record for Phase 6. It must remain a draft until the declared beta scope is implemented and the applicable gates above are green.

The authoritative PR does **not** override the backlog's review discipline. Work packages should still arrive in dependency order as reviewable commits or focused child PRs targeting this branch; #6 becomes mergeable only after those changes are integrated and independently verifiable.
