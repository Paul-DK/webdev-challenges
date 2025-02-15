Write-Host "DEBUG: Script started..." -ForegroundColor Cyan

# PowerShell Script to Automate Challenge & Project Creation
# Updated to fix parsing issues & unapproved verb warnings:
#   - Single quotes or $($variable) for SCSS strings
#   - Approved verb usage (Convert, Test, Select, Receive, New, etc.)

# --------------------------------
# 1. Configuration
# --------------------------------
$baseDir = 'C:\Users\pdbho\OneDrive\Documents\Personal Documents\Educational\webdev-challenges'

if (!(Test-Path $baseDir)) {
    Write-Host "Error: The directory '$baseDir' does not exist. Check your path." -ForegroundColor Red
    exit
}

Write-Host "DEBUG: Base directory exists!"
Write-Host "DEBUG: Proceeding with script execution..."
Write-Host "DEBUG: About to define functions..." -ForegroundColor Cyan


# --------------------------------
# 2. Helper Functions
# --------------------------------

function Convert-ProjectName {
    param ([string]$name)
    # Lowercase + replace spaces with dashes
    Write-Host "DEBUG: Inside Convert-ProjectName function" -ForegroundColor Yellow
    return $name.ToLower() -replace '\s+', '-'
}

function Test-FontValidity {
    param ([string]$filePath)
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        if ($fileBytes.Length -lt 4) { return $false }
        $woffMagic = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..3])
        if ($woffMagic -eq 'wOFF' -or $woffMagic -eq 'wOF2') {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Get-GoogleFontsList {
    $repoUrl = 'https://api.github.com/repos/google/fonts/contents/ofl'
    try {
        $response = Invoke-RestMethod -Uri $repoUrl
        return $response | Select-Object -ExpandProperty name
    } catch {
        Write-Host "Error: Unable to fetch font list. Defaulting to 'Poppins'." -ForegroundColor Red
        return @('Poppins')  # fallback
    }
}

function Select-Font {
    param (
        [string[]]$availableFonts
    )
    Write-Host "DEBUG: Inside Select-Font function" -ForegroundColor Yellow
    Write-Host "`nAvailable Google Fonts:"
    for ($i = 0; $i -lt $availableFonts.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i+1), $availableFonts[$i])
    }

    do {
        $choice = Read-Host -Prompt 'Enter the number of the font you want'
        if ([int]::TryParse($choice, [ref]$null)) {
            $choiceIndex = [int]$choice
            if ($choiceIndex -ge 1 -and $choiceIndex -le $availableFonts.Count) {
                return $availableFonts[$choiceIndex - 1]
            }
        }
        Write-Host "Invalid selection. Please enter a number between 1 and $($availableFonts.Count)."
    }
    while ($true)
}

# -----------------------------------
# 2.1 Style => Custom Prop Mappings
# -----------------------------------
$styleMap = @{
    'thin'         = @{ prop = 'fw-lighter'; value = 100 }
    'extralight'   = @{ prop = 'fw-lighter'; value = 200 }
    'lighter'      = @{ prop = 'fw-lighter'; value = 200 }
    'light'        = @{ prop = 'fw-light';   value = 300 }
    'regular'      = @{ prop = 'fw-regular'; value = 400 }
    'medium'       = @{ prop = 'fw-semibold';value = 500 }
    'semibold'     = @{ prop = 'fw-semibold';value = 600 }
    'bold'         = @{ prop = 'fw-bold';    value = 700 }
    'extrabold'    = @{ prop = 'fw-bolder';  value = 800 }
    'bolder'       = @{ prop = 'fw-bolder';  value = 800 }
    'black'        = @{ prop = 'fw-black';   value = 900 }
}

function Convert-StyleToProp {
    param([string]$styleName)

    # Remove "italic" if present (just for weight mapping)
    $clean = $styleName.ToLower() -replace 'italic',''

    foreach ($key in $styleMap.Keys) {
        if ($clean -like "*$key*") {
            return $styleMap[$key]
        }
    }
    return $null
}

# --------------------------------
# 3. Font Download (returns chosen style names)
# --------------------------------
function Receive-Fonts {
    param (
        [string]$targetFolder,
        [string]$fontName
    )
    Write-Host "DEBUG: Inside Receive-Fonts function" -ForegroundColor Yellow

    $availableFonts = Get-GoogleFontsList
    if ($availableFonts -notcontains $fontName) {
        Write-Host "Invalid font name '$fontName'. Defaulting to 'Poppins'." -ForegroundColor Yellow
        $fontName = 'Poppins'
    }

    $formattedFont = $fontName.ToLower() -replace '\s+', ''
    $fontDirUrl = "https://api.github.com/repos/google/fonts/contents/ofl/$formattedFont"

    try {
        $dirContents = Invoke-RestMethod -Uri $fontDirUrl
    } catch {
        Write-Host "Could not fetch contents for '$fontName'. Skipping."
        return @()
    }

    $woffFiles = $dirContents | Where-Object { $_.name -match '\.(woff2|woff)$' }
    if (!$woffFiles) {
        Write-Host "No .woff or .woff2 files found for '$fontName'."
        return @()
    }

    # Unique style tokens (e.g. ["Light","BoldItalic"])
    $foundStyles = @()
    foreach ($file in $woffFiles) {
        $baseName = $file.name -replace '\.woff2?$',''
        $pattern  = "^$fontName-"
        $clean    = $baseName -replace $pattern, ''
        if ($clean -notin $foundStyles) {
            $foundStyles += $clean
        }
    }

    # Prompt user for which styles to download
    Write-Host ('`nStyles found for ' + $fontName + ':')
    for ($i = 0; $i -lt $foundStyles.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i+1), $foundStyles[$i])
    }

    $selection = Read-Host 'Enter the numbers of the styles you want (comma-separated), or press ENTER for all'
    if ([string]::IsNullOrWhiteSpace($selection)) {
        $chosenStyles = $foundStyles
    }
    else {
        $chosenStyles = @()
        $nums = $selection -split ',' | ForEach-Object { $_.Trim() }
        foreach ($n in $nums) {
            if ([int]::TryParse($n, [ref]$null)) {
                $idx = [int]$n - 1
                if ($idx -ge 0 -and $idx -lt $foundStyles.Count) {
                    $chosenStyles += $foundStyles[$idx]
                }
            }
        }
        if ($chosenStyles.Count -eq 0) {
            Write-Host 'No valid selection. Downloading all by default.'
            $chosenStyles = $foundStyles
        }
    }

    if (!(Test-Path $targetFolder)) {
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    }
    foreach ($style in $chosenStyles) {
        $foundAny = $false
        foreach ($ext in @('woff2','woff')) {
            $fileName  = "$fontName-$style.$ext"
            $matchFile = $woffFiles | Where-Object { $_.name -eq $fileName }
            if ($matchFile) {
                $foundAny = $true
                $outPath  = Join-Path $targetFolder $fileName
                if (!(Test-Path $outPath)) {
                    Write-Host "Downloading $fileName..." -ForegroundColor Cyan
                    Invoke-WebRequest -Uri $matchFile.download_url -OutFile $outPath -ErrorAction SilentlyContinue

                    if (Test-Path $outPath -and (Get-Item $outPath).Length -gt 0 -and (Test-FontValidity $outPath)) {
                        Write-Host "$fileName downloaded successfully." -ForegroundColor Green
                    }
                    else {
                        Write-Host "Failed to verify $fileName. Removing." -ForegroundColor Red
                        Remove-Item $outPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    Write-Host "$fileName already exists. Skipping." -ForegroundColor Green
                }
            }
        }
        if (-not $foundAny) {
            Write-Host "$fontName-$style not found in any supported format. Skipping."
        }
    }

    return $chosenStyles
}

# --------------------------------
# 4. Boilerplate & SCSS Creation
# --------------------------------

function New-BoilerplateFiles {
    param (
        [string]$projectPath,
        [string]$displayName,  # Original (unsanitized) for index.html
        [string]$bodyFont,
        [string[]]$bodyStyles,
        [string]$headingFont,
        [string[]]$headingStyles,
        [string]$projectType,  # e.g. "ICT", "FEM", "PROJECT"
        [bool]$isPro           # whether it's a "pro" challenge
    )
Write-Host "DEBUG: Inside New-BoilerplateFiles function" -ForegroundColor Yellow
    # 1) index.html
    $htmlContent = @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8' />
    <title>$displayName</title>
    <meta name='description' content='A simple default HTML page.' />
    <meta name='viewport' content='width=device-width, initial-scale=1.0' />
    <link rel='stylesheet' href='css/styles.css' />
</head>
<body>
    <header>
        <h1>Welcome to $displayName</h1>
    </header>
    <main>
        <p>This is a minimal starting point. Add content here!</p>
    </main>
    <footer></footer>
    <script src='js/main.js'></script>
</body>
</html>
"@
    Set-Content -Path (Join-Path $projectPath 'index.html') -Value $htmlContent

    # 2) Build SCSS (font-face + custom props, etc.)
    $fontFaceRules = ''
    if ($bodyFont) {
        $fontFaceRules += (New-FontFaceRules -fontName $bodyFont -styles $bodyStyles -projectPath $projectPath)
    }
    if ($headingFont) {
        $fontFaceRules += "`r`n" + (New-FontFaceRules -fontName $headingFont -styles $headingStyles -projectPath $projectPath)
    }

    # Gather style props
    $usedProps = @{}
    foreach ($bs in $bodyStyles) {
        $mapping = Convert-StyleToProp $bs
        if ($mapping) {
            $usedProps[$mapping.prop] = $mapping.value
        }
    }
    foreach ($hs in $headingStyles) {
        $mapping = Convert-StyleToProp $hs
        if ($mapping) {
            $usedProps[$mapping.prop] = $mapping.value
        }
    }

    $weightPropLines = @()
    foreach ($k in $usedProps.Keys) {
        $val = $usedProps[$k]
        $weightPropLines += '--' + $k + ': ' + $val + ';'
    }

    # Heading font line
    $headingFontLine = ''
    if ($headingFont) {
        $headingFontLine = "--ff-heading: '$headingFont', sans-serif;"
    }

    # Body font fallback
    $bodyFontLine = '--ff-body: sans-serif;'
    if ($bodyFont) {
        $bodyFontLine = "--ff-body: '$bodyFont', sans-serif;"
    }

    $scssContent = @"
/* --------------------------------
   1. Font Imports (Local @font-face)
-------------------------------- */
$fontFaceRules

/* --------------------------------
   2. Custom Properties
-------------------------------- */
:root {
  $bodyFontLine
  $headingFontLine

  // Weight props discovered:
  $($weightPropLines -join "`r`n  ")
}

/* --------------------------------
   3. Global Reset
-------------------------------- */
*,
*::before,
*::after {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

/* --------------------------------
   4. Base Styles
-------------------------------- */
body {
  font-family: var(--ff-body);
  font-weight: var(--fw-regular, 400);
  display: grid;
  min-height: 100dvh;
  place-items: center;
  background-color: lighten(#007ACC, 50%);
  color: darken(#007ACC, 30%);
}

/* --------------------------------
   5. Typography Reset
-------------------------------- */
h1, h2, h3, h4, h5, h6 {
  font-family: var(--ff-heading, var(--ff-body));
  font-size: 1.5rem;
  font-weight: var(--fw-bold, 700);
}

/* --------------------------------
   6. Image Reset
-------------------------------- */
img, svg {
  display: block;
  max-width: 100%;
}
"
    Set-Content -Path (Join-Path $projectPath 'scss\styles.scss') -Value $scssContent
    Set-Content -Path (Join-Path $projectPath 'css\styles.css') -Value '/* Compiled CSS goes here */'
    New-Item -ItemType File -Path (Join-Path $projectPath 'css\styles.min.css') -Force | Out-Null

    # 3) Basic JS
    $jsContent = "// Main JavaScript File`nconsole.log('Hello from $displayName!');"
    Set-Content -Path (Join-Path $projectPath 'js\main.js') -Value $jsContent

    # 4) .gitignore
    $gitignoreContent = @"
node_modules/
*.log
*.cache
.DS_Store
Thumbs.db
.vscode/
*.fig
*.sketch
"@
    Set-Content -Path (Join-Path $projectPath '.gitignore') -Value $gitignoreContent

    # 5) README.md
    $proLabel     = if ($isPro) { 'Yes' } else { 'No' }
    $headingLabel = if ([string]::IsNullOrWhiteSpace($headingFont)) { 'None' } else { "$headingFont (Styles: $($headingStyles -join ', '))" }
    $bodyLabel    = if ([string]::IsNullOrWhiteSpace($bodyFont)) { 'None/Defaults' } else { "$bodyFont (Styles: $($bodyStyles -join ', '))" }

    $readmeContent = @"
# $displayName

Welcome to the **$displayName** project!

## Project Info

- **Project Type**: $projectType
- **Pro Challenge?**: $proLabel
- **Body Font**: $bodyLabel
- **Heading Font**: $headingLabel

## What's Included

- **index.html**: A minimal HTML starter with a `<header>`, `<main>` and `<footer>`.
- **scss/styles.scss**: Main SCSS file with local @font-face rules for any chosen fonts/styles, plus custom properties (--fw-lighter, --fw-bold, etc.), a global reset, and basic base styles.
- **css/styles.css**: Placeholder file that gets overwritten when you compile scss/styles.scss.
- **js/main.js**: A placeholder JavaScript file with a simple console log.
- **.gitignore**: Handy ignores (like node_modules/, .vscode/, etc.)

## Setup & Usage

1. **Compile SCSS**: If you haven't already, install a Sass compiler (e.g. npm install -g sass), then run:

   sass scss/styles.scss css/styles.css

   This produces your final styles.css.

2. **Open index.html** in your browser, or use a local server (like Live Server in VS Code).

3. **Edit** to your heart's content! Update index.html, tweak scss/styles.scss, or add new folders/files as you grow.

Enjoy your new challenge/project!
"@

    Set-Content -Path (Join-Path $projectPath 'README.md') -Value $readmeContent

    Write-Host "Boilerplate files created successfully." -ForegroundColor Green
}

function New-FontFaceRules {
    param (
        [string]$fontName,
        [string[]]$styles,
        [string]$projectPath
    )

    if ([string]::IsNullOrWhiteSpace($fontName)) {
        return ''
    }
    if (-not $styles) {
        return ''
    }

    $rules = @()

    foreach ($style in $styles) {
        # Map style to numeric weight
        $mapping = Convert-StyleToProp $style
        $weight = if ($mapping) { $mapping.value } else { 400 }

        # italic detection
        $fStyle = 'normal'
        if ($style.ToLower().Contains('italic')) {
            $fStyle = 'italic'
        }

        # Build woff paths
        $baseFileName = "$fontName-$style"
        $woff2Path    = Join-Path $projectPath "assets\fonts\$baseFileName.woff2"
        $woffPath     = Join-Path $projectPath "assets\fonts\$baseFileName.woff"

        $srcEntries = @()
        if (Test-Path $woff2Path) {
            # Single quotes + $($variable) to avoid parse issues
            $srcEntries += 'url(' + "'../assets/fonts/$($baseFileName).woff2'" + ') format("woff2")'
        }
        if (Test-Path $woffPath) {
            $srcEntries += 'url(' + "'../assets/fonts/$($baseFileName).woff'" + ') format("woff")'
        }

        if ($srcEntries.Count -gt 0) {
            $srcLine = $srcEntries -join ",`r`n       "
            $rule = @"
@font-face {
  font-family: '$fontName';
  src: $srcLine;
  font-weight: $weight;
  font-style: $fStyle;
}
"@
            $rules += $rule
        }
    }

    return ($rules -join "`r`n")
}

function New-Project {
    param (
        [string]$type = 'PROJECT',
        [string]$name,
        [switch]$pro
    )
Write-Host "DEBUG: Inside New-Project function" -ForegroundColor Yellow
    # Keep original name for display in HTML/README
    $originalName = $name

    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host 'Error: Project name cannot be empty.' -ForegroundColor Red
        return
    }

    $type = $type.ToUpper()
    switch ($type) {
        'ICT'      { $targetDir = Join-Path $baseDir 'ict-challenges' }
        'FEM'      { $targetDir = Join-Path $baseDir 'fem-challenges' }
        'PROJECT'  { $targetDir = Join-Path $baseDir 'projects' }
        default {
            Write-Host 'Error: Invalid type. Did you mean ICT, FEM, or PROJECT?' -ForegroundColor Red
            return
        }
    }

    $isPro = $false
    if ($pro) {
        $targetDir = Join-Path $targetDir 'pro-challenges'
        $isPro = $true
    }

    $sanitizedName = Convert-ProjectName $name
    $projectPath   = Join-Path $targetDir $sanitizedName
    Write-Host "DEBUG: Target Directory: '$targetDir'" -ForegroundColor Yellow
    Write-Host "DEBUG: Project Path: '$projectPath'" -ForegroundColor Yellow

    # If project folder exists, prompt for a new name
    while (Test-Path $projectPath) {
        Write-Host "Error: Project '$sanitizedName' already exists in $targetDir." -ForegroundColor Red
        $newName = Read-Host 'Please enter a different project name (or press Enter to exit)'
        if ([string]::IsNullOrWhiteSpace($newName)) {
            Write-Host 'No project name provided. Exiting...'
            return
        }
        $originalName  = $newName
        $sanitizedName = Convert-ProjectName $newName
        $projectPath   = Join-Path $targetDir $sanitizedName
    }

    # Create folder structure
    New-Item -ItemType Directory -Path (Join-Path $projectPath 'css')           -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectPath 'scss')          -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectPath 'js')            -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectPath 'assets\fonts')  -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $projectPath 'assets\images') -Force | Out-Null

    # --------------------------------------------------------------------
    # Font Selection & Download (Optional)
    # --------------------------------------------------------------------
    $wantFontsResponse = Read-Host 'Would you like to download any fonts? (Y/N)'
    $wantFontsTrim     = $wantFontsResponse.Trim().ToLower()

    $bodyFont     = ''
    $bodyStyles   = @()
    $headingFont  = ''
    $headingStyles = @()

    if ($wantFontsTrim -eq 'y' -or $wantFontsTrim -eq 'yes') {
        $availableFonts = Get-GoogleFontsList

        # Body Font
        Write-Host "`nSelect the Body font:"
        $bodyFont   = Select-Font -availableFonts $availableFonts
        $bodyStyles = Receive-Fonts -targetFolder (Join-Path $projectPath 'assets\fonts') -fontName $bodyFont

        # Heading Font?
        $headingQ     = Read-Host 'Would you like to select a Heading font as well? (Y/N)'
        $headingQTrim = $headingQ.Trim().ToLower()
        if ($headingQTrim -eq 'y' -or $headingQTrim -eq 'yes') {
            Write-Host "`nSelect the Heading font:"
            $headingFont   = Select-Font -availableFonts $availableFonts
            $headingStyles = Receive-Fonts -targetFolder (Join-Path $projectPath 'assets\fonts') -fontName $headingFont
        }
    }
    else {
        Write-Host 'Skipping font download...'
    }

    # --------------------------------------------------------------------
    # Create the boilerplate (index.html, SCSS, README, etc.)
    # --------------------------------------------------------------------
    New-BoilerplateFiles `
        -projectPath $projectPath `
        -displayName $originalName `
        -bodyFont $bodyFont `
        -bodyStyles $bodyStyles `
        -headingFont $headingFont `
        -headingStyles $headingStyles `
        -projectType $type `
        -isPro $isPro

    # Finally, open VS Code
    Start-Process code -ArgumentList '-r', $baseDir
    Start-Sleep -Milliseconds 500
    Start-Process code -ArgumentList '-r', $projectPath
}

Write-Host "DEBUG: Script finished!" -ForegroundColor Green
Write-Host "DEBUG: Reached the end of script execution!" -ForegroundColor Cyan

Write-Host "DEBUG: Calling New-Project function..." -ForegroundColor Cyan
$projectName = Read-Host "Enter project name"
New-Project -name $projectName


# SIG # Begin signature block
# MIIbxAYJKoZIhvcNAQcCoIIbtTCCG7ECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU6QGlYoJLbncP5FXEfvsv0gaN
# t+WgghY2MIIDLzCCAhegAwIBAgIQblCCJJuvObtDRwb5Zi1LaDANBgkqhkiG9w0B
# AQsFADAfMR0wGwYDVQQDDBRQYXVsLURLIENvZGUgU2lnbmluZzAeFw0yNTAxMjMw
# NzU0NThaFw0yNjAxMjMwODE0NThaMB8xHTAbBgNVBAMMFFBhdWwtREsgQ29kZSBT
# aWduaW5nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv+ymOGr6mpkr
# zgwH8sg3yYbSBm492aNCKASTR44hmP0ndQF9cGI2lQnHogms1ohoJc70WdULFokZ
# AukkCL4c7eE/4pXxmGUPuIheOtBx9xixN2cVvHjHisTnpmrPWvpq4+aIlwkPD6bH
# vLkUjk4IbGcWqTQSGXrz6ZuGKLoS19FpWub9Ohd9k0dp5rNMph2NEb5ZQUUg7wHZ
# 1UFc7DP+kuxOAwm3iDTOjkyhj5k5Tn7Y/4ubWD1+FpxsZ3ESbR8rQ9WylcA3XTeQ
# UPHkbTFbzGHn387a58RHPoqDeZoOXEb2YpfOutSsfK+sAyF4blJozNypwmwi3KM6
# JBBNwKI9iQIDAQABo2cwZTAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYB
# BQUHAwMwHwYDVR0RBBgwFoIUUGF1bC1ESyBDb2RlIFNpZ25pbmcwHQYDVR0OBBYE
# FFFOmhHTDYg+jD6VTnCgPSVooOh2MA0GCSqGSIb3DQEBCwUAA4IBAQAkuQgrkUGC
# B9MnVLEZI5ii8/yR5tTi9xCJ+l9kdW7koG+br29a6OI9k7nfHbgW408Wxe6BMDkV
# 6QLO8YFawTHZdL20YY0kshSjoaXN0m02RkimqqxJcxeqDmPsrmYN+nWwh7fMz9eq
# ezJMikfcROMugQ/fS+SZX0rQzT/BmcDS7YIOeZk68hgi1O50F1tzBk2e6kBfFOiY
# hVwmpMQyPpZPNYSFkCGhczryo/Cja/xvOfR86W4+IcFUo61CfSiOvkEZEbH1i0iL
# erJ4EC3hWJrD+Q/CTq8oLUEd7Z5TmtOibNbHGfXcKYpDPv3JTxgoNxL4e3srLBJP
# cNn2+wutU68xMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG
# 9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1
# cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBi
# MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
# d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3Qg
# RzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAi
# MGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnny
# yhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE
# 5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm
# 7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5
# w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsD
# dV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1Z
# XUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS0
# 0mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hk
# pjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m8
# 00ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+i
# sX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB
# /zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReui
# r/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0w
# azAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUF
# BzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVk
# SURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAG
# BgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9
# mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxS
# A8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/
# 6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSM
# b++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt
# 9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGrjCC
# BJagAwIBAgIQBzY3tyRUfNhHrP0oZipeWzANBgkqhkiG9w0BAQsFADBiMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcN
# MjIwMzIzMDAwMDAwWhcNMzcwMzIyMjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQg
# RzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAxoY1BkmzwT1ySVFVxyUDxPKRN6mXUaHW0oPRnkyi
# baCwzIP5WvYRoUQVQl+kiPNo+n3znIkLf50fng8zH1ATCyZzlm34V6gCff1DtITa
# EfFzsbPuK4CEiiIY3+vaPcQXf6sZKz5C3GeO6lE98NZW1OcoLevTsbV15x8GZY2U
# KdPZ7Gnf2ZCHRgB720RBidx8ald68Dd5n12sy+iEZLRS8nZH92GDGd1ftFQLIWhu
# NyG7QKxfst5Kfc71ORJn7w6lY2zkpsUdzTYNXNXmG6jBZHRAp8ByxbpOH7G1WE15
# /tePc5OsLDnipUjW8LAxE6lXKZYnLvWHpo9OdhVVJnCYJn+gGkcgQ+NDY4B7dW4n
# JZCYOjgRs/b2nuY7W+yB3iIU2YIqx5K/oN7jPqJz+ucfWmyU8lKVEStYdEAoq3ND
# zt9KoRxrOMUp88qqlnNCaJ+2RrOdOqPVA+C/8KI8ykLcGEh/FDTP0kyr75s9/g64
# ZCr6dSgkQe1CvwWcZklSUPRR8zZJTYsg0ixXNXkrqPNFYLwjjVj33GHek/45wPmy
# MKVM1+mYSlg+0wOI/rOP015LdhJRk8mMDDtbiiKowSYI+RQQEgN9XyO7ZONj4Kbh
# PvbCdLI/Hgl27KtdRnXiYKNYCQEoAA6EVO7O6V3IXjASvUaetdN2udIOa5kM0jO0
# zbECAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFLoW
# 2W1NhS9zKXaaL3WMaiCPnshvMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiu
# HA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEF
# BQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBB
# BggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkw
# FzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQB9WY7A
# k7ZvmKlEIgF+ZtbYIULhsBguEE0TzzBTzr8Y+8dQXeJLKftwig2qKWn8acHPHQfp
# PmDI2AvlXFvXbYf6hCAlNDFnzbYSlm/EUExiHQwIgqgWvalWzxVzjQEiJc6VaT9H
# d/tydBTX/6tPiix6q4XNQ1/tYLaqT5Fmniye4Iqs5f2MvGQmh2ySvZ180HAKfO+o
# vHVPulr3qRCyXen/KFSJ8NWKcXZl2szwcqMj+sAngkSumScbqyQeJsG33irr9p6x
# eZmBo1aGqwpFyd/EjaDnmPv7pp1yr8THwcFqcdnGE4AJxLafzYeHJLtPo0m5d2aR
# 8XKc6UsCUqc3fpNTrDsdCEkPlM05et3/JWOZJyw9P2un8WbDQc1PtkCbISFA0LcT
# JM3cHXg65J6t5TRxktcma+Q4c6umAU+9Pzt4rUyt+8SVe+0KXzM5h0F4ejjpnOHd
# I/0dKNPH+ejxmF/7K9h+8kaddSweJywm228Vex4Ziza4k9Tm8heZWcpw8De/mADf
# IBZPJ/tgZxahZrrdVcA6KYawmKAr7ZVBtzrVFZgxtGIJDwq9gdkT/r+k0fNX2bwE
# +oLeMt8EifAAzV3C+dAjfwAL5HYCJtnwZXZCpimHCUcr5n8apIUP/JiW9lVUKx+A
# +sDyDivl1vupL0QVSucTDh3bNzgaoSv27dZ8/DCCBrwwggSkoAMCAQICEAuuZrxa
# un+Vh8b56QTjMwQwDQYJKoZIhvcNAQELBQAwYzELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0
# IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTAeFw0yNDA5MjYwMDAwMDBa
# Fw0zNTExMjUyMzU5NTlaMEIxCzAJBgNVBAYTAlVTMREwDwYDVQQKEwhEaWdpQ2Vy
# dDEgMB4GA1UEAxMXRGlnaUNlcnQgVGltZXN0YW1wIDIwMjQwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC+anOf9pUhq5Ywultt5lmjtej9kR8YxIg7apnj
# pcH9CjAgQxK+CMR0Rne/i+utMeV5bUlYYSuuM4vQngvQepVHVzNLO9RDnEXvPghC
# aft0djvKKO+hDu6ObS7rJcXa/UKvNminKQPTv/1+kBPgHGlP28mgmoCw/xi6FG9+
# Un1h4eN6zh926SxMe6We2r1Z6VFZj75MU/HNmtsgtFjKfITLutLWUdAoWle+jYZ4
# 9+wxGE1/UXjWfISDmHuI5e/6+NfQrxGFSKx+rDdNMsePW6FLrphfYtk/FLihp/fe
# un0eV+pIF496OVh4R1TvjQYpAztJpVIfdNsEvxHofBf1BWkadc+Up0Th8EifkEEW
# dX4rA/FE1Q0rqViTbLVZIqi6viEk3RIySho1XyHLIAOJfXG5PEppc3XYeBH7xa6V
# TZ3rOHNeiYnY+V4j1XbJ+Z9dI8ZhqcaDHOoj5KGg4YuiYx3eYm33aebsyF6eD9MF
# 5IDbPgjvwmnAalNEeJPvIeoGJXaeBQjIK13SlnzODdLtuThALhGtyconcVuPI8Aa
# iCaiJnfdzUcb3dWnqUnjXkRFwLtsVAxFvGqsxUA2Jq/WTjbnNjIUzIs3ITVC6VBK
# AOlb2u29Vwgfta8b2ypi6n2PzP0nVepsFk8nlcuWfyZLzBaZ0MucEdeBiXL+nUOG
# hCjl+QIDAQABo4IBizCCAYcwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAw
# FgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMB8GA1UdIwQYMBaAFLoW2W1NhS9zKXaaL3WMaiCPnshvMB0GA1Ud
# DgQWBBSfVywDdw4oFZBmpWNe7k+SH3agWzBaBgNVHR8EUzBRME+gTaBLhklodHRw
# Oi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2U0hB
# MjU2VGltZVN0YW1waW5nQ0EuY3JsMIGQBggrBgEFBQcBAQSBgzCBgDAkBggrBgEF
# BQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMFgGCCsGAQUFBzAChkxodHRw
# Oi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRSU0E0MDk2
# U0hBMjU2VGltZVN0YW1waW5nQ0EuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQA9rR4f
# dplb4ziEEkfZQ5H2EdubTggd0ShPz9Pce4FLJl6reNKLkZd5Y/vEIqFWKt4oKcKz
# 7wZmXa5VgW9B76k9NJxUl4JlKwyjUkKhk3aYx7D8vi2mpU1tKlY71AYXB8wTLrQe
# h83pXnWwwsxc1Mt+FWqz57yFq6laICtKjPICYYf/qgxACHTvypGHrC8k1TqCeHk6
# u4I/VBQC9VK7iSpU5wlWjNlHlFFv/M93748YTeoXU/fFa9hWJQkuzG2+B7+bMDvm
# gF8VlJt1qQcl7YFUMYgZU1WM6nyw23vT6QSgwX5Pq2m0xQ2V6FJHu8z4LXe/371k
# 5QrN9FQBhLLISZi2yemW0P8ZZfx4zvSWzVXpAb9k4Hpvpi6bUe8iK6WonUSV6yPl
# MwerwJZP/Gtbu3CKldMnn+LmmRTkTXpFIEB06nXZrDwhCGED+8RsWQSIXZpuG4WL
# FQOhtloDRWGoCwwc6ZpPddOFkM2LlTbMcqFSzm4cd0boGhBq7vkqI1uHRz6Fq1IX
# 7TaRQuR+0BGOzISkcqwXu7nMpFu3mgrlgbAW+BzikRVQ3K2YHcGkiKjA4gi4OA/k
# z1YCsdhIBHXqBzR0/Zd2QwQ/l4Gxftt/8wY3grcc/nS//TVkej9nmUYu83BDtccH
# HXKibMs/yXHhDXNkoPIdynhVAku7aRZOwqw6pDGCBPgwggT0AgEBMDMwHzEdMBsG
# A1UEAwwUUGF1bC1ESyBDb2RlIFNpZ25pbmcCEG5QgiSbrzm7Q0cG+WYtS2gwCQYF
# Kw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkD
# MQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJ
# KoZIhvcNAQkEMRYEFHP1gQIjZf3iTvbLMQqB6U7cdWYoMA0GCSqGSIb3DQEBAQUA
# BIIBAB8QDbKu7ifGU7M4XTVL9G2d59cp7uOUA2SB5QHCfbiMpMtv4DxE8pbwVQpK
# 1e5EymRIGnV1xjKCLy9yz6y53gc+xvDDNJertYoakLH68ZtqjwEYD8ODxN8gxAp/
# VEziibEeA/bmMlIiIoSAcRKEok5Md/+EGNselbeds9MRUlQOlGE4zMVLksRU4GMZ
# Q9vphofgAHAgIEt28I20entB29BNSuxilXi/PFRDJVauglXfVFhJ8K230wzh6j4Y
# gA09L5bSrd6ucJ8/IGOzQtsCwtdYpwA/bgMbh7w0mF8cfXa4FMSsG7yXxEttM9ds
# L/dKgydQv6b0po4kLdt/XqWLYqahggMgMIIDHAYJKoZIhvcNAQkGMYIDDTCCAwkC
# AQEwdzBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5
# BgNVBAMTMkRpZ2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0
# YW1waW5nIENBAhALrma8Wrp/lYfG+ekE4zMEMA0GCWCGSAFlAwQCAQUAoGkwGAYJ
# KoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjUwMTIzMDg1
# MjEwWjAvBgkqhkiG9w0BCQQxIgQgedjuMHIGDgwJ02CsNw5A2oBj+3RLE37HytE0
# NblX3XYwDQYJKoZIhvcNAQEBBQAEggIAgHV4L0P9qBPFDk5ZFnfeECkazDCy7jsM
# 8VLhfefDh5u024E7i6U4EcaLq0cjhSX71jq5U9QQ6YEmzVkaKPdadAdz+W1/Jof3
# DJJ3ayCbTY75xHQA0cmqMgNSYyfwk6cJ84OALiwAhqsNau4ZutYq22COJgLbv9Ca
# nSsRezmH9bYsZCahK4RB7HZ6HEUurNXkvOnj97xnQvCLha76FGL5imwnY0YuochB
# N4T2bZQplDYAN3P3JtyA3NSuF9mAbZD8S+OgsNCnmClTNSecQRYKz3NK3ZweIZ1v
# SVYU8xz+vy/f4uXNQZUur6fxLxhRna4gYzjz0ODz/5CU3FXbBDL1w4iSMT6dNOKV
# RkXNmNHxvypF2aNFVLHO4cxk2G659Qe0z/Ylr9gMZVpAXTYxYdhopthgpwHBb20L
# 8R9q16+autwXILXExzFwkejchCN7AbpPrr6QizuauJUz8EpnNDQ9RaYXix/oY0El
# aiKoZeM0QmDx1/1ZXvCZlWacsen6MKrThVr2MNeEjjjAxnLcqfa9sRYOc19NKQ1e
# SSlLC7QfYhkFbglP53ZvhkjffmOaBsH4pNY4YkvfZOMziL3UKSy81MLDeKv3pxTb
# +/6E3v3LbTEaJoc7nAqHg4MXcHmDXS/s0ui8aMMUWOcgJmb85jS2nKg2eQHsvRBB
# h1Q0sr7/p14=
# SIG # End signature block
