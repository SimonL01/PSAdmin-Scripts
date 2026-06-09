function Get-ADGroupUserReportBatch {
<#
.SYNOPSIS
    Runs the AD user report for multiple groups and combines the results.

.DESCRIPTION
    Accepts multiple Active Directory group names directly or from a text file, searches
    the configured target domains for each group, and returns one combined user report.

    This command reuses Get-ADGroupUserReport as the single-group lookup engine, so the
    user fields and domain-resolution behavior stay consistent between both commands.

.PARAMETER GroupName
    One or more group names, sAMAccountNames, or distinguished names.

.PARAMETER GroupListPath
    Optional text file containing one group per line. Blank lines and lines beginning
    with # are ignored.

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
    Displays full result objects with Format-List instead of the compact table view.

.PARAMETER ExportCsv
    Exports the combined report to CSV. If CsvPath is not provided, a timestamped file
    is created in the current directory.

.PARAMETER CsvPath
    CSV export path. Providing this parameter automatically enables CSV export.

.PARAMETER CsvDelimiter
    Delimiter used for CSV exports. Defaults to comma.

.PARAMETER ShowPerGroupOutput
    Shows the console output from each underlying Get-ADGroupUserReport run.

.PARAMETER PassThru
    Writes raw combined objects to the pipeline instead of formatted console output.

.EXAMPLE
    Get-ADGroupUserReportBatch -GroupName "Group A","Group B" -TargetDomains corp.example.com -CsvPath .\multi_group_export.csv

.EXAMPLE
    Get-ADGroupUserReportBatch -GroupListPath .\groups.txt -DiscoverForestDomains -ExportCsv
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias("Name", "Groups")]
        [string[]]$GroupName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$GroupListPath,

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
        [switch]$ShowPerGroupOutput,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"

        $requestedGroups = New-Object System.Collections.Generic.List[string]
        $combinedResults = New-Object System.Collections.Generic.List[object]
        $resolvedTargetDomains = Resolve-TargetDomains -Domains $TargetDomains -UseForestDiscovery:$DiscoverForestDomains.IsPresent

        if ($PSBoundParameters.ContainsKey("GroupListPath")) {
            $resolvedGroupListPath = (Resolve-Path -LiteralPath $GroupListPath).Path
            $groupListLines = Get-Content -LiteralPath $resolvedGroupListPath

            foreach ($line in $groupListLines) {
                $trimmedLine = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#")) {
                    continue
                }

                Add-RequestedGroupName -List $requestedGroups -Value $trimmedLine
            }
        }
    }

    process {
        foreach ($group in @($GroupName)) {
            Add-RequestedGroupName -List $requestedGroups -Value $group
        }
    }

    end {
        if ($requestedGroups.Count -eq 0) {
            throw "Specify at least one group with -GroupName or provide a text file with -GroupListPath."
        }

        Write-Host ""
        Write-Host "Active Directory multi-group user report" -ForegroundColor Cyan
        Write-Host ("Groups      : {0}" -f $requestedGroups.Count)
        Write-Host ("Domains     : {0}" -f ($resolvedTargetDomains -join ", "))
        Write-Host ("Scope       : {0}" -f $(if ($NoRecursive.IsPresent) { "Direct members only" } else { "Recursive members" }))

        $groupNumber = 0
        foreach ($group in $requestedGroups) {
            $groupNumber++
            $activity = "Reading Active Directory groups"
            $status = "[{0}/{1}] {2}" -f $groupNumber, $requestedGroups.Count, $group
            $percentComplete = [int](($groupNumber / $requestedGroups.Count) * 100)

            Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete
            Write-Host ("[{0}/{1}] {2}" -f $groupNumber, $requestedGroups.Count, $group) -ForegroundColor Cyan

            $lookupParameters = @{
                GroupName     = $group
                TargetDomains = $resolvedTargetDomains
                PassThru      = $true
            }

            if ($IncludeDirectGroups.IsPresent) {
                $lookupParameters["IncludeDirectGroups"] = $true
            }

            if ($IncludeNonUserMembers.IsPresent) {
                $lookupParameters["IncludeNonUserMembers"] = $true
            }

            if ($NoRecursive.IsPresent) {
                $lookupParameters["NoRecursive"] = $true
            }

            if (-not $ShowPerGroupOutput.IsPresent) {
                $lookupParameters["InformationAction"] = "SilentlyContinue"
            }

            if ($PSBoundParameters.ContainsKey("Verbose")) {
                $lookupParameters["Verbose"] = $true
            }

            if ($PSBoundParameters.ContainsKey("Debug")) {
                $lookupParameters["Debug"] = $true
            }

            try {
                $groupResults = @(Get-ADGroupUserReport @lookupParameters)
                foreach ($result in $groupResults) {
                    [void]$combinedResults.Add($result)
                }
            }
            catch {
                Write-Warning ("Unable to process group '{0}': {1}" -f $group, $_.Exception.Message)
            }
        }

        Write-Progress -Activity "Reading Active Directory groups" -Completed

        if ($combinedResults.Count -eq 0) {
            Write-Warning "No reportable members were found for the requested groups."
            return
        }

        $sortedResults = $combinedResults | Sort-Object SourceGroupName, SourceGroupDomain, UserDomain, DisplayName, SamAccountName
        $okUsers = @($sortedResults | Where-Object { $_.ObjectClass -eq "user" -and $_.LookupStatus -eq "OK" })
        $failedUserLookups = @($sortedResults | Where-Object { $_.LookupStatus -eq "UserLookupFailed" })
        $uniqueUsers = @($okUsers | Sort-Object UserDomain, SamAccountName -Unique)
        $matchedGroups = @($sortedResults | Sort-Object SourceGroupDomain, SourceGroupDistinguishedName -Unique)

        Write-Host ""
        Write-Host ("Matched groups : {0}" -f $matchedGroups.Count) -ForegroundColor Green
        Write-Host ("User rows      : {0}" -f $okUsers.Count) -ForegroundColor Green
        Write-Host ("Unique users   : {0}" -f $uniqueUsers.Count) -ForegroundColor Green

        if ($failedUserLookups.Count -gt 0) {
            Write-Warning ("Failed user lookups: {0}. Check the LookupStatus and LookupMessage columns." -f $failedUserLookups.Count)
        }

        if ($ExportCsv.IsPresent -or $PSBoundParameters.ContainsKey("CsvPath")) {
            if ([string]::IsNullOrWhiteSpace($CsvPath)) {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

                if ($requestedGroups.Count -eq 1) {
                    $safeGroupName = Get-SafeFileName -Value $requestedGroups[0]
                    $fileName = "{0}-members-{1}.csv" -f $safeGroupName, $timestamp
                }
                else {
                    $fileName = "ad-multi-group-members-{0}.csv" -f $timestamp
                }

                $CsvPath = Join-Path -Path (Get-Location).Path -ChildPath $fileName
            }

            $csvParent = Split-Path -Path $CsvPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($csvParent) -and -not (Test-Path -LiteralPath $csvParent)) {
                New-Item -ItemType Directory -Path $csvParent -Force | Out-Null
            }

            $sortedResults | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter $CsvDelimiter
            $resolvedCsvPath = (Resolve-Path -LiteralPath $CsvPath).Path
            Write-Host ("CSV export     : {0}" -f $resolvedCsvPath) -ForegroundColor Cyan
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
                Select-Object SourceGroupName, SourceGroupDomain, UserDomain, DisplayName, SamAccountName, UserPrincipalName, Mail, Enabled, Department, Title, LookupStatus |
                Format-Table -AutoSize
        }
    }
}
