<#
.SYNOPSIS
    Configures Entitlement Management (ID Governance) for the Verified ID + Face Check POC.

.DESCRIPTION
    Creates the catalog, resource groups, access package, and custom extension
    that integrates with Verified ID for the onboarding scenario.

.PARAMETER TenantId
    The Entra ID tenant ID.

.PARAMETER LogicAppEndpoint
    The HTTP trigger URL of the Logic App that orchestrates Verified ID presentation.
    If not provided, a placeholder is used and must be updated after Logic App deployment.

.PARAMETER PilotGroupName
    Name of the pilot security group. Default: "POC-VerifiedID-Pilots"

.EXAMPLE
    .\Deploy-EntitlementManagement.ps1 -TenantId "your-tenant-id" -WhatIf
    .\Deploy-EntitlementManagement.ps1 -TenantId "your-tenant-id" -LogicAppEndpoint "https://prod-xx.westus.logic.azure.com/..."

.NOTES
    Requires: Microsoft.Graph PowerShell module
    Permissions: EntitlementManagement.ReadWrite.All, Group.ReadWrite.All
    Run Deploy-VerifiedID.ps1 first.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter()]
    [string]$LogicAppEndpoint = "https://placeholder-update-after-logic-app-deployment.azurewebsites.net",

    [Parameter()]
    [string]$PilotGroupName = "POC-VerifiedID-Pilots",

    [Parameter()]
    [string]$CatalogName = "New Employee Onboarding",

    [Parameter()]
    [string]$AccessPackageName = "New Employee Starter Pack"
)

#region Connect
Write-Host "`n=== Deploy Entitlement Management ===" -ForegroundColor Cyan
Write-Host "Tenant: $TenantId" -ForegroundColor Gray
Write-Host "Catalog: $CatalogName" -ForegroundColor Gray
Write-Host "Access Package: $AccessPackageName" -ForegroundColor Gray
Write-Host ""

$requiredScopes = @(
    "EntitlementManagement.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All"
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

#region Step 1: Create Resource Groups
Write-Host "`n--- Step 1: Create Resource Groups ---" -ForegroundColor Yellow

$resourceGroups = @(
    @{ Name = "POC-AllEmployees"; Description = "All verified employees (POC)" },
    @{ Name = "POC-Department-IT"; Description = "IT department members (POC)" }
)

$createdGroupIds = @{}

foreach ($rg in $resourceGroups) {
    $existing = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$($rg.Name)'" -ErrorAction Stop

    if ($existing.value.Count -gt 0) {
        Write-Host "  [SKIP] Group '$($rg.Name)' already exists" -ForegroundColor Yellow
        $createdGroupIds[$rg.Name] = $existing.value[0].id
    }
    else {
        if ($PSCmdlet.ShouldProcess($rg.Name, "Create Security Group")) {
            $groupBody = @{
                displayName     = $rg.Name
                description     = $rg.Description
                mailEnabled     = $false
                mailNickname    = $rg.Name -replace "-", ""
                securityEnabled = $true
                groupTypes      = @()
            } | ConvertTo-Json

            $newGroup = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $groupBody -ContentType "application/json" -ErrorAction Stop
            $createdGroupIds[$rg.Name] = $newGroup.id
            Write-Host "  [OK] Created group '$($rg.Name)' (ID: $($newGroup.id))" -ForegroundColor Green
        }
    }
}
#endregion

#region Step 2: Create Catalog
Write-Host "`n--- Step 2: Create Catalog ---" -ForegroundColor Yellow

$existingCatalog = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs?`$filter=displayName eq '$CatalogName'" -ErrorAction Stop

if ($existingCatalog.value.Count -gt 0) {
    Write-Host "  [SKIP] Catalog '$CatalogName' already exists" -ForegroundColor Yellow
    $catalogId = $existingCatalog.value[0].id
}
else {
    if ($PSCmdlet.ShouldProcess($CatalogName, "Create Entitlement Management Catalog")) {
        $catalogBody = @{
            displayName         = $CatalogName
            description         = "Resources automatically assigned after Verified ID + Face Check verification"
            isExternallyVisible = $false
            state               = "published"
        } | ConvertTo-Json

        $newCatalog = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs" -Body $catalogBody -ContentType "application/json" -ErrorAction Stop
        $catalogId = $newCatalog.id
        Write-Host "  [OK] Created catalog '$CatalogName' (ID: $catalogId)" -ForegroundColor Green
    }
}
#endregion

#region Step 3: Add Resources to Catalog
Write-Host "`n--- Step 3: Add Resources to Catalog ---" -ForegroundColor Yellow

foreach ($groupName in $createdGroupIds.Keys) {
    $groupId = $createdGroupIds[$groupName]

    # Check if resource already in catalog
    $existingResources = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs/$catalogId/resources" -ErrorAction SilentlyContinue

    $alreadyAdded = $existingResources.value | Where-Object { $_.originId -eq $groupId }
    if ($alreadyAdded) {
        Write-Host "  [SKIP] Group '$groupName' already in catalog" -ForegroundColor Yellow
        continue
    }

    if ($PSCmdlet.ShouldProcess($groupName, "Add group to catalog")) {
        $resourceBody = @{
            catalogId = $catalogId
            requestType = "AdminAdd"
            accessPackageResource = @{
                displayName  = $groupName
                description  = "Security group for POC"
                resourceType = "AadGroup"
                originId     = $groupId
                originSystem = "AadGroup"
            }
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/resourceRequests" -Body $resourceBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "  [OK] Added '$groupName' to catalog" -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Could not add '$groupName': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
#endregion

#region Step 4: Create Access Package
Write-Host "`n--- Step 4: Create Access Package ---" -ForegroundColor Yellow

$existingPackage = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq '$AccessPackageName'" -ErrorAction Stop

if ($existingPackage.value.Count -gt 0) {
    Write-Host "  [SKIP] Access package '$AccessPackageName' already exists" -ForegroundColor Yellow
    $packageId = $existingPackage.value[0].id
}
else {
    if ($PSCmdlet.ShouldProcess($AccessPackageName, "Create Access Package")) {
        $packageBody = @{
            displayName = $AccessPackageName
            description = "Auto-assigned after Verified ID + Face Check verification. Contains base employee resources for onboarding."
            catalogId   = $catalogId
            isHidden    = $false
        } | ConvertTo-Json

        $newPackage = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/accessPackages" -Body $packageBody -ContentType "application/json" -ErrorAction Stop
        $packageId = $newPackage.id
        Write-Host "  [OK] Created access package '$AccessPackageName' (ID: $packageId)" -ForegroundColor Green
    }
}
#endregion

#region Step 5: Configure Assignment Policy
Write-Host "`n--- Step 5: Configure Assignment Policy ---" -ForegroundColor Yellow

# Get pilot group ID
$pilotGroup = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$PilotGroupName'" -ErrorAction Stop
$pilotGroupId = $pilotGroup.value[0].id

if (-not $pilotGroupId) {
    Write-Host "  [ERROR] Pilot group '$PilotGroupName' not found. Run Deploy-VerifiedID.ps1 first." -ForegroundColor Red
}
else {
    if ($PSCmdlet.ShouldProcess($AccessPackageName, "Create Assignment Policy")) {
        $policyBody = @{
            displayName         = "Verified ID Auto-Approval Policy"
            description         = "Auto-approves access when Verified ID + Face Check is presented successfully"
            allowedTargetScope  = "specificDirectoryUsers"
            specificAllowedTargets = @(
                @{
                    "@odata.type" = "#microsoft.graph.groupMembers"
                    groupId       = $pilotGroupId
                    description   = "POC Pilot Users"
                }
            )
            automaticRequestSettings = @{
                requestAccessForAllowedTargets = $false
            }
            requestorSettings = @{
                enableTargetsToSelfAddAccess    = $true
                enableTargetsToSelfUpdateAccess = $false
                enableTargetsToSelfRemoveAccess = $true
            }
            requestApprovalSettings = @{
                isApprovalRequiredForAdd    = $false
                isApprovalRequiredForUpdate = $false
                stages                      = @()
            }
            accessPackage = @{
                id = $packageId
            }
        } | ConvertTo-Json -Depth 5

        try {
            $newPolicy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies" -Body $policyBody -ContentType "application/json" -ErrorAction Stop
            Write-Host "  [OK] Created assignment policy (ID: $($newPolicy.id))" -ForegroundColor Green
            Write-Host "    - Requestors: Members of '$PilotGroupName'" -ForegroundColor Gray
            Write-Host "    - Approval: Auto-approve (no manual approval)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [WARN] Could not create policy: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
#endregion

#region Step 6: Custom Extension (Guidance)
Write-Host "`n--- Step 6: Custom Extension for Verified ID ---" -ForegroundColor Yellow

Write-Host "  The custom extension connects Entitlement Management to Verified ID." -ForegroundColor Cyan
Write-Host "  This must be configured in the Entra admin center:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Steps:" -ForegroundColor White
Write-Host "    1. Navigate to: Identity Governance > Entitlement Management > Catalogs" -ForegroundColor White
Write-Host "    2. Open: '$CatalogName'" -ForegroundColor White
Write-Host "    3. Select: Custom extensions > + Add custom extension" -ForegroundColor White
Write-Host "    4. Configure:" -ForegroundColor White
Write-Host "       - Name: Verify-FaceCheck-Credential" -ForegroundColor White
Write-Host "       - Type: Request workflow" -ForegroundColor White
Write-Host "       - Trigger: When request is created" -ForegroundColor White
Write-Host "       - Endpoint: $LogicAppEndpoint" -ForegroundColor White
Write-Host "    5. Select: Create" -ForegroundColor White
Write-Host ""

if ($LogicAppEndpoint -like "*placeholder*") {
    Write-Host "  [ACTION] Deploy the Logic App first, then update the endpoint URL" -ForegroundColor Yellow
    Write-Host "  See: 01-configuration-guide.md, Phase 2, Step 2.5 for Logic App setup" -ForegroundColor Yellow
}
else {
    Write-Host "  Logic App endpoint: $LogicAppEndpoint" -ForegroundColor Green
}
#endregion

#region Summary
Write-Host "`n`n=== Entitlement Management Deployment Summary ===" -ForegroundColor Cyan
Write-Host "  Catalog: $CatalogName (ID: $catalogId)" -ForegroundColor White
Write-Host "  Access Package: $AccessPackageName (ID: $packageId)" -ForegroundColor White
Write-Host "  Resource Groups:" -ForegroundColor White
foreach ($gn in $createdGroupIds.Keys) {
    Write-Host "    - $gn (ID: $($createdGroupIds[$gn]))" -ForegroundColor Gray
}
Write-Host "  Pilot Group: $PilotGroupName (ID: $pilotGroupId)" -ForegroundColor White
Write-Host ""
Write-Host "  Remaining Manual Steps:" -ForegroundColor Yellow
Write-Host "    1. Deploy Azure Logic App for Verified ID orchestration" -ForegroundColor Yellow
Write-Host "    2. Configure custom extension with Logic App endpoint" -ForegroundColor Yellow
Write-Host "    3. Add resource roles to the access package (portal)" -ForegroundColor Yellow
Write-Host "    4. Test end-to-end flow with a pilot user" -ForegroundColor Yellow
Write-Host ""
#endregion

Disconnect-MgGraph -ErrorAction SilentlyContinue
