# Module Design

This project keeps two ways of working:

- module commands for `Import-Module` usage
- standalone `.ps1` wrappers for direct execution

The actual implementation lives in the module under `src/ADGroupUserReporting`.

## Public Commands

The public commands are stored in `src/ADGroupUserReporting/Public`:

- `Get-ADGroupUserReport`
- `Get-ADGroupUserReportBatch`
- `Split-ADGroupUserReport`

These are exported by `ADGroupUserReporting.psm1` and listed in `ADGroupUserReporting.psd1`.

## Private Helpers

Shared helper functions are stored in `src/ADGroupUserReporting/Private`.

Examples include:

- domain discovery
- LDAP escaping
- AD property access
- report row construction
- CSV grouping helpers

Private helpers are dot-sourced into the module but are not exported.

## Standalone Scripts

The files in `scripts/` are thin wrappers. They import the local module manifest and call the matching public command.

This keeps behavior consistent between:

```powershell
Get-ADGroupUserReport ...
```

and:

```powershell
.\scripts\Get-ADGroupUserReport.ps1 ...
```
