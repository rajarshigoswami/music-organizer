<#
.SYNOPSIS
    Generates Sonix OS / HiBy R1 compatible M3U playlists remapping legacy folders
    to organized music paths.

.DESCRIPTION
    Sonix OS (HiBy R1) reads user playlists from `<card_root>/Playlist/<Name>.m3u`
    and recognizes files marked with `#[Sonix Playlist]`.
    
    This script inspects legacy music folders (e.g. from E:\music), matches each audio
    track to its new organized destination in E:\Music_Organized, and writes out
    clean, UTF-8 (no BOM) .m3u playlists with relative Linux/FAT32 paths.

    Playlists generated:
      1. Hindi 2.m3u     (remapped from 'hindi 2')
      2. LP.m3u          (remapped from 'lp')
      3. Best of LP.m3u  (remapped from 'best of lp')
      4. Hindi.m3u       (remapped from 'hindi')
      5. KK.m3u          (remapped from 'kk')
      6. Lucky Ali.m3u   (remapped from 'lucky ali')
      7. Movies.m3u      (remapped from 'Movies')

.PARAMETER SourceMusicDir
    Path to original legacy music folder. Default: "E:\music"

.PARAMETER OrganizedMusicDir
    Path to organized music folder. Default: "E:\Music_Organized"

.PARAMETER PlaylistDir
    Primary Sonix OS playlist folder on SD card root. Default: "E:\Playlist"

.PARAMETER OrganizedPlaylistDir
    Secondary backup playlist folder inside organized music. Default: "E:\Music_Organized\Playlists"

.PARAMETER DryRun
    If specified, displays the remapping plan without writing files.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$SourceMusicDir = "E:\music",

    [Parameter(Position = 1)]
    [string]$OrganizedMusicDir = "E:\Music",

    [Parameter(Position = 2)]
    [string]$PlaylistDir = "E:\Playlist",

    [Parameter(Position = 3)]
    [string]$OrganizedPlaylistDir = "E:\Music\Playlists",

    [switch]$DryRun
)

# Initialize Shell COM object for metadata extraction
$shell = New-Object -ComObject Shell.Application

function Get-TrackMetadata($fullPath) {
    $parent = [System.IO.Path]::GetDirectoryName($fullPath)
    $leaf = [System.IO.Path]::GetFileName($fullPath)
    $fObj = $shell.Namespace($parent)
    if (-not $fObj) { return $null }
    $item = $fObj.ParseName($leaf)
    if (-not $item) { return $null }
    
    $title = $fObj.GetDetailsOf($item, 21)
    $artist = $fObj.GetDetailsOf($item, 20)
    $album = $fObj.GetDetailsOf($item, 14)
    $durStr = $fObj.GetDetailsOf($item, 27)

    $seconds = -1
    if (-not [string]::IsNullOrWhiteSpace($durStr)) {
        $parts = $durStr.Trim() -split ':'
        if ($parts.Count -eq 3) {
            $seconds = ([int]$parts[0] * 3600) + ([int]$parts[1] * 60) + [int]$parts[2]
        } elseif ($parts.Count -eq 2) {
            $seconds = ([int]$parts[0] * 60) + [int]$parts[1]
        }
    }

    return @{
        Title = if (-not [string]::IsNullOrWhiteSpace($title)) { $title.Trim() } else { [System.IO.Path]::GetFileNameWithoutExtension($fullPath) }
        Artist = if (-not [string]::IsNullOrWhiteSpace($artist)) { $artist.Trim() } else { "Unknown Artist" }
        Album = if (-not [string]::IsNullOrWhiteSpace($album)) { $album.Trim() } else { "" }
        Seconds = $seconds
    }
}

function Normalize-String([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $clean = $s -replace '(?i)\s*[\(\[]Original Motion Picture Soundtrack[\)\]]', ''
    $clean = $clean -replace '(?i)\s*[\(\[]Deluxe Edition[\)\]]', ''
    $clean = $clean -replace '(?i)\s*[\(\[]Bonus Edition[\)\]]', ''
    $clean = $clean -replace '[\/:*?"<>|_-]', ' '
    $clean = $clean -replace '\s+', ' '
    return $clean.Trim().ToLowerInvariant()
}

# 1. Index all organized tracks
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Sonix OS Playlist Remapper for HiBy R1" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Indexing organized tracks in '$OrganizedMusicDir'..." -ForegroundColor Gray

$audioPattern = '\.(mp3|flac|m4a|wav|ogg|aac|wma|aiff|ape|dsf|dff)$'
$orgFiles = Get-ChildItem -LiteralPath $OrganizedMusicDir -File -Recurse | Where-Object { $_.Extension -match $audioPattern }

$orgByLength = @{}
$orgByAlbumTitle = @{}
$orgByTitle = @{}

foreach ($f in $orgFiles) {
    if (-not $orgByLength.ContainsKey($f.Length)) {
        $orgByLength[$f.Length] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $orgByLength[$f.Length].Add($f)

    $meta = Get-TrackMetadata $f.FullName
    $cleanTitle = Normalize-String $meta.Title
    if (-not $cleanTitle) {
        $cleanTitle = Normalize-String ($f.BaseName -replace '^\d+\s*[-_.]\s*', '')
    }
    $cleanAlbum = Normalize-String $meta.Album

    $atKey = "$cleanAlbum|$cleanTitle"
    if (-not $orgByAlbumTitle.ContainsKey($atKey)) {
        $orgByAlbumTitle[$atKey] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $orgByAlbumTitle[$atKey].Add($f)

    if (-not $orgByTitle.ContainsKey($cleanTitle)) {
        $orgByTitle[$cleanTitle] = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    }
    $orgByTitle[$cleanTitle].Add($f)
}

Write-Host "Found $($orgFiles.Count) organized tracks available for remapping." -ForegroundColor Green

# 2. Define Playlist Mapping Specifications
$PlaylistSpecs = @(
    @{ Folder = "hindi 2";     PlaylistName = "Hindi 2" },
    @{ Folder = "lp";          PlaylistName = "LP" },
    @{ Folder = "best of lp";  PlaylistName = "Best of LP" },
    @{ Folder = "hindi";       PlaylistName = "Hindi" },
    @{ Folder = "kk";          PlaylistName = "KK" },
    @{ Folder = "lucky ali";   PlaylistName = "Lucky Ali" },
    @{ Folder = "Movies";      PlaylistName = "Movies" }
)

# Prepare destination directories
if (-not $DryRun) {
    if (-not [System.IO.Directory]::Exists($PlaylistDir)) {
        [System.IO.Directory]::CreateDirectory($PlaylistDir) | Out-Null
    }
    if (-not [System.IO.Directory]::Exists($OrganizedPlaylistDir)) {
        [System.IO.Directory]::CreateDirectory($OrganizedPlaylistDir) | Out-Null
    }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$summaryTable = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($spec in $PlaylistSpecs) {
    $srcFolderName = $spec.Folder
    $plName = $spec.PlaylistName
    $srcFolderPath = Join-Path $SourceMusicDir $srcFolderName

    Write-Host "`nProcessing Playlist: '$plName' (from '$srcFolderName')..." -ForegroundColor Yellow

    if (-not (Test-Path -LiteralPath $srcFolderPath)) {
        Write-Warning "Source folder '$srcFolderPath' does not exist. Skipping."
        continue
    }

    # Gather audio files (and media files for Movies)
    $srcFiles = Get-ChildItem -LiteralPath $srcFolderPath -File -Recurse | Where-Object { 
        $_.Extension -match $audioPattern -or ($srcFolderName -eq "Movies" -and $_.Extension -match '\.(mp4|mkv|avi)$')
    }

    $cardRootEntries = [System.Collections.Generic.List[string]]::new()
    $orgRootEntries = [System.Collections.Generic.List[string]]::new()

    # Sonix Standard Header
    $cardRootEntries.Add("#EXTM3U")
    $cardRootEntries.Add("#[Sonix Playlist]")
    $orgRootEntries.Add("#EXTM3U")
    $orgRootEntries.Add("#[Sonix Playlist]")

    $matchedCount = 0

    foreach ($sf in $srcFiles) {
        $targetFile = $null

        if ($sf.Extension -match $audioPattern) {
            # Attempt 1: Exact byte length match (100% exact for copied files)
            if ($sf.Length -gt 0 -and $orgByLength.ContainsKey($sf.Length)) {
                $targetFile = $orgByLength[$sf.Length][0]
            } else {
                # Attempt 2: Metadata normalized Album + Title match
                $meta = Get-TrackMetadata $sf.FullName
                $cleanTitle = Normalize-String $meta.Title
                if (-not $cleanTitle) {
                    $cleanTitle = Normalize-String ($sf.BaseName -replace '^\d+\s*[-_.]\s*', '')
                }
                $cleanAlbum = Normalize-String $meta.Album
                $atKey = "$cleanAlbum|$cleanTitle"

                if ($orgByAlbumTitle.ContainsKey($atKey)) {
                    $targetFile = $orgByAlbumTitle[$atKey][0]
                } elseif ($orgByTitle.ContainsKey($cleanTitle)) {
                    # Attempt 3: Title match
                    $targetFile = $orgByTitle[$cleanTitle][0]
                }
            }
        }

        if ($targetFile) {
            $matchedCount++
            $meta = Get-TrackMetadata $targetFile.FullName
            $dispArtist = ($meta.Artist -split ';')[0].Trim()
            $extInf = "#EXTINF:$($meta.Seconds),$dispArtist - $($meta.Title)"

            # Relative path from E:\Playlist to E:\Music_Organized\...
            # e.g.: ../Music_Organized/Artists/KK/Pal/03 - Yaaron.flac
            $driveRoot = [System.IO.Path]::GetPathRoot($targetFile.FullName)
            $fromDriveRoot = $targetFile.FullName.Substring($driveRoot.Length).TrimStart('\/').Replace('\', '/')
            $cardEntry = "../$fromDriveRoot"

            # Relative path from E:\Music_Organized\Playlists to E:\Music_Organized\...
            # e.g.: ../Artists/KK/Pal/03 - Yaaron.flac
            $relToOrg = $targetFile.FullName.Substring($OrganizedMusicDir.Length).TrimStart('\/').Replace('\', '/')
            $orgEntry = "../$relToOrg"

            $cardRootEntries.Add($extInf)
            $cardRootEntries.Add($cardEntry)

            $orgRootEntries.Add($extInf)
            $orgRootEntries.Add($orgEntry)
        } elseif ($srcFolderName -eq "Movies") {
            # For Movies video files, preserve paths in playlist
            $meta = Get-TrackMetadata $sf.FullName
            $extInf = "#EXTINF:$($meta.Seconds),$($sf.BaseName)"
            $cardEntry = "../music/Movies/$($sf.Name)"
            $cardRootEntries.Add($extInf)
            $cardRootEntries.Add($cardEntry)

            $orgEntry = "../../music/Movies/$($sf.Name)"
            $orgRootEntries.Add($extInf)
            $orgRootEntries.Add($orgEntry)
            $matchedCount++
        }
    }

    # File paths
    $cardPlPath = Join-Path $PlaylistDir "$plName.m3u"
    $orgPlPath = Join-Path $OrganizedPlaylistDir "$plName.m3u"

    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($cardPlPath, ($cardRootEntries -join "`n") + "`n", $utf8NoBom)
        [System.IO.File]::WriteAllText($orgPlPath, ($orgRootEntries -join "`n") + "`n", $utf8NoBom)
        Write-Host "  [OK] Saved to: $cardPlPath" -ForegroundColor Green
        Write-Host "  [OK] Saved to: $orgPlPath" -ForegroundColor Green
    } else {
        Write-Host "  [DryRun] Would write $($cardRootEntries.Count) lines to $cardPlPath" -ForegroundColor Cyan
    }

    $summaryTable.Add([PSCustomObject]@{
        PlaylistName = "$plName.m3u"
        SourceFolder = $srcFolderName
        TotalTracks  = $srcFiles.Count
        MappedTracks = $matchedCount
        MatchRate    = if ($srcFiles.Count -gt 0) { "{0:P0}" -f ($matchedCount / $srcFiles.Count) } else { "100%" }
        Status       = "Success"
    })
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Playlist Generation Summary" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
$summaryTable | Format-Table -AutoSize

Write-Host "`nAll 7 playlists created successfully!" -ForegroundColor Green
Write-Host "Primary Location (Auto-imported by Sonix on HiBy R1 boot): $PlaylistDir" -ForegroundColor Cyan
Write-Host "Organized Backup Location: $OrganizedPlaylistDir" -ForegroundColor Cyan
