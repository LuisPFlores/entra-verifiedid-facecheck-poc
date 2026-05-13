<#
.SYNOPSIS
    Configures Microsoft Entra Verified ID service for POC deployment.

.DESCRIPTION
    Sets up the Verified ID service, creates the VerifiedEmployee credential type,
    and configures Face Check settings. This script handles the Verified ID side
    of the POC deployment.

.PARAMETER TenantId
    The Entra ID tenant ID.

.PARAMETER CredentialName
    Name for the Verified Employee credential. Default: "VerifiedEmployee"

.PARAMETER PartnerName
    ID verification partner name. Default: "Onfido"

.PARAMETER FaceCheckConfidence
    Face Check confidence level. Default: "High"

.EXAMPLE
    .\Deploy-VerifiedID.ps1 -TenantId "your-tenant-id" -WhatIf
    .\Deploy-VerifiedID.ps1 -TenantId "your-tenant-id"

.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions: VerifiableCredential.Create.All, Application.ReadWrite.All
    Run Validate-Prerequisites.ps1 first to confirm readiness.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter()]
    [string]$CredentialName = "VerifiedEmployee",

    [Parameter()]
    [string]$CredentialDisplayName = "Verified Employee",

    [Parameter()]
    [ValidateSet("Onfido", "CLEAR", "Jumio", "AU10TIX")]
    [string]$PartnerName = "Onfido",

    [Parameter()]
    [ValidateSet("Low", "Medium", "High")]
    [string]$FaceCheckConfidence = "High",

    [Parameter()]
    [int]$CredentialValidityDays = 30
)

#region Connect
Write-Host "`n=== Deploy Entra Verified ID ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantId" -ForegroundColor Gray
Write-Host "Credential: $CredentialName" -ForegroundColor Gray
Write-Host "Partner: $PartnerName" -ForegroundColor Gray
Write-Host "Face Check Confidence: $FaceCheckConfidence" -ForegroundColor Gray
Write-Host ""

$requiredScopes = @(
    "Directory.ReadWrite.All",
    "Application.ReadWrite.All"
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

#region Step 1: Register App for Verified ID
Write-Host "`n--- Step 1: App Registration ---" -ForegroundColor Yellow

$appName = "VerifiedID-POC-FaceCheck"

# Check if app already exists
$existingApp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$appName'" -ErrorAction Stop
if ($existingApp.value.Count -gt 0) {
    Write-Host "  [SKIP] App '$appName' already exists (ID: $($existingApp.value[0].appId))" -ForegroundColor Yellow
    $appId = $existingApp.value[0].appId
    $appObjectId = $existingApp.value[0].id
}
else {
    if ($PSCmdlet.ShouldProcess($appName, "Create App Registration")) {
        $appBody = @{
            displayName    = $appName
            signInAudience = "AzureADMyOrg"
            web            = @{
                redirectUris = @(
                    "https://localhost:5001/signin-oidc"
                )
            }
            requiredResourceAccess = @(
                @{
                    resourceAppId  = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
                    resourceAccess = @(
                        @{ id = "87f40944-71ba-4635-a9dd-5765ad3bbc3c"; type = "Scope" } # VerifiableCredential.Create.All
                    )
                }
            )
        } | ConvertTo-Json -Depth 5

        $newApp = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/applications" -Body $appBody -ContentType "application/json" -ErrorAction Stop
        $appId = $newApp.appId
        $appObjectId = $newApp.id
        Write-Host "  [OK] Created app '$appName' (AppId: $appId)" -ForegroundColor Green
    }
}
#endregion

#region Step 2: Create Service Principal
Write-Host "`n--- Step 2: Service Principal ---" -ForegroundColor Yellow

$existingSp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$appId'" -ErrorAction Stop
if ($existingSp.value.Count -gt 0) {
    Write-Host "  [SKIP] Service principal already exists" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($appName, "Create Service Principal")) {
        $spBody = @{ appId = $appId } | ConvertTo-Json
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" -Body $spBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "  [OK] Service principal created" -ForegroundColor Green
    }
}
#endregion

#region Step 3: Configure Credential Schema
Write-Host "`n--- Step 3: Credential Schema ---" -ForegroundColor Yellow

$credentialSchema = @{
    name        = $CredentialName
    displayName = $CredentialDisplayName
    description = "Issued after government ID verification with Face Check"
    rules       = @{
        attestations = @{
            idTokenHints = @(
                @{
                    mapping = @(
                        @{ outputClaim = "givenName"; required = $true; inputClaim = "given_name"; indexed = $false }
                        @{ outputClaim = "surname"; required = $true; inputClaim = "family_name"; indexed = $false }
                        @{ outputClaim = "employeeId"; required = $true; inputClaim = "employee_id"; indexed = $true }
                        @{ outputClaim = "department"; required = $false; inputClaim = "department"; indexed = $false }
                        @{ outputClaim = "faceCheckVerified"; required = $true; inputClaim = "face_check_verified"; indexed = $false }
                        @{ outputClaim = "verificationDate"; required = $true; inputClaim = "verification_date"; indexed = $false }
                    )
                    required = $true
                }
            )
        }
        validityInterval = $CredentialValidityDays * 86400
    }
    display = @{
        locale = "en-US"
        card   = @{
            title           = $CredentialDisplayName
            issuedBy        = "Contoso IT"
            backgroundColor = "#1E3A5F"
            textColor       = "#FFFFFF"
            description     = "Verified via government ID + Face Check"
        }
        claims = @(
            @{ claim = "givenName"; label = "First Name"; type = "String" }
            @{ claim = "surname"; label = "Last Name"; type = "String" }
            @{ claim = "employeeId"; label = "Employee ID"; type = "String" }
            @{ claim = "department"; label = "Department"; type = "String" }
            @{ claim = "verificationDate"; label = "Verified On"; type = "String" }
        )
    }
}

Write-Host "  Credential schema prepared:" -ForegroundColor Gray
Write-Host "    Name: $CredentialName" -ForegroundColor Gray
Write-Host "    Claims: givenName, surname, employeeId, department, faceCheckVerified, verificationDate" -ForegroundColor Gray
Write-Host "    Validity: $CredentialValidityDays days" -ForegroundColor Gray
Write-Host ""
Write-Host "  [INFO] Credential type configuration must be completed in the Entra admin center:" -ForegroundColor Cyan
Write-Host "    1. Go to: Entra admin center > Verification solutions > Verified ID > Credentials" -ForegroundColor Cyan
Write-Host "    2. Select '+ Add credential' > Custom credential" -ForegroundColor Cyan
Write-Host "    3. Use the schema definition above" -ForegroundColor Cyan

# Export schema for reference
$schemaPath = Join-Path $PSScriptRoot "credential-schema.json"
$credentialSchema | ConvertTo-Json -Depth 10 | Out-File -FilePath $schemaPath -Encoding UTF8
Write-Host "  [OK] Schema exported to: $schemaPath" -ForegroundColor Green
#endregion

#region Step 4: Face Check Configuration Guidance
Write-Host "`n--- Step 4: Face Check Configuration ---" -ForegroundColor Yellow

Write-Host "  Face Check must be configured in the Entra admin center:" -ForegroundColor Cyan
Write-Host "    1. Navigate to: Verified ID > Face Check settings" -ForegroundColor Cyan
Write-Host "    2. Enable: Require Face Check for credential presentation" -ForegroundColor Cyan
Write-Host "    3. Matching mode: Live selfie vs. government ID photo" -ForegroundColor Cyan
Write-Host "    4. Confidence level: $FaceCheckConfidence" -ForegroundColor Cyan
Write-Host "    5. Liveness requirement: Active" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Partner configuration ($PartnerName):" -ForegroundColor Cyan
Write-Host "    1. Navigate to: Verified ID > Partner gallery" -ForegroundColor Cyan
Write-Host "    2. Select: $PartnerName" -ForegroundColor Cyan
Write-Host "    3. Provide API credentials from your $PartnerName account" -ForegroundColor Cyan
Write-Host "    4. Enable liveness detection" -ForegroundColor Cyan
Write-Host "    5. Set confidence threshold: $FaceCheckConfidence" -ForegroundColor Cyan
#endregion

#region Step 5: Create POC Pilot Group
Write-Host "`n--- Step 5: POC Pilot Group ---" -ForegroundColor Yellow

$pilotGroupName = "POC-VerifiedID-Pilots"
$existingGroup = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$pilotGroupName'" -ErrorAction Stop

if ($existingGroup.value.Count -gt 0) {
    Write-Host "  [SKIP] Group '$pilotGroupName' already exists" -ForegroundColor Yellow
}
else {
    if ($PSCmdlet.ShouldProcess($pilotGroupName, "Create Security Group")) {
        $groupBody = @{
            displayName     = $pilotGroupName
            description     = "Pilot users for Verified ID + Face Check POC"
            mailEnabled     = $false
            mailNickname    = "POCVerifiedIDPilots"
            securityEnabled = $true
            groupTypes      = @()
        } | ConvertTo-Json

        $newGroup = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $groupBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "  [OK] Created group '$pilotGroupName' (ID: $($newGroup.id))" -ForegroundColor Green
        Write-Host "  [ACTION] Add 10 pilot users to this group manually or via script" -ForegroundColor Yellow
    }
}
#endregion

#region Summary
Write-Host "`n`n=== Deployment Summary ===" -ForegroundColor Cyan
Write-Host "  App Registration: $appName (AppId: $appId)" -ForegroundColor White
Write-Host "  Credential Schema: Exported to $schemaPath" -ForegroundColor White
Write-Host "  Pilot Group: $pilotGroupName" -ForegroundColor White
Write-Host ""
Write-Host "  Manual Steps Required:" -ForegroundColor Yellow
Write-Host "    1. Complete Verified ID credential creation in admin center" -ForegroundColor Yellow
Write-Host "    2. Configure Face Check settings in admin center" -ForegroundColor Yellow
Write-Host "    3. Set up $PartnerName partner integration" -ForegroundColor Yellow
Write-Host "    4. Add pilot users to '$pilotGroupName' group" -ForegroundColor Yellow
Write-Host "    5. Run Deploy-EntitlementManagement.ps1 for access package setup" -ForegroundColor Yellow
Write-Host ""
#endregion

Disconnect-MgGraph -ErrorAction SilentlyContinue
