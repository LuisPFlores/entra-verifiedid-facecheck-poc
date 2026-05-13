# Configuration Guide: Verified ID + Face Check + Entitlement Management

## Phase 1: Configure Entra Verified ID Service

### Step 1.1: Enable Verified ID in Your Tenant

1. Navigate to **Microsoft Entra admin center** > **Verification solutions** > **Verified ID**
2. Select **Get started**
3. Choose **Set up Verified ID using quick setup** (recommended for POC)
   - This auto-creates a DID (Decentralized Identifier) for your tenant
   - Uses the `did:web` method anchored to your tenant domain
4. Confirm the domain displayed matches your tenant primary domain
5. Select **Save**

> [!NOTE]
> Quick setup uses Microsoft as the trust system. For production, you may want manual setup with a custom domain.

### Step 1.2: Verify Domain Ownership

1. In **Verified ID** > **Organization settings**, verify your domain is listed
2. If domain verification is required:
   - Add the provided TXT record to your DNS
   - Wait for propagation (up to 48 hours, typically minutes)
   - Select **Verify**

### Step 1.3: Configure the ID Verification Partner

1. Navigate to **Verified ID** > **Verification solutions** > **Partner gallery**
2. Select your chosen partner (e.g., **Onfido** for global coverage)
3. Select **Add partner**
4. Complete the partner configuration:
   - Provide your partner API key / account credentials
   - Configure accepted document types (passport, driver's license, national ID)
   - Enable **Liveness detection** (required for Face Check)
   - Set confidence threshold (recommended: **High** for POC)
5. Select **Save**

> [!IMPORTANT]
> You must have an active account with the ID verification partner. Most partners offer trial/sandbox accounts suitable for POC.

### Step 1.4: Create a Verified Employee Credential

1. Navigate to **Verified ID** > **Credentials** > **+ Add credential**
2. Select **Custom credential**
3. Configure:
   - **Name:** `VerifiedEmployee`
   - **Display name:** Verified Employee
   - **Description:** Issued after government ID verification with Face Check
4. Define the credential schema (claims):

```json
{
  "attestations": {
    "idTokenHints": [
      {
        "mapping": [
          { "outputClaim": "givenName", "required": true, "inputClaim": "given_name", "indexed": false },
          { "outputClaim": "surname", "required": true, "inputClaim": "family_name", "indexed": false },
          { "outputClaim": "employeeId", "required": true, "inputClaim": "employee_id", "indexed": true },
          { "outputClaim": "department", "required": false, "inputClaim": "department", "indexed": false },
          { "outputClaim": "faceCheckVerified", "required": true, "inputClaim": "face_check_verified", "indexed": false }
        ],
        "required": true
      }
    ]
  },
  "validityInterval": 2592000
}
```

5. Under **Display definition**, customize the card appearance:
   - Logo: Upload your company logo
   - Card color: Match brand
   - Description on card: "Verified via government ID + Face Check"
6. Select **Create**

### Step 1.5: Configure Face Check Requirement

1. Navigate to **Verified ID** > **Face Check settings**
2. Enable **Require Face Check for credential presentation**
3. Configure match settings:
   - **Matching mode:** Live selfie vs. government ID photo
   - **Confidence level:** High
   - **Liveness requirement:** Active (user must perform head movements)
4. Select **Save**

---

## Phase 2: Configure Entitlement Management

### Step 2.1: Create a Catalog for Onboarding Resources

1. Navigate to **Identity Governance** > **Entitlement management** > **Catalogs**
2. Select **+ New catalog**
3. Configure:
   - **Name:** New Employee Onboarding
   - **Description:** Resources automatically assigned after identity verification
   - **Enabled:** Yes
   - **Enabled for external users:** No (internal onboarding only)
4. Select **Create**

### Step 2.2: Add Resources to the Catalog

1. Open the **New Employee Onboarding** catalog
2. Select **Resources** > **+ Add resources**
3. Add the following resource types:

**Groups:**
- `POC-AllEmployees` — Base employee group
- `POC-Department-IT` — Department-specific group (example)

**Applications:**
- Microsoft 365 (Office apps)
- Any LOB apps assigned during onboarding

**SharePoint sites:**
- Employee onboarding site
- Company intranet

4. Select **Add**

> [!NOTE]
> For the POC, create dedicated test groups prefixed with `POC-` to avoid affecting production resources.

### Step 2.3: Create the Onboarding Access Package

1. Navigate to **Entitlement management** > **Access packages** > **+ New access package**
2. **Basics tab:**
   - **Name:** New Employee Starter Pack
   - **Description:** Auto-assigned after Verified ID + Face Check verification
   - **Catalog:** New Employee Onboarding
3. **Resource roles tab:**
   - Add `POC-AllEmployees` → Role: Member
   - Add `POC-Department-IT` → Role: Member
   - Add Microsoft 365 → Role: User
   - Add SharePoint site → Role: Member
4. **Requests tab:**
   - **Users who can request access:** For users in your directory
   - **Select users/groups:** Select pilot group (10 users)
   - **Require approval:** No (auto-approve upon successful Verified ID)
   - **Enable:** Yes
5. **Requestor information tab:**
   - Add a question: "Verified ID Credential Presented" (informational)
6. Select **Create**

### Step 2.4: Configure Custom Extension for Verified ID Validation

1. Navigate to **Entitlement management** > **Catalogs** > **New Employee Onboarding**
2. Select **Custom extensions** > **+ Add custom extension**
3. Configure:
   - **Name:** Verify-FaceCheck-Credential
   - **Extension type:** Request workflow
   - **Trigger:** When request is created
   - **Endpoint:** Logic App or Azure Function that:
     1. Receives the access request
     2. Initiates a Verified ID presentation request with Face Check
     3. Validates the credential + face match
     4. Returns approval/denial to Entitlement Management
4. Select **Create**

> [!IMPORTANT]
> The custom extension is the integration point between Entitlement Management and Verified ID. You need an Azure Logic App or Function App to orchestrate this.

### Step 2.5: Create the Logic App for Verification Orchestration

1. In **Azure portal** > **Logic Apps** > **+ Create**
2. Configure:
   - **Name:** `la-verifiedid-facecheck-poc`
   - **Region:** Same as your Entra tenant
   - **Plan type:** Consumption (sufficient for POC)
3. Design the workflow:

```
Trigger: When an HTTP request is received (from Entitlement Management)
    ↓
Action: Create Verified ID presentation request
    - Include Face Check requirement
    - Target credential type: VerifiedEmployee
    ↓
Action: Wait for presentation response (callback)
    ↓
Condition: Face Check passed AND credential valid?
    - Yes → Return "Approved" to Entitlement Management
    - No → Return "Denied" with reason
```

4. Copy the Logic App trigger URL and paste it into the custom extension endpoint configuration

---

## Phase 3: Configure Conditional Access After Credential Verification

This phase enforces a Conditional Access policy that requires users to have completed Verified ID + Face Check before they can access protected applications. The policy uses an **authentication context** that is satisfied only when a valid credential presentation (with Face Check) has been confirmed.

### Step 3.1: Create an Authentication Context

Authentication contexts allow you to define step-up authentication requirements that are triggered by specific conditions.

1. Navigate to **Protection** > **Conditional Access** > **Authentication context**
2. Select **+ New authentication context**
3. Configure:
   - **Name:** Verified ID Face Check Completed
   - **Description:** Requires successful Verified ID credential presentation with Face Check
   - **ID:** `c10` (or next available)
   - **Publish to apps:** Yes
4. Select **Save**

> [!NOTE]
> Authentication context IDs (`c1`–`c25`) are fixed identifiers. Note the ID you assign — you'll reference it in the Conditional Access policy and the Logic App callback.

### Step 3.2: Create a Custom Authentication Strength

1. Navigate to **Protection** > **Authentication methods** > **Authentication strengths**
2. Select **+ New authentication strength**
3. Configure:
   - **Name:** Verified ID + Face Check
   - **Description:** Requires presentation of a Verified Employee credential with liveness-verified Face Check
4. Under **Allowed combinations**, select:
   - **Phishing-resistant MFA** (FIDO2, Windows Hello, Certificate-based)
   - This ensures the base authentication is strong before the Verified ID check
5. Select **Next** > **Create**

> [!IMPORTANT]
> The custom authentication strength enforces the MFA baseline. The Verified ID + Face Check requirement is enforced via the authentication context claim injected by the Logic App after successful credential presentation.

### Step 3.3: Create the Conditional Access Policy — Post-Verification Gate

This policy blocks access to onboarding apps unless the authentication context confirms a successful Verified ID + Face Check.

1. Navigate to **Protection** > **Conditional Access** > **+ Create new policy**
2. **Name:** `POC - Require Verified ID for Onboarding Apps`
3. **Assignments:**
   - **Users:**
     - **Include:** Select **POC-VerifiedID-Pilots** group
     - **Exclude:** Break-glass emergency accounts
   - **Target resources:**
     - **Select what this policy applies to:** Authentication context
     - **Select authentication context:** Verified ID Face Check Completed (`c10`)
4. **Conditions:**
   - **Client apps:** Browser, Mobile apps and desktop clients
   - **Device platforms:** All platforms (or limit to iOS + Android for Authenticator-only)
5. **Grant:**
   - Select **Grant access**
   - Require **authentication strength:** Verified ID + Face Check (custom, created in Step 3.2)
   - Require **all selected controls**
6. **Session:** No session controls
7. **Enable policy:** **Report-only** (start here)
8. Select **Create**

### Step 3.4: Create a Second Policy — Block Without Verified ID

This companion policy ensures that pilot users cannot access sensitive onboarding resources without having completed the Verified ID flow.

1. Navigate to **Protection** > **Conditional Access** > **+ Create new policy**
2. **Name:** `POC - Block Onboarding Apps Without Verified ID`
3. **Assignments:**
   - **Users:**
     - **Include:** Select **POC-VerifiedID-Pilots** group
     - **Exclude:** Break-glass emergency accounts
   - **Target resources:**
     - **Select what this policy applies to:** Cloud apps
     - **Select apps:** Choose the onboarding applications (Microsoft 365, LOB apps, SharePoint onboarding site)
4. **Conditions:**
   - **Client apps:** Browser, Mobile apps and desktop clients
5. **Grant:**
   - Select **Block access**
   - **Unless** user satisfies the authentication context `c10` (Verified ID Face Check Completed)

   > To implement the "unless" logic: configure the grant to **Require authentication strength** → **Verified ID + Face Check**. Users who haven't completed the Verified ID flow won't have the required claim and will be blocked.

6. **Enable policy:** **Report-only**
7. Select **Create**

> [!WARNING]
> **Always start both policies in Report-only mode.** Validate in the sign-in logs that:
> - Pilot users who completed Verified ID + Face Check → would be granted access
> - Pilot users who have NOT completed verification → would be blocked
>
> Only switch to **On** after confirming correct behavior for all 10 pilot users.

### Step 3.5: Integrate Authentication Context into the Logic App

The Logic App (from Phase 2, Step 2.5) must inject the authentication context claim after a successful Verified ID + Face Check. Update the Logic App workflow:

```
Existing step: Credential valid + Face Check passed
    ↓
NEW Action: Issue authentication context claim
    - Call Microsoft Graph:
      POST /identity/conditionalAccess/authenticationContextClassReferences
    - Set claim value: c10 (Verified ID Face Check Completed)
    - Target user: The requesting user's object ID
    ↓
Existing step: Return "Approved" to Entitlement Management
```

**Graph API call to set authentication context (from Logic App):**
```http
POST https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationContextClassReferences
Content-Type: application/json

{
  "id": "c10",
  "displayName": "Verified ID Face Check Completed",
  "description": "User completed Verified ID presentation with Face Check",
  "isAvailable": true
}
```

### Step 3.6: Validate Conditional Access in Report-Only Mode

1. Navigate to **Monitoring** > **Sign-in logs**
2. Filter by:
   - **User:** A pilot user
   - **Conditional Access:** Report-only
3. For each sign-in, check:
   - Policy `POC - Require Verified ID for Onboarding Apps` → Result should be **Report-only: Success** for verified users
   - Policy `POC - Block Onboarding Apps Without Verified ID` → Result should be **Report-only: Failure** for unverified users
4. After 2–3 days of clean results, switch both policies to **On**

### Step 3.7: Monitor and Respond

After enabling:
- **Alert on blocks:** Set up an alert in **Monitoring** > **Diagnostic settings** if the block policy fires unexpectedly
- **Self-remediation:** Blocked users see a message directing them to complete the Verified ID flow at the My Access portal
- **Break-glass:** Emergency accounts are excluded and can always access resources

> [!IMPORTANT]
> The Conditional Access policy targets the **POC pilot group only**. No other users in the tenant are affected.

---

## Phase 4: End-to-End Integration

### Step 4.1: Configure the Issuance Flow

The issuance flow is triggered after HR confirms the new hire:

1. HR initiates onboarding in your HR system
2. HR system (or manual trigger) calls the Verified ID issuance API:

**API Endpoint:** `POST https://verifiedid.did.msidentity.com/v1.0/verifiableCredentials/createIssuanceRequest`

**Request body (simplified):**
```json
{
  "includeQRCode": true,
  "callback": {
    "url": "https://your-callback-endpoint.azurewebsites.net/api/issuance-callback",
    "state": "random-state-value"
  },
  "authority": "did:web:your-tenant.onmicrosoft.com",
  "registration": {
    "clientName": "Contoso Employee Verification"
  },
  "type": "VerifiedEmployee",
  "claims": {
    "givenName": "Jane",
    "surname": "Doe",
    "employeeId": "EMP-12345",
    "department": "Engineering",
    "faceCheckVerified": "true"
  }
}
```

3. New employee scans QR code with Microsoft Authenticator
4. Authenticator triggers Face Check:
   - Employee takes a live selfie
   - Partner service matches selfie against government ID
   - If match passes → credential is stored in Authenticator
   - If match fails → issuance is denied

### Step 4.2: Configure the Presentation + Access Request Flow

1. New employee navigates to **My Access** (https://myaccess.microsoft.com)
2. Finds "New Employee Starter Pack" access package
3. Selects **Request access**
4. Custom extension triggers Verified ID presentation request:
   - Employee receives a push notification in Authenticator
   - Opens Authenticator → presents VerifiedEmployee credential
   - Face Check runs again (live selfie vs. credential photo)
   - If match passes → access package is auto-approved
   - If match fails → request is denied

### Step 4.3: Verify Resource Assignment

After approval:
- User is added to `POC-AllEmployees` group
- User is added to `POC-Department-IT` group
- Microsoft 365 apps become available
- SharePoint site access is granted

---

## Phase 5: Monitoring & Audit

### Step 5.1: Configure Audit Logging

1. Navigate to **Identity Governance** > **Entitlement management** > **Access packages**
2. Open "New Employee Starter Pack" > **Requests**
3. Verify you can see request status, timestamps, and approval details

### Step 5.2: Monitor Verified ID Activity

1. Navigate to **Verified ID** > **Activity log**
2. Monitor issuance and presentation events
3. Check Face Check success/failure rates

### Step 5.3: Review Sign-in Logs

1. Navigate to **Monitoring** > **Sign-in logs**
2. Filter by pilot users
3. Verify Conditional Access policy is applied correctly (if configured)
