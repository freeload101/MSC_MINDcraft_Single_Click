param(
    [Parameter(Mandatory=$false)]
    [string]$Headless
)

# function for messages
#$ErrorActionPreference="Continue"
$VerNum = 'MSC 1.4'
$host.ui.RawUI.WindowTitle = $VerNum 
 
# set current directory
Set-Location ($VARCD = (Get-Location)); $env:HOMEPATH = $env:USERPROFILE = $VARCD; $env:APPDATA = "$VARCD\AppData\Roaming"; $env:LOCALAPPDATA = "$VARCD\AppData\Local"; $env:TEMP = $env:TMP = "$VARCD\AppData\Local\Temp"; $env:JAVA_HOME = "$VARCD\jdk"; $env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\;$VARCD\PortableGit\cmd;$VARCD\jdk\bin;$VARCD\node;$VARCD\python\tools\Scripts;$VARCD\python\tools;python\tools\Lib\site-packages"
 
# Setup Form
Add-Type -assembly System.Windows.Forms
$main_form = New-Object System.Windows.Forms.Form
$main_form.AutoSize = $true
$main_form.Text = "$VerNum"

$hShift = 0
$vShift = 0

function Write-Message  {
    <#
    .SYNOPSIS
        Prints	 colored messages depending on type
    .PARAMETER TYPE
        Type of error message to be prepended to the message and sets the color
    .PARAMETER MESSAGE
        Message to be output
    #>
    [CmdletBinding()]
    param (
        [string]
        $Type,
        
        [string]
        $Message
        )

if  (($TYPE) -eq  ("INFO")) { $Tag = "INFO"  ; $Color = "Green"}
if  (($TYPE) -eq  ("WARNING")) { $Tag = "WARNING"  ; $Color = "Yellow"}
if  (($TYPE) -eq  ("ERROR")) { $Tag = "ERROR"  ; $Color = "Red"}
Write-Host  (Get-Date -UFormat "%m/%d:%T")$($Tag)$($Message) -ForegroundColor $Color  
#echo "$Message"
}
### MAIN ###

################################# FUNCTIONS
############# CHECK PYTHON
Function CheckPython {
   if (-not(Test-Path -Path "$VARCD\python" )) {
            Write-Message  -Message  "Downloading Python nuget package" -Type "INFO"
            downloadFile "https://www.nuget.org/api/v2/package/python" "$VARCD\python.zip"
            New-Item -Path "$VARCD\python" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
            Write-Message  -Message  "Extracting Python nuget package" -Type "INFO"
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\python.zip", "$VARCD\python")
			Write-Message  -Message  "Updating pip" -Type "INFO"
			Start-Process -FilePath "$VARCD\python\tools\python.exe" -WorkingDirectory "$VARCD\python\tools" -ArgumentList " -m pip install --upgrade pip " -wait -NoNewWindow

New-Item -ItemType Directory -Path "$VARCD\python\tools\Scripts" -ErrorAction SilentlyContinue |Out-Null
# DO NOT INDENT THIS PART
$PipBatch = @'
python -m pip %*
'@
$PipBatch | Out-File -Encoding Ascii -FilePath "$VARCD\python\tools\Scripts\pip.bat" -ErrorAction SilentlyContinue |Out-Null
# DO NOT INDENT THIS PART

            }
        else {
            Write-Message  -Message  "$VARCD\python already exists" -Type "WARNING"
            }
			Write-Message  -Message  "CheckPython Complete" -Type "INFO"
}
############# CheckNode
Function CheckNode {
   if (-not(Test-Path -Path "$VARCD\node" )) {
        try {
			Write-Message  "Downloading latest node"  -Type "INFO"
			$downloadUri = $downloadUri = (Invoke-RestMethod -Method GET -Uri "https://nodejs.org/dist/latest/")  -split '"' -match '.*node-.*-win-x64.zip.*' | ForEach-Object {$_ -ireplace '^\/','https://nodejs.org/' } | select -first 1
            downloadFile "$downloadUri" "$VARCD\node.zip"
			Write-Message  "Extracting Node"  -Type "INFO"
			Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\node.zip", "$VARCD")
			Get-ChildItem "$VARCD\node-*"  | Rename-Item -NewName "node"
			Write-Message  "Updating npm"  -Type "INFO"
			Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\node" -ArgumentList " install -g npm " -wait -NoNewWindow
			}
                catch {
                    throw $_.Exception.Message
            }
            }
        else {
			Write-Message  "$VARCD\node already Exist"  -Type "WARNING"
			}
}

############# downloadFile
function downloadFile($url, $targetFile)
{
	Write-Message  -Message "Downloading $url" -Type "INFO"
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) #15 second timeout
    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 10KB
    $count = $responseStream.Read($buffer,0,$buffer.length)
    $downloadedBytes = $count
    while ($count -gt 0)
    {
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer,0,$buffer.length)
    }
        $downloadedBytes = $downloadedBytes + $count
	Write-Message  -Message "Finished Download" -Type "INFO"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

############# CHECK JAVA
Function CheckJava {
Write-Message  "Checking for Java"  -Type "INFO"
   if (-not(Test-Path -Path "$VARCD\jdk" )) {
            Write-Message  "Downloading Java"  -Type "INFO"
            downloadFile "https://download.java.net/java/GA/jdk24/1f9ff9062db4449d8ca828c504ffae90/36/GPL/openjdk-24_windows-x64_bin.zip" "$VARCD\jdk.zip"
            Write-Message  "Extracting Java"  -Type "INFO"
			Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\jdk.zip", "$VARCD")
			Get-ChildItem "$VARCD\jdk-*"  | Rename-Item -NewName { $_.Name -replace '-.*','' }
            $env:JAVA_HOME = "$VARCD\jdk"
            }
        else {
            Write-Message  "$VARCD\openjdk.zip already exists"  -Type "WARNING"
            }
}

############# CMDPrompt
Function CMDPrompt {
	CheckJava
	CheckGit
	CheckNode
	Start-Process -FilePath "cmd" -WorkingDirectory "$VARCD"
}

############# CHECK CheckGit
Function CheckGit {
	 Write-Message  "Checking Git"  -Type "INFO"
   if (-not(Test-Path -Path "$VARCD\PortableGit" )) {
        try {
            Write-Message  "Downloading Git"  -Type "INFO"

            $downloadUri = ((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest").assets | Where-Object name -like *PortableGit*64*.exe ).browser_download_url | select -first 1
            downloadFile "$downloadUri" "$VARCD\git7zsfx.exe"
            Start-Process -FilePath "$VARCD\git7zsfx.exe" -WorkingDirectory "$VARCD\" -ArgumentList " -o`"$VARCD\PortableGit`" -y " -wait -NoNewWindow}
                catch {
                    throw $_.Exception.Message
                }
            }
        else {
            Write-Message  "$VARCD\Git already exists"  -Type "WARNING"
            }
}

############# UpdateJAMBO
Function UpdateJAMBO {
$JAMBOPATH = Get-ScriptPathFromCallStack
Write-Message  "Downloading latest JAMBOREE to $JAMBOPATH"  -Type "INFO"
Invoke-WebRequest -Method GET -Uri 'https://github.com/freeload101/MSC_Single_Click_MINDcraft/raw/refs/heads/main/MSC_Single_Click_MINDcraft.ps1' -OutFile "$JAMBOPATH"
Write-Message  "Restarting"  -Type "INFO"
Start-Sleep -Seconds 1
Set-Variable -Name ErrorActionPreference -Value SilentlyContinue

Start-Process -FilePath "powershell" -WorkingDirectory "$VARCD\" -ArgumentList " -File `"$JAMBOPATH`" "  -ErrorAction SilentlyContinue
#exit 0
}

############# EXECheckOllama
function EXECheckOllama{
  if (-not(Test-Path -Path "$VARCD\Ollama" )) {
	 
		Stop-process -name ollama -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name "ollama" -Force -ErrorAction SilentlyContinue |Out-Null
		
		Write-Message   "Downloading Latetst Ollama binary from github"  -Type "INFO"
		$downloadUri = ((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/ollama/ollama/releases/latest").assets | Where-Object name -like ollama-windows-amd64.zip ).browser_download_url
		downloadFile  $downloadUri "$VARCD\ollama-windows-amd64.zip"
		Write-Message  "Extracting ollama-windows-amd64.zip"  -Type "INFO"
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		Add-Type -AssemblyName System.IO.Compression
		[System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\ollama-windows-amd64.zip", "$VARCD\Ollama\")
		
		Write-Message   "Setting Environment Variables for Ollamma"  -Type "INFO"
		$env:OLLAMA_HOST = "0.0.0.0"
		# $env:OLLAMA_NUM_PARALLEL = 1
		# $env:OLLAMA_MAX_LOADED_MODELS = 3
		# $env:OLLAMA_KEEP_ALIVE = "60m"
		$env:OLLAMA_KEEP_ALIVE = "-1"
		$env:OLLAMA_FLASH_ATTENTION = "1" 
		$env:OLLAMA_MODELS = "$VARCD\Ollama\.ollama"
		
		# Write-Message   "Attempting to set System.Environment Variables for Ollama ( Run these lines as admin if you want to run Ollama outside of this script  )"  -Type "WARNING"
		# Run the following as admin to get env outside of this script!
		# [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "$VARCD\Ollama\.ollama", [System.EnvironmentVariableTarget]::Machine)
		# [System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", [System.EnvironmentVariableTarget]::Machine)
		# [System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", [System.EnvironmentVariableTarget]::Machine)
		# [System.Environment]::SetEnvironmentVariable("OLLAMA_FLASH_ATTENTION", "1", [System.EnvironmentVariableTarget]::Machine)
		
		Write-Message   "Starting Ollama ...."  -Type "INFO"
		Stop-process -name ollama -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name "ollama" -Force -ErrorAction SilentlyContinue |Out-Null
		Start-Sleep -Seconds 1
		Start-Process -FilePath "$VARCD\Ollama\ollama.exe" -WorkingDirectory "$VARCD\Ollama\" -ArgumentList " serve"
		while(!(Get-Process "ollama" -ErrorAction SilentlyContinue)){Start-Sleep -Seconds 5};Write-Message   "Waiting for Ollama to start"  -Type "INFO"
		Start-Sleep -Seconds 10
  		Remove-Item -Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk" -Force -ErrorAction SilentlyContinue |Out-Null
		
		
		Write-Message   "Downloading nomic-embed-text Ollama model"  -Type "INFO"
		Start-Process -FilePath "$VARCD\Ollama\ollama.exe" -WorkingDirectory "$VARCD\Ollama\" -ArgumentList " pull nomic-embed-text" -wait -NoNewWindow
		Write-Message   "Downloading sweaterdog/andy-4:q8_0 Ollama model"  -Type "INFO"
		Start-Process -FilePath "$VARCD\Ollama\ollama.exe" -WorkingDirectory "$VARCD\Ollama\" -ArgumentList " pull sweaterdog/andy-4:q8_0"  -wait -NoNewWindow
		Start-Process -FilePath "$VARCD\Ollama\ollama.exe" -WorkingDirectory "$VARCD\Ollama\" -ArgumentList " list "  -wait -NoNewWindow
 
		} else {
		
		Write-Message   "Starting Ollama ...."  -Type "INFO"
		Stop-process -name ollama -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name "ollama" -Force -ErrorAction SilentlyContinue |Out-Null
		Start-Sleep -Seconds 1
		Start-Process -FilePath "$VARCD\Ollama\ollama.exe" -WorkingDirectory "$VARCD\Ollama\" -ArgumentList " serve"
		while(!(Get-Process "ollama" -ErrorAction SilentlyContinue)){Start-Sleep -Seconds 5};Write-Message   "Waiting for Ollama to start"  -Type "INFO"
		Start-Sleep -Seconds 2
  		Remove-Item -Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk" -Force -ErrorAction SilentlyContinue |Out-Null
 
		}
}

############# OllamaGape
function OllamaGape {
    param(
        $OllamaIP
    )

    Write-Message  "Checking: $OllamaIP"  -Type "INFO"
    $OllamaIP = $OllamaIP -replace ',.*',''
    try {

        $Global:OllamaCheck = Invoke-RestMethod -Uri "http://${OllamaIP}:11434/api/tags" -TimeoutSec 2 | Select-Object -ExpandProperty models | Select-Object name,size,modified  | Sort-Object -Property Size  | Select-Object name -First 1
        $Global:OlammaModel = $OllamaCheck.name
    } catch {
        throw  "Error: $_"
      }

    if([string]::IsNullOrWhiteSpace($OllamaCheck) -or ($OllamaCheck -match "smollm")){
        return
    }else{
        $uri = "http://${OllamaIP}:11434/api/chat"
        $headers = @{"Content-Type"="application/json"}
        $body = @{
            model="${OlammaModel}"
            messages=@(@{role="user";content="What's the default port for a Minecraft server?. be sure to only respond with a single word or token"})
            stream=$false
        } | ConvertTo-Json

        try {
             $CSV = $OllamaIP + "," + $OlammaModel +  "," + (Invoke-RestMethod -Uri $uri -TimeoutSec 15 -Method Post -Headers $headers -Body $body -ContentType "application/json").message.content # | Out-File -FilePath "OllamaGape.txt" -Encoding UTF8 -Append
             if(($CSV -match "25565")){
                   return $CSV
                 } else {
                    throw  "Error: null or not 25565 $CSV"
                 }
            
        } catch {
           throw  "Error: $_"
        }
    }
      
}

#################### OllamaGapeFind
function OllamaGapeFind {
	Write-Message  "Downloading latest Public Ollama Server list"  -Type "INFO"
	Invoke-WebRequest -Uri "https://raw.githubusercontent.com/freeload101/SCRIPTS/refs/heads/master/MISC/OllamaGape.csv" -OutFile "$VARCD\mindcraft\OllamaGape.txt"
		
    $maxAttempts = 10  # Maximum number of attempts
    $attempt = 1      # Current attempt counter
    $success = $false # Success flag

    while (-not $success -and $attempt -le $maxAttempts) {
        try {
        
            $OllamaCSV = OllamaGape (Get-Content "$VARCD\mindcraft\OllamaGape.txt" | Get-Random )
			$Global:OllamaValidIP = $OllamaCSV -replace ',.*',''  -replace '\r',''  -replace '\n','' -replace '\s',''
            $Global:OllamaValidModel = $Global:OlammaModel
			
       		Write-Message  "Attempt $attempt Operation successful $OllamaCSV IP $Global:OllamaValidIP Model $Global:OllamaValidModel"  -Type "INFO"
            $success = $true  # Set success flag to exit loop
        
        }
        catch {
            Write-Message  "Attempt $attempt failed with error: $($_.Exception.Message)"  -Type "ERROR"
            $attempt++
        }
    }
}

#################### mindcraftStart
function mindcraftStart {
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null
 
	Write-Message  "Removing Andy memory folder $VARCD\mindcraft\mindcraft\bots\Andy "  -Type "WARNING"
 	Remove-Item -Path "$VARCD\mindcraft\mindcraft\bots\Andy" -Force -ErrorAction SilentlyContinue  -Confirm:$false -Recurse |Out-Null
	Write-Message  "Starting Mindcraft"  -Type "INFO"
	Start-Process -FilePath "$VARCD\node\node.exe" -WorkingDirectory ".\" -ArgumentList " main.js "
}

############# CheckGPU
Function CheckGPU {
	$GPUList = Get-ItemProperty -Path "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*"   | Where-Object {$_."HardwareInformation.qwMemorySize" -gt 0}  	
	$VRAM = [math]::round($GPUList."HardwareInformation.qwMemorySize"/1GB)	

	if ($VRAM -lt 5) {
			Write-Message  "Dedicated GPU Less then 5 GB VRAM. Dedicated GPU Memory this is differnet then Shared GPU memory or GPU Memory ! We can use public Ollama servers or see FAQ for Mindcraft to setup APIs"  -Type "WARNING"
			$Global:GPUVRAM = 0
			(Get-WmiObject -Namespace root\CIMV2 -Class CIM_VideoController)  | Select-Object Name,Description,Caption,DeviceID,VideoMemoryType  | Format-Table -AutoSize
			
	} else {
	$DriverDesc = $GPUList.DriverDesc
	Write-Message  "Dedicated GPU: $DriverDesc with $VRAM GB of VRAM"  -Type "INFO"
	$Global:GPUVRAM = 1 # DEBUG 0
	EXECheckOllama
		}	
}
############# CheckSDK  C:\Program Files (x86)\Windows Kits\10\Include
function CheckSDK{
	Write-Message  "Checking for C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"  -Type "INFO"
  if (-not(Test-Path -Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" )) {
		
	New-Item -Path "$VARCD\AppData\Local\Temp" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null 
	New-Item -Path "$VARCD\AppData\Roaming" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null 
	New-Item -Path  "$VARCD\AppData\Local" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null 
	 
	Write-Message  "Installing Microsoft Visual Studio\2022\BuildTools ( for Andy-5 Vision! this will take a while ... ) "  -Type "INFO"
	Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile "$VARCD\vs_buildtools.exe"
			Start-Process -FilePath "$VARCD\vs_buildtools.exe"    -ArgumentList @(
				"--quiet",
				"--wait", 
				"--norestart",
				"--nocache",
				"--add", "Microsoft.VisualStudio.Workload.VCTools",
				"--add", "Microsoft.Component.MSBuild",
				"--add", "Microsoft.VisualStudio.Component.Roslyn.Compiler",
				"--includeRecommended"
			) -Wait
		Write-Message  "Microsoft Visual Studio\2022\BuildTools Complete!" -Type "INFO"		
  } else {
	Write-Message  "Microsoft Visual Studio\2022\BuildTools found" -Type "INFO"	
  }
}	
############# mindcraft
Function mindcraft {
Write-Message  "Ending task Java"  -Type "INFO"
Stop-process -name java -Force -ErrorAction SilentlyContinue |Out-Null
CheckSDK
CheckPython
CheckGPU
CheckGit
CheckJava
CheckNode
MinecraftServer
	
if (-not(Test-Path -Path "$VARCD\mindcraft\mindcraft" )) {
	
	Write-Message  "Changing working directory to $VARCD\mindcraft"  -Type "INFO"
	New-Item -Path "$VARCD\mindcraft" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	
	Write-Message  "Running git clone https://github.com/mindcraft-ce/mindcraft-ce.git "  -Type "INFO"
	Start-Process -FilePath "$VARCD\PortableGit\cmd\git.exe" -WorkingDirectory "$VARCD\mindcraft" -ArgumentList " clone `"https://github.com/mindcraft-ce/mindcraft-ce.git`" " -wait -NoNewWindow
	Rename-Item -Path "$VARCD\mindcraft\mindcraft-ce" -NewName "$VARCD\mindcraft\mindcraft" 
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null
	
	
	Write-Message  "Installing mindcraft. This may take a while..."  -Type "INFO"
	Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\mindcraft\mindcraft\" -ArgumentList " install --progress=true --loglevel=info " -NoNewWindow   -RedirectStandardOutput RedirectStandardOutput.txt -RedirectStandardError RedirectStandardError.txt
	Start-Sleep -Seconds 5
	
	Start-Process powershell -ArgumentList "-NoExit", "-Command", "& {Get-Content '$VARCD\mindcraft\mindcraft\RedirectStandardError.txt' -Wait}"
    
	while(!(Select-String -Path "RedirectStandardOutput.txt" -Pattern "patch-package finished" -Quiet)){Start-Sleep -Seconds 10}
	Write-Message  "Installing mindcraft Complete!"  -Type "INFO"

	Write-Message   "Settings.js: show_bot_views to true bot viewer server prismarine-viewer on http://localhost:3000" -Type "INFO"
	(gc "$VARCD\mindcraft\mindcraft\settings.js" -Raw) -replace '"show_bot_views".*', '"show_bot_views": true,' | sc  "$VARCD\mindcraft\mindcraft\settings.js"
	
	Write-Message  "Settings.js: Replace the minecraft port with common Minecraft port"  -Type "INFO"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("55916", "25565") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js"
	
	Write-Message  "Settings.js: Replace the Mindcraft port with less common port I have stuff runnning on 8080 so change to 8881"  -Type "INFO"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("8080", "8881") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js" 
 
	Write-Message  ".\Settings.js: Enableing TTS"  -Type "INFO"
	(gc "$VARCD\mindcraft\mindcraft\settings.js" -Raw) -replace '"speak".*', '"speak": true,' | sc  "$VARCD\mindcraft\mindcraft\settings.js"
	 
	Write-Message  ".\Settings.js: Enableing Vison"  -Type "INFO"
	(gc "$VARCD\mindcraft\mindcraft\settings.js" -Raw) -replace '"allow_vision".*', '"allow_vision": true,' | sc  "$VARCD\mindcraft\mindcraft\settings.js"
	(gc "$VARCD\mindcraft\mindcraft\settings.js" -Raw) -replace '"vision_mode".*', '"vision_mode": "always",' | sc  "$VARCD\mindcraft\mindcraft\settings.js"

	Write-Message  ".\src\server\mind_server.js: Replace the Mindcraft server port with 8082 "  -Type "INFO"
	(Get-Content "$VARCD\mindcraft\mindcraft\src\server\mind_server.js").Replace("8080", "8082") | Set-Content "$VARCD\mindcraft\mindcraft\src\server\mind_server.js"
 
	#################### PROFILE  _default.json
	Write-Message   ".\profiles\defaults\_default.json: Hunting to false" -Type "INFO"
	(gc ".\profiles\defaults\_default.json" -Raw) -replace '"hunting".*', '"hunting": false,' | sc  ".\profiles\defaults\_default.json"
	
	Write-Message   ".\profiles\defaults\_default.json: cowardice to true" -Type "INFO"
	(gc ".\profiles\defaults\_default.json" -Raw) -replace '"cowardice".*', '"cowardice": true,' | sc ".\profiles\defaults\_default.json"
	
	Write-Message   ".\profiles\defaults\_default.json: item_collecting to false" -Type "INFO"
	(gc ".\profiles\defaults\_default.json" -Raw) -replace '"item_collecting".*', '"item_collecting": false,' | sc ".\profiles\defaults\_default.json"
	
	Write-Message   ".\profiles\defaults\_default.json: elbow_room to true" -Type "INFO"
	(gc ".\profiles\defaults\_default.json" -Raw) -replace '"elbow_room".*', '"elbow_room": false,' | sc ".\profiles\defaults\_default.json"
	
#################### PROFILE  survival.json
	Write-Message   ".\profiles\defaults\survival.json: Hunting to false" -Type "INFO"
	(gc ".\profiles\defaults\survival.json" -Raw) -replace '"hunting".*', '"hunting": false,' | sc  ".\profiles\defaults\survival.json"
	
	Write-Message   ".\profiles\defaults\survival.json: cowardice to true" -Type "INFO"
	(gc ".\profiles\defaults\survival.json" -Raw) -replace '"cowardice".*', '"cowardice": true,' | sc ".\profiles\defaults\survival.json"
	
	Write-Message   ".\profiles\defaults\survival.json: item_collecting to false" -Type "INFO"
	(gc ".\profiles\defaults\survival.json" -Raw) -replace '"item_collecting".*', '"item_collecting": false,' | sc ".\profiles\defaults\survival.json"
	
	Write-Message   ".\profiles\defaults\survival.json: elbow_room to true" -Type "INFO"
	(gc ".\profiles\defaults\survival.json" -Raw) -replace '"elbow_room".*', '"elbow_room": false,' | sc ".\profiles\defaults\survival.json"
	
	
	Write-Message  ".\Andy.json: Updating for Ollama server and local TTS"  -Type "INFO"
	(gc "$VARCD\mindcraft\mindcraft\Andy.json" -Raw) -replace '"model".*', '"model": { "api": "ollama", "url": "http://localhost:11434","model": "sweaterdog/andy-4:q8_0" },"speak_model": "system","embedding": "ollama"' | sc  "$VARCD\mindcraft\mindcraft\Andy.json"
 
	
	}
	Write-Message  "Changing working directory to $VARCD\mindcraft"  -Type "INFO"
	New-Item -Path "$VARCD\mindcraft\mindcraft\" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null
	if($Global:GPUVRAM -match "0"){
		Write-Message  ".\Andy.json: No GPU VRAM found Looking for Open Ollama server"  -Type "WARNING"
		OllamaGapeFind
		Write-Message  ".\Andy.json: Updating Global:OllamaValidIP: $Global:OllamaValidIP  and  OllamaValidModel: $Global:OllamaValidModel  "  -Type "INFO"
		(Get-Content "$VARCD\Andy.json").Replace("localhost", "$Global:OllamaValidIP") | Set-Content "$VARCD\Andy.json"
		(gc "$VARCD\mindcraft\mindcraft\Andy.orig" -Raw) -replace '"model".*', '"model": { "api": "ollama", "url": "$Global:OllamaValidIP","model": "$Global:OllamaValidModel" }' | sc  "$VARCD\mindcraft\mindcraft\Andy.json"
	}

 	Write-Message  "Starting Mindcraft"  -Type "INFO"
	Start-Process -FilePath "$VARCD\node\node.exe" -WorkingDirectory "$VARCD\mindcraft\mindcraft" -ArgumentList " main.js " 
 
 	Write-Message  "Waiting to start bot viewer server prismarine-viewer on http://localhost:3000"  -Type "INFO"
	Start-Sleep 15
	Start-Process -FilePath "http://localhost:3000"
	
}

############# MinecraftServer
Function MinecraftServer {
	Write-Message  "Ending task Java"  -Type "INFO"
	Stop-process -name java -Force -ErrorAction SilentlyContinue |Out-Null

	Write-Message  "Running MinecraftServer"  -Type "INFO"
if (-not(Test-Path -Path "$VARCD\mindcraft\MinecraftServer" )) {

	Write-Message  "Creating $VARCD\mindcraft\MinecraftServer"  -Type "INFO"
	New-Item -Path "$VARCD\mindcraft\MinecraftServer" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	Set-Location -Path "$VARCD\mindcraft\MinecraftServer"
	
	Write-Message  "Downloading MinecraftServer"  -Type "INFO"
	downloadFile "https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar" "$VARCD\mindcraft\MinecraftServer\server.jar"
	# Create and configure server.properties

$properties = @"
server-ip=0.0.0.0
server-port=25565
online-mode=false
eula=true
gamemode=survival
difficulty=peaceful # normal DEBUG peaceful
allow-cheats=flase
force-gamemode=false
enable-command-block=true
show_bot_views: true
prevent-proxy-connections=false
view-distance=20
pvp=true
allow-nether=true
bonus-chest=true

"@
$properties | Out-File "$VARCD\mindcraft\MinecraftServer\server.properties" -encoding ascii

# Create eula.txt
out-file -filepath .\eula.txt -encoding ascii -inputobject "eula=true`n"

}
 
# Run the server
Start-Process -FilePath "java.exe" -WorkingDirectory "$VARCD\mindcraft\MinecraftServer" -ArgumentList " -Xmx4G -jar server.jar   " -RedirectStandardOutput "server.log"   -WindowStyle hidden
while ($true) {
    if (Get-Content "server.log" -Tail 1 | Select-String "Done") {
		Write-Message  "Minecraft server world loaded!"  -Type "INFO"
		#Start-Sleep -Seconds 2
		#Start-Process powershell -ArgumentList "-NoExit", "-Command", "Get-Content `"$VARCD\mindcraft\MinecraftServer\logs\latest.log`" -Wait -Tail 50"

        return
    }
	Write-Message  "Waiting for world to load.."  -Type "INFO"
    Start-Sleep -Seconds 4
}
}

######################################################################################################################### FUNCTIONS END

############# mindcraft
$Button = New-Object System.Windows.Forms.Button
$Button.AutoSize = $true
$Button.Text = "Mindcraft"
$Button.Location = New-Object System.Drawing.Point(($hShift+0),($vShift+0))
$Button.Add_Click({mindcraft})
$main_form.Controls.Add($Button)
$vShift = $vShift + 30

############# mindcraftStart
$Button = New-Object System.Windows.Forms.Button
$Button.AutoSize = $true
$Button.Text = "Restart Bot"
$Button.Location = New-Object System.Drawing.Point(($hShift+0),($vShift+0))
$Button.Add_Click({mindcraftStart})
$main_form.Controls.Add($Button)
$vShift = $vShift + 30

############# CMDPrompt
$Button = New-Object System.Windows.Forms.Button
$Button.AutoSize = $true
$Button.Text = "Command Prompt Java/Git/Node/Python"
$Button.Location = New-Object System.Drawing.Point(($hShift),($vShift+0))
$Button.Add_Click({CMDPrompt})
$main_form.Controls.Add($Button)
$vShift = $vShift + 30

############# UpdateJAMBO
$Button = New-Object System.Windows.Forms.Button
$Button.AutoSize = $true
$Button.Text = "Update"
$Button.Location = New-Object System.Drawing.Point(($hShift+0),($vShift+0))
$Button.Add_Click({UpdateJAMBO})
$main_form.Controls.Add($Button)
$vShift = $vShift + 30 

############# SHOW FORM
$main_form.ShowDialog()

