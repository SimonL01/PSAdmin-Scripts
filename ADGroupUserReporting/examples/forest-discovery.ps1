Import-Module ..\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -DiscoverForestDomains `
    -CsvPath .\single_group_export.csv
