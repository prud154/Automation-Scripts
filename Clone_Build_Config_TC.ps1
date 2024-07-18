#[string]$branchNumber = "%branchToBuild%"; [string]$teamcityUrl = "%teamcity.serverUrl%";
[string]$teamcityUrl = "";
[string]$projectToClone = "InternalBusinessSystems";  [string]$configToClone = "Cfs";
[string]$branchToClone = "1701";  [string]$newBranchToBuild = "1702";
#[System.Management.Automation.PSCredential] $usercreds = $null;

if ($usercreds -eq $null) {
    $usercreds = (Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter Credentials for your REST API connection");
}

try {
	[string]$baseUrl = "$teamcityUrl/httpAuth/app/rest";
	Write-Host "Base URL: $baseUrl";

	# Get all build type definitions
    Write-Host "buildXML URL: $baseUrl/buildTypes/";
    [xml]$buildXML = Invoke-RestMethod -Uri "$baseUrl/buildTypes/" -Credential $usercreds -Method GET;
    
	[string]$buildTypeNameFilter = "(^($projectToClone)_($configToClone)_($branchNumber).*)";

	# Get the build types that match our regular expression filter
	$buildTypesToClone = $buildXML.buildTypes.buildType.Where({$_.id -Match $buildTypeNameFilter}).id;

	# Set the build number counter value of each build type to 1
	$buildTypesToClone | ForEach-Object -Process {
        [string]$clonedBuildTypeid = "$_";
        [string]$buildNamesToClone = $buildXML.buildTypes.buildType.Where({$_.id -Match $clonedBuildTypeid}).name;
        [string]$baseProjectID = $buildXML.buildTypes.buildType.Where({$_.id -Match $clonedBuildTypeid}).projectId;
        
        $updatedProjectID = $baseProjectID.replace($branchToClone,$newBranchToBuild);
        [string]$postUrl = "$baseUrl/projects";
        
        $result = try {
            Invoke-RestMethod -Uri "$postUrl/id:$updatedProjectID" -Credential $usercreds -Method GET;
        }
        catch {
            #Create Project first
            $data = "<newProjectDescription name='"+$newBranchToBuild+"' id='"+$updatedProjectID+"' copyAllAssociatedSettings='true'><parentProject locator='id:"+"$($projectToClone)_$($configToClone)"+"'/><sourceProject locator='id:"+$baseProjectID+"'/></newProjectDescription>";
            Write-Host "Creating Project for $newBranchToBuild - $configToClone under $projectToClone";
            write-warning "Posting:`n$data`nto: $postUrl";
            Invoke-RestMethod -Uri $postUrl -Credential $usercreds -Method POST -ContentType "application/xml" -Body $data;
            $usercreds
        }
	}
}
catch {
	Write-Error $_.Exception.Message;
	#exit(1)
}
