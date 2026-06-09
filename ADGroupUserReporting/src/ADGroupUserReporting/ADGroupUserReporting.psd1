@{
    RootModule = 'ADGroupUserReporting.psm1'
    ModuleVersion = '1.0.0'
    GUID = '9f86c872-b13e-4b8d-9555-96a8377d4f63'
    Author = 'ADGroupUserReporting contributors'
    CompanyName = 'Community'
    Copyright = '(c) ADGroupUserReporting contributors. All rights reserved.'
    Description = 'PowerShell toolkit for Active Directory group membership reporting, enriched user exports, and membership overlap analysis.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-ADGroupUserReport',
        'Get-ADGroupUserReportBatch',
        'Split-ADGroupUserReport'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ActiveDirectory', 'AD', 'Groups', 'Reporting', 'Audit')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ExternalModuleDependencies = @('ActiveDirectory')
            ReleaseNotes = 'Initial module-ready release.'
        }
    }
}
