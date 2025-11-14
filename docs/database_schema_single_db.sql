-- TWMT Single Database Architecture
-- Database: twmt.db (stored in AppData\Roaming\TWMT\twmt.db)
-- SQLite with WAL mode enabled

-- ============================================================================
-- OPERATIONAL TABLES
-- High write frequency, project-specific data
-- ============================================================================

CREATE TABLE operational_projects (
    id TEXT PRIMARY KEY,  -- UUID
    name TEXT NOT NULL,
    source_language TEXT NOT NULL,
    target_language TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('active', 'completed', 'archived')),
    created_at INTEGER NOT NULL,
    modified_at INTEGER NOT NULL,
    metadata TEXT  -- JSON for extensibility
) WITHOUT ROWID;

CREATE INDEX idx_operational_projects_modified
    ON operational_projects(modified_at DESC);
CREATE INDEX idx_operational_projects_status
    ON operational_projects(status) WHERE status = 'active';

-- ============================================================================

CREATE TABLE operational_translation_units (
    id TEXT PRIMARY KEY,  -- UUID
    project_id TEXT NOT NULL,
    source_text TEXT NOT NULL,
    source_hash TEXT NOT NULL,  -- SHA-256 for TM matching
    context TEXT,  -- Surrounding text for disambiguation
    metadata TEXT,  -- JSON (e.g., file location, line number)
    created_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES operational_projects(id) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE INDEX idx_operational_tu_project
    ON operational_translation_units(project_id);
CREATE INDEX idx_operational_tu_source_hash
    ON operational_translation_units(source_hash);

-- ============================================================================

CREATE TABLE operational_translations (
    id TEXT PRIMARY KEY,  -- UUID
    translation_unit_id TEXT NOT NULL,
    target_text TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('draft', 'confirmed', 'approved', 'rejected')),
    translator_id TEXT,  -- Future: user who created translation
    created_at INTEGER NOT NULL,
    modified_at INTEGER NOT NULL,
    FOREIGN KEY (translation_unit_id) REFERENCES operational_translation_units(id) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE INDEX idx_operational_translations_tu
    ON operational_translations(translation_unit_id);
CREATE INDEX idx_operational_translations_status
    ON operational_translations(status);

-- ============================================================================
-- TRANSLATION MEMORY TABLES
-- Read-heavy, append-only (mostly), large corpus
-- ============================================================================

CREATE TABLE tm_entries (
    id TEXT PRIMARY KEY,  -- UUID
    source_text TEXT NOT NULL,
    target_text TEXT NOT NULL,
    source_language TEXT NOT NULL,
    target_language TEXT NOT NULL,
    source_hash TEXT NOT NULL,  -- SHA-256 for exact matching
    domain TEXT,  -- e.g., 'medical', 'legal', 'technical'
    quality_score REAL DEFAULT 1.0,  -- 0.0 to 1.0 (1.0 = human-confirmed)
    usage_count INTEGER DEFAULT 0,  -- Tracks reuse frequency
    created_at INTEGER NOT NULL,
    last_used_at INTEGER,
    origin TEXT,  -- 'user_translation', 'imported_tmx', 'mt_suggestion'
    metadata TEXT  -- JSON for extensibility
);

CREATE INDEX idx_tm_source_hash
    ON tm_entries(source_hash);
CREATE INDEX idx_tm_language_pair
    ON tm_entries(source_language, target_language);
CREATE INDEX idx_tm_quality
    ON tm_entries(quality_score DESC) WHERE quality_score > 0.8;
CREATE INDEX idx_tm_usage
    ON tm_entries(usage_count DESC);

-- Full-text search for fuzzy matching
CREATE VIRTUAL TABLE tm_fts USING fts5(
    source_text,
    target_text,
    content='tm_entries',
    content_rowid='rowid'
);

-- Triggers to keep FTS synchronized
CREATE TRIGGER tm_fts_insert AFTER INSERT ON tm_entries BEGIN
    INSERT INTO tm_fts(rowid, source_text, target_text)
    VALUES (new.rowid, new.source_text, new.target_text);
END;

CREATE TRIGGER tm_fts_delete AFTER DELETE ON tm_entries BEGIN
    DELETE FROM tm_fts WHERE rowid = old.rowid;
END;

CREATE TRIGGER tm_fts_update AFTER UPDATE ON tm_entries BEGIN
    UPDATE tm_fts
    SET source_text = new.source_text, target_text = new.target_text
    WHERE rowid = new.rowid;
END;

-- ============================================================================

CREATE TABLE tm_metadata (
    id TEXT PRIMARY KEY,  -- UUID
    key TEXT NOT NULL UNIQUE,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
) WITHOUT ROWID;

-- Store global TM statistics
INSERT INTO tm_metadata (id, key, value, updated_at) VALUES
    ('tm_version', 'version', '1.0', strftime('%s', 'now')),
    ('tm_entry_count', 'entry_count', '0', strftime('%s', 'now')),
    ('tm_last_import', 'last_import', '', strftime('%s', 'now'));

-- ============================================================================
-- APPLICATION TABLES
-- User preferences, settings, application state
-- ============================================================================

CREATE TABLE app_settings (
    id TEXT PRIMARY KEY,  -- UUID
    category TEXT NOT NULL,  -- 'ui', 'editor', 'tm', 'performance'
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(category, key)
) WITHOUT ROWID;

CREATE INDEX idx_app_settings_category
    ON app_settings(category);

-- ============================================================================
-- DATABASE METADATA
-- ============================================================================

CREATE TABLE db_metadata (
    schema_version INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    last_migration_at INTEGER
);

INSERT INTO db_metadata (schema_version, created_at)
VALUES (1, strftime('%s', 'now'));

-- ============================================================================
-- PERFORMANCE OPTIMIZATIONS
-- ============================================================================

-- Enable WAL mode for concurrent reads + writes
PRAGMA journal_mode = WAL;

-- Optimize for performance
PRAGMA synchronous = NORMAL;  -- Safe with WAL mode
PRAGMA cache_size = -64000;  -- 64MB cache
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;  -- 256MB memory-mapped I/O

-- Auto-vacuum to prevent fragmentation
PRAGMA auto_vacuum = INCREMENTAL;

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Complete translation units with their translations
CREATE VIEW v_translation_units_with_translations AS
SELECT
    tu.id AS tu_id,
    tu.project_id,
    tu.source_text,
    tu.source_hash,
    tu.context,
    t.id AS translation_id,
    t.target_text,
    t.status,
    t.created_at AS translation_created_at,
    t.modified_at AS translation_modified_at
FROM operational_translation_units tu
LEFT JOIN operational_translations t ON tu.id = t.translation_unit_id;

-- TM entries with usage statistics
CREATE VIEW v_tm_entries_stats AS
SELECT
    id,
    source_text,
    target_text,
    source_language,
    target_language,
    quality_score,
    usage_count,
    CASE
        WHEN usage_count > 100 THEN 'highly_used'
        WHEN usage_count > 10 THEN 'frequently_used'
        WHEN usage_count > 0 THEN 'occasionally_used'
        ELSE 'unused'
    END AS usage_category,
    created_at,
    last_used_at
FROM tm_entries;

-- ============================================================================
-- NOTES
-- ============================================================================

-- 1. All timestamps are Unix epoch (INTEGER) for consistency
-- 2. UUIDs are TEXT (36 characters: 8-4-4-4-12 format)
-- 3. JSON fields use TEXT type (parse in application layer)
-- 4. Foreign keys enforced with ON DELETE CASCADE for data integrity
-- 5. WITHOUT ROWID optimization for tables with UUID primary keys
-- 6. Indexes strategically placed based on query patterns
-- 7. FTS5 for fuzzy TM matching (levenshtein distance in app layer)
-- 8. WAL mode enables concurrent reads without blocking
-- 9. Single database ensures ACID properties across operational + TM operations
-- 10. Clear naming convention: 'operational_*', 'tm_*', 'app_*' for logical separation
