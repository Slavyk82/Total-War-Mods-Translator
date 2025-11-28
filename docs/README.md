# TWMT - Total War Mods Translator

A professional-grade Windows desktop application for translating Total War Workshop mods using AI-powered translation, Translation Memory, and glossary management.

## Features

### AI-Powered Translation
- **Multiple LLM Providers**: Anthropic Claude, OpenAI GPT, DeepL
- **Batch Processing**: Translate up to 100 entries per batch
- **Parallel Processing**: Run multiple batches concurrently
- **Cost Tracking**: Real-time token usage and cost estimation

### Translation Memory (TM)
- **Exact Matching**: Hash-based O(1) lookup for identical phrases
- **Fuzzy Matching**: 3-algorithm hybrid (Levenshtein, Jaro-Winkler, Token-based)
- **Auto-Accept**: Automatically apply matches with >95% similarity
- **TMX Support**: Import/Export industry-standard format

### Glossary Management
- **Global & Game-Specific**: Scope terminology appropriately
- **Variants Support**: Multiple translations per term with notes
- **Forbidden Terms**: Mark terms that should never appear
- **Multiple Formats**: CSV, Excel, TBX support

### Quality Validation
- Empty translation detection
- Length mismatch warnings
- Special character preservation
- Number consistency checks
- Auto-fix for common issues

### Steam Workshop Integration
- Auto-detect installed mods
- Track mod updates
- Extract .loc files automatically

## Supported Games

| Game | Status |
|------|--------|
| Total War: Warhammer III | Supported |
| Total War: Warhammer II | Supported |
| Total War: Warhammer | Supported |
| Total War: Rome II | Supported |
| Total War: Attila | Supported |
| Total War: Three Kingdoms | Supported |
| Total War Saga: Troy | Supported |
| Total War: Pharaoh | Supported |

## Requirements

- Windows 10 or Windows 11
- 8 GB RAM minimum (16 GB recommended)
- 500 MB free disk space
- Internet connection for LLM providers
- API key from at least one LLM provider

## Installation

1. Download the latest release from [Releases](../../releases)
2. Run the installer or extract the portable version
3. Launch TWMT
4. Configure game paths in Settings
5. Add your LLM provider API key

## Quick Start

1. **Configure Provider**: Go to Settings > LLM Providers and add your API key
2. **Scan Mods**: Navigate to Mods and click Refresh
3. **Create Project**: Select a mod and click Create Project
4. **Translate**: Open the Translation Editor and click Translate All
5. **Export**: Export translations to your preferred format

## Screenshots

*Screenshots coming soon*

## Documentation

See [Functional Documentation](FUNCTIONAL_DOCUMENTATION.md) for detailed information about all features.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+1-7 | Navigate between screens |
| Ctrl+T | Translate selected |
| Ctrl+A | Select all |
| Ctrl+S | Save |
| Ctrl+Z/Y | Undo/Redo |
| Ctrl+F | Search |

## Technology Stack

- **Framework**: Flutter (Windows Desktop)
- **Design**: Microsoft Fluent Design System
- **Database**: SQLite with FTS5
- **State Management**: Riverpod
- **Icons**: Fluent UI System Icons

## Data Location

```
%APPDATA%\TWMT\
├── twmt.db          # Database
├── config\          # Configuration
├── logs\            # Logs
└── cache\           # Cache
```

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting pull requests.

## License

*License information*

## Acknowledgments

- [RPFM](https://github.com/Frodo45127/rpfm) - For pack file operations
- Total War modding community

---

*TWMT - Making Total War mod translation efficient and consistent.*
