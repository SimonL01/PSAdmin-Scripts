$privateFunctions = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$publicFunctions = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($functionFile in @($privateFunctions + $publicFunctions)) {
    . $functionFile.FullName
}

Export-ModuleMember -Function $publicFunctions.BaseName
