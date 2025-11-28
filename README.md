# TWMT - Total War Mods Translator

A professional-grade Windows desktop application for translating Total War Workshop mods using AI-powered translation, Translation Memory, and glossary management.

## Features

### AI-Powered Translation
- **Multiple LLM Providers**: Anthropic Claude, OpenAI GPT, DeepL
- **Batch Processing**: Translate up to 100 entries per batch
- **Parallel Processing**: Run multiple batches concurrently

### Translation Memory (TM)
- **Exact Matching**: Hash-based O(1) lookup for identical phrases
- **Fuzzy Matching**: 3-algorithm hybrid (Levenshtein, Jaro-Winkler, Token-based)
- **Auto-Accept**: Automatically apply matches with >95% similarity
- **TMX Support**: Import/Export industry-standard format

### Glossary Management
- **Global & Game-Specific**: Scope terminology appropriately
- **Variants Support**: Multiple translations per term with notes

### Quality Validation
- Empty translation detection
- Length mismatch warnings
- Special character preservation
- Number consistency checks

### Steam Workshop Integration
- Auto-detect installed mods
- Track mod updates
- Extract files automatically

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

1. Download the latest beta version from [TWMT](https://github.com/Slavyk82/Total-War-Mods-Translator/releases/tag/beta)
2. Launch TWMT
3. Configure all paths in Settings
4. Select your default language for new projects
5. Add your LLM provider API key

## Quick Start

1. **Game**: Select a game in the sidebar
2. **Scan Mods**: Navigate to Mods
3. **Create Project**: Select a mod and it will create a project
4. **Translate**: Open the Translation Editor and click Translate All
5. **Generate**: Generate a .pack file in the "data" game folder

## Data Location

```
%APPDATA%\com.github.slavyk82\twmt
├── twmt.db          # Database
├── config\          # Configuration
├── logs\            # Logs
└── cache\           # Cache
```

## License

MIT

## Acknowledgments

- [RPFM](https://github.com/Frodo45127/rpfm) - For pack file operations
- Total War modding community

---

*TWMT - Making Total War mod translation efficient and consistent.*
