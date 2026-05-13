# Microsoft Entra Verified ID + Face Check + Entitlement Management POC

## Overview

This proof-of-concept demonstrates high-assurance employee onboarding by combining:

- **Entra Verified ID** — Issue and verify decentralized identity credentials
- **Face Check** — Liveness detection + government ID match via partner integration
- **Entitlement Management (ID Governance)** — Auto-assign access packages upon successful identity verification

## Scenario

New employees complete identity verification via a government ID + selfie (Face Check). Upon successful verification, they receive a Verified Employee credential. When they present this credential in the My Access portal, Entitlement Management automatically grants them their onboarding access package (apps, groups, sites).

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

| Phase | Duration |
|-------|----------|
| Prerequisites & partner setup | 1–2 days |
| Verified ID configuration | 1 day |
| Entitlement Management setup | 1 day |
| Integration & Face Check policy | 1 day |
| Testing & validation | 2–3 days |
| **Total** | **~1 week** |
