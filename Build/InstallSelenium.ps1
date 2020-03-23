#Get Latest Pester.....bullet-proof/strong arm/asshole method
$null = Install-PackageProvider -Name NuGet -Force
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -Verbose
Install-Module PowershellGet -Force -SkipPublisherCheck -Verbose
Install-Module Selenium -Force -SkipPublisherCheck -Verbose

#Import the modules we will need
Import-Module Selenium -Force
