# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Which versions are eligible receiving such patches depend on the CVSS v3.0 Rating:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

Please report vulnerabilities by emailing security@poshify.dev (or create an issue if this email is not available).

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a timeline for the fix.

## Security Best Practices

This module follows these security principles:

1. **Input Validation**: All user inputs are validated before processing
2. **Secure Defaults**: Safe default configurations
3. **Principle of Least Privilege**: Only requests necessary permissions
4. **No Hardcoded Secrets**: All sensitive data is configurable
5. **Secure Communication**: Uses HTTPS for all web requests

## Known Security Considerations

- The module modifies PowerShell profiles - always creates backups
- Downloads themes from GitHub over HTTPS
- Validates theme files before applying them
- Does not execute arbitrary code from downloaded themes

## Security Updates

When security updates are released, we will:

1. Notify users through GitHub releases
2. Update the PowerShell Gallery package
3. Provide clear upgrade instructions
4. Document the vulnerability and fix in the changelog