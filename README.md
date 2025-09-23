# Poshify 🎨

A powerful PowerShell module for managing Oh My Posh themes with ease. Discover, install, and switch between beautiful terminal themes in seconds.

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Poshify.svg)](https://www.powershellgallery.com/packages/Poshify)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-purple.svg)]()

## ✨ Features

- 🔍 **Discover Themes**: Browse hundreds of Oh My Posh themes from the official repository
- 📥 **Easy Installation**: Download and install themes with a single command
- 🔄 **Quick Switching**: Seamlessly switch between installed themes
- 💾 **Profile Management**: Automatic PowerShell profile backup and restoration
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

# Set a theme
Poshify theme set agnoster

# List installed themes
Poshify theme list

# Reset to default PowerShell prompt
Poshify theme reset
```

## 📖 Commands

### Get-PoshifyTheme
List all locally installed themes.

```powershell
Get-PoshifyTheme
Get-PoshifyTheme -Name "agnoster"
```

### Find-PoshifyTheme
Discover themes available in the Oh My Posh repository.

```powershell
Find-PoshifyTheme
Find-PoshifyTheme -Name "power"
```

### Install-PoshifyTheme
Download and install a theme from the official repository.

```powershell
Install-PoshifyTheme -Name "agnoster"
Install-PoshifyTheme -Name "powerlevel10k_rainbow"
```

### Set-PoshifyTheme
Apply a theme to your PowerShell prompt.

```powershell
Set-PoshifyTheme -Name "agnoster"
Set-PoshifyTheme -ThemePath "C:\path\to\custom.omp.json"
```

### Reset-PoshifyTheme
Remove Oh My Posh configuration and restore default PowerShell prompt.

```powershell
Reset-PoshifyTheme
```

### Poshify (Main CLI)
A unified command-line interface for all theme operations.

```powershell
Poshify theme list
Poshify theme find
Poshify theme install <name>
Poshify theme set <name>
Poshify theme reset
```

## 📁 File Structure

```
%USERPROFILE%\.poshthemes\
├── agnoster.omp.json
├── powerlevel10k_rainbow.omp.json
├── .profile_backup          # Backup of original PowerShell profile
└── ... (other theme files)
```

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
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\Poshify -Settings PSGallery

# Test module functions
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
