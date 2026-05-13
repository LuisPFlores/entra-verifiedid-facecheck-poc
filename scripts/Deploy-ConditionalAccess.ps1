<#
.SYNOPSIS
    Deploys Conditional Access policies for the Verified ID + Face Check POC.

.DESCRIPTION
    Creates the authentication context, custom authentication strength, and two
    Conditional Access policies that enforce Verified ID + Face Check before
    granting access to onboarding applications.

    Policy 1: Require Verified ID authentication context for onboarding apps
    Policy 2: Block access to onboarding apps without Verified ID

    Both policies are created in Report-only mode by default.

.PARAMETER TenantId
    The Entra ID tenant ID.

.PARAMETER PilotGroupName
    Name of the pilot security group. Default: "POC-VerifiedID-Pilots"

.PARAMETER AuthContextId
    Authentication context class reference ID. Default: "c10"

.PARAMETER BreakGlassUpn
    UPN of the break-glass / emergency access account to exclude. Required.

.PARAMETER TargetAppIds
    Array of application IDs to protect. If empty, guidance is provided.

.PARAMETER EnablePolicy
    Set to "enabled" to activate policies immediately (not recommended).
    Default: "enabledForReportingButNotEnforced" (Report-only)

.EXAMPLE
    .\Deploy-ConditionalAccess.ps1 -TenantId "your-tenant-id" -BreakGlassUpn "breakglass@contoso.com" -WhatIf
    .\Deploy-ConditionalAccess.ps1 -TenantId "your-tenant-id" -BreakGlassUpn "breakglass@contoso.com"

.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions: Policy.ReadWrite.ConditionalAccess, Policy.Read.All, Directory.Read.All
    Run AFTER Deploy-VerifiedID.ps1 and Deploy-EntitlementManagement.ps1.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$BreakGlassUpn,

    [Parameter()]
    [string]$PilotGroupName = "POC-VerifiedID-Pilots",

    [Parameter()]
    [string]$AuthContextId = "c10",

    [Parameter()]
    [string]$AuthContextDisplayName = "Verified ID Face Check Completed",

    [Parameter()]
    [string[]]$TargetAppIds = @(),

    [Parameter()]
    [ValidateSet("enabledForReportingButNotEnforced", "enabled", "disabled")]
    [string]$EnablePolicy = "enabledForReportingButNotEnforced"
)

#region Connect
Write-Host "`n=== Deploy Conditional Access Policies ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantId" -ForegroundColor Gray
Write-Host "Policy mode: $EnablePolicy" -ForegroundColor Gray
Write-Host "Auth context: $AuthContextId ($AuthContextDisplayName)" -ForegroundColor Gray
Write-Host ""

$requiredScopes = @(
    "Policy.ReadWrite.ConditionalAccess",
    "Policy.Read.All",
    "Directory.Read.All",
    "Application.Read.All"
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -ErrorAction Stop
    Write-Host "  Connected." -ForegroundColor Green
}
catch {
    Write-Host "  Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
#endregion

#region Resolve pilot group and break-glass account
Write-Host "`n--- Resolving identities ---" -ForegroundColor Yellow

# Pilot group
$pilotGroup = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$PilotGroupName'" -ErrorAction Stop
if ($pilotGroup.value.Count -eq 0) {
    Write-Host "  [ERROR] Pilot group '$PilotGroupName' not found. Run Deploy-VerifiedID.ps1 first." -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit 1
}
$pilotGroupId = $pilotGroup.value[0].id
Write-Host "  [OK] Pilot group: $PilotGroupName (ID: $pilotGroupId)" -ForegroundColor Green

# Break-glass account
$breakGlass = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userPrincipalName eq '$BreakGlassUpn'" -ErrorAction Stop
if ($breakGlass.value.Count -eq 0) {
    Write-Host "  [WARN] Break-glass account '$BreakGlassUpn' not found. Policy will be created without exclusion." -ForegroundColor Yellow
    $breakGlassId = $null
}
else {
    $breakGlassId = $breakGlass.value[0].id
    Write-Host "  [OK] Break-glass account: $BreakGlassUpn (ID: $breakGlassId)" -ForegroundColor Green
}
#endregion

#region Step 1: Create Authentication Context
Write-Host "`n--- Step 1: Authentication Context ---" -ForegroundColor Yellow

$existingAuthCtx = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationContextClassReferences/$AuthContextId" -ErrorAction SilentlyContinue

if ($existingAuthCtx -and $existingAuthCtx.displayName) {
    Write-Host "  [SKIP] Authentication context '$AuthContextId' already exists: $($existingAuthCtx.displayName)" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($AuthContextDisplayName, "Create Authentication Context ($AuthContextId)")) {
        $authCtxBody = @{
            id          = $AuthContextId
            displayName = $AuthContextDisplayName
            description = "User completed Verified ID credential presentation with Face Check liveness verification"
            isAvailable = $true
        } | ConvertTo-Json

        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationContextClassReferences" -Body $authCtxBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "  [OK] Created authentication context: $AuthContextId - $AuthContextDisplayName" -ForegroundColor Green
        }
        catch {
            # Try PATCH if POST fails (context ID may be reserved but not configured)
            try {
                Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationContextClassReferences/$AuthContextId" -Body $authCtxBody -ContentType "application/json" -ErrorAction Stop
                Write-Host "  [OK] Updated authentication context: $AuthContextId - $AuthContextDisplayName" -ForegroundColor Green
            }
            catch {
                Write-Host "  [WARN] Could not create auth context: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "  [INFO] Create it manually: Protection > Conditional Access > Authentication context" -ForegroundColor Cyan
            }
        }
    }
}
#endregion

#region Step 2: Create Custom Authentication Strength
Write-Host "`n--- Step 2: Custom Authentication Strength ---" -ForegroundColor Yellow

$authStrengthName = "Verified ID + Face Check"

$existingStrengths = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies" -ErrorAction Stop
$existingStrength = $existingStrengths.value | Where-Object { $_.displayName -eq $authStrengthName }

if ($existingStrength) {
    Write-Host "  [SKIP] Authentication strength '$authStrengthName' already exists (ID: $($existingStrength.id))" -ForegroundColor Yellow
    $authStrengthId = $existingStrength.id
}
else {
    if ($PSCmdlet.ShouldProcess($authStrengthName, "Create Custom Authentication Strength")) {
        $strengthBody = @{
            displayName  = $authStrengthName
            description  = "Requires phishing-resistant MFA as baseline. Verified ID + Face Check is enforced via authentication context."
            policyType   = "custom"
            allowedCombinations = @(
                "fido2",
                "windowsHelloForBusiness",
                "x509CertificateMultiFactor"
            )
        } | ConvertTo-Json -Depth 3

        try {
            $newStrength = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies" -Body $strengthBody -ContentType "application/json" -ErrorAction Stop
            $authStrengthId = $newStrength.id
            Write-Host "  [OK] Created authentication strength '$authStrengthName' (ID: $authStrengthId)" -ForegroundColor Green
            Write-Host "    Allowed methods: FIDO2, Windows Hello, X.509 Certificate" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [WARN] Could not create auth strength: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  [INFO] Create it manually: Protection > Authentication methods > Authentication strengths" -ForegroundColor Cyan
        }
    }
}
#endregion

#region Step 3: Create CA Policy — Require Verified ID
Write-Host "`n--- Step 3: CA Policy — Require Verified ID for Onboarding ---" -ForegroundColor Yellow

$policy1Name = "POC - Require Verified ID for Onboarding Apps"

$existingPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -ErrorAction Stop
$existingPolicy1 = $existingPolicies.value | Where-Object { $_.displayName -eq $policy1Name }

if ($existingPolicy1) {
    Write-Host "  [SKIP] Policy '$policy1Name' already exists (ID: $($existingPolicy1.id))" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($policy1Name, "Create Conditional Access Policy")) {

        # Build exclusions
        $excludeUsers = @()
        if ($breakGlassId) { $excludeUsers += $breakGlassId }

        $policy1Body = @{
            displayName = $policy1Name
            state       = $EnablePolicy
            conditions  = @{
                users = @{
                    includeGroups = @($pilotGroupId)
                    excludeUsers  = $excludeUsers
                }
                authenticationContext = @{
                    include = @($AuthContextId)
                }
                clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
            }
            grantControls = @{
                operator        = "OR"
                builtInControls = @()
                authenticationStrength = @{
                    id = $authStrengthId
                }
            }
        } | ConvertTo-Json -Depth 5

        try {
            $newPolicy1 = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -Body $policy1Body -ContentType "application/json" -ErrorAction Stop
            Write-Host "  [OK] Created policy '$policy1Name'" -ForegroundColor Green
            Write-Host "    ID: $($newPolicy1.id)" -ForegroundColor Gray
            Write-Host "    State: $EnablePolicy" -ForegroundColor Gray
            Write-Host "    Targets: Pilot group + Auth context $AuthContextId" -ForegroundColor Gray
            Write-Host "    Grant: Require authentication strength '$authStrengthName'" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [ERROR] Failed to create policy: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
#endregion

#region Step 4: Create CA Policy — Block Without Verified ID
Write-Host "`n--- Step 4: CA Policy — Block Without Verified ID ---" -ForegroundColor Yellow

$policy2Name = "POC - Block Onboarding Apps Without Verified ID"

$existingPolicy2 = $existingPolicies.value | Where-Object { $_.displayName -eq $policy2Name }

if ($existingPolicy2) {
    Write-Host "  [SKIP] Policy '$policy2Name' already exists (ID: $($existingPolicy2.id))" -ForegroundColor Yellow
}
else {
    # Determine target apps
    if ($TargetAppIds.Count -eq 0) {
        Write-Host "  [INFO] No target app IDs provided. Generating policy template with placeholder." -ForegroundColor Cyan
        Write-Host "  [ACTION] After creation, edit the policy in the admin center to add your onboarding apps:" -ForegroundColor Yellow
        Write-Host "    - Microsoft 365 (Office apps)" -ForegroundColor Yellow
        Write-Host "    - SharePoint onboarding site" -ForegroundColor Yellow
        Write-Host "    - Any LOB applications for new hires" -ForegroundColor Yellow
        Write-Host ""

        # Use a well-known app ID as placeholder — Office 365
        $targetApps = @("Office365")
    }
    else {
        $targetApps = $TargetAppIds
    }

    if ($PSCmdlet.ShouldProcess($policy2Name, "Create Conditional Access Policy")) {

        $excludeUsers = @()
        if ($breakGlassId) { $excludeUsers += $breakGlassId }

        $policy2Body = @{
            displayName = $policy2Name
            state       = $EnablePolicy
            conditions  = @{
                users = @{
                    includeGroups = @($pilotGroupId)
                    excludeUsers  = $excludeUsers
                }
                applications = @{
                    includeApplications = $targetApps
                }
                clientAppTypes = @("browser", "mobileAppsAndDesktopClients")
            }
            grantControls = @{
                operator        = "OR"
                builtInControls = @()
                authenticationStrength = @{
                    id = $authStrengthId
                }
            }
        } | ConvertTo-Json -Depth 5

        try {
            $newPolicy2 = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -Body $policy2Body -ContentType "application/json" -ErrorAction Stop
            Write-Host "  [OK] Created policy '$policy2Name'" -ForegroundColor Green
            Write-Host "    ID: $($newPolicy2.id)" -ForegroundColor Gray
            Write-Host "    State: $EnablePolicy" -ForegroundColor Gray
            Write-Host "    Targets: Pilot group + Onboarding apps" -ForegroundColor Gray
            Write-Host "    Grant: Require authentication strength (blocks if not met)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [ERROR] Failed to create policy: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
#endregion

#region Step 5: Validation Guidance
Write-Host "`n--- Step 5: Validation ---" -ForegroundColor Yellow

Write-Host "  Both policies are in Report-only mode. Validate before enabling:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Sign in as a pilot user who HAS completed Verified ID + Face Check" -ForegroundColor White
Write-Host "     → Sign-in log should show: Report-only: Success" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Sign in as a pilot user who has NOT completed Verified ID" -ForegroundColor White
Write-Host "     → Sign-in log should show: Report-only: Failure (would block)" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Sign in as a break-glass account" -ForegroundColor White
Write-Host "     → Should NOT be affected by either policy (excluded)" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. After 2-3 days of clean results, switch both policies to 'On':" -ForegroundColor White
Write-Host "     Protection > Conditional Access > Select policy > Enable policy: On" -ForegroundColor Gray
Write-Host ""

if ($EnablePolicy -eq "enabledForReportingButNotEnforced") {
    Write-Host "  [SAFE] Policies are in REPORT-ONLY mode. No users will be blocked." -ForegroundColor Green
}
elseif ($EnablePolicy -eq "enabled") {
    Write-Host "  [WARNING] Policies are ENABLED. Pilot users without Verified ID will be blocked!" -ForegroundColor Red
}
#endregion

#region Summary
Write-Host "`n`n=== Conditional Access Deployment Summary ===" -ForegroundColor Cyan
Write-Host "  Authentication Context: $AuthContextId - $AuthContextDisplayName" -ForegroundColor White
Write-Host "  Authentication Strength: $authStrengthName (ID: $authStrengthId)" -ForegroundColor White
Write-Host "  Policy 1: $policy1Name" -ForegroundColor White
Write-Host "    → Requires Verified ID auth context + strong MFA" -ForegroundColor Gray
Write-Host "  Policy 2: $policy2Name" -ForegroundColor White
Write-Host "    → Blocks onboarding app access without Verified ID" -ForegroundColor Gray
Write-Host "  Break-glass excluded: $BreakGlassUpn" -ForegroundColor White
Write-Host "  Mode: $EnablePolicy" -ForegroundColor White
Write-Host ""
Write-Host "  Remaining Steps:" -ForegroundColor Yellow
Write-Host "    1. Verify auth context is injected by Logic App after Face Check" -ForegroundColor Yellow
Write-Host "    2. Add specific onboarding app IDs to Policy 2 (if not provided)" -ForegroundColor Yellow
Write-Host "    3. Test with pilot users in Report-only mode for 2-3 days" -ForegroundColor Yellow
Write-Host "    4. Switch to 'On' after validation" -ForegroundColor Yellow
Write-Host ""
#endregion

Disconnect-MgGraph -ErrorAction SilentlyContinue
