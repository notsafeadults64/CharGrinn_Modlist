$apiKey = "YOURNEXUSAPIKEY"
$downloadPath = "YOURDOWNLOADSFOLDERPATH"
$primaryGame = "skyrimspecialedition" 
$secondaryGame = "skyrim" # Fallback for older mods
$mo2GameName = "SkyrimSE"

$logFile = Join-Path $downloadPath "failed_meta_queries.txt"
"--- Meta Build Log $(Get-Date) ---" | Out-File -FilePath $logFile

$headers = @{ "apikey" = $apiKey; "accept" = "application/json" }

Get-ChildItem -Path $downloadPath -Exclude "*.meta", "*.txt" | ForEach-Object {
    $file = $_
    $metaPath = "$($file.FullName).meta"
    if (Test-Path $metaPath) { return }

    if ($file.BaseName -match '-(?<modID>\d+)-(?<version>[\d\.-]+)-(?<fileID>\d+)$') {
        $modID = $Matches['modID']
        $fileID = $Matches['fileID']
        $version = $Matches['version']
        $foundGame = $null
        $modData = $null

        try {
            Write-Host "Processing Mod ${modID}..." -ForegroundColor Cyan
            
            # 1. Double-Tap Logic: Try Primary, then Secondary
            foreach ($game in @($primaryGame, $secondaryGame)) {
                try {
                    $modUrl = "https://api.nexusmods.com/v1/games/$game/mods/$modID.json"
                    $modData = Invoke-RestMethod -Uri $modUrl -Headers $headers
                    $foundGame = $game
                    break 
                } catch { continue }
            }

            if (-not $modData) { throw "Mod not found on $primaryGame or $secondaryGame" }

            # 2. Attempt Specific File Data (for the better name/description)
            $fileData = $null
            try {
                $fileUrl = "https://api.nexusmods.com/v1/games/$foundGame/mods/$modID/files/$fileID.json"
                $fileData = Invoke-RestMethod -Uri $fileUrl -Headers $headers
            } catch {
                Write-Host "  (!) FileID ${fileID} 404'd. Falling back to Mod info." -ForegroundColor Yellow
            }

            # 3. Construct the missing URL and data
            $nexusUrl = "https://www.nexusmods.com/$foundGame/mods/$modID"
            $finalName = if ($fileData) { $fileData.name } else { $modData.name }
            $rawDesc = if ($fileData -and $fileData.description) { $fileData.description } else { $modData.summary }
            $cleanDesc = $rawDesc -replace "`n", "\n" -replace "`r", "" -replace '"', '\"'

            # 4. Build .meta with URL field populated
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
userData=@Variant(\0\0\0\b\0\0\0\0)
installed=false
uninstalled=false
"@
            Set-Content -Path $metaPath -Value $metaContent -Encoding UTF8
            Write-Host "  [OK] Created .meta (URL: $foundGame) for: $finalName" -ForegroundColor Green
        }
        catch {
            $errorMessage = "FAILED: Mod ${modID} (File: $($file.Name)) - $($_.Exception.Message)"
            Write-Host "  [!!] $errorMessage" -ForegroundColor Red
            $errorMessage | Add-Content -Path $logFile
        }
        Start-Sleep -Milliseconds 350
    }
}
