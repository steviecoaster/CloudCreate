choco install nexus-repository -y --no-progress -s chocolatey
choco install chocolatey-nexus-setup -y -s C:\packages --no-progress

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
repository.createNugetHosted("Internal","$($params.BlobStoreName)");
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
repository.createNugetProxy("Community","https://chocolatey.org/api/v2","$($params.BlobStoreName)");
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
repository.createNugetGroup("ChocolateyGroup",["Internal","Community"],"$($params.BlobStoreName)")

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
        choco push $_.Fullname -s http://localhost:8081/repository/Internal/ --api-key $NugetApiKey --force
    }
}


Write-Host "Configuring choco sources"
choco source add -n Internal_Chocolatey -s http://localhost:8081/repository/ChocolateyGroup/
choco source disable -n chocolatey

Write-Host "Verifying source contents"
