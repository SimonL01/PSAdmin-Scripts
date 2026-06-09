function Split-ADGroupUserReport {
<#
.SYNOPSIS
    Splits an AD group member export into single-group and multi-group user reports.

.DESCRIPTION
    Imports a CSV created by Get-ADGroupUserReport or Get-ADGroupUserReportBatch, groups
    rows by a stable user identity, and exports two reports:

    - users found in more than one source group
    - users found in exactly one source group

    The command prefers DistinguishedName for user identity, then UserDomain +
    SamAccountName, then UserPrincipalName, then DisplayName. Source groups are counted
    by distinguished name when available, otherwise by domain and group name.

.PARAMETER InputCsv
    CSV file exported by Get-ADGroupUserReport or Get-ADGroupUserReportBatch.

.PARAMETER OutputDirectory
    Directory where default output files are created. Defaults to the current directory.

.PARAMETER OutputPrefix
    Prefix for default output file names. Defaults to the input file name without extension.

.PARAMETER MultipleGroupsCsvPath
    Explicit output path for users found in multiple source groups.

.PARAMETER SingleGroupCsvPath
    Explicit output path for users found in exactly one source group.

.PARAMETER Delimiter
    CSV delimiter used for input and output. Defaults to comma.

.PARAMETER IncludeNonUserRows
    Includes non-user rows when the input contains ObjectClass values other than user.
    By default, only user rows are included when ObjectClass exists.

.PARAMETER IncludeLookupFailures
    Includes rows where LookupStatus is not OK. By default, only successful lookups are
    included when LookupStatus exists.

.PARAMETER PassThru
    Writes the combined categorized result objects to the pipeline.

.EXAMPLE
    Split-ADGroupUserReport -InputCsv .\multi_group_export.csv -OutputDirectory .\reports

.EXAMPLE
    Split-ADGroupUserReport -InputCsv .\multi_group_export.csv -Delimiter ";" -OutputDirectory .\reports
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
            if (Test-Path -LiteralPath $_ -PathType Leaf) {
                return $true
            }

            throw "Input CSV not found: $_"
        })]
        [string]$InputCsv,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPrefix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$MultipleGroupsCsvPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SingleGroupCsvPath,

        [Parameter()]
        [char]$Delimiter = ",",

        [Parameter()]
        [switch]$IncludeNonUserRows,

        [Parameter()]
        [switch]$IncludeLookupFailures,

        [Parameter()]
        [switch]$PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $resolvedInputCsv = (Resolve-Path -LiteralPath $InputCsv).Path
    $rows = @(Import-Csv -LiteralPath $resolvedInputCsv -Delimiter $Delimiter)

    if ($rows.Count -eq 0) {
        throw "Input CSV contains no rows: $resolvedInputCsv"
    }

    $firstRow = $rows[0]
    if (-not (Test-ObjectProperty -InputObject $firstRow -Name "SourceGroupName")) {
        throw "Input CSV is missing the required 'SourceGroupName' column."
    }

    $hasObjectClass = Test-ObjectProperty -InputObject $firstRow -Name "ObjectClass"
    $hasLookupStatus = Test-ObjectProperty -InputObject $firstRow -Name "LookupStatus"
    $filteredRows = $rows
    $nonUserRowsSkipped = 0
    $lookupFailureRowsSkipped = 0

    if ($hasObjectClass -and -not $IncludeNonUserRows.IsPresent) {
        $beforeCount = @($filteredRows).Count
        $filteredRows = @($filteredRows | Where-Object { $_.ObjectClass -eq "user" })
        $nonUserRowsSkipped = $beforeCount - @($filteredRows).Count
    }

    if ($hasLookupStatus -and -not $IncludeLookupFailures.IsPresent) {
        $beforeCount = @($filteredRows).Count
        $filteredRows = @($filteredRows | Where-Object { $_.LookupStatus -eq "OK" })
        $lookupFailureRowsSkipped = $beforeCount - @($filteredRows).Count
    }

    if (@($filteredRows).Count -eq 0) {
        throw "No rows remain after filtering. Use -IncludeNonUserRows or -IncludeLookupFailures if those rows are expected."
    }

    $normalizedRows = New-Object System.Collections.Generic.List[object]
    $rowNumber = 0

    foreach ($row in $filteredRows) {
        $rowNumber++
        [void]$normalizedRows.Add([PSCustomObject]@{
            UserKey            = Get-UserIdentityKey -Row $row -RowNumber $rowNumber
            SourceGroupKey     = Get-SourceGroupKey -Row $row
            SourceGroupDisplay = Get-SourceGroupDisplayName -Row $row
            Row                = $row
        })
    }

    $reportRows = New-Object System.Collections.Generic.List[object]

    foreach ($userGroup in ($normalizedRows | Group-Object UserKey)) {
        $userRows = @($userGroup.Group)
        $rawRows = @($userRows | ForEach-Object { $_.Row })
        $uniqueSourceGroupKeys = @($userRows.SourceGroupKey | Sort-Object -Unique)
        $uniqueSourceGroupNames = @($userRows.SourceGroupDisplay | Sort-Object -Unique)
        $groupCount = $uniqueSourceGroupKeys.Count

        if ($groupCount -gt 1) {
            $membershipCategory = "MultipleGroups"
        }
        else {
            $membershipCategory = "SingleGroup"
        }

        [void]$reportRows.Add([PSCustomObject]@{
            MembershipCategory = $membershipCategory
            UserKey            = $userGroup.Name
            DisplayName        = Join-UniqueValues -Values $rawRows.DisplayName
            UserDomain         = Join-UniqueValues -Values $rawRows.UserDomain
            SamAccountName     = Join-UniqueValues -Values $rawRows.SamAccountName
            UserPrincipalName  = Join-UniqueValues -Values $rawRows.UserPrincipalName
            Mail               = Join-UniqueValues -Values $rawRows.Mail
            Enabled            = Join-UniqueValues -Values $rawRows.Enabled
            Department         = Join-UniqueValues -Values $rawRows.Department
            Title              = Join-UniqueValues -Values $rawRows.Title
            GroupCount         = $groupCount
            SourceGroups       = ($uniqueSourceGroupNames -join "; ")
            SourceGroupKeys    = ($uniqueSourceGroupKeys -join "; ")
            DistinguishedName  = Join-UniqueValues -Values $rawRows.DistinguishedName
        })
    }

    $sortedReportRows = $reportRows | Sort-Object MembershipCategory, DisplayName, UserDomain, SamAccountName
    $multipleGroupUsers = @($sortedReportRows | Where-Object { $_.MembershipCategory -eq "MultipleGroups" })
    $singleGroupUsers = @($sortedReportRows | Where-Object { $_.MembershipCategory -eq "SingleGroup" })

    if ([string]::IsNullOrWhiteSpace($OutputPrefix)) {
        $OutputPrefix = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInputCsv)
    }

    New-DirectoryIfMissing -Path $OutputDirectory
    $resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

    if ([string]::IsNullOrWhiteSpace($MultipleGroupsCsvPath)) {
        $MultipleGroupsCsvPath = Join-Path -Path $resolvedOutputDirectory -ChildPath ("{0}-multiple-groups.csv" -f $OutputPrefix)
    }

    if ([string]::IsNullOrWhiteSpace($SingleGroupCsvPath)) {
        $SingleGroupCsvPath = Join-Path -Path $resolvedOutputDirectory -ChildPath ("{0}-single-group.csv" -f $OutputPrefix)
    }

    New-ParentDirectoryIfMissing -Path $MultipleGroupsCsvPath
    New-ParentDirectoryIfMissing -Path $SingleGroupCsvPath

    $multipleGroupUsers | Export-Csv -LiteralPath $MultipleGroupsCsvPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter
    $singleGroupUsers | Export-Csv -LiteralPath $SingleGroupCsvPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

    $resolvedMultipleGroupsCsvPath = (Resolve-Path -LiteralPath $MultipleGroupsCsvPath).Path
    $resolvedSingleGroupCsvPath = (Resolve-Path -LiteralPath $SingleGroupCsvPath).Path

    Write-Host ""
    Write-Host "AD group membership split report" -ForegroundColor Cyan
    Write-Host ("Input rows            : {0}" -f $rows.Count)
    Write-Host ("Rows analyzed         : {0}" -f @($filteredRows).Count)
    Write-Host ("Users analyzed        : {0}" -f @($sortedReportRows).Count)
    Write-Host ("Multiple-group users  : {0}" -f $multipleGroupUsers.Count) -ForegroundColor Green
    Write-Host ("Single-group users    : {0}" -f $singleGroupUsers.Count) -ForegroundColor Green

    if ($nonUserRowsSkipped -gt 0) {
        Write-Host ("Non-user rows skipped : {0}" -f $nonUserRowsSkipped) -ForegroundColor Yellow
    }

    if ($lookupFailureRowsSkipped -gt 0) {
        Write-Host ("Lookup rows skipped   : {0}" -f $lookupFailureRowsSkipped) -ForegroundColor Yellow
    }

    Write-Host ("Multiple CSV          : {0}" -f $resolvedMultipleGroupsCsvPath) -ForegroundColor Cyan
    Write-Host ("Single CSV            : {0}" -f $resolvedSingleGroupCsvPath) -ForegroundColor Cyan

    if ($PassThru.IsPresent) {
        $sortedReportRows
    }
}
