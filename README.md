# PSAdmin-Scripts

Professional PowerShell administration toolkits for reporting, auditing, and day-to-day operational support.

## Overview

`PSAdmin-Scripts` is a collection of focused PowerShell modules and standalone scripts for system administrators. The repository is designed around a practical pattern:

- each toolkit has its own folder
- each toolkit can expose importable PowerShell module commands
- standalone `.ps1` wrappers are kept for quick execution
- examples and documentation live beside the toolkit they describe
- environment-specific values such as domains, servers, paths, and group names are passed as parameters, not hard-coded

The goal is to keep the tools useful at the console while still being clean enough to reuse, share, and version like a proper PowerShell project.

## Toolkits

| Toolkit | Status | Description |
| --- | --- | --- |
| [`ADGroupUserReporting`](./ADGroupUserReporting/README.md) | Ready | Active Directory group membership reporting, enriched user exports, and membership overlap analysis. |

More toolkits can be added later using the same structure.

## Repository Layout

```text
PSAdmin-Scripts/
├─ README.md
├─ ADGroupUserReporting/
│  ├─ README.md
│  ├─ src/
│  │  └─ ADGroupUserReporting/
│  │     ├─ ADGroupUserReporting.psd1
│  │     ├─ ADGroupUserReporting.psm1
│  │     ├─ Public/
│  │     └─ Private/
│  ├─ scripts/
│  ├─ examples/
│  └─ docs/
└─ ...
```

Recommended structure for each toolkit:

- `src/<ModuleName>/`: importable PowerShell module.
- `src/<ModuleName>/Public/`: exported commands.
- `src/<ModuleName>/Private/`: internal helper functions.
- `scripts/`: standalone wrappers for direct `.ps1` usage.
- `examples/`: copy/pasteable usage examples.
- `docs/`: detailed notes, design references, and quick references.

## Quick Start

Clone the repository:

```powershell
git clone https://github.com/<your-account>/PSAdmin-Scripts.git
cd PSAdmin-Scripts
```

Import a toolkit module directly from the repository:

```powershell
Import-Module .\ADGroupUserReporting\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force
```

List available commands:

```powershell
Get-Command -Module ADGroupUserReporting
```

Run a command:

```powershell
Get-ADGroupUserReport `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com `
    -CsvPath .\single_group_export.csv
```

## Optional Local Module Install

For daily use, copy a toolkit module into a PowerShell module path so it can be imported by name.

Windows PowerShell:

```powershell
$moduleRoot = Join-Path $HOME 'Documents\WindowsPowerShell\Modules\ADGroupUserReporting'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
Copy-Item -Path .\ADGroupUserReporting\src\ADGroupUserReporting\* -Destination $moduleRoot -Recurse -Force
Import-Module ADGroupUserReporting
```

PowerShell 7:

```powershell
$moduleRoot = Join-Path $HOME 'Documents\PowerShell\Modules\ADGroupUserReporting'
New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
Copy-Item -Path .\ADGroupUserReporting\src\ADGroupUserReporting\* -Destination $moduleRoot -Recurse -Force
Import-Module ADGroupUserReporting
```

After that:

```powershell
Import-Module ADGroupUserReporting
```

## Standalone Script Usage

Each toolkit may also provide standalone scripts in its `scripts/` folder. These are thin wrappers around the module commands.

Example:

```powershell
.\ADGroupUserReporting\scripts\Get-ADGroupUserReport.ps1 `
    -GroupName "Example Group" `
    -TargetDomains corp.example.com `
    -CsvPath .\single_group_export.csv
```

Use module commands for automation and reuse. Use standalone scripts when you want quick direct execution without thinking about module import paths.

## Current Toolkit: ADGroupUserReporting

`ADGroupUserReporting` provides three public commands:

```powershell
Get-ADGroupUserReport
Get-ADGroupUserReportBatch
Split-ADGroupUserReport
```

Typical workflow:

```powershell
Import-Module .\ADGroupUserReporting\src\ADGroupUserReporting\ADGroupUserReporting.psd1 -Force

Get-ADGroupUserReportBatch `
    -GroupName "Group A","Group B","Group C" `
    -TargetDomains corp.example.com `
    -CsvPath .\multi_group_export.csv

Split-ADGroupUserReport `
    -InputCsv .\multi_group_export.csv `
    -OutputDirectory .\reports
```

See the toolkit documentation for full usage:

- [ADGroupUserReporting README](./ADGroupUserReporting/README.md)
- [Quick reference](./ADGroupUserReporting/docs/quick-reference.md)
- [Module design](./ADGroupUserReporting/docs/module-design.md)

## Requirements

General:

- Windows PowerShell 5.1 or PowerShell 7 where supported by the toolkit.
- Execution policy that allows local scripts or signed scripts, depending on your environment.
- Appropriate administrative or read permissions for the systems being queried.

For Active Directory tooling:

- RSAT Active Directory tools.
- `ActiveDirectory` PowerShell module.
- Network access to target domains or domain controllers.

Individual toolkits may have their own requirements. Check each toolkit README.

## Design Principles

- No hard-coded organization-specific domains, paths, servers, or group names.
- Public commands use approved PowerShell verbs.
- Shared logic belongs in module `Private/` helpers.
- Exported commands belong in module `Public/`.
- Standalone scripts stay thin and call module commands.
- Commands should support pipeline-friendly output where practical.
- CSV exports should allow explicit paths and delimiter selection.
- Documentation should include realistic but generic examples.

## Security Notes

These scripts are intended for administrative reporting and operational support.

- Review scripts before running them in production.
- Test first in a non-production environment when possible.
- Run with the least privilege needed for the report or operation.
- Avoid committing generated CSV exports, logs, or files containing internal data.
- Keep environment-specific details out of code and documentation.

## Contributing

When adding a new toolkit:

1. Create a new top-level folder for the toolkit.
2. Use a module-first structure under `src/`.
3. Place exported functions in `Public/`.
4. Place helper functions in `Private/`.
5. Add standalone wrappers under `scripts/` only when useful.
6. Add examples and a toolkit README.
7. Update the root toolkit table.

Before committing:

```powershell
Test-ModuleManifest .\<Toolkit>\src\<ModuleName>\<ModuleName>.psd1
```

And parse-check PowerShell files:

```powershell
$files = Get-ChildItem -Path . -Recurse -Include *.ps1,*.psm1,*.psd1
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object {
            "{0} line {1}: {2}" -f $file.FullName, $_.Extent.StartLineNumber, $_.Message
        }
    }
}
```

## Roadmap Ideas

- Add Pester tests for module commands.
- Add PSScriptAnalyzer configuration.
- Add CI validation for manifests and parser checks.
- Add more focused admin toolkits as separate modules.
- Add release packaging for each module.

## License

MIT License
