function Get-ADGroupUserReport {
<#
.SYNOPSIS
    Finds an Active Directory group across target domains and reports its user members.

.DESCRIPTION
    Searches each target domain for a group by Name, sAMAccountName, or distinguishedName.
    For every matching group, the command retrieves recursive members by default, resolves
    user objects in their owning domain, and displays relevant administrator-facing user
    information.

    Specify domains with -TargetDomains, or use -DiscoverForestDomains to query all
    domains in the current Active Directory forest.

.PARAMETER GroupName
    Group Name, sAMAccountName, or distinguished name to search for.

.PARAMETER TargetDomains
    Domain controllers or domain DNS names to query.

.PARAMETER DiscoverForestDomains
    Discovers all domains in the current Active Directory forest and uses them as targets.

.PARAMETER IncludeDirectGroups
    Resolves each user's direct group memberships and adds them to the report.

.PARAMETER IncludeNonUserMembers
    Includes non-user members, such as computers, groups, or foreign security principals.

.PARAMETER NoRecursive
    Returns only direct group members instead of recursive members.

.PARAMETER Detailed
    Displays the full result objects with Format-List instead of the compact table view.

.PARAMETER ExportCsv
    Exports the report to CSV. If CsvPath is not provided, a timestamped file is created
    in the current directory.

.PARAMETER CsvPath
    CSV export path. Providing this parameter automatically enables CSV export.

.PARAMETER CsvDelimiter
    Delimiter used for CSV exports. Defaults to comma.

.PARAMETER PassThru
    Writes raw objects to the pipeline instead of formatted console output.

.EXAMPLE
    Get-ADGroupUserReport -GroupName "Example Group" -TargetDomains corp.example.com,admin.example.com

.EXAMPLE
    Get-ADGroupUserReport -GroupName "Example Group" -DiscoverForestDomains -CsvPath .\single_group_export.csv
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [Alias("Name")]
        [string]$GroupName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias("Domains")]
        [string[]]$TargetDomains,

        [Parameter()]
        [switch]$DiscoverForestDomains,

        [Parameter()]
        [switch]$IncludeDirectGroups,

        [Parameter()]
        [switch]$IncludeNonUserMembers,

        [Parameter()]
        [switch]$NoRecursive,

        [Parameter()]
        [switch]$Detailed,

        [Parameter()]
        [switch]$ExportCsv,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$CsvPath,

        [Parameter()]
        [char]$CsvDelimiter = ",",

        [Parameter()]
        [switch]$PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        throw "The ActiveDirectory module is required. Install RSAT Active Directory tools or run this command from an admin host where the module is available. Details: $($_.Exception.Message)"
    }

    $resolvedTargetDomains = Resolve-TargetDomains -Domains $TargetDomains -UseForestDiscovery:$DiscoverForestDomains.IsPresent

    $userProperties = @(
        "AccountExpirationDate",
        "CanonicalName",
        "Company",
        "Department",
        "Description",
        "DisplayName",
        "EmployeeID",
        "EmployeeNumber",
        "Enabled",
        "GivenName",
        "LastLogonDate",
        "LockedOut",
        "Manager",
        "MemberOf",
        "MobilePhone",
        "Office",
        "OfficePhone",
        "PasswordLastSet",
        "PasswordNeverExpires",
        "SamAccountName",
        "Surname",
        "Title",
        "UserPrincipalName",
        "mail",
        "whenChanged",
        "whenCreated"
    )

    $recursiveLookup = -not $NoRecursive.IsPresent
    $results = New-Object System.Collections.Generic.List[object]
    $foundGroups = New-Object System.Collections.Generic.List[object]
    $skippedNonUserMembers = 0

    Write-Host ""
    Write-Host "Active Directory group user report" -ForegroundColor Cyan
    Write-Host ("Group search : {0}" -f $GroupName)
    Write-Host ("Domains      : {0}" -f ($resolvedTargetDomains -join ", "))
    Write-Host ("Scope        : {0}" -f $(if ($recursiveLookup) { "Recursive members" } else { "Direct members only" }))

    foreach ($domain in $resolvedTargetDomains) {
        Write-Verbose ("Searching for group '{0}' in '{1}'." -f $GroupName, $domain)
        $domainGroups = Find-ADGroupInDomain -Name $GroupName -Domain $domain

        foreach ($group in $domainGroups) {
            [void]$foundGroups.Add([PSCustomObject]@{
                Group  = $group
                Domain = $domain
            })
        }
    }

    if ($foundGroups.Count -eq 0) {
        Write-Warning ("Group '{0}' was not found in any target domain: {1}" -f $GroupName, ($resolvedTargetDomains -join ", "))
        return
    }

    Write-Host ("Groups found : {0}" -f $foundGroups.Count) -ForegroundColor Green

    foreach ($groupMatch in $foundGroups) {
        $group = $groupMatch.Group
        $groupDomain = $groupMatch.Domain
        $groupNameResolved = Get-ADObjectProperty -InputObject $group -Name "Name"
        $groupDn = Get-ADObjectProperty -InputObject $group -Name "DistinguishedName"

        Write-Host ""
        Write-Host ("Reading members from '{0}' in '{1}'." -f $groupNameResolved, $groupDomain) -ForegroundColor Cyan

        try {
            $members = @(Get-ADGroupMember -Identity $groupDn -Server $groupDomain -Recursive:$recursiveLookup -ErrorAction Stop)
        }
        catch {
            Write-Warning ("Unable to read members for group '{0}' in '{1}': {2}" -f $groupNameResolved, $groupDomain, $_.Exception.Message)
            continue
        }

        if ($members.Count -eq 0) {
            Write-Warning ("Group '{0}' in '{1}' has no members." -f $groupNameResolved, $groupDomain)
            continue
        }

        foreach ($member in $members) {
            $objectClass = Get-ADObjectProperty -InputObject $member -Name "ObjectClass"

            if ($objectClass -ne "user") {
                if ($IncludeNonUserMembers.IsPresent) {
                    [void]$results.Add((New-NonUserReportRow -Group $group -GroupDomain $groupDomain -Member $member))
                }
                else {
                    $skippedNonUserMembers++
                }

                continue
            }

            $resolvedUser = Resolve-ADUserForMember -Member $member -SourceDomain $groupDomain -KnownDomains $resolvedTargetDomains -Properties $userProperties

            if ($null -eq $resolvedUser.User) {
                [void]$results.Add((New-UnresolvedUserReportRow -Group $group -GroupDomain $groupDomain -Member $member -UserDomain $resolvedUser.Domain -LookupError $resolvedUser.LookupError))
                continue
            }

            [void]$results.Add((New-UserReportRow -Group $group -GroupDomain $groupDomain -User $resolvedUser.User -UserDomain $resolvedUser.Domain -KnownDomains $resolvedTargetDomains -ResolveDirectGroups:$IncludeDirectGroups.IsPresent))
        }
    }

    if ($results.Count -eq 0) {
        Write-Warning "No reportable members were found."

        if ($skippedNonUserMembers -gt 0) {
            Write-Warning ("Skipped {0} non-user member(s). Re-run with -IncludeNonUserMembers to display them." -f $skippedNonUserMembers)
        }

        return
    }

    $sortedResults = $results | Sort-Object SourceGroupDomain, SourceGroupName, UserDomain, DisplayName, SamAccountName
    $userCount = @($sortedResults | Where-Object { $_.ObjectClass -eq "user" -and $_.LookupStatus -eq "OK" }).Count
    $failedUserLookups = @($sortedResults | Where-Object { $_.LookupStatus -eq "UserLookupFailed" }).Count

    Write-Host ""
    Write-Host ("Users        : {0}" -f $userCount) -ForegroundColor Green

    if ($failedUserLookups -gt 0) {
        Write-Warning ("Failed user lookups: {0}. Check the LookupStatus and LookupMessage columns." -f $failedUserLookups)
    }

    if ($skippedNonUserMembers -gt 0) {
        Write-Warning ("Skipped {0} non-user member(s). Re-run with -IncludeNonUserMembers to display them." -f $skippedNonUserMembers)
    }

    if ($ExportCsv.IsPresent -or $PSBoundParameters.ContainsKey("CsvPath")) {
        if ([string]::IsNullOrWhiteSpace($CsvPath)) {
            $safeGroupName = Get-SafeFileName -Value $GroupName
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $CsvPath = Join-Path -Path (Get-Location).Path -ChildPath ("{0}-members-{1}.csv" -f $safeGroupName, $timestamp)
        }

        $csvParent = Split-Path -Path $CsvPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($csvParent) -and -not (Test-Path -LiteralPath $csvParent)) {
            New-Item -ItemType Directory -Path $csvParent -Force | Out-Null
        }

        $sortedResults | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter $CsvDelimiter
        $resolvedCsvPath = (Resolve-Path -LiteralPath $CsvPath).Path
        Write-Host ("CSV export   : {0}" -f $resolvedCsvPath) -ForegroundColor Cyan
    }

    if ($PassThru.IsPresent) {
        $sortedResults
        return
    }

    Write-Host ""

    if ($Detailed.IsPresent) {
        $sortedResults | Format-List *
    }
    else {
        $sortedResults |
            Select-Object SourceGroupDomain, UserDomain, DisplayName, SamAccountName, UserPrincipalName, Mail, Enabled, Department, Title, Company, OfficePhone, LastLogonDate, LookupStatus |
            Format-Table -AutoSize
    }
}
