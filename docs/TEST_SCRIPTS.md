# TWMT Test Runner Scripts

This document describes the test runner scripts available for executing the TWMT test suite.

## Overview

Two scripts are provided for running tests:
- **PowerShell** (`scripts/run_tests.ps1`) - Full-featured with named parameters
- **Batch** (`scripts/run_tests.cmd`) - Simple command-line interface

Both scripts support the same test execution modes and provide colored output with execution time tracking.

---

## Test Categories

| Category | Path | Tests | Description |
|----------|------|-------|-------------|
| **Widgets** | `test/features/` | 352 | Screen and widget tests |
| **Services** | `test/unit/services/` | 241 | Business logic tests |
| **Repositories** | `test/unit/repositories/` | 182 | Data access tests |
| **Providers** | `test/providers/` | 232 | State management tests |
| **Smoke** | `test/widget_test.dart` | 1 | Basic app test |
| **Total** | | **1008** | |

### What are "Unit Tests"?

In this project, **unit tests** refer to:
- Service tests (`test/unit/services/`)
- Repository tests (`test/unit/repositories/`)

These test isolated business logic and data access without UI components.

---

## PowerShell Script

**File:** `scripts/run_tests.ps1`

### Execution Modes

```powershell
# Run ALL tests (default)
.\scripts\run_tests.ps1
.\scripts\run_tests.ps1 -All

# Run all tests EXCEPT unit tests (widgets + providers + smoke)
.\scripts\run_tests.ps1 -NoUnit

# Run ONLY unit tests (services + repositories)
.\scripts\run_tests.ps1 -UnitOnly
```

### Category Selection

```powershell
# Run specific categories
.\scripts\run_tests.ps1 -Services      # Only service tests
.\scripts\run_tests.ps1 -Repositories  # Only repository tests
.\scripts\run_tests.ps1 -Providers     # Only provider tests
.\scripts\run_tests.ps1 -Widgets       # Only widget tests

# Combine categories
.\scripts\run_tests.ps1 -Services -Repositories
```

### Additional Options

```powershell
# Generate coverage report
.\scripts\run_tests.ps1 -Coverage
.\scripts\run_tests.ps1 -All -Coverage

# Detailed output (expanded reporter)
.\scripts\run_tests.ps1 -Detailed
.\scripts\run_tests.ps1 -UnitOnly -Detailed

# Combine options
.\scripts\run_tests.ps1 -UnitOnly -Coverage -Detailed
```

### Examples

```powershell
# Quick unit test check before commit
.\scripts\run_tests.ps1 -UnitOnly

# Full test suite with coverage
.\scripts\run_tests.ps1 -All -Coverage

# Debug failing widget tests
.\scripts\run_tests.ps1 -Widgets -Detailed

# Test only data layer
.\scripts\run_tests.ps1 -Services -Repositories
```

---

## Batch Script

**File:** `scripts/run_tests.cmd`

### Execution Modes

```cmd
:: Run ALL tests (default)
scripts\run_tests.cmd
scripts\run_tests.cmd all

:: Run all tests EXCEPT unit tests
scripts\run_tests.cmd no-unit

:: Run ONLY unit tests
scripts\run_tests.cmd unit
```

### Category Selection

```cmd
:: Run specific categories
scripts\run_tests.cmd services    :: Only service tests
scripts\run_tests.cmd repos       :: Only repository tests
scripts\run_tests.cmd providers   :: Only provider tests
scripts\run_tests.cmd widgets     :: Only widget tests
```

### Additional Options

```cmd
:: Generate coverage report
scripts\run_tests.cmd all --coverage

:: Verbose output
scripts\run_tests.cmd unit --verbose

:: Combine options
scripts\run_tests.cmd services --coverage --verbose
```

### Help

```cmd
scripts\run_tests.cmd help
scripts\run_tests.cmd -h
scripts\run_tests.cmd --help
```

---

## Quick Reference

| Action | PowerShell | Batch |
|--------|------------|-------|
| All tests | `.\scripts\run_tests.ps1` | `scripts\run_tests.cmd` |
| All except unit | `.\scripts\run_tests.ps1 -NoUnit` | `scripts\run_tests.cmd no-unit` |
| Unit only | `.\scripts\run_tests.ps1 -UnitOnly` | `scripts\run_tests.cmd unit` |
| Services | `.\scripts\run_tests.ps1 -Services` | `scripts\run_tests.cmd services` |
| Repositories | `.\scripts\run_tests.ps1 -Repositories` | `scripts\run_tests.cmd repos` |
| Providers | `.\scripts\run_tests.ps1 -Providers` | `scripts\run_tests.cmd providers` |
| Widgets | `.\scripts\run_tests.ps1 -Widgets` | `scripts\run_tests.cmd widgets` |
| With coverage | `-Coverage` | `--coverage` |
| Detailed output | `-Detailed` | `--verbose` |
| Help | `Get-Help .\scripts\run_tests.ps1` | `scripts\run_tests.cmd help` |

---

## Test Counts by Mode

| Mode | PowerShell | Batch | Tests |
|------|------------|-------|-------|
| All | `-All` | `all` | 1008 |
| No Unit | `-NoUnit` | `no-unit` | 585 |
| Unit Only | `-UnitOnly` | `unit` | 423 |
| Services | `-Services` | `services` | 241 |
| Repositories | `-Repositories` | `repos` | 182 |
| Providers | `-Providers` | `providers` | 232 |
| Widgets | `-Widgets` | `widgets` | 352 |

---

## Coverage Reports

When using the `-Coverage` or `--coverage` flag:

1. Coverage data is generated at `coverage/lcov.info`
2. To generate an HTML report:
   ```bash
   genhtml coverage/lcov.info -o coverage/html
   ```
3. Open `coverage/html/index.html` in a browser

---

## Exit Codes

Both scripts return proper exit codes:
- `0` - All tests passed
- `1` - One or more tests failed

This allows integration with CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run unit tests
  run: .\scripts\run_tests.ps1 -UnitOnly
  shell: pwsh
```

---

## Recommended Workflows

### Before Commit
```powershell
# Quick check of core logic
.\scripts\run_tests.ps1 -UnitOnly
```

### Before Push
```powershell
# Full test suite
.\scripts\run_tests.ps1 -All
```

### Before Release
```powershell
# Full suite with coverage
.\scripts\run_tests.ps1 -All -Coverage -Detailed
```

### Debugging Specific Area
```powershell
# Example: debugging provider issues
.\scripts\run_tests.ps1 -Providers -Detailed
```

---

## Troubleshooting

### PowerShell Execution Policy
If you get an execution policy error:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Script Not Found
Run from the project root directory:
```powershell
cd E:\twmt
.\scripts\run_tests.ps1
```

### Tests Failing After Code Changes
1. Run `flutter pub get` to update dependencies
2. Run `dart run build_runner build` if using code generation
3. Try `flutter clean` then retry
