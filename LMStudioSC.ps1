#requires -Version 3.0
# sort of portable install of LM Studio no Admin required !

param([switch]$VerboseDebug)

# -- Portability ---------------------------------------------------------------
Set-Location ($VARCD = Get-Location); $env:HOMEPATH = $env:USERPROFILE = $VARCD; $env:APPDATA = "$VARCD\AppData\Roaming"; $env:LOCALAPPDATA = "$VARCD\AppData\Local"; $env:TEMP = $env:TMP = "$VARCD\AppData\Local\Temp"; $env:JAVA_HOME = "$VARCD\jdk"; $env:Path = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:SystemRoot\System32\WindowsPowerShell\v1.0\;$VARCD\PortableGit\cmd;$VARCD\jdk\bin;$VARCD\node;$VARCD\python\tools\Scripts;$VARCD\python\tools;python\tools\Lib\site-packages"

# -- Model config --------------------------------------------------------------
$ModelPublisher = "Mindcraft-CE"
$ModelRepo      = "Andy-4.1-GGUF"
$ModelFile      = "andy-4.1.q4_k_m.gguf"
$ModelKey        = "$ModelPublisher/$ModelRepo/$ModelFile"
$HFUrl          = "https://huggingface.co/$ModelPublisher/$ModelRepo/resolve/main/$ModelFile"
$ApiPort        = 1234

# -- Download helper -----------------------------------------------------------
function downloadFile($url, $file) {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.AllowAutoRedirect = $true
    $req.Timeout = 600000            # 10 min connect timeout
    $req.ReadWriteTimeout = 600000   # 10 min read timeout
    $req.UserAgent = "Mozilla/5.0"
    $webRes = $req.GetResponse()
    $expectedLen = $webRes.ContentLength
    if ($expectedLen -gt 0) {
        Write-Host "  Expected size   : $([math]::Round($expectedLen / 1MB)) MB"
    }
    $res = $webRes.GetResponseStream()
    $fs  = [System.IO.FileStream]::new($file, 'Create')
    $buf = [byte[]]::new(256KB)
    $totalRead = [long]0
    $lastPct   = -1
    while (($c = $res.Read($buf, 0, $buf.Length)) -gt 0) {
        $fs.Write($buf, 0, $c)
        $totalRead += $c
        if ($expectedLen -gt 0) {
            $pct = [math]::Floor($totalRead * 100 / $expectedLen)
            if ($pct -ne $lastPct -and $pct % 10 -eq 0) {
                Write-Host "  Downloaded      : $pct% ($([math]::Round($totalRead / 1MB)) MB)" -ForegroundColor DarkGray
                $lastPct = $pct
            }
        }
    }
    $fs.Flush()
    $fs.Close()
    $res.Close()
    $webRes.Close()
    # Verify download completeness
    $actualLen = (Get-Item $file).Length
    Write-Host "  Actual size     : $([math]::Round($actualLen / 1MB)) MB"
    if ($expectedLen -gt 0 -and $actualLen -ne $expectedLen) {
        Write-Error "Download INCOMPLETE: expected $expectedLen bytes, got $actualLen bytes"
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        throw "Download verification failed for $file"
    }
}

# -- Port poller - hard max 20 sec --------------------------------------------
function Wait-Port {
    param([int]$Port, [int]$MaxSec = 20)
    $elapsed = 0
    while ($elapsed -lt $MaxSec) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        try {
            $tc = New-Object System.Net.Sockets.TcpClient
            $tc.Connect("127.0.0.1", $Port)
            if ($tc.Connected) {
                $tc.Close()
                return $true
            }
        } catch { }
        Write-Host "  ... $elapsed / $MaxSec sec" -ForegroundColor DarkGray
    }
    return $false
}

# -- Directories ---------------------------------------------------------------
$InstallerDir = "$VARCD\Installer"
$LMStudioDir  = "$VARCD\LMStudio"
$LMSDataDir   = "$VARCD\.lmstudio"
$LogDir       = "$VARCD\Logs"
$ModelDir     = "$LMSDataDir\models\$ModelPublisher\$ModelRepo"

foreach ($d in @($InstallerDir, $LMStudioDir, $LMSDataDir,
                 "$LMSDataDir\.internal", $LogDir, $ModelDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

Write-Host "=== LM Studio Portable Setup ===" -ForegroundColor Cyan
Write-Host "Working directory : $VARCD"

# -- Download installer --------------------------------------------------------
$InstallerUrl  = "https://installers.lmstudio.ai/win32/x64/0.4.5-2/LM-Studio-0.4.5-2-x64.exe"
$InstallerPath = "$InstallerDir\LM-Studio-0.4.5-2-x64.exe"

if (-not (Test-Path $InstallerPath)) {
    Write-Host "Downloading LM Studio 0.4.5-2..." -ForegroundColor Yellow
    downloadFile $InstallerUrl $InstallerPath
    Write-Host "Download complete." -ForegroundColor Green
} else {
    Write-Host "Installer already downloaded."
}

# -- Extract -------------------------------------------------------------------
$LMExe = "$LMStudioDir\LM Studio.exe"
if (-not (Test-Path $LMExe)) {
    Write-Host "Extracting LM Studio..." -ForegroundColor Yellow
    Start-Process $InstallerPath -ArgumentList "/S", "/D=`"$LMStudioDir`"" -Wait
    if (-not (Test-Path $LMExe)) {
        Write-Error "Extraction failed."
        exit 1
    }
    Write-Host "Extraction complete." -ForegroundColor Green
} else {
    Write-Host "LM Studio already extracted."
}

# -- Find lms.exe --------------------------------------------------------------
$LMSCli = Get-ChildItem -Path $LMStudioDir -Recurse -Filter "lms.exe" `
          -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $LMSCli) {
    Write-Error "lms.exe not found."
    exit 1
}
$LMSPath = $LMSCli.FullName
Write-Host "Found LMS CLI     : $LMSPath"

# -- Download model BEFORE launching LM Studio ---------------------------------
$ModelPath = "$ModelDir\$ModelFile"
if (-not (Test-Path $ModelPath)) {
    Write-Host "`nDownloading model : $ModelFile" -ForegroundColor Yellow
    Write-Host "Source            : $HFUrl"
    Write-Host "(~2 GB - please wait...)"
    downloadFile $HFUrl $ModelPath
    if (-not (Test-Path $ModelPath)) {
        Write-Error "Model download failed."
        exit 1
    }
    Write-Host "Model download OK : $ModelPath" -ForegroundColor Green
} else {
    Write-Host "`nModel on disk     : $ModelPath"
}

# -- Kill stale instances ------------------------------------------------------
Get-Process | Where-Object { $_.Name -match "^LM.Studio$|^lms$" } |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# -- Patch settings.json -------------------------------------------------------
$SettingsPath = "$LMSDataDir\settings.json"
try {
    if (Test-Path $SettingsPath) {
        $cfg = Get-Content $SettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
    } else {
        $cfg = [PSCustomObject]@{}
    }
} catch {
    $cfg = [PSCustomObject]@{}
}

$cfg | Add-Member -MemberType NoteProperty -Name "autoStartServer"          -Value $false                  -Force
$cfg | Add-Member -MemberType NoteProperty -Name "serverPort"               -Value $ApiPort                -Force
$cfg | Add-Member -MemberType NoteProperty -Name "serverCorsEnabled"        -Value $true                   -Force
$cfg | Add-Member -MemberType NoteProperty -Name "developerMode"            -Value $true                   -Force
$cfg | Add-Member -MemberType NoteProperty -Name "justInTimeModelLoading"   -Value $true                   -Force
$cfg | Add-Member -MemberType NoteProperty -Name "verboseLogging"           -Value $VerboseDebug.IsPresent -Force

$cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsPath -Force
Write-Host "Settings patched  : $SettingsPath"

# -- Restore backend preferences to CUDA12 ------------------------------------
$BackendPrefsPath = "$LMSDataDir\.internal\backend-preferences-v1.json"
$backendPrefs = @(
    @{
        model_format = "gguf"
        name         = "llama.cpp-win-x86_64-nvidia-cuda12-avx2"
        version      = "2.4.0"
    }
) | ConvertTo-Json -Depth 4
$backendPrefs | Set-Content -Path $BackendPrefsPath -Force
Write-Host "Backend prefs     : CUDA12 restored"

# -- Define Pathing -----------------------------------------------------------
$PerModelDir = "$LMSDataDir\.internal\user-concrete-model-default-config\$ModelPublisher\$ModelRepo"
New-Item -ItemType Directory -Force -Path $PerModelDir | Out-Null
$PerModelPath = "$PerModelDir\$ModelFile.json"

# hates \r\n an inside jinja is a PINA to parse use GUI to get the .json file to write out ...

$jsonContent = @'
{
  "preset": "",
  "operation": {
    "fields": [
      {
        "key": "llm.prediction.promptTemplate",
        "value": {
          "type": "jinja",
          "jinjaPromptTemplate": {
            "template": "{%- set image_count = namespace(value=0) %}\n{%- set video_count = namespace(value=0) %}\n{%- macro render_content(content, do_vision_count) %}\n    {%- if content is string %}\n        {{- content }}\n    {%- else %}\n        {%- for item in content %}\n            {%- if 'image' in item or 'image_url' in item or item.type == 'image' %}\n                {%- if do_vision_count %}\n                    {%- set image_count.value = image_count.value + 1 %}\n                {%- endif %}\n                {%- if add_vision_id %}Picture {{ image_count.value }}: {% endif -%}\n                <|vision_start|><|image_pad|><|vision_end|>\n            {%- elif 'video' in item or item.type == 'video' %}\n                {%- if do_vision_count %}\n                    {%- set video_count.value = video_count.value + 1 %}\n                {%- endif %}\n                {%- if add_vision_id %}Video {{ video_count.value }}: {% endif -%}\n                <|vision_start|><|video_pad|><|vision_end|>\n            {%- elif 'text' in item %}\n                {{- item.text }}\n            {%- endif %}\n        {%- endfor %}\n    {%- endif %}\n{%- endmacro %}\n{%- if tools %}\n    {{- '<|im_start|>system\\n' }}\n    {%- if messages[0].role == 'system' %}\n        {{- render_content(messages[0].content, false) + '\\n\\n' }}\n    {%- endif %}\n    {{- \"# Tools\\n\\nYou may call one or more functions to assist with the user query.\\n\\nYou are provided with function signatures within <tools></tools> XML tags:\\n<tools>\" }}\n    {%- for tool in tools %}\n        {{- \"\\n\" }}\n        {{- tool | tojson }}\n    {%- endfor %}\n    {{- \"\\n</tools>\\n\\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\\n<tool_call>\\n{\\\"name\\\": <function-name>, \\\"arguments\\\": <args-json-object>}\\n</tool_call><|im_end|>\\n\" }}\n{%- else %}\n    {%- if messages[0].role == 'system' %}\n        {{- '<|im_start|>system\\n' + render_content(messages[0].content, false) + '<|im_end|>\\n' }}\n    {%- endif %}\n{%- endif %}\n{%- set ns = namespace(multi_step_tool=true, last_query_index=messages|length - 1) %}\n{%- for message in messages[::-1] %}\n    {%- set index = (messages|length - 1) - loop.index0 %}\n    {%- if ns.multi_step_tool and message.role == \"user\" %}\n        {%- set content = render_content(message.content, false) %}\n        {%- if not(content.startswith('<tool_response>') and content.endswith('</tool_response>')) %}\n            {%- set ns.multi_step_tool = false %}\n            {%- set ns.last_query_index = index %}\n        {%- endif %}\n    {%- endif %}\n{%- endfor %}\n{%- for message in messages %}\n    {%- set content = render_content(message.content, True) %}\n    {%- if (message.role == \"user\") or (message.role == \"system\" and not loop.first) %}\n        {{- '<|im_start|>' + message.role + '\\n' + content + '<|im_end|>' + '\\n' }}\n    {%- elif message.role == \"assistant\" %}\n        {%- set reasoning_content = '' %}\n        {%- if message.reasoning_content is string %}\n            {%- set reasoning_content = message.reasoning_content %}\n        {%- else %}\n            {%- if '</think>' in content %}\n                {%- set reasoning_content = content.split('</think>')[0].rstrip('\\n').split('<think>')[-1].lstrip('\\n') %}\n                {%- set content = content.split('</think>')[-1].lstrip('\\n') %}\n            {%- endif %}\n        {%- endif %}\n        {%- if loop.index0 > ns.last_query_index %}\n            {%- if loop.last or (not loop.last and reasoning_content) %}\n                {{- '<|im_start|>' + message.role + '\\n<think>\\n' + reasoning_content.strip('\\n') + '\\n</think>\\n\\n' + content.lstrip('\\n') }}\n            {%- else %}\n                {{- '<|im_start|>' + message.role + '\\n' + content }}\n            {%- endif %}\n        {%- else %}\n            {{- '<|im_start|>' + message.role + '\\n' + content }}\n        {%- endif %}\n        {%- if message.tool_calls %}\n            {%- for tool_call in message.tool_calls %}\n                {%- if (loop.first and content) or (not loop.first) %}\n                    {{- '\\n' }}\n                {%- endif %}\n                {%- if tool_call.function %}\n                    {%- set tool_call = tool_call.function %}\n                {%- endif %}\n                {{- '<tool_call>\\n{\"name\": \"' }}\n                {{- tool_call.name }}\n                {{- '\", \"arguments\": ' }}\n                {%- if tool_call.arguments is string %}\n                    {{- tool_call.arguments }}\n                {%- else %}\n                    {{- tool_call.arguments | tojson }}\n                {%- endif %}\n                {{- '}\\n</tool_call>' }}\n            {%- endfor %}\n        {%- endif %}\n        {{- '<|im_end|>\\n' }}\n    {%- elif message.role == \"tool\" %}\n        {%- if loop.first or (messages[loop.index0 - 1].role != \"tool\") %}\n            {{- '<|im_start|>user' }}\n        {%- endif %}\n        {{- '\\n<tool_response>\\n' }}\n        {{- content }}\n        {{- '\\n</tool_response>' }}\n        {%- if loop.last or (messages[loop.index0 + 1].role != \"tool\") %}\n            {{- '<|im_end|>\\n' }}\n        {%- endif %}\n    {%- endif %}\n{%- endfor %}\n{%- if add_generation_prompt %}\n    {{- '<|im_start|>assistant\\n<think>\\n' }}\n{%- endif %}"
          },
          "stopStrings": []
        }
      }
    ]
  },
  "load": {
    "fields": [
      {
        "key": "llm.load.contextLength",
        "value": 32768
      }
    ]
  }
}
'@

# Replace Windows CRLF with Unix LF
$unixContent = $jsonContent -replace "`r`n", "`n"

# Write using [System.IO.File] to prevent PowerShell from re-adding CRLF
[System.IO.File]::WriteAllText("$PerModelPath", $unixContent)

 
Write-Host "Success: Template written with literal formatting to $PerModelPath" -ForegroundColor Green


# -- Launch LM Studio ----------------------------------------------------------
Write-Host "`nLaunching LM Studio..." -ForegroundColor Cyan
if ($VerboseDebug) {
    Write-Host "Verbose logging   : ON" -ForegroundColor Magenta
}
# -ArgumentList "--minimized"  -PassThru -WindowStyle Hidden
$LMSProc = Start-Process -FilePath $LMExe -ArgumentList "--minimized" -PassThru -WindowStyle Hidden
Write-Host "LM Studio PID     : $($LMSProc.Id)"

Write-Host "Startup pause (5 sec)..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

if ($LMSProc.HasExited) {
    Write-Error "LM Studio exited immediately - check the install."
    exit 1
}

# -- Start API server on port 1234 ---------------------------------------------
Write-Host "`nStarting API server on port $ApiPort (max 20 sec)..." -ForegroundColor Cyan

$srvArgs = [System.Collections.Generic.List[string]]::new()
$srvArgs.Add("server")
$srvArgs.Add("start")
$srvArgs.Add("--port")
$srvArgs.Add("$ApiPort")
$srvArgs.Add("--cors")

if ($VerboseDebug) {
    $srvArgs.Add("--verbose")
    $SrvProc = Start-Process -FilePath $LMSPath `
                             -ArgumentList $srvArgs `
                             -PassThru -WindowStyle Hidden `
                             -RedirectStandardOutput "$LogDir\lms-server.log" `
                             -RedirectStandardError  "$LogDir\lms-server-err.log"
} else {
    $SrvProc = Start-Process -FilePath $LMSPath `
                             -ArgumentList $srvArgs `
                             -PassThru -WindowStyle Hidden
}

Write-Host "lms server PID    : $($SrvProc.Id)"

if (-not (Wait-Port -Port $ApiPort -MaxSec 20)) {
    Write-Error "Port $ApiPort not open after 20 sec."
    if ($VerboseDebug) {
        if (Test-Path "$LogDir\lms-server-err.log") {
            Write-Host "`nServer error log:" -ForegroundColor Red
            Get-Content "$LogDir\lms-server-err.log" | Select-Object -Last 15
        }
    }
    exit 1
}

Write-Host "API server UP     : http://127.0.0.1:$ApiPort" -ForegroundColor Green

# -- Discover model key via lms ls ---------------------------------------------
Write-Host "`nDiscovering model key..." -ForegroundColor Cyan
$lmsLsOut = & $LMSPath ls 2>&1 | Out-String
Write-Host $lmsLsOut -ForegroundColor DarkGray

# Parse the short key from lms ls output (match lines containing our model file stem)
$ModelStem = [System.IO.Path]::GetFileNameWithoutExtension($ModelFile) -replace '\.q\d.*$',''
$ModelLoadKey = $null
foreach ($line in ($lmsLsOut -split "`n")) {
    $trimmed = $line.Trim()
    if ($trimmed -match $ModelStem -and $trimmed -notmatch '^\s*$' -and $trimmed -notmatch '^[-=]') {
        # Extract the first token (the model key) from the line
        if ($trimmed -match '^(\S+)') {
            $ModelLoadKey = $Matches[1]
            break
        }
    }
}

if (-not $ModelLoadKey) {
    Write-Warning "Could not auto-detect model key from lms ls. Falling back to file stem."
    $ModelLoadKey = ($ModelFile -replace '\.gguf$','').ToLower()
}
Write-Host "Model load key    : $ModelLoadKey" -ForegroundColor Green

# -- Load model (non-interactive via JIT) --------------------------------------
# JIT loading is enabled in settings.json. The first API request will trigger
# the model load automatically. No interactive lms load needed.
Write-Host "`nJIT model loading enabled - first API call will load the model." -ForegroundColor Cyan
Write-Host "Sending API test (may take a moment for initial model load)..." -ForegroundColor Cyan

# -- API test ------------------------------------------------------------------
$body = @{
    model    = $ModelLoadKey
    messages = @(
        @{ role = "system"; content = "You are a helpful assistant." }
        @{ role = "user";   content = "Reply with exactly: API test successful" }
    )
    temperature = 0.1
    max_tokens  = 15
    stream      = $false
} | ConvertTo-Json -Depth 4

try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/v1/chat/completions" `
                              -Method POST -ContentType "application/json" `
                              -Body $body -TimeoutSec 120
    $text = $resp.choices[0].message.content
    Write-Host "Response  : '$text'"
    if ($text -match "successful") {
        Write-Host "[PASS] API working correctly!" -ForegroundColor Green
    } else {
        Write-Host "[CHECK] Unexpected content in response." -ForegroundColor Yellow
    }
    Write-Host "Tokens    : $($resp.usage.total_tokens)" -ForegroundColor DarkGray
} catch {
    Write-Error "API test failed: $($_.Exception.Message)"
}

# -- Stop helper ---------------------------------------------------------------
$stopScript = 'Get-Process | Where-Object { $_.Name -match "^LM.Studio$|^lms$" } | Stop-Process -Force -ErrorAction SilentlyContinue' + "`n" + 'Write-Host "LM Studio stopped."'
$stopScript | Set-Content -Path "$VARCD\Stop-LMStudio.ps1" -Force

# -- Summary -------------------------------------------------------------------
Write-Host "`n=== Complete ===" -ForegroundColor Green
Write-Host "Endpoint  : http://127.0.0.1:$ApiPort/v1/chat/completions"
Write-Host "Model     : $ModelLoadKey"
Write-Host "LM PID    : $($LMSProc.Id)"
Write-Host "Stop      : .\Stop-LMStudio.ps1"

if ($VerboseDebug) {
    Write-Host "`nStreaming server logs (Ctrl+C to exit):" -ForegroundColor Magenta
    & $LMSPath log stream
}
