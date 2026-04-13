<#
.SYNOPSIS
    Poshify - A PowerShell module for managing oh-my-posh themes

.DESCRIPTION
    This module provides comprehensive functions to manage oh-my-posh themes including:
    - Listing local and online themes
    - Installing, updating, and removing themes
    - Switching between themes with preview capability
    - Managing favorite themes
    - Random theme selection
    - Theme information and details

.NOTES
    Author: Poshify Module
    Version: 2.0.0
    Changelog:
        - Added theme caching for better performance
        - Added GitHub API rate limit handling
        - Added theme preview functionality
        - Added current theme detection
        - Added theme remove/update functions
        - Added favorites system
        - Added random theme feature
        - Improved error handling and validation
        - Enhanced output formatting
        - Added progress indicators
#>

# Module variables
$script:PoshifyVersion = '2.0.0'
$script:PoshifyThemesPath = Join-Path $env:USERPROFILE ".poshthemes"
$script:PoshifyCachePath = Join-Path $script:PoshifyThemesPath ".cache"
$script:PoshifyFavoritesPath = Join-Path $script:PoshifyThemesPath ".favorites.json"
$script:OhMyPoshGitHubThemesUrl = "https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes"
$script:ProfileBackupPath = Join-Path $env:USERPROFILE ".poshthemes\.profile_backup"
$script:CacheDurationMinutes = 60
$script:GitHubApiRateLimitRemaining = $null
$script:GitHubApiRateLimitReset = $null

#region Helper Functions

<#
.SYNOPSIS
    Internal helper to ensure required directories exist
#>
function Initialize-PoshifyDirectories {
    if (-not (Test-Path $script:PoshifyThemesPath)) {
        New-Item -ItemType Directory -Path $script:PoshifyThemesPath -Force | Out-Null
    }
    if (-not (Test-Path $script:PoshifyCachePath)) {
        New-Item -ItemType Directory -Path $script:PoshifyCachePath -Force | Out-Null
    }
}

<#
.SYNOPSIS
    Internal helper to manage GitHub API rate limits
#>
function Test-PoshifyRateLimit {
    param(
        [switch]$Verbose
    )
    
    if ($script:GitHubApiRateLimitRemaining -and $script:GitHubApiRateLimitReset) {
        if ($script:GitHubApiRateLimitRemaining -lt 5) {
            $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($script:GitHubApiRateLimitReset).DateTime
            $timeUntilReset = $resetTime - (Get-Date)
            
            if ($timeUntilReset -gt [TimeSpan]::Zero) {
                Write-Warning "GitHub API rate limit nearly exhausted. $($script:GitHubApiRateLimitRemaining) requests remaining."
                Write-Host "Rate limit resets in: $($timeUntilReset.ToString('hh\:mm\:ss'))" -ForegroundColor Yellow
                return $false
            }
        }
    }
    return $true
}

<#
.SYNOPSIS
    Internal helper to update rate limit info from response headers
#>
function Update-PoshifyRateLimit {
    param(
        $Response
    )
    
    if ($Response.Headers.'X-RateLimit-Remaining') {
        $script:GitHubApiRateLimitRemaining = [int]$Response.Headers.'X-RateLimit-Remaining'
    }
    if ($Response.Headers.'X-RateLimit-Reset') {
        $script:GitHubApiRateLimitReset = [int]$Response.Headers.'X-RateLimit-Reset'
    }
}

<#
.SYNOPSIS
    Internal helper to get cached themes or fetch fresh data
#>
function Get-PoshifyCachedThemes {
    param(
        [switch]$ForceRefresh
    )
    
    $cacheFile = Join-Path $script:PoshifyCachePath "themes_cache.json"
    $cacheInfoFile = Join-Path $script:PoshifyCachePath "themes_cache_info.json"
    
    # Check if cache is valid
    $useCache = $false
    if (-not $ForceRefresh -and (Test-Path $cacheFile) -and (Test-Path $cacheInfoFile)) {
        try {
            $cacheInfo = Get-Content $cacheInfoFile -Raw | ConvertFrom-Json
            $cacheAge = (Get-Date) - $cacheInfo.CachedAt
            
            if ($cacheAge.TotalMinutes -lt $script:CacheDurationMinutes) {
                $useCache = $true
                Write-Verbose "Using cached theme data (age: $($cacheAge.TotalMinutes.ToString('0.0')) minutes)"
            }
        }
        catch {
            Write-Verbose "Cache file corrupted, will fetch fresh data"
        }
    }
    
    if ($useCache) {
        return Get-Content $cacheFile -Raw | ConvertFrom-Json
    }
    
    # Fetch fresh data
    Write-Host "Fetching themes from GitHub..." -ForegroundColor Cyan
    
    try {
        $response = Invoke-RestMethod -Uri $script:OhMyPoshGitHubThemesUrl -Method Get -ErrorAction Stop
        
        # Update rate limit info
        Update-PoshifyRateLimit -Response $response
        
        $themes = $response | Where-Object { $_.name -like "*.omp.json" } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name -replace '\.omp\.json$', ''
                FileName = $_.name
                DownloadUrl = $_.download_url
                Size = [math]::Round($_.size / 1KB, 2)
                GitUrl = $_.git_url
                Sha = $_.sha
            }
        }
        
        # Save to cache
        $themes | ConvertTo-Json -Depth 3 | Set-Content $cacheFile -Force
        @{ CachedAt = Get-Date; Count = $themes.Count } | ConvertTo-Json | Set-Content $cacheInfoFile -Force
        
        Write-Verbose "Cached $($themes.Count) themes"
        return $themes
    }
    catch {
        Write-Error "Failed to fetch themes: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Internal helper to load favorites
#>
function Get-PoshifyFavorites {
    if (Test-Path $script:PoshifyFavoritesPath) {
        try {
            return Get-Content $script:PoshifyFavoritesPath -Raw | ConvertFrom-Json
        }
        catch {
            return @()
        }
    }
    return @()
}

<#
.SYNOPSIS
    Internal helper to save favorites
#>
function Save-PoshifyFavorites {
    param(
        $Favorites
    )
    
    $Favorites | ConvertTo-Json | Set-Content $script:PoshifyFavoritesPath -Force
}

<#
.SYNOPSIS
    Internal helper to get current theme info
#>
function Get-PoshifyCurrentThemeInfo {
    $profilePath = $PROFILE.CurrentUserAllHosts
    
    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        
        if ($content -match 'oh-my-posh init \w+ --config ["'']([^"'']+)["'']') {
            $themePath = $matches[1]
            
            if (Test-Path $themePath) {
                return @{
                    Path = $themePath
                    Name = (Get-Item $themePath).BaseName
                    IsCustom = $themePath -notlike "$script:PoshifyThemesPath*"
                }
            }
            else {
                return @{
                    Path = $themePath
                    Name = "Unknown (file not found)"
                    IsCustom = $true
                }
            }
        }
    }
    
    return $null
}

#endregion Helper Functions

<#
.SYNOPSIS
    Gets available local oh-my-posh themes

.DESCRIPTION
    Lists all oh-my-posh theme files available in the local themes directory.
    Can also show detailed information about specific themes including size and last modified date.

.PARAMETER Name
    Optional. Filter themes by name (supports wildcards)

.PARAMETER Detailed
    Show detailed information including file size and last modified date

.EXAMPLE
    Get-PoshifyTheme
    Lists all available local themes

.EXAMPLE
    Get-PoshifyTheme -Name "agnoster"
    Gets information about a specific theme

.EXAMPLE
    Get-PoshifyTheme -Detailed
    Shows detailed information about all themes

.OUTPUTS
    System.IO.FileInfo[] or PSCustomObject
#>
function Get-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,
        
        [switch]$Detailed
    )

    try {
        Initialize-PoshifyDirectories
        
        # Get theme files
        $themeFiles = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ".cache*" -and $_.Name -notlike ".favorites*" }

        if ($Name) {
            $themeFiles = $themeFiles | Where-Object { $_.BaseName -like "*$Name*" }
            
            if (-not $themeFiles) {
                Write-Error "Theme '$Name' not found in local themes directory"
                return
            }
        }

        if (-not $themeFiles -or $themeFiles.Count -eq 0) {
            Write-Host "No themes found in: $script:PoshifyThemesPath" -ForegroundColor Yellow
            Write-Host "Use Find-PoshifyTheme to discover and Install-PoshifyTheme to download themes" -ForegroundColor Cyan
            return
        }

        if ($Detailed) {
            $themes = $themeFiles | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.BaseName
                    FileName = $_.Name
                    Path = $_.FullName
                    SizeKB = [math]::Round($_.Length / 1KB, 2)
                    LastModified = $_.LastWriteTime
                    Created = $_.CreationTime
                }
            }
            
            Write-Host "Local themes (detailed view):" -ForegroundColor Green
            return $themes
        }
        else {
            Write-Host "Available local themes ($($themeFiles.Count)):" -ForegroundColor Green
            return $themeFiles
        }
    }
    catch {
        Write-Error "Failed to get themes: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Finds oh-my-posh themes available online

.DESCRIPTION
    Lists all oh-my-posh themes available in the official GitHub repository.
    Uses caching to improve performance and respects GitHub API rate limits.

.PARAMETER Name
    Optional. Filter themes by name (supports wildcards)

.PARAMETER ForceRefresh
    Force refresh of cached data

.EXAMPLE
    Find-PoshifyTheme
    Lists all available online themes

.EXAMPLE
    Find-PoshifyTheme -Name "agnoster"
    Searches for themes containing "agnoster" in their name

.EXAMPLE
    Find-PoshifyTheme -ForceRefresh
    Fetches fresh data from GitHub, bypassing cache

.OUTPUTS
    PSCustomObject[]
#>
function Find-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,
        
        [switch]$ForceRefresh
    )

    try {
        # Check rate limit
        if (-not (Test-PoshifyRateLimit)) {
            Write-Warning "GitHub API rate limit reached. Using cached data if available."
            if (-not $ForceRefresh) {
                $ForceRefresh = $false
            }
        }
        
        # Get themes (from cache or fresh)
        $themes = Get-PoshifyCachedThemes -ForceRefresh:$ForceRefresh
        
        if (-not $themes) {
            return
        }

        if ($Name) {
            $themes = $themes | Where-Object { $_.Name -like "*$Name*" }
            if ($themes.Count -eq 0) {
                Write-Warning "No themes found matching '$Name'"
                return
            }
        }

        Write-Host "Found $($themes.Count) themes available online:" -ForegroundColor Green
        return $themes
    }
    catch {
        Write-Error "Failed to fetch themes from GitHub: $($_.Exception.Message)"
        Write-Host "Make sure you have internet connectivity and GitHub is accessible" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Installs an oh-my-posh theme

.DESCRIPTION
    Downloads and saves a theme from the official oh-my-posh repository

.PARAMETER Name
    The name of the theme to install

.EXAMPLE
    Install-PoshifyTheme -Name "agnoster"
    Downloads and installs the agnoster theme

.EXAMPLE
    Install-PoshifyTheme -Name "powerlevel10k_rainbow"
    Downloads and installs the powerlevel10k_rainbow theme

.OUTPUTS
    System.IO.FileInfo
#>
function Install-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )

    try {
        # Ensure themes directory exists
        if (-not (Test-Path $script:PoshifyThemesPath)) {
            New-Item -ItemType Directory -Path $script:PoshifyThemesPath -Force | Out-Null
        }

        # Check if theme already exists locally
        $existingTheme = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$Name*.omp.json" -ErrorAction SilentlyContinue
        if ($existingTheme) {
            Write-Warning "Theme '$Name' already exists locally"
            Write-Host "Use Get-PoshifyTheme to see all local themes" -ForegroundColor Yellow
            return $existingTheme
        }

        Write-Host "Searching for theme '$Name' online..." -ForegroundColor Cyan
        
        # Find the theme online
        $onlineThemes = Find-PoshifyTheme -Name $Name
        if (-not $onlineThemes) {
            Write-Error "Theme '$Name' not found online"
            return
        }

        # If multiple matches, let user choose
        $selectedTheme = if ($onlineThemes.Count -gt 1) {
            Write-Host "Multiple themes found matching '$Name':" -ForegroundColor Yellow
            for ($i = 0; $i -lt $onlineThemes.Count; $i++) {
                Write-Host "  [$i] $($onlineThemes[$i].Name)" -ForegroundColor Cyan
            }
            $choice = Read-Host "Select theme number (0-$($onlineThemes.Count-1))"
            $onlineThemes[$choice]
        } else {
            $onlineThemes[0]
        }

        # Download the theme
        Write-Host "Downloading theme '$($selectedTheme.Name)'..." -ForegroundColor Green
        $themePath = Join-Path $script:PoshifyThemesPath $selectedTheme.FileName
        
        Invoke-WebRequest -Uri $selectedTheme.DownloadUrl -OutFile $themePath -ErrorAction Stop
        
        if (Test-Path $themePath) {
            Write-Host "Theme '$($selectedTheme.Name)' installed successfully!" -ForegroundColor Green
            Write-Host "Theme location: $themePath" -ForegroundColor Cyan
            return Get-Item $themePath
        } else {
            Write-Error "Theme download failed - file not found after download"
        }
    }
    catch {
        Write-Error "Failed to install theme '$Name': $($_.Exception.Message)"
        Write-Host "Make sure you have internet connectivity and the theme name is correct" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Sets the current oh-my-posh theme

.DESCRIPTION
    Applies a theme by updating the user's PowerShell profile and calling oh-my-posh init

.PARAMETER Name
    The name of the theme to apply

.PARAMETER ThemePath
    Optional direct path to a theme file

.EXAMPLE
    Set-PoshifyTheme -Name "agnoster"
    Sets the agnoster theme as the current prompt

.EXAMPLE
    Set-PoshifyTheme -ThemePath "C:\path\to\custom.omp.json"
    Sets a custom theme file as the current prompt

.OUTPUTS
    None
#>
function Set-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = "ByName", Position = 0)]
        [string]$Name,
        
        [Parameter(ParameterSetName = "ByPath")]
        [string]$ThemePath
    )

    try {
        # Determine theme file path
        $themeFile = if ($PSCmdlet.ParameterSetName -eq "ByPath") {
            if (-not (Test-Path $ThemePath)) {
                Write-Error "Theme file not found: $ThemePath"
                return
            }
            Get-Item $ThemePath
        } else {
            # Find theme by name
            $localThemes = Get-PoshifyTheme -Name $Name
            if (-not $localThemes) {
                Write-Error "Theme '$Name' not found locally"
                Write-Host "Use Find-PoshifyTheme to discover themes and Install-PoshifyTheme to download them" -ForegroundColor Yellow
                return
            }
            $localThemes[0]
        }

        # Check if oh-my-posh is installed
        $ohMyPosh = Get-Command oh-my-posh -ErrorAction SilentlyContinue
        if (-not $ohMyPosh) {
            Write-Error "oh-my-posh is not installed or not in PATH"
            Write-Host "Install oh-my-posh from: https://ohmyposh.dev/docs/installation" -ForegroundColor Yellow
            return
        }

        # Backup current profile if it exists
        $profilePath = $PROFILE.CurrentUserAllHosts
        if (Test-Path $profilePath) {
            Write-Host "Backing up current profile..." -ForegroundColor Cyan
            Copy-Item -Path $profilePath -Destination $script:ProfileBackupPath -Force
        }

        # Create or update profile
        Write-Host "Setting theme to '$($themeFile.BaseName)'..." -ForegroundColor Green
        
        $profileContent = @"
# Poshify Theme - Generated by Poshify Module
# Theme: $($themeFile.BaseName)
# Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

oh-my-posh init pwsh --config "$($themeFile.FullName)" | Invoke-Expression
"@

        # Add to profile
        if (Test-Path $profilePath) {
            # Remove existing Poshify entries
            $existingContent = Get-Content $profilePath -Raw
            $existingContent = $existingContent -replace '# Poshify Theme - Generated by Poshify Module[\s\S]*?(?=\n#|\noh-my-posh init|\n\$|\nfunction|\nSet-|\nWrite-|\nif|\nImport-Module|\n$)', ''
            $existingContent = $existingContent.TrimEnd()
            
            if ($existingContent) {
                $profileContent = "$existingContent`n`n$profileContent"
            }
        }

        Set-Content -Path $profilePath -Value $profileContent -Force
        
        Write-Host "Theme set successfully!" -ForegroundColor Green
        Write-Host "Theme file: $($themeFile.FullName)" -ForegroundColor Cyan
        Write-Host "Profile updated: $profilePath" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Yellow
        Write-Host "To apply the theme immediately, restart PowerShell or run:" -ForegroundColor Yellow
        Write-Host "  oh-my-posh init pwsh --config `"$($themeFile.FullName)`" | Invoke-Expression" -ForegroundColor Cyan
        
    }
    catch {
        Write-Error "Failed to set theme: $($_.Exception.Message)"
        Write-Host "Make sure you have write permissions to your PowerShell profile" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Resets the PowerShell prompt to default

.DESCRIPTION
    Removes oh-my-posh configuration from the user's PowerShell profile
and restores the default PowerShell prompt

.EXAMPLE
    Reset-PoshifyTheme
    Resets the prompt to default PowerShell appearance

.OUTPUTS
    None
#>
function Reset-PoshifyTheme {
    [CmdletBinding()]
    param()

    try {
        $profilePath = $PROFILE.CurrentUserAllHosts
        
        if (-not (Test-Path $profilePath)) {
            Write-Host "No PowerShell profile found - prompt is already default" -ForegroundColor Yellow
            return
        }

        # Read current profile
        $profileContent = Get-Content $profilePath -Raw
        
        # Check if Poshify theme is configured
        if ($profileContent -notmatch '# Poshify Theme - Generated by Poshify Module') {
            Write-Host "No Poshify theme configuration found in profile" -ForegroundColor Yellow
            
            # Check for any oh-my-posh configuration
            if ($profileContent -match 'oh-my-posh init') {
                Write-Warning "Found oh-my-posh configuration in profile, but it's not managed by Poshify"
                $confirm = Read-Host "Do you want to remove all oh-my-posh configuration? (y/N)"
                if ($confirm -ne 'y') {
                    return
                }
                
                # Remove all oh-my-posh lines
                $profileContent = $profileContent -replace 'oh-my-posh init[\s\S]*?\n', "`n"
                $profileContent = $profileContent -replace '\n{3,}', "`n`n"
                $profileContent = $profileContent.Trim()
                
                Set-Content -Path $profilePath -Value $profileContent -Force
                Write-Host "All oh-my-posh configuration removed from profile" -ForegroundColor Green
            } else {
                Write-Host "Prompt is already using default PowerShell configuration" -ForegroundColor Green
            }
            return
        }

        # Restore backup if available
        if (Test-Path $script:ProfileBackupPath) {
            Write-Host "Restoring profile from backup..." -ForegroundColor Cyan
            Copy-Item -Path $script:ProfileBackupPath -Destination $profilePath -Force
            Remove-Item -Path $script:ProfileBackupPath -Force -ErrorAction SilentlyContinue
            Write-Host "Profile restored from backup" -ForegroundColor Green
        } else {
            # Remove Poshify configuration
            Write-Host "Removing Poshify theme configuration..." -ForegroundColor Cyan
            $profileContent = $profileContent -replace '# Poshify Theme - Generated by Poshify Module[\s\S]*?(?=\n#|\n\$|\nfunction|\nSet-|\nWrite-|\nif|\nImport-Module|\n$)', ''
            $profileContent = $profileContent.TrimEnd()
            
            Set-Content -Path $profilePath -Value $profileContent -Force
            Write-Host "Poshify theme configuration removed" -ForegroundColor Green
        }

        Write-Host "PowerShell prompt reset to default" -ForegroundColor Green
        Write-Host "Restart PowerShell to see the changes" -ForegroundColor Yellow
        
    }
    catch {
        Write-Error "Failed to reset theme: $($_.Exception.Message)"
        Write-Host "Make sure you have write permissions to your PowerShell profile" -ForegroundColor Yellow
    }
}

<#
.SYNOPSIS
    Gets the currently active oh-my-posh theme

.DESCRIPTION
    Detects and returns information about the currently configured oh-my-posh theme
    by examining the PowerShell profile.

.EXAMPLE
    Get-PoshifyCurrentTheme
    Shows the current theme information

.OUTPUTS
    PSCustomObject or null if no theme is configured
#>
function Get-PoshifyCurrentTheme {
    [CmdletBinding()]
    param()
    
    try {
        $currentInfo = Get-PoshifyCurrentThemeInfo
        
        if ($currentInfo) {
            Write-Host "Current theme:" -ForegroundColor Green
            $themeInfo = [PSCustomObject]@{
                Name = $currentInfo.Name
                Path = $currentInfo.Path
                IsCustom = $currentInfo.IsCustom
                Source = if ($currentInfo.IsCustom) { "Custom" } else { "Poshify" }
            }
            return $themeInfo
        }
        else {
            Write-Host "No oh-my-posh theme is currently configured" -ForegroundColor Yellow
            Write-Host "Use 'Set-PoshifyTheme' to apply a theme" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Error "Failed to get current theme: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Removes an installed oh-my-posh theme

.DESCRIPTION
    Deletes a theme file from the local themes directory

.PARAMETER Name
    The name of the theme to remove (required)

.PARAMETER Force
    Skip confirmation prompt

.EXAMPLE
    Remove-PoshifyTheme -Name "agnoster"
    Removes the agnoster theme with confirmation

.EXAMPLE
    Remove-PoshifyTheme -Name "agnoster" -Force
    Removes the agnoster theme without confirmation

.OUTPUTS
    None
#>
function Remove-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        Initialize-PoshifyDirectories
        
        $themeFile = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$Name*.omp.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ".cache*" -and $_.Name -notlike ".favorites*" }
        
        if (-not $themeFile) {
            Write-Error "Theme '$Name' not found in local themes directory"
            return
        }
        
        if ($themeFile.Count -gt 1) {
            Write-Warning "Multiple themes match '$Name':"
            $themeFile | ForEach-Object { Write-Host "  - $($_.BaseName)" }
            Write-Host "Please specify a more specific name" -ForegroundColor Yellow
            return
        }
        
        # Check if this is the current theme
        $currentInfo = Get-PoshifyCurrentThemeInfo
        if ($currentInfo -and $currentInfo.Path -eq $themeFile.FullName) {
            Write-Warning "This theme is currently active!"
            if (-not $Force) {
                $confirm = Read-Host "Continue anyway? (y/N)"
                if ($confirm -ne 'y') {
                    return
                }
            }
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess("Theme '$($themeFile.BaseName)'", "Remove")) {
            Remove-Item -Path $themeFile.FullName -Force
            Write-Host "Theme '$($themeFile.BaseName)' removed successfully" -ForegroundColor Green
            
            # Clear cache to force refresh on next find
            $cacheFile = Join-Path $script:PoshifyCachePath "themes_cache.json"
            if (Test-Path $cacheFile) {
                Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Error "Failed to remove theme: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Updates an installed oh-my-posh theme

.DESCRIPTION
    Re-downloads a theme from the official repository to get the latest version

.PARAMETER Name
    The name of the theme to update (required)

.PARAMETER All
    Update all installed themes

.EXAMPLE
    Update-PoshifyTheme -Name "agnoster"
    Updates the agnoster theme

.EXAMPLE
    Update-PoshifyTheme -All
    Updates all installed themes

.OUTPUTS
    None
#>
function Update-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,
        
        [switch]$All
    )
    
    try {
        Initialize-PoshifyDirectories
        
        if ($All) {
            $themes = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike ".cache*" -and $_.Name -notlike ".favorites*" }
            
            if (-not $themes) {
                Write-Host "No themes installed to update" -ForegroundColor Yellow
                return
            }
            
            Write-Host "Updating $($themes.Count) themes..." -ForegroundColor Cyan
            foreach ($theme in $themes) {
                Write-Host "Updating $($theme.BaseName)..." -ForegroundColor Cyan
                & $MyInvocation.MyCommand.Name -Name $theme.BaseName -Verbose:$false
            }
            Write-Host "All themes updated!" -ForegroundColor Green
            return
        }
        
        if (-not $Name) {
            Write-Error "Either -Name or -All parameter is required"
            return
        }
        
        $themeFile = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$Name*.omp.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ".cache*" -and $_.Name -notlike ".favorites*" }
        
        if (-not $themeFile) {
            Write-Error "Theme '$Name' not found locally. Use Install-PoshifyTheme to install it first"
            return
        }
        
        if ($themeFile.Count -gt 1) {
            Write-Warning "Multiple themes match '$Name'. Please specify a more specific name"
            return
        }
        
        Write-Host "Checking for updates for '$Name'..." -ForegroundColor Cyan
        
        # Get online theme info
        $onlineThemes = Get-PoshifyCachedThemes -ForceRefresh
        $onlineTheme = $onlineThemes | Where-Object { $_.Name -eq $themeFile.BaseName }
        
        if (-not $onlineTheme) {
            Write-Warning "Theme '$Name' not found in online repository. It may have been renamed or removed."
            return
        }
        
        # Compare sizes as a simple check (GitHub SHA would be more accurate but requires more API calls)
        $localSize = $themeFile.Length
        $onlineSize = (Invoke-WebRequest -Uri $onlineTheme.DownloadUrl -Method Head -UseBasicParsing).Headers.'Content-Length'
        
        if ([int]$localSize -eq [int]$onlineSize) {
            Write-Host "Theme '$Name' is already up to date" -ForegroundColor Green
            return
        }
        
        # Download updated theme
        $backupPath = "$($themeFile.FullName).bak"
        Copy-Item -Path $themeFile.FullName -Destination $backupPath -Force
        
        try {
            Invoke-WebRequest -Uri $onlineTheme.DownloadUrl -OutFile $themeFile.FullName -ErrorAction Stop
            Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            Write-Host "Theme '$Name' updated successfully!" -ForegroundColor Green
        }
        catch {
            Write-Warning "Update failed, restoring backup"
            Copy-Item -Path $backupPath -Destination $themeFile.FullName -Force
            Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            throw
        }
    }
    catch {
        Write-Error "Failed to update theme: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Adds a theme to favorites

.DESCRIPTION
    Saves a theme name to the favorites list for quick access

.PARAMETER Name
    The name of the theme to add to favorites

.EXAMPLE
    Add-PoshifyFavorite -Name "agnoster"
    Adds agnoster to favorites

.OUTPUTS
    None
#>
function Add-PoshifyFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )
    
    try {
        Initialize-PoshifyDirectories
        
        $favorites = Get-PoshifyFavorites
        
        if ($favorites -contains $Name) {
            Write-Host "Theme '$Name' is already in favorites" -ForegroundColor Yellow
            return
        }
        
        $favorites += $Name
        Save-PoshifyFavorites -Favorites $favorites
        Write-Host "Added '$Name' to favorites" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to add favorite: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Removes a theme from favorites

.DESCRIPTION
    Removes a theme name from the favorites list

.PARAMETER Name
    The name of the theme to remove from favorites

.EXAMPLE
    Remove-PoshifyFavorite -Name "agnoster"
    Removes agnoster from favorites

.OUTPUTS
    None
#>
function Remove-PoshifyFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )
    
    try {
        $favorites = Get-PoshifyFavorites
        
        if ($favorites -notcontains $Name) {
            Write-Host "Theme '$Name' is not in favorites" -ForegroundColor Yellow
            return
        }
        
        $favorites = $favorites | Where-Object { $_ -ne $Name }
        Save-PoshifyFavorites -Favorites $favorites
        Write-Host "Removed '$Name' from favorites" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove favorite: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Gets the list of favorite themes

.DESCRIPTION
    Returns the list of themes marked as favorites

.EXAMPLE
    Get-PoshifyFavorite
    Lists all favorite themes

.OUTPUTS
    String[]
#>
function Get-PoshifyFavorite {
    [CmdletBinding()]
    param()
    
    try {
        $favorites = Get-PoshifyFavorites
        
        if (-not $favorites -or $favorites.Count -eq 0) {
            Write-Host "No favorite themes configured" -ForegroundColor Yellow
            Write-Host "Use Add-PoshifyFavorite to add themes to your favorites" -ForegroundColor Cyan
            return
        }
        
        Write-Host "Favorite themes ($($favorites.Count)):" -ForegroundColor Green
        return $favorites
    }
    catch {
        Write-Error "Failed to get favorites: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Applies a random theme from installed or favorite themes

.DESCRIPTION
    Selects and applies a random theme, optionally from favorites only

.PARAMETER FromFavorites
    Only choose from favorite themes

.EXAMPLE
    Get-PoshifyRandomTheme
    Applies a random theme from all installed themes

.EXAMPLE
    Get-PoshifyRandomTheme -FromFavorites
    Applies a random theme from favorites

.OUTPUTS
    None
#>
function Get-PoshifyRandomTheme {
    [CmdletBinding()]
    param(
        [switch]$FromFavorites
    )
    
    try {
        if ($FromFavorites) {
            $favorites = Get-PoshifyFavorites
            
            if (-not $favorites -or $favorites.Count -eq 0) {
                Write-Error "No favorite themes configured. Add some with Add-PoshifyFavorite"
                return
            }
            
            $selectedName = $favorites | Get-Random
            $themeFile = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$selectedName*.omp.json" -ErrorAction SilentlyContinue
            
            if (-not $themeFile) {
                Write-Warning "Favorite theme '$selectedName' not found locally. Installing..."
                Install-PoshifyTheme -Name $selectedName
                $themeFile = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$selectedName*.omp.json" -ErrorAction SilentlyContinue
            }
        }
        else {
            $themes = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike ".cache*" -and $_.Name -notlike ".favorites*" }
            
            if (-not $themes) {
                Write-Error "No themes installed. Use Find-PoshifyTheme and Install-PoshifyTheme to get themes"
                return
            }
            
            $themeFile = $themes | Get-Random
        }
        
        Write-Host "Selected random theme: $($themeFile.BaseName)" -ForegroundColor Cyan
        Set-PoshifyTheme -Name $themeFile.BaseName
    }
    catch {
        Write-Error "Failed to apply random theme: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Previews a theme by displaying its configuration summary

.DESCRIPTION
    Shows basic information about a theme including colors and segments

.PARAMETER Name
    The name of the theme to preview

.EXAMPLE
    Test-PoshifyTheme -Name "agnoster"
    Shows information about the agnoster theme

.OUTPUTS
    PSCustomObject
#>
function Test-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name
    )
    
    try {
        $themeFile = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*$Name*.omp.json" -ErrorAction SilentlyContinue
        
        if (-not $themeFile) {
            Write-Error "Theme '$Name' not found locally"
            return
        }
        
        Write-Host "Theme Preview: $($themeFile.BaseName)" -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Gray
        Write-Host "File: $($themeFile.Name)"
        Write-Host "Size: $([math]::Round($themeFile.Length / 1KB, 2)) KB"
        Write-Host "Modified: $($themeFile.LastWriteTime)"
        Write-Host ""
        
        # Try to read and display basic theme info
        try {
            $themeContent = Get-Content $themeFile.FullName -Raw | ConvertFrom-Json
            
            Write-Host "Theme Information:" -ForegroundColor Green
            if ($themeContent.author) {
                Write-Host "  Author: $($themeContent.author)"
            }
            if ($themeContent.console_title_template) {
                Write-Host "  Has custom title template: Yes"
            }
            if ($themeContent.blocks) {
                Write-Host "  Blocks: $($themeContent.blocks.Count)"
                $segmentCount = ($themeContent.blocks | ForEach-Object { $_.segments.Count } | Measure-Object -Sum).Sum
                Write-Host "  Total segments: $segmentCount"
            }
            if ($themeContent.final_space) {
                Write-Host "  Final space: Yes"
            }
        }
        catch {
            Write-Host "  (Unable to parse theme details)" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Host "To apply this theme, run: Set-PoshifyTheme -Name '$($themeFile.BaseName)'" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to preview theme: $($_.Exception.Message)"
    }
}

# Create CLI-friendly aliases for common operations
New-Alias -Name 'poshify-theme-get' -Value 'Get-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-find' -Value 'Find-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-install' -Value 'Install-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-set' -Value 'Set-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-reset' -Value 'Reset-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-current' -Value 'Get-PoshifyCurrentTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-remove' -Value 'Remove-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-update' -Value 'Update-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-add' -Value 'Add-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-remove' -Value 'Remove-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-get' -Value 'Get-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-random' -Value 'Get-PoshifyRandomTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-test' -Value 'Test-PoshifyTheme' -ErrorAction SilentlyContinue

# Create a main Poshify command that acts as a CLI utility
function Poshify {
    <#
    .SYNOPSIS
        Main Poshify CLI utility command
    
    .DESCRIPTION
        Provides a command-line interface for managing oh-my-posh themes
        
    .EXAMPLE
        Poshify theme install agnoster
        Downloads and installs the agnoster theme
        
    .EXAMPLE
        Poshify theme list
        Lists all available local themes
        
    .EXAMPLE
        Poshify theme find
        Finds available themes online
        
    .EXAMPLE
        Poshify theme set agnoster
        Sets the agnoster theme as current
        
    .EXAMPLE
        Poshify theme reset
        Resets theme to default PowerShell prompt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet('theme')]
        [string]$Command,
        
        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateSet('list', 'find', 'install', 'set', 'reset')]
        [string]$Action,
        
        [Parameter(Position = 2)]
        [string]$ThemeName
    )

    switch ($Action) {
        'list' {
            Get-PoshifyTheme
        }
        'find' {
            if ($ThemeName) {
                Find-PoshifyTheme -Name $ThemeName
            } else {
                Find-PoshifyTheme
            }
        }
        'install' {
            if (-not $ThemeName) {
                Write-Error "Theme name is required for install action"
                Write-Host "Usage: Poshify theme install <theme-name>" -ForegroundColor Yellow
                return
            }
            Install-PoshifyTheme -Name $ThemeName
        }
        'set' {
            if (-not $ThemeName) {
                Write-Error "Theme name is required for set action"
                Write-Host "Usage: Poshify theme set <theme-name>" -ForegroundColor Yellow
                return
            }
            Set-PoshifyTheme -Name $ThemeName
        }
        'reset' {
            Reset-PoshifyTheme
        }
        default {
            Write-Error "Unknown action: $Action"
            Write-Host "Available actions: list, find, install, set, reset" -ForegroundColor Yellow
        }
    }
}

# Export module functions and aliases
Export-ModuleMember -Function @(
    'Get-PoshifyTheme',
    'Find-PoshifyTheme', 
    'Install-PoshifyTheme',
    'Set-PoshifyTheme',
    'Reset-PoshifyTheme',
    'Poshify'
) -Alias @(
    'poshify-theme-get',
    'poshify-theme-find',
    'poshify-theme-install',
    'poshify-theme-set',
    'poshify-theme-reset'
)