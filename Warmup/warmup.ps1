param(
    $instance = "habitathome.dev.local",
    $identityServerUrl = "https://identityserver.habitathome.dev.local",
    [ValidateSet('xp', 'xc')]
    $demoType,
    $adminUser = "admin",
    $adminPassword = "b"
)

$config = Get-Content -Raw -Path "$PSSCriptRoot\warmup-config.json" | ConvertFrom-Json
if ($instance -eq "") {
    $instanceName = $config.instanceName
}
else {
    $instanceName = $instance    
}
Write-Host $instanceName

function Convert-FromBase64StringWithNoPadding([string]$data)
{
    $data = $data.Replace('-', '+').Replace('_', '/')
    switch ($data.Length % 4)
    {
        0 { break }
        2 { $data += '==' }
        3 { $data += '=' }
        default { throw New-Object ArgumentException('data') }
    }
    return [System.Convert]::FromBase64String($data)
}
Function Get-SitecoreToken {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$identityserverUrl,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$username,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$password
    )
    $tokenendpointurl = $identityserverUrl + "/connect/token"
    $granttype = "password" # client_credentials / password 
    $client_id = "postman-api"
    $client_secret = "ClientSecret"
    $scope = "openid sitecore.profile sitecore.profile.api"
    
    $body = @{
        grant_type = $granttype
        scope = $scope
        client_id = $client_id
        client_secret = $client_secret    
        username = $username
        password = $password
    }
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", 'application/x-www-form-urlencoded')
    $headers.Add("Accept", 'application/json')

    $resp = Invoke-RestMethod -Method Post -Body $body -Headers $headers -Uri $tokenendpointurl 
    $parts = $resp.access_token.Split('.');

    $baseDecoded = Convert-FromBase64StringWithNoPadding($parts[1])
    $decoded = [System.Text.Encoding]::UTF8.GetString($baseDecoded)

    Write-Host "`***** SUCCESSFULLY FETCHED TOKEN ***** `n" -foreground Green

    Write-Host "`JWT payload: `n" -foreground Yellow
    $decoded = $decoded | ConvertFrom-Json | ConvertTo-Json
    Write-Host $decoded -foreground White

    Write-Host
    Write-Host "`ACCESSTOKEN: `n" -foreground Yellow
    $access_token = $resp.access_token | Format-Table -Wrap | Out-String
    Write-Host $access_token -foreground White
    Write-Host   
    return $access_token
	# if ($cookies["sitecore_userticket"]){
    #     Write-Host "login done"
	#     Write-Host ""
	# 	$webSession
    # }else{
    #     Write-Host "login failed" -ForegroundColor Red
    #     exit 2
    # }
}

Function RequestPage {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$url,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$access_token
    )
    Write-Host $(Get-Date -Format HH:mm:ss.fff)
    Write-Host "requesting $url ..."

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", ("Bearer {0}" -f $access_token))

    try { 
        
		$content = Invoke-WebRequest $url -Headers $headers -TimeoutSec 60000 | select -Expand Content
        Write-Host "Done" 
        return $true
	} 
	catch {
        $status = $_.Exception.Response.StatusCode.Value__
        if ($status -ne 200) {
            Write-Host ("ERROR Something went wrong while requesting {0} - Error {1}" -f $url,$status) -ForegroundColor Red
        }
		return $false
    }
	finally{
		Write-Host $(Get-Date -Format HH:mm:ss.fff)
        Write-Host ""
	}
}

$demoType = $demoType.ToLower()
$session = Get-SitecoreToken $identityServerUrl ("sitecore\{0}" -f $adminUser) $adminPassword
$errors = 0

Write-Host "Warming up XP Demo" -ForegroundColor Green
foreach ($page in $config.urls.xp) {
	if (!$(RequestPage "https://$instanceName$($page.url)" $session)){
		$errors++
	}
}

if ($demoType -eq "xc") {
Write-Host "Warming up XC Demo" -ForegroundColor Green
    foreach ($page in $config.urls.xc) {
		if (!$(RequestPage "https://$instanceName$($page.url)" $session)){
			$errors++
		}
    }
}

if ($errors -eq 0){
	Write-Host "Warmup Complete" -ForegroundColor Green
}else{
	Write-Host "Warmup Complete With Errors" -ForegroundColor Red
	exit 1
}
