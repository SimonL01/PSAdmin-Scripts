<#
.SYNOPSIS
    Standalone wrapper for Split-ADGroupUserReport.
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

$modulePath = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\src\ADGroupUserReporting\ADGroupUserReporting.psd1')
Import-Module $modulePath.Path -Force
Split-ADGroupUserReport @PSBoundParameters
