<#
.SYNOPSIS
    Poshify - A PowerShell module for managing oh-my-posh themes

.DESCRIPTION
    This module provides functions to list, install, update, remove, preview and switch between
    oh-my-posh themes, and to keep a list of favorite themes.

    Poshify adds a single marked block to your PowerShell profile that loads whichever theme
    is currently selected. Switching themes only changes that selection, so the rest of your
    profile is never rewritten.
#>

# Module variables
$script:PoshifyHome = Join-Path $HOME '.poshthemes'
$script:OhMyPoshGitHubThemesUrl = 'https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes'
$script:ThemeFilePattern = '\.omp\.(json|ya?ml|toml)$'
$script:ProfileBlockStart = '# >>> poshify >>>'
$script:ProfileBlockEnd = '# <<< poshify <<<'
$script:CacheMaxAge = [TimeSpan]::FromMinutes(60)

# Show a compact table by default; the remaining properties are still on the objects
Update-TypeData -TypeName 'Poshify.Theme' -DefaultDisplayPropertySet 'Name', 'Source', 'Current', 'Favorite' -Force
Update-TypeData -TypeName 'Poshify.OnlineTheme' -DefaultDisplayPropertySet 'Name', 'SizeKB' -Force

#region Private helpers

function Get-PoshifyProfilePath {
    $PROFILE.CurrentUserAllHosts
}

function Get-OhMyPoshCommand {
    Get-Command -Name oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Invoke-OhMyPosh {
    param([string[]]$ArgumentList)
    & (Get-OhMyPoshCommand) @ArgumentList
}

# File that holds the full path of the selected theme; read by the profile block at startup
function Get-PoshifyCurrentThemeFile {
    Join-Path $script:PoshifyHome 'current'
}

function Get-PoshifyCacheFile {
    Join-Path $script:PoshifyHome '.cache/themes.json'
}

function Get-PoshifyFavoritesFile {
    Join-Path $script:PoshifyHome '.favorites.json'
}

function Get-PoshifyCurrentThemePath {
    $file = Get-PoshifyCurrentThemeFile
    if (Test-Path -LiteralPath $file) {
        Get-Content -LiteralPath $file -TotalCount 1
    }
}

function Get-PoshifyThemeName {
    param([string]$FileName)
    $FileName -replace $script:ThemeFilePattern, ''
}

# Directories searched for themes, in priority order. Themes downloaded by Poshify shadow
# the ones bundled with oh-my-posh (POSH_THEMES_PATH), which may not exist on every install.
function Get-PoshifyThemeSource {
    [PSCustomObject]@{ Name = 'Poshify'; Path = $script:PoshifyHome }
    if ($env:POSH_THEMES_PATH) {
        [PSCustomObject]@{ Name = 'oh-my-posh'; Path = $env:POSH_THEMES_PATH }
    }
}

function ConvertTo-PoshifyThemeObject {
    param(
        [System.IO.FileInfo]$File,
        [string]$Source,
        [string]$CurrentPath,
        [string[]]$Favorites
    )

    $name = Get-PoshifyThemeName $File.Name
    [PSCustomObject]@{
        PSTypeName   = 'Poshify.Theme'
        Name         = $name
        Source       = $Source
        Current      = $File.FullName -eq $CurrentPath
        Favorite     = $name -in $Favorites
        SizeKB       = [math]::Round($File.Length / 1KB, 2)
        LastModified = $File.LastWriteTime
        Path         = $File.FullName
    }
}

function ConvertTo-PoshifyOnlineTheme {
    param($Entry)

    [PSCustomObject]@{
        PSTypeName  = 'Poshify.OnlineTheme'
        Name        = Get-PoshifyThemeName $Entry.name
        FileName    = $Entry.name
        SizeKB      = [math]::Round($Entry.size / 1KB, 2)
        DownloadUrl = $Entry.download_url
        Sha         = $Entry.sha
    }
}

# Exact name match wins; otherwise wildcards are honoured and plain text is a substring search
function Select-PoshifyThemeMatch {
    param(
        [object[]]$Theme,
        [string]$Name
    )

    $exact = @($Theme | Where-Object { $_.Name -eq $Name })
    if ($exact.Count -gt 0) {
        return $exact
    }

    $pattern = if ([WildcardPattern]::ContainsWildcardCharacters($Name)) { $Name } else { "*$Name*" }
    @($Theme | Where-Object { $_.Name -like $pattern })
}

function Resolve-PoshifySingleTheme {
    param(
        [object[]]$Match,
        [string]$Name,
        [string]$Location
    )

    if ($Match.Count -eq 1) {
        return $Match[0]
    }

    if ($Match.Count -eq 0) {
        Write-Error -Message "Theme '$Name' not found $Location." -Category ObjectNotFound -TargetObject $Name
        return
    }

    $names = ($Match | Select-Object -First 10 -ExpandProperty Name) -join ', '
    if ($Match.Count -gt 10) {
        $names += ", ... ($($Match.Count) total)"
    }
    Write-Error -Message "Theme name '$Name' is ambiguous $Location. Matches: $names" -Category InvalidArgument -TargetObject $Name
}

# Resolves -Name or -ThemePath to an object with Name and Path, writing an error if that fails
function Resolve-PoshifyThemeFile {
    param(
        [string]$Name,
        [string]$ThemePath
    )

    if ($ThemePath) {
        $item = Get-Item -LiteralPath $ThemePath -ErrorAction SilentlyContinue
        if (-not $item -or $item.PSIsContainer) {
            Write-Error -Message "Theme file not found: $ThemePath" -Category ObjectNotFound -TargetObject $ThemePath
            return
        }
        return [PSCustomObject]@{ Name = Get-PoshifyThemeName $item.Name; Path = $item.FullName }
    }

    Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme (Get-PoshifyTheme) -Name $Name) -Name $Name `
        -Location 'locally. Use Find-PoshifyTheme and Install-PoshifyTheme to get it'
}

# Online theme list, cached for an hour. A stale cache is used when GitHub can't be reached.
function Get-PoshifyOnlineThemeList {
    param([switch]$ForceRefresh)

    $cacheFile = Get-PoshifyCacheFile
    $cache = $null
    $cachedAt = $null
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $cache = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            $cachedAt = $cache.CachedAt -as [datetime]
        }
        catch {
            Write-Verbose "Ignoring unreadable theme cache: $cacheFile"
        }
    }

    if (-not $ForceRefresh -and $cachedAt -and ([datetime]::UtcNow - $cachedAt.ToUniversalTime()) -lt $script:CacheMaxAge) {
        Write-Verbose "Using theme list cached at $cachedAt"
        return $cache.Themes | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
    }

    Write-Verbose "Fetching theme list from $script:OhMyPoshGitHubThemesUrl"
    try {
        $response = Invoke-RestMethod -Uri $script:OhMyPoshGitHubThemesUrl -Method Get -ErrorAction Stop
    }
    catch {
        $message = "Failed to fetch themes from GitHub: $($_.Exception.Message)"
        if ("$($_.ErrorDetails.Message) $($_.Exception.Message)" -match 'rate limit') {
            $message = 'GitHub API rate limit reached (60 requests per hour without authentication).'
        }
        if ($cache) {
            Write-Warning "$message Using the theme list cached at $cachedAt."
            return $cache.Themes | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
        }
        Write-Error -Message "$message Try again later." -Exception $_.Exception -Category ConnectionError
        return
    }

    $entries = @($response | Where-Object { $_.name -match $script:ThemeFilePattern } |
            Select-Object -Property name, size, download_url, sha)

    try {
        $json = ConvertTo-Json -Depth 3 -InputObject ([ordered]@{
                CachedAt = [datetime]::UtcNow.ToString('o')
                Themes   = $entries
            })
        Write-PoshifyTextFile -Path $cacheFile -Text $json
    }
    catch {
        Write-Verbose "Could not write theme cache: $($_.Exception.Message)"
    }

    $entries | ForEach-Object { ConvertTo-PoshifyOnlineTheme $_ }
}

# Downloads to a temporary name first so a failed download never leaves a broken theme behind
function Save-PoshifyThemeFile {
    param(
        $Theme,
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $downloadPath = "$Path.download"
    try {
        Invoke-WebRequest -Uri $Theme.DownloadUrl -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
        Move-Item -LiteralPath $downloadPath -Destination $Path -Force
        $true
    }
    catch {
        Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
        Write-Error -Message "Failed to download theme '$($Theme.Name)': $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError
        $false
    }
}

# Git blob hash of a file, comparable to the 'sha' GitHub reports for repository files
function Get-PoshifyGitBlobSha {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $sha1.TransformBlock($header, 0, $header.Length, $null, 0) | Out-Null
        $sha1.TransformFinalBlock($bytes, 0, $bytes.Length) | Out-Null
        -join ($sha1.Hash | ForEach-Object { $_.ToString('x2') })
    }
    finally {
        $sha1.Dispose()
    }
}

function Get-PoshifyFavoriteList {
    $file = Get-PoshifyFavoritesFile
    if (-not (Test-Path -LiteralPath $file)) {
        return
    }

    try {
        $parsed = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Ignoring unreadable favorites file: $file"
        return
    }
    $parsed | Where-Object { $_ -is [string] -and $_ }
}

function Save-PoshifyFavoriteList {
    param([string[]]$Name)

    $sorted = @($Name | Sort-Object -Unique)
    Write-PoshifyTextFile -Path (Get-PoshifyFavoritesFile) -Text (ConvertTo-Json -InputObject $sorted)
}

# Reads a text file keeping its encoding, so rewriting a profile never mangles non-ASCII text.
# Windows PowerShell treats BOM-less files as ANSI, so non-UTF-8 content falls back to that.
function Read-PoshifyTextFile {
    param([string]$Path)

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $reader = New-Object System.IO.StreamReader($Path, $strictUtf8, $true)
    try {
        $text = $reader.ReadToEnd()
        $encoding = $reader.CurrentEncoding
    }
    catch [System.Text.DecoderFallbackException] {
        $encoding = [System.Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        $text = [System.IO.File]::ReadAllText($Path, $encoding)
    }
    finally {
        $reader.Dispose()
    }

    [PSCustomObject]@{ Text = $text; Encoding = $encoding }
}

function Write-PoshifyTextFile {
    param(
        [string]$Path,
        [string]$Text,
        # UTF-8 with BOM is read correctly by both Windows PowerShell and PowerShell 7
        [System.Text.Encoding]$Encoding = (New-Object System.Text.UTF8Encoding($true))
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function Get-PoshifyProfileBlock {
    param([string]$NewLine)

    $pointer = (Get-PoshifyCurrentThemeFile) -replace "'", "''"
    @(
        $script:ProfileBlockStart
        '# Managed by Poshify - use Set-PoshifyTheme / Reset-PoshifyTheme instead of editing this block.'
        "`$poshifyTheme = Get-Content -LiteralPath '$pointer' -TotalCount 1 -ErrorAction SilentlyContinue"
        'if ($poshifyTheme -and (Test-Path -LiteralPath $poshifyTheme) -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {'
        '    oh-my-posh init pwsh --config $poshifyTheme | Invoke-Expression'
        '}'
        'Remove-Variable -Name poshifyTheme -ErrorAction SilentlyContinue'
        $script:ProfileBlockEnd
    ) -join $NewLine
}

# Returns profile text with the Poshify block replaced in place (or appended), or removed with -Remove.
# Also cleans up the unmarked blocks written by Poshify 1.0.x and 2.0.0, including the partial
# leftovers that their broken cleanup regex used to leave behind.
function Merge-PoshifyProfileBlock {
    param(
        [AllowEmptyString()]
        [string]$Content,
        [switch]$Remove
    )

    $newLine = if ($Content -match "`r`n") { "`r`n" } elseif ($Content -match "`n") { "`n" } else { [Environment]::NewLine }
    $markedPattern = '(?ms)^{0}[ \t]*\r?$.*?^{1}[ \t]*(\r?\n)?' -f [regex]::Escape($script:ProfileBlockStart), [regex]::Escape($script:ProfileBlockEnd)
    $legacyPattern = '(?m)^(?:# Poshify Theme - Generated by Poshify Module\r?\n)?# Theme: .*\r?\n# Generated on: .*\r?\n(?:[ \t]*\r?\n)*oh-my-posh init pwsh --config ".*" \| Invoke-Expression[ \t]*(?:\r?\n)?'

    $result = $Content -replace $legacyPattern, ''

    if ($Remove) {
        $result = $result -replace $markedPattern, ''
    }
    else {
        $block = (Get-PoshifyProfileBlock -NewLine $newLine) + $newLine
        $marked = [regex]::new($markedPattern)
        $existing = $marked.Match($result)
        if ($existing.Success) {
            # Keep the block where the user put it; drop any duplicates after it
            $rest = $marked.Replace($result.Substring($existing.Index + $existing.Length), '')
            $result = $result.Substring(0, $existing.Index) + $block + $rest
        }
        else {
            $result = $result.TrimEnd()
            $result = if ($result) { $result + $newLine + $newLine + $block } else { $block }
        }
    }

    if ($result -cne $Content) {
        $result = $result.TrimEnd()
        if ($result) { $result += $newLine }
    }
    $result
}

#endregion

<#
.SYNOPSIS
    Gets available local oh-my-posh themes

.DESCRIPTION
    Lists oh-my-posh theme files downloaded by Poshify (~/.poshthemes) and the themes bundled
    with oh-my-posh ($env:POSH_THEMES_PATH). A theme downloaded by Poshify takes precedence
    over a bundled theme with the same name.

    Each theme also has SizeKB, LastModified and Path properties; use Format-List * to see them.

.PARAMETER Name
    Theme name to look up. An exact match is returned if one exists; otherwise the name is
    treated as a wildcard pattern, or as a substring if it contains no wildcard characters.

.EXAMPLE
    Get-PoshifyTheme
    Lists all available local themes

.EXAMPLE
    Get-PoshifyTheme -Name "agnoster"
    Gets the agnoster theme

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite
    Lists local themes marked as favorites

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyTheme {
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    $currentPath = Get-PoshifyCurrentThemePath
    $favorites = @(Get-PoshifyFavoriteList)
    $seen = @{}

    $themes = foreach ($source in Get-PoshifyThemeSource) {
        if (-not (Test-Path -LiteralPath $source.Path)) {
            Write-Verbose "Theme directory not found: $($source.Path)"
            continue
        }

        Get-ChildItem -LiteralPath $source.Path -File |
            Where-Object { $_.Name -match $script:ThemeFilePattern } |
            ForEach-Object {
                $themeName = Get-PoshifyThemeName $_.Name
                if ($seen.ContainsKey($themeName)) { return }
                $seen[$themeName] = $true
                ConvertTo-PoshifyThemeObject -File $_ -Source $source.Name -CurrentPath $currentPath -Favorites $favorites
            }
    }
    $themes = @($themes | Sort-Object -Property Name)

    if (-not $Name) {
        return $themes
    }

    $found = Select-PoshifyThemeMatch -Theme $themes -Name $Name
    if (-not $found) {
        Write-Error -Message "Theme '$Name' not found locally. Use Find-PoshifyTheme to search online." -Category ObjectNotFound -TargetObject $Name
        return
    }
    $found
}

<#
.SYNOPSIS
    Gets the currently selected oh-my-posh theme

.DESCRIPTION
    Returns the theme selected with Set-PoshifyTheme, or nothing if no theme is selected.
    A theme file set by path that is outside the Poshify and oh-my-posh theme folders is
    reported with Source 'Custom'.

.EXAMPLE
    Get-PoshifyCurrentTheme
    Shows the current theme

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyCurrentTheme {
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param()

    $currentPath = Get-PoshifyCurrentThemePath
    if (-not $currentPath) {
        Write-Verbose 'No theme is selected. Use Set-PoshifyTheme to select one.'
        return
    }

    $theme = Get-PoshifyTheme | Where-Object { $_.Path -eq $currentPath }
    if ($theme) {
        return $theme
    }

    $file = Get-Item -LiteralPath $currentPath -ErrorAction SilentlyContinue
    if (-not $file) {
        Write-Warning "The selected theme file no longer exists: $currentPath"
        return
    }
    ConvertTo-PoshifyThemeObject -File $file -Source 'Custom' -CurrentPath $currentPath -Favorites @(Get-PoshifyFavoriteList)
}

<#
.SYNOPSIS
    Finds oh-my-posh themes available online

.DESCRIPTION
    Lists the oh-my-posh themes available in the official GitHub repository.
    The list is cached for an hour to stay well within GitHub's limit of 60 unauthenticated
    API requests per hour. If GitHub can't be reached, an older cached list is used.

.PARAMETER Name
    Theme name to search for. Exact match first, then wildcard or substring match.

.PARAMETER ForceRefresh
    Ignore the cache and fetch the list from GitHub.

.EXAMPLE
    Find-PoshifyTheme
    Lists all available online themes

.EXAMPLE
    Find-PoshifyTheme -Name "agnoster"
    Searches for themes containing "agnoster" in their name

.EXAMPLE
    Find-PoshifyTheme -Name "power*" | Install-PoshifyTheme
    Installs every theme whose name starts with "power"

.OUTPUTS
    Poshify.OnlineTheme
#>
function Find-PoshifyTheme {
    [CmdletBinding()]
    [OutputType('Poshify.OnlineTheme')]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [switch]$ForceRefresh
    )

    $themes = @(Get-PoshifyOnlineThemeList -ForceRefresh:$ForceRefresh)

    if (-not $Name) {
        return $themes
    }

    $found = Select-PoshifyThemeMatch -Theme $themes -Name $Name
    if (-not $found) {
        if ($themes.Count -gt 0) {
            Write-Warning "No online themes found matching '$Name'"
        }
        return
    }
    $found
}

<#
.SYNOPSIS
    Installs an oh-my-posh theme

.DESCRIPTION
    Downloads a theme from the official oh-my-posh repository into ~/.poshthemes.
    If the theme is already available locally (including themes bundled with oh-my-posh),
    the local theme is returned instead unless -Force is used.

.PARAMETER Name
    The name of the theme to install. Must match exactly one online theme.

.PARAMETER Force
    Download the theme even if it is already available locally, overwriting any previous download.

.EXAMPLE
    Install-PoshifyTheme -Name "agnoster"
    Downloads and installs the agnoster theme

.EXAMPLE
    Install-PoshifyTheme -Name "powerlevel10k_rainbow" -Force
    Downloads the theme again, replacing the local copy

.OUTPUTS
    Poshify.Theme
#>
function Install-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

        [switch]$Force
    )

    begin {
        $onlineThemes = $null
    }

    process {
        if (-not $Force) {
            $existing = @(Get-PoshifyTheme | Where-Object { $_.Name -eq $Name })
            if ($existing.Count -gt 0) {
                Write-Warning "Theme '$Name' is already available locally ($($existing[0].Source)). Use -Force to download it again."
                return $existing[0]
            }
        }

        # Fetch the online list once per pipeline, not once per piped theme
        if ($null -eq $onlineThemes) {
            $onlineThemes = @(Get-PoshifyOnlineThemeList)
        }
        if ($onlineThemes.Count -eq 0) {
            return
        }

        $theme = Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme $onlineThemes -Name $Name) -Name $Name -Location 'online'
        if (-not $theme) {
            return
        }

        $themePath = Join-Path $script:PoshifyHome $theme.FileName
        if (-not $PSCmdlet.ShouldProcess($themePath, "Download theme '$($theme.Name)'")) {
            return
        }

        if (Save-PoshifyThemeFile -Theme $theme -Path $themePath) {
            Write-Verbose "Theme '$($theme.Name)' installed to $themePath"
            Get-PoshifyTheme | Where-Object { $_.Path -eq $themePath }
        }
    }
}

<#
.SYNOPSIS
    Updates themes installed by Poshify

.DESCRIPTION
    Compares themes downloaded by Poshify with the official oh-my-posh repository and downloads
    the ones that changed. Themes bundled with oh-my-posh are updated with oh-my-posh itself.

.PARAMETER Name
    Name of the theme to update. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER All
    Update every theme installed by Poshify.

.EXAMPLE
    Update-PoshifyTheme -Name "agnoster"
    Updates the agnoster theme if it changed online

.EXAMPLE
    Update-PoshifyTheme -All
    Updates all installed themes

.OUTPUTS
    Poshify.Theme for each theme that was updated
#>
function Update-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    [OutputType('Poshify.Theme')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName', ValueFromPipelineByPropertyName = $true)]
        [string[]]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All
    )

    begin {
        $onlineThemes = $null
    }

    process {
        $installed = @(Get-PoshifyTheme | Where-Object { $_.Source -eq 'Poshify' })
        $targets = if ($All) {
            $installed
        }
        else {
            foreach ($themeName in $Name) {
                Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme $installed -Name $themeName) -Name $themeName `
                    -Location 'among themes installed by Poshify'
            }
        }
        if (-not $targets) {
            Write-Verbose 'No themes to update'
            return
        }

        if ($null -eq $onlineThemes) {
            $onlineThemes = @(Get-PoshifyOnlineThemeList -ForceRefresh)
        }
        if ($onlineThemes.Count -eq 0) {
            return
        }

        foreach ($theme in $targets) {
            $fileName = Split-Path -Path $theme.Path -Leaf
            $remote = $onlineThemes | Where-Object { $_.FileName -eq $fileName } | Select-Object -First 1
            if (-not $remote) {
                Write-Warning "Theme '$($theme.Name)' is no longer in the oh-my-posh repository; keeping the local copy."
                continue
            }

            if ($remote.Sha -and (Get-PoshifyGitBlobSha -Path $theme.Path) -eq $remote.Sha) {
                Write-Verbose "Theme '$($theme.Name)' is up to date"
                continue
            }

            if ($PSCmdlet.ShouldProcess($theme.Path, "Update theme '$($theme.Name)'")) {
                if (Save-PoshifyThemeFile -Theme $remote -Path $theme.Path) {
                    Get-PoshifyTheme | Where-Object { $_.Path -eq $theme.Path }
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Removes a theme installed by Poshify

.DESCRIPTION
    Deletes a theme file downloaded by Poshify. Themes bundled with oh-my-posh can't be removed.
    The name must match exactly. The current theme is only removed with -Force.

.PARAMETER Name
    Exact name of the theme to remove. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER Force
    Remove the theme even if it is the current theme.

.EXAMPLE
    Remove-PoshifyTheme -Name "agnoster"
    Removes the agnoster theme

.EXAMPLE
    Get-PoshifyTheme | Where-Object { $_.Source -eq 'Poshify' -and -not $_.Favorite } | Remove-PoshifyTheme -WhatIf
    Shows which downloaded themes that aren't favorites would be removed

.OUTPUTS
    None
#>
function Remove-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

        [switch]$Force
    )

    process {
        $theme = Get-PoshifyTheme | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if (-not $theme) {
            Write-Error -Message "Theme '$Name' not found locally. Remove-PoshifyTheme needs the exact theme name." -Category ObjectNotFound -TargetObject $Name
            return
        }

        if ($theme.Source -ne 'Poshify') {
            Write-Error -Message "Theme '$Name' is bundled with oh-my-posh and can't be removed by Poshify." -Category InvalidOperation -TargetObject $Name
            return
        }

        if ($theme.Current -and -not $Force) {
            Write-Error -Message "Theme '$Name' is the current theme. Switch to another theme first, or use -Force." -Category InvalidOperation -TargetObject $Name
            return
        }

        if ($PSCmdlet.ShouldProcess($theme.Path, "Remove theme '$Name'")) {
            Remove-Item -LiteralPath $theme.Path -Force
            if ($theme.Current) {
                Write-Warning "Removed the current theme '$Name'. New sessions will use the default prompt until you set another theme."
            }
        }
    }
}

<#
.SYNOPSIS
    Sets the current oh-my-posh theme

.DESCRIPTION
    Selects a theme, makes sure your PowerShell profile contains the Poshify block that loads the
    selected theme at startup, and applies the theme to the current session.

    The profile block is written once and kept where it is; switching themes afterwards only
    changes the selection stored in ~/.poshthemes/current.

.PARAMETER Name
    The name of a local theme (see Get-PoshifyTheme).

.PARAMETER ThemePath
    Direct path to a theme file. Accepts pipeline input from Get-PoshifyTheme.

.PARAMETER NoApply
    Only update the selection and profile; leave the prompt of the current session unchanged.

.EXAMPLE
    Set-PoshifyTheme -Name "agnoster"
    Sets the agnoster theme as the current prompt

.EXAMPLE
    Set-PoshifyTheme -ThemePath "C:\path\to\custom.omp.json"
    Sets a custom theme file as the current prompt

.EXAMPLE
    Get-PoshifyRandomTheme -FromFavorites | Set-PoshifyTheme
    Switches to a random favorite theme

.OUTPUTS
    None
#>
function Set-PoshifyTheme {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'oh-my-posh init output is designed to be invoked')]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$ThemePath,

        [switch]$NoApply
    )

    process {
        $theme = Resolve-PoshifyThemeFile -Name $Name -ThemePath $ThemePath
        if (-not $theme) {
            return
        }

        if (-not (Get-OhMyPoshCommand)) {
            Write-Error -Message 'oh-my-posh is not installed or not in PATH. Install it from https://ohmyposh.dev/docs/installation' -Category NotInstalled
            return
        }

        $profilePath = Get-PoshifyProfilePath
        if (-not $PSCmdlet.ShouldProcess($profilePath, "Set oh-my-posh theme to '$($theme.Name)'")) {
            return
        }

        Write-PoshifyTextFile -Path (Get-PoshifyCurrentThemeFile) -Text $theme.Path

        $original = if (Test-Path -LiteralPath $profilePath) { Read-PoshifyTextFile -Path $profilePath }
        $content = Merge-PoshifyProfileBlock -Content $original.Text
        if ($content -cne $original.Text) {
            Write-Verbose "Updating Poshify block in $profilePath"
            if ($original) {
                Write-PoshifyTextFile -Path $profilePath -Text $content -Encoding $original.Encoding
            }
            else {
                Write-PoshifyTextFile -Path $profilePath -Text $content
            }
        }

        if (-not $NoApply) {
            # oh-my-posh's init script installs its prompt globally, so it can run from module scope
            (Invoke-OhMyPosh -ArgumentList 'init', 'pwsh', '--config', $theme.Path) -join [Environment]::NewLine | Invoke-Expression
        }

        Write-Verbose "Theme set to '$($theme.Name)' ($($theme.Path))"
    }
}

<#
.SYNOPSIS
    Resets the PowerShell prompt to default

.DESCRIPTION
    Removes the Poshify block from your PowerShell profile, clears the theme selection, and
    unloads oh-my-posh from the current session. Any oh-my-posh setup in your profile that
    Poshify did not create is left untouched and reported as a warning.

.EXAMPLE
    Reset-PoshifyTheme
    Resets the prompt to default PowerShell appearance

.OUTPUTS
    None
#>
function Reset-PoshifyTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $profilePath = Get-PoshifyProfilePath
    if (-not $PSCmdlet.ShouldProcess($profilePath, 'Remove Poshify theme configuration')) {
        return
    }

    if (Test-Path -LiteralPath $profilePath) {
        $original = Read-PoshifyTextFile -Path $profilePath
        $content = Merge-PoshifyProfileBlock -Content $original.Text -Remove
        if ($content -cne $original.Text) {
            Write-PoshifyTextFile -Path $profilePath -Text $content -Encoding $original.Encoding
            Write-Verbose "Removed Poshify block from $profilePath"
        }
        else {
            Write-Verbose "No Poshify block found in $profilePath"
        }

        Select-String -LiteralPath $profilePath -Pattern 'oh-my-posh(\.exe)?[''"]?\s+init' | ForEach-Object {
            Write-Warning "Your profile still initializes oh-my-posh outside Poshify (line $($_.LineNumber)): $($_.Line.Trim())"
        }
    }

    Remove-Item -LiteralPath (Get-PoshifyCurrentThemeFile) -Force -ErrorAction SilentlyContinue

    # Unloading oh-my-posh's module restores the prompt it replaced
    Get-Module -Name oh-my-posh-core | Remove-Module -Force
}

<#
.SYNOPSIS
    Previews an oh-my-posh theme

.DESCRIPTION
    Renders what the prompt looks like with a theme, without changing your current theme.

.PARAMETER Name
    The name of a local theme (see Get-PoshifyTheme).

.PARAMETER ThemePath
    Direct path to a theme file. Accepts pipeline input from Get-PoshifyTheme.

.EXAMPLE
    Show-PoshifyTheme -Name "agnoster"
    Shows the agnoster prompt

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite | Show-PoshifyTheme
    Shows every favorite theme

.OUTPUTS
    System.String
#>
function Show-PoshifyTheme {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByPath', ValueFromPipelineByPropertyName = $true)]
        [Alias('Path', 'FullName')]
        [string]$ThemePath
    )

    process {
        $theme = Resolve-PoshifyThemeFile -Name $Name -ThemePath $ThemePath
        if (-not $theme) {
            return
        }

        if (-not (Get-OhMyPoshCommand)) {
            Write-Error -Message 'oh-my-posh is not installed or not in PATH. Install it from https://ohmyposh.dev/docs/installation' -Category NotInstalled
            return
        }

        "== $($theme.Name) =="
        Invoke-OhMyPosh -ArgumentList 'print', 'preview', '--config', $theme.Path
    }
}

<#
.SYNOPSIS
    Gets a random local theme

.DESCRIPTION
    Picks a random local theme, other than the current one when possible. Pipe it to
    Set-PoshifyTheme to apply it.

.PARAMETER FromFavorites
    Only pick from favorite themes that are available locally.

.EXAMPLE
    Get-PoshifyRandomTheme | Set-PoshifyTheme
    Applies a random theme

.EXAMPLE
    Get-PoshifyRandomTheme -FromFavorites | Set-PoshifyTheme
    Applies a random favorite theme

.OUTPUTS
    Poshify.Theme
#>
function Get-PoshifyRandomTheme {
    [CmdletBinding()]
    [OutputType('Poshify.Theme')]
    param(
        [switch]$FromFavorites
    )

    $candidates = @(Get-PoshifyTheme)
    if ($FromFavorites) {
        $candidates = @($candidates | Where-Object { $_.Favorite })
        if ($candidates.Count -eq 0) {
            Write-Error -Message 'None of your favorite themes are available locally. Use Add-PoshifyFavorite and Install-PoshifyTheme first.' -Category ObjectNotFound
            return
        }
    }
    elseif ($candidates.Count -eq 0) {
        Write-Error -Message 'No local themes found. Use Find-PoshifyTheme and Install-PoshifyTheme to get some.' -Category ObjectNotFound
        return
    }

    $others = @($candidates | Where-Object { -not $_.Current })
    if ($others.Count -gt 0) {
        $candidates = $others
    }
    $candidates | Get-Random
}

<#
.SYNOPSIS
    Adds a theme to favorites

.DESCRIPTION
    Saves a theme name to the favorites list. If the name matches a local theme, the theme's
    exact name is stored. Themes that aren't installed yet can be added too.

.PARAMETER Name
    The theme to add. Accepts pipeline input from Get-PoshifyTheme and Find-PoshifyTheme.

.EXAMPLE
    Add-PoshifyFavorite -Name "agnoster"
    Adds agnoster to favorites

.OUTPUTS
    None
#>
function Add-PoshifyFavorite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name
    )

    process {
        $local = @(Select-PoshifyThemeMatch -Theme (Get-PoshifyTheme) -Name $Name)
        if ($local.Count -gt 1) {
            $null = Resolve-PoshifySingleTheme -Match $local -Name $Name -Location 'locally'
            return
        }

        $themeName = if ($local.Count -eq 1) { $local[0].Name } else { $Name }
        if ($local.Count -eq 0) {
            Write-Warning "Theme '$Name' is not installed locally. It is added to favorites, but won't be picked by Get-PoshifyRandomTheme -FromFavorites until installed."
        }

        $favorites = @(Get-PoshifyFavoriteList)
        if ($themeName -in $favorites) {
            Write-Verbose "Theme '$themeName' is already a favorite"
            return
        }

        Save-PoshifyFavoriteList -Name ($favorites + $themeName)
        Write-Verbose "Added '$themeName' to favorites"
    }
}

<#
.SYNOPSIS
    Removes a theme from favorites

.PARAMETER Name
    Exact name of the theme to remove from favorites.

.EXAMPLE
    Remove-PoshifyFavorite -Name "agnoster"
    Removes agnoster from favorites

.OUTPUTS
    None
#>
function Remove-PoshifyFavorite {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
        [string]$Name
    )

    process {
        $favorites = @(Get-PoshifyFavoriteList)
        if ($Name -notin $favorites) {
            Write-Error -Message "Theme '$Name' is not in favorites." -Category ObjectNotFound -TargetObject $Name
            return
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove from favorites')) {
            Save-PoshifyFavoriteList -Name @($favorites | Where-Object { $_ -ne $Name })
        }
    }
}

<#
.SYNOPSIS
    Gets the list of favorite themes

.EXAMPLE
    Get-PoshifyFavorite
    Lists all favorite theme names

.EXAMPLE
    Get-PoshifyTheme | Where-Object Favorite
    Lists favorite themes that are available locally, with details

.OUTPUTS
    System.String
#>
function Get-PoshifyFavorite {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-PoshifyFavoriteList
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
New-Alias -Name 'poshify-theme-show' -Value 'Show-PoshifyTheme' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-add' -Value 'Add-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-remove' -Value 'Remove-PoshifyFavorite' -ErrorAction SilentlyContinue
New-Alias -Name 'poshify-favorite-get' -Value 'Get-PoshifyFavorite' -ErrorAction SilentlyContinue

# Create a main Poshify command that acts as a CLI utility
function Poshify {
    <#
    .SYNOPSIS
        Main Poshify CLI utility command

    .DESCRIPTION
        Provides a command-line interface for managing oh-my-posh themes.

        Theme actions:    list, find, install, set, reset, current, show, update, remove, random
        Favorite actions: list, add, remove, random

    .EXAMPLE
        Poshify theme install agnoster
        Downloads and installs the agnoster theme

    .EXAMPLE
        Poshify theme set agnoster
        Sets the agnoster theme as current

    .EXAMPLE
        Poshify theme show agnoster
        Previews the agnoster theme

    .EXAMPLE
        Poshify theme update
        Updates all themes installed by Poshify

    .EXAMPLE
        Poshify favorite add agnoster
        Adds agnoster to favorites

    .EXAMPLE
        Poshify favorite random
        Applies a random favorite theme

    .EXAMPLE
        Poshify theme reset
        Resets theme to default PowerShell prompt
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive CLI front-end')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet('theme', 'favorite')]
        [string]$Command,

        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateSet('list', 'find', 'install', 'set', 'reset', 'current', 'show', 'update', 'remove', 'random', 'add')]
        [string]$Action,

        [Parameter(Position = 2)]
        [string]$ThemeName
    )

    $actions = @{
        theme    = 'list', 'find', 'install', 'set', 'reset', 'current', 'show', 'update', 'remove', 'random'
        favorite = 'list', 'add', 'remove', 'random'
    }
    $needsName = 'theme install', 'theme set', 'theme show', 'theme remove', 'favorite add', 'favorite remove'

    if ($Action -notin $actions[$Command]) {
        Write-Error "Unknown action '$Action' for '$Command'. Available actions: $($actions[$Command] -join ', ')"
        return
    }

    if ("$Command $Action" -in $needsName -and -not $ThemeName) {
        Write-Error "Theme name is required for '$Command $Action'"
        Write-Host "Usage: Poshify $Command $Action <theme-name>" -ForegroundColor Yellow
        return
    }

    switch ("$Command $Action") {
        'theme list' {
            $themes = Get-PoshifyTheme
            if (-not $themes) {
                Write-Host 'No local themes found. Use "Poshify theme find" and "Poshify theme install <name>" to get some.' -ForegroundColor Yellow
            }
            $themes
        }
        'theme find' {
            Find-PoshifyTheme -Name $ThemeName
        }
        'theme install' {
            $theme = Install-PoshifyTheme -Name $ThemeName
            if ($theme) {
                Write-Host "Theme '$($theme.Name)' is ready. Apply it with: Poshify theme set $($theme.Name)" -ForegroundColor Green
            }
        }
        'theme set' {
            Set-PoshifyTheme -Name $ThemeName -ErrorVariable setError
            if (-not $setError) {
                Write-Host "Theme set to '$ThemeName'." -ForegroundColor Green
            }
        }
        'theme reset' {
            Reset-PoshifyTheme
            Write-Host 'Poshify theme removed. Open a new session if your prompt has not changed.' -ForegroundColor Green
        }
        'theme current' {
            $theme = Get-PoshifyCurrentTheme
            if (-not $theme) {
                Write-Host 'No theme is selected. Use "Poshify theme set <name>" to select one.' -ForegroundColor Yellow
            }
            $theme
        }
        'theme show' {
            Show-PoshifyTheme -Name $ThemeName
        }
        'theme update' {
            $updated = if ($ThemeName) { @(Update-PoshifyTheme -Name $ThemeName) } else { @(Update-PoshifyTheme -All) }
            Write-Host "$($updated.Count) theme(s) updated." -ForegroundColor Green
            $updated
        }
        'theme remove' {
            Remove-PoshifyTheme -Name $ThemeName
        }
        { $_ -in 'theme random', 'favorite random' } {
            $theme = Get-PoshifyRandomTheme -FromFavorites:($Command -eq 'favorite')
            if ($theme) {
                $theme | Set-PoshifyTheme -ErrorVariable setError
                if (-not $setError) {
                    Write-Host "Theme set to '$($theme.Name)'." -ForegroundColor Green
                }
            }
        }
        'favorite list' {
            $favorites = Get-PoshifyFavorite
            if (-not $favorites) {
                Write-Host 'No favorite themes yet. Use "Poshify favorite add <name>" to add one.' -ForegroundColor Yellow
            }
            $favorites
        }
        'favorite add' {
            Add-PoshifyFavorite -Name $ThemeName
        }
        'favorite remove' {
            Remove-PoshifyFavorite -Name $ThemeName
        }
    }
}

# Tab completion for theme names
$localThemeCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($commandName -eq 'Poshify') {
        $command = "$($fakeBoundParameters['Command']) $($fakeBoundParameters['Action'])"
        if ($command -eq 'favorite remove') {
            Get-PoshifyFavorite | Where-Object { $_ -like "$wordToComplete*" }
            return
        }
        # Install and find work with online themes; don't suggest local names there
        if ($command -notin 'theme set', 'theme show', 'theme update', 'theme remove', 'favorite add') {
            return
        }
    }

    Get-PoshifyTheme | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Path)
    }
}
$favoriteCompleter = {
    param($commandName, $parameterName, $wordToComplete)
    Get-PoshifyFavorite | Where-Object { $_ -like "$wordToComplete*" }
}
Register-ArgumentCompleter -ParameterName 'Name' -ScriptBlock $localThemeCompleter -CommandName @(
    'Get-PoshifyTheme', 'Set-PoshifyTheme', 'Show-PoshifyTheme', 'Update-PoshifyTheme', 'Remove-PoshifyTheme', 'Add-PoshifyFavorite'
)
Register-ArgumentCompleter -CommandName 'Remove-PoshifyFavorite' -ParameterName 'Name' -ScriptBlock $favoriteCompleter
Register-ArgumentCompleter -CommandName 'Poshify' -ParameterName 'ThemeName' -ScriptBlock $localThemeCompleter

# Export module functions and aliases
Export-ModuleMember -Function @(
    'Get-PoshifyTheme',
    'Get-PoshifyCurrentTheme',
    'Find-PoshifyTheme',
    'Install-PoshifyTheme',
    'Update-PoshifyTheme',
    'Remove-PoshifyTheme',
    'Set-PoshifyTheme',
    'Reset-PoshifyTheme',
    'Show-PoshifyTheme',
    'Get-PoshifyRandomTheme',
    'Add-PoshifyFavorite',
    'Remove-PoshifyFavorite',
    'Get-PoshifyFavorite',
    'Poshify'
) -Alias @(
    'poshify-theme-get',
    'poshify-theme-find',
    'poshify-theme-install',
    'poshify-theme-set',
    'poshify-theme-reset',
    'poshify-theme-current',
    'poshify-theme-remove',
    'poshify-theme-update',
    'poshify-theme-show',
    'poshify-favorite-add',
    'poshify-favorite-remove',
    'poshify-favorite-get'
)
