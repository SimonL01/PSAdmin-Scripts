Import-Module ..\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports
