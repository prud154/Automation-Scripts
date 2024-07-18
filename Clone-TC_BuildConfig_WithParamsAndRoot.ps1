[CmdletBinding()]
Param (
    #[string]$branchNumber = "%branchToBuild%",
    #[string]$teamcityUrl = "%teamcity.serverUrl%",
    #[System.Management.Automation.PSCredential] $usercreds = $null,
    [string]$teamcityUrl = "https://ci.hallmarkbusiness.com",
    [string]$projectToClone = "InternalBusinessSystems",
    [string]$configToClone = "Cfs",
    [string]$branchToClone = "1702",  
    [string]$newBranchToBuild = "1703"
)

function Update-XMLData([xml] $inboundxmldata, $currentbranch, $targetbranch){
	$inboundxmldata.SelectNodes("//*") | foreach {
		$node=$_;
		@("id","name","value","href") | foreach {
			$nodename=$_;
			if ( $node.GetAttribute($nodename) | where { $_ -like "*$($currentbranch)*"} ) {
				$currentNodeValue = $node.GetAttribute($nodename);
				#$replacedNodeValue = $(($currentNodeValue).replace($currentbranch,$targetbranch));
				Write-Verbose "Found Node $nodename with value of $($currentNodeValue)";
				$node.SetAttribute($nodename, $(($currentNodeValue).replace($currentbranch,$targetbranch)));
				Write-Verbose "`tReplaced with new value of $(($currentNodeValue).replace($currentbranch,$targetbranch))";
			}
		}
	}
	return $inboundxmldata;
}

if ($usercreds -eq $null) {
    $usercreds = (Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message "Enter Credentials for your REST API connection");
}

try {
	[string]$baseUrl = "$teamcityUrl/httpAuth/app/rest";
	Write-Verbose "Base URL: $baseUrl";

	# Get all build type definitions
    Write-Verbose "buildXML URL: $baseUrl/buildTypes/";
    [xml]$buildXML = Invoke-RestMethod -Uri "$baseUrl/buildTypes/" -Credential $usercreds -Method GET;
    
	[string]$buildTypeNameFilter = "(^($projectToClone)_($configToClone)_($branchToClone).*)";

	# Get the build types that match our regular expression filter
	$buildTypesToClone = $buildXML.buildTypes.buildType.Where({$_.id -Match $buildTypeNameFilter}).id;

    #Build Up new project        
    [string]$baseProjectID = $buildXML.buildTypes.buildType.Where({$_.id -Match $buildTypeNameFilter}).projectId | Select-Object -First 1;
    $updatedProjectID = $baseProjectID.replace($branchToClone,$newBranchToBuild);
    [string]$postUrl = "$baseUrl/projects";
    
    $result = try {
        Invoke-RestMethod -Uri "$postUrl/id:$updatedProjectID" -Credential $usercreds -Method GET;
    }
    catch {
        #Create Project first
        $data = "<newProjectDescription name='"+$newBranchToBuild+"' id='"+$updatedProjectID+"' copyAllAssociatedSettings='true' shareVCSRoots='false'><parentProject locator='id:"+"$($projectToClone)_$($configToClone)"+"'/><sourceProject locator='id:"+$baseProjectID+"'/></newProjectDescription>";
        Write-Verbose "Creating Project for $newBranchToBuild - $configToClone under $projectToClone";
        Write-warning "Posting:`n$data`nto: $postUrl";
        Invoke-RestMethod -Uri $postUrl -Credential $usercreds -Method POST -ContentType "application/xml" -Body $data;
    }
    
    "Updating Project Parameters for $updatedProjectID"
    $projectParameterPostURL = "$postUrl/id:$updatedProjectID/parameters"
    $result = try {
        $data = "";  Invoke-RestMethod -Uri "$projectParameterPostURL/octopusAutoDeployEnvironments" -Credential $usercreds -Method PUT -ContentType "text/plain" -Body $data;
        $data = "$newBranchToBuild";  Invoke-RestMethod -Uri "$projectParameterPostURL/system.branchName" -Credential $usercreds -Method PUT -ContentType "text/plain" -Body $data;
        $data = "Next";  Invoke-RestMethod -Uri "$projectParameterPostURL/system.octopusChannelFriendlyName" -Credential $usercreds -Method PUT -ContentType "text/plain" -Body $data;
        $data = "NXT";  Invoke-RestMethod -Uri "$projectParameterPostURL/system.octopusChannelName" -Credential $usercreds -Method PUT -ContentType "text/plain" -Body $data;
        "Completed Parameter Update"
    }
    catch {
        Write-Verbose "Current Data: $data"
        Write-Error -Exception $_.exception -ErrorAction stop;
    }
    
	# Set the build number counter value of each build type to 1
	$buildTypesToClone | ForEach-Object -Process {
        [string]$clonedBuildTypeid = "$_";
        [string]$buildNameToClone = $buildXML.buildTypes.buildType.Where({$_.id -Match $clonedBuildTypeid}).name;
        [string]$buildIdToClone = $buildXML.buildTypes.buildType.Where({$_.id -Match $clonedBuildTypeid}).id;
        "buildNameToClone: $buildNameToClone"; "buildIdToClone: $buildIdToClone";
        
        #$result = try {
        try {
            Write-Verbose "Getting currently attached VCS roots"
            [string]$buildTypesVcsRootEntriesURL = "$baseUrl/buildTypes/id:$buildIdToClone";
            Write-Verbose "buildTypesVcsRootEntriesURL: $buildTypesVcsRootEntriesURL"
            [xml]$buildOldvcsRootXML = Invoke-RestMethod -Uri "$buildTypesVcsRootEntriesURL" -Credential $usercreds -Method GET;
            
            $oldRootToClone = $buildOldvcsRootXML.buildType.'vcs-root-entries'.'vcs-root-entry'.id
            Write-Verbose "oldRootToClone: $oldRootToClone"
            
            [string]$buildRootToCloneURL = "$baseUrl/vcs-roots/id:$oldRootToClone"
            Write-Verbose "buildRootToCloneURL: $buildRootToCloneURL"
            [xml]$buildRootToCloneXML = Invoke-RestMethod -Uri "$buildRootToCloneURL" -Credential $usercreds -Method GET;
            
            [xml]$newVcsRootToAddXML = Update-XMLData $buildRootToCloneXML $branchToClone $newBranchToBuild;
            
            [string]$projectVcsRootsUrl = "$baseUrl/vcs-roots?locator=project:(id:$updatedProjectID)"
            "projectVcsRootsUrl: $projectVcsRootsUrl"
            [xml]$projectVcsRootToRemoveXML = Invoke-RestMethod -Uri "$projectVcsRootsUrl" -Credential $usercreds -Method GET;
            
            $newRootToDelete = $projectVcsRootToRemoveXML.'vcs-roots'.'vcs-root'.id
            "newRootToDelete: $newRootToDelete"
        }
        catch {
            Write-Error -Exception $_.exception -ErrorAction stop;
        }
        
        write-verbose "Attaching updated VCSRoot";
        #$postUrl = "$($RESTURLNewConfig)/vcs-root-entries";
        #$data = "XML_DATA_GOES_HERE";
        #Invoke-RestMethod -Uri $postUrl -Credential $usercreds -Method POST -ContentType "application/xml" -Body $data;

        write-verbose "Removing previous VCS Root: $oldRootToClone";
        # Remove Old VCSRoot
        #write-verbose "Removing Old VCS Root";
        #$HTTPMethod = 'DELETE'; 
        #$RESTURL = "$($RESTURLNewConfig)/vcs-root-entries/$($oldVCSRoot)";
        #Invoke-RestMethod -Uri $postUrl -Credential $usercreds -Method POST -ContentType "application/xml" -Body $data;

	}
}
catch {
	Write-Error $_.Exception.Message;
	#exit(1)
}
