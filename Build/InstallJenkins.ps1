choco install jenkins -y --no-progress -s https://chocolatey.org/api/v2
choco install googlechrome --version=79.0.3945.130 -s https://chocolatey.org/api/v2 -y --ignore-checksums
choco install selenium-chrome-driver --version=79.0.3945.36 -y --no-progress -s https://chocolatey.org/api/v2
$VerbosePreference = 'Continue'
Import-Module Selenium -Force -Verbose

Write-Verbose -Message "Ensuring appropriate Chrome Assembly is loaded"
$ModuleBase = (Get-Module -ListAvailable Selenium).ModuleBase
Unblock-File -Path 'C:\tools\selenium\*'
Get-Process -Name *chrome*, *firefox*, *gecko* | Stop-Process -Force
Get-ChildItem -Path 'C:\tools\selenium\*' | Copy-Item -Destination "$ModuleBase\assemblies\" -Force -ErrorAction SilentlyContinue

# Start Jenkins in Selenium
$driver = Start-SeChrome -Maximized -Arguments disable-gpu
Start-Sleep -Seconds 30
Enter-SeUrl -Url http://localhost:8080 -Driver $driver
Start-Sleep -Seconds 3

Write-Verbose -Message "Loaded Jenkins UI"

# Login to UI
gc 'C:\Program Files (x86)\Jenkins\secrets\initialAdminPassword' | Set-Clipboard
$input = Find-SeElement -Driver $driver -Id 'security-token'
Send-SeKeys -Element $input -Keys "$(Get-Clipboard)"
Start-Sleep -Seconds 5
Write-Host "Logged into UI"

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
$xml = Get-ChildItem C:\packages\jenkins\xml -Filter *.xml
$xml | % { Get-Content $_.Fullname | java -jar C:\packages\jenkins\jenkins-cli.jar -s http://localhost:8080/ create-job "$($_.basename)" }

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

# Go Back to Top
Write-Verbose "Clicking Back To Top link"
$BackToTop = Find-SeElement -Driver $driver -XPath  '//*[@id="scheduleRestart"]/p[1]/a'
Invoke-SeClick -Element $BackToTop -Driver $driver -JavaScriptClick
Start-Sleep -Seconds 5

Write-Verbose -Message 'Closing down Selenium, we are all set!'
Stop-SeDriver -Driver $driver
