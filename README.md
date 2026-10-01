# Poshify 🎨

A powerful PowerShell module for managing Oh My Posh themes with ease. Discover, install, and switch between beautiful terminal themes in seconds.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Poshify.svg)](https://www.powershellgallery.com/packages/Poshify)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-purple.svg)]()

## ✨ Features

- 🔍 **Discover Themes**: Browse hundreds of Oh My Posh themes from the official repository
- 📥 **Easy Installation**: Download and install themes with a single command
- 🔄 **Quick Switching**: Switch themes instantly, in the current session and future ones
- 👀 **Previews**: See what a theme's prompt looks like before applying it
- ⭐ **Favorites & Random**: Keep a list of favorite themes and pick one at random
- ♻️ **Updates**: Re-download only the themes that changed upstream
- 💾 **Safe Profile Management**: One clearly marked profile block; the rest of your profile is never touched
- 🎯 **CLI Interface**: Simple command-line interface for all operations
- 🔧 **Zero Configuration**: Works out of the box with sensible defaults

## 🚀 Quick Start

### Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name Poshify -Scope CurrentUser

# Import the module
Import-Module Poshify
```

### Basic Usage

```powershell
# Find available themes
Poshify theme find

# Install a theme
Poshify theme install agnoster

# Preview it, then set it
Poshify theme show agnoster
Poshify theme set agnoster

# List installed themes
Poshify theme list

# Mark favorites and switch to a random one
Poshify favorite add agnoster
Poshify favorite random

# Reset to default PowerShell prompt
Poshify theme reset
```

## 📖 Commands

### Get-PoshifyTheme
List local themes: ones downloaded by Poshify plus the themes bundled with oh-my-posh
(`$env:POSH_THEMES_PATH`). An exact name match wins over partial matches.

```powershell
Get-PoshifyTheme
Get-PoshifyTheme -Name "agnoster"
Get-PoshifyTheme | Where-Object Favorite
Get-PoshifyTheme agnoster | Format-List *   # size, last modified, path
```

### Get-PoshifyCurrentTheme
The theme currently selected with `Set-PoshifyTheme`.

```powershell
Get-PoshifyCurrentTheme
```

### Find-PoshifyTheme
Discover themes available in the Oh My Posh repository. The list is cached for an hour to stay
within GitHub's limit of 60 API requests per hour.

```powershell
Find-PoshifyTheme
Find-PoshifyTheme -Name "power"
Find-PoshifyTheme -ForceRefresh   # bypass the cache
```

### Install-PoshifyTheme
Download and install a theme from the official repository.

```powershell
Install-PoshifyTheme -Name "agnoster"
Install-PoshifyTheme -Name "powerlevel10k_rainbow" -Force   # re-download
Find-PoshifyTheme "power*" | Install-PoshifyTheme
```

### Update-PoshifyTheme
Re-download themes installed by Poshify whose content changed upstream.

```powershell
Update-PoshifyTheme -Name "agnoster"
Update-PoshifyTheme -All
```

### Remove-PoshifyTheme
Delete a downloaded theme. Needs the exact name; the current theme is only removed with `-Force`.

```powershell
Remove-PoshifyTheme -Name "agnoster"
Remove-PoshifyTheme -Name "agnoster" -WhatIf
```

### Show-PoshifyTheme
Render a theme's prompt without applying it.

```powershell
Show-PoshifyTheme -Name "agnoster"
Get-PoshifyTheme | Where-Object Favorite | Show-PoshifyTheme
```

### Set-PoshifyTheme
Apply a theme to your PowerShell prompt, in the current session and future ones.
Theme names tab-complete.

```powershell
Set-PoshifyTheme -Name "agnoster"
Set-PoshifyTheme -ThemePath "C:\path\to\custom.omp.json"
Set-PoshifyTheme agnoster -WhatIf
```

### Favorites and random themes

```powershell
Add-PoshifyFavorite -Name "agnoster"
Get-PoshifyFavorite
Remove-PoshifyFavorite -Name "agnoster"

Get-PoshifyRandomTheme | Set-PoshifyTheme                  # any local theme except the current one
Get-PoshifyRandomTheme -FromFavorites | Set-PoshifyTheme   # a random favorite
```

### Reset-PoshifyTheme
Remove Poshify's block from your profile and restore the default PowerShell prompt.
Any oh-my-posh setup Poshify didn't create is left alone and reported as a warning.

```powershell
Reset-PoshifyTheme
```

### Poshify (Main CLI)
A unified command-line interface for all theme operations.

```powershell
Poshify theme list
Poshify theme find [name]
Poshify theme install <name>
Poshify theme show <name>
Poshify theme set <name>
Poshify theme current
Poshify theme update [name]      # all downloaded themes when no name is given
Poshify theme remove <name>
Poshify theme random
Poshify theme reset

Poshify favorite list
Poshify favorite add <name>
Poshify favorite remove <name>
Poshify favorite random
```

## 📁 How It Works

The first `Set-PoshifyTheme` adds this block to your profile (`$PROFILE.CurrentUserAllHosts`).
It is only written once; you can move it anywhere in the profile and Poshify will keep it there.

```powershell
# >>> poshify >>>
$poshifyTheme = Get-Content -LiteralPath '~/.poshthemes/current' -TotalCount 1 -ErrorAction SilentlyContinue
if ($poshifyTheme -and (Test-Path -LiteralPath $poshifyTheme) -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    oh-my-posh init pwsh --config $poshifyTheme | Invoke-Expression
}
# <<< poshify <<<
```

Switching themes only changes the selection file:

```
~/.poshthemes/
├── current                          # Path of the selected theme
├── .favorites.json                  # Favorite theme names
├── .cache/themes.json               # Online theme list, cached for an hour
├── agnoster.omp.json                # Themes downloaded by Install-PoshifyTheme
└── powerlevel10k_rainbow.omp.json
```

Upgrading from 1.0.x or 2.0.0? The old unmarked profile entries are cleaned up automatically the next time
you run `Set-PoshifyTheme` or `Reset-PoshifyTheme`. The old `~/.poshthemes/.profile_backup` file
is no longer used and can be deleted.

## 🔧 Requirements

- PowerShell 5.1 or higher
- Windows, macOS, or Linux
- Oh My Posh installed (automatically configured)
- Internet connection for theme discovery and installation

## 🛠️ Development

### Building from Source

```powershell
# Clone the repository
git clone https://github.com/tamujin/Poshify.git
cd Poshify

# Import the module for testing
Import-Module .\Poshify\Poshify.psd1 -Force
```

### Running Tests

```powershell
# Unit tests (Pester 5+); they never touch your real profile or the network
Invoke-Pester -Path .\tests

# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Poshify -Settings PSGallery -Recurse

# Validate the manifest
Test-ModuleManifest -Path .\Poshify\Poshify.psd1
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Oh My Posh](https://ohmyposh.dev/) - The amazing prompt theme engine
- [Jan De Dobbeleer](https://github.com/JanDeDobbeleer) - Creator of Oh My Posh
- PowerShell Community - For continuous support and inspiration

## 📞 Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/tamujin/Poshify/issues) page
2. Create a new issue with detailed information
3. Join our discussions

---

**Made with ❤️ by the Poshify Team**
