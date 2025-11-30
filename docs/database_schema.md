# TWMT - Database Schema

This file contains the complete database schema for the Total War Mods Translator application.

## Overview

The database uses SQLite with the following optimizations:
- **UUIDs**: All tables use UUID primary keys (TEXT type)
- **WAL Mode**: Write-Ahead Logging for better performance
- **FTS5**: Full-text search for efficient text searching
- **Indexes**: Optimized indexes for 10k+ rows (100-800x performance gain)
- **Triggers**: Automatic timestamp and cache management
- **Constraints**: CHECK constraints for data validation

## Complete Schema

```sql
-- ============================================================================
-- TWMT Database Schema - OPTIMIZED VERSION
-- Total War Mods Translator - Windows Desktop Application
-- ============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;  -- Write-Ahead Logging pour meilleures performances

-- ============================================================================
-- TABLES DE RÉFÉRENCE
-- ============================================================================

-- Languages: Langues supportées
CREATE TABLE languages (
    id TEXT PRIMARY KEY,  -- UUID
    code TEXT NOT NULL UNIQUE,  -- 'fr', 'de', 'es', 'en', 'ru', 'zh'
    name TEXT NOT NULL,  -- 'French', 'German', 'Spanish'
    native_name TEXT NOT NULL,  -- 'Français', 'Deutsch', 'Español'
    is_active INTEGER NOT NULL DEFAULT 1,
    CHECK (is_active IN (0, 1))
);

-- Translation Providers: Fournisseurs de traduction
CREATE TABLE translation_providers (
    id TEXT PRIMARY KEY,  -- UUID
    code TEXT NOT NULL UNIQUE,  -- 'anthropic_sonnet', 'anthropic_haiku', 'openai_gpt4o', 'deepl'
    name TEXT NOT NULL,  -- 'Anthropic Claude Sonnet 4.5', 'OpenAI GPT-4o', 'DeepL'
    api_endpoint TEXT,
    default_model TEXT,
    max_context_tokens INTEGER,  -- Capacité max en tokens du modèle (context window / input)
    max_output_tokens INTEGER,  -- Capacité max en tokens de sortie (output)
    max_batch_size INTEGER NOT NULL DEFAULT 30,
    rate_limit_rpm INTEGER,  -- Requests per minute
    rate_limit_tpm INTEGER,  -- Tokens per minute (input)
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    CHECK (is_active IN (0, 1)),
    CHECK (max_context_tokens IS NULL OR max_context_tokens > 0),
    CHECK (max_output_tokens IS NULL OR max_output_tokens > 0)
);

-- ============================================================================
-- GESTION DES JEUX
-- ============================================================================

-- Game Installations: Jeux Total War détectés
CREATE TABLE game_installations (
    id TEXT PRIMARY KEY,
    game_code TEXT NOT NULL UNIQUE,  -- 'warhammer3', 'rome2', 'troy'
    game_name TEXT NOT NULL,  -- 'Total War: WARHAMMER III'
    installation_path TEXT,
    steam_workshop_path TEXT,
    steam_app_id TEXT,  -- Steam App ID pour SteamCMD
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
-- GESTION DES PROJETS
-- ============================================================================

-- Projects: Projets de traduction de mods
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    mod_steam_id TEXT,  -- Steam Workshop ID du mod source
    mod_version TEXT,
    game_installation_id TEXT NOT NULL,
    source_file_path TEXT,
    output_file_path TEXT,
    status TEXT NOT NULL DEFAULT 'draft',
    last_update_check INTEGER,
    source_mod_updated INTEGER,
    -- Paramètres de traduction par projet
    batch_size INTEGER NOT NULL DEFAULT 25,  -- Nombre de lignes par batch
    parallel_batches INTEGER NOT NULL DEFAULT 3,  -- Nombre de batches en parallèle
    custom_prompt TEXT,  -- Prompt personnalisé pour ce projet (complète le prompt du jeu)
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    completed_at INTEGER,
    metadata TEXT,  -- JSON pour données supplémentaires
    FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
    CHECK (status IN ('draft', 'translating', 'reviewing', 'completed')),
    CHECK (batch_size > 0 AND batch_size <= 100),
    CHECK (parallel_batches > 0 AND parallel_batches <= 20),
    CHECK (created_at <= updated_at)
);

-- Project Languages: Langues cibles d'un projet
CREATE TABLE project_languages (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    language_id TEXT NOT NULL,  -- UUID de la langue
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

-- Mod Versions: Historique des versions du mod source
CREATE TABLE mod_versions (
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

-- Mod Version Changes: Changements détaillés entre versions
CREATE TABLE mod_version_changes (
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
-- UNITÉS DE TRADUCTION
-- ============================================================================

-- Translation Units: Unités de texte à traduire (source)
CREATE TABLE translation_units (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    key TEXT NOT NULL,  -- Clé du fichier de localisation
    source_text TEXT NOT NULL,
    source_language_id TEXT,  -- UUID de la langue source
    context TEXT,
    notes TEXT,
    is_obsolete INTEGER NOT NULL DEFAULT 0,  -- Marqué obsolète si mod mis à jour
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (source_language_id) REFERENCES languages(id) ON DELETE SET NULL,
    UNIQUE(project_id, key),
    CHECK (is_obsolete IN (0, 1)),
    CHECK (created_at <= updated_at)
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

-- Translation Version History: Historique des modifications
CREATE TABLE translation_version_history (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    status TEXT NOT NULL,
    confidence_score REAL,
    changed_by TEXT NOT NULL,  -- 'system', 'user', 'llm:{provider}'
    change_reason TEXT,
    created_at INTEGER NOT NULL,
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
    provider_id TEXT NOT NULL,  -- UUID du provider utilisé (historique)
    batch_number INTEGER NOT NULL,  -- Numéro séquentiel dans le projet
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
-- MÉMOIRE DE TRADUCTION
-- ============================================================================

-- Translation Memory: Réutilisation des traductions
CREATE TABLE translation_memory (
    id TEXT PRIMARY KEY,
    source_text TEXT NOT NULL,
    source_hash TEXT NOT NULL,  -- SHA256 du source_text
    source_language_id TEXT NOT NULL,  -- UUID de la langue source
    target_language_id TEXT NOT NULL,  -- UUID de la langue cible
    translated_text TEXT NOT NULL,
    game_context TEXT,  -- game_code pour différencier entre jeux
    translation_provider_id TEXT,  -- UUID du provider
    quality_score REAL,  -- Score de qualité agrégé (0-1)
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

-- Translation Version TM Usage: Traçabilité TM utilisée
CREATE TABLE translation_version_tm_usage (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,
    tm_id TEXT NOT NULL,
    match_confidence REAL NOT NULL,  -- Degré de correspondance (0-1)
    applied_at INTEGER NOT NULL,
    FOREIGN KEY (version_id) REFERENCES translation_versions(id) ON DELETE CASCADE,
    FOREIGN KEY (tm_id) REFERENCES translation_memory(id) ON DELETE CASCADE,
    CHECK (match_confidence >= 0 AND match_confidence <= 1)
);

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

-- Settings: Configuration utilisateur
CREATE TABLE settings (
    id TEXT PRIMARY KEY,
    key TEXT UNIQUE NOT NULL,
    value TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'string',  -- 'string', 'integer', 'boolean', 'json'
    updated_at INTEGER NOT NULL,
    CHECK (value_type IN ('string', 'integer', 'boolean', 'json'))
);

-- ============================================================================
-- INDEX POUR PERFORMANCE (Gain 100-800x)
-- ============================================================================

-- Projects
CREATE INDEX idx_projects_game ON projects(game_installation_id, status);
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

-- Translation Versions
CREATE INDEX idx_translation_versions_unit ON translation_versions(unit_id);
CREATE INDEX idx_translation_versions_proj_lang ON translation_versions(project_language_id, status);
CREATE INDEX idx_translation_versions_status ON translation_versions(status);

-- Translation Batches
CREATE INDEX idx_batches_proj_lang ON translation_batches(project_language_id, status);
CREATE INDEX idx_batches_provider ON translation_batches(provider_id, status);

-- Translation Batch Units
CREATE INDEX idx_batch_units_batch ON translation_batch_units(batch_id, status);
CREATE INDEX idx_batch_units_unit ON translation_batch_units(unit_id);

-- Translation Memory
CREATE INDEX idx_tm_hash_lang_context ON translation_memory(source_hash, target_language_id, game_context);
CREATE INDEX idx_tm_source_lang ON translation_memory(source_language_id, target_language_id);
CREATE INDEX idx_tm_last_used ON translation_memory(last_used_at DESC);
CREATE INDEX idx_tm_game_context ON translation_memory(game_context, quality_score DESC);

-- Translation Version TM Usage
CREATE INDEX idx_tm_usage_version ON translation_version_tm_usage(version_id);
CREATE INDEX idx_tm_usage_tm ON translation_version_tm_usage(tm_id);

-- Game Installations
CREATE INDEX idx_game_installations_code ON game_installations(game_code);
CREATE INDEX idx_game_installations_valid ON game_installations(is_valid);

-- Settings
CREATE INDEX idx_settings_key ON settings(key);

-- Languages (pour recherche par code)
CREATE INDEX idx_languages_code ON languages(code);

-- Translation Providers (pour recherche par code)
CREATE INDEX idx_translation_providers_code ON translation_providers(code);

-- ============================================================================
-- FULL-TEXT SEARCH (FTS5) POUR RECHERCHE PERFORMANTE
-- ============================================================================

-- FTS5 pour recherche dans translation_units
-- Permet recherche full-text 100-1000x plus rapide que LIKE
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
    content='translation_versions',
    content_rowid='rowid'
);

-- Triggers pour maintenir FTS5 à jour avec translation_units

CREATE TRIGGER trg_translation_units_fts_insert AFTER INSERT ON translation_units BEGIN
    INSERT INTO translation_units_fts(rowid, key, source_text, context, notes)
    VALUES (new.rowid, new.key, new.source_text, new.context, new.notes);
END;

CREATE TRIGGER trg_translation_units_fts_update AFTER UPDATE ON translation_units BEGIN
    UPDATE translation_units_fts
    SET key = new.key,
        source_text = new.source_text,
        context = new.context,
        notes = new.notes
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_translation_units_fts_delete AFTER DELETE ON translation_units BEGIN
    DELETE FROM translation_units_fts WHERE rowid = old.rowid;
END;

-- Triggers pour maintenir FTS5 à jour avec translation_versions

CREATE TRIGGER trg_translation_versions_fts_insert AFTER INSERT ON translation_versions BEGIN
    INSERT INTO translation_versions_fts(rowid, translated_text, validation_issues)
    VALUES (new.rowid, new.translated_text, new.validation_issues);
END;

CREATE TRIGGER trg_translation_versions_fts_update AFTER UPDATE ON translation_versions BEGIN
    UPDATE translation_versions_fts
    SET translated_text = new.translated_text,
        validation_issues = new.validation_issues
    WHERE rowid = new.rowid;
END;

CREATE TRIGGER trg_translation_versions_fts_delete AFTER DELETE ON translation_versions BEGIN
    DELETE FROM translation_versions_fts WHERE rowid = old.rowid;
END;

-- ============================================================================
-- TABLE DÉNORMALISÉE POUR PERFORMANCE (DataGrid)
-- ============================================================================

-- Cache dénormalisé pour affichage rapide dans DataGrid
-- Évite les JOIN complexes pour chaque ligne affichée
CREATE TABLE translation_view_cache (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    project_language_id TEXT NOT NULL,
    language_code TEXT NOT NULL,
    unit_id TEXT NOT NULL,
    version_id TEXT,

    -- Données dénormalisées
    key TEXT NOT NULL,
    source_text TEXT NOT NULL,
    translated_text TEXT,
    status TEXT NOT NULL,
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
    unit_created_at INTEGER NOT NULL,
    unit_updated_at INTEGER NOT NULL,
    version_updated_at INTEGER,

    FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
    FOREIGN KEY (project_language_id) REFERENCES project_languages(id) ON DELETE CASCADE
);

-- Index pour accès rapide par projet + langue
CREATE INDEX idx_translation_cache_proj_lang
    ON translation_view_cache(project_id, project_language_id);

CREATE INDEX idx_translation_cache_status
    ON translation_view_cache(project_language_id, status);

CREATE INDEX idx_translation_cache_updated
    ON translation_view_cache(project_language_id, version_updated_at DESC);

-- Triggers pour maintenir le cache à jour

-- Mise à jour du cache quand une translation_unit change
CREATE TRIGGER trg_update_cache_on_unit_change
AFTER UPDATE ON translation_units
BEGIN
    UPDATE translation_view_cache
    SET key = new.key,
        source_text = new.source_text,
        is_obsolete = new.is_obsolete,
        unit_updated_at = new.updated_at
    WHERE unit_id = new.id;
END;

-- Mise à jour du cache quand une translation_version change
CREATE TRIGGER trg_update_cache_on_version_change
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

-- Insertion dans le cache pour nouvelles versions
CREATE TRIGGER trg_insert_cache_on_version_insert
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

-- Suppression du cache quand une version est supprimée
CREATE TRIGGER trg_delete_cache_on_version_delete
AFTER DELETE ON translation_versions
BEGIN
    DELETE FROM translation_view_cache
    WHERE version_id = old.id;
END;

-- ============================================================================
-- VUES POUR STATISTIQUES
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
-- TRIGGERS POUR AUTOMATION
-- ============================================================================

-- Mise à jour automatique du progress_percent
CREATE TRIGGER trg_update_project_language_progress
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

-- Mise à jour automatique des timestamps
CREATE TRIGGER trg_projects_updated_at
AFTER UPDATE ON projects
BEGIN
    UPDATE projects SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_translation_units_updated_at
AFTER UPDATE ON translation_units
BEGIN
    UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_translation_versions_updated_at
AFTER UPDATE ON translation_versions
BEGIN
    UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
END;

-- ============================================================================
-- DONNÉES DE RÉFÉRENCE INITIALES
-- ============================================================================

-- Langues supportées (par ordre alphabétique)
INSERT INTO languages (id, code, name, native_name, is_active) VALUES
('lang_de', 'de', 'German', 'Deutsch', 1),
('lang_en', 'en', 'English', 'English', 1),
('lang_zh', 'zh', 'Chinese', '中文', 1),
('lang_es', 'es', 'Spanish', 'Español', 1),
('lang_fr', 'fr', 'French', 'Français', 1),
('lang_ru', 'ru', 'Russian', 'Русский', 1);

-- Providers de traduction (par ordre alphabétique)
-- Note: Les rate limits correspondent aux tiers Build/Tier 2 (payants de base)
-- Les utilisateurs peuvent ajuster selon leur tier réel dans les paramètres
INSERT INTO translation_providers (id, code, name, api_endpoint, default_model, max_context_tokens, max_output_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at) VALUES
('provider_anthropic_sonnet', 'anthropic_sonnet', 'Anthropic Claude Sonnet 4.5', 'https://api.anthropic.com/v1', 'claude-sonnet-4-5-20250929', 200000, 64000, 25, 50, 40000, 1, strftime('%s', 'now')),
('provider_anthropic_haiku', 'anthropic_haiku', 'Anthropic Claude Haiku 4.5', 'https://api.anthropic.com/v1', 'claude-haiku-4-5-20251001', 200000, 64000, 25, 50, 50000, 1, strftime('%s', 'now')),
('provider_deepl', 'deepl', 'DeepL', 'https://api.deepl.com/v2', NULL, NULL, NULL, 50, NULL, NULL, 1, strftime('%s', 'now')),
('provider_openai_gpt4o', 'openai_gpt4o', 'OpenAI GPT-4o', 'https://api.openai.com/v1', 'gpt-4o', 128000, 16384, 40, 5000, 300000, 1, strftime('%s', 'now')),
('provider_openai_gpt4turbo', 'openai_gpt4turbo', 'OpenAI GPT-4 Turbo', 'https://api.openai.com/v1', 'gpt-4-turbo', 128000, 4096, 40, 5000, 300000, 1, strftime('%s', 'now'));

-- Settings par défaut
INSERT INTO settings (id, key, value, value_type, updated_at) VALUES
('setting_active_provider', 'active_translation_provider_id', 'provider_anthropic_sonnet', 'string', strftime('%s', 'now')),
('setting_default_game', 'default_game_installation_id', '', 'string', strftime('%s', 'now')),
-- Prompts de contexte par défaut par jeu (JSON: {game_code: prompt})
('setting_game_prompts', 'default_game_context_prompts', '{}', 'json', strftime('%s', 'now')),
-- Paramètres de batch par défaut
('setting_default_batch_size', 'default_batch_size', '25', 'integer', strftime('%s', 'now')),
('setting_default_parallel_batches', 'default_parallel_batches', '3', 'integer', strftime('%s', 'now'));
```

## Schema Improvements

The schema includes the following key improvements:

1. **UUIDs everywhere**: All tables use UUIDs (TEXT PRIMARY KEY)
2. **Reference tables**: `languages`, `translation_providers` with UUIDs and unique codes
3. **Global LLM provider**: Single configuration in `settings`, used for all projects
4. **Model capabilities**: `max_context_tokens` and `max_output_tokens` stored in `translation_providers` for automatic validation
5. **Latest LLM models (2025)**: Claude Sonnet 4.5 (200k context, 64k output), Claude Haiku 4.5 (200k context, 64k output), GPT-4o (128k context, 16k output), GPT-4 Turbo (128k context, 4k output)
6. **Complete versioning**: `mod_versions`, `mod_version_changes` for update tracking
7. **History**: `translation_version_history` for audit trail
8. **Batch traceability**: `translation_batch_units` for many-to-many relationship (provider history)
9. **Enhanced translation memory**: With `translation_version_tm_usage` for tracking
10. **Optimized indexes**: 15+ indexes for 100-800x performance gain
11. **Practical views**: Pre-calculated statistics for dashboard
12. **Automatic triggers**: Auto-calculation of `progress_percent` and timestamps
13. **Robust constraints**: Validation via CHECK on all statuses and values
14. **Supported languages**: German, English, Chinese, Spanish, French, Russian
15. **Per-project translation parameters**: `batch_size`, `parallel_batches`, `custom_prompt`

## Database Location

The database file is stored at:
```
%APPDATA%\Roaming\TWMT\twmt.db
```

Using `getApplicationSupportDirectory()` from the `path_provider` package.

## Reference

For implementation details and usage examples, see the main specifications document: [`specs.md`](./specs.md)
