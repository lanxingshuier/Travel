Function IsPathExists([string]$path)
{
    return Test-Path $path
}

Function JoinPath
{
    param (
        [parameter(mandatory=$true)]
        [string]$rootPath, 
        [parameter(mandatory=$true)]
        [string[]]$childPaths
    )

    $destination = $rootPath

    $childPaths | % {
        $destination = Join-Path $destination -ChildPath $_
    }

    return $destination
}

Function ConvertToHashtableFromPsCustomObject([object]$psCustomObject)
{
    $hashtable = @{ }
    if ($psCustomObject)
    {
        $psCustomObject | Get-Member -MemberType *Property | % {
            $hashtable.($_.name) = $psCustomObject.($_.name)
        }
    }
    return $hashtable
}

Function ParseSubmodulesFromGit([string]$gitmodulesFile)
{
    $start = "[{"
    $middle = "},{"
    $end = "}]"
    $empty = "[]"

    $gitModuleContents = Get-Content $gitmodulesFile
    $gitModuleJsonContents = $start
    foreach ($line in $gitModuleContents)
    {
        if($line -Match '^\s*\[submodule\s+"\s*(\w+[^"]*|[^"]*\w+)\s*"\s*\]\s*$')
        {
            $submoduleName = $line -Replace '^\s*\[submodule\s+"\s*(\w+[^"]*|[^"]*\w+)\s*"\s*\]\s*$','$1'
            if ($gitModuleJsonContents -ne $start)
            {
                $gitModuleJsonContents += $middle
            }
            $gitModuleJsonContents += "'name' : '$($submoduleName.Trim())'"
        }
        elseif ($line -like "*=*")
        {
            $key = $line.Split("=")[0].Trim()
            $value = $line.Split("=")[1].Trim()
            $gitModuleJsonContents += ",'$key' : '$value'"
        }
    }
    $gitModuleJsonContents += $end
    if ($gitModuleJsonContents -eq $start+$end)
    {
        $gitModuleJsonContents = $empty
    }

    try {
        $submodules = $gitModuleJsonContents | ConvertFrom-Json
    }
    catch {
        $err = $_.Exception
        echo "Invalid JSON file $gitmodulesFile. Exception detail: $err.Message" | timestamp
        exit 1
    }
    
    return $submodules | % { ConvertToHashtableFromPsCustomObject($_) }
}

Function LocateGitExe()
{
    try
    {
        $gitPath = Get-Command git.exe | Select-Object -ExpandProperty Definition
        return $gitPath
    }
    catch
    {
        exit ConsoleErrorAndExit("Can't find git.exe in your environment. Please make sure you've already installed git and check if the path is already added into environment variable PATH.") (1)
    }
}

Function RunExeProcess([string]$exeFilePath, [string]$arguments, [string]$workingDirectory = [String]::Empty)
{
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $exeFilePath
    $process.StartInfo.Arguments = $arguments
    $process.StartInfo.WorkingDirectory = $workingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true

    $process.Start()
    $process.WaitForExit()
    return $process
}

Function GetJsonContent([string]$jsonFilePath)
{
    try {
        $jsonContent = Get-Content $jsonFilePath -Raw
        return $jsonContent | ConvertFrom-Json
    }
    catch {
        Write-Error "Invalid JSON file $jsonFilePath. JSON content detail: $jsonContent" -ErrorAction Continue
        throw
    }
}

Function ParseBuildEntryPoint([object]$predefinedEntryPoints, [string]$buildEntryPoint)
{
   foreach ($predefinedEntryPoint in $predefinedEntryPoints.Keys)
    {
        if ($buildEntryPoint -eq "$predefinedEntryPoint.ps1" -or $buildEntryPoint -eq $predefinedEntryPoint)
        {
            return $predefinedEntryPoint
        }
    }
    return $buildEntryPoint
}

Function GetWorkingBranch([string]$gitPath, [string]$workingFolder, [string]$reportFilePath, [string]$source, [int]$lineNumber)
{
    $process = RunExeProcess($gitPath) ("rev-parse --abbrev-ref HEAD") ($workingFolder)
    if ($process.ExitCode -ne 0)
    {
        $errorMessage = "Can't get working branch info in folder $workingFolder. Error: $($process.StandardError.ReadToEnd())"
        ConsoleErrorAndExit($errorMessage) ($process.ExitCode)
        LogError -logFilePath $reportFilePath -message $errorMessage -source $source -line $lineNumber
        return [String]::Empty
    }
    return $process.StandardOutput.ReadToEnd().Trim()
}

Function GetPropertyStringValueFromGlobalMetadata([string]$globalMetadataFile, [string]$overrideValue, [string]$property)
{
    if (![string]::IsNullOrEmpty($overrideValue))
    {
        return $overrideValue
    }

    if (![string]::IsNullOrEmpty($globalMetadataFile) -and (Test-Path $globalMetadataFile))
    {
        $docsetMetadata = ConvertToHashtableFromPsCustomObject(Get-Content $globalMetadataFile | ConvertFrom-Json)
        if ($docsetMetadata.($property) -and ![string]::IsNullOrEmpty($docsetMetadata.($property)))
        {
            $overrideValue = $docsetMetadata.($property)
        }
    }

    return $overrideValue
}

Function NormalizePath([string]$originalPath)
{
    $originalPaths = $originalPath.Split("\/", [System.StringSplitOptions]::RemoveEmptyEntries)
    return [string]::Join("/", $originalPaths)
}

Function NormalizeGitUrlWithoutToken([string]$gitUrl)
{
    if($gitUrl -Match "(?<prefix>https:\/\/)((?<username>[\w]+):)?(?<accesstoken>[\w]+)@(?<postfix>[\w\W]+)")
    {
        return $Matches["prefix"] + $Matches["postfix"]
    }

    return $gitUrl
}

$normalizedUrl = NormalizeGitUrlWithoutToken("https://userName:123@github.com/fenxu/NewSchame")
$normalizedUrl = NormalizeGitUrlWithoutToken("https://123@github.com/fenxu/NewSchame")
$normalizedUrl = NormalizeGitUrlWithoutToken("https://github.com/fenxu/NewSchame")

$normalizedPathToRoot = NormalizePath("asdf\asdf/asdf\adsf/asdf\")

$publishConfigFile = "D:\temp\ps_test\.openpublishing.publish.config.json"
$publishConfigContent = (Get-Content $publishConfigFile -Raw) | ConvertFrom-Json

$hasDuplicateCRRs = $false
$crrPaths = @()
foreach($crr in $publishConfigContent.dependent_repositories)
{
    if($crrPaths.Contains($crr.path_to_root))
    {
        $errorMessage = "Dependent repositories are invalid in publish config: Don't set more than one dependent repositories with same path_to_root. Same path_to_root: $($crr.path_to_root)"
        $hasDuplicateCRRs = $true
    }
    else
    {
        $crrPaths += $crr.path_to_root
    }
}

if($hasDuplicateCRRs)
{
    $errorMessage = "Dependent repositories configuration are invalid, please ref the other error details to fix."
}


$systemDefaultVariables = @{
    GenerateDocumentId = $false;
    PreservedTemplateFolderNameList = @("_themes", "_themes.MSDN.Modern", "_themes.VS.Modern")
}

$PreservedTemplateFolder = $systemDefaultVariables.PreservedTemplateFolderNameList

$configPath = "D:\temp\ps_test\.openpublishing.publish.config.json"
$test_null = GetPropertyStringValueFromGlobalMetadata($configPath) ("") ("test_null")
$test_empty = GetPropertyStringValueFromGlobalMetadata($configPath) ("") ("test_empty")
$build_entry_point1 = GetPropertyStringValueFromGlobalMetadata($configPath) ("op") ("build_entry_point")
$build_entry_point1 = GetPropertyStringValueFromGlobalMetadata($configPath) ("") ("build_entry_point")
$docset_name1 = GetPropertyStringValueFromGlobalMetadata($configPath) ("") ("git_repository_url_open_to_public_contributors")

$gitPath = LocateGitExe
$dpRepoPath = "D:\GitHub2\fenxu\dependent_repo_20160527"

$CloneFolder = "D:\temp\Repo"
$process = RunExeProcess($gitPath) ("clone https://4365f594e5e41f682c9251caec16bb8272202ca3github.com/fenxu/NewSchema.git") ($CloneFolder)
if ($process.ExitCode -ne 0)
{
    
}

$workingBranch = GetWorkingBranch($gitPath) ($dpRepoPath) ("") ("") (1)


$process = RunExeProcess($gitPath) ("chekout master") ($dpRepoPath)
$gitFolderRelativePathToDpRepoFolder = $process.StandardOutput.ReadToEnd().Trim()
if (($process.ExitCode -ne 0) -or ($gitFolderRelativePathToDpRepoFolder -ne ".git"))
{
    $cloneExitCode = 1
    $errorMessage = "Fodler $dpRepoPath under repository is not a valid git folder of dependent repository. Error: $($process.StandardError.ReadToEnd())"
    continue
}

$process = RunExeProcess($gitPath) ("rev-parse --git-dir") ($dpRepoPath)
$gitFolderRelativePathToDpRepoFolder = $process.StandardOutput.ReadToEnd().Trim()
if (($process.ExitCode -ne 0) -or ($gitFolderRelativePathToDpRepoFolder -ne ".git"))
{
    $cloneExitCode = 1
    $errorMessage = "Fodler $dpRepoPath under repository is not a valid git folder of dependent repository. Error: $process.StandardError.ReadToEnd()"
    continue
}




$buildEntryPoint = "BuildAzureContent.ps1"

$predefinedEntryPoints = @{
    BuildAzureContent = "mdproj.builder.ps1"
    op = "mdproj.builder.ps1"
    docs = "mdproj.builder.ps1"
    reposyncer = "repo.syncer.ps1"
}


$buildEntryPoint = ParseBuildEntryPoint($predefinedEntryPoints) ($buildEntryPoint)


$dpRepoPath = "D:\GitHub3\fenxu\fenxu_docs_20160417\_themes"
$dpRepoGitFolder = JoinPath($dpRepoPath) (@(".git"))
        if (IsPathExists($dpRepoGitFolder))
        {
            Remove-Item $dpRepoGitFolder -Recurse -Force
        }

$repositoryRoot = "D:\GitHub3\fenxu\ATADocs-pr"
$publishVersion = @{ }
$parsedDependencies = @()

# Parse dependent repositories from .openpublishing.publish.config
$gitPath = LocateGitExe
$publishConfigFile = JoinPath($repositoryRoot) (@(".openpublishing.publish.config.json"))
$publishConfigContent = (Get-Content $publishConfigFile -Raw) | ConvertFrom-Json
if ($publishConfigContent.dependent_repositories -ne $null)
{
    foreach($dpRepo in $publishConfigContent.dependent_repositories)
    {
        $dpDependency = @{ }
        $dpDependency.path = $dpRepo.path_to_root
        $dpDependency.url = $dpRepo.url

        $dpRepoPath = JoinPath($repositoryRoot) (@($dpDependency.path))
        $process = RunExeProcess($gitPath) ("rev-parse --abbrev-ref HEAD") ($dpRepoPath)
        if ($process.ExitCode -ne 0)
        {
            exit ConsoleErrorAndExit("Can't get branch info for the build dependent repository: $($dpRepo.url). Error: $process.StandardError.ReadToEnd()") ($process.ExitCode)
        }
        $dpDependency.branch = $process.StandardOutput.ReadToEnd().Trim()

        $currentCommitId = &"$gitPath" "-C" "$dpRepoPath" "rev-parse" "HEAD"
        if ($LASTEXITCODE -ne 0)
        {
            exit ConsoleErrorAndExit("Can't get the head commit id with dependent repository: $($submodule.url), path: $($dpDependency.path).") ($LASTEXITCODE)
        }
        $dpDependency.commit_id = $currentCommitId
        $parsedDependencies += $dpDependency
    }
}

foreach ($parsedDependency in $parsedDependencies)
{
    echo "path: $($parsedDependency.path). url:  $($parsedDependency.url). branch: $($parsedDependency.branch). commit_id: $($parsedDependency.commit_id)"
}

# Parse submodules from .gitmodules
$gitmodulesFile = JoinPath($repositoryRoot) (@(".gitmodules"))
if (IsPathExists($gitmodulesFile))
{
    $submodules = ParseSubmodulesFromGit($gitmodulesFile)
    foreach ($submodule in $submodules)
    {
        echo $submodule.path
        foreach ($parsedDependency in $parsedDependencies)
        {
            if ([String]::Compare($parsedDependency.path, $submodule.path, $true) -eq 0)
            {
                echo "submodule $($submodule.path) is already in dp repo config, skip"
                continue
            }
        }

        $submoduleFolder = JoinPath($repositoryRoot) (@($submodule.path))
        $submodule.branch = "master"

        $submodule.commit_id = "aa"
        $parsedDependencies += $submodule
    }
}

if ($parsedDependencies -and $parsedDependencies.Length -gt 0)
{
    $publishVersion.dependencies = $parsedDependencies
}


$publishConfigurationFilePath = "D:\GitHub4\Microsoft\EMDocs-pr\.openpublishing.publish.config.json"
$publishConfigContent = GetJsonContent($publishConfigurationFilePath)

#$workingBranchName = "Test1"
$workingBranchName

foreach($dpRepo in $publishConfigContent.dependent_repositories)
{

    $ddd = $($($dpRepo.branch_mapping).$workingBranchName)
    echo "$ddd"
}



$repositoryRoot = "D:\GitHub4\Microsoft\EMDocs-pr"

Try
{
    $process = RunExeProcess($gitPath) ("branch") ($repositoryRoot)
    if ($process.ExitCode -ne 0)
    {
        echo "branch failed"
    }
    
    $branches = $process.StandardOutput.ReadToEnd().Trim() -split '[\r\n]'
    $selectedBranchRegex = [regex]"^\s*\*\s*(.*?)\s*$"
    foreach ($branch in $branches)
    {
        echo "branch = $branch"
        $match = $selectedBranchRegex.Match($branch)
        if ($match.Success)
        {
            $workingBranchName = $match.Groups[1].Value
            break
        }
    }
}
Catch
{
    echo $_
}
Finally
{
    echo "exit"
}
