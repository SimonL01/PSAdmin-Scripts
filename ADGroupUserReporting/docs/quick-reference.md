# Quick Reference

Import the module:

```powershell
Import-Module .\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force
```

Single group:

```powershell
Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com `
    -CsvPath .\single_group_export.csv
```

Multiple groups:

```powershell
Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B","Group C" `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv
```

Split membership overlap:

```powershell
Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports
```

Forest discovery:

```powershell
Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -DiscoverForestDomains `
    -CsvPath .\single_group_export.csv
```

Semicolon delimiter:

```powershell
Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B" `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv `
    -CsvDelimiter ";"

Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports `
    -Delimiter ";"
```
