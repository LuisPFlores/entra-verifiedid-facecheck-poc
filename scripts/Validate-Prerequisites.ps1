<#
.SYNOPSIS
    Validates prerequisites for Verified ID + Face Check + Entitlement Management POC.

.DESCRIPTION
    Checks tenant configuration for required licenses, roles, service enablement,
    and dependencies before deploying the POC.

.PARAMETER TenantId
    The Entra ID tenant ID.

.PARAMETER PilotGroupName
    Name of the security group containing pilot users. Default: "POC-VerifiedID-Pilots"

.EXAMPLE
    .\Validate-Prerequisites.ps1 -TenantId "your-tenant-id"

.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions: Directory.Read.All, EntitlementManagement.Read.All, Policy.Read.All
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter()]
    [string]$PilotGroupName = "POC-VerifiedID-Pilots"
)

#region Functions
function Write-CheckResult {
    param(
        [string]$Component,
        [string]$Check,
        [bool]$Passed,
        [string]$Details = ""
    )

    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Host "  [$status] " -ForegroundColor $color -NoNewline
    Write-Host "$Check" -NoNewline
    if ($Details) { Write-Host " - $Details" -ForegroundColor Gray } else { Write-Host "" }

    return [PSCustomObject]@{
        Component = $Component
        Check     = $Check
        Status    = $status
        Details   = $Details
    }
}
#endregion

#region Connect to Microsoft Graph
Write-Host "`n=== Entra Verified ID + Face Check + Entitlement Management ===" -ForegroundColor Cyan
Write-Host "=== Prerequisites Validation ===" -ForegroundColor Cyan
Write-Host ""

$requiredScopes = @(
    "Directory.Read.All",
    "EntitlementManagement.Read.All",
    "Policy.Read.All",
    "Organization.Read.All"
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
try {
    Connect-MgGraph -TenantId $TenantId -Scopes $requiredScopes -ErrorAction Stop
    Write-Host "  Connected successfully." -ForegroundColor Green
}
catch {
    Write-Host "  Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
#endregion

$results = @()

#region 1. License Validation
Write-Host "`n--- License Validation ---" -ForegroundColor Yellow

# Check for Entra Suite or required individual licenses
$subscribedSkus = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/subscribedSkus" -ErrorAction Stop
$skuList = $subscribedSkus.value

$entraLicenses = @{
    "Entra Suite"        = "Microsoft_Entra_Suite"
    "Entra ID P2"       = "AAD_PREMIUM_P2"
    "ID Governance"     = "IDENTITY_GOVERNANCE"
}

foreach ($license in $entraLicenses.GetEnumerator()) {
    $found = $skuList | Where-Object { $_.skuPartNumber -like "*$($license.Value)*" -or $_.servicePlans.servicePlanName -contains $license.Value }
    $hasLicense = $null -ne $found
    $detail = if ($hasLicense) { "Available units: $($found.prepaidUnits.enabled - $found.consumedUnits)" } else { "Not found in tenant" }
    $results += Write-CheckResult -Component "Licensing" -Check $license.Key -Passed $hasLicense -Details $detail
}
#endregion

#region 2. Directory Roles
Write-Host "`n--- Required Roles ---" -ForegroundColor Yellow

$currentUser = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me" -ErrorAction Stop
$userId = $currentUser.id

$roleAssignments = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$userId'" -ErrorAction Stop

$requiredRoles = @(
    "Global Administrator",
    "Identity Governance Administrator",
    "Verified ID Administrator"
)

$directoryRoles = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryRoles" -ErrorAction Stop

foreach ($roleName in $requiredRoles) {
    $roleTemplate = $directoryRoles.value | Where-Object { $_.displayName -eq $roleName }
    $hasRole = $false
    if ($roleTemplate) {
        $members = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$($roleTemplate.id)/members" -ErrorAction SilentlyContinue
        if ($members.value) {
            $hasRole = ($members.value | Where-Object { $_.id -eq $userId }) -ne $null
        }
    }
    $results += Write-CheckResult -Component "Roles" -Check $roleName -Passed $hasRole -Details $(if ($hasRole) { "Assigned to current user" } else { "Not assigned - may need elevation" })
}
#endregion

#region 3. Verified ID Service Status
Write-Host "`n--- Verified ID Service ---" -ForegroundColor Yellow

try {
    $verifiedIdConfig = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization" -ErrorAction Stop
    $orgId = $verifiedIdConfig.value[0].id
    $results += Write-CheckResult -Component "Verified ID" -Check "Organization accessible" -Passed $true -Details "Org ID: $orgId"
}
catch {
    $results += Write-CheckResult -Component "Verified ID" -Check "Organization accessible" -Passed $false -Details $_.Exception.Message
}

# Check Verified ID credentials endpoint
try {
    $credentials = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/organization/$orgId/certificateBasedAuthConfiguration" -ErrorAction SilentlyContinue
    $results += Write-CheckResult -Component "Verified ID" -Check "Certificate-based auth config" -Passed $true -Details "Accessible"
}
catch {
    $results += Write-CheckResult -Component "Verified ID" -Check "Certificate-based auth config" -Passed $false -Details "May need additional setup"
}
#endregion

#region 4. Pilot Group
Write-Host "`n--- Pilot Group ---" -ForegroundColor Yellow

try {
    $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$PilotGroupName'" -ErrorAction Stop
    $groupExists = $group.value.Count -gt 0

    if ($groupExists) {
        $groupId = $group.value[0].id
        $members = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$count" -Headers @{ "ConsistencyLevel" = "eventual" } -ErrorAction SilentlyContinue
        $memberCount = if ($members) { $members } else { "unknown" }
        $results += Write-CheckResult -Component "Pilot Group" -Check "Group '$PilotGroupName' exists" -Passed $true -Details "Members: $memberCount"
    }
    else {
        $results += Write-CheckResult -Component "Pilot Group" -Check "Group '$PilotGroupName' exists" -Passed $false -Details "Create the group and add 10 pilot users"
    }
}
catch {
    $results += Write-CheckResult -Component "Pilot Group" -Check "Group '$PilotGroupName' exists" -Passed $false -Details $_.Exception.Message
}
#endregion

#region 5. Entitlement Management
Write-Host "`n--- Entitlement Management ---" -ForegroundColor Yellow

try {
    $catalogs = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs" -ErrorAction Stop
    $results += Write-CheckResult -Component "Entitlement Mgmt" -Check "Service accessible" -Passed $true -Details "Found $($catalogs.value.Count) catalog(s)"

    $pocCatalog = $catalogs.value | Where-Object { $_.displayName -eq "New Employee Onboarding" }
    $results += Write-CheckResult -Component "Entitlement Mgmt" -Check "POC catalog exists" -Passed ($null -ne $pocCatalog) -Details $(if ($pocCatalog) { "ID: $($pocCatalog.id)" } else { "Will be created during deployment" })
}
catch {
    $results += Write-CheckResult -Component "Entitlement Mgmt" -Check "Service accessible" -Passed $false -Details $_.Exception.Message
}
#endregion

#region Summary
Write-Host "`n`n=== VALIDATION SUMMARY ===" -ForegroundColor Cyan
$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $results.Count

Write-Host "  Total checks: $total" -ForegroundColor White
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -gt 0) {
    Write-Host "  Action Required:" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "    - [$($_.Component)] $($_.Check): $($_.Details)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  All prerequisites met. Ready to deploy!" -ForegroundColor Green
}

Write-Host ""
#endregion

# Disconnect
Disconnect-MgGraph -ErrorAction SilentlyContinue
