# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release preparation
- GitHub Actions CI/CD pipeline
- Comprehensive documentation
- Contribution guidelines

## [1.0.0] - 2024-01-01

### Added
- Initial release of Poshify module
- Get-PoshifyTheme: List available local themes
- Find-PoshifyTheme: Discover themes from oh-my-posh repository
- Install-PoshifyTheme: Download and install themes
- Set-PoshifyTheme: Apply themes to PowerShell prompt
- Reset-PoshifyTheme: Restore default PowerShell prompt
- Poshify: Main CLI utility command
- PowerShell profile backup and restoration
- Comprehensive error handling and user feedback
- Comment-based help for all functions
- Aliases for common operations

### Security
- Safe profile modification with automatic backups
- Input validation on all parameters
- Secure web requests for theme downloads

[Unreleased]: https://github.com/tamujin/Poshify/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/tamujin/Poshify/releases/tag/v1.0.0