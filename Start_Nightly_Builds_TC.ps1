[string]$branchNumber = "%branchToBuild%";
[string]$teamcityUrl = "%teamcity.serverUrl%";

try {
	[string]$baseUrl = "$teamcityUrl/httpAuth/app/rest/buildTypes/";
	Write-Host "Base URL: $baseUrl";
	[string]$encodedUsernamePassword = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($('{0}:{1}' -f "RestApi", "RestApi")));

	# Get all build type definitions
	[xml]$xml = Invoke-RestMethod -Uri $baseUrl -Headers @{'Authorization' = "Basic $encodedUsernamePassword"} -Method GET;
    
	[string]$buildTypeNameFilter = "(^(Core|Assets)_$branchNumber.*)";

	# Get the build types that match our regular expression filter
	$buildTypesToUpdate = $xml.buildTypes.buildType.Where({$_.id -Match $buildTypeNameFilter}).id;

    [string]$buildBaseUrl = "$teamcityUrl/httpAuth";
	# Set the build number counter value of each build type to 1
	$buildTypesToUpdate | ForEach-Object -Process {
        [string]$buildStartUrl = "$buildBaseUrl/action.html?add2Queue=";
        [string] $postUrl = $buildStartUrl + "$_";
        Write-Host "Starting Build for $_";
        Invoke-RestMethod -Uri $postUrl -Headers @{'Authorization' = "Basic $encodedUsernamePassword"} -Method POST -ContentType "text/plain" -Body 1;
	}
}
catch {
	Write-Error $_.Exception.Message
	exit(1)
}