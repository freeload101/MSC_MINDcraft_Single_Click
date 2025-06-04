param(
    [Parameter(Mandatory=$false)]
    [string]$Headless
)


# function for messages
#$ErrorActionPreference="Continue"
$VerNum = 'MSC 1.1b'
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
			Write-Host "Downloading latest node"
			$downloadUri = $downloadUri = (Invoke-RestMethod -Method GET -Uri "https://nodejs.org/dist/latest/")  -split '"' -match '.*node-.*-win-x64.zip.*' | ForEach-Object {$_ -ireplace '^\/','https://nodejs.org/' } | select -first 1
            downloadFile "$downloadUri" "$VARCD\node.zip"
			Write-Host "Extracting Node"
			Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\node.zip", "$VARCD")
			Get-ChildItem "$VARCD\node-*"  | Rename-Item -NewName "node"
			Write-Host "Updating npm"
			Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\node" -ArgumentList " install -g npm " -wait -NoNewWindow
			}
                catch {
                    throw $_.Exception.Message
            }
            }
        else {
			Write-Host "$VARCD\node already Exist"
			}
}

############# downloadFile
function downloadFile($url, $targetFile)
{
    "Downloading $url"
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
    "Finished Download"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

############# CHECK JAVA
Function CheckJava {
Write-Host "Checking for Java"
   if (-not(Test-Path -Path "$VARCD\jdk" )) {
            Write-Host "Downloading Java"
            downloadFile "https://download.java.net/java/GA/jdk24/1f9ff9062db4449d8ca828c504ffae90/36/GPL/openjdk-24_windows-x64_bin.zip" "$VARCD\jdk.zip"
            Write-Host "Extracting Java"
			Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\jdk.zip", "$VARCD")
			Get-ChildItem "$VARCD\jdk-*"  | Rename-Item -NewName { $_.Name -replace '-.*','' }
            $env:JAVA_HOME = "$VARCD\jdk"
            }
        else {
            Write-Host "$VARCD\openjdk.zip already exists"
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
	 Write-Host "Checking Git"
   if (-not(Test-Path -Path "$VARCD\PortableGit" )) {
        try {
            Write-Host "Downloading Git"

            $downloadUri = ((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest").assets | Where-Object name -like *PortableGit*64*.exe ).browser_download_url | select -first 1
            downloadFile "$downloadUri" "$VARCD\git7zsfx.exe"
            Start-Process -FilePath "$VARCD\git7zsfx.exe" -WorkingDirectory "$VARCD\" -ArgumentList " -o`"$VARCD\PortableGit`" -y " -wait -NoNewWindow}
                catch {
                    throw $_.Exception.Message
                }
            }
        else {
            Write-Host "$VARCD\Git already exists"
            }
}

############# UpdateJAMBO
Function UpdateJAMBO {
$JAMBOPATH = Get-ScriptPathFromCallStack
Write-Host "Downloading latest JAMBOREE to $JAMBOPATH"
Invoke-WebRequest -Method GET -Uri 'https://github.com/freeload101/MSC_Single_Click_MINDcraft/raw/refs/heads/main/MSC_Single_Click_MINDcraft.ps1' -OutFile "$JAMBOPATH"
Write-Host "Restarting"
Start-Sleep -Seconds 1
Set-Variable -Name ErrorActionPreference -Value SilentlyContinue

Start-Process -FilePath "powershell" -WorkingDirectory "$VARCD\" -ArgumentList " -File `"$JAMBOPATH`" "  -ErrorAction SilentlyContinue
#exit 0
}

############# EXECheckOllama
function EXECheckOllama{
  if (-not(Test-Path -Path "$VARCD\Ollama" )) {
	try {
		Stop-process -name ollama -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name "ollama app" -Force -ErrorAction SilentlyContinue |Out-Null
		
		Write-Host  "Downloading Latetst binary from github"
		$downloadUri = ((Invoke-RestMethod -Method GET -Uri "https://api.github.com/repos/ollama/ollama/releases/latest").assets | Where-Object name -like ollama-windows-amd64.zip ).browser_download_url
		downloadFile  $downloadUri "$VARCD\ollama-windows-amd64.zip"
		Write-Host "Extracting ollama-windows-amd64.zip"
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		Add-Type -AssemblyName System.IO.Compression
		[System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\ollama-windows-amd64.zip", "$VARCD\Ollama\")
		
		Write-Host  "Setting .ollama OLLAMA_MODELS System.Environment to $VARCD\Ollama\ and listen on 0.0.0.0"
		[System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "$VARCD\Ollama\.ollama", [System.EnvironmentVariableTarget]::Machine)
		[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0", [System.EnvironmentVariableTarget]::Machine)
		[System.Environment]::SetEnvironmentVariable("OLLAMA_KEEP_ALIVE", "-1", [System.EnvironmentVariableTarget]::Machine)
		
		
		}
			catch {
				throw $_.Exception.Message
		}
		}
		
		Write-Host  "Starting Ollama ...."
		Stop-process -name ollama -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name "ollama app" -Force -ErrorAction SilentlyContinue |Out-Null
		Start-Sleep -Seconds 1
		Start-Process -FilePath "$VARCD\Ollama\ollama app.exe" -WorkingDirectory "$VARCD\Ollama\"
		while(!(Get-Process "ollama app" -ErrorAction SilentlyContinue)){Start-Sleep -Seconds 5};Write-Host  "Waiting for Ollama to start"
		Start-Sleep -Seconds 2
  		Remove-Item -Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk" -Force -ErrorAction SilentlyContinue |Out-Null
}

############# OllamaGape
function OllamaGape {
    param(
        $OllamaIP
    )

    Write-Host "Checking: $OllamaIP"
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
	Write-Host "Downloading latest Public Ollama Server list"
	Invoke-WebRequest -Uri "https://raw.githubusercontent.com/freeload101/SCRIPTS/refs/heads/master/MISC/OllamaGape.csv" -OutFile "$VARCD\mindcraft\OllamaGape.txt"
		
    $maxAttempts = 10  # Maximum number of attempts
    $attempt = 1      # Current attempt counter
    $success = $false # Success flag

    while (-not $success -and $attempt -le $maxAttempts) {
        try {
        
            $OllamaCSV = OllamaGape (Get-Content "$VARCD\mindcraft\OllamaGape.txt" | Get-Random )
			$Global:OllamaValidIP = $OllamaCSV -replace ',.*',''  -replace '\r',''  -replace '\n','' -replace '\s',''
            $Global:OllamaValidModel = $Global:OlammaModel
			
       		Write-Host "Attempt $attempt Operation successful $OllamaCSV IP $Global:OllamaValidIP Model $Global:OllamaValidModel"
            $success = $true  # Set success flag to exit loop
        
        }
        catch {
            Write-Host "Attempt $attempt failed with error: $($_.Exception.Message)"
            $attempt++
        }
    }
}

#################### mindcraftStart
function mindcraftStart {
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null
 
	Write-Host "Removing Andy memory folder $VARCD\mindcraft\mindcraft\bots\Andy "
 	Remove-Item -Path "$VARCD\mindcraft\mindcraft\bots\Andy" -Force -ErrorAction SilentlyContinue  -Confirm:$false -Recurse |Out-Null
	Write-Host "Starting Mindcraft"
 	Start-Sleep -Seconds 10
	Start-Process -FilePath "$VARCD\node\node.exe" -WorkingDirectory ".\" -ArgumentList " main.js "
}

############# CheckGPU
Function CheckGPU {
	$GPUList = Get-ItemProperty -Path "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*"   | Where-Object {$_."HardwareInformation.qwMemorySize" -gt 0}  	
	$VRAM = [math]::round($GPUList."HardwareInformation.qwMemorySize"/1GB)	

	if ($VRAM -lt 5) {
			Write-Host "Dedicated GPU Less then 5 GB VRAM. Dedicated GPU Memory this is differnet then Shared GPU memory or GPU Memory ! We can use public Ollama servers or see FAQ for Mindcraft to setup APIs"
			$Global:GPUVRAM = 0
			(Get-WmiObject -Namespace root\CIMV2 -Class CIM_VideoController)  | Select-Object Name,Description,Caption,DeviceID,VideoMemoryType  | Format-Table -AutoSize
			
	} else {
	$DriverDesc = $GPUList.DriverDesc
	Write-Host "Dedicated GPU: $DriverDesc with $VRAM GB of VRAM"
	$Global:GPUVRAM = 1 # DEBUG 0
	EXECheckOllama
		}	
}

############# mindcraft
Function mindcraft {
Stop-process -name java -Force -ErrorAction SilentlyContinue |Out-Null
Stop-process -name javaw -Force -ErrorAction SilentlyContinue |Out-Null
CheckPython
CheckGPU
CheckGit
CheckJava
CheckNode
MinecraftServer
	
if (-not(Test-Path -Path "$VARCD\mindcraft\mindcraft" )) {
	
	Write-Host "Changing working directory to $VARCD\mindcraft"
	New-Item -Path "$VARCD\mindcraft" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	New-Item -Path "$VARCD\mindcraft\mindcraft\" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null
		
	Write-Host "Running git clone https://github.com/kolbytn/mindcraft.git "
	Start-Process -FilePath "$VARCD\PortableGit\cmd\git.exe" -WorkingDirectory "$VARCD\mindcraft" -ArgumentList " clone `"https://github.com/kolbytn/mindcraft.git`" " -wait -NoNewWindow

	Write-Host "Installing mindcraft"
	#npm install --save-dev node-canvas-webgl@latest --ignore-scripts
	# Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\mindcraft\mindcraft\" -ArgumentList " install  " -wait -NoNewWindow
	Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\mindcraft\mindcraft\" -ArgumentList " install --save-dev node-canvas-webgl@latest --ignore-scripts  " -wait -NoNewWindow

	Write-Host "Settings.js: show_bot_views to true bot viewer server prismarine-viewer on http://localhost:3000"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("`"show_bot_views`": false", "`"show_bot_views`": true") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js"

	Write-Host "Settings.js: Replace the minecraft port with common Minecraft port"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("55916", "25565") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js"
	
	Write-Host "Settings.js: Replace the Mindcraft port with less common port I have stuff runnning on 8080 so change to 8881"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("8080", "8881") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js"

	Write-Host "Settings.js: Replace andy with moded Andy profile for ollama"
	(Get-Content "$VARCD\mindcraft\mindcraft\settings.js").Replace("andy", "profiles/Andy") | Set-Content "$VARCD\mindcraft\mindcraft\settings.js"
	
	Write-Host ".\src\server\mind_server.js: Replace the port with common Minecraft port "
	(Get-Content "$VARCD\mindcraft\mindcraft\src\server\mind_server.js").Replace("8080", "8082") | Set-Content "$VARCD\mindcraft\mindcraft\src\server\mind_server.js"
	
	Write-Host ".\profiles\Andy.json: Downloading Andy.json profile "
	Invoke-WebRequest -Uri "https://github.com/freeload101/SCRIPTS/raw/refs/heads/master/MISC/Andy.json" -OutFile "$VARCD\mindcraft\mindcraft\profiles\Andy.json"
 
 	Write-Host "Installing prismarine-viewer@1.28.0 to fix broken repo"
	Start-Process -FilePath "$VARCD\node\npm.cmd" -WorkingDirectory ".\" -ArgumentList " install prismarine-viewer@1.28.0 " -wait -NoNewWindow
 
	}
	Write-Host "Changing working directory to $VARCD\mindcraft"
	New-Item -Path "$VARCD\mindcraft\mindcraft\" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	Set-Location -Path "$VARCD\mindcraft\mindcraft\" -ErrorAction SilentlyContinue |Out-Null


	if($Global:GPUVRAM -match "0"){
		Write-Host ".\profiles\Andy.json: No GPU VRAM found Downloading Andy.json"
		Invoke-WebRequest -Uri "https://raw.githubusercontent.com/freeload101/SCRIPTS/refs/heads/master/MISC/Andy.json" -OutFile "$VARCD\mindcraft\mindcraft\profiles\Andy.json"
		OllamaGapeFind
		Write-Host "Andy.json: Updating Global:OllamaValidIP: $Global:OllamaValidIP  and  OllamaValidModel: $Global:OllamaValidModel  "
		(Get-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json").Replace("localhost", "$Global:OllamaValidIP") | Set-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json"
		(Get-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json").Replace("`"model`": `"sweaterdog/andy-4:q8_0`",", "`"model`": `"$Global:OllamaValidModel`",") | Set-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json"
		(Get-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json").Replace("`"model`": `"nomic-embed-text`"", "`"model`": `"$Global:OllamaValidModel`"") | Set-Content "$VARCD\mindcraft\mindcraft\profiles\Andy.json"
	}

 	Write-Host "Starting Mindcraft"
	Start-Process -FilePath "$VARCD\node\node.exe" -WorkingDirectory ".\" -ArgumentList " main.js " 
 
 	Write-Host "Waiting to start bot viewer server prismarine-viewer on http://localhost:3000"
	Start-Sleep 15
	Invoke-Item "http://localhost:3000"
	
}

############# MinecraftServer
Function MinecraftServer {
		Write-Host "Killing Java and Javaw "
		Stop-process -name java -Force -ErrorAction SilentlyContinue |Out-Null
		Stop-process -name javaw -Force -ErrorAction SilentlyContinue |Out-Null
	Write-Host "Running MinecraftServer"
if (-not(Test-Path -Path "$VARCD\mindcraft\MinecraftServer" )) {

	Write-Host "Creating $VARCD\mindcraft\MinecraftServer"
	New-Item -Path "$VARCD\mindcraft\MinecraftServer" -ItemType Directory  -ErrorAction SilentlyContinue |Out-Null
	Set-Location -Path "$VARCD\mindcraft\MinecraftServer"
	
	Write-Host "Downloading MinecraftServer"
	downloadFile "https://piston-data.mojang.com/v1/objects/59353fb40c36d304f2035d51e7d6e6baa98dc05c/server.jar" "$VARCD\mindcraft\MinecraftServer\server.jar"
	# Create and configure server.properties

$properties = @"
server-ip=0.0.0.0
server-port=25565
online-mode=false
eula=true
gamemode=survival
difficulty=normal
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
Start-Process -FilePath "java.exe" -WorkingDirectory "$VARCD\mindcraft\MinecraftServer" -ArgumentList " -Xmx2G -jar server.jar nogui  " -RedirectStandardOutput "server.log" -WindowStyle hidden


while ($true) {
    if (Get-Content "server.log" -Tail 1 | Select-String "Done") {
		Write-Host "Minecraft server world loaded!"
		Start-Sleep -Seconds 2
		Start-Process powershell -ArgumentList "-NoExit", "-Command", "Get-Content `"$VARCD\mindcraft\MinecraftServer\logs\latest.log`" -Wait -Tail 50"

        return
    }
	Write-Host "Waiting for world to load.."
    Start-Sleep -Seconds 2
}


}

######################################################################################################################### FUNCTIONS END

############# CMDPrompt
$Button = New-Object System.Windows.Forms.Button
$Button.AutoSize = $true
$Button.Text = "Command Prompt Java/Git/Node/Python"
$Button.Location = New-Object System.Drawing.Point(($hShift),($vShift+0))
$Button.Add_Click({CMDPrompt})
$main_form.Controls.Add($Button)
$vShift = $vShift + 30

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
