[cmdletBinding()]
param(
    [parameter()]
    [string[]]
    $Packages = @('googlechrome','firefox','git','discord','microsoft-teams','zoom','gotomeeting','skype','skypeforbusiness','slack','vscode','adobereader','foxitreader','spotify','gitkraken','git-fork'),

    [parameter()]
    [string]
    $RepositoryUrl = 'http://localhost:8081/repository/Internal',

    [parameter()]
    [string]
    $RemoteRepo = 'https://chocolatey.org/api/v2'

    [parameter()]
    [string]
    $NexusApiKey = $NugetApiKey

)


process {
    
    if(!(Test-Path "$env:ChocolateyInstall\license")){
        throw "Licensed edition required to use Package Internalizer"
    }

    $Guid = [Guid]::NewGuid().Guid
    $null = New-Item "$env:TEMP\$($Guid)" -ItemType Directory

    foreach ($package in $packages) {
        choco download $package --internalize --output-directory "$env:TEMP\$Guid" --no-progress --internalize-all-urls --append-use-original-location -s $RemoteRepo
    }

    Get-ChildItem "$env:TEMP\$Guid" -Filter *.nupkg -Recurse | Foreach-Object {
        choco push $_.Fullname -s $RepositoryUrl --api-key $NexusApiKey
    }

    Remove-Item "$env:TEMP\$Guid" -Recurse -Force

}