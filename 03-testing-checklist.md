# Testing Checklist: Verified ID + Face Check + Entitlement Management POC

## Pre-Testing Validation

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | Entra Suite license assigned to all 10 pilot users | ☐ | |
| 2 | Verified ID service enabled in tenant | ☐ | |
| 3 | DID document published and resolvable | ☐ | |
| 4 | ID verification partner configured and active | ☐ | |
| 5 | Face Check enabled with High confidence | ☐ | |
| 6 | VerifiedEmployee credential type created | ☐ | |
| 7 | Catalog "New Employee Onboarding" created | ☐ | |
| 8 | Access package "New Employee Starter Pack" created | ☐ | |
| 9 | Custom extension configured and linked to Logic App | ☐ | |
| 10 | Logic App deployed and functional | ☐ | |
| 11 | POC groups created (POC-AllEmployees, POC-Department-IT) | ☐ | |
| 12 | Microsoft Authenticator installed on pilot devices | ☐ | |
| 13 | Pilot users can access My Access portal | ☐ | |

---

## Test Scenarios

### Test 1: Credential Issuance — Happy Path

**Objective:** Verify that a pilot user can successfully receive a Verified Employee credential after government ID + Face Check.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Trigger issuance request for pilot user | QR code or push notification generated | ☐ |
| 2 | User opens Microsoft Authenticator | Issuance prompt displayed | ☐ |
| 3 | User scans/accepts the credential request | Redirected to ID verification partner | ☐ |
| 4 | User uploads government ID (front + back) | Document accepted and validated | ☐ |
| 5 | User completes liveness check (selfie + head movements) | Liveness confirmed | ☐ |
| 6 | Face Check matches selfie to ID photo | Match confidence: HIGH | ☐ |
| 7 | Credential issued to Authenticator wallet | VerifiedEmployee card visible in app | ☐ |

---

### Test 2: Credential Issuance — Face Mismatch

**Objective:** Verify that issuance fails when face does not match government ID.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Trigger issuance for a user with mismatched ID | Issuance request created | ☐ |
| 2 | User presents a different person's ID | Document processed | ☐ |
| 3 | User completes selfie | Face Check comparison runs | ☐ |
| 4 | Face match fails | Issuance denied with error message | ☐ |
| 5 | No credential in Authenticator | Wallet remains empty for this credential | ☐ |

> [!NOTE]
> For POC testing, use a stock photo printout to simulate mismatch. Do NOT use another person's real ID.

---

### Test 3: Access Package Request — Happy Path

**Objective:** Verify end-to-end flow from access request to resource assignment via Verified ID + Face Check.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | User navigates to https://myaccess.microsoft.com | My Access portal loads | ☐ |
| 2 | User finds "New Employee Starter Pack" | Package listed and requestable | ☐ |
| 3 | User selects "Request access" | Request created; custom extension triggered | ☐ |
| 4 | Logic App sends presentation request | Push notification in Authenticator | ☐ |
| 5 | User opens Authenticator and approves | Credential presentation initiated | ☐ |
| 6 | Face Check runs (live selfie) | Liveness + match passes | ☐ |
| 7 | Credential validated by Verified ID service | Claims verified, not expired | ☐ |
| 8 | Logic App returns APPROVED to Entitlement Management | Request status: Approved | ☐ |
| 9 | User added to POC-AllEmployees group | Group membership confirmed in Entra | ☐ |
| 10 | User added to POC-Department-IT group | Group membership confirmed | ☐ |
| 11 | Microsoft 365 apps accessible | User can open Office apps | ☐ |
| 12 | SharePoint site accessible | User can browse onboarding site | ☐ |

---

### Test 4: Access Package Request — Face Check Failure at Presentation

**Objective:** Verify that access is denied when Face Check fails during credential presentation.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | User requests access package | Custom extension triggered | ☐ |
| 2 | Another person attempts to present credential | Face Check runs | ☐ |
| 3 | Face does not match credential photo | Face Check fails | ☐ |
| 4 | Logic App returns DENIED | Request status: Denied | ☐ |
| 5 | User NOT added to any groups | No resource assignment | ☐ |
| 6 | Audit log shows denial reason | "Face Check failed" recorded | ☐ |

---

### Test 5: Expired Credential Presentation

**Objective:** Verify that an expired credential is rejected.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Set credential validity to short period (testing) | Credential expires | ☐ |
| 2 | User attempts to present expired credential | Presentation request sent | ☐ |
| 3 | Verified ID service rejects expired credential | Validation fails | ☐ |
| 4 | Access request denied | Request status: Denied | ☐ |

---

### Test 6: Revoked Credential

**Objective:** Verify that a revoked credential cannot be used for access.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Admin revokes a user's VerifiedEmployee credential | Credential marked as revoked | ☐ |
| 2 | User attempts to present revoked credential | Presentation request sent | ☐ |
| 3 | Verified ID checks revocation status | Credential rejected | ☐ |
| 4 | Access request denied | Request status: Denied | ☐ |

---

### Test 7: Conditional Access — Post-Verification Enforcement

**Objective:** Verify that the CA policy blocks access to onboarding apps for users who have NOT completed Verified ID + Face Check, and grants access to those who have.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Pilot user (NOT verified) attempts to access onboarding app | CA policy evaluates | ☐ |
| 2 | Check auth context c10 | Not present | ☐ |
| 3 | User is blocked or redirected | Sign-in log shows: Report-only: Failure | ☐ |
| 4 | User completes Verified ID + Face Check flow | Auth context c10 set | ☐ |
| 5 | User retries access to onboarding app | CA policy re-evaluates | ☐ |
| 6 | Auth context c10 found | Access granted | ☐ |
| 7 | Sign-in log shows: Report-only: Success | Policy applied correctly | ☐ |

---

### Test 8: Conditional Access — Break-Glass Exclusion

**Objective:** Verify that the break-glass account is excluded from CA policies.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Sign in as break-glass account | Authentication succeeds | ☐ |
| 2 | Access onboarding app | Access granted (no CA prompt) | ☐ |
| 3 | Check sign-in log | CA policy shows "Not applied" for break-glass | ☐ |

---

### Test 9: Conditional Access — Non-Pilot User Unaffected

**Objective:** Verify that users outside the pilot group are not affected by POC CA policies.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Sign in as a non-pilot user | Authentication succeeds normally | ☐ |
| 2 | Access onboarding app | Access granted (no Verified ID required) | ☐ |
| 3 | Check sign-in log | POC CA policies show "Not applied" | ☐ |

---

### Test 10: Audit and Compliance

**Objective:** Verify all activities are properly logged.

| Step | Action | Expected Result | Pass/Fail |
|------|--------|-----------------|-----------|
| 1 | Check Verified ID activity log | Issuance events logged with timestamps | ☐ |
| 2 | Check Verified ID activity log | Presentation events logged | ☐ |
| 3 | Check Entitlement Management requests | All requests visible with status | ☐ |
| 4 | Check Entra audit log | Group membership changes logged | ☐ |
| 5 | Check Logic App run history | All orchestration runs visible | ☐ |
| 6 | Verify Face Check data not persisted | No biometric data in any log | ☐ |

---

## Performance Benchmarks (POC Targets)

| Metric | Target | Actual |
|--------|--------|--------|
| Issuance completion time (user perspective) | < 3 minutes | |
| Face Check processing time | < 10 seconds | |
| Access package assignment after approval | < 5 minutes | |
| Logic App execution time | < 30 seconds | |
| End-to-end (request → resources available) | < 10 minutes | |

---

## Known Limitations for POC

- Face Check requires adequate lighting for selfie capture
- Government ID must not be expired
- Microsoft Authenticator must be version 6.2309+ (Android) or 6.7.4+ (iOS)
- Logic App consumption plan may have cold-start delay (~5 seconds)
- Credential revocation check may have propagation delay (up to 5 minutes)

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| POC Lead | | | |
| Security Admin | | | |
| Identity Admin | | | |
| IT Director | | | |
