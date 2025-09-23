<#
.SYNOPSIS
    Poshify - A PowerShell module for managing oh-my-posh themes

.DESCRIPTION
    This module provides functions to manage oh-my-posh themes including listing,
    installing, and switching between themes.

.NOTES
    Author: Poshify Module
    Version: 1.0.0
#>

# Module variables
$script:PoshifyThemesPath = Join-Path $env:USERPROFILE ".poshthemes"
$script:OhMyPoshGitHubThemesUrl = "https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes"
$script:ProfileBackupPath = Join-Path $env:USERPROFILE ".poshthemes\.profile_backup"

<#
.SYNOPSIS
    Gets available local oh-my-posh themes

.DESCRIPTION
    Lists all oh-my-posh theme files available in the local themes directory

.EXAMPLE
    Get-PoshifyTheme
    Lists all available local themes

.EXAMPLE
    Get-PoshifyTheme -Name "agnoster"
    Gets information about a specific theme

.OUTPUTS
    System.IO.FileInfo[]
#>
function Get-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    try {
        # Ensure themes directory exists
        if (-not (Test-Path $script:PoshifyThemesPath)) {
            Write-Warning "Themes directory not found at: $script:PoshifyThemesPath"
            Write-Host "Creating themes directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $script:PoshifyThemesPath -Force | Out-Null
        }

        # Get theme files
        $themeFiles = Get-ChildItem -Path $script:PoshifyThemesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue

        if ($Name) {
            $theme = $themeFiles | Where-Object { $_.BaseName -like "*$Name*" }
            if (-not $theme) {
                Write-Error "Theme '$Name' not found in local themes directory"
                return
            }
            return $theme
        }

        if ($themeFiles.Count -eq 0) {
            Write-Host "No themes found in: $script:PoshifyThemesPath" -ForegroundColor Yellow
            Write-Host "Use Find-PoshifyTheme to discover and Install-PoshifyTheme to download themes" -ForegroundColor Cyan
            return
        }

        Write-Host "Available local themes:" -ForegroundColor Green
        return $themeFiles
    }
    catch {
        Write-Error "Failed to get themes: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Finds oh-my-posh themes available online

.DESCRIPTION
    Lists all oh-my-posh themes available in the official GitHub repository

.EXAMPLE
    Find-PoshifyTheme
    Lists all available online themes

.EXAMPLE
    Find-PoshifyTheme -Name "agnoster"
    Searches for themes containing "agnoster" in their name

.OUTPUTS
    PSCustomObject[]
#>
function Find-PoshifyTheme {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    try {
        Write-Host "Fetching available themes from oh-my-posh GitHub repository..." -ForegroundColor Cyan
        
        # Fetch themes from GitHub API
        $response = Invoke-RestMethod -Uri $script:OhMyPoshGitHubThemesUrl -Method Get -ErrorAction Stop
        
        # Filter for JSON theme files
        $themes = $response | Where-Object { $_.name -like "*.omp.json" } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name -replace '\.omp\.json$', ''
                FileName = $_.name
                DownloadUrl = $_.download_url
                Size = [math]::Round($_.size / 1KB, 2)
                LastModified = $_.git_url
            }
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

# Create CLI-friendly aliases for common operations
New-Alias -Name 'poshify-theme-get' -Value 'Get-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-find' -Value 'Find-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-install' -Value 'Install-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-set' -Value 'Set-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-theme-reset' -Value 'Reset-PoshifyTheme' -ErrorAction SilentlyContinue

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