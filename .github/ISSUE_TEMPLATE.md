# GitHub Issue and Pull Request Templates

## Issue Templates

### Bug Report Template
```markdown
## Bug Description
A clear and concise description of what the bug is.

## Steps to Reproduce
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
A clear and concise description of what actually happened.

## Screenshots
If applicable, add screenshots to help explain your problem.

## Environment
- OS: [e.g. Windows 10, macOS 12, Ubuntu 20.04]
- PowerShell Version: [e.g. 7.2.0]
- Poshify Version: [e.g. 1.0.0]
- Oh My Posh Version: [e.g. 12.0.0]

## Additional Context
Add any other context about the problem here.
```

### Feature Request Template
```markdown
## Feature Description
A clear and concise description of what you want to happen.

## Problem Statement
A clear and concise description of what the problem is. Ex. I'm always frustrated when [...]

## Proposed Solution
A clear and concise description of what you want to happen.

## Alternatives Considered
A clear and concise description of any alternative solutions or features you've considered.

## Additional Context
Add any other context or screenshots about the feature request here.
```

## Pull Request Template

```markdown
## Description
Brief description of changes made.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring

## Testing
- [ ] Manual testing completed
- [ ] PSScriptAnalyzer passes with no warnings
- [ ] Module manifest validates successfully
- [ ] All functions have been tested
- [ ] Error handling tested

## Checklist
- [ ] My code follows the project's style guidelines
- [ ] I have performed a self-review of my code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] I have made corresponding changes to the documentation
- [ ] My changes generate no new warnings
- [ ] Any dependent changes have been merged and published

## Related Issues
Fixes #(issue number)
Related to #(issue number)

## Screenshots (if applicable)
Add screenshots to help explain your changes.
```

## Setting Up Templates

To use these templates in your repository:

1. Create `.github/ISSUE_TEMPLATE/` directory
2. Create `.github/PULL_REQUEST_TEMPLATE.md` file
3. Copy the appropriate template content into each file

This will ensure consistent and comprehensive issue/PR reporting.