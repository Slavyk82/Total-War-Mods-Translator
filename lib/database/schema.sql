-- ============================================================================
-- TWMT Database Schema
-- Total War Mods Translator - Complete SQLite Database Schema
-- ============================================================================
-- Description: Full database schema for fresh installations
-- Database: SQLite with FTS5, WAL mode, Foreign Keys enabled
-- ============================================================================

-- Enable foreign keys and WAL mode for performance
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ============================================================================
-- REFERENCE TABLES
-- ============================================================================

-- Languages: Supported languages
CREATE TABLE IF NOT EXISTS languages (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    native_name TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    CHECK (is_active IN (0, 1))
);

-- Translation Providers: Translation service providers
CREATE TABLE IF NOT EXISTS translation_providers (
    id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    api_endpoint TEXT,
    default_model TEXT,
    max_context_tokens INTEGER,
    max_batch_size INTEGER NOT NULL DEFAULT 30,
    rate_limit_rpm INTEGER,
    rate_limit_tpm INTEGER,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    CHECK (is_active IN (0, 1)),
    CHECK (max_context_tokens IS NULL OR max_context_tokens > 0)
);

-- ============================================================================
-- GAME MANAGEMENT
-- ============================================================================

-- Game Installations: Detected Total War games
CREATE TABLE IF NOT EXISTS game_installations (
    id TEXT PRIMARY KEY,
    game_code TEXT NOT NULL UNIQUE,
    game_name TEXT NOT NULL,
    installation_path TEXT,
    steam_workshop_path TEXT,
    steam_app_id TEXT,
    is_auto_detected INTEGER NOT NULL DEFAULT 0,
    is_valid INTEGER NOT NULL DEFAULT 1,
    last_validated_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (is_auto_detected IN (0, 1)),
    CHECK (is_valid IN (0, 1)),
    CHECK (created_at <= updated_at)
);

-- ============================================================================
-- PROJECT MANAGEMENT
-- ============================================================================

-- Projects: Mod translation projects
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    mod_steam_id TEXT,
    mod_version TEXT,
    game_installation_id TEXT NOT NULL,
    source_file_path TEXT,
    output_file_path TEXT,
    last_update_check INTEGER,
    source_mod_updated INTEGER,
    batch_size INTEGER NOT NULL DEFAULT 25,
    parallel_batches INTEGER NOT NULL DEFAULT 5,
    custom_prompt TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    metadata TEXT,
    published_steam_id TEXT,
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
    CHECK (batch_size > 0 AND batch_size <= 100),
    CHECK (parallel_batches > 0 AND parallel_batches <= 20),
    CHECK (created_at <= updated_at)
);

-- Project Languages: Target languages for a project
CREATE TABLE IF NOT EXISTS project_languages (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    language_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    progress_percent REAL NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    UNIQUE(project_id, language_id),
    CHECK (status IN ('pending', 'translating', 'completed', 'error')),
    CHECK (progress_percent >= 0 AND progress_percent <= 100),
    CHECK (created_at <= updated_at)
);

-- Mod Versions: Source mod version history
CREATE TABLE IF NOT EXISTS mod_versions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    version_string TEXT NOT NULL,
    release_date INTEGER,
    steam_update_timestamp INTEGER,
    units_added INTEGER NOT NULL DEFAULT 0,
    units_modified INTEGER NOT NULL DEFAULT 0,
    units_deleted INTEGER NOT NULL DEFAULT 0,
    is_current INTEGER NOT NULL DEFAULT 1,
    detected_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    CHECK (is_current IN (0, 1))
);

-- Mod Version Changes: Detailed changes between versions
CREATE TABLE IF NOT EXISTS mod_version_changes (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    unit_key TEXT NOT NULL,
    change_type TEXT NOT NULL,
    old_source_text TEXT,
    new_source_text TEXT,
    detected_at INTEGER NOT NULL,
    FOREIGN KEY (version_id) REFERENCES mod_versions(id) ON DELETE CASCADE,
    CHECK (change_type IN ('added', 'modified', 'deleted'))
);

-- ============================================================================
-- TRANSLATION UNITS
-- ============================================================================

-- Translation Units: Text units to translate (source)
CREATE TABLE IF NOT EXISTS translation_units (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    key TEXT NOT NULL,
    source_text TEXT NOT NULL,
    context TEXT,
    notes TEXT,
    source_loc_file TEXT,
    is_obsolete INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(project_id, key),
    CHECK (is_obsolete IN (0, 1)),
    CHECK (created_at <= updated_at)
);

-- Translation Versions: Translations by language
CREATE TABLE IF NOT EXISTS translation_versions (
    id TEXT PRIMARY KEY,
    unit_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,
    translated_text TEXT,
    is_manually_edited INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending',
    translation_source TEXT DEFAULT 'unknown',
    validation_issues TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (unit_id) REFERENCES translation_units(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE,
    UNIQUE(unit_id, project_language_id),
    CHECK (status IN ('pending', 'translating', 'translated', 'reviewed', 'approved', 'needs_review')),
    CHECK (translation_source IN ('unknown', 'manual', 'tm_exact', 'tm_fuzzy', 'llm')),
    CHECK (is_manually_edited IN (0, 1)),
    CHECK (created_at <= updated_at)
);

-- Translation Version History: Change history
CREATE TABLE IF NOT EXISTS translation_version_history (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    status TEXT NOT NULL,
    changed_by TEXT NOT NULL,
    change_reason TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (version_id) REFERENCES translation_versions(id) ON DELETE CASCADE
);

-- ============================================================================
-- BATCH MANAGEMENT
-- ============================================================================

-- Translation Batches: Translation batches
CREATE TABLE IF NOT EXISTS translation_batches (
    id TEXT PRIMARY KEY,
    project_language_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    provider_id TEXT NOT NULL,
    batch_number INTEGER NOT NULL,
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

-- Translation Batch Units: Units in a batch
CREATE TABLE IF NOT EXISTS translation_batch_units (
    id TEXT PRIMARY KEY,
    batch_id TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    processing_order INTEGER NOT NULL,
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
-- TRANSLATION MEMORY
-- ============================================================================

-- Translation Memory: Translation reuse
CREATE TABLE IF NOT EXISTS translation_memory (
    id TEXT PRIMARY KEY,
    source_text TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    source_language_id TEXT NOT NULL,
    target_language_id TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    translation_provider_id TEXT,
    usage_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (translation_provider_id) REFERENCES translation_providers(id) ON DELETE SET NULL,
    UNIQUE(source_hash, target_language_id),
    CHECK (usage_count >= 0)
);

-- Translation Version TM Usage: TM usage tracking
CREATE TABLE IF NOT EXISTS translation_version_tm_usage (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    tm_id TEXT NOT NULL,
    match_confidence REAL NOT NULL,
    applied_at INTEGER NOT NULL,
    FOREIGN KEY (version_id) REFERENCES translation_versions(id) ON DELETE CASCADE,
    FOREIGN KEY (tm_id) REFERENCES translation_memory(id) ON DELETE CASCADE,
    CHECK (match_confidence >= 0 AND match_confidence <= 1)
);

-- ============================================================================
-- GLOSSARY MANAGEMENT
-- ============================================================================

-- Glossaries: Term glossaries for consistent translations
-- is_global = 1: Universal glossary (all games, all projects)
-- is_global = 0: Game-specific glossary (all projects of one game)
CREATE TABLE IF NOT EXISTS glossaries (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    is_global INTEGER NOT NULL DEFAULT 0,
    game_installation_id TEXT,
    target_language_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE CASCADE,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    CHECK (is_global IN (0, 1)),
    CHECK ((is_global = 1 AND game_installation_id IS NULL) OR (is_global = 0 AND game_installation_id IS NOT NULL)),
    CHECK (created_at <= updated_at)
);

-- Glossary Entries: Individual terms in a glossary
CREATE TABLE IF NOT EXISTS glossary_entries (
    id TEXT PRIMARY KEY,
    glossary_id TEXT NOT NULL,
    target_language_code TEXT NOT NULL,
    source_term TEXT NOT NULL,
    target_term TEXT NOT NULL,
    definition TEXT,
    notes TEXT,
    is_forbidden INTEGER NOT NULL DEFAULT 0,
    case_sensitive INTEGER NOT NULL DEFAULT 0,
    usage_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (glossary_id) REFERENCES glossaries(id) ON DELETE CASCADE,
    CHECK (is_forbidden IN (0, 1)),
    CHECK (case_sensitive IN (0, 1)),
    CHECK (usage_count >= 0),
    CHECK (created_at <= updated_at),
    UNIQUE(glossary_id, target_language_code, source_term, case_sensitive)
);

-- ============================================================================
-- SEARCH MANAGEMENT
-- ============================================================================

-- Search History: Recent search queries
CREATE TABLE IF NOT EXISTS search_history (
    id TEXT PRIMARY KEY,
    query TEXT NOT NULL,
    scope TEXT NOT NULL,
    filters_json TEXT,
    result_count INTEGER NOT NULL,
    searched_at INTEGER NOT NULL,
    CHECK (scope IN ('source', 'target', 'both', 'key', 'all'))
);

-- Saved Searches: User-saved search queries
CREATE TABLE IF NOT EXISTS saved_searches (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    query TEXT NOT NULL,
    scope TEXT NOT NULL,
    filters_json TEXT,
    usage_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL,
    CHECK (scope IN ('source', 'target', 'both', 'key', 'all')),
    CHECK (usage_count >= 0)
);

-- ============================================================================
-- WORKSHOP MODS
-- ============================================================================

-- Workshop Mods: Steam Workshop mod metadata
CREATE TABLE IF NOT EXISTS workshop_mods (
    id TEXT PRIMARY KEY,
    workshop_id TEXT NOT NULL UNIQUE,
    app_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    workshop_url TEXT NOT NULL,
    file_size INTEGER,
    time_created INTEGER,
    time_updated INTEGER,
    subscriptions INTEGER DEFAULT 0,
    tags TEXT,
    is_hidden INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_checked_at INTEGER,
    CHECK (file_size IS NULL OR file_size >= 0),
    CHECK (subscriptions >= 0),
    CHECK (created_at <= updated_at),
    CHECK (is_hidden IN (0, 1))
);

-- ============================================================================
-- LLM PROVIDER MODELS
-- ============================================================================

-- LLM Provider Models: Available models per provider
CREATE TABLE IF NOT EXISTS llm_provider_models (
    id TEXT PRIMARY KEY,
    provider_code TEXT NOT NULL,
    model_id TEXT NOT NULL,
    display_name TEXT,
    is_enabled INTEGER NOT NULL DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    last_fetched_at INTEGER NOT NULL,
    UNIQUE(provider_code, model_id)
);

-- ============================================================================
-- EVENT STORE
-- ============================================================================

-- Event Store: Event sourcing and audit trail
CREATE TABLE IF NOT EXISTS event_store (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    triggered_by TEXT,
    aggregate_id TEXT,
    aggregate_type TEXT,
    correlation_id TEXT,
    causation_id TEXT,
    metadata TEXT
);

-- ============================================================================
-- MOD SCAN CACHE
-- ============================================================================

-- Mod Scan Cache: Cache RPFM scan results
CREATE TABLE IF NOT EXISTS mod_scan_cache (
    id TEXT PRIMARY KEY,
    pack_file_path TEXT NOT NULL UNIQUE,
    file_last_modified INTEGER NOT NULL,
    has_loc_files INTEGER NOT NULL DEFAULT 0,
    scanned_at INTEGER NOT NULL,
    CHECK (has_loc_files IN (0, 1))
);

-- Mod Update Analysis Cache: Cache analysis results per project
-- Only re-analyze when the pack file has been modified
CREATE TABLE IF NOT EXISTS mod_update_analysis_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    pack_file_path TEXT NOT NULL,
    file_last_modified INTEGER NOT NULL,
    new_units_count INTEGER NOT NULL DEFAULT 0,
    removed_units_count INTEGER NOT NULL DEFAULT 0,
    modified_units_count INTEGER NOT NULL DEFAULT 0,
    total_pack_units INTEGER NOT NULL DEFAULT 0,
    total_project_units INTEGER NOT NULL DEFAULT 0,
    analyzed_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    UNIQUE(project_id, pack_file_path)
);

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Settings: User configuration
CREATE TABLE IF NOT EXISTS settings (
    id TEXT PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'string',
    updated_at INTEGER NOT NULL,
    CHECK (value_type IN ('string', 'integer', 'boolean', 'json'))
);

-- ============================================================================
-- DENORMALIZED TABLE FOR PERFORMANCE (DataGrid)
-- ============================================================================

-- Denormalized cache for fast DataGrid display
CREATE TABLE IF NOT EXISTS translation_view_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    version_id TEXT,
    key TEXT NOT NULL,
    source_text TEXT NOT NULL,
    translated_text TEXT,
    status TEXT NOT NULL,
    confidence_score REAL,
    is_manually_edited INTEGER NOT NULL DEFAULT 0,
    is_obsolete INTEGER NOT NULL DEFAULT 0,
    tm_match_confidence REAL,
    tm_match_text TEXT,
    batch_number INTEGER,
    provider_name TEXT,
    unit_created_at INTEGER NOT NULL,
    unit_updated_at INTEGER NOT NULL,
    version_updated_at INTEGER,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Projects
CREATE INDEX IF NOT EXISTS idx_projects_game ON projects(game_installation_id);
CREATE INDEX IF NOT EXISTS idx_projects_updated ON projects(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_projects_steam_id ON projects(mod_steam_id);

-- Project Languages
CREATE INDEX IF NOT EXISTS idx_project_languages_project ON project_languages(project_id, status);
CREATE INDEX IF NOT EXISTS idx_project_languages_language ON project_languages(language_id);

-- Mod Versions
CREATE INDEX IF NOT EXISTS idx_mod_versions_project ON mod_versions(project_id, is_current);
CREATE INDEX IF NOT EXISTS idx_mod_version_changes_version ON mod_version_changes(version_id, change_type);

-- Translation Units
CREATE INDEX IF NOT EXISTS idx_translation_units_project ON translation_units(project_id);
CREATE INDEX IF NOT EXISTS idx_translation_units_key ON translation_units(key);
CREATE INDEX IF NOT EXISTS idx_translation_units_obsolete ON translation_units(project_id, is_obsolete);
CREATE INDEX IF NOT EXISTS idx_translation_units_source_loc_file ON translation_units(project_id, source_loc_file);

-- Translation Versions
CREATE INDEX IF NOT EXISTS idx_translation_versions_unit ON translation_versions(unit_id);
CREATE INDEX IF NOT EXISTS idx_translation_versions_proj_lang ON translation_versions(project_language_id, status);
CREATE INDEX IF NOT EXISTS idx_translation_versions_status ON translation_versions(status);
-- Composite index for common JOIN pattern (unit + project_language)
CREATE INDEX IF NOT EXISTS idx_translation_versions_unit_proj_lang ON translation_versions(unit_id, project_language_id);
-- Index for filtering untranslated versions by project_language_id
-- Used by getUntranslatedIds, filterUntranslatedIds, getTranslatedUnitIds
CREATE INDEX IF NOT EXISTS idx_translation_versions_proj_lang_text ON translation_versions(project_language_id, translated_text)
    WHERE translated_text IS NULL OR translated_text = '';
-- Index for status inconsistency queries (reanalyzeAllStatuses, countInconsistentStatuses)
CREATE INDEX IF NOT EXISTS idx_translation_versions_status_text ON translation_versions(status, is_manually_edited)
    WHERE status IN ('pending', 'translating');

-- Translation Version History
CREATE INDEX IF NOT EXISTS idx_translation_version_history_version ON translation_version_history(version_id);
-- Index for history lookup with chronological ordering
CREATE INDEX IF NOT EXISTS idx_translation_version_history_version_time ON translation_version_history(version_id, created_at DESC);

-- Translation Batches
CREATE INDEX IF NOT EXISTS idx_batches_proj_lang ON translation_batches(project_language_id, status);
CREATE INDEX IF NOT EXISTS idx_batches_provider ON translation_batches(provider_id, status);

-- Translation Batch Units
CREATE INDEX IF NOT EXISTS idx_batch_units_batch ON translation_batch_units(batch_id, status);
CREATE INDEX IF NOT EXISTS idx_batch_units_unit ON translation_batch_units(unit_id);

-- Translation Memory
CREATE INDEX IF NOT EXISTS idx_tm_hash_lang ON translation_memory(source_hash, target_language_id);
CREATE INDEX IF NOT EXISTS idx_tm_source_lang ON translation_memory(source_language_id, target_language_id);
CREATE INDEX IF NOT EXISTS idx_tm_last_used ON translation_memory(last_used_at DESC);
-- Index for target language filtering (getWithFilters, searchFts5)
CREATE INDEX IF NOT EXISTS idx_tm_target_lang ON translation_memory(target_language_id);
-- Index for source language filtering (deleteByLanguageId OR condition)
CREATE INDEX IF NOT EXISTS idx_tm_source_lang_only ON translation_memory(source_language_id);
-- Index for usage-based sorting with language filter
CREATE INDEX IF NOT EXISTS idx_tm_target_lang_usage ON translation_memory(target_language_id, usage_count DESC);

-- Translation Version TM Usage
CREATE INDEX IF NOT EXISTS idx_tm_usage_version ON translation_version_tm_usage(version_id);
CREATE INDEX IF NOT EXISTS idx_tm_usage_tm ON translation_version_tm_usage(tm_id);

-- Game Installations
CREATE INDEX IF NOT EXISTS idx_game_installations_code ON game_installations(game_code);
CREATE INDEX IF NOT EXISTS idx_game_installations_valid ON game_installations(is_valid);

-- Settings
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

-- Languages
CREATE INDEX IF NOT EXISTS idx_languages_code ON languages(code);

-- Translation Providers
CREATE INDEX IF NOT EXISTS idx_translation_providers_code ON translation_providers(code);

-- Glossaries
CREATE INDEX IF NOT EXISTS idx_glossaries_game ON glossaries(game_installation_id, is_global);
CREATE INDEX IF NOT EXISTS idx_glossaries_target_language ON glossaries(target_language_id);
CREATE INDEX IF NOT EXISTS idx_glossaries_name ON glossaries(name);

-- Glossary Entries
CREATE INDEX IF NOT EXISTS idx_glossary_entries_glossary ON glossary_entries(glossary_id);
CREATE INDEX IF NOT EXISTS idx_glossary_entries_source ON glossary_entries(source_term);
CREATE INDEX IF NOT EXISTS idx_glossary_entries_usage ON glossary_entries(usage_count DESC);
CREATE INDEX IF NOT EXISTS idx_glossary_entries_language ON glossary_entries(target_language_code);

-- Search History
CREATE INDEX IF NOT EXISTS idx_search_history_searched ON search_history(searched_at DESC);
CREATE INDEX IF NOT EXISTS idx_saved_searches_name ON saved_searches(name);
CREATE INDEX IF NOT EXISTS idx_saved_searches_last_used ON saved_searches(last_used_at DESC);

-- Workshop Mods
CREATE UNIQUE INDEX IF NOT EXISTS idx_workshop_mods_workshop_id ON workshop_mods(workshop_id);
CREATE INDEX IF NOT EXISTS idx_workshop_mods_app_id ON workshop_mods(app_id);
CREATE INDEX IF NOT EXISTS idx_workshop_mods_app_updated ON workshop_mods(app_id, time_updated DESC);
CREATE INDEX IF NOT EXISTS idx_workshop_mods_title ON workshop_mods(title COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS idx_workshop_mods_updated ON workshop_mods(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_workshop_mods_last_checked ON workshop_mods(last_checked_at);

-- LLM Provider Models
CREATE INDEX IF NOT EXISTS idx_llm_models_provider ON llm_provider_models(provider_code);
CREATE INDEX IF NOT EXISTS idx_llm_models_enabled ON llm_provider_models(provider_code, is_enabled) WHERE is_archived = 0;
CREATE INDEX IF NOT EXISTS idx_llm_models_default ON llm_provider_models(provider_code, is_default) WHERE is_archived = 0;

-- Event Store
CREATE INDEX IF NOT EXISTS idx_event_store_type ON event_store(event_type);
CREATE INDEX IF NOT EXISTS idx_event_store_aggregate ON event_store(aggregate_id, aggregate_type);
CREATE INDEX IF NOT EXISTS idx_event_store_occurred_at ON event_store(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_store_correlation ON event_store(correlation_id) WHERE correlation_id IS NOT NULL;

-- Mod Scan Cache
CREATE INDEX IF NOT EXISTS idx_mod_scan_cache_pack_path ON mod_scan_cache(pack_file_path);
CREATE INDEX IF NOT EXISTS idx_mod_scan_cache_scanned_at ON mod_scan_cache(scanned_at);

-- Mod Update Analysis Cache
CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_project ON mod_update_analysis_cache(project_id);
CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_pack_path ON mod_update_analysis_cache(pack_file_path);

-- Translation View Cache
CREATE INDEX IF NOT EXISTS idx_translation_cache_proj_lang ON translation_view_cache(project_id, project_language_id);
CREATE INDEX IF NOT EXISTS idx_translation_cache_status ON translation_view_cache(project_language_id, status);
CREATE INDEX IF NOT EXISTS idx_translation_cache_updated ON translation_view_cache(project_language_id, version_updated_at DESC);

-- ============================================================================
-- FULL-TEXT SEARCH (FTS5)
-- ============================================================================

-- FTS5 for translation_units search
CREATE VIRTUAL TABLE IF NOT EXISTS translation_units_fts USING fts5(
    key,
    source_text,
    context,
    notes,
    content='translation_units',
    content_rowid='rowid'
);

-- FTS5 for translation_versions search (CONTENTLESS MODE)
-- Uses contentless FTS5 to avoid rowid mapping issues with TEXT PRIMARY KEY (UUID)
-- The version_id column is stored (UNINDEXED) to enable JOINs back to translation_versions
CREATE VIRTUAL TABLE IF NOT EXISTS translation_versions_fts USING fts5(
    translated_text,
    validation_issues,
    version_id UNINDEXED,
    content=''
);

-- FTS5 for translation_memory search
CREATE VIRTUAL TABLE IF NOT EXISTS translation_memory_fts USING fts5(
    source_text,
    translated_text,
    content='translation_memory',
    content_rowid='rowid'
);

-- FTS5 for workshop_mods search
CREATE VIRTUAL TABLE IF NOT EXISTS workshop_mods_fts USING fts5(
    title,
    tags,
    content='workshop_mods',
    content_rowid='rowid'
);

-- ============================================================================
-- VIEWS FOR STATISTICS
-- ============================================================================

-- View for project language statistics
CREATE VIEW IF NOT EXISTS v_project_language_stats AS
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

-- View for translations needing review
CREATE VIEW IF NOT EXISTS v_translations_needing_review AS
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
-- TRIGGERS
-- ============================================================================

-- Translation Units FTS5 sync triggers
CREATE TRIGGER IF NOT EXISTS trg_translation_units_fts_insert AFTER INSERT ON translation_units BEGIN
    INSERT INTO translation_units_fts(rowid, key, source_text, context, notes)
    VALUES (new.rowid, new.key, new.source_text, new.context, new.notes);
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_units_fts_update AFTER UPDATE ON translation_units BEGIN
    UPDATE translation_units_fts
    SET key = new.key,
        source_text = new.source_text,
        context = new.context,
        notes = new.notes
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_units_fts_delete AFTER DELETE ON translation_units BEGIN
    DELETE FROM translation_units_fts WHERE rowid = old.rowid;
END;

-- Translation Versions FTS5 sync triggers (CONTENTLESS MODE)
-- Uses version_id for identification instead of rowid mapping
-- Note: Contentless FTS5 requires DELETE+INSERT for updates (no UPDATE support)
CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_insert
AFTER INSERT ON translation_versions
WHEN new.translated_text IS NOT NULL
BEGIN
    INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
    VALUES (new.translated_text, new.validation_issues, new.id);
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_update
AFTER UPDATE OF translated_text, validation_issues ON translation_versions
BEGIN
    -- Contentless FTS5: must DELETE then INSERT (cannot UPDATE)
    DELETE FROM translation_versions_fts WHERE version_id = old.id;
    INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
    SELECT new.translated_text, new.validation_issues, new.id
    WHERE new.translated_text IS NOT NULL;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_delete
AFTER DELETE ON translation_versions
BEGIN
    DELETE FROM translation_versions_fts WHERE version_id = old.id;
END;

-- Translation Memory FTS5 sync triggers
CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_insert AFTER INSERT ON translation_memory BEGIN
    INSERT INTO translation_memory_fts(rowid, source_text, translated_text)
    VALUES (new.rowid, new.source_text, new.translated_text);
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_update AFTER UPDATE ON translation_memory BEGIN
    UPDATE translation_memory_fts
    SET source_text = new.source_text,
        translated_text = new.translated_text
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_memory_fts_delete AFTER DELETE ON translation_memory BEGIN
    DELETE FROM translation_memory_fts WHERE rowid = old.rowid;
END;

-- Workshop Mods FTS5 sync triggers
CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_insert AFTER INSERT ON workshop_mods BEGIN
    INSERT INTO workshop_mods_fts(rowid, title, tags)
    VALUES (new.rowid, new.title, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_update AFTER UPDATE ON workshop_mods BEGIN
    UPDATE workshop_mods_fts
    SET title = new.title,
        tags = new.tags
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_fts_delete AFTER DELETE ON workshop_mods BEGIN
    DELETE FROM workshop_mods_fts WHERE rowid = old.rowid;
END;

-- Cache sync triggers
CREATE TRIGGER IF NOT EXISTS trg_update_cache_on_unit_change
AFTER UPDATE ON translation_units
BEGIN
    UPDATE translation_view_cache
    SET key = new.key,
        source_text = new.source_text,
        is_obsolete = new.is_obsolete,
        unit_updated_at = new.updated_at
    WHERE unit_id = new.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_update_cache_on_version_change
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_view_cache
    SET translated_text = new.translated_text,
        status = new.status,
        confidence_score = NULL,
        is_manually_edited = new.is_manually_edited,
        version_id = new.id,
        version_updated_at = new.updated_at
    WHERE unit_id = new.unit_id
      AND project_language_id = new.project_language_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_insert_cache_on_version_insert
AFTER INSERT ON translation_versions
BEGIN
    INSERT OR REPLACE INTO translation_view_cache (
        id, project_id, project_language_id, language_code, unit_id, version_id,
        key, source_text, translated_text, status, confidence_score,
        is_manually_edited, is_obsolete, unit_created_at, unit_updated_at, version_updated_at
    )
    SELECT
        new.id || '_' || tu.id AS id,
        tu.project_id,
        new.project_language_id,
        l.code,
        tu.id,
        new.id,
        tu.key,
        tu.source_text,
        new.translated_text,
        new.status,
        NULL,
        new.is_manually_edited,
        tu.is_obsolete,
        tu.created_at,
        tu.updated_at,
        new.updated_at
    FROM translation_units tu
    INNER JOIN project_languages pl ON pl.id = new.project_language_id
    INNER JOIN languages l ON l.id = pl.language_id
    WHERE tu.id = new.unit_id;
END;

CREATE TRIGGER IF NOT EXISTS trg_delete_cache_on_version_delete
AFTER DELETE ON translation_versions
BEGIN
    DELETE FROM translation_view_cache WHERE version_id = old.id;
END;

-- Auto-update progress_percent
CREATE TRIGGER IF NOT EXISTS trg_update_project_language_progress
AFTER UPDATE ON translation_versions
WHEN NEW.status != OLD.status
BEGIN
    UPDATE project_languages
    SET progress_percent = (
        SELECT
            CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
            NULLIF(COUNT(*), 0)
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = NEW.project_language_id
            AND tu.is_obsolete = 0
    ),
    updated_at = strftime('%s', 'now')
    WHERE id = NEW.project_language_id;
END;

-- Auto-update timestamps
-- IMPORTANT: All self-referential triggers MUST have WHEN clause to prevent infinite recursion
CREATE TRIGGER IF NOT EXISTS trg_projects_updated_at
AFTER UPDATE ON projects
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE projects SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_units_updated_at
AFTER UPDATE ON translation_units
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_updated_at
AFTER UPDATE ON translation_versions
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_glossaries_updated_at
AFTER UPDATE ON glossaries
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE glossaries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_glossary_entries_updated_at
AFTER UPDATE ON glossary_entries
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE glossary_entries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_workshop_mods_updated_at
AFTER UPDATE ON workshop_mods
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE workshop_mods SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

-- LLM Models triggers
CREATE TRIGGER IF NOT EXISTS trg_llm_models_single_default
BEFORE UPDATE OF is_default ON llm_provider_models
WHEN NEW.is_default = 1
BEGIN
    UPDATE llm_provider_models
    SET is_default = 0
    WHERE provider_code = NEW.provider_code
      AND id != NEW.id
      AND is_default = 1;
END;

CREATE TRIGGER IF NOT EXISTS trg_llm_models_updated_at
AFTER UPDATE ON llm_provider_models
WHEN NEW.updated_at = OLD.updated_at
BEGIN
    UPDATE llm_provider_models
    SET updated_at = strftime('%s', 'now')
    WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_llm_models_prevent_enable_archived
BEFORE UPDATE OF is_enabled ON llm_provider_models
WHEN NEW.is_enabled = 1 AND NEW.is_archived = 1
BEGIN
    SELECT RAISE(ABORT, 'Cannot enable archived model');
END;

CREATE TRIGGER IF NOT EXISTS trg_llm_models_prevent_default_archived
BEFORE UPDATE OF is_default ON llm_provider_models
WHEN NEW.is_default = 1 AND NEW.is_archived = 1
BEGIN
    SELECT RAISE(ABORT, 'Cannot set archived model as default');
END;

-- ============================================================================
-- INITIAL REFERENCE DATA
-- ============================================================================

-- Supported languages
INSERT OR IGNORE INTO languages (id, code, name, native_name, is_active) VALUES
('lang_de', 'de', 'German', 'Deutsch', 1),
('lang_en', 'en', 'English', 'English', 1),
('lang_zh', 'zh', 'Chinese', '中文', 1),
('lang_es', 'es', 'Spanish', 'Español', 1),
('lang_fr', 'fr', 'French', 'Français', 1),
('lang_ru', 'ru', 'Russian', 'Русский', 1);

-- Translation providers
INSERT OR IGNORE INTO translation_providers (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at) VALUES
('provider_anthropic', 'anthropic', 'Anthropic Claude', 'https://api.anthropic.com/v1', 'claude-sonnet-4-5-20250929', 200000, 25, 50, 40000, 1, strftime('%s', 'now')),
('provider_deepl', 'deepl', 'DeepL', 'https://api-free.deepl.com/v2', 'deepl-free', NULL, 50, 100, NULL, 1, strftime('%s', 'now')),
('provider_openai', 'openai', 'OpenAI GPT', 'https://api.openai.com/v1', 'gpt-5.1-2025-11-13', 128000, 40, 60, 90000, 1, strftime('%s', 'now')),
('provider_deepseek', 'deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat', 64000, 30, 60, 100000, 1, strftime('%s', 'now')),
('provider_gemini', 'gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-3-flash-preview', 1048576, 30, 60, 250000, 1, strftime('%s', 'now'));

-- Default settings
INSERT OR IGNORE INTO settings (id, key, value, value_type, updated_at) VALUES
('setting_active_provider', 'active_translation_provider_id', 'provider_openai', 'string', strftime('%s', 'now')),
('setting_default_game', 'default_game_installation_id', '', 'string', strftime('%s', 'now')),
('setting_game_prompts', 'default_game_context_prompts', '{}', 'json', strftime('%s', 'now')),
('setting_default_batch_size', 'default_batch_size', '25', 'integer', strftime('%s', 'now')),
('setting_default_parallel_batches', 'default_parallel_batches', '5', 'integer', strftime('%s', 'now'));

-- ============================================================================
-- LLM MODELS SEED DATA
-- ============================================================================

-- Anthropic models
INSERT OR IGNORE INTO llm_provider_models (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
VALUES
('model_claude_sonnet_4_5', 'anthropic', 'claude-sonnet-4-5-20250929', 'Claude Sonnet 4.5', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
('model_claude_4_5_haiku', 'anthropic', 'claude-haiku-4-5-20251001', 'Claude 4.5 Haiku', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'));

-- OpenAI models
INSERT OR IGNORE INTO llm_provider_models (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
VALUES
('model_gpt_5_1', 'openai', 'gpt-5.1-2025-11-13', 'GPT-5.1', 1, 1, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'));

-- DeepL models (plans)
INSERT OR IGNORE INTO llm_provider_models (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
VALUES
('model_deepl_free', 'deepl', 'deepl-free', 'DeepL Free', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
('model_deepl_pro', 'deepl', 'deepl-pro', 'DeepL Pro', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'));

-- DeepSeek models
INSERT OR IGNORE INTO llm_provider_models (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
VALUES
('model_deepseek_chat', 'deepseek', 'deepseek-chat', 'DeepSeek V3.2', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'));

-- Google Gemini models
INSERT OR IGNORE INTO llm_provider_models (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
VALUES
('model_gemini_3_pro', 'gemini', 'gemini-3-pro-preview', 'Gemini 3 Pro', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
('model_gemini_3_flash', 'gemini', 'gemini-3-flash-preview', 'Gemini 3 Flash', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'));
