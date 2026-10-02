# Poshify 🎨

A powerful PowerShell module for managing Oh My Posh themes with ease. Discover, install, and switch between beautiful terminal themes in seconds.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Poshify.svg)](https://www.powershellgallery.com/packages/Poshify)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-purple.svg)]()

## ✨ Features

- 🚀 **One-Command Setup**: `Poshify setup` installs oh-my-posh and a Nerd Font, fixes your terminal font, and sets a theme
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
Install-Module -Name Poshify -Scope CurrentUser
Poshify setup
```

`Poshify setup` takes care of everything a working themed prompt needs, asking before each change:

1. **oh-my-posh**: installs it if it's missing (winget on Windows, Homebrew on macOS, the official
   install script on Linux).
2. **Nerd Font**: installs Meslo Nerd Font if you have none, since most themes need one for their icons.
3. **Terminal font**: switches Windows Terminal's default font to that Nerd Font (keeping a backup of its settings).
4. **Execution policy**: checks that PowerShell is allowed to run your profile, and tells you the
   command to run if not. Poshify never changes the execution policy itself.
5. **Theme**: shows previews of popular themes, lets you pick one, and sets it up in both
   PowerShell 7 and Windows PowerShell.

It's safe to run again at any time; steps that are already fine are skipped. For an unattended
setup use `Initialize-Poshify -Theme atomic -Force`, and add `-WhatIf` to see what would change.

There's no need to run `Import-Module`: PowerShell loads Poshify automatically the first time you use one of its commands.

### Basic Usage

```powershell
# Find available themes
Poshify theme find

# Preview a theme, then set it (it's downloaded automatically if needed)
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
Apply a theme to your PowerShell prompt, in the current session and future ones. On Windows
both PowerShell 7 and Windows PowerShell are set up. A theme that isn't installed yet is
downloaded first when the name matches an online theme exactly. Theme names tab-complete.

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

Get-PoshifyRandomTheme | Set-PoshifyTheme                  # switch to a random theme now and keep it
Get-PoshifyRandomTheme -FromFavorites | Set-PoshifyTheme   # same, from favorites

Set-PoshifyTheme -Random                                   # a different theme in every new session
Set-PoshifyTheme -Random -FromFavorites                    # a different favorite in every new session
```

### Per-folder themes
Give a project its own theme. A `.poshify` file in a folder sets the theme for that folder and
everything below it; the nearest one wins. Elsewhere your default theme is used. Existing
`.ompconfig` files work the same way.

```powershell
Set-PoshifyFolderTheme dracula                    # writes .poshify in the current folder
Set-PoshifyFolderTheme -ThemePath .\tools\project.omp.json
Get-PoshifyFolderTheme                            # which folder theme applies here
Get-PoshifyCurrentTheme | Select-Object Name, SelectedBy
Clear-PoshifyFolderTheme
```

A `.poshify` file is a single line with a theme name, or a path to a theme file:

```
dracula
```

oh-my-posh themes can run commands, so a `.poshify` file that points to a theme file outside your
theme folders (for example one inside a cloned repository) is ignored until you trust it with
`Approve-PoshifyFolderTheme` (`Poshify folder trust`). Trust is tied to the file's content, so a
changed file has to be trusted again.

### Reset-PoshifyTheme
Remove Poshify's block from your profile and restore the default PowerShell prompt.
Any oh-my-posh setup Poshify didn't create is left alone and reported as a warning.

```powershell
Reset-PoshifyTheme
```

### Poshify (Main CLI)
A unified command-line interface for all theme operations.

```powershell
Poshify setup                    # install and configure everything (see Initialize-Poshify)

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

Poshify folder set <name>        # theme for the current folder and below
Poshify folder show
Poshify folder clear
Poshify folder trust

Poshify theme set random         # or random-favorites: a different theme in every session
```

## 📁 How It Works

The first `Set-PoshifyTheme` adds this block to your profile (`$PROFILE.CurrentUserAllHosts`).
It is only written once; you can move it anywhere in the profile and Poshify will keep it there.

```powershell
# >>> poshify >>>
$poshifyInit = '~/.poshthemes/init.ps1'
if (Test-Path -LiteralPath $poshifyInit) { . $poshifyInit }
# <<< poshify <<<
```

`init.ps1` is generated by Poshify and works without loading the module, so startup stays fast.
It picks the theme for the current folder and, when you move to a folder that needs a different
theme, re-initializes oh-my-posh at the next prompt. The last command's status and exit code are
passed through, so oh-my-posh's error indicators keep working.

Switching themes only changes files in `~/.poshthemes`:

```
~/.poshthemes/
├── current                          # Default theme: a theme file path, or random / random:favorites
├── init.ps1                         # Generated startup script loaded by your profile
├── trusted                          # Project theme files you trusted
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
- Oh My Posh and a Nerd Font (`Poshify setup` installs both)
- Internet connection for theme discovery and installation

### Troubleshooting

- **Icons show as boxes or question marks**: your terminal isn't using a Nerd Font. Run
  `Poshify setup`, or set your terminal's font to one such as "MesloLGM Nerd Font". In VS Code,
  set `terminal.integrated.fontFamily`.
- **The theme doesn't appear in a new terminal**: PowerShell may not be allowed to run your
  profile. `Poshify setup` checks this and shows the command to fix it, usually
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- **The theme appears in PowerShell 7 but not Windows PowerShell (or the other way round)**:
  run `Poshify setup` from the edition that's missing it.

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
