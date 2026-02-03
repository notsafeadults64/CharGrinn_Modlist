$apiKey = "YOURAPIKEY"
$downloadPath = "G:\Downloads"
$gameName = "skyrimspecialedition" # Use 'skyrim' for LE, 'fallout4' for FO4
$mo2GameName = "SkyrimSE"

$headers = @{ "apikey" = $apiKey; "accept" = "application/json" }

Get-ChildItem -Path $downloadPath -Exclude "*.meta" | ForEach-Object {
    $file = $_
    $metaPath = "$($file.FullName).meta"
    if (Test-Path $metaPath) { return }

    # Regex tailored for standard Nexus: Name-ModID-Version-FileID.ext
    if ($file.BaseName -match '-(?<modID>\d+)-(?<version>[\d\.-]+)-(?<fileID>\d+)$') {
        $modID = $Matches['modID']
        $fileID = $Matches['fileID']
        $version = $Matches['version']

        try {
            Write-Host "Processing Mod ${modID}..." -ForegroundColor Cyan
            
            # 1. Attempt to get Mod Data (This is usually more stable than File data)
            $modUrl = "https://api.nexusmods.com/v1/games/$gameName/mods/$modID.json"
            $modData = Invoke-RestMethod -Uri $modUrl -Headers $headers

            # 2. Attempt to get Specific File Data
            $fileData = $null
            try {
                $fileUrl = "https://api.nexusmods.com/v1/games/$gameName/mods/$modID/files/$fileID.json"
                $fileData = Invoke-RestMethod -Uri $fileUrl -Headers $headers
            } catch {
                Write-Host "  (!) Specific FileID ${fileID} not found. Falling back to Mod info." -ForegroundColor Yellow
            }

            # 3. Consolidate Data
            $finalName = if ($fileData) { $fileData.name } else { $modData.name }
            $rawDesc = if ($fileData -and $fileData.description) { $fileData.description } else { $modData.summary }
            $cleanDesc = $rawDesc -replace "`n", "\n" -replace "`r", "" -replace '"', '\"'

            # 4. Build .meta
            $metaContent = @"
[General]
gameName=$mo2GameName
modID=$modID
fileID=$fileID
url=
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
            Write-Host "  [OK] Created .meta for: $finalName" -ForegroundColor Green
        }
        catch {
            Write-Host "  [ERROR] Mod ${modID} totally not found on ${gameName}. Check gameName variable." -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 300
    }
}