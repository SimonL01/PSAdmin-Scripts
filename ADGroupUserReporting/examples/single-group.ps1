Import-Module ..\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com,admin.example.com `
    -CsvPath .\single_group_export.csv
