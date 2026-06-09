<#
.SYNOPSIS
    Standalone wrapper for Get-ADGroupUserReportBatch.
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
    $modulePath = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\src\ADGroupUserReporting\ADGroupUserReporting.psd1')
    Import-Module $modulePath.Path -Force
    $script:boundParameters = @{} + $PSBoundParameters
}

process {
    if ($PSBoundParameters.ContainsKey("GroupName")) {
        $script:boundParameters["GroupName"] = $GroupName
    }
}

end {
    Get-ADGroupUserReportBatch @script:boundParameters
}
