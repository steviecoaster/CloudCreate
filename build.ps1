Set-ExecutionPolicy Bypass -Scope Process -Force
@('https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Build/InstallChocolatey.ps1',
'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Build/InstallSelenium.ps1',
'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Build/InstallNexusAndSeed.ps1',
'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Build/InstallJenkins.ps1',
'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Build/FirewallRules.ps1') | Foreach-Object {

    Invoke-Expression (New-Object System.Net.WebClient).DownloadString("$_")
}