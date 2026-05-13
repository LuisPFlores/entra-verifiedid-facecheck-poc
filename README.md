# Microsoft Entra Verified ID + Face Check + Entitlement Management POC

## Overview

This proof-of-concept demonstrates high-assurance employee onboarding by combining:

- **Entra Verified ID** — Issue and verify decentralized identity credentials
- **Face Check** — Liveness detection + government ID match via partner integration
- **Entitlement Management (ID Governance)** — Auto-assign access packages upon successful identity verification
- **Conditional Access with Authentication Context** — Enforce post-verification access controls using authentication context (`c10`) that gates onboarding apps until Verified ID + Face Check is completed

## Scenario

New employees complete identity verification via a government ID + selfie (Face Check). Upon successful verification, they receive a Verified Employee credential. When they present this credential in the My Access portal, Entitlement Management automatically grants them their onboarding access package (apps, groups, sites).

A **Conditional Access policy with authentication context** enforces that onboarding applications (Microsoft 365, SharePoint, LOB apps) are only accessible after the user has successfully presented their Verified ID with Face Check. Users who have not completed verification are blocked and redirected to the verification flow.

## Pilot Scope

- **Users:** 10 pilot users
- **Licensing:** Entra Suite
- **ID Verification Partner:** Government ID via approved partner (Onfido, CLEAR, Jumio, or AU10TIX)

## Contents

| File | Description |
|------|-------------|
| [01-configuration-guide.md](01-configuration-guide.md) | Step-by-step deployment guide |
| [02-architecture.md](02-architecture.md) | Architecture diagrams and data flows |
| [03-testing-checklist.md](03-testing-checklist.md) | Validation and testing procedures |
| [scripts/Deploy-VerifiedID.ps1](scripts/Deploy-VerifiedID.ps1) | Verified ID tenant setup |
| [scripts/Deploy-EntitlementManagement.ps1](scripts/Deploy-EntitlementManagement.ps1) | Access package configuration |
| [scripts/Deploy-ConditionalAccess.ps1](scripts/Deploy-ConditionalAccess.ps1) | CA policies (post-verification gate) |
| [scripts/Validate-Prerequisites.ps1](scripts/Validate-Prerequisites.ps1) | Prerequisites validation |

## Prerequisites

- Microsoft Entra Suite license (assigned to pilot users)
- Global Administrator or combined: Verified ID Administrator + Identity Governance Administrator
- Microsoft Authenticator app installed on pilot users' devices
- Contract with ID verification partner (trial account sufficient for POC)

## Timeline Estimate

## Conditional Access with Authentication Context

This POC uses a **Conditional Access authentication context** to enforce Verified ID as a prerequisite for accessing onboarding resources:

1. **Authentication context `c10`** — "Verified ID Face Check Completed" is created as a step-up requirement
2. **Custom authentication strength** — Requires phishing-resistant MFA (FIDO2, Windows Hello, or X.509 certificate) as the baseline
3. **CA Policy: Require Verified ID** — Targets the pilot group and authentication context `c10`; grants access only when the auth context is satisfied
4. **CA Policy: Block Without Verified ID** — Blocks access to onboarding apps for pilot users who haven't completed the Verified ID + Face Check flow
5. **Logic App integration** — After successful credential presentation with Face Check, the Logic App sets the authentication context claim, unlocking access

Both policies are deployed in **Report-only** mode first, then switched to **On** after validation.

> **Break-glass accounts are always excluded** from both CA policies to prevent lockout.

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| Prerequisites & partner setup | 1–2 days |
| Verified ID configuration | 1 day |
| Entitlement Management setup | 1 day |
| Conditional Access + auth context | 0.5 day |
| Integration & Face Check policy | 1 day |
| Testing & validation | 2–3 days |
| **Total** | **~1 week** |
