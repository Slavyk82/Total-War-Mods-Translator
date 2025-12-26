## What's New

### New Features
- Added DeepL Pro glossary support: TWMT glossaries are now synchronized with DeepL servers before each translation batch, ensuring consistent terminology in your translations

### Improvements
- Improved Steam game detection to support installations on any drive letter (not just C:, D:, E:)
- Added ACF manifest file parsing for more accurate game path detection
- Enhanced Windows registry lookup (HKCU, HKLM, WOW6432Node) for Steam installation detection
- Added automatic scanning of all available drives when registry lookup fails

### Bug Fixes
- Fixed automatic game detection failing when Steam or games are installed on non-system drives
- Fixed DeepL glossary sync failing with "API key not configured" error even when the key was correctly set in settings
- Fixed double-click editing not working in the "Translated Text" column of the translation editor

