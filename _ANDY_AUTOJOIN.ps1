param(
    [Parameter(Mandatory=$false)]
    [string]$Headless
)

$VerNum = '_ANDY_AUTOJOIN 1.0a'
$host.ui.RawUI.WindowTitle = $VerNum 

Set-Location ($VARCD = "C:\backup\MSC1" ); $env:HOMEPATH = $env:USERPROFILE = $VARCD; $env:APPDATA = "$VARCD\AppData\Roaming"; $env:LOCALAPPDATA = "$VARCD\AppData\Local"; $env:TEMP = $env:TMP = "$VARCD\AppData\Local\Temp"; $env:JAVA_HOME = "$VARCD\jdk"; $env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\;$VARCD\PortableGit\cmd;$VARCD\jdk\bin;$VARCD\node;$VARCD\python\tools\Scripts;$VARCD\python\tools;python\tools\Lib\site-packages"

function Write-Message  {
    [CmdletBinding()]
    param (
        [string]$Type,
        [string]$Message
    )

    if (($TYPE) -eq ("INFO")) { $Tag = "INFO"; $Color = "Green"}
    if (($TYPE) -eq ("WARNING")) { $Tag = "WARNING"; $Color = "Yellow"}
    if (($TYPE) -eq ("ERROR")) { $Tag = "ERROR"; $Color = "Red"}
    Write-Host (Get-Date -UFormat "%m/%d:%T")$($Tag)$($Message) -ForegroundColor $Color  
}

function mindcraftStart {
    Set-Location -Path "$VARCD\mindcraft\mindcraft-ce\" -ErrorAction SilentlyContinue |Out-Null
    Write-Message "Removing Andy memory folder $VARCD\mindcraft\mindcraft-ce\bots\Andy" -Type "WARNING"
    Remove-Item -Path "$VARCD\mindcraft\mindcraft-ce\bots\Andy" -Force -ErrorAction SilentlyContinue -Confirm:$false -Recurse |Out-Null
    Write-Message "Starting Mindcraft" -Type "INFO"
    Start-Process -FilePath "$VARCD\node\node.exe" -WorkingDirectory ".\" -ArgumentList " main.js "
}

$serverHost = "192.168.1.151"
$serverPort = 25565
$rconPort = 25575
$rconPassword = "YOURPASSWORD"

function Send-RconCommand {
    param(
        [string]$ServerHost,
        [int]$Port,
        [string]$Password,
        [string]$Command
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient($ServerHost, $Port)
        $stream = $client.GetStream()

        $authId = 1
        $authPacket = Build-RconPacket -RequestId $authId -Type 3 -Body $Password
        $stream.Write($authPacket, 0, $authPacket.Length)

        $authResponse = Read-RconPacket -Stream $stream
        if ($authResponse.RequestId -eq -1) {
            throw "RCON authentication failed"
        }

        $cmdId = 2
        $cmdPacket = Build-RconPacket -RequestId $cmdId -Type 2 -Body $Command
        $stream.Write($cmdPacket, 0, $cmdPacket.Length)

        $response = Read-RconPacket -Stream $stream

        $client.Close()
        return $response.Body
    }
    catch {
        Write-Error "RCON Error: $_"
        return $null
    }
}

function Build-RconPacket {
    param([int]$RequestId, [int]$Type, [string]$Body)

    $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $length = $bodyBytes.Length + 10

    $packet = New-Object byte[] ($length + 4)
    [BitConverter]::GetBytes($length).CopyTo($packet, 0)
    [BitConverter]::GetBytes($RequestId).CopyTo($packet, 4)
    [BitConverter]::GetBytes($Type).CopyTo($packet, 8)
    $bodyBytes.CopyTo($packet, 12)

    return $packet
}

function Read-RconPacket {
    param([System.Net.Sockets.NetworkStream]$Stream)

    $lengthBytes = New-Object byte[] 4
    $Stream.Read($lengthBytes, 0, 4) | Out-Null
    $length = [BitConverter]::ToInt32($lengthBytes, 0)

    $packetBytes = New-Object byte[] $length
    $Stream.Read($packetBytes, 0, $length) | Out-Null

    $requestId = [BitConverter]::ToInt32($packetBytes, 0)
    $type = [BitConverter]::ToInt32($packetBytes, 4)
    $body = [System.Text.Encoding]::ASCII.GetString($packetBytes, 8, $length - 10)

    return @{
        RequestId = $requestId
        Type = $type
        Body = $body
    }
}

function Get-PlayerPosition {
    param([string]$PlayerName)

    $posData = Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "data get entity $PlayerName Pos"

    if ($posData -match '\[(-?\d+\.?\d*)d, (-?\d+\.?\d*)d, (-?\d+\.?\d*)d\]') {
        return @{
            X = [double]$matches[1]
            Y = [double]$matches[2]
            Z = [double]$matches[3]
        }
    }
    return $null
}

function Get-Distance {
    param($Pos1, $Pos2)

    $dx = $Pos1.X - $Pos2.X
    $dy = $Pos1.Y - $Pos2.Y
    $dz = $Pos1.Z - $Pos2.Z

    return [Math]::Sqrt($dx*$dx + $dy*$dy + $dz*$dz)
}

function Check-AndTeleportIfNeeded {
    param([array]$NonAndyPlayers)

    Write-Host "`n=== CHECKING DISTANCES ===" -ForegroundColor Cyan

    $andyPos = Get-PlayerPosition -PlayerName "andy"

    if ($andyPos) {
        Write-Host "Andy position: X=$($andyPos.X), Y=$($andyPos.Y), Z=$($andyPos.Z)"

        $closestPlayer = $null
        $closestDistance = [double]::MaxValue
        $withinRange = $false

        foreach ($player in $NonAndyPlayers) {
            $playerPos = Get-PlayerPosition -PlayerName $player

            if ($playerPos) {
                $distance = Get-Distance -Pos1 $andyPos -Pos2 $playerPos
                Write-Host "Distance to $player : $([Math]::Round($distance, 2)) blocks"

                if ($distance -le 50) {
                    $withinRange = $true
                }

                if ($distance -lt $closestDistance) {
                    $closestDistance = $distance
                    $closestPlayer = $player
                }
            }
        }

        if (-not $withinRange -and $closestPlayer) {
            Write-Host "`n=== TELEPORTING ===" -ForegroundColor Green
            Write-Host "Andy is NOT within 50 blocks of any player. Teleporting to closest player: [$closestPlayer] (Distance: $([Math]::Round($closestDistance, 2)) blocks)"

            $tpCommand = "tp andy $closestPlayer"
            Write-Host "TP command: [$tpCommand]"

            $tpResult = Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command $tpCommand
            Write-Host "Teleport result: [$tpResult]" -ForegroundColor Green
			
			# Clean after teleport
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:cobblestone"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:rotten_flesh"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:andesite"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:diorite"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:dirt"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:granite"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:gravel"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:sand"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:stone"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:deepslate"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:tuff"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:calcite"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:netherrack"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:soul_sand"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:soul_soil"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:basalt"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:blackstone"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:spider_eye"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:bone"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:string"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:wheat_seeds"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:beetroot_seeds"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:pumpkin_seeds"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:melon_seeds"
				Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "/clear andy minecraft:poisonous_potato"

			
        }
        elseif ($withinRange) {
            Write-Host "`nAndy is within 50 blocks of a player. No teleport needed." -ForegroundColor Yellow
        }
        else {
            Write-Host "`nNo valid players to teleport to." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Could not get Andy's position!" -ForegroundColor Red
    }
}

Write-Host "=== INITIAL PLAYER CHECK ===" -ForegroundColor Cyan

$playerList = Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "list"

if ($playerList) {
    Write-Host "Initial server response: [$playerList]"

    if ($playerList -match "online:\s*([^\r\n]+)") {
        $playerString = $matches[1].Trim()
        $players = @($playerString -split ",\s*" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^\d+$' })

        Write-Host "Initial players: [$($players -join '], [')]"

        $andyIsOnline = $players -contains "andy"
        $nonAndyPlayers = @($players | Where-Object { $_ -ne "andy" })

        Write-Host "Andy online initially: $andyIsOnline"
        Write-Host "Non-andy players: [$($nonAndyPlayers -join '], [')]"

        if ($nonAndyPlayers.Count -gt 0 -and $andyIsOnline) {
            Write-Host "`n=== ANDY ALREADY ONLINE ===" -ForegroundColor Yellow
            Check-AndTeleportIfNeeded -NonAndyPlayers $nonAndyPlayers
        }
        elseif ($nonAndyPlayers.Count -gt 0 -and -not $andyIsOnline) {
            Write-Host "`n=== STARTING BOT ===" -ForegroundColor Green
            Stop-process -name node -Force -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 5
            mindcraftStart

            Write-Host "Waiting 10 seconds for andy to join..."
            Start-Sleep -Seconds 10
			
			Write-Host "`n=== CLEARING ANDY INVENTORY ===" -ForegroundColor Yellow
					# clear
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/clear andy'
					
					
					# Aasic stuff he needs ..
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy torch 64'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:golden_apple 64'
					
					# Armor
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_helmet[minecraft:enchantments={"minecraft:protection":4,"minecraft:unbreaking":3,"minecraft:mending":1,"minecraft:respiration":3,"minecraft:aqua_affinity":1}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_chestplate[minecraft:enchantments={"minecraft:protection":4,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_leggings[minecraft:enchantments={"minecraft:protection":4,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_boots[minecraft:enchantments={"minecraft:protection":4,"minecraft:unbreaking":3,"minecraft:mending":1,"minecraft:feather_falling":4,"minecraft:depth_strider":3}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:shield[minecraft:enchantments={"minecraft:unbreaking":3,"minecraft:mending":1}]'

					# Equip armor
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy armor.head with minecraft:diamond_helmet'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy armor.chest with minecraft:diamond_chestplate'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy armor.legs with minecraft:diamond_leggings'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy armor.feet with minecraft:diamond_boots'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy weapon.mainhand with minecraft:diamond_sword'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/item replace entity Andy weapon.offhand with minecraft:shield'
					
					# Wepons
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_sword[minecraft:enchantments={"minecraft:sharpness":5,"minecraft:unbreaking":3,"minecraft:mending":1,"minecraft:looting":3,"minecraft:sweeping_edge":3}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_axe[minecraft:enchantments={"minecraft:sharpness":5,"minecraft:efficiency":5,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:bow[minecraft:enchantments={"minecraft:power":5,"minecraft:unbreaking":3,"minecraft:flame":1,"minecraft:infinity":1,"minecraft:punch":2}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:crossbow[minecraft:enchantments={"minecraft:quick_charge":3,"minecraft:multishot":1,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:spectral_arrow 64'

					# tools
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_hoe[minecraft:enchantments={"minecraft:efficiency":5,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:shears[minecraft:enchantments={"minecraft:efficiency":5,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:fishing_rod[minecraft:enchantments={"minecraft:luck_of_the_sea":3,"minecraft:lure":3,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_pickaxe[minecraft:enchantments={"minecraft:efficiency":5,"minecraft:fortune":3,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					#Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command '/give andy minecraft:diamond_shovel[minecraft:enchantments={"minecraft:efficiency":5,"minecraft:fortune":3,"minecraft:unbreaking":3,"minecraft:mending":1}]'
					
			
            Write-Host "`n=== REFRESHING PLAYER LIST ===" -ForegroundColor Yellow
            $playerList2 = Send-RconCommand -ServerHost $serverHost -Port $rconPort -Password $rconPassword -Command "list"

            Write-Host "Updated server response: [$playerList2]"

            if ($playerList2 -match "online:\s*([^\r\n]+)") {
                $playerString2 = $matches[1].Trim()
                Write-Host "Updated player string: [$playerString2]"

                $players2 = @($playerString2 -split ",\s*" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^\d+$' })

                Write-Host "Updated players array (Count: $($players2.Count)):"
                for ($i = 0; $i -lt $players2.Count; $i++) {
                    Write-Host "  Player[$i]: [$($players2[$i])] (Length: $($players2[$i].Length))"
                }

                $nonAndyPlayers2 = @($players2 | Where-Object { $_ -ne "andy" })

                Write-Host "`nUpdated non-andy players (Count: $($nonAndyPlayers2.Count)):"
                for ($i = 0; $i -lt $nonAndyPlayers2.Count; $i++) {
                    Write-Host "  NonAndy[$i]: [$($nonAndyPlayers2[$i])] (Length: $($nonAndyPlayers2[$i].Length))"
                }

                if ($nonAndyPlayers2.Count -gt 0) {
                    Check-AndTeleportIfNeeded -NonAndyPlayers $nonAndyPlayers2
                }
                else {
                    Write-Host "No non-andy players found after refresh!" -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "`nOnly andy (or no players) online. No action needed." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "No players online or unable to parse player list." -ForegroundColor Red
    }
}
else {
    Write-Error "Failed to connect to server or retrieve player list."
}
