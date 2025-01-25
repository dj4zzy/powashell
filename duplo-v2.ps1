<#
.SYNOPSIS
Finds and manages duplicate files in a directory.

.DESCRIPTION
Scans files, identifies duplicates using hash comparisons, and moves duplicates to a specified folder.
Supports recursive scanning and different hash algorithms.

.PARAMETER OutputFolder
Name of the folder to store duplicates (default: 'duplicated')

.PARAMETER Algorithm
Hashing algorithm to use (SHA256, SHA1, MD5). Default: SHA256

.PARAMETER Recurse
Scan subdirectories recursively

.PARAMETER WhatIf
Show what would happen without making changes

.EXAMPLE
.\duplo.ps1 -Algorithm MD5 -Recurse
#>

param(
    [string]$OutputFolder = "duplicated",
    [ValidateSet('SHA256','SHA1','MD5')]
    [string]$Algorithm = "SHA256",
    [switch]$Recurse,
    [switch]$WhatIf
)

# Initialize counters
$script:totalFiles = 0
$script:totalDuplicates = 0
$script:totalSpaceSaved = 0
$dupFolderPath = Join-Path -Path $PWD -ChildPath $OutputFolder

# Create output folder if needed
try {
    if (-not (Test-Path $dupFolderPath)) {
        Write-Verbose "Creating output folder: $dupFolderPath" -Verbose
        $null = New-Item -Path $dupFolderPath -ItemType Directory -Force -ErrorAction Stop
    }
}
catch {
    Write-Error "Failed to create output folder: $_"
    exit 1
}

# File scanning with progress display
Write-Host "`nScanning files..." -ForegroundColor Cyan
$files = Get-ChildItem -File -Recurse:$Recurse | 
        Where-Object { $_.FullName -notmatch [regex]::Escape($dupFolderPath) } |
        ForEach-Object {
            $script:totalFiles++
            Write-Progress -Activity "Hashing Files" -Status "$($_.Name)" -PercentComplete ($script:totalFiles / $fileCount * 100)
            
            try {
                [PSCustomObject]@{
                    FilePath = $_.FullName
                    SizeMB = [math]::Round($_.Length/1MB, 2)
                    Hash = (Get-FileHash -Path $_.FullName -Algorithm $Algorithm -ErrorAction Stop).Hash
                }
            }
            catch {
                Write-Warning "Failed to hash $($_.FullName): $_"
            }
        }

# Process duplicates
Write-Host "`nAnalyzing hashes..." -ForegroundColor Cyan
$files | Group-Object -Property Hash | 
    Where-Object { $_.Count -gt 1 } | 
    ForEach-Object {
        $group = $_.Group
        $duplicateCount = $group.Count - 1
        $script:totalDuplicates += $duplicateCount
        $spaceSaved = $group[0].SizeMB * $duplicateCount
        $script:totalSpaceSaved += $spaceSaved

        Write-Host "`nDuplicate Group (Hash: $($_.Name))" -ForegroundColor Magenta
        Write-Host "Original: $($group[0].FilePath)" -ForegroundColor Green
        
        $group | Select-Object -Skip 1 | ForEach-Object {
            $targetPath = Join-Path $dupFolderPath (Get-UniqueFileName -Path $dupFolderPath -Name $_.FilePath.Split('\')[-1])
            
            if ($WhatIf) {
                Write-Host "[WHATIF] Would move $($_.FilePath) -> $targetPath" -ForegroundColor DarkGray
                return
            }

            try {
                Write-Host "Moving: $($_.FilePath) -> $OutputFolder" -ForegroundColor Yellow
                Move-Item -Path $_.FilePath -Destination $targetPath -Force -ErrorAction Stop
            }
            catch {
                Write-Error "Failed to move $($_.FilePath): $_"
            }
        }
    }

# Summary
$summary = [PSCustomObject]@{
    FilesScanned = $script:totalFiles
    DuplicatesFound = $script:totalDuplicates
    PotentialSpaceSaved = "$([math]::Round($script:totalSpaceSaved, 2)) MB"
    OutputLocation = $dupFolderPath
}

Write-Host "`nSummary:" -ForegroundColor Cyan
$summary | Format-List

# Helper function to generate unique filenames
function Get-UniqueFileName {
    param($Path, $Name)
    $base = $Name.Split('.')[0]
    $ext = $Name.Substring($base.Length)
    $counter = 1
    $newName = $Name

    while (Test-Path (Join-Path $Path $newName)) {
        $newName = "${base}_$counter$ext"
        $counter++
    }
    return $newName
}