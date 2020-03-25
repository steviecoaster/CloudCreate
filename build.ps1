[cmdletBinding()]
param(
  [parameter()]
  [string]
  $TaskUser,

  [parameter()]
  [string]
  $TaskPass
)

Function Install-Chocolatey {
  Set-ExecutionPolicy Bypass -Scope Process -Force
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}


Function Install-SeleniumDependency {
  $null = Install-PackageProvider -Name NuGet -Force
  Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -Verbose
  Install-Module PowershellGet -Force -SkipPublisherCheck -Verbose
  Install-Module Selenium -Force -SkipPublisherCheck -Verbose

  #Import the modules we will need
  Import-Module Selenium -Force
}

Function Get-Scripts {
  $null = New-Item C:\scripts -ItemType Directory
  $null = New-Item C:\jenkinsxml -Itemtype Directory

  @([pscustomobject]@{
          XmlPath = 'C:\jenkinsxml\Internalize packages from the Community Repository.xml'
          Xml = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Pipelines/Internalize%20packages%20from%20the%20Community%20Repository.xml?token=ACCFXQBMU3QPAXDJIXIN4GK6O6XOA'
          Script = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/scripts/ConvertTo-ChocoObject.ps1'
          ScriptPath = 'C:\scripts\ConvertTo-ChocoObject.ps1'
      },
      [pscustomobject]@{
          XmlPath = 'C:\jenkinsxml\Udpate production repository.xml'
          Xml = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Pipelines/Update%20production%20repository.xml?token=ACCFXQHKHVDPLFH3EEWAXNC6O6XOE'
          Script = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/scripts/Update-ProdRepoFromTest.ps1'
          ScriptPath = 'C:\scripts\Update-ProdRepoFromTest.ps1'
      },
      [pscustomobject]@{
          XmlPath = 'C:\jenkinsxml\Update test repository from Chocolatey Community Repository.xml'
          Xml = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/Pipelines/Update%20test%20repository%20from%20Chocolatey%20Community%20Repository.xml?token=ACCFXQASJZTHBQVVPN3PWDS6O6XOI'
          Script = 'https://raw.githubusercontent.com/steviecoaster/CloudCreate/master/scripts/Get-UpdatedPackage.ps1'
          ScriptPath = 'C:\scripts\Get-UpdatedPackage.ps1'
      }
  ) | Foreach-Object {

      [system.net.webclient]::new().DownloadString("$($_.Xml)") | Set-Content $_.XmlPath
      [system.net.webclient]::new().DownloadString("$($_.Script)") | Set-Content $_.ScriptPath
  }
  [system.net.webclient]::new().DownloadFile('https://github.com/steviecoaster/CloudCreate/raw/master/jenkins-cli.jar','C:\jenkinsxml\jenkins-cli.jar')
}

function Invoke-NexusScript {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [String]
        $ServerUri,

        [Parameter(Mandatory)]
        [Hashtable]
        $ApiHeader,
        
        [Parameter(Mandatory)]
        [String]
        $Script
    )

    $scriptName = [GUID]::NewGuid().ToString()
    $body = @{
        name    = $scriptName
        type    = 'groovy'
        content = $Script
    }

    # Call the API
    $baseUri = "$ServerUri/service/rest/v1/script"

    #Store the Script
    $uri = $baseUri
    Invoke-RestMethod -Uri $uri -ContentType 'application/json' -Body $($body | ConvertTo-Json) -Header $ApiHeader -Method Post
    #Run the script
    $uri = "{0}/{1}/run" -f $baseUri, $scriptName
    $result = Invoke-RestMethod -Uri $uri -ContentType 'text/plain' -Header $ApiHeader -Method Post
    #Delete the Script
    $uri = "{0}/{1}" -f $baseUri, $scriptName
    Invoke-RestMethod -Uri $uri -Header $ApiHeader -Method Delete -UseBasicParsing

    $result

}

Function Install-Nexus {
choco install nexus-repository -y --no-progress -s chocolatey
[System.Net.WebClient]::DownoadFile("https://chocolatey.box.com/shared/static/hfb7zzpv3ellfnvljly7wgniryuxudhk.nupkg","D:\packages\chocolatey-nexus-setup.0.1.0.nupkg")
choco install chocolatey-nexus-setup -y -s D:\packages --no-progress

#Global parameter values
$params = @{
    ServerUri      = 'http://localhost:8081'
    BlobStoreName  = 'default'
    Username = 'admin'
    Password = "$(Get-Content 'C:\ProgramData\sonatype-work\nexus3\admin.password')"
}

#Build Authentication Header
$credPair = ("{0}:{1}" -f $params.Username, $params.Password)
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credPair))
$header = @{
    Authorization = "Basic $encodedCreds"
}

#Create Hosted Repository
$createHostedRepoParams = @{
    ServerUri = $params.ServerUri
    ApiHeader = $header
    Script    = @"
import org.sonatype.nexus.repository.Repository;
repository.createNugetHosted("ChocolateyInternal","$($params.BlobStoreName)");
"@
}

Write-Host "Creating Nuget repository: $($params.NuGetRepositoryName)"
$null = Invoke-NexusScript @createHostedRepoParams

#Create Proxy Repository
$createProxyRepoParams = @{
    ServerUri = $params.ServerUri
    ApiHeader = $header
    Script = @"
import org.sonatype.nexus.repository.Repository;
repository.createNugetProxy("ChocolateyCommunity","https://chocolatey.org/api/v2","$($params.BlobStoreName)");
"@
}

Write-Host "Creating NuGet Proxy Repository"
$null = Invoke-NexusScript @createProxyRepoParams

#Create Group Repository
$createGroupRepoParams = @{
    ServerUri = $params.ServerUri
    ApiHeader = $header
    Script = @"
import org.sonatype.nexus.repository.Repository;
repository.createNugetGroup("ChocolateyGroup",["ChocolateyInternal","ChocolateyCommunity"],"$($params.BlobStoreName)")

"@
}

Write-Host "Creating Nuget Group Repository"
$null = Invoke-NexusScript @createGroupRepoParams

#Surface the API Key
$getApiKeyParams = @{
    ServerUri = $params.ServerUri
    ApiHeader = $header
    Script    = @" 
    import org.sonatype.nexus.security.authc.apikey.ApiKeyStore
    import org.sonatype.nexus.security.realm.RealmManager
    import org.apache.shiro.subject.SimplePrincipalCollection
    
    def getOrCreateNuGetApiKey(String userName) {
        realmName = "NexusAuthenticatingRealm"
        apiKeyDomain = "NuGetApiKey"
        principal = new SimplePrincipalCollection(userName, realmName)
        keyStore = container.lookup(ApiKeyStore.class.getName())
        apiKey = keyStore.getApiKey(apiKeyDomain, principal)
        if (apiKey == null) {
            apiKey = keyStore.createApiKey(apiKeyDomain, principal)
        }
        return apiKey.toString()
    }
    
    getOrCreateNuGetApiKey("$($params.Username)")
"@
}

$result = Invoke-NexusScript @getApiKeyParams

#Remove default Nexus Repositories
$defaultRepositories = @('choco-hosted')

Write-Host "Removing default Nexus repositories"
Foreach($default in $defaultRepositories){
    $removalParams = @{
        ServerUri = $params.ServerUri
        ApiHeader = $header
        Script = @"
import org.sonatype.nexus.repository.Repository;
repository.getRepositoryManager().delete("$default");
"@
    }

    $null = Invoke-NexusScript @removalParams
}

$global:NugetApiKey = $result.result

$NuGetApiKey | Set-Content $env:TEMP\NugetApiKey.txt
Write-Host "Seeding repository"

$packages = Get-ChildItem -Path C:\packages -Filter "*.nupkg"

If($Packages.Count -gt 0){
    $packages | Foreach-Object {
        choco push $_.Fullname -s http://localhost:8081/repository/ChocolateyInternal/ --api-key $NugetApiKey --force
    }
}


Write-Host "Configuring choco sources"
choco source add -n Internal_Chocolatey -s http://localhost:8081/repository/ChocolateyGroup/
choco source disable -n chocolatey

Write-Host "Verifying source contents"


}


Function Set-NexusFirewall {
  $fwParams = @{
      DisplayName = "Nexus"
      Direction = "Inbound"
      LocalPort = "8081"
      Protocol = "TCP"
      Action = "Allow"
  }

  New-NetFirewallRule @fwParams
  Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -enabled True
}

Function Install-Jenkins {

  process {
    choco install jenkins -y --no-progress -s https://chocolatey.org/api/v2 --no-progress
    choco install googlechrome --version=79.0.3945.130 -s https://chocolatey.org/api/v2 -y --ignore-checksums --no-progress
    choco install selenium-chrome-driver --version=79.0.3945.36 -y --no-progress -s https://chocolatey.org/api/v2
    $VerbosePreference = 'Continue'
    Import-Module Selenium -Force -Verbose

    Write-Verbose -Message "Ensuring appropriate Chrome Assembly is loaded"
    $ModuleBase = (Get-Module -ListAvailable Selenium).ModuleBase
    Unblock-File -Path 'C:\tools\selenium\*'
    Get-Process -Name *chrome*, *firefox*, *gecko* | Stop-Process -Force
    Get-ChildItem -Path 'C:\tools\selenium\*' | Copy-Item -Destination "$ModuleBase\assemblies\" -Force -ErrorAction SilentlyContinue

    # Start Jenkins in Selenium

    $driver = Start-SeChrome -Maximized -Headless
    # Enforce a reasonable window size
    $driver.Manage().Window.Size = [System.Drawing.Size]::new(1600, 900)
    Start-Sleep -Seconds 20

    Enter-SeUrl -Url http://localhost:8080 -Driver $driver
    Start-Sleep -Seconds 3

    Write-Verbose -Message "Loaded Jenkins UI"

    # Login to UI
    gc 'C:\Program Files (x86)\Jenkins\secrets\initialAdminPassword' | Set-Clipboard
    $input = Find-SeElement -Driver $driver -Id 'security-token'
    Send-SeKeys -Element $input -Keys "$(Get-Clipboard)"
    Start-Sleep -Seconds 5
    Write-Verbos -Message "Logged into UI"

    $Continue = Find-SeElement -Driver $driver -XPath '/html/body/div[2]/div/form/div[1]/div/div/div/div[3]/input'
    Invoke-SeClick -Driver $driver -Element $Continue
    Start-Sleep -Seconds 5

    Write-Verbose -Message "Installing Suggested Plugins"

    # Install Suggested Plugins
    $SuggestedPlugins = Find-SeElement -Driver $driver -XPath '/html/body/div[2]/div/div/div/div/div/div/div[2]/div/p[2]/a[1]'
    Invoke-SeClick -Driver $driver -Element $SuggestedPlugins
    Start-Sleep -Seconds 240

    Write-Verbose -Message "Installed suggested Plugins"

    #continue as admin
    $ContinueAsAdmin = Find-SeElement -Driver $driver -XPath '/html/body/div[2]/div/div/div/div/div/div/div[3]/button[1]'
    Invoke-SeClick -Element $ContinueAsAdmin -Driver $driver
    Start-Sleep -Seconds 3

    #Click Save and Finish Button
    $Save = Find-SeElement -Driver $driver -XPath '/html/body/div[2]/div/div/div/div/div/div/div[3]/button[2]'
    Invoke-SeClick -Element $Save  -Driver $driver
    Start-Sleep -Seconds 3

    #Start using Jenkins
    $Start = Find-SeElement -Driver $driver -XPath '/html/body/div[2]/div/div/div/div/div/div/div[2]/div/button'
    Invoke-SeClick -Element $Start -Driver $driver
    Start-Sleep -Seconds 3

    Write-Verbose "Disabling security to import Pipeline jobs"
    #Manage Jenkins 
    $ManageJenkins = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[1]/div[1]/div[4]/a[2]'
    Invoke-SeClick -Element $ManageJenkins -Driver $driver
    Start-Sleep -Seconds 3

    #Global Security
    $GlobalSecurity = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/div[3]/a'
    Invoke-SeClick -Element $GlobalSecurity -Driver $driver
    Start-Sleep -Seconds 3

    #Implement Terrible security practices
    $Security = Find-SeElement -Driver $driver -XPath '/html/body/div[6]/div[2]/form/table/tbody/tr[6]/td[3]/table/tbody/tr[25]/td[1]/label/input'
    Invoke-SeClick -Element $Security -Driver $driver
    Start-Sleep -Milliseconds 100

    #Save Changes
    $SaveChanges = Find-SeElement -Driver $driver -XPath '/html/body/div[6]/div[2]/form/table/tbody/tr[60]/td/div[2]/div[2]/span[1]/span/button'
    Invoke-SeClick -Element $SaveChanges -Driver $driver
    Start-Sleep -Seconds 3

    Write-Verbose -Message "Importing Pipeline jobs"
    $xml = Get-ChildItem C:\jenkinsxml -Filter *.xml
    $xml | % { Get-Content $_.Fullname | &'C:\Program Files (x86)\Jenkins\jre\bin\java.exe' -jar C:\jenkinsxml\jenkins-cli.jar -s http://localhost:8080/ create-job "$($_.basename)" }
    Remove-Item C:\jenkinsxml -Recurse -Force

    Write-Verbose -Message "Enabling hardened security"
    #Manage Jenkins 
    $ManageJenkins = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[1]/div[1]/div[4]/a[2]'
    Invoke-SeClick -Element $ManageJenkins -Driver $driver
    Start-Sleep -Seconds 3

    #Global Security
    $GlobalSecurity = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/div[3]/a'
    Invoke-SeClick -Element $GlobalSecurity -Driver $driver
    Start-Sleep -Seconds 3

    #Fix Terrible security practices
    $Security = Find-SeElement -Driver $driver -XPath '/html/body/div[6]/div[2]/form/table/tbody/tr[6]/td[3]/table/tbody/tr[33]/td[1]/label/input'
    Invoke-SeClick -Element $Security -Driver $driver
    Start-Sleep -Milliseconds 100

    #Save Changes
    $SaveChanges = Find-SeElement -Driver $driver -XPath '/html/body/div[6]/div[2]/form/table/tbody/tr[60]/td/div[2]/div[2]/span[1]/span/button'
    Invoke-SeClick -Element $SaveChanges -Driver $driver
    Start-Sleep -Seconds 5

    Write-Verbose -Message "Enabling PowerShell Plug-in"
    Write-Verbose "Clicking Manage jenkins"
    $ManageJenkins = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[1]/div[1]/div[4]/a[2]'
    Invoke-SeClick -Element $ManageJenkins -Driver $driver
    Start-Sleep -Seconds 3

    # Manage Plugins
    Write-Verbose "Clicking Manage Plugins"
    $ManagePlugins = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/div[7]/a'
    Invoke-SeClick -Element $ManagePlugins -Driver $driver
    Start-Sleep -Seconds 3

    # Click Available tab
    Write-Verbose "Clicking Available Tab"
    $Available = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/form/div[1]/div[1]/div[2]/a'
    Invoke-SeClick -Element $Available -Driver $driver
    Start-Sleep -Seconds 3

    # Filter for PowerShell
    Write-Verbose "Filtering for PowerShell"
    $filterBox = Find-SeElement -Driver $driver -Id 'filter-box'
    Send-SeKeys -Element $filterBox -Keys 'Powershell'

    #Tick check box
    Write-Verbose "Selecting PowerShell"
    $TickBox = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/form/div[2]/table/tbody/tr[11]/td[1]/input'
    Invoke-SeClick -Element $TickBox -Driver $driver

    # Install w/o Restart
    Write-Verbose "Clicking Install w/o Restart"
    $InstallButton = Find-SeElement -Driver $driver -XPath '/html/body/div[4]/div[2]/form/div[4]/div[2]/span[1]/span/button'
    Invoke-SeClick -Element $InstallButton -Driver $driver
    Start-Sleep -Seconds 15

    Write-Verbose -Message 'Closing down Selenium, we are all set!'
    Stop-SeDriver -Driver $driver

  }
  
}

Function New-JenkinsScheduledTask {
  [cmdletbinding()]
  param(
    [parameter()]
    [string]
    $User,

    [parameter()]
    [string]
    $Pass
  )
  process {
    if(!(Test-Path C:\scripts)){
        $null = New-Item C:\scripts -ItemType Directory
    }
    ${Function:\Install-Jenkins} | Set-Content "C:\scripts\Jenkins.ps1"
    $action = New-ScheduledTaskAction -Execute 'C:\windows\system32\WindowsPowerShellv1.0\powershell.exe' -Argument "-NonInteractive -Nologo -NoProfile -File 'C:\scripts\Jenkins.ps1'" -WorkingDirectory 'C:\scripts'
    $trigger = New-ScheduledTaskTrigger -Once -At 3am
    $securePass = $Pass | ConvertTo-SecureString -AsPlainText -Force
    $cred = [System.Management.Automation.PSCredential]::new($User,$securePass)

    $Task = New-ScheduledTask -Action $Action -Trigger $Trigger


    Write-Host " Using credential user: $($cred.Username)"
    Write-Host: "Using credential password: $($cred.GetNetworkCredential().Password)"
    $Task | Register-ScheduledTask -TaskName  'JenkinsSetup' -User "$($cred.Username)" -Password "$($cred.GetNetworkCredential().Password)"

    #Start-ScheduledTask -TaskName 'Jenkins Setup'

  }
}


#Install-Chocolatey
#Install-SeleniumDependency
#Get-Scripts
#Install-Nexus
#Set-NexusFirewall
New-JenkinsScheduledTask -User $TaskUser -Pass $TaskPass

<#
$InformationString = @"
        Nexus Information
BaseUrl: http://localhost:8081
Username: admin
Password: $(Get-Content "C:\programdata\sonatype-work\nexus3\admin.password")
Api Key: $NugetApiKey

        Jenkins Information
BaseUrl: http://localhost:8080
Username: admin
Password: $(Get-Content "C:\Program Files (x86)\jenkins\secrets\initialAdminPassword")
"@

#Write-Host $InformationString
#>