[cmdletBinding()]
Param(
    [Parameter()]
    [String[]]
    $Packages,

    [Parameter()]
    [String]
    $RepositoryUrl = 'http://localhost:8081/repository/Internal',

    [Parameter()]
    [String]
    $NexusApiKey = $NugetApiKey

)


process {
    
    if(!(Test-Path "$env:ChocolateyInstall\license")){
        throw "Licensed edition required to use Package Internalizer"
    }

    $Guid = [Guid]::NewGuid().Guid
    $null = New-Item "$env:TEMP\$($Guid)"

    foreach ($package in $packages) {
        choco download $package --internalize --output-directory "$env:TEMP\$Guid"
    }

    Get-ChildItem "$env:TEMP\$Guid" -Filter *.nupkg -Recurse | Foreach-Object {
        choco push $_.Fullname -s $RepositoryUrl --api-key $NexusApiKey
    }

    Remove-Item "$env:TEMP\$Guid" -Recurse -Force

}