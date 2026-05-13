# Architecture: Verified ID + Face Check + Entitlement Management

## High-Level Architecture

```mermaid
flowchart TB
    subgraph "Employee Device"
        A[Microsoft Authenticator]
    end

    subgraph "Identity Verification"
        B[ID Verification Partner<br/>Onfido / CLEAR / Jumio]
        C[Face Check Service<br/>Liveness + Match]
    end

    subgraph "Microsoft Entra"
        D[Verified ID Service]
        E[Entitlement Management]
        F[Conditional Access]
        G[Entra ID Directory]
    end

    subgraph "Integration Layer"
        H[Azure Logic App<br/>Orchestrator]
    end

    subgraph "Target Resources"
        I[Microsoft 365 Apps]
        J[Security Groups]
        K[SharePoint Sites]
    end

    A -->|1. Government ID + Selfie| B
    B -->|2. Document verified| C
    C -->|3. Face match result| D
    D -->|4. Issue VC to wallet| A
    A -->|5. Present VC + Face Check| H
    H -->|6. Validate credential| D
    H -->|7. Approve/Deny| E
    E -->|8. Assign resources| G
    G --> I
    G --> J
    G --> K
    F -->|Policy enforcement| E
```

## Issuance Flow (Credential Creation)

```mermaid
sequenceDiagram
    participant HR as HR System
    participant VID as Verified ID Service
    participant Auth as Microsoft Authenticator
    participant Partner as ID Verification Partner
    participant FC as Face Check

    HR->>VID: 1. Create issuance request
    VID->>Auth: 2. Push notification / QR code
    Auth->>Partner: 3. Upload government ID
    Partner->>Partner: 4. Validate document authenticity
    Partner-->>Auth: 5. Document OK
    Auth->>FC: 6. Capture live selfie
    FC->>FC: 7. Liveness detection (active)
    FC->>Partner: 8. Compare selfie vs. ID photo
    Partner-->>FC: 9. Match confidence: HIGH
    FC-->>VID: 10. Face Check passed
    VID->>Auth: 11. Issue VerifiedEmployee credential
    Auth-->>Auth: 12. Store in wallet
```

## Presentation + Access Request Flow

```mermaid
sequenceDiagram
    participant User as New Employee
    participant Portal as My Access Portal
    participant EM as Entitlement Management
    participant LA as Logic App (Custom Extension)
    participant VID as Verified ID Service
    participant Auth as Microsoft Authenticator
    participant FC as Face Check

    User->>Portal: 1. Request "New Employee Starter Pack"
    Portal->>EM: 2. Create access request
    EM->>LA: 3. Trigger custom extension
    LA->>VID: 4. Create presentation request (Face Check required)
    VID->>Auth: 5. Push notification
    Auth->>User: 6. "Present your Verified Employee credential?"
    User->>Auth: 7. Approve
    Auth->>FC: 8. Capture live selfie
    FC->>FC: 9. Liveness + match vs. credential photo
    FC-->>VID: 10. Face Check passed
    VID-->>LA: 11. Credential valid + face matched
    LA-->>EM: 12. Return: APPROVED
    EM->>EM: 13. Assign resources (groups, apps, sites)
    EM-->>Portal: 14. Request approved
    Portal-->>User: 15. "Access granted!"
```

## Conditional Access Enforcement Flow

```mermaid
sequenceDiagram
    participant User as Verified Employee
    participant App as Onboarding App
    participant CA as Conditional Access
    participant AuthCtx as Auth Context (c10)
    participant VID as Verified ID Service
    participant FC as Face Check

    User->>App: 1. Attempt to access onboarding app
    App->>CA: 2. Evaluate policies
    CA->>CA: 3. Check: User in POC-VerifiedID-Pilots?
    CA->>AuthCtx: 4. Check: Auth context c10 present?
    
    alt Auth context NOT present
        CA-->>User: 5a. BLOCKED - Redirect to My Access portal
        User->>VID: 6a. Present Verified Employee credential
        VID->>FC: 7a. Face Check (live selfie)
        FC-->>VID: 8a. Match confirmed
        VID-->>AuthCtx: 9a. Set auth context c10 = satisfied
        User->>App: 10a. Retry access
        App->>CA: 11a. Re-evaluate
        CA->>AuthCtx: 12a. Auth context c10 present ✓
        CA-->>App: 13a. ACCESS GRANTED
    end
    
    alt Auth context IS present
        CA-->>App: 5b. ACCESS GRANTED (already verified)
    end

    App-->>User: Access to onboarding resources
```

## Component Relationships

```mermaid
graph LR
    subgraph "Entra Verified ID"
        A1[DID Document<br/>did:web:tenant]
        A2[Credential Schema<br/>VerifiedEmployee]
        A3[Face Check Policy]
        A4[Partner Integration]
    end

    subgraph "Entitlement Management"
        B1[Catalog:<br/>New Employee Onboarding]
        B2[Access Package:<br/>New Employee Starter Pack]
        B3[Custom Extension:<br/>Verify-FaceCheck-Credential]
        B4[Policy:<br/>Auto-approve on VC]
    end

    subgraph "Azure Resources"
        C1[Logic App:<br/>la-verifiedid-facecheck-poc]
        C2[App Registration:<br/>VerifiedID-POC-App]
    end

    A1 --> A2
    A2 --> A3
    A3 --> A4
    B1 --> B2
    B2 --> B3
    B2 --> B4
    B3 --> C1
    C1 --> A2
    C2 --> A1
```

## Network and Data Flow

```mermaid
flowchart LR
    subgraph "On-Premises / Device"
        U[User Device]
        M[Authenticator App]
    end

    subgraph "Internet"
        P[ID Verification Partner API]
    end

    subgraph "Microsoft Cloud"
        VID[Verified ID Service]
        EM[Entitlement Management]
        LA[Logic App]
        AAD[Entra ID]
    end

    U -->|HTTPS 443| VID
    M -->|HTTPS 443| VID
    M -->|HTTPS 443| P
    VID -->|HTTPS 443| P
    LA -->|HTTPS 443| VID
    EM -->|Internal| LA
    EM -->|Internal| AAD
```

## Security Boundaries

| Layer | Protection |
|-------|-----------|
| Credential storage | Encrypted in Microsoft Authenticator, device-bound |
| Face Check | Live selfie never stored; processed in-memory only |
| Government ID | Processed by partner; not stored in Entra |
| Presentation | Zero-knowledge proof; verifier only sees required claims |
| Access assignment | Audit-logged; time-bound; revocable |
| Logic App | Managed identity authentication; no stored secrets |
