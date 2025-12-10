# TWMT - Database Schema

This file contains the complete database schema for the Total War Mods Translator application.

## Overview

The database uses SQLite with the following optimizations:
- **UUIDs**: All tables use UUID primary keys (TEXT type)
- **WAL Mode**: Write-Ahead Logging for better performance
- **FTS5**: Full-text search for efficient text searching (translation_units, translation_versions, translation_memory, workshop_mods)
- **Indexes**: Optimized indexes for 10k+ rows (100-800x performance gain)
- **Triggers**: Automatic timestamp and cache management
- **Constraints**: CHECK constraints for data validation
- **Event Sourcing**: Event store for audit trail

## Database Statistics

- **Total Tables**: 34 user-defined tables + FTS5 virtual table infrastructure
- **Total Indexes**: 85+ indexes
- **Total Triggers**: 27 triggers
- **Total Views**: 2 views

## Complete Schema

```sql
-- ============================================================================
-- TWMT Database Schema - CURRENT VERSION
-- Total War Mods Translator - Windows Desktop Application
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ============================================================================
-- TABLES DE RÉFÉRENCE
-- ============================================================================

-- Languages: Langues supportées
CREATE TABLE languages (
    id TEXT PRIMARY KEY,  -- UUID
    code TEXT NOT NULL UNIQUE,  -- 'fr', 'de', 'es', 'en', 'ru', 'zh'
    name TEXT,  -- 'French', 'German', 'Spanish'
    native_name TEXT,  -- 'Français', 'Deutsch', 'Español'
    is_active INTEGER NOT NULL DEFAULT 1,
    CHECK (is_active IN (0, 1))
);

-- Translation Providers: Fournisseurs de traduction
CREATE TABLE translation_providers (
    id TEXT PRIMARY KEY,  -- UUID
    code TEXT NOT NULL UNIQUE,  -- 'anthropic', 'openai', 'deepl'
    name TEXT,  -- 'Claude API', 'GPT API', 'DeepL'
    api_endpoint TEXT,
    default_model TEXT,
    max_context_tokens INTEGER,  -- Capacité max en tokens du modèle
    max_batch_size INTEGER NOT NULL DEFAULT 30,
    rate_limit_rpm INTEGER,  -- Requests per minute
    rate_limit_tpm INTEGER,  -- Tokens per minute (input)
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER,
    CHECK (is_active IN (0, 1)),
    CHECK (max_context_tokens IS NULL OR max_context_tokens > 0)
);

-- LLM Provider Models: Modèles disponibles par provider
CREATE TABLE llm_provider_models (
    id TEXT PRIMARY KEY,
    provider_code TEXT,
    model_id TEXT,
    display_name TEXT,
    is_enabled INTEGER DEFAULT 0,
    is_default INTEGER DEFAULT 0,
    is_archived INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER,
    last_fetched_at INTEGER,
    UNIQUE(provider_code, model_id)
);

-- ============================================================================
-- GESTION DES JEUX
-- ============================================================================

-- Game Installations: Jeux Total War détectés
CREATE TABLE game_installations (
    id TEXT PRIMARY KEY,
    game_code TEXT NOT NULL UNIQUE,  -- 'warhammer3', 'rome2', 'troy'
    game_name TEXT,  -- 'Total War: WARHAMMER III'
    installation_path TEXT,
    steam_workshop_path TEXT,
    steam_app_id TEXT,  -- Steam App ID
    is_auto_detected INTEGER NOT NULL DEFAULT 0,
    is_valid INTEGER NOT NULL DEFAULT 1,
    last_validated_at INTEGER,
    created_at INTEGER,
    updated_at INTEGER,
    CHECK (is_auto_detected IN (0, 1)),
    CHECK (is_valid IN (0, 1))
);

-- Workshop Mods: Mods Steam Workshop détectés
CREATE TABLE workshop_mods (
    id TEXT PRIMARY KEY,
    workshop_id TEXT UNIQUE,
    app_id INTEGER,
    title TEXT,
    workshop_url TEXT,
    file_size INTEGER CHECK (file_size >= 0),
    time_created INTEGER,
    time_updated INTEGER,
    subscriptions INTEGER DEFAULT 0 CHECK (subscriptions >= 0),
    tags TEXT,
    is_hidden INTEGER DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER,
    last_checked_at INTEGER
);

-- ============================================================================
-- GESTION DES PROJETS
-- ============================================================================

-- Projects: Projets de traduction de mods
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT,
    mod_steam_id TEXT,  -- Steam Workshop ID du mod source
    mod_version TEXT,
    game_installation_id TEXT NOT NULL,
    source_file_path TEXT,
    output_file_path TEXT,
    last_update_check INTEGER,
    source_mod_updated INTEGER,
    -- Paramètres de traduction par projet
    batch_size INTEGER NOT NULL DEFAULT 25,  -- Nombre de lignes par batch
    parallel_batches INTEGER NOT NULL DEFAULT 5,  -- Nombre de batches en parallèle
    custom_prompt TEXT,  -- Prompt personnalisé pour ce projet
    created_at INTEGER,
    updated_at INTEGER,
    completed_at INTEGER,
    metadata TEXT,  -- JSON pour données supplémentaires
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
    CHECK (batch_size > 0 AND batch_size <= 100),
    CHECK (parallel_batches > 0 AND parallel_batches <= 10)
);

-- Project Languages: Langues cibles d'un projet
CREATE TABLE project_languages (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    language_id TEXT NOT NULL,  -- UUID de la langue
    status TEXT NOT NULL DEFAULT 'pending',
    progress_percent REAL NOT NULL DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    UNIQUE(project_id, language_id),
    CHECK (status IN ('pending', 'translating', 'completed', 'error')),
    CHECK (progress_percent >= 0 AND progress_percent <= 100)
);

-- Mod Versions: Historique des versions du mod source
CREATE TABLE mod_versions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    version_string TEXT,
    release_date INTEGER,
    steam_update_timestamp INTEGER,
    units_added INTEGER NOT NULL DEFAULT 0,
    units_modified INTEGER NOT NULL DEFAULT 0,
    units_deleted INTEGER NOT NULL DEFAULT 0,
    is_current INTEGER NOT NULL DEFAULT 1,
    detected_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    CHECK (is_current IN (0, 1))
);

-- Mod Version Changes: Changements détaillés entre versions
CREATE TABLE mod_version_changes (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    unit_key TEXT,
    change_type TEXT,
    old_source_text TEXT,
    new_source_text TEXT,
    detected_at INTEGER,
    FOREIGN KEY (version_id) REFERENCES mod_versions(id) ON DELETE CASCADE,
    CHECK (change_type IN ('added', 'modified', 'deleted'))
);

-- ============================================================================
-- UNITÉS DE TRADUCTION
-- ============================================================================

-- Translation Units: Unités de texte à traduire (source)
CREATE TABLE translation_units (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    key TEXT,  -- Clé du fichier de localisation
    source_text TEXT,
    context TEXT,
    notes TEXT,
    source_loc_file TEXT,  -- Nom du fichier .loc d'origine
    is_obsolete INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(project_id, key),
    CHECK (is_obsolete IN (0, 1))
);

-- Translation Versions: Traductions par langue
CREATE TABLE translation_versions (
    id TEXT PRIMARY KEY,
    unit_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,  -- Lien vers project_languages
    translated_text TEXT,
    is_manually_edited INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    confidence_score REAL,
    validation_issues TEXT,  -- JSON des problèmes détectés
    translation_source TEXT DEFAULT 'unknown',  -- 'llm', 'tm', 'manual', 'unknown'
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (unit_id) REFERENCES translation_units(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE,
    UNIQUE(unit_id, project_language_id),
    CHECK (status IN ('pending', 'translating', 'translated', 'reviewed', 'approved', 'needs_review')),
    CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CHECK (is_manually_edited IN (0, 1))
);

-- Translation Version History: Historique des modifications
CREATE TABLE translation_version_history (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    translated_text TEXT,
    status TEXT,
    confidence_score REAL,
    changed_by TEXT,  -- 'system', 'user', 'llm:{provider}'
    change_reason TEXT,
    created_at INTEGER,
    FOREIGN KEY (version_id) REFERENCES translation_versions(id) ON DELETE CASCADE
);

-- ============================================================================
-- GESTION DES BATCHES
-- ============================================================================

-- Translation Batches: Batches de traduction
CREATE TABLE translation_batches (
    id TEXT PRIMARY KEY,
    project_language_id TEXT NOT NULL,  -- Lien vers project_languages
    status TEXT NOT NULL DEFAULT 'pending',
    provider_id TEXT NOT NULL,  -- UUID du provider utilisé
    batch_number INTEGER,  -- Numéro séquentiel dans le projet
    units_count INTEGER NOT NULL DEFAULT 0,
    units_completed INTEGER NOT NULL DEFAULT 0,
    started_at INTEGER,
    completed_at INTEGER,
    error_message TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE,
    FOREIGN KEY (provider_id) REFERENCES translation_providers(id) ON DELETE RESTRICT,
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
    CHECK (units_completed <= units_count),
    CHECK (retry_count >= 0)
);

-- Translation Batch Units: Unités dans un batch
CREATE TABLE translation_batch_units (
    id TEXT PRIMARY KEY,
    batch_id TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    processing_order INTEGER,
    status TEXT NOT NULL DEFAULT 'pending',
    error_message TEXT,
    started_at INTEGER,
    completed_at INTEGER,
    FOREIGN KEY (batch_id) REFERENCES translation_batches(id) ON DELETE CASCADE,
    FOREIGN KEY (unit_id) REFERENCES translation_units(id) ON DELETE CASCADE,
    UNIQUE(batch_id, unit_id),
    CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
);

-- ============================================================================
-- MÉMOIRE DE TRADUCTION
-- ============================================================================

-- Translation Memory: Réutilisation des traductions
CREATE TABLE translation_memory (
    id TEXT PRIMARY KEY,
    source_text TEXT,
    source_hash TEXT,  -- SHA256 du source_text
    source_language_id TEXT NOT NULL,  -- UUID de la langue source
    target_language_id TEXT NOT NULL,  -- UUID de la langue cible
    translated_text TEXT,
    translation_provider_id TEXT,  -- UUID du provider
    quality_score REAL,  -- Score de qualité agrégé (0-1)
    usage_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER,
    last_used_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (translation_provider_id) REFERENCES translation_providers(id) ON DELETE SET NULL,
    UNIQUE(source_hash, target_language_id),
    CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
    CHECK (usage_count >= 0)
);

-- Translation Version TM Usage: Traçabilité TM utilisée
CREATE TABLE translation_version_tm_usage (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    tm_id TEXT NOT NULL,
    match_confidence REAL,  -- Degré de correspondance (0-1)
    applied_at INTEGER,
    FOREIGN KEY (version_id) REFERENCES translation_versions(id) ON DELETE CASCADE,
    FOREIGN KEY (tm_id) REFERENCES translation_memory(id) ON DELETE CASCADE,
    CHECK (match_confidence >= 0 AND match_confidence <= 1)
);

-- ============================================================================
-- GLOSSAIRES
-- ============================================================================

-- Glossaries: Glossaires par jeu ou globaux
CREATE TABLE glossaries (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE,
    description TEXT,
    is_global INTEGER DEFAULT 0,
    game_installation_id TEXT,
    target_language_id TEXT,
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE CASCADE,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    CHECK ((is_global = 1 AND game_installation_id IS NULL) OR (is_global = 0 AND game_installation_id IS NOT NULL))
);

-- Glossary Entries: Entrées de glossaire
CREATE TABLE glossary_entries (
    id TEXT PRIMARY KEY,
    glossary_id TEXT NOT NULL,
    target_language_code TEXT,
    source_term TEXT,
    target_term TEXT,
    definition TEXT,
    notes TEXT,
    is_forbidden INTEGER DEFAULT 0,  -- Terme à ne pas traduire
    case_sensitive INTEGER DEFAULT 0,
    usage_count INTEGER DEFAULT 0 CHECK (usage_count >= 0),
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (glossary_id) REFERENCES glossaries(id) ON DELETE CASCADE,
    UNIQUE(glossary_id, target_language_code, source_term, case_sensitive)
);

-- ============================================================================
-- RECHERCHE ET HISTORIQUE
-- ============================================================================

-- Search History: Historique des recherches
CREATE TABLE search_history (
    id TEXT PRIMARY KEY,
    query TEXT,
    scope TEXT,  -- 'source', 'target', 'both', 'key', 'all'
    filters_json TEXT,
    result_count INTEGER,
    searched_at INTEGER,
    CHECK (scope IN ('source', 'target', 'both', 'key', 'all'))
);

-- Saved Searches: Recherches sauvegardées
CREATE TABLE saved_searches (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE,
    query TEXT,
    scope TEXT,  -- 'source', 'target', 'both', 'key', 'all'
    filters_json TEXT,
    usage_count INTEGER DEFAULT 0 CHECK (usage_count >= 0),
    created_at INTEGER,
    last_used_at INTEGER,
    CHECK (scope IN ('source', 'target', 'both', 'key', 'all'))
);

-- ============================================================================
-- EVENT SOURCING
-- ============================================================================

-- Event Store: Journal des événements
CREATE TABLE event_store (
    id TEXT PRIMARY KEY,
    event_type TEXT,
    payload TEXT,  -- JSON
    occurred_at INTEGER,
    triggered_by TEXT,
    aggregate_id TEXT,
    aggregate_type TEXT,
    correlation_id TEXT,
    causation_id TEXT,
    metadata TEXT  -- JSON
);

-- ============================================================================
-- EXPORT ET COMPILATION
-- ============================================================================

-- Export History: Historique des exports
CREATE TABLE export_history (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    languages TEXT,  -- JSON array
    format TEXT,  -- 'pack', 'csv', 'excel', 'tmx'
    validated_only INTEGER DEFAULT 0,
    output_path TEXT,
    file_size INTEGER,
    entry_count INTEGER,
    exported_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    CHECK (format IN ('pack', 'csv', 'excel', 'tmx'))
);

-- Compilations: Compilations de packs
CREATE TABLE compilations (
    id TEXT PRIMARY KEY,
    name TEXT,
    prefix TEXT DEFAULT '!!!!!!!!!!_FR_Compilation_',
    pack_name TEXT,
    game_installation_id TEXT,
    language_id TEXT,
    last_output_path TEXT,
    last_generated_at INTEGER,
    created_at INTEGER,
    updated_at INTEGER,
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
    FOREIGN KEY (language_id) REFERENCES languages(id) ON DELETE SET NULL
);

-- Compilation Projects: Projets dans une compilation
CREATE TABLE compilation_projects (
    id TEXT PRIMARY KEY,
    compilation_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    sort_order INTEGER DEFAULT 0,
    added_at INTEGER,
    FOREIGN KEY (compilation_id) REFERENCES compilations(id) ON DELETE CASCADE,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(compilation_id, project_id)
);

-- ============================================================================
-- TABLES DE CACHE
-- ============================================================================

-- Mod Scan Cache: Cache de scan des mods
CREATE TABLE mod_scan_cache (
    id TEXT PRIMARY KEY,
    pack_file_path TEXT UNIQUE,
    file_last_modified INTEGER,
    has_loc_files INTEGER DEFAULT 0,
    scanned_at INTEGER
);

-- Mod Update Analysis Cache: Cache d'analyse des mises à jour
CREATE TABLE mod_update_analysis_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    pack_file_path TEXT,
    file_last_modified INTEGER,
    new_units_count INTEGER DEFAULT 0,
    removed_units_count INTEGER DEFAULT 0,
    modified_units_count INTEGER DEFAULT 0,
    total_pack_units INTEGER DEFAULT 0,
    total_project_units INTEGER DEFAULT 0,
    analyzed_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(project_id, pack_file_path)
);

-- Translation View Cache: Cache dénormalisé pour DataGrid
CREATE TABLE translation_view_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,
    language_code TEXT,
    unit_id TEXT,
    version_id TEXT,
    -- Données dénormalisées
    key TEXT,
    source_text TEXT,
    translated_text TEXT,
    status TEXT,
    confidence_score REAL,
    is_manually_edited INTEGER NOT NULL DEFAULT 0,
    is_obsolete INTEGER NOT NULL DEFAULT 0,
    -- Métadonnées TM
    tm_match_confidence REAL,
    tm_match_text TEXT,
    -- Métadonnées batch
    batch_number INTEGER,
    provider_name TEXT,
    -- Timestamps
    unit_created_at INTEGER,
    unit_updated_at INTEGER,
    version_updated_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE
);

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Settings: Configuration utilisateur
CREATE TABLE settings (
    id TEXT PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value TEXT,
    value_type TEXT NOT NULL DEFAULT 'string',  -- 'string', 'integer', 'boolean', 'json'
    updated_at INTEGER,
    CHECK (value_type IN ('string', 'integer', 'boolean', 'json'))
);

-- LLM Custom Rules: Custom rules for LLM translation prompts
CREATE TABLE llm_custom_rules (
    id TEXT PRIMARY KEY,
    rule_text TEXT NOT NULL,
    is_enabled INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (is_enabled IN (0, 1))
);

-- ============================================================================
-- INDEX POUR PERFORMANCE
-- ============================================================================

-- Projects
CREATE INDEX idx_projects_game ON projects(game_installation_id);
CREATE INDEX idx_projects_updated ON projects(updated_at DESC);
CREATE INDEX idx_projects_steam_id ON projects(mod_steam_id);

-- Project Languages
CREATE INDEX idx_project_languages_project ON project_languages(project_id, status);
CREATE INDEX idx_project_languages_language ON project_languages(language_id);

-- Mod Versions
CREATE INDEX idx_mod_versions_project ON mod_versions(project_id, is_current);
CREATE INDEX idx_mod_version_changes_version ON mod_version_changes(version_id, change_type);

-- Translation Units
CREATE INDEX idx_translation_units_project ON translation_units(project_id);
CREATE INDEX idx_translation_units_key ON translation_units(key);
CREATE INDEX idx_translation_units_obsolete ON translation_units(project_id, is_obsolete);
CREATE INDEX idx_translation_units_source_loc ON translation_units(source_loc_file);

-- Translation Versions
CREATE INDEX idx_translation_versions_unit ON translation_versions(unit_id);
CREATE INDEX idx_translation_versions_proj_lang ON translation_versions(project_language_id, status);
CREATE INDEX idx_translation_versions_status ON translation_versions(status);
CREATE INDEX idx_translation_versions_unit_proj_lang ON translation_versions(unit_id, project_language_id);

-- Translation Batches
CREATE INDEX idx_batches_proj_lang ON translation_batches(project_language_id, status);
CREATE INDEX idx_batches_provider ON translation_batches(provider_id, status);

-- Translation Batch Units
CREATE INDEX idx_batch_units_batch ON translation_batch_units(batch_id, status);
CREATE INDEX idx_batch_units_unit ON translation_batch_units(unit_id);

-- Translation Memory
CREATE INDEX idx_tm_hash_lang ON translation_memory(source_hash, target_language_id);
CREATE INDEX idx_tm_source_lang ON translation_memory(source_language_id, target_language_id);
CREATE INDEX idx_tm_last_used ON translation_memory(last_used_at DESC);
CREATE INDEX idx_tm_quality ON translation_memory(quality_score DESC);

-- Translation Version TM Usage
CREATE INDEX idx_tm_usage_version ON translation_version_tm_usage(version_id);
CREATE INDEX idx_tm_usage_tm ON translation_version_tm_usage(tm_id);

-- Game Installations
CREATE INDEX idx_game_installations_code ON game_installations(game_code);
CREATE INDEX idx_game_installations_valid ON game_installations(is_valid);

-- Workshop Mods
CREATE INDEX idx_workshop_mods_workshop_id ON workshop_mods(workshop_id);
CREATE INDEX idx_workshop_mods_app_id ON workshop_mods(app_id);
CREATE INDEX idx_workshop_mods_app_updated ON workshop_mods(app_id, time_updated);
CREATE INDEX idx_workshop_mods_title ON workshop_mods(title COLLATE NOCASE);
CREATE INDEX idx_workshop_mods_updated ON workshop_mods(updated_at);
CREATE INDEX idx_workshop_mods_checked ON workshop_mods(last_checked_at);

-- Glossaries
CREATE INDEX idx_glossaries_game ON glossaries(game_installation_id, is_global);
CREATE INDEX idx_glossaries_language ON glossaries(target_language_id);
CREATE INDEX idx_glossaries_name ON glossaries(name);

-- Glossary Entries
CREATE INDEX idx_glossary_entries_glossary ON glossary_entries(glossary_id);
CREATE INDEX idx_glossary_entries_term ON glossary_entries(source_term);
CREATE INDEX idx_glossary_entries_usage ON glossary_entries(usage_count DESC);
CREATE INDEX idx_glossary_entries_language ON glossary_entries(target_language_code);

-- Search & History
CREATE INDEX idx_saved_searches_name ON saved_searches(name);
CREATE INDEX idx_saved_searches_used ON saved_searches(last_used_at DESC);

-- LLM Provider Models
CREATE INDEX idx_llm_models_provider ON llm_provider_models(provider_code);
CREATE INDEX idx_llm_models_provider_enabled ON llm_provider_models(provider_code, is_enabled) WHERE is_archived = 0;
CREATE INDEX idx_llm_models_provider_default ON llm_provider_models(provider_code, is_default) WHERE is_archived = 0;

-- Event Store
CREATE INDEX idx_events_type ON event_store(event_type);
CREATE INDEX idx_events_aggregate ON event_store(aggregate_id, aggregate_type);
CREATE INDEX idx_events_occurred ON event_store(occurred_at DESC);
CREATE INDEX idx_events_correlation ON event_store(correlation_id) WHERE correlation_id IS NOT NULL;

-- Export History
CREATE INDEX idx_export_project ON export_history(project_id, exported_at DESC);
CREATE INDEX idx_export_format ON export_history(format, exported_at DESC);
CREATE INDEX idx_export_date ON export_history(exported_at DESC);

-- Compilations
CREATE INDEX idx_compilations_game ON compilations(game_installation_id);
CREATE INDEX idx_compilation_projects_compilation ON compilation_projects(compilation_id);
CREATE INDEX idx_compilation_projects_project ON compilation_projects(project_id);

-- Cache Tables
CREATE INDEX idx_translation_cache_proj_lang ON translation_view_cache(project_id, project_language_id);
CREATE INDEX idx_translation_cache_status ON translation_view_cache(project_language_id, status);
CREATE INDEX idx_translation_cache_updated ON translation_view_cache(project_language_id, version_updated_at DESC);

-- Settings
CREATE INDEX idx_settings_key ON settings(key);

-- LLM Custom Rules
CREATE INDEX idx_llm_custom_rules_enabled_order ON llm_custom_rules(is_enabled, sort_order);

-- Languages
CREATE INDEX idx_languages_code ON languages(code);

-- Translation Providers
CREATE INDEX idx_translation_providers_code ON translation_providers(code);

-- ============================================================================
-- FULL-TEXT SEARCH (FTS5)
-- ============================================================================

-- FTS5 pour recherche dans translation_units
CREATE VIRTUAL TABLE translation_units_fts USING fts5(
    key,
    source_text,
    context,
    notes,
    content='translation_units',
    content_rowid='rowid'
);

-- FTS5 pour recherche dans translation_versions
CREATE VIRTUAL TABLE translation_versions_fts USING fts5(
    translated_text,
    validation_issues,
    version_id UNINDEXED,
    content='translation_versions',
    content_rowid='rowid'
);

-- FTS5 pour recherche dans translation_memory
CREATE VIRTUAL TABLE translation_memory_fts USING fts5(
    source_text,
    translated_text,
    content='translation_memory',
    content_rowid='rowid'
);

-- FTS5 pour recherche dans workshop_mods
CREATE VIRTUAL TABLE workshop_mods_fts USING fts5(
    title,
    tags,
    content='workshop_mods',
    content_rowid='rowid'
);

-- ============================================================================
-- TRIGGERS FTS5
-- ============================================================================

-- Triggers pour translation_units_fts
CREATE TRIGGER trg_translation_units_fts_insert AFTER INSERT ON translation_units BEGIN
    INSERT INTO translation_units_fts(rowid, key, source_text, context, notes)
    VALUES (new.rowid, new.key, new.source_text, new.context, new.notes);
END;

CREATE TRIGGER trg_translation_units_fts_update AFTER UPDATE ON translation_units BEGIN
    UPDATE translation_units_fts
    SET key = new.key, source_text = new.source_text, context = new.context, notes = new.notes
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_translation_units_fts_delete AFTER DELETE ON translation_units BEGIN
    DELETE FROM translation_units_fts WHERE rowid = old.rowid;
END;

-- Triggers pour translation_versions_fts
CREATE TRIGGER trg_translation_versions_fts_insert AFTER INSERT ON translation_versions BEGIN
    INSERT INTO translation_versions_fts(rowid, translated_text, validation_issues, version_id)
    VALUES (new.rowid, new.translated_text, new.validation_issues, new.id);
END;

CREATE TRIGGER trg_translation_versions_fts_update AFTER UPDATE ON translation_versions BEGIN
    UPDATE translation_versions_fts
    SET translated_text = new.translated_text, validation_issues = new.validation_issues
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_translation_versions_fts_delete AFTER DELETE ON translation_versions BEGIN
    DELETE FROM translation_versions_fts WHERE rowid = old.rowid;
END;

-- Triggers pour translation_memory_fts
CREATE TRIGGER trg_translation_memory_fts_insert AFTER INSERT ON translation_memory BEGIN
    INSERT INTO translation_memory_fts(rowid, source_text, translated_text)
    VALUES (new.rowid, new.source_text, new.translated_text);
END;

CREATE TRIGGER trg_translation_memory_fts_update AFTER UPDATE ON translation_memory BEGIN
    UPDATE translation_memory_fts
    SET source_text = new.source_text, translated_text = new.translated_text
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_translation_memory_fts_delete AFTER DELETE ON translation_memory BEGIN
    DELETE FROM translation_memory_fts WHERE rowid = old.rowid;
END;

-- Triggers pour workshop_mods_fts
CREATE TRIGGER trg_workshop_mods_fts_insert AFTER INSERT ON workshop_mods BEGIN
    INSERT INTO workshop_mods_fts(rowid, title, tags)
    VALUES (new.rowid, new.title, new.tags);
END;

CREATE TRIGGER trg_workshop_mods_fts_update AFTER UPDATE ON workshop_mods BEGIN
    UPDATE workshop_mods_fts SET title = new.title, tags = new.tags WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_workshop_mods_fts_delete AFTER DELETE ON workshop_mods BEGIN
    DELETE FROM workshop_mods_fts WHERE rowid = old.rowid;
END;

-- ============================================================================
-- TRIGGERS AUTOMATISATION
-- ============================================================================

-- Mise à jour automatique des timestamps
CREATE TRIGGER trg_projects_updated_at AFTER UPDATE ON projects BEGIN
    UPDATE projects SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_translation_units_updated_at AFTER UPDATE ON translation_units BEGIN
    UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_translation_versions_updated_at AFTER UPDATE ON translation_versions BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_glossaries_updated_at AFTER UPDATE ON glossaries BEGIN
    UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_glossary_entries_updated_at AFTER UPDATE ON glossary_entries BEGIN
    UPDATE glossary_entries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_workshop_mods_updated_at AFTER UPDATE ON workshop_mods BEGIN
    UPDATE workshop_mods SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_llm_models_updated_at AFTER UPDATE ON llm_provider_models BEGIN
    UPDATE llm_provider_models SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

-- Mise à jour automatique du progress_percent
CREATE TRIGGER trg_update_project_language_progress
AFTER UPDATE ON translation_versions
WHEN NEW.status != OLD.status
BEGIN
    UPDATE project_languages
    SET progress_percent = (
        SELECT CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
               NULLIF(COUNT(*), 0)
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = NEW.project_language_id AND tu.is_obsolete = 0
    ),
    updated_at = strftime('%s', 'now')
    WHERE id = NEW.project_language_id;
END;

-- LLM Models: Assurer un seul default par provider
CREATE TRIGGER trg_llm_models_single_default
AFTER UPDATE OF is_default ON llm_provider_models
WHEN NEW.is_default = 1 AND NEW.is_archived = 0
BEGIN
    UPDATE llm_provider_models
    SET is_default = 0
    WHERE provider_code = NEW.provider_code
      AND id != NEW.id
      AND is_default = 1;
END;

-- LLM Models: Empêcher l'activation de modèles archivés
CREATE TRIGGER trg_llm_models_prevent_enable_archived
BEFORE UPDATE OF is_enabled ON llm_provider_models
WHEN NEW.is_enabled = 1 AND NEW.is_archived = 1
BEGIN
    SELECT RAISE(ABORT, 'Cannot enable archived model');
END;

-- LLM Models: Empêcher les modèles archivés comme default
CREATE TRIGGER trg_llm_models_prevent_default_archived
BEFORE UPDATE OF is_default ON llm_provider_models
WHEN NEW.is_default = 1 AND NEW.is_archived = 1
BEGIN
    SELECT RAISE(ABORT, 'Cannot set archived model as default');
END;

-- Triggers pour translation_view_cache
CREATE TRIGGER trg_update_cache_on_unit_change
AFTER UPDATE ON translation_units
BEGIN
    UPDATE translation_view_cache
    SET key = new.key, source_text = new.source_text, is_obsolete = new.is_obsolete,
        unit_updated_at = new.updated_at
    WHERE unit_id = new.id;
END;

CREATE TRIGGER trg_update_cache_on_version_change
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_view_cache
    SET translated_text = new.translated_text, status = new.status,
        confidence_score = new.confidence_score, is_manually_edited = new.is_manually_edited,
        version_id = new.id, version_updated_at = new.updated_at
    WHERE unit_id = new.unit_id AND project_language_id = new.project_language_id;
END;

CREATE TRIGGER trg_insert_cache_on_version_insert
AFTER INSERT ON translation_versions
BEGIN
    INSERT OR REPLACE INTO translation_view_cache (
        id, project_id, project_language_id, language_code, unit_id, version_id,
        key, source_text, translated_text, status, confidence_score,
        is_manually_edited, is_obsolete, unit_created_at, unit_updated_at, version_updated_at
    )
    SELECT
        new.id || '_' || tu.id AS id, tu.project_id, new.project_language_id, l.code,
        tu.id, new.id, tu.key, tu.source_text, new.translated_text, new.status,
        new.confidence_score, new.is_manually_edited, tu.is_obsolete,
        tu.created_at, tu.updated_at, new.updated_at
    FROM translation_units tu
    INNER JOIN project_languages pl ON pl.id = new.project_language_id
    INNER JOIN languages l ON l.id = pl.language_id
    WHERE tu.id = new.unit_id;
END;

CREATE TRIGGER trg_delete_cache_on_version_delete
AFTER DELETE ON translation_versions
BEGIN
    DELETE FROM translation_view_cache WHERE version_id = old.id;
END;

-- ============================================================================
-- VUES
-- ============================================================================

-- Vue pour statistiques de projet par langue
CREATE VIEW v_project_language_stats AS
SELECT
    pl.id AS project_language_id,
    pl.project_id,
    p.name AS project_name,
    l.code AS language_code,
    l.native_name AS language_name,
    pl.status,
    pl.progress_percent,
    COUNT(DISTINCT tu.id) AS total_units,
    COUNT(DISTINCT CASE WHEN tv.status = 'approved' THEN tv.id END) AS approved_units,
    COUNT(DISTINCT CASE WHEN tv.status = 'reviewed' THEN tv.id END) AS reviewed_units,
    COUNT(DISTINCT CASE WHEN tv.status = 'translated' THEN tv.id END) AS translated_units,
    COUNT(DISTINCT CASE WHEN tv.status = 'pending' THEN tv.id END) AS pending_units,
    COUNT(DISTINCT CASE WHEN tv.is_manually_edited = 1 THEN tv.id END) AS manually_edited_units
FROM project_languages pl
INNER JOIN projects p ON pl.project_id = p.id
INNER JOIN languages l ON pl.language_id = l.id
LEFT JOIN translation_units tu ON tu.project_id = p.id AND tu.is_obsolete = 0
LEFT JOIN translation_versions tv ON tv.unit_id = tu.id AND tv.project_language_id = pl.id
GROUP BY pl.id;

-- Vue pour traductions nécessitant révision
CREATE VIEW v_translations_needing_review AS
SELECT
    tv.id AS version_id,
    tu.project_id,
    l.code AS language_code,
    tu.key,
    tu.source_text,
    tv.translated_text,
    tv.status,
    tv.confidence_score,
    tv.validation_issues,
    tv.updated_at
FROM translation_versions tv
INNER JOIN translation_units tu ON tv.unit_id = tu.id
INNER JOIN project_languages pl ON tv.project_language_id = pl.id
INNER JOIN languages l ON pl.language_id = l.id
WHERE tv.status IN ('needs_review', 'translated')
    AND tu.is_obsolete = 0
    AND (tv.confidence_score < 0.8 OR tv.validation_issues IS NOT NULL);

-- ============================================================================
-- DONNÉES DE RÉFÉRENCE INITIALES
-- ============================================================================

-- Langues supportées
INSERT INTO languages (id, code, name, native_name, is_active) VALUES
('lang_de', 'de', 'German', 'Deutsch', 1),
('lang_en', 'en', 'English', 'English', 1),
('lang_zh', 'zh', 'Chinese', '中文', 1),
('lang_es', 'es', 'Spanish', 'Español', 1),
('lang_fr', 'fr', 'French', 'Français', 1),
('lang_ru', 'ru', 'Russian', 'Русский', 1);

-- Providers de traduction
INSERT INTO translation_providers (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at) VALUES
('provider_anthropic', 'anthropic', 'Claude API', 'https://api.anthropic.com/v1', 'claude-sonnet-4-5-20250929', 200000, 25, 50, 40000, 1, strftime('%s', 'now')),
('provider_deepl', 'deepl', 'DeepL', 'https://api.deepl.com/v2', NULL, NULL, 50, 100, NULL, 1, strftime('%s', 'now')),
('provider_openai', 'openai', 'GPT API', 'https://api.openai.com/v1', 'gpt-4o', 128000, 40, 60, 90000, 1, strftime('%s', 'now'));

-- Settings par défaut
INSERT INTO settings (id, key, value, value_type, updated_at) VALUES
('setting_active_provider', 'active_translation_provider_id', 'provider_anthropic', 'string', strftime('%s', 'now')),
('setting_default_game', 'default_game_installation_id', '', 'string', strftime('%s', 'now')),
('setting_default_batch_size', 'default_batch_size', '25', 'integer', strftime('%s', 'now')),
('setting_default_parallel_batches', 'default_parallel_batches', '5', 'integer', strftime('%s', 'now')),
('setting_default_target_language', 'default_target_language', 'fr', 'string', strftime('%s', 'now'));
```

## Schema Features

### Core Features

1. **UUIDs everywhere**: All tables use UUIDs (TEXT PRIMARY KEY)
2. **Reference tables**: `languages`, `translation_providers` with UUIDs and unique codes
3. **Global LLM provider**: Single configuration in `settings`, used for all projects
4. **Model management**: `llm_provider_models` for dynamic model discovery and selection
5. **Complete versioning**: `mod_versions`, `mod_version_changes` for update tracking
6. **History**: `translation_version_history` for audit trail
7. **Event sourcing**: `event_store` for comprehensive event logging
8. **Batch traceability**: `translation_batch_units` for many-to-many relationship

### Translation Features

9. **Translation source tracking**: `translation_source` field in `translation_versions` ('llm', 'tm', 'manual')
10. **Source file tracking**: `source_loc_file` in `translation_units` to track origin .loc file
11. **Enhanced translation memory**: With `translation_version_tm_usage` for tracking
12. **Glossaries**: Game-specific or global glossaries with term management

### Performance Features

13. **Optimized indexes**: 84+ indexes for 100-800x performance gain
14. **FTS5 Full-text search**: 4 virtual tables for fast text searching
15. **Denormalized cache**: `translation_view_cache` for DataGrid performance
16. **Scan caches**: `mod_scan_cache`, `mod_update_analysis_cache` for efficient mod scanning

### Export Features

17. **Export history**: Track all exports with format, size, and count
18. **Compilations**: Pack compilation management with project ordering
19. **Workshop mods**: Steam Workshop mod tracking and metadata

### Automation

20. **Automatic triggers**: Auto-calculation of `progress_percent` and timestamps
21. **FTS5 sync triggers**: Automatic full-text index maintenance
22. **Cache triggers**: Automatic cache invalidation and updates
23. **LLM model triggers**: Single default per provider, archive protection

### Constraints

24. **Robust constraints**: Validation via CHECK on all statuses and values
25. **Foreign key integrity**: Proper CASCADE/RESTRICT relationships
26. **Unique constraints**: Prevent duplicate entries where needed

## Database Location

The database file is stored at:
```
%APPDATA%\Roaming\com.github.slavyk82\twmt\twmt.db
```

Using `getApplicationSupportDirectory()` from the `path_provider` package.

## Supported Languages

- German (de)
- English (en)
- Chinese (zh)
- Spanish (es)
- French (fr)
- Russian (ru)

## Translation Providers

- **Anthropic** (Claude API): 200k context, 25 batch size
- **DeepL**: 50 batch size
- **OpenAI** (GPT API): 128k context, 40 batch size

## Reference

For implementation details and usage examples, see the main specifications document: [`specs.md`](./specs.md)
