$apiKey = "YOURNEXUSAPIKEY"
$downloadPath = "YOURDOWNLOADSFOLDERPATH"
$primaryGame = "skyrimspecialedition" 
$secondaryGame = "skyrim" # Fallback for older mods
$mo2GameName = "SkyrimSE"

$primaryGame = "skyrimspecialedition" 
$secondaryGame = "skyrim" # Fallback for older mods
$mo2GameName = "SkyrimSE"

$headers = @{ "apikey" = $apiKey; "accept" = "application/json" }

Get-ChildItem -Path $downloadPath -Exclude "*.meta", "*.txt" | ForEach-Object {
    $file = $_
    $metaPath = "$($file.FullName).meta"

    # 1. SKIP IF META EXISTS
    if (Test-Path $metaPath) { return }

    # 2. IMPROVED REGEX: Handles "Name-ModID-Version-FileID"
    if ($file.BaseName -match '-(?<modID>\d+)-(?<version>.*)-(?<fileID>\d+)$') {
        $modID = $Matches['modID']
        $fileID = $Matches['fileID']
        $version = $Matches['version']

        # 3. SAFETY SWAP: If the first ID is huge (10 digits), it's a FileID timestamp
        if ($modID.Length -ge 9) {
            $temp = $modID
            $modID = $fileID
            $fileID = $temp
        }

        try {
            Write-Host "Targeting Mod: ${modID} | File: ${fileID}" -ForegroundColor Cyan
            
            # 4. DOMAIN CHECK (SSE vs Oldrim)
            $foundGame = $null
            $modData = $null
            foreach ($game in @($primaryGame, $secondaryGame)) {
                try {
                    $modUrl = "https://api.nexusmods.com/v1/games/$game/mods/$modID.json"
                    $modData = Invoke-RestMethod -Uri $modUrl -Headers $headers
                    $foundGame = $game
                    break 
                } catch { continue }
            }

            if (-not $modData) { throw "Mod ID ${modID} not found on Nexus." }

            # 5. FILE DATA QUERY
            $fileData = $null
            try {
                $fileUrl = "https://api.nexusmods.com/v1/games/$foundGame/mods/$modID/files/$fileID.json"
                $fileData = Invoke-RestMethod -Uri $fileUrl -Headers $headers
            } catch {
                Write-Host "  (!) FileID ${fileID} 404'd. Falling back to Mod info." -ForegroundColor Yellow
            }

            # 6. CONSTRUCT META CONTENT
            $nexusUrl = "https://www.nexusmods.com/$foundGame/mods/$modID"
            $finalName = if ($fileData) { $fileData.name } else { $modData.name }
            $rawDesc = if ($fileData -and $fileData.description) { $fileData.description } else { $modData.summary }
            $cleanDesc = $rawDesc -replace "`n", "\n" -replace "`r", "" -replace '"', '\"'

            $metaContent = @"
[General]
gameName=$mo2GameName
modID=$modID
fileID=$fileID
url=$nexusUrl
name=$finalName
description="$cleanDesc"
modName=$($modData.name)
version=$version
newestVersion=$($modData.version)
fileTime=@DateTime(\0\0\0\x10\0\x80\0\0\0\0\0\0\0\xff\xff\xff\xff\0)
fileCategory=1
category=$($modData.category_id)
repository=Nexus
installed=false
"@
            Set-Content -Path $metaPath -Value $metaContent -Encoding UTF8
            Write-Host "  [SUCCESS] Created meta for: $finalName" -ForegroundColor Green
        }
        catch {
            # FIX: Using ${modID} to avoid the drive-reference error
            Write-Host "  [SKIP] API Error for Mod ${modID}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [IGNORE] Could not find ID pattern in: $($file.Name)" -ForegroundColor DarkGray
    }
    
    # Respect API Rate Limits
    Start-Sleep -Milliseconds 350
}
