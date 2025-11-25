# TWMT - Total War Mods Translator

**Translation assistance for Total War game mods**

TWMT is a professional-grade Windows desktop application that streamlines the translation workflow for Total War Workshop mods. Built with Flutter and powered by advanced LLM technology, TWMT helps modders translate their content efficiently while maintaining consistency and quality.

![TWMT Application](docs/images/screenshots/main-window.png)

## Key Features

- **LLM-Powered Translation**: Integrate with Anthropic Claude, OpenAI GPT, or DeepL for high-quality automated translation
- **Translation Memory**: Reuse previous translations with fuzzy matching to save time and reduce costs
- **Multi-Glossary Management**: Maintain consistent terminology with project-specific and global glossaries
- **Advanced Search**: Lightning-fast FTS5 full-text search across all translations
- **Batch Operations**: Translate, validate, export, and manage thousands of entries at once
- **Version History**: Complete undo/redo support with visual diff comparison
- **Steam Workshop Integration**: Detect mod updates and track translation progress
- **Import/Export**: Support for CSV, Excel, JSON, .loc, TMX, and TBX formats
- **Quality Validation**: Automatic checks for placeholders, formatting, and consistency
- **Cost Tracking**: Monitor API usage and translation costs in real-time

## Screenshots

### Translation Editor
![Translation Editor](docs/images/screenshots/translation-editor.png)

### Translation Memory Browser
![Translation Memory](docs/images/screenshots/translation-memory.png)

### Glossary Management
![Glossary](docs/images/screenshots/glossary.png)

## System Requirements

**Operating System**: Windows 10 (version 1809 or later) or Windows 11

**Hardware**:
- Processor: 1 GHz or faster
- RAM: 4 GB minimum, 8 GB recommended
- Storage: 500 MB available space
- Display: 1280x720 minimum resolution, 1920x1080 recommended

**Dependencies**:
- No additional runtime dependencies required (all bundled)

**Network**:
- Internet connection required for LLM API access
- Steam Workshop integration requires Steam to be installed

## Installation

### Option 1: Download Release (Recommended)

1. Download the latest release from [GitHub Releases](https://github.com/yourusername/twmt/releases)
2. Run the `TWMT-Setup-x.x.x.exe` installer
3. Follow the installation wizard
4. Launch TWMT from the Start Menu or Desktop shortcut

### Option 2: Build from Source

```bash
# Prerequisites: Flutter SDK 3.10+, Git

# Clone repository
git clone https://github.com/yourusername/twmt.git
cd twmt

# Install dependencies
flutter pub get

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Run application
flutter run -d windows

# Build release
flutter build windows --release
```

## Quick Start

### 1. Configure API Keys

On first launch, you'll need to configure at least one LLM provider:

1. Open **Settings** (press `Ctrl+7` or click the gear icon)
2. Navigate to **LLM Providers** tab
3. Enter your API key for Anthropic, OpenAI, or DeepL
4. Click **Test Connection** to verify
5. Click **Save**

> **Need API keys?** See our [API Setup Guide](docs/api_setup.md) for detailed instructions.

### 2. Set Game Path

TWMT needs to know where your Total War games are installed:

1. Go to **Settings** → **Games**
2. Click **Auto-detect** to scan for installed games
3. Verify the Workshop path is correct (usually `C:\Program Files (x86)\Steam\steamapps\workshop\content\[APPID]`)
4. Click **Save**

### 3. Browse Mods

1. Navigate to **Mods** (press `Ctrl+2`)
2. Select your Total War game from the dropdown
3. Browse your subscribed Workshop mods
4. Click on a mod to view details

### 4. Create Translation Project

1. Select a mod from the Mods screen
2. Click **Create Project**
3. Enter project name and description
4. Select source language (usually English)
5. Select target language(s)
6. Click **Create**

### 5. Translate Content

1. Open your project from the **Projects** screen (`Ctrl+3`)
2. Click **Open Editor** for your target language
3. Select entries to translate (use `Ctrl+A` to select all)
4. Click **Translate Selected** (or press `Ctrl+T`)
5. Review and edit translations as needed
6. Click **Export** when complete

> **Tip**: Use Translation Memory and Glossaries to improve quality and reduce costs!

## Configuration

### LLM Provider Settings

**Anthropic Claude** (Recommended):
- Best quality-to-cost ratio
- Models: claude-3-5-sonnet-20241022, claude-3-opus-20240229
- Pricing: ~$3 per 1M input tokens, ~$15 per 1M output tokens

**OpenAI GPT**:
- Fast and reliable
- Models: gpt-4o, gpt-4-turbo, gpt-3.5-turbo
- Pricing: Varies by model

**DeepL**:
- Specialized translation service
- Limited language pairs
- Character-based pricing

### Game Paths

TWMT automatically detects Steam installations. If auto-detection fails:

1. Locate your Steam Workshop folder manually
2. Typical paths:
   - Total War: Warhammer III: `...\steamapps\workshop\content\1142710`
   - Total War: Three Kingdoms: `...\steamapps\workshop\content\779340`
   - Total War: Warhammer II: `...\steamapps\workshop\content\594570`
3. Enter the path in Settings → Games → Custom Path

### Translation Preferences

Configure default settings for new projects:

- **Quality Threshold**: Minimum quality score for Translation Memory matches (default: 70%)
- **Batch Size**: Number of entries to translate at once (default: 100)
- **Auto-save**: Automatically save changes every N minutes (default: 5)
- **Validation**: Enable automatic quality checks (recommended)

## Documentation

- **[User Guide](docs/user_guide.md)** - Comprehensive manual covering all features
- **[API Setup Guide](docs/api_setup.md)** - How to obtain and configure API keys
- **[Keyboard Shortcuts](docs/keyboard_shortcuts.md)** - Complete shortcuts reference
- **[FAQ](docs/faq.md)** - Frequently asked questions
- **[Developer Guide](docs/developer_guide.md)** - For contributors and developers

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/twmt/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/twmt/discussions)
- **Documentation**: [docs/](docs/)

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details on:

- Code of Conduct
- Development setup
- Coding standards
- Pull request process
- Issue reporting

Key areas for contribution:
- Additional LLM provider integrations
- Support for more Total War games
- Translation quality improvements
- UI/UX enhancements
- Documentation and tutorials

## Architecture

TWMT follows Clean Architecture principles with a feature-first organization:

- **Presentation Layer**: Fluent Design UI components (Windows native look)
- **Business Logic**: Service layer with dependency injection
- **Data Access**: Repository pattern with SQLite database
- **State Management**: Riverpod with code generation

Technology Stack:
- **Framework**: Flutter 3.10+ (Windows Desktop)
- **UI**: Fluent Design System (no Material Design)
- **Database**: SQLite with FTS5 full-text search
- **State**: Riverpod 3.x
- **Routing**: GoRouter 14.x

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Fluent UI Icons**: Microsoft's Fluent Design System
- **Syncfusion DataGrid**: High-performance virtualized tables
- **Total War Community**: For inspiration and feedback
- **LLM Providers**: Anthropic, OpenAI, DeepL for powering translations

## Roadmap

### Version 1.0 (Current)
- ✅ Core translation workflow
- ✅ Translation Memory with fuzzy matching
- ✅ Multi-glossary management
- ✅ Advanced search (FTS5)
- ✅ Batch operations
- ✅ Version history and undo/redo
- ✅ Import/Export (CSV, Excel, JSON, .loc, TMX, TBX)

### Version 1.1 (Planned)
- 🔄 Cloud synchronization
- 🔄 Collaborative translation (team features)
- 🔄 Machine translation quality estimation
- 🔄 Context-aware translation suggestions
- 🔄 Plugin system for custom workflows

### Version 2.0 (Future)
- 🔮 Additional Total War titles support
- 🔮 Game engine integration (direct mod file editing)
- 🔮 Translation marketplace
- 🔮 Advanced analytics and reporting

## Project Status

**Current Version**: 1.0.0
**Status**: ✅ Stable
**Last Updated**: November 2025

TWMT is actively maintained and under continuous development. We release updates regularly with bug fixes, performance improvements, and new features.

## Privacy & Security

- **API Keys**: Stored securely in Windows Credential Manager (encrypted)
- **Data Storage**: All data stored locally in `%APPDATA%\TWMT\`
- **Network**: Only communicates with selected LLM provider APIs
- **No Telemetry**: We do not collect usage data or analytics

## Credits

**Developed by**: [Your Name/Team]
**Framework**: Flutter Team at Google
**Design System**: Microsoft Fluent Design
**AI Technology**: Anthropic, OpenAI, DeepL

---

**Get Started**: [Download Latest Release](https://github.com/yourusername/twmt/releases) | [Read Documentation](docs/user_guide.md) | [Report Issues](https://github.com/yourusername/twmt/issues)

**Made with** ❤️ **for the Total War modding community**
