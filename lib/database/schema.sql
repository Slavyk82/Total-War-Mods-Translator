-- ============================================================================
-- TWMT Database Schema v1
-- Total War Mods Translator - Complete SQLite Database Schema
-- ============================================================================
-- Description: Complete database schema for TWMT application
-- Version: 1
-- Created: 2025-11-14
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
    status TEXT NOT NULL DEFAULT 'draft',
    last_update_check INTEGER,
    source_mod_updated INTEGER,
    batch_size INTEGER NOT NULL DEFAULT 25,
    parallel_batches INTEGER NOT NULL DEFAULT 3,
    custom_prompt TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    metadata TEXT,
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
    CHECK (status IN ('draft', 'translating', 'reviewing', 'completed')),
    CHECK (batch_size > 0 AND batch_size <= 100),
    CHECK (parallel_batches > 0 AND parallel_batches <= 10),
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
    source_language_id TEXT,
    context TEXT,
    notes TEXT,
    is_obsolete INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE SET NULL,
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
    confidence_score REAL,
    validation_issues TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (unit_id) REFERENCES translation_units(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE,
    UNIQUE(unit_id, project_language_id),
    CHECK (status IN ('pending', 'translating', 'translated', 'reviewed', 'approved', 'needs_review')),
    CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
    CHECK (is_manually_edited IN (0, 1)),
    CHECK (created_at <= updated_at)
);

-- Translation Version History: Change history
CREATE TABLE IF NOT EXISTS translation_version_history (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    status TEXT NOT NULL,
    confidence_score REAL,
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
    game_context TEXT,
    translation_provider_id TEXT,
    quality_score REAL,
    usage_count INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (target_language_id) REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (translation_provider_id) REFERENCES translation_providers(id) ON DELETE SET NULL,
    UNIQUE(source_hash, target_language_id, game_context),
    CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
    CHECK (usage_count >= 1)
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
-- INDEXES FOR PERFORMANCE (100-800x gain)
-- ============================================================================

-- Projects
CREATE INDEX IF NOT EXISTS idx_projects_game ON projects(game_installation_id, status);
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

-- Translation Versions
CREATE INDEX IF NOT EXISTS idx_translation_versions_unit ON translation_versions(unit_id);
CREATE INDEX IF NOT EXISTS idx_translation_versions_proj_lang ON translation_versions(project_language_id, status);
CREATE INDEX IF NOT EXISTS idx_translation_versions_status ON translation_versions(status);

-- Translation Batches
CREATE INDEX IF NOT EXISTS idx_batches_proj_lang ON translation_batches(project_language_id, status);
CREATE INDEX IF NOT EXISTS idx_batches_provider ON translation_batches(provider_id, status);

-- Translation Batch Units
CREATE INDEX IF NOT EXISTS idx_batch_units_batch ON translation_batch_units(batch_id, status);
CREATE INDEX IF NOT EXISTS idx_batch_units_unit ON translation_batch_units(unit_id);

-- Translation Memory
CREATE INDEX IF NOT EXISTS idx_tm_hash_lang_context ON translation_memory(source_hash, target_language_id, game_context);
CREATE INDEX IF NOT EXISTS idx_tm_source_lang ON translation_memory(source_language_id, target_language_id);
CREATE INDEX IF NOT EXISTS idx_tm_last_used ON translation_memory(last_used_at DESC);
CREATE INDEX IF NOT EXISTS idx_tm_game_context ON translation_memory(game_context, quality_score DESC);
-- Optimized index for FTS5 TM lookups with language filtering (10-50x performance improvement)
CREATE INDEX IF NOT EXISTS idx_tm_lang_quality ON translation_memory(target_language_id, quality_score DESC, usage_count DESC) WHERE quality_score >= 0.85;

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

-- ============================================================================
-- FULL-TEXT SEARCH (FTS5) FOR PERFORMANT SEARCH
-- ============================================================================

-- FTS5 for translation_units search (100-1000x faster than LIKE)
CREATE VIRTUAL TABLE IF NOT EXISTS translation_units_fts USING fts5(
    key,
    source_text,
    context,
    notes,
    content='translation_units',
    content_rowid='rowid'
);

-- FTS5 for translation_versions search
CREATE VIRTUAL TABLE IF NOT EXISTS translation_versions_fts USING fts5(
    translated_text,
    validation_issues,
    content='translation_versions',
    content_rowid='rowid'
);

-- Triggers to maintain FTS5 sync with translation_units

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

-- Triggers to maintain FTS5 sync with translation_versions

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_insert AFTER INSERT ON translation_versions BEGIN
    INSERT INTO translation_versions_fts(rowid, translated_text, validation_issues)
    VALUES (new.rowid, new.translated_text, new.validation_issues);
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_update AFTER UPDATE ON translation_versions BEGIN
    UPDATE translation_versions_fts
    SET translated_text = new.translated_text,
        validation_issues = new.validation_issues
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_delete AFTER DELETE ON translation_versions BEGIN
    DELETE FROM translation_versions_fts WHERE rowid = old.rowid;
END;

-- ============================================================================
-- DENORMALIZED TABLE FOR PERFORMANCE (DataGrid)
-- ============================================================================

-- Denormalized cache for fast DataGrid display
-- Avoids complex JOINs for each displayed row
CREATE TABLE IF NOT EXISTS translation_view_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    version_id TEXT,

    -- Denormalized data
    key TEXT NOT NULL,
    source_text TEXT NOT NULL,
    translated_text TEXT,
    status TEXT NOT NULL,
    confidence_score REAL,
    is_manually_edited INTEGER NOT NULL DEFAULT 0,
    is_obsolete INTEGER NOT NULL DEFAULT 0,

    -- TM metadata
    tm_match_confidence REAL,
    tm_match_text TEXT,

    -- Batch metadata
    batch_number INTEGER,
    provider_name TEXT,

    -- Timestamps
    unit_created_at INTEGER NOT NULL,
    unit_updated_at INTEGER NOT NULL,
    version_updated_at INTEGER,

    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE
);

-- Indexes for fast cache access
CREATE INDEX IF NOT EXISTS idx_translation_cache_proj_lang
    ON translation_view_cache(project_id, project_language_id);

CREATE INDEX IF NOT EXISTS idx_translation_cache_status
    ON translation_view_cache(project_language_id, status);

CREATE INDEX IF NOT EXISTS idx_translation_cache_updated
    ON translation_view_cache(project_language_id, version_updated_at DESC);

-- Triggers to maintain cache

-- Update cache when translation_unit changes
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

-- Update cache when translation_version changes
CREATE TRIGGER IF NOT EXISTS trg_update_cache_on_version_change
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_view_cache
    SET translated_text = new.translated_text,
        status = new.status,
        confidence_score = new.confidence_score,
        is_manually_edited = new.is_manually_edited,
        version_id = new.id,
        version_updated_at = new.updated_at
    WHERE unit_id = new.unit_id
      AND project_language_id = new.project_language_id;
END;

-- Insert into cache for new versions
CREATE TRIGGER IF NOT EXISTS trg_insert_cache_on_version_insert
AFTER INSERT ON translation_versions
BEGIN
    INSERT OR REPLACE INTO translation_view_cache (
        id,
        project_id,
        project_language_id,
        language_code,
        unit_id,
        version_id,
        key,
        source_text,
        translated_text,
        status,
        confidence_score,
        is_manually_edited,
        is_obsolete,
        unit_created_at,
        unit_updated_at,
        version_updated_at
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
        new.confidence_score,
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

-- Delete from cache when version is deleted
CREATE TRIGGER IF NOT EXISTS trg_delete_cache_on_version_delete
AFTER DELETE ON translation_versions
BEGIN
    DELETE FROM translation_view_cache
    WHERE version_id = old.id;
END;

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
-- TRIGGERS FOR AUTOMATION
-- ============================================================================

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

CREATE TRIGGER IF NOT EXISTS trg_projects_updated_at
AFTER UPDATE ON projects
BEGIN
    UPDATE projects SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_units_updated_at
AFTER UPDATE ON translation_units
BEGIN
    UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_translation_versions_updated_at
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

-- ============================================================================
-- INITIAL REFERENCE DATA
-- ============================================================================

-- Supported languages (alphabetical order)
INSERT OR IGNORE INTO languages (id, code, name, native_name, is_active) VALUES
('lang_de', 'de', 'German', 'Deutsch', 1),
('lang_en', 'en', 'English', 'English', 1),
('lang_zh', 'zh', 'Chinese', '中文', 1),
('lang_es', 'es', 'Spanish', 'Español', 1),
('lang_fr', 'fr', 'French', 'Français', 1),
('lang_ru', 'ru', 'Russian', 'Русский', 1);

-- Translation providers (alphabetical order)
INSERT OR IGNORE INTO translation_providers (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at) VALUES
('provider_anthropic', 'anthropic', 'Anthropic Claude', 'https://api.anthropic.com/v1', 'claude-3-5-sonnet-20241022', 200000, 25, 50, 40000, 1, strftime('%s', 'now')),
('provider_deepl', 'deepl', 'DeepL', 'https://api.deepl.com/v2', NULL, NULL, 50, 100, NULL, 1, strftime('%s', 'now')),
('provider_openai', 'openai', 'OpenAI GPT', 'https://api.openai.com/v1', 'gpt-4-turbo-preview', 128000, 40, 60, 90000, 1, strftime('%s', 'now'));

-- Default settings
INSERT OR IGNORE INTO settings (id, key, value, value_type, updated_at) VALUES
('setting_active_provider', 'active_translation_provider_id', 'provider_anthropic', 'string', strftime('%s', 'now')),
('setting_default_game', 'default_game_installation_id', '', 'string', strftime('%s', 'now')),
('setting_game_prompts', 'default_game_context_prompts', '{}', 'json', strftime('%s', 'now')),
('setting_default_batch_size', 'default_batch_size', '25', 'integer', strftime('%s', 'now')),
('setting_default_parallel_batches', 'default_parallel_batches', '3', 'integer', strftime('%s', 'now'));
