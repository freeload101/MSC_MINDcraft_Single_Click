param([string]$Headless)

$VerNum = 'MSC LMS Studio 1.0a'
$host.ui.RawUI.WindowTitle = $VerNum
Set-Location ($VARCD = (Get-Location))
$env:HOMEPATH = $env:USERPROFILE = $VARCD
$env:APPDATA = "$VARCD\AppData\Roaming"
$env:LOCALAPPDATA = "$VARCD\AppData\Local"
$env:TEMP = $env:TMP = "$VARCD\AppData\Local\Temp"
$env:JAVA_HOME = "$VARCD\jdk"
$env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\;$VARCD\PortableGit\cmd;$VARCD\jdk\bin;$VARCD\node;$VARCD\python\tools\Scripts;$VARCD\python\tools;python\tools\Lib\site-packages"

Add-Type -Assembly System.Windows.Forms
$main_form = New-Object System.Windows.Forms.Form
$main_form.AutoSize = $true
$main_form.Text = $VerNum
$hShift = 0; $vShift = 0

function Write-Message([string]$Type, [string]$Message) {
    $map = @{ INFO='Green'; WARNING='Yellow'; ERROR='Red' }
    Write-Host "$(Get-Date -UFormat '%m/%d:%T') $Type $Message" -ForegroundColor $map[$Type]
}

function downloadFile($url, $targetFile) {
    Write-Message INFO "Downloading $url"
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = 15000
    $resp = $req.GetResponse()
    $rs = $resp.GetResponseStream()
    $ts = New-Object System.IO.FileStream($targetFile, [System.IO.FileMode]::Create)
    $buf = New-Object byte[] 10240
    while (($n = $rs.Read($buf, 0, $buf.Length)) -gt 0) { $ts.Write($buf, 0, $n) }
    $ts.Flush(); $ts.Dispose(); $rs.Dispose()
    Write-Message INFO "Finished Download"
}

function CheckPython {
    if (Test-Path "$VARCD\python") { Write-Message WARNING "$VARCD\python already exists"; return }
    Write-Message INFO "Downloading Python nuget package"
    downloadFile "https://www.nuget.org/api/v2/package/python" "$VARCD\python.zip"
    New-Item "$VARCD\python" -ItemType Directory -EA SilentlyContinue | Out-Null
    Write-Message INFO "Extracting Python nuget package"
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\python.zip", "$VARCD\python")
    Write-Message INFO "Updating pip"
    Start-Process "$VARCD\python\tools\python.exe" -WorkingDirectory "$VARCD\python\tools" -ArgumentList "-m pip install --upgrade pip" -Wait -NoNewWindow
    New-Item "$VARCD\python\tools\Scripts" -ItemType Directory -EA SilentlyContinue | Out-Null
$PipBatch = @'
python -m pip %*
'@
    $PipBatch | Out-File -Encoding Ascii "$VARCD\python\tools\Scripts\pip.bat" -EA SilentlyContinue | Out-Null
    Write-Message INFO "CheckPython Complete"
}

function CheckNode {
    if (Test-Path "$VARCD\node") { Write-Message WARNING "$VARCD\node already exists"; return }
    try {
        Write-Message INFO "Downloading latest Node"
        $uri = (Invoke-RestMethod -Uri "https://nodejs.org/dist/latest/") -split '"' -match '.*node-.*-win-x64\.zip.*' |
               ForEach-Object { $_ -ireplace '^\/','https://nodejs.org/' } | Select-Object -First 1
        downloadFile $uri "$VARCD\node.zip"
        Write-Message INFO "Extracting Node"
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\node.zip", "$VARCD")
        Get-ChildItem "$VARCD\node-*" | Rename-Item -NewName "node"
        Write-Message INFO "Updating npm"
        Start-Process "$VARCD\node\npm.cmd" -WorkingDirectory "$VARCD\node" -ArgumentList "install -g npm" -Wait -NoNewWindow
    } catch { throw $_.Exception.Message }
}

function CheckJava {
    Write-Message INFO "Checking for Java"
    if (Test-Path "$VARCD\jdk") { Write-Message WARNING "$VARCD\jdk already exists"; return }
    Write-Message INFO "Downloading Java"
    downloadFile "https://download.java.net/java/GA/jdk24/1f9ff9062db4449d8ca828c504ffae90/36/GPL/openjdk-24_windows-x64_bin.zip" "$VARCD\jdk.zip"
    Write-Message INFO "Extracting Java"
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\jdk.zip", "$VARCD")
    Get-ChildItem "$VARCD\jdk-*" | Rename-Item -NewName { $_.Name -replace '-.*','' }
    $env:JAVA_HOME = "$VARCD\jdk"
}

function CheckGit {
    Write-Message INFO "Checking Git"
    if (Test-Path "$VARCD\PortableGit") { Write-Message WARNING "$VARCD\Git already exists"; return }
    try {
        Write-Message INFO "Downloading Git"
        $uri = ((Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest").assets |
                Where-Object name -like '*PortableGit*64*.exe').browser_download_url | Select-Object -First 1
        downloadFile $uri "$VARCD\git7zsfx.exe"
        Start-Process "$VARCD\git7zsfx.exe" -WorkingDirectory "$VARCD\" -ArgumentList "-o`"$VARCD\PortableGit`" -y" -Wait -NoNewWindow
    } catch { throw $_.Exception.Message }
}

function CMDPrompt {
    CheckJava; CheckGit; CheckNode
    Start-Process cmd -WorkingDirectory "$VARCD"
}

function Get-MinecraftVersion {
    $manifest = Invoke-RestMethod -Uri "https://launchermeta.mojang.com/mc/game/version_manifest.json"
    Add-Type -Assembly System.Windows.Forms
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Select Minecraft Version"
    $form.Size = New-Object System.Drawing.Size(400,500)
    $form.StartPosition = "CenterScreen"
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point(10,10)
    $lb.Size = New-Object System.Drawing.Size(360,380)
    $manifest.versions | Where-Object { $_.id -match '^[\d\.]+$' } | ForEach-Object { [void]$lb.Items.Add($_.id) }
    $btn = New-Object System.Windows.Forms.Button
    $btn.Location = New-Object System.Drawing.Point(10,400)
    $btn.Size = New-Object System.Drawing.Size(360,40)
    $btn.Text = "Download Selected Version"
    $btn.Add_Click({
        if (-not $lb.SelectedItem) { [System.Windows.Forms.MessageBox]::Show("Please select a version","Error"); return }
        $ver = $manifest.versions | Where-Object id -eq $lb.SelectedItem
        $vj  = Invoke-RestMethod -Uri $ver.url
        if ($vj.downloads.client.url) { Write-Message INFO "Downloading client JAR..."; downloadFile $vj.downloads.client.url "$VARCD\client.jar" }
        if ($vj.downloads.server.url) { Write-Message INFO "Downloading server JAR..."; downloadFile $vj.downloads.server.url "$VARCD\mindcraft\MinecraftServer\server.jar" }
        $form.Close()
    })
    $form.Controls.AddRange(@($lb,$btn))
    [void]$form.ShowDialog()
}

function UpdateJAMBO {
    $path = $PSCommandPath
    Write-Message INFO "Downloading latest update to $path"
    Invoke-WebRequest -Uri 'https://github.com/freeload101/MSC_Single_Click_MINDcraft/raw/refs/heads/main/MSC_Single_Click_MINDcraft.ps1' -OutFile $path
    Write-Message INFO "Restarting"
    Start-Sleep 1
    Start-Process powershell -WorkingDirectory "$VARCD\" -ArgumentList "-File `"$path`"" -EA SilentlyContinue
}

function EXECheckLMStudio {
	Write-Message INFO "Checking for LM Studio"
	Set-Location ($VARCD)
	$scriptFile = "$VARCD\LMStudioSC.ps1"
	downloadFile "https://github.com/freeload101/MSC_MINDcraft_Single_Click/raw/refs/heads/main/LMStudioSC.ps1" $scriptFile

	Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
	& $scriptFile
	}
 


function CheckGPU {
    $gpu  = Get-ItemProperty "HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0*" |
            Where-Object { $_."HardwareInformation.qwMemorySize" -gt 0 }
    $VRAM = [math]::Round($gpu."HardwareInformation.qwMemorySize" / 1GB)
    if ($VRAM -lt 5) {
        Write-Message WARNING "GPU VRAM < 5 GB. Andy-4.1 does not run on Ollama... so no public LM Studio servers RN ...Watch discord for andy API supporting Andy-4.1"
        $Global:GPUVRAM = 0
        Get-WmiObject -Class CIM_VideoController | Select-Object Name,Description,DeviceID,VideoMemoryType | Format-Table -AutoSize
		Start-Sleep 20
		exit

    } else {
        Write-Message WARNING "GPU: $($gpu.DriverDesc) with $VRAM GB VRAM"
        $Global:GPUVRAM = 1
@'
{ "name": "andy", "model": { "api": "openai", "model": "andy-4.1", "url": "http://localhost:1234/v1" } , "speak_model": null }
'@ | Set-Content "$VARCD\mindcraft\mindcraft-ce\Andy.json" -NoNewline

		Write-Message INFO "Writing keys.json template for local LM Studio"
@'
{ "OPENAI_API_KEY": "DUMMYKEYFORLMSTUDIO"}
'@ | Set-Content "$VARCD\mindcraft\mindcraft-ce\keys.json" -NoNewline

        EXECheckLMStudio
    }

   
}

function CheckSDK {
    $msbuild = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    if (Test-Path $msbuild) { Write-Message INFO "VS BuildTools found"; return }
    @("$VARCD\AppData\Local\Temp","$VARCD\AppData\Roaming","$VARCD\AppData\Local") |
        ForEach-Object { New-Item $_ -ItemType Directory -EA SilentlyContinue | Out-Null }
    Write-Message INFO "Installing VS 2022 BuildTools (5-20 min)..."
    Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile "$VARCD\vs_buildtools.exe"
    Start-Process "$VARCD\vs_buildtools.exe" -ArgumentList @(
        "--quiet","--wait","--norestart","--nocache",
        "--add","Microsoft.VisualStudio.Workload.VCTools",
        "--add","Microsoft.Component.MSBuild",
        "--add","Microsoft.VisualStudio.Component.Roslyn.Compiler",
        "--includeRecommended"
    ) -Wait
    Write-Message INFO "VS BuildTools install complete"
}

function CheckMindcraft {
    if (Test-Path "$VARCD\mindcraft\mindcraft-ce") { return }
    Write-Message INFO "Cloning mindcraft-ce"
    New-Item "$VARCD\mindcraft" -ItemType Directory -EA SilentlyContinue | Out-Null
    New-Item "$VARCD\mindcraft\mindcraft-ce\" -ItemType Directory -EA SilentlyContinue | Out-Null
    # DEV LOL ... Start-Process "$VARCD\PortableGit\cmd\git.exe" -WorkingDirectory "$VARCD\mindcraft" -ArgumentList "clone  -b dev `"https://github.com/mindcraft-ce/mindcraft-ce.git`"" -Wait -NoNewWindow
    Start-Process "$VARCD\PortableGit\cmd\git.exe" -WorkingDirectory "$VARCD\mindcraft" -ArgumentList "clone `"https://github.com/mindcraft-ce/mindcraft-ce.git`"" -Wait -NoNewWindow
    Set-Location "$VARCD\mindcraft\mindcraft-ce"

    Write-Message INFO "Starting npm install in new window..."
	
	Push-Location "$VARCD\mindcraft\mindcraft-ce"
	& "$VARCD\node\npm.cmd" install --progress=true --loglevel=info
	Pop-Location

    # Patch settings.js
    $sjs = "$VARCD\mindcraft\mindcraft-ce\settings.js"
    (Get-Content $sjs -Raw) -replace '"render_bot_view".*','"render_bot_view": true,' |
        Set-Content $sjs
    (Get-Content $sjs).Replace("55916","25565").Replace("8080","8881") | Set-Content $sjs
    (Get-Content $sjs -Raw) -replace '"speak".*','"speak": "system",' |
        Set-Content $sjs
    (Get-Content $sjs -Raw) -replace '"allow_vision".*','"allow_vision": true,' |
        Set-Content $sjs
    (Get-Content $sjs -Raw) -replace '"vision_mode".*','"vision_mode": "always",' |
        Set-Content $sjs
	(Get-Content $sjs -Raw) -replace '"base_profile".*','"base_profile": "survival",' |
        Set-Content $sjs

    # Patch mindcraft.js for mindserver port 
    $mjs = "$VARCD\mindcraft\mindcraft-ce\src\mindcraft\mindcraft.js"
    (Get-Content $mjs).Replace("8080","8881") | Set-Content $mjs

}




function MinecraftServer {
    $running = Get-WmiObject Win32_Process -Filter "Name='java.exe'" |
               Where-Object CommandLine -like "*server.jar*"
    if ($running) { Write-Message WARNING "server.jar already running PID: $($running.ProcessId)"; return }
    Write-Message INFO "Starting MinecraftServer"

    if (-not (Test-Path "$VARCD\mindcraft\MinecraftServer")) {
        New-Item "$VARCD\mindcraft\MinecraftServer" -ItemType Directory -EA SilentlyContinue | Out-Null
        Set-Location "$VARCD\mindcraft\MinecraftServer"
        Write-Message INFO "Downloading server.jar"
        downloadFile "https://piston-data.mojang.com/v1/objects/6e64dcabba3c01a7271b4fa6bd898483b794c59b/server.jar" "$VARCD\mindcraft\MinecraftServer\server.jar"
@"
server-ip=0.0.0.0
server-port=25565
online-mode=false
eula=true
gamemode=survival
difficulty=peaceful
allow-cheats=false
force-gamemode=false
enable-command-block=true
show_bot_views=true
prevent-proxy-connections=false
view-distance=20
pvp=true
allow-nether=true
bonus-chest=true
"@ | Out-File "$VARCD\mindcraft\MinecraftServer\server.properties" -Encoding ascii
        "eula=true`n" | Out-File ".\eula.txt" -Encoding ascii
    }

    Start-Process java.exe -WorkingDirectory "$VARCD\mindcraft\MinecraftServer" `
        -ArgumentList "-Xmx4G -jar server.jar" `
        -RedirectStandardOutput "$VARCD\mindcraft\MinecraftServer\server.log" `
        -WindowStyle Hidden

    while ($true) {
        if (Get-Content "$VARCD\mindcraft\MinecraftServer\server.log" -Tail 1 | Select-String "Done") {
            Write-Message INFO "Minecraft server ready!"; return
        }
        Write-Message INFO "Waiting for world to load..."
        Start-Sleep 4
    }
}
 
function StartMINDCraft {
    CheckSDK; CheckPython; CheckGit; CheckJava; CheckNode
    MinecraftServer; CheckMindcraft; CheckGPU
    Remove-Item "$VARCD\mindcraft\mindcraft-ce\bots\Andy" -Force -Recurse -EA SilentlyContinue | Out-Null
    Set-Location "$VARCD\mindcraft\mindcraft-ce"
    Write-Message INFO "Starting Mindcraft"
	Start-Process "cmd.exe" -ArgumentList "/c title MINDCraft Bot & set TITLE=MINDCraft Bot & `"$VARCD\node\node.exe`" main.js & title MINDCraft Bot" -WorkingDirectory "$VARCD\mindcraft\mindcraft-ce"
    Write-Message INFO "Waiting for bot viewer on http://localhost:3000"
}

# Build UI
$buttons = @(
    @{ Text='StartMINDCraft';                        Action={ StartMINDCraft } },
    @{ Text='Command Prompt Java/Git/Node/Python';   Action={ CMDPrompt } },
    @{ Text='Change Minecraft Server.jar';           Action={ Get-MinecraftVersion } },
    @{ Text='Update';                                Action={ UpdateJAMBO } }
)
foreach ($b in $buttons) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.AutoSize = $true
    $btn.Text = $b.Text
    $btn.Location = New-Object System.Drawing.Point($hShift, $vShift)
    $btn.Add_Click($b.Action)
    $main_form.Controls.Add($btn)
    $vShift += 30
}

[void]$main_form.ShowDialog()
