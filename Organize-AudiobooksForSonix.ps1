<#
.SYNOPSIS
    Organizes converted audiobooks into the exact folder structure and naming
    convention required by the Sonix OS on the HiBy R1.

.DESCRIPTION
    Sonix OS indexes audiobooks from the root /Audiobooks folder and parses:
      - Series books: Audiobooks/<Author>/<Series>/<BookTitle>/
      - Standalone books: Audiobooks/<Author>/<BookTitle>/
      - Book numbers in a series: expects "01 - Title" or "1 - Title" (square brackets like "[01]" break series ordering).
      - Chapter playback order: Sonix sorts folder book chapters using 'natural_compare' on the filename.
        Without numeric prefixes, tracks like 'Opening Credits', 'End Credits', and 'Chapter 10' play out of order.
        This script uses the book's .m3u playlist (or ID3 track tags) to prefix each file with padded track numbers (01 -, 02 -).

.PARAMETER SourceDir
    The directory containing converted audiobooks. Default: "$HOME\Music\Audible\converted"

.PARAMETER DestinationDir
    The output directory where the organized Audiobooks folder structure will be created.
    Default: "$HOME\Music\Audible\Audiobooks"

.PARAMETER Mode
    "Copy" (default) or "Move". "Copy" leaves the source folder intact (Option B).

.PARAMETER DryRun
    If specified, displays all actions that would be performed without modifying or copying any files.

.EXAMPLE
    .\Organize-AudiobooksForSonix.ps1 -DryRun
    .\Organize-AudiobooksForSonix.ps1 -DestinationDir "E:\Audiobooks"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$SourceDir = "$HOME\Music\Audible\converted",

    [Parameter(Position = 1)]
    [string]$DestinationDir = "$HOME\Music\Audible\Audiobooks",

    [ValidateSet("Copy", "Move")]
    [string]$Mode = "Copy",

    [switch]$DryRun
)

# Helper for long path support on Windows
function Get-ExtendedPath([string]$p) {
    $full = [System.IO.Path]::GetFullPath($p)
    if ($full.StartsWith("\\?\")) { return $full }
    if ($full.StartsWith("\\")) { return "\\?\UNC\" + $full.Substring(2) }
    return "\\?\" + $full
}

function Clean-AuthorName([string]$author) {
    if ([string]::IsNullOrWhiteSpace($author)) { return "Unknown Author" }
    
    # Specific known author cleanup
    if ($author -eq "Amish") { return "Amish Tripathi" }
    if ($author -match "H.*ctor Garc.*a") { return "Hector Garcia & Francesc Miralles" }
    if ($author -match "Suhas Kshirsagar") { return "Dr. Suhas Kshirsagar" }
    if ($author -match "Marco Suarez") { return "Marco Suarez et al" }
    if ($author -match "Neil Gaiman") { return "Neil Gaiman & Dirk Maggs" }
    
    # General cleanup: normalize separators and multiple whitespace
    $clean = $author -replace ";", "," -replace "\s+", " "
    $parts = $clean -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    
    # Trim author roles like " - foreword"
    $parts = $parts | ForEach-Object { $_ -replace "\s*-\s*(foreword|narrator|introduction).*$", "" }
    
    # If more than 3 authors, abbreviate for small screen display
    if ($parts.Count -gt 3) {
        return "$($parts[0]) et al"
    }
    return ($parts -join ", ")
}

function Clean-SeriesName([string]$series) {
    if ([string]::IsNullOrWhiteSpace($series)) { return $null }
    $s = $series.Trim()
    $s = $s -replace "(?i)\s*series\s*$", ""
    $s = $s -replace "(?i)\s*\(chronological order\)\s*$", ""
    $s = $s -replace "(?i)^a\s+jack\s+ryan\s+novel.*$", "Jack Ryan"
    return $s.Trim()
}

function Clean-BookFolderName([string]$folderName) {
    # Convert [01] Book Title or [1] Book Title -> 01 - Book Title
    if ($folderName -match '^\[(\d+)\]\s*[\-_.]?\s*(.*)$') {
        $num = [int]$matches[1]
        $rest = $matches[2].Trim()
        return ("{0:D2} - {1}" -f $num, $rest)
    }
    return $folderName.Trim()
}

function Get-OrderedTrackList([string]$bookDir) {
    $extBookDir = Get-ExtendedPath $bookDir
    $allMp3s = [System.IO.Directory]::GetFiles($extBookDir, "*.mp3") | ForEach-Object { [System.IO.Path]::GetFileName($_) }
    if ($allMp3s.Count -eq 0) { return @() }

    # Check for .m3u playlist file first
    $m3uFiles = [System.IO.Directory]::GetFiles($extBookDir, "*.m3u")
    if ($m3uFiles.Count -gt 0) {
        $m3uPath = $m3uFiles[0]
        try {
            $lines = [System.IO.File]::ReadAllLines($m3uPath)
            $orderedFromM3u = @()
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed -and -not $trimmed.StartsWith("#")) {
                    $leaf = [System.IO.Path]::GetFileName($trimmed)
                    if ($allMp3s -contains $leaf -and -not ($orderedFromM3u -contains $leaf)) {
                        $orderedFromM3u += $leaf
                    }
                }
            }
            # Append any mp3 files that were in the directory but not in the m3u
            $missing = $allMp3s | Where-Object { -not ($orderedFromM3u -contains $_) }
            if ($missing) {
                $orderedFromM3u += ($missing | Sort-Object)
            }
            if ($orderedFromM3u.Count -gt 0) {
                return $orderedFromM3u
            }
        } catch {
            Write-Warning "Could not read .m3u in '$bookDir': $_"
        }
    }

    # Fallback: Sort naturally by filename
    return ($allMp3s | Sort-Object)
}

# --- Execution Entry Point ---

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   HiBy R1 / Sonix OS Audiobook Organizer (Option B)" -ForegroundColor Cyan
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

# Locate all directories containing .mp3 files
$extSource = Get-ExtendedPath $SourceDir
$rawDirs = [System.IO.Directory]::GetDirectories($extSource, "*", [System.IO.SearchOption]::AllDirectories)
$bookDirs = @()
foreach ($d in $rawDirs) {
    $mp3Count = [System.IO.Directory]::GetFiles($d, "*.mp3").Count
    if ($mp3Count -gt 0) {
        # Strip long path prefix for relative calculation
        $normalPath = $d
        if ($normalPath.StartsWith("\\?\")) { $normalPath = $normalPath.Substring(4) }
        $bookDirs += $normalPath
    }
}

Write-Host "Found $($bookDirs.Count) audiobook(s) to process.`n" -ForegroundColor Green

$bookSummary = @()
$totalCopied = 0

foreach ($d in ($bookDirs | Sort-Object)) {
    $rel = $d.Substring($SourceDir.Length).TrimStart('\', '/')
    $parts = $rel -split '[\\/]'
    
    $author = ""
    $series = $null
    $book = ""

    if ($parts.Count -ge 3) {
        $author = Clean-AuthorName $parts[0]
        $series = Clean-SeriesName $parts[1]
        $book = Clean-BookFolderName $parts[2]
        $destBookRel = Join-Path $author (Join-Path $series $book)
    } elseif ($parts.Count -eq 2) {
        $author = Clean-AuthorName $parts[0]
        $book = Clean-BookFolderName $parts[1]
        $destBookRel = Join-Path $author $book
    } else {
        $author = "Unknown Author"
        $book = Clean-BookFolderName $parts[0]
        $destBookRel = Join-Path $author $book
    }

    $destBookDir = Join-Path $DestinationDir $destBookRel
    $orderedFiles = Get-OrderedTrackList -bookDir $d
    $totalTracks = $orderedFiles.Count
    $pad = if ($totalTracks -ge 100) { 3 } else { 2 }

    Write-Host "Processing Book: $book" -ForegroundColor Yellow
    Write-Host "  Author: $author"
    if ($series) { Write-Host "  Series: $series" }
    Write-Host "  Target: $destBookRel"
    Write-Host "  Tracks: $totalTracks"

    if (-not $DryRun) {
        $extDestBook = Get-ExtendedPath $destBookDir
        if (-not [System.IO.Directory]::Exists($extDestBook)) {
            [System.IO.Directory]::CreateDirectory($extDestBook) | Out-Null
        }
    }

    $destM3uEntries = @()

    for ($i = 0; $i -lt $totalTracks; $i++) {
        $trackNum = $i + 1
        $srcFile = $orderedFiles[$i]
        $prefix = ("{0:D$pad}" -f $trackNum)

        # Clean existing prefix if already present (e.g. "(001) " or "01 - ")
        $cleanName = if ($srcFile -match "^\(?\d{2,3}\)?[\s\.\-]+(.*)$") { $matches[1] } else { $srcFile }
        $destFileName = "$prefix - $cleanName"
        $destM3uEntries += $destFileName

        $srcPath = Join-Path $d $srcFile
        $destPath = Join-Path $destBookDir $destFileName

        if ($DryRun) {
            Write-Verbose "  [DryRun] $srcFile -> $destFileName"
        } else {
            $extSrcPath = Get-ExtendedPath $srcPath
            $extDestPath = Get-ExtendedPath $destPath
            if ($Mode -eq "Move") {
                [System.IO.File]::Move($extSrcPath, $extDestPath)
            } else {
                [System.IO.File]::Copy($extSrcPath, $extDestPath, $true)
            }
            $totalCopied++
        }
    }

    # Also copy any cover art images if present
    $extSrcBook = Get-ExtendedPath $d
    $imgFiles = [System.IO.Directory]::GetFiles($extSrcBook, "*.*") | Where-Object {
        $_ -match '\.(jpg|jpeg|png)$'
    }
    foreach ($img in $imgFiles) {
        $imgName = [System.IO.Path]::GetFileName($img)
        $destImgPath = Join-Path $destBookDir $imgName
        if (-not $DryRun) {
            $extDestImg = Get-ExtendedPath $destImgPath
            [System.IO.File]::Copy($img, $extDestImg, $true)
        }
    }

    # Write clean updated playlist file
    if (-not $DryRun) {
        $destM3uName = "$book.m3u"
        $destM3uPath = Join-Path $destBookDir $destM3uName
        $extDestM3u = Get-ExtendedPath $destM3uPath
        [System.IO.File]::WriteAllLines($extDestM3u, $destM3uEntries)
    }

    $bookSummary += [PSCustomObject]@{
        Author     = $author
        Series     = if ($series) { $series } else { "-" }
        BookTitle  = $book
        Tracks     = $totalTracks
        TargetDir  = $destBookRel
    }

    Write-Host ""
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "                     SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
$bookSummary | Format-Table -AutoSize

if ($DryRun) {
    Write-Host "[DRY RUN COMPLETE] No files were copied or moved." -ForegroundColor Yellow
    Write-Host "To execute, run again without the -DryRun switch:`n" -ForegroundColor Yellow
    Write-Host "  .\Organize-AudiobooksForSonix.ps1" -ForegroundColor White
} else {
    Write-Host "Successfully processed $($bookSummary.Count) books ($totalCopied files $Mode`d)!" -ForegroundColor Green
    Write-Host "`nHow to copy to your HiBy R1:" -ForegroundColor Cyan
    Write-Host "1. Connect your HiBy R1 via USB or mount your microSD card." -ForegroundColor White
    Write-Host "2. Copy the entire '$DestinationDir' folder to the ROOT of the microSD card so it becomes:" -ForegroundColor White
    Write-Host "     <SD-Drive>:\Audiobooks\" -ForegroundColor Yellow
    Write-Host "3. Safely disconnect the device." -ForegroundColor White
    Write-Host "4. On HiBy R1: Go to Audiobooks -> Settings icon (top right) -> 'Scan audiobooks' (or 扫描有声书)." -ForegroundColor White
}
