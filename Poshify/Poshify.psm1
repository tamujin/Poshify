<#
.SYNOPSIS
    Poshify - A PowerShell module for managing oh-my-posh themes

.DESCRIPTION
    This module provides functions to list, install, and switch between oh-my-posh themes.

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

#region Private helpers

function Get-PoshifyProfilePath {
    $PROFILE.CurrentUserAllHosts
}

function Get-OhMyPoshCommand {
    Get-Command -Name oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

# File that holds the full path of the selected theme; read by the profile block at startup
function Get-PoshifyCurrentThemeFile {
    Join-Path $script:PoshifyHome 'current'
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
# Also cleans up the unmarked blocks written by Poshify 1.0.x, including the partial leftovers
# that its broken cleanup regex used to leave behind.
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
    Get-PoshifyTheme | Where-Object Current
    Shows the currently selected theme

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

                [PSCustomObject]@{
                    PSTypeName = 'Poshify.Theme'
                    Name       = $themeName
                    Source     = $source.Name
                    Current    = $_.FullName -eq $currentPath
                    Path       = $_.FullName
                }
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
    Finds oh-my-posh themes available online

.DESCRIPTION
    Lists the oh-my-posh themes available in the official GitHub repository.
    Uses the GitHub API, which allows 60 unauthenticated requests per hour.

.PARAMETER Name
    Theme name to search for. Exact match first, then wildcard or substring match.

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
        [string]$Name
    )

    Write-Verbose "Fetching theme list from $script:OhMyPoshGitHubThemesUrl"
    try {
        $response = Invoke-RestMethod -Uri $script:OhMyPoshGitHubThemesUrl -Method Get -ErrorAction Stop
    }
    catch {
        $message = "Failed to fetch themes from GitHub: $($_.Exception.Message)"
        if ("$($_.ErrorDetails.Message) $($_.Exception.Message)" -match 'rate limit') {
            $message = 'GitHub API rate limit reached (60 requests per hour without authentication). Try again later.'
        }
        Write-Error -Message $message -Exception $_.Exception -Category ConnectionError
        return
    }

    $themes = @($response | Where-Object { $_.name -match $script:ThemeFilePattern } | ForEach-Object {
            [PSCustomObject]@{
                PSTypeName  = 'Poshify.OnlineTheme'
                Name        = Get-PoshifyThemeName $_.name
                FileName    = $_.name
                SizeKB      = [math]::Round($_.size / 1KB, 2)
                DownloadUrl = $_.download_url
            }
        })

    if (-not $Name) {
        return $themes
    }

    $found = Select-PoshifyThemeMatch -Theme $themes -Name $Name
    if (-not $found) {
        Write-Warning "No online themes found matching '$Name'"
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
            $onlineThemes = @(Find-PoshifyTheme)
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

        if (-not (Test-Path -LiteralPath $script:PoshifyHome)) {
            New-Item -ItemType Directory -Path $script:PoshifyHome -Force | Out-Null
        }

        # Download to a temporary name so a failed download never leaves a broken theme behind
        $downloadPath = "$themePath.download"
        try {
            Invoke-WebRequest -Uri $theme.DownloadUrl -OutFile $downloadPath -UseBasicParsing -ErrorAction Stop
            Move-Item -LiteralPath $downloadPath -Destination $themePath -Force
        }
        catch {
            Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
            Write-Error -Message "Failed to download theme '$($theme.Name)': $($_.Exception.Message)" -Exception $_.Exception -Category ConnectionError
            return
        }

        Write-Verbose "Theme '$($theme.Name)' installed to $themePath"
        Get-PoshifyTheme | Where-Object { $_.Path -eq $themePath }
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
    Get-PoshifyTheme | Get-Random | Set-PoshifyTheme
    Switches to a random local theme

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
        if ($PSCmdlet.ParameterSetName -eq 'ByPath') {
            $item = Get-Item -LiteralPath $ThemePath -ErrorAction SilentlyContinue
            if (-not $item -or $item.PSIsContainer) {
                Write-Error -Message "Theme file not found: $ThemePath" -Category ObjectNotFound -TargetObject $ThemePath
                return
            }
            $themeName = Get-PoshifyThemeName $item.Name
            $themeFile = $item.FullName
        }
        else {
            $theme = Resolve-PoshifySingleTheme -Match (Select-PoshifyThemeMatch -Theme (Get-PoshifyTheme) -Name $Name) -Name $Name `
                -Location 'locally. Use Find-PoshifyTheme and Install-PoshifyTheme to get it'
            if (-not $theme) {
                return
            }
            $themeName = $theme.Name
            $themeFile = $theme.Path
        }

        $ohMyPosh = Get-OhMyPoshCommand
        if (-not $ohMyPosh) {
            Write-Error -Message 'oh-my-posh is not installed or not in PATH. Install it from https://ohmyposh.dev/docs/installation' -Category NotInstalled
            return
        }

        $profilePath = Get-PoshifyProfilePath
        if (-not $PSCmdlet.ShouldProcess($profilePath, "Set oh-my-posh theme to '$themeName'")) {
            return
        }

        Write-PoshifyTextFile -Path (Get-PoshifyCurrentThemeFile) -Text $themeFile

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
            (& $ohMyPosh init pwsh --config $themeFile) -join [Environment]::NewLine | Invoke-Expression
        }

        Write-Verbose "Theme set to '$themeName' ($themeFile)"
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive CLI front-end')]
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

    if ($Action -in 'install', 'set' -and -not $ThemeName) {
        Write-Error "Theme name is required for $Action action"
        Write-Host "Usage: Poshify theme $Action <theme-name>" -ForegroundColor Yellow
        return
    }

    switch ($Action) {
        'list' {
            $themes = Get-PoshifyTheme
            if (-not $themes) {
                Write-Host 'No local themes found. Use "Poshify theme find" and "Poshify theme install <name>" to get some.' -ForegroundColor Yellow
            }
            $themes
        }
        'find' {
            Find-PoshifyTheme -Name $ThemeName
        }
        'install' {
            $theme = Install-PoshifyTheme -Name $ThemeName
            if ($theme) {
                Write-Host "Theme '$($theme.Name)' is ready. Apply it with: Poshify theme set $($theme.Name)" -ForegroundColor Green
            }
        }
        'set' {
            Set-PoshifyTheme -Name $ThemeName -ErrorVariable setError
            if (-not $setError) {
                Write-Host "Theme set to '$ThemeName'." -ForegroundColor Green
            }
        }
        'reset' {
            Reset-PoshifyTheme
            Write-Host 'Poshify theme removed. Open a new session if your prompt has not changed.' -ForegroundColor Green
        }
    }
}

# Tab completion for local theme names
$localThemeCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # Install and find work with online themes; don't suggest local names there
    if ($commandName -eq 'Poshify' -and $fakeBoundParameters['Action'] -ne 'set') {
        return
    }

    Get-PoshifyTheme | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Path)
    }
}
Register-ArgumentCompleter -CommandName 'Get-PoshifyTheme', 'Set-PoshifyTheme' -ParameterName 'Name' -ScriptBlock $localThemeCompleter
Register-ArgumentCompleter -CommandName 'Poshify' -ParameterName 'ThemeName' -ScriptBlock $localThemeCompleter

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
