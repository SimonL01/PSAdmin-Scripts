Import-Module ..\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B","Group C" `
    -TargetDomains corp.example.com,admin.example.com `
    -CsvPath .\multi_group_export.csv
