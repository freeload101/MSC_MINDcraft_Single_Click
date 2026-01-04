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
    $buffer = new-object byte[] 10KB
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

# Async download with fast method
function Download-Async($downloads) {
    $jobs = @()
    $throttle = 8
    $i = 0

    foreach ($dl in $downloads) {
        while ((Get-Job -State Running).Count -ge $throttle) {
            Start-Sleep -Milliseconds 100
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
                    $buffer = new-object byte[] 10KB
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

        if (++$i % 50 -eq 0) { Write-Host "Queued $i/$($downloads.Count) downloads..." }
    }

    $jobs | Wait-Job | Remove-Job
}

# Create servers.dat NBT file
function Create-ServersDat($serverIp, $serverPort, $serverName, $outputPath) {
    Add-Type -AssemblyName System.IO.Compression

    $ms = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($ms)

    # NBT format for servers.dat
    # TAG_Compound (root)
    $writer.Write([byte]10) # TAG_Compound
    $writer.Write([byte]0)  # Name length (root has no name)
    $writer.Write([byte]0)

    # TAG_List "servers"
    $writer.Write([byte]9)  # TAG_List
    $nameBytes = [System.Text.Encoding]::UTF8.GetBytes("servers")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$nameBytes.Length)))
    $writer.Write($nameBytes)
    $writer.Write([byte]10) # List type: TAG_Compound
    $writer.Write([int32]([System.Net.IPAddress]::HostToNetworkOrder([int32]1))) # List length: 1 server

    # Server entry TAG_Compound
    # TAG_String "ip"
    $writer.Write([byte]8)  # TAG_String
    $ipTagBytes = [System.Text.Encoding]::UTF8.GetBytes("ip")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$ipTagBytes.Length)))
    $writer.Write($ipTagBytes)
    $serverAddress = "$serverIp`:$serverPort"
    $serverAddressBytes = [System.Text.Encoding]::UTF8.GetBytes($serverAddress)
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$serverAddressBytes.Length)))
    $writer.Write($serverAddressBytes)

    # TAG_String "name"
    $writer.Write([byte]8)  # TAG_String
    $nameTagBytes = [System.Text.Encoding]::UTF8.GetBytes("name")
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$nameTagBytes.Length)))
    $writer.Write($nameTagBytes)
    $serverNameBytes = [System.Text.Encoding]::UTF8.GetBytes($serverName)
    $writer.Write([int16]([System.Net.IPAddress]::HostToNetworkOrder([int16]$serverNameBytes.Length)))
    $writer.Write($serverNameBytes)

    # TAG_End (end of server compound)
    $writer.Write([byte]0)

    # TAG_End (end of root compound)
    $writer.Write([byte]0)

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
    Add-Type -AssemblyName System.IO.Compression
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

# Download assets from PixiGeko repository
Write-Host "Downloading assets from PixiGeko repository..." -ForegroundColor Cyan
$assetsZipUrl = "https://github.com/PixiGeko/Minecraft-default-assets/archive/refs/heads/$version.zip"
$assetsZipPath = "$VARCD\assets_temp.zip"

try {
    downloadFile $assetsZipUrl $assetsZipPath
    Write-Host "Extracting assets..." -ForegroundColor Cyan

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    [System.IO.Compression.ZipFile]::ExtractToDirectory($assetsZipPath, "$VARCD\assets_temp")

    # Move assets to correct location
    $extractedPath = "$VARCD\assets_temp\Minecraft-default-assets-$version\assets"
    if (Test-Path $extractedPath) {
        Copy-Item -Path "$extractedPath\*" -Destination $assetsDir -Recurse -Force
    }

    # Cleanup
    Remove-Item $assetsZipPath -Force
    Remove-Item "$VARCD\assets_temp" -Recurse -Force
    Write-Host "Assets downloaded successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to download from PixiGeko, falling back to Mojang CDN..." -ForegroundColor Yellow

    # Fallback to individual asset downloads
    $assetsIndexDir = "$VARCD\indexes"
    $assetsObjectsDir = "$VARCD\objects"
    New-Item -ItemType Directory -Force -Path $assetsIndexDir, $assetsObjectsDir | Out-Null

    $assetIndex = Invoke-RestMethod $versionJson.assetIndex.url
    $assetIndex | ConvertTo-Json -Depth 100 | Out-File "$assetsIndexDir\$($versionJson.assetIndex.id).json"

    $assetDownloads = @()
    foreach ($asset in $assetIndex.objects.PSObject.Properties) {
        $hash = $asset.Value.hash
        $hashPrefix = $hash.Substring(0, 2)
        $assetDownloads += @{url="https://resources.download.minecraft.net/$hashPrefix/$hash"; path="$assetsObjectsDir\$hashPrefix\$hash"}
    }

    Download-Async $assetDownloads
}

# Create servers.dat
Write-Host "Creating servers.dat..." -ForegroundColor Cyan
Create-ServersDat "tunnel.rmccurdy.com" "55631" "RMcCurdy Server" "$minecraftDir\servers.dat"

# Build classpath
$classpath = "$versionsDir\$version.jar;" + ((Get-ChildItem -Path $librariesDir -Recurse -Filter *.jar).FullName -join ";")

# Create launch script in base directory
$launchScript = @"
@echo off
set /p PlayerName="Enter Minecraft Username: "
cd /d "$minecraftDir"
"$VARCD\jdk\bin\javaw.exe" -Xmx2G -Xms1G -cp "$classpath" net.minecraft.client.main.Main --version $version --accessToken 0 --userProperties {} --gameDir "$minecraftDir" --assetsDir "$assetsDir" --assetIndex $($versionJson.assetIndex.id) --username "%PlayerName%"
"@

$launchScript | Out-File "$VARCD\launch_$version.bat" -Encoding ASCII

Write-Host "`nComplete! Launch: $VARCD\launch_$version.bat" -ForegroundColor Green
Start-Process "$VARCD\launch_$version.bat" 
