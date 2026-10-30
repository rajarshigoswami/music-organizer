<#
.SYNOPSIS
    Organizes a music collection into a clean, HiBy R1 / Sonix OS optimized layout.

.DESCRIPTION
    Sonix OS operates with a 480x800 display, supports both Library (Tags) and Browse
    (Folder) modes, and employs folder-based album grouping ('album_key' and 'Join albums').
    
    This script organizes music into three clear sections:
      1. Artists/     - Studio albums by band / artist (e.g. Linkin Park, Lucky Ali, KK)
      2. Soundtracks/ - Film soundtracks & multi-artist OSTs (e.g. 36 China Town, Sur, Jannat)
      3. Singles/     - Non-album tracks & individual singles grouped by primary artist
    
    HiBy R1 Display & Library Optimizations:
      - Strips long suffix clutter like "(Original Motion Picture Soundtrack)" to fit the 480px screen
      - Merges fragmented soundtrack tracks into unified album folders
      - Keeps files per folder well under Sonix's 64-file FOLDERORDER_TAG_READS limit
      - Formats filenames with track numbers for clean natural sorting in folder browsing
      - Preserves original files untouched (Mode = 'Copy')

.PARAMETER SourceDir
    Source music folder. Default: "E:\music"

.PARAMETER DestinationDir
    Target organized music folder. Default: "E:\Music_Organized"

.PARAMETER Mode
    "Copy" (default) or "Move".

.PARAMETER DryRun
    If specified, shows what actions would be taken without copying or modifying files.

.EXAMPLE
    .\Organize-MusicForSonix.ps1 -DryRun
    .\Organize-MusicForSonix.ps1 -DestinationDir "E:\Music_Organized"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$SourceDir = "E:\music",

    [Parameter(Position = 1)]
    [string]$DestinationDir = "E:\Music",

    [ValidateSet("Copy", "Move")]
    [string]$Mode = "Copy",

    [switch]$DryRun
)

# Helper for long Windows path support
function Get-ExtendedPath([string]$p) {
    $full = [System.IO.Path]::GetFullPath($p)
    if ($full.StartsWith("\\?\")) { return $full }
    if ($full.StartsWith("\\")) { return "\\?\UNC\" + $full.Substring(2) }
    return "\\?\" + $full
}

function Sanitize-PathString([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return "Unknown" }
    $clean = $name -replace '[\/:*?"<>|]', '_'
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim()
}

function Clean-AlbumTitle([string]$album) {
    if ([string]::IsNullOrWhiteSpace($album)) { return $null }
    $a = $album.Trim()
    
    # Strip long OST markers that cause small-screen clutter on HiBy R1
    $a = $a -replace '(?i)\s*[\(\[]Original Motion Picture Soundtrack[\)\]]', ''
    $a = $a -replace '(?i)\s*[\(\[]Deluxe Edition[\)\]]', ''
    $a = $a -replace '(?i)\s*[\(\[]Bonus Edition[\)\]]', ''
    $a = $a -replace '(?i)\s*[\(\[]From "[^"]+"[\)\]]', ''
    $a = $a -replace '(?i)\s*[\(\[]From [^()]+[\)\]]', ''
    $a = $a -replace '\s+', ' '
    return (Sanitize-PathString $a)
}

function Clean-ArtistName([string]$artist) {
    if ([string]::IsNullOrWhiteSpace($artist)) { return "Unknown Artist" }
    
    # Strip repeated artist entries (common in Vorbis comments: "Artist; Artist; Artist")
    $first = ($artist -split ';')[0].Trim()
    
    # If comma-separated multiple artists, take primary or clean up
    $clean = $first -replace '\s+', ' '
    return (Sanitize-PathString $clean)
}

function Get-PrimaryArtist([string]$artist) {
    $clean = Clean-ArtistName $artist
    # If multiple artists like "Arijit Singh, Irshad Kamil", take the primary singer
    if ($clean -match '^([^,;&]+)') {
        return $matches[1].Trim()
    }
    return $clean
}

# Known Studio Album Artists and their albums
$ArtistAlbumCatalog = @{
    "Linkin Park" = @("From Zero", "Hybrid Theory", "Meteora", "Minutes to Midnight", "Reanimation", "Living Things", "The Hunting Party", "One More Light")
    "Lucky Ali"   = @("Sunoh", "Sifar", "Aks", "Kabhi Aisa Lagta Hai", "Subah Ke Taare")
    "KK"          = @("Pal", "Humsafar")
    "Adnan Sami"  = @("Tera Chehra", "Kabhi To Nazar Milao")
    "Rabbi"       = @("Rabbi")
    "Abhijeet"    = @("Tere Bina")
    "A Band Of Boys" = @("Ye Bhi Woh Bhi")
    "Falguni Pathak" = @("The Golden Melodies")
}

function Classify-Track([string]$album, [string]$artist) {
    if ([string]::IsNullOrWhiteSpace($album) -or $album -eq "(No Album Tag)") {
        return @{ Category = "Singles"; SubGroup = (Get-PrimaryArtist $artist); AlbumFolder = $null }
    }

    $cleanAlbum = Clean-AlbumTitle $album
    $cleanArtist = Clean-ArtistName $artist

    # Check if this track belongs to a known artist studio album
    foreach ($artistKey in $ArtistAlbumCatalog.Keys) {
        if ($cleanArtist -like "*$artistKey*") {
            foreach ($knownAlbum in $ArtistAlbumCatalog[$artistKey]) {
                if ($cleanAlbum -match "(?i)^\s*$([regex]::Escape($knownAlbum))(\s|$|\()") {
                    return @{
                        Category    = "Artists"
                        SubGroup    = $artistKey
                        AlbumFolder = $cleanAlbum
                    }
                }
            }
        }
    }

    # If album exists and isn't a dedicated artist studio album, it's a Soundtrack / OST / Compilation
    return @{
        Category    = "Soundtracks"
        SubGroup    = $cleanAlbum
        AlbumFolder = $null
    }
}

# --- Execution Entry Point ---

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     HiBy R1 / Sonix OS Music Library Organizer" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Source:      $SourceDir"
Write-Host "Destination: $DestinationDir"
Write-Host "Mode:        $Mode"
Write-Host "DryRun:      $DryRun"
Write-Host ""

if (-not (Test-Path -LiteralPath $SourceDir)) {
    Write-Error "Source directory not found: $SourceDir"
    exit 1
}

$shell = New-Object -ComObject Shell.Application
$audioExtensions = @(".flac", ".m4a", ".mp3", ".wav", ".opus", ".ogg")

Write-Host "Scanning source files in $SourceDir..." -ForegroundColor Yellow
$extSource = Get-ExtendedPath $SourceDir
$rawFiles = [System.IO.Directory]::GetFiles($extSource, "*.*", [System.IO.SearchOption]::AllDirectories) | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_).ToLower()
    $audioExtensions -contains $ext
}

Write-Host "Found $($rawFiles.Count) audio track(s).`n" -ForegroundColor Green

$processedTracks = 0
$stats = @{ Artists = 0; Soundtracks = 0; Singles = 0 }
$albumMap = @{}

foreach ($fPath in $rawFiles) {
    $normalPath = $fPath
    if ($normalPath.StartsWith("\\?\")) { $normalPath = $normalPath.Substring(4) }
    $fName = [System.IO.Path]::GetFileName($normalPath)
    $fDir = [System.IO.Path]::GetDirectoryName($normalPath)
    $fExt = [System.IO.Path]::GetExtension($normalPath).ToLower()

    $fObj = $shell.Namespace($fDir)
    if (-not $fObj) {
        Write-Warning "Could not access folder: $fDir"
        continue
    }
    $pItem = $fObj.ParseName($fName)
    if (-not $pItem) {
        Write-Warning "Could not parse file: $fName in $fDir"
        continue
    }

    $rawTitle  = $fObj.GetDetailsOf($pItem, 21)
    $rawArtist = $fObj.GetDetailsOf($pItem, 20)
    $rawAlbum  = $fObj.GetDetailsOf($pItem, 14)
    $rawTrack  = $fObj.GetDetailsOf($pItem, 26)

    # Fallback title to filename if tag is empty
    $title = if (-not [string]::IsNullOrWhiteSpace($rawTitle)) {
        Sanitize-PathString $rawTitle
    } else {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($fName)
        Sanitize-PathString $stem
    }

    $artist = Clean-ArtistName $rawArtist
    $trackNumber = 0
    if ($rawTrack -and ($rawTrack -match '(\d+)')) {
        $trackNumber = [int]$matches[1]
    }

    $classification = Classify-Track -album $rawAlbum -artist $rawArtist
    $category = $classification.Category
    $stats[$category]++

    # Build target directory structure
    $destRelDir = ""
    $destFileName = ""

    if ($category -eq "Artists") {
        # Artists/<Artist>/<Album>/01 - Title.ext
        $artistFolder = $classification.SubGroup
        $albumFolder = $classification.AlbumFolder
        $destRelDir = Join-Path "Artists" (Join-Path $artistFolder $albumFolder)

        if ($trackNumber -gt 0) {
            $destFileName = ("{0:D2} - {1}{2}" -f $trackNumber, $title, $fExt)
        } else {
            $destFileName = ("{0}{1}" -f $title, $fExt)
        }
    }
    elseif ($category -eq "Soundtracks") {
        # Soundtracks/<Movie_or_Album>/01 - Title - Artist.ext
        $albumFolder = $classification.SubGroup
        $destRelDir = Join-Path "Soundtracks" $albumFolder

        if ($trackNumber -gt 0) {
            $destFileName = ("{0:D2} - {1} - {2}{3}" -f $trackNumber, $title, $artist, $fExt)
        } else {
            $destFileName = ("{0} - {1}{2}" -f $title, $artist, $fExt)
        }
    }
    else {
        # Singles/<PrimaryArtist>/Title.ext
        $primaryArtist = $classification.SubGroup
        $destRelDir = Join-Path "Singles" $primaryArtist
        $destFileName = ("{0}{1}" -f $title, $fExt)
    }

    $destFullDir = Join-Path $DestinationDir $destRelDir
    $destFullPath = Join-Path $destFullDir $destFileName

    if (-not $albumMap.ContainsKey($destRelDir)) {
        $albumMap[$destRelDir] = 0
    }
    $albumMap[$destRelDir]++

    if ($DryRun) {
        Write-Verbose "[DryRun] $fName -> $destRelDir\$destFileName"
    } else {
        $extDestDir = Get-ExtendedPath $destFullDir
        if (-not [System.IO.Directory]::Exists($extDestDir)) {
            [System.IO.Directory]::CreateDirectory($extDestDir) | Out-Null
        }

        $extSrc = Get-ExtendedPath $fPath
        $extDest = Get-ExtendedPath $destFullPath

        if ($Mode -eq "Move") {
            [System.IO.File]::Move($extSrc, $extDest)
        } else {
            [System.IO.File]::Copy($extSrc, $extDest, $true)
        }
        $processedTracks++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "                     SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Total Audio Tracks Processed: $($rawFiles.Count)"
Write-Host "  - Artists (Studio Albums):  $($stats['Artists']) tracks"
Write-Host "  - Soundtracks (Film OSTs):  $($stats['Soundtracks']) tracks"
Write-Host "  - Singles (Non-Album):      $($stats['Singles']) tracks"
Write-Host "Total Output Folders Created: $($albumMap.Keys.Count)`n"

Write-Host "Sample Output Folders:" -ForegroundColor Yellow
$albumMap.Keys | Sort-Object | Select-Object -First 15 | ForEach-Object {
    Write-Host "  $_ ($($albumMap[$_]) tracks)"
}
if ($albumMap.Keys.Count -gt 15) {
    Write-Host "  ... and $($albumMap.Keys.Count - 15) more folders."
}

Write-Host ""
if ($DryRun) {
    Write-Host "[DRY RUN COMPLETE] No files were copied or moved." -ForegroundColor Yellow
    Write-Host "To execute, run again without the -DryRun switch:`n" -ForegroundColor Yellow
    Write-Host "  .\Organize-MusicForSonix.ps1" -ForegroundColor White
} else {
    Write-Host "Successfully organized $($processedTracks) tracks into '$DestinationDir'!" -ForegroundColor Green
    Write-Host "`nTo use with HiBy R1:" -ForegroundColor Cyan
    Write-Host "1. Copy the '$DestinationDir' folder (or its subfolders) to your microSD card." -ForegroundColor White
    Write-Host "2. On the HiBy R1: Settings -> Music -> 'Scan music library'." -ForegroundColor White
}
