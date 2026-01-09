# Set environment
$VARCD = Get-Location
$env:HOMEPATH = $env:USERPROFILE = $VARCD
$env:APPDATA = "$VARCD\AppData\Roaming"
$env:LOCALAPPDATA = "$VARCD\AppData\Local"
$env:TEMP = $env:TMP = "$VARCD\AppData\Local\Temp"
$env:JAVA_HOME = "$VARCD\jdk"
$env:Path = "$env:Path;$VARCD\jdk\bin"

# Fast download function
function downloadFile($url, $targetFile) {
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000)
    $response = $request.GetResponse()
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 64KB
    $count = $responseStream.Read($buffer,0,$buffer.length)
    while ($count -gt 0) {
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer,0,$buffer.length)
    }
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

# Async download with 16 threads
function Download-Async($downloads) {
    $jobs = @()
    $throttle = 16
    $i = 0

    foreach ($dl in $downloads) {
        while ((Get-Job -State Running).Count -ge $throttle) {
            Start-Sleep -Milliseconds 50
        }

        $jobs += Start-Job -ScriptBlock {
            param($url, $path)
            $dir = Split-Path $path
            if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            if (!(Test-Path $path)) {
                try {
                    $uri = New-Object "System.Uri" "$url"
                    $request = [System.Net.HttpWebRequest]::Create($uri)
                    $request.set_Timeout(15000)
                    $response = $request.GetResponse()
                    $responseStream = $response.GetResponseStream()
                    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $path, Create
                    $buffer = new-object byte[] 64KB
                    $count = $responseStream.Read($buffer,0,$buffer.length)
                    while ($count -gt 0) {
                        $targetStream.Write($buffer, 0, $count)
                        $count = $responseStream.Read($buffer,0,$buffer.length)
                    }
                    $targetStream.Flush()
                    $targetStream.Close()
                    $targetStream.Dispose()
                    $responseStream.Dispose()
                } catch {}
            }
        } -ArgumentList $dl.url, $dl.path

        if (++$i % 100 -eq 0) { Write-Host "Queued $i/$($downloads.Count) downloads..." }
    }

    $jobs | Wait-Job | Remove-Job
}

# Create servers.dat NBT file
function Create-ServersDat($serverIp, $serverPort, $serverName, $outputPath) {
    Add-Type -AssemblyName System.IO.Compression

    $ms = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($ms)

    # NBT format for servers.dat
    $writer.Write([byte]10) # TAG_Compound
    $writer.Write([byte]0)  # Name length
    $writer.Write([byte]0)

    # TAG_List "servers"
    $writer.Write([byte]9)  # TAG_List
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes("servers")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$nameBytes.Length)))
    $writer.Write($nameBytes)
    $writer.Write([byte]10) # List type: TAG_Compound
    $writer.Write([int32]([System.Net.IPAddress]::HostToNetworkOrder([int32]1)))

    # Server entry
    $writer.Write([byte]8)  # TAG_String "ip"
    $ipTagBytes = [System.Text.Encoding]::UTF8.GetBytes("ip")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$ipTagBytes.Length)))
    $writer.Write($ipTagBytes)
    $serverAddress = "$serverIp`:$serverPort"
    $serverAddressBytes = [System.Text.Encoding]::UTF8.GetBytes($serverAddress)
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$serverAddressBytes.Length)))
    $writer.Write($serverAddressBytes)

    $writer.Write([byte]8)  # TAG_String "name"
    $nameTagBytes = [System.Text.Encoding]::UTF8.GetBytes("name")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$nameTagBytes.Length)))
    $writer.Write($nameTagBytes)
    $serverNameBytes = [System.Text.Encoding]::UTF8.GetBytes($serverName)
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$serverNameBytes.Length)))
    $writer.Write($serverNameBytes)

    $writer.Write([byte]0) # TAG_End server compound
    $writer.Write([byte]0) # TAG_End root compound

    $writer.Flush()
    [System.IO.File]::WriteAllBytes($outputPath, $ms.ToArray())
    $writer.Close()
    $ms.Close()
}

# Check Java
if (!(Test-Path "$VARCD\jdk")) {
    Write-Host "Downloading Java..." -ForegroundColor Yellow
    downloadFile "https://download.java.net/java/GA/jdk24/1f9ff9062db4449d8ca828c504ffae90/36/GPL/openjdk-24_windows-x64_bin.zip" "$VARCD\jdk.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$VARCD\jdk.zip", "$VARCD")
    Get-ChildItem "$VARCD\jdk-*" | Rename-Item -NewName { $_.Name -replace '-.*','' }
}

# Setup directories
$version = "1.21.6"
$versionsDir = "$VARCD\versions\$version"
$librariesDir = "$VARCD\libraries"
$assetsDir = "$VARCD\assets"
$minecraftDir = "$VARCD\minecraft"

@($versionsDir, $librariesDir, $assetsDir, $minecraftDir) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

Write-Host "Downloading Minecraft $version..." -ForegroundColor Green

# Get version data
$manifest = Invoke-RestMethod "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
$versionData = $manifest.versions | Where-Object { $_.id -eq $version }
$versionJson = Invoke-RestMethod $versionData.url
$versionJson | ConvertTo-Json -Depth 100 | Out-File "$versionsDir\$version.json"

# Prepare download list
$downloads = @()

# Client JAR
$downloads += @{url=$versionJson.downloads.client.url; path="$versionsDir\$version.jar"}

# Libraries
foreach ($lib in $versionJson.libraries) {
    if ($lib.rules) {
        $allowed = $false
        foreach ($rule in $lib.rules) {
            if ($rule.action -eq "allow" -and (!$rule.os -or $rule.os.name -eq "windows")) { $allowed = $true }
            if ($rule.action -eq "disallow" -and $rule.os.name -eq "windows") { $allowed = $false }
        }
        if (!$allowed) { continue }
    }

    $artifact = $lib.downloads.artifact
    if (!$artifact -and $lib.downloads.classifiers -and $lib.natives) {
        $nativeKey = $lib.natives.'windows'
        if ($nativeKey) { $artifact = $lib.downloads.classifiers.$nativeKey }
    }

    if ($artifact) {
        $downloads += @{url=$artifact.url; path="$librariesDir\$($artifact.path)"}
    }
}

# Download client and libraries
Write-Host "Downloading client and libraries..." -ForegroundColor Cyan
Download-Async $downloads

# Download assets using Mojang's asset index
Write-Host "Downloading asset index..." -ForegroundColor Cyan
$assetsIndexDir = "$assetsDir\indexes"
$assetsObjectsDir = "$assetsDir\objects"
New-Item -ItemType Directory -Force -Path $assetsIndexDir, $assetsObjectsDir | Out-Null

# Download asset index
$assetIndexUrl = $versionJson.assetIndex.url
$assetIndexPath = "$assetsIndexDir\$($versionJson.assetIndex.id).json"
downloadFile $assetIndexUrl $assetIndexPath

# Parse asset index
$assetIndex = Get-Content $assetIndexPath | ConvertFrom-Json

# Prepare asset downloads
Write-Host "Preparing asset downloads..." -ForegroundColor Cyan
$assetDownloads = @()
foreach ($asset in $assetIndex.objects.PSObject.Properties) {
    $hash = $asset.Value.hash
    $hashPrefix = $hash.Substring(0, 2)
    $assetPath = "$assetsObjectsDir\$hashPrefix\$hash"

    if (!(Test-Path $assetPath)) {
        $assetDownloads += @{
            url = "https://resources.download.minecraft.net/$hashPrefix/$hash"
            path = $assetPath
        }
    }
}

Write-Host "Downloading $($assetDownloads.Count) assets..." -ForegroundColor Cyan
Download-Async $assetDownloads
Write-Host "Assets downloaded successfully!" -ForegroundColor Green

# Create servers.dat
Write-Host "Creating servers.dat..." -ForegroundColor Cyan
Create-ServersDat "tunnel.rmccurdy.com" "55631" "RMcCurdy Server" "$minecraftDir\servers.dat"

# Build classpath with relative paths from script directory
$classpathItems = @("%~dp0versions\$version\$version.jar")
$classpathItems += (Get-ChildItem -Path $librariesDir -Recurse -Filter *.jar | ForEach-Object { 
    "%~dp0libraries\" + $_.FullName.Substring($librariesDir.Length + 1)
})
$classpath = $classpathItems -join ";"

# Create launch script - stay in script directory, not minecraft directory
$launchScript = @"
@echo off
set /p PlayerName="Enter Minecraft Username: "
"%~dp0jdk\bin\javaw.exe" -Xmx2G -Xms1G -cp "$classpath" net.minecraft.client.main.Main --version $version --accessToken 0 --userProperties {} --gameDir "%~dp0minecraft" --assetsDir "%~dp0assets" --assetIndex $($versionJson.assetIndex.id) --username "%PlayerName%"
"@

$launchScript | Out-File "$VARCD\launch_$version.bat" -Encoding ASCII

Write-Host "`nComplete! Launch: $VARCD\launch_$version.bat" -ForegroundColor Green
Start-Process "$VARCD\launch_$version.bat"
