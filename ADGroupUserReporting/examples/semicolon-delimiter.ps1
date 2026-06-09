Import-Module ..\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B" `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv `
    -CsvDelimiter ";"

Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports `
    -Delimiter ";"
