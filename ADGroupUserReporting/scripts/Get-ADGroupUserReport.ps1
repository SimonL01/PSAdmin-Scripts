<#
.SYNOPSIS
    Standalone wrapper for Get-ADGroupUserReport.
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

$modulePath = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\src\ADGroupUserReporting\ADGroupUserReporting.psd1')
Import-Module $modulePath.Path -Force
Get-ADGroupUserReport @PSBoundParameters
