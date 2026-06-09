# ADGroupUserReporting

PowerShell toolkit for Active Directory group membership reporting, enriched user exports, and membership overlap analysis.

## Description

`ADGroupUserReporting` helps administrators answer three common audit questions:

- Who is a member of this Active Directory group?
- Who is a member of these Active Directory groups across one or more domains?
- Which users appear in exactly one source group, and which users appear in multiple source groups?

The project is environment-agnostic. It does not contain hard-coded domains, domain controllers, user paths, or group names. You can provide target domains explicitly with `-TargetDomains`, or query all domains in the current AD forest with `-DiscoverForestDomains`.

## Commands

- `Get-ADGroupUserReport`: report members for one group.
- `Get-ADGroupUserReportBatch`: report members for several groups and combine the results.
- `Split-ADGroupUserReport`: post-process an exported report into single-group and multi-group user reports.

## Requirements

- Windows PowerShell 5.1 or later.
- RSAT Active Directory tools for the AD lookup commands.
- The `ActiveDirectory` PowerShell module available on the admin workstation or server.
- An account with read access to the target AD domains.
- Network access to the target domains or domain controllers.

`Split-ADGroupUserReport` only processes CSV files and does not contact Active Directory.

## Repository Layout

```text
ADGroupUserReporting/
├─ README.md
├─ .gitignore
├─ src/
│  └─ ADGroupUserReporting/
│     ├─ ADGroupUserReporting.psd1
│     ├─ ADGroupUserReporting.psm1
│     ├─ Public/
│     │  ├─ Get-ADGroupUserReport.ps1
│     │  ├─ Get-ADGroupUserReportBatch.ps1
│     │  └─ Split-ADGroupUserReport.ps1
│     └─ Private/
│        └─ ADGroupUserReporting.Private.ps1
├─ scripts/
│  ├─ Get-ADGroupUserReport.ps1
│  ├─ Get-ADGroupUserReportBatch.ps1
│  └─ Split-ADGroupUserReport.ps1
├─ examples/
└─ docs/
```

The `src/` folder contains the importable module. The `scripts/` folder contains standalone wrappers for users who prefer running `.ps1` files directly.

## Import The Module

From the project root:

```powershell
Import-Module .\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force
```

Check exported commands:

```powershell
Get-Command -Module ADGroupUserReporting
```

## Optional Local Install

To import the module by name, copy the module folder into a location in `$env:PSModulePath`.

For the current user on Windows PowerShell:

```powershell
$moduleRoot = Join-Path $HOME 'Documents\WindowsPowerShell\Modules\ADGroupUserReporting'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
Copy-Item -Path .\src\ADGroupUserReporting\* -Destination $moduleRoot -Recurse -Force
Import-Module ADGroupUserReporting
```

For PowerShell 7:

```powershell
$moduleRoot = Join-Path $HOME 'Documents\PowerShell\Modules\ADGroupUserReporting'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
Copy-Item -Path .\src\ADGroupUserReporting\* -Destination $moduleRoot -Recurse -Force
Import-Module ADGroupUserReporting
```

## Quick Reference

Run a single-group report:

```powershell
Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com,admin.example.com `
    -CsvPath .\single_group_export.csv
```

Run a multi-group report:

```powershell
Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B","Group C" `
    -TargetDomains corp.example.com,admin.example.com `
    -CsvPath .\multi_group_export.csv
```

Split the multi-group export into overlap reports:

```powershell
Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports
```

Use forest discovery when the current AD forest is the desired scope:

```powershell
Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -DiscoverForestDomains `
    -CsvPath .\single_group_export.csv
```

Use a semicolon delimiter when needed:

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

The delimiter used by `Split-ADGroupUserReport` must match the delimiter used when the CSV was exported.

## Standalone Scripts

The `scripts/` folder contains direct-run wrappers. They import the local module and call the corresponding command.

```powershell
.\scripts\Get-ADGroupUserReport.ps1 `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com `
    -CsvPath .\single_group_export.csv
```

```powershell
.\scripts\Get-ADGroupUserReportBatch.ps1 `
    -GroupName "Group A","Group B" `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv
```

```powershell
.\scripts\Split-ADGroupUserReport.ps1 `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports
```

## Domain Selection

Use explicit domains when you know exactly where to search:

```powershell
-TargetDomains corp.example.com,admin.example.com
```

Use forest discovery when the current AD forest is the correct search scope:

```powershell
-DiscoverForestDomains
```

Use `-TargetDomains` for trusted domains outside the current forest, specific domain controllers, or when you want a controlled subset of domains.

## Group List File

`Get-ADGroupUserReportBatch` can read group names from a text file.

Example `groups.txt`:

```text
# One group per line
Group A
Group B
Group C
```

Run:

```powershell
Get-ADGroupUserReportBatch `
    -GroupListPath .\groups.txt `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv
```

Blank lines and lines beginning with `#` are ignored.

## Output

The AD report includes administrator-friendly fields such as:

- source group and source domain
- user domain
- display name
- sAMAccountName
- UPN
- mail
- enabled and locked-out state
- department, title, company, office, and phone fields
- manager
- last logon date
- password metadata
- distinguished name
- lookup status and lookup message

`Split-ADGroupUserReport` creates two CSV files by default:

- `<input-name>-multiple-groups.csv`
- `<input-name>-single-group.csv`

## Notes For Contributors

Public functions live in `src/ADGroupUserReporting/Public`. Shared implementation helpers live in `src/ADGroupUserReporting/Private` and are not exported.

The standalone scripts in `scripts/` should stay thin wrappers around the module functions. Keep the core behavior in the module so imported usage and script usage remain consistent.

## Troubleshooting

If the Active Directory module is missing, install RSAT Active Directory tools and run:

```powershell
Import-Module ActiveDirectory
```

If no domains are provided, use one of these patterns:

```powershell
Get-ADGroupUserReport -GroupName "Example Group" -DiscoverForestDomains
```

or:

```powershell
Get-ADGroupUserReport -GroupName "Example Group" -TargetDomains corp.example.com
```

If a group is not found, verify the group name, sAMAccountName, or distinguished name and confirm that the target domain list includes the domain where the group exists.

If lookups are slow, avoid `-IncludeDirectGroups` unless you need direct group membership data for each user.
