function ConvertTo-LdapEscapedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $escapedValue = $Value -replace "\\", "\5c"
    $escapedValue = $escapedValue -replace "\*", "\2a"
    $escapedValue = $escapedValue -replace "\(", "\28"
    $escapedValue = $escapedValue -replace "\)", "\29"
    $escapedValue = $escapedValue -replace "`0", "\00"

    return $escapedValue
}

function Get-ADObjectProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-DomainFromDistinguishedName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownDomains,

        [Parameter()]
        [AllowNull()]
        [string]$FallbackDomain
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return $FallbackDomain
    }

    $dcMatches = [regex]::Matches($DistinguishedName, "(?i)(?:^|,)DC=([^,]+)")
    if ($dcMatches.Count -eq 0) {
        return $FallbackDomain
    }

    $domainFromDn = ($dcMatches | ForEach-Object { $_.Groups[1].Value }) -join "."
    foreach ($knownDomain in $KnownDomains) {
        if ($knownDomain.Equals($domainFromDn, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $knownDomain
        }
    }

    return $domainFromDn
}

function Get-OrderedDomainCandidates {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$PreferredDomain,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownDomains
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PreferredDomain)) {
        [void]$candidates.Add($PreferredDomain)
    }

    foreach ($domain in $KnownDomains) {
        if ([string]::IsNullOrWhiteSpace($domain)) {
            continue
        }

        $alreadyAdded = $false
        foreach ($candidate in $candidates) {
            if ($candidate.Equals($domain, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyAdded = $true
                break
            }
        }

        if (-not $alreadyAdded) {
            [void]$candidates.Add($domain)
        }
    }

    return $candidates.ToArray()
}

function Find-ADGroupInDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $escapedGroupName = ConvertTo-LdapEscapedValue -Value $Name
    $ldapFilter = "(|(name=$escapedGroupName)(sAMAccountName=$escapedGroupName)(distinguishedName=$escapedGroupName))"

    try {
        return @(Get-ADGroup -LDAPFilter $ldapFilter -Server $Domain -Properties Description, ManagedBy, GroupCategory, GroupScope, Mail, WhenCreated, WhenChanged -ErrorAction Stop)
    }
    catch {
        Write-Warning ("Unable to search domain '{0}' for group '{1}': {2}" -f $Domain, $Name, $_.Exception.Message)
        return @()
    }
}

function Resolve-ADUserForMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Member,

        [Parameter(Mandatory = $true)]
        [string]$SourceDomain,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownDomains,

        [Parameter(Mandatory = $true)]
        [string[]]$Properties
    )

    $memberDomain = Get-DomainFromDistinguishedName -DistinguishedName $Member.DistinguishedName -KnownDomains $KnownDomains -FallbackDomain $SourceDomain
    $lookupDomains = Get-OrderedDomainCandidates -PreferredDomain $memberDomain -KnownDomains $KnownDomains
    $lastError = $null

    foreach ($domain in $lookupDomains) {
        try {
            $user = Get-ADUser -Identity $Member.DistinguishedName -Server $domain -Properties $Properties -ErrorAction Stop
            return [PSCustomObject]@{
                User        = $user
                Domain      = $domain
                LookupError = $null
            }
        }
        catch {
            $lastError = $_.Exception.Message
            Write-Verbose ("Unable to resolve '{0}' as a user in '{1}': {2}" -f $Member.DistinguishedName, $domain, $lastError)
        }
    }

    return [PSCustomObject]@{
        User        = $null
        Domain      = $memberDomain
        LookupError = $lastError
    }
}

function Resolve-ManagerName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$ManagerDistinguishedName,

        [Parameter(Mandatory = $true)]
        [string]$UserDomain,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownDomains
    )

    if ([string]::IsNullOrWhiteSpace($ManagerDistinguishedName)) {
        return $null
    }

    $managerDomain = Get-DomainFromDistinguishedName -DistinguishedName $ManagerDistinguishedName -KnownDomains $KnownDomains -FallbackDomain $UserDomain
    $lookupDomains = Get-OrderedDomainCandidates -PreferredDomain $managerDomain -KnownDomains $KnownDomains

    foreach ($domain in $lookupDomains) {
        try {
            $manager = Get-ADUser -Identity $ManagerDistinguishedName -Server $domain -Properties DisplayName, SamAccountName -ErrorAction Stop
            $managerDisplayName = Get-ADObjectProperty -InputObject $manager -Name "DisplayName"
            $managerSamAccountName = Get-ADObjectProperty -InputObject $manager -Name "SamAccountName"

            if (-not [string]::IsNullOrWhiteSpace($managerDisplayName) -and -not [string]::IsNullOrWhiteSpace($managerSamAccountName)) {
                return ("{0} ({1})" -f $managerDisplayName, $managerSamAccountName)
            }

            if (-not [string]::IsNullOrWhiteSpace($managerDisplayName)) {
                return $managerDisplayName
            }

            if (-not [string]::IsNullOrWhiteSpace($managerSamAccountName)) {
                return $managerSamAccountName
            }
        }
        catch {
            Write-Verbose ("Unable to resolve manager '{0}' in '{1}': {2}" -f $ManagerDistinguishedName, $domain, $_.Exception.Message)
        }
    }

    return $ManagerDistinguishedName
}

function Get-DirectGroupNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$User,

        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $memberOf = Get-ADObjectProperty -InputObject $User -Name "MemberOf"
    if ($null -eq $memberOf) {
        return $null
    }

    $groupNames = foreach ($groupDn in @($memberOf)) {
        try {
            (Get-ADGroup -Identity $groupDn -Server $Domain -Properties Name -ErrorAction Stop).Name
        }
        catch {
            Write-Verbose ("Unable to resolve direct group '{0}' in '{1}': {2}" -f $groupDn, $Domain, $_.Exception.Message)
            $groupDn
        }
    }

    return (($groupNames | Sort-Object) -join "; ")
}

function New-UserReportRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string]$GroupDomain,

        [Parameter(Mandatory = $true)]
        [object]$User,

        [Parameter(Mandatory = $true)]
        [string]$UserDomain,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownDomains,

        [Parameter(Mandatory = $true)]
        [bool]$ResolveDirectGroups
    )

    $emailAddress = Get-ADObjectProperty -InputObject $User -Name "EmailAddress"
    if ([string]::IsNullOrWhiteSpace($emailAddress)) {
        $emailAddress = Get-ADObjectProperty -InputObject $User -Name "mail"
    }

    $memberOf = Get-ADObjectProperty -InputObject $User -Name "MemberOf"
    if ($null -eq $memberOf) {
        $directGroupCount = 0
    }
    else {
        $directGroupCount = @($memberOf).Count
    }

    $managerDistinguishedName = Get-ADObjectProperty -InputObject $User -Name "Manager"
    $managerName = Resolve-ManagerName -ManagerDistinguishedName $managerDistinguishedName -UserDomain $UserDomain -KnownDomains $KnownDomains

    $directGroups = $null
    if ($ResolveDirectGroups) {
        $directGroups = Get-DirectGroupNames -User $User -Domain $UserDomain
    }

    $created = Get-ADObjectProperty -InputObject $User -Name "whenCreated"
    if ($null -eq $created) {
        $created = Get-ADObjectProperty -InputObject $User -Name "Created"
    }

    $modified = Get-ADObjectProperty -InputObject $User -Name "whenChanged"
    if ($null -eq $modified) {
        $modified = Get-ADObjectProperty -InputObject $User -Name "Modified"
    }

    [PSCustomObject]@{
        SourceGroupDomain            = $GroupDomain
        SourceGroupName              = Get-ADObjectProperty -InputObject $Group -Name "Name"
        SourceGroupSamAccountName    = Get-ADObjectProperty -InputObject $Group -Name "SamAccountName"
        SourceGroupDistinguishedName = Get-ADObjectProperty -InputObject $Group -Name "DistinguishedName"
        UserDomain                   = $UserDomain
        ObjectClass                  = "user"
        DisplayName                  = Get-ADObjectProperty -InputObject $User -Name "DisplayName"
        Name                         = Get-ADObjectProperty -InputObject $User -Name "Name"
        SamAccountName               = Get-ADObjectProperty -InputObject $User -Name "SamAccountName"
        UserPrincipalName            = Get-ADObjectProperty -InputObject $User -Name "UserPrincipalName"
        Mail                         = $emailAddress
        Enabled                      = Get-ADObjectProperty -InputObject $User -Name "Enabled"
        LockedOut                    = Get-ADObjectProperty -InputObject $User -Name "LockedOut"
        GivenName                    = Get-ADObjectProperty -InputObject $User -Name "GivenName"
        Surname                      = Get-ADObjectProperty -InputObject $User -Name "Surname"
        Title                        = Get-ADObjectProperty -InputObject $User -Name "Title"
        Department                   = Get-ADObjectProperty -InputObject $User -Name "Department"
        Company                      = Get-ADObjectProperty -InputObject $User -Name "Company"
        Office                       = Get-ADObjectProperty -InputObject $User -Name "Office"
        OfficePhone                  = Get-ADObjectProperty -InputObject $User -Name "OfficePhone"
        MobilePhone                  = Get-ADObjectProperty -InputObject $User -Name "MobilePhone"
        Manager                      = $managerName
        ManagerDistinguishedName     = $managerDistinguishedName
        EmployeeID                   = Get-ADObjectProperty -InputObject $User -Name "EmployeeID"
        EmployeeNumber               = Get-ADObjectProperty -InputObject $User -Name "EmployeeNumber"
        Description                  = Get-ADObjectProperty -InputObject $User -Name "Description"
        LastLogonDate                = Get-ADObjectProperty -InputObject $User -Name "LastLogonDate"
        PasswordLastSet              = Get-ADObjectProperty -InputObject $User -Name "PasswordLastSet"
        PasswordNeverExpires         = Get-ADObjectProperty -InputObject $User -Name "PasswordNeverExpires"
        AccountExpirationDate        = Get-ADObjectProperty -InputObject $User -Name "AccountExpirationDate"
        Created                      = $created
        Modified                     = $modified
        DirectGroupCount             = $directGroupCount
        DirectGroups                 = $directGroups
        CanonicalName                = Get-ADObjectProperty -InputObject $User -Name "CanonicalName"
        DistinguishedName            = Get-ADObjectProperty -InputObject $User -Name "DistinguishedName"
        LookupStatus                 = "OK"
        LookupMessage                = $null
    }
}

function New-NonUserReportRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string]$GroupDomain,

        [Parameter(Mandatory = $true)]
        [object]$Member
    )

    [PSCustomObject]@{
        SourceGroupDomain            = $GroupDomain
        SourceGroupName              = Get-ADObjectProperty -InputObject $Group -Name "Name"
        SourceGroupSamAccountName    = Get-ADObjectProperty -InputObject $Group -Name "SamAccountName"
        SourceGroupDistinguishedName = Get-ADObjectProperty -InputObject $Group -Name "DistinguishedName"
        UserDomain                   = $GroupDomain
        ObjectClass                  = Get-ADObjectProperty -InputObject $Member -Name "ObjectClass"
        DisplayName                  = Get-ADObjectProperty -InputObject $Member -Name "Name"
        Name                         = Get-ADObjectProperty -InputObject $Member -Name "Name"
        SamAccountName               = Get-ADObjectProperty -InputObject $Member -Name "SamAccountName"
        UserPrincipalName            = $null
        Mail                         = $null
        Enabled                      = $null
        LockedOut                    = $null
        GivenName                    = $null
        Surname                      = $null
        Title                        = $null
        Department                   = $null
        Company                      = $null
        Office                       = $null
        OfficePhone                  = $null
        MobilePhone                  = $null
        Manager                      = $null
        ManagerDistinguishedName     = $null
        EmployeeID                   = $null
        EmployeeNumber               = $null
        Description                  = $null
        LastLogonDate                = $null
        PasswordLastSet              = $null
        PasswordNeverExpires         = $null
        AccountExpirationDate        = $null
        Created                      = $null
        Modified                     = $null
        DirectGroupCount             = $null
        DirectGroups                 = $null
        CanonicalName                = $null
        DistinguishedName            = Get-ADObjectProperty -InputObject $Member -Name "DistinguishedName"
        LookupStatus                 = "NonUserMember"
        LookupMessage                = "Object is not an AD user."
    }
}

function New-UnresolvedUserReportRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string]$GroupDomain,

        [Parameter(Mandatory = $true)]
        [object]$Member,

        [Parameter()]
        [AllowNull()]
        [string]$UserDomain,

        [Parameter()]
        [AllowNull()]
        [string]$LookupError
    )

    [PSCustomObject]@{
        SourceGroupDomain            = $GroupDomain
        SourceGroupName              = Get-ADObjectProperty -InputObject $Group -Name "Name"
        SourceGroupSamAccountName    = Get-ADObjectProperty -InputObject $Group -Name "SamAccountName"
        SourceGroupDistinguishedName = Get-ADObjectProperty -InputObject $Group -Name "DistinguishedName"
        UserDomain                   = $UserDomain
        ObjectClass                  = Get-ADObjectProperty -InputObject $Member -Name "ObjectClass"
        DisplayName                  = Get-ADObjectProperty -InputObject $Member -Name "Name"
        Name                         = Get-ADObjectProperty -InputObject $Member -Name "Name"
        SamAccountName               = Get-ADObjectProperty -InputObject $Member -Name "SamAccountName"
        UserPrincipalName            = $null
        Mail                         = $null
        Enabled                      = $null
        LockedOut                    = $null
        GivenName                    = $null
        Surname                      = $null
        Title                        = $null
        Department                   = $null
        Company                      = $null
        Office                       = $null
        OfficePhone                  = $null
        MobilePhone                  = $null
        Manager                      = $null
        ManagerDistinguishedName     = $null
        EmployeeID                   = $null
        EmployeeNumber               = $null
        Description                  = $null
        LastLogonDate                = $null
        PasswordLastSet              = $null
        PasswordNeverExpires         = $null
        AccountExpirationDate        = $null
        Created                      = $null
        Modified                     = $null
        DirectGroupCount             = $null
        DirectGroups                 = $null
        CanonicalName                = $null
        DistinguishedName            = Get-ADObjectProperty -InputObject $Member -Name "DistinguishedName"
        LookupStatus                 = "UserLookupFailed"
        LookupMessage                = $LookupError
    }
}

function Get-SafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return ($Value -replace '[\\/:*?"<>|]', "_")
}

function Resolve-TargetDomains {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Domains,

        [Parameter()]
        [bool]$UseForestDiscovery
    )

    $resolvedDomains = New-Object System.Collections.Generic.List[string]

    foreach ($domain in @($Domains)) {
        if ([string]::IsNullOrWhiteSpace($domain)) {
            continue
        }

        $cleanDomain = $domain.Trim()
        $alreadyAdded = $false

        foreach ($resolvedDomain in $resolvedDomains) {
            if ($resolvedDomain.Equals($cleanDomain, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyAdded = $true
                break
            }
        }

        if (-not $alreadyAdded) {
            [void]$resolvedDomains.Add($cleanDomain)
        }
    }

    if ($resolvedDomains.Count -gt 0) {
        if ($UseForestDiscovery) {
            Write-Verbose "-TargetDomains was supplied; skipping forest discovery."
        }

        return $resolvedDomains.ToArray()
    }

    if (-not $UseForestDiscovery) {
        throw "Specify -TargetDomains, or use -DiscoverForestDomains to query all domains in the current AD forest."
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $forestDomains = @((Get-ADForest -ErrorAction Stop).Domains)
    }
    catch {
        throw "Unable to discover forest domains. Specify -TargetDomains explicitly. Details: $($_.Exception.Message)"
    }

    foreach ($domain in $forestDomains) {
        if (-not [string]::IsNullOrWhiteSpace($domain)) {
            [void]$resolvedDomains.Add($domain.Trim())
        }
    }

    if ($resolvedDomains.Count -eq 0) {
        throw "Forest discovery did not return any domains. Specify -TargetDomains explicitly."
    }

    return $resolvedDomains.ToArray()
}

function Add-RequestedGroupName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$List,

        [Parameter()]
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $cleanValue = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanValue)) {
        return
    }

    foreach ($existingValue in $List) {
        if ($existingValue.Equals($cleanValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    [void]$List.Add($cleanValue)
}

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-ObjectProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return ($null -ne $InputObject.PSObject.Properties[$Name])
}

function Join-UniqueValues {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]]$Values,

        [Parameter()]
        [string]$Separator = "; "
    )

    $cleanValues = @(
        foreach ($value in @($Values)) {
            if ($null -eq $value) {
                continue
            }

            $stringValue = [string]$value
            if ([string]::IsNullOrWhiteSpace($stringValue)) {
                continue
            }

            $stringValue.Trim()
        }
    )

    return (($cleanValues | Sort-Object -Unique) -join $Separator)
}

function Get-UserIdentityKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [int]$RowNumber
    )

    $distinguishedName = Get-ObjectPropertyValue -InputObject $Row -Name "DistinguishedName"
    if (-not [string]::IsNullOrWhiteSpace($distinguishedName)) {
        return "dn::$distinguishedName"
    }

    $userDomain = Get-ObjectPropertyValue -InputObject $Row -Name "UserDomain"
    $samAccountName = Get-ObjectPropertyValue -InputObject $Row -Name "SamAccountName"
    if (-not [string]::IsNullOrWhiteSpace($userDomain) -and -not [string]::IsNullOrWhiteSpace($samAccountName)) {
        return ("sam::{0}\{1}" -f $userDomain, $samAccountName)
    }

    $userPrincipalName = Get-ObjectPropertyValue -InputObject $Row -Name "UserPrincipalName"
    if (-not [string]::IsNullOrWhiteSpace($userPrincipalName)) {
        return "upn::$userPrincipalName"
    }

    $displayName = Get-ObjectPropertyValue -InputObject $Row -Name "DisplayName"
    if (-not [string]::IsNullOrWhiteSpace($displayName)) {
        return "display::$displayName"
    }

    return "row::$RowNumber"
}

function Get-SourceGroupKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row
    )

    $sourceGroupDn = Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupDistinguishedName"
    if (-not [string]::IsNullOrWhiteSpace($sourceGroupDn)) {
        return "dn::$sourceGroupDn"
    }

    $sourceGroupDomain = Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupDomain"
    $sourceGroupName = Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupName"
    if (-not [string]::IsNullOrWhiteSpace($sourceGroupDomain) -and -not [string]::IsNullOrWhiteSpace($sourceGroupName)) {
        return ("name::{0}\{1}" -f $sourceGroupDomain, $sourceGroupName)
    }

    if (-not [string]::IsNullOrWhiteSpace($sourceGroupName)) {
        return "name::$sourceGroupName"
    }

    return "unknown-source-group"
}

function Get-SourceGroupDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row
    )

    $sourceGroupDomain = Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupDomain"
    $sourceGroupName = Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupName"

    if (-not [string]::IsNullOrWhiteSpace($sourceGroupDomain) -and -not [string]::IsNullOrWhiteSpace($sourceGroupName)) {
        return ("{0}\{1}" -f $sourceGroupDomain, $sourceGroupName)
    }

    if (-not [string]::IsNullOrWhiteSpace($sourceGroupName)) {
        return $sourceGroupName
    }

    return (Get-ObjectPropertyValue -InputObject $Row -Name "SourceGroupDistinguishedName")
}

function New-DirectoryIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function New-ParentDirectoryIfMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-DirectoryIfMissing -Path $parent
    }
}
