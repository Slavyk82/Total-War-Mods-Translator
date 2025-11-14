# Total War Mod Translator (TWMT) - Spécifications

## Vue d'ensemble

TWMT est une application Windows desktop développée en Flutter qui permet aux utilisateurs de traduire facilement les mods des jeux Total War en utilisant les Large Language Models (LLM). L'application offre une interface intuitive pour gérer des projets de traduction, avec des performances optimisées pour traiter des fichiers de localisation volumineux.

## Objectifs principaux

1. **Simplicité**: Interface utilisateur intuitive et parcours simplifié
2. **Performance**: Gestion efficace de fichiers avec 10 000+ lignes de traduction
3. **Flexibilité**: Édition manuelle des traductions générées par LLM
4. **Intégration**: Utilisation de RPFM-CLI pour l'extraction des fichiers
5. **Qualité**: Traductions contextuelles adaptées à l'univers Total War

## Architecture technique

### Stack technologique

- **Frontend**: Flutter (Windows Desktop)
- **UI Framework**: Fluent Design System
- **Base de données**: SQLite unique (sqflite_common_ffi) - `twmt.db`
- **LLM Integration**: API Anthropic (Claude), OpenAI, DeepL
- **Extraction**: RPFM-CLI (outil externe en ligne de commande)
- **Synchronisation**: SteamCMD pour suivi des mods sources
- **State Management**: Provider Pattern
- **Architecture**: Clean Architecture avec séparation des couches

### Couche de services (Business Layer)

**Documentation complète** : Voir [`docs/architecture_services.md`](docs/architecture_services.md)

La couche services implémente la **Clean Architecture** avec une séparation stricte entre Présentation (UI) → Services (Business Logic) → Repositories (Data Access).

**Services principaux** :
- **LLM Services** : Interface unifiée pour Anthropic, OpenAI, DeepL avec factory pattern, rate limiting, token calculation
- **RPFM Service** : Extraction/création de fichiers .pack, validation, auto-détection de l'installation
- **Steam Services** : SteamCMD pour téléchargement de mods, Workshop API pour détection de mises à jour
- **Translation Orchestrator** : Workflow complet TM lookup → LLM → Validation → Save avec traitement parallèle
- **File Services** : Parsing de fichiers .loc/.tsv, écriture avec préfixage de langue
- **Validation Service** : Vérification de la qualité des traductions (variables, longueur, caractères spéciaux)
- **Prompt Builder** : Construction de prompts (système + jeu + projet + instructions)

**Gestion d'erreurs** : Type `Result<T, E>` pour gestion d'erreurs type-safe (pattern fonctionnel inspiré de Rust), hiérarchie d'exceptions complète (20+ types d'erreurs spécialisées).

**Injection de dépendances** : Service Locator avec get_it, tous les services enregistrés au démarrage, interfaces mockables pour tests.

**Total** : ~40 fichiers de services avec interfaces, implémentations, modèles et utilitaires.

### Structure de données

#### Schéma de base de données optimisé

Le schéma ci-dessous a été optimisé par l'agent database-architect pour garantir :
- **Intégrité des données** : Clés étrangères complètes avec CASCADE appropriés
- **Performance** : Index optimisés pour 10k+ lignes (gain 100-800x)
- **Traçabilité** : Historique des modifications et versioning
- **Validation** : Contraintes CHECK sur tous les champs critiques

```sql
-- ============================================================================
-- TWMT Database Schema - OPTIMIZED VERSION
-- Total War Mod Translator - Windows Desktop Application
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
    code TEXT NOT NULL UNIQUE,  -- 'anthropic', 'openai', 'deepl'
    name TEXT NOT NULL,  -- 'Anthropic Claude', 'OpenAI GPT', 'DeepL'
    api_endpoint TEXT,
    default_model TEXT,
    max_context_tokens INTEGER,  -- Capacité max en tokens du modèle (context window)
    max_batch_size INTEGER NOT NULL DEFAULT 30,
    rate_limit_rpm INTEGER,  -- Requests per minute
    rate_limit_tpm INTEGER,  -- Tokens per minute
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    CHECK (is_active IN (0, 1)),
    CHECK (max_context_tokens IS NULL OR max_context_tokens > 0)
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
    CHECK (parallel_batches > 0 AND parallel_batches <= 10),
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
INSERT INTO translation_providers (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at) VALUES
('provider_anthropic', 'anthropic', 'Anthropic Claude', 'https://api.anthropic.com/v1', 'claude-3-5-sonnet-20241022', 200000, 25, 50, 40000, 1, strftime('%s', 'now')),
('provider_deepl', 'deepl', 'DeepL', 'https://api.deepl.com/v2', NULL, NULL, 50, 100, NULL, 1, strftime('%s', 'now')),
('provider_openai', 'openai', 'OpenAI GPT', 'https://api.openai.com/v1', 'gpt-4-turbo-preview', 128000, 40, 60, 90000, 1, strftime('%s', 'now'));

-- Settings par défaut
INSERT INTO settings (id, key, value, value_type, updated_at) VALUES
('setting_active_provider', 'active_translation_provider_id', 'provider_anthropic', 'string', strftime('%s', 'now')),
('setting_default_game', 'default_game_installation_id', '', 'string', strftime('%s', 'now')),
-- Prompts de contexte par défaut par jeu (JSON: {game_code: prompt})
('setting_game_prompts', 'default_game_context_prompts', '{}', 'json', strftime('%s', 'now')),
-- Paramètres de batch par défaut
('setting_default_batch_size', 'default_batch_size', '25', 'integer', strftime('%s', 'now')),
('setting_default_parallel_batches', 'default_parallel_batches', '3', 'integer', strftime('%s', 'now'));
```

### Améliorations principales du schéma

1. **UUIDs partout** : Toutes les tables utilisent des UUIDs (TEXT PRIMARY KEY)
2. **Tables de référence** : `languages`, `translation_providers` avec UUIDs et codes uniques
3. **Provider LLM global** : Configuration unique dans `settings`, utilisé pour tous les projets
4. **Capacités des modèles** : `max_context_tokens` stocké dans `translation_providers` pour validation automatique
5. **Versioning complet** : `mod_versions`, `mod_version_changes` pour suivi des mises à jour
6. **Historique** : `translation_version_history` pour audit trail
7. **Traçabilité batches** : `translation_batch_units` pour relation many-to-many (historique du provider utilisé)
8. **Mémoire de traduction améliorée** : Avec `translation_version_tm_usage` pour tracking
9. **Index optimisés** : 15+ index pour gain de performance 100-800x
10. **Vues pratiques** : Statistiques pré-calculées pour dashboard
11. **Triggers automatiques** : Calcul auto du `progress_percent` et timestamps
12. **Contraintes robustes** : Validation via CHECK sur tous les statuts et valeurs
13. **Langues supportées** : Allemand, Anglais, Chinois, Espagnol, Français, Russe
14. **Paramètres de traduction par projet** : `batch_size`, `parallel_batches`, `custom_prompt`

## Fonctionnalités principales

### 1. Gestion des jeux et installations

#### Détection automatique des jeux
- Scan automatique des installations Steam
- Détection des chemins d'installation standards
- Identification des dossiers Steam Workshop
- Vérification de la validité des installations
- Liste des jeux supportés:
  - Total War: WARHAMMER III
  - Total War: WARHAMMER II
  - Total War: WARHAMMER
  - Total War: ROME II
  - Total War: ATTILA
  - Total War: TROY
  - Total War: THREE KINGDOMS
  - Total War: PHARAOH

#### Configuration manuelle
- Ajout manuel des chemins d'installation
- Configuration des dossiers Workshop personnalisés
- Validation des chemins configurés
- Sauvegarde des préférences utilisateur

### 2. Gestion des mods du Workshop

#### Détection des mods
- **Scan automatique** du dossier Workshop du jeu sélectionné
- Lecture des fichiers `.pack` présents
- Extraction des métadonnées via RPFM-CLI :
  - Steam Workshop ID (depuis le nom de dossier)
  - Nom du mod (depuis les métadonnées)
  - Version (si disponible)
  - Taille du fichier
- **Association avec les projets existants**
  - Vérification si un projet existe déjà pour ce mod
  - Affichage du nom du projet et des langues en cours

#### Écran "Mods"
- Liste paginée de tous les mods détectés
- Recherche par nom ou Steam ID
- Tri par nom, taille, date de modification
- **Actions disponibles** :
  - **[+ Créer projet de traduction]** : Pour les mods sans projet
  - **[Ouvrir projet]** : Pour les mods avec projet existant
  - **[Rafraîchir]** : Re-scan du dossier Workshop

### 3. Gestion des projets

#### Création de projet
- Depuis l'écran "Mods" : sélection d'un mod
- **Sélection multiple des langues de destination** (parmi les 6 supportées)
- Nom du projet (modifiable, pré-rempli avec le nom du mod)
- **Paramètres de traduction** :
  - Nombre de lignes par batch (valeur par défaut depuis settings)
  - Nombre de batches en parallèle (valeur par défaut depuis settings)
  - Prompt personnalisé optionnel (complète le prompt du jeu)
- Extraction automatique des fichiers de localisation via RPFM-CLI
- Association automatique avec le Steam Workshop ID pour suivi des mises à jour
- **Utilisation du provider LLM global** configuré dans les paramètres

#### Écran "Projects"
- Liste de **tous les projets**, quel que soit le statut
- Filtrage par :
  - **Statut** : Brouillon, En cours, Révision, Terminé
  - **Jeu** : Filtré automatiquement par le jeu sélectionné
  - **Langue** : Projets contenant une langue spécifique
- **Recherche** par nom de mod ou de projet
- **Tri** par date de modification, progression, nom
- **Indicateurs visuels** :
  - Progression par langue (pourcentage + icône de statut)
  - Alerte de mise à jour disponible (⚠)
  - Date de dernière modification ou de completion

#### Dashboard projet (dans l'éditeur)
- Vue d'ensemble avec statistiques de progression **par langue**
- Nombre de lignes total/traduites/révisées **pour chaque langue**
- **Indicateur de mise à jour disponible** du mod source
- Estimation du temps restant par langue
- Gestion des statuts par langue
- **Synchronisation avec Steam Workshop** via SteamCMD

### 4. Interface de traduction

#### Éditeur principal (DataGrid optimisé)
- **Tableau virtualisé** pour performances optimales (10k+ lignes)
- **Sélecteur de langue** pour basculer entre les traductions
- Colonnes dynamiques selon la langue sélectionnée:
  - Clé | Texte source | Traduction [LANGUE] | Statut | Actions
- **Vue comparative multi-langues** (affichage côte-à-côte)
- **Filtrage en temps réel** par statut, texte, clé, langue
- **Tri** sur toutes les colonnes
- **Recherche** avec highlighting
- **Navigation clavier** complète
- **Indicateurs de mise à jour** pour les textes modifiés dans le mod source

#### Modes d'édition
1. **Mode automatique**: Traduction par batch via LLM
2. **Mode manuel**: Édition ligne par ligne
3. **Mode hybride**: Traduction LLM + révision manuelle
4. **Mode validation**: Révision des traductions uniquement

#### Panneau de détail (splitview)
- Affichage du contexte de traduction
- Historique des modifications
- Notes et commentaires
- Suggestions de la mémoire de traduction
- Score de confiance de la traduction

### 5. Traitement par LLM

#### Providers supportés

##### Anthropic (Claude)
- Support des modèles Claude 3.5 Sonnet, Claude 3 Opus
- Contexte étendu (200k tokens)
- Excellente compréhension du contexte de jeu
- Traduction nuancée et créative

##### OpenAI
- Support GPT-4, GPT-4 Turbo, GPT-3.5
- Traduction rapide et cohérente
- Bonne gestion des termes techniques

##### DeepL
- API dédiée à la traduction
- Qualité professionnelle
- Support de nombreuses langues
- Traitement rapide des gros volumes
- Glossaires personnalisés intégrés

#### Configuration du provider (GLOBAL)
- **Provider unique** configuré dans les paramètres
- S'applique à **tous les projets** et **toutes les langues**
- Peut être changé à tout moment dans les paramètres
- Les batches en cours continuent avec leur provider d'origine
- Les nouveaux batches utilisent le provider actif

#### Gestion intelligente des tokens

##### Capacités par modèle (context window)

Les capacités en tokens sont stockées dans la table `translation_providers` (colonne `max_context_tokens`) :

| Provider | Modèle par défaut | max_context_tokens |
|----------|-------------------|-------------------|
| Anthropic Claude | claude-3-5-sonnet-20241022 | 200,000 |
| OpenAI GPT | gpt-4-turbo-preview | 128,000 |
| DeepL | N/A | NULL (pas de limite tokens, mais 128KB par requête) |

**Note** : Si vous changez de modèle dans les paramètres (ex: GPT-4 au lieu de GPT-4 Turbo), pensez à mettre à jour la valeur `max_context_tokens` en conséquence :
- GPT-4: 8,000 tokens
- GPT-3.5 Turbo: 16,000 tokens
- Claude 3 Opus: 200,000 tokens

##### Calcul des tokens estimés
- **Estimation rapide** : 1 token ≈ 4 caractères (moyenne pour textes anglais/européens)
- **Formule** : `tokens_estimés = longueur_totale_texte / 4`
- **Buffers de sécurité** :
  - 20% pour les variations de tokenisation
  - Tokens du prompt système (contexte jeu + instructions)
  - Tokens de sortie (traduction ≈ même taille que source)

##### Ajustement automatique de la taille des batches
1. **Au lancement du batch** :
   - Récupérer `max_context_tokens` depuis `translation_providers` pour le provider actif
   - Calculer les tokens estimés pour N lignes configurées
   - Vérifier : `tokens_estimés * 2.4 < max_context_tokens`
     - x2 pour input + output
     - x1.2 pour buffer sécurité
   - Si dépassement : réduire automatiquement la taille du batch

2. **Division intelligente** :
   - Si batch trop grand : diviser en sous-batches
   - Respecter les limites du modèle
   - Logger les ajustements

3. **Alertes utilisateur** :
   - Notification si réduction automatique > 30%
   - Suggestion d'ajuster manuellement `batch_size` du projet

#### Système de prompts contextuels

##### Prompt par défaut par jeu (Settings)
- Configuration globale dans les paramètres
- Exemple pour Warhammer III :
  ```
  Tu traduis des textes du jeu Total War: WARHAMMER III, un jeu de stratégie
  fantasy. Le contexte inclut des noms de factions (Empire, Nains, Comtes Vampires),
  des unités militaires, des sorts et des technologies. Conserve les noms propres
  en anglais sauf si une traduction officielle existe. Adapte le ton épique et
  médiéval-fantastique.
  ```

##### Prompt personnalisé par projet
- Champ `custom_prompt` dans la table `projects`
- **Complète** le prompt du jeu (ne le remplace pas)
- Exemple pour un mod spécifique :
  ```
  Ce mod ajoute des unités médiévales historiques. Les noms d'unités doivent
  suivre les conventions historiques françaises (ex: "Chevalier" au lieu de "Knight").
  ```

##### Construction du prompt final
```
[Prompt système de base]
+ [Prompt du jeu depuis settings]
+ [Prompt personnalisé du projet si défini]
+ [Instructions de traduction]
+ [Format de sortie attendu]
```

#### Pipeline de traduction
1. **Utilisation du provider actif global** configuré dans les paramètres
   - Récupération du provider depuis `settings` (clé: `active_translation_provider_id`)
   - Lecture de `max_context_tokens` depuis la table `translation_providers`
2. **Analyse du contexte**: Détection automatique de la langue source
3. **Construction du prompt contextuel** :
   - Prompt du jeu (depuis settings)
   - Prompt personnalisé du projet (si défini)
   - Instructions de traduction et format
4. **Calcul des tokens** :
   - Estimation des tokens du batch
   - Vérification : `tokens_estimés * 2.4 < max_context_tokens`
   - Ajustement automatique si nécessaire
5. **Batching intelligent**: Groupement selon `batch_size` du projet
   - Valeur configurable par projet (1-100 lignes)
   - Ajustement automatique selon `max_context_tokens` du provider
6. **Traduction parallèle**: Exécution de N batches en parallèle
   - Nombre configurable par projet (1-10 batches)
   - Respect des rate limits API (`rate_limit_rpm`, `rate_limit_tpm`)
7. **Validation**: Vérification de cohérence et complétude
8. **Sauvegarde**: Mise à jour en base de données + historique du provider utilisé

#### Optimisations
- **Mémoire de traduction**: Réutilisation des traductions existantes
- **Cache intelligent**: Éviter les re-traductions inutiles
- **Traitement parallèle**: Multiple batches simultanés
- **Queue management**: File d'attente avec priorités par provider
- **Rate limiting**: Respect des limites API de chaque provider
- **Fallback automatique**: Basculement vers un autre provider si erreur

### 6. Suivi et synchronisation des mods

#### Intégration Steam Workshop
- **Connexion via SteamCMD** pour téléchargement des mods
- **Surveillance automatique** des mises à jour
- **Comparaison de versions** entre mod source et traduction
- **Notifications** de mise à jour disponible
- **Historique des versions** du mod source

#### Gestion des mises à jour
- **Détection des changements** dans les fichiers de localisation
- **Marquage des traductions obsolètes**
- **Fusion intelligente** des nouvelles entrées
- **Préservation des traductions existantes** validées
- **Rapport de différences** entre versions
- **Re-traduction sélective** des éléments modifiés

### 7. Contrôle qualité

#### Validation automatique
- Détection des traductions manquantes
- Vérification de la longueur (alerte si >150% de l'original)
- Détection des variables non traduites ({0}, %s, etc.)
- Cohérence terminologique (glossaire personnalisé)
- Détection des caractères spéciaux manquants

#### Outils de révision
- Mode comparaison côte-à-côte
- Highlighting des différences
- Validation par batch
- Export des problèmes détectés
- Statistiques de qualité

### 8. Import/Export

#### Import
- Fichiers .pack via RPFM-CLI
- Fichiers .loc/.tsv directement
- Import de mémoire de traduction (.tmx)
- Import de glossaires

#### Export de traductions

##### Principe de fonctionnement
**IMPORTANT** : Les packs de traduction générés contiennent **UNIQUEMENT les fichiers de traduction**, pas le mod source complet. L'utilisateur doit installer le mod source ET le pack de traduction pour que cela fonctionne.

##### Convention de nommage des fichiers

**IMPORTANT** : Le préfixage s'applique à **DEUX niveaux** :
1. Le nom du fichier `.pack` lui-même
2. **Tous les fichiers `.loc` à l'intérieur du `.pack`**

Pour que les traductions prennent priorité sur les fichiers de localisation originaux, la convention de préfixage est :

```
!!!!!!!!!!_{LANG_CODE}_nom_fichier.loc
```

**Exemples de préfixage des fichiers .loc** :
- `test.loc` → `!!!!!!!!!!_FR_test.loc` (français)
- `test.loc` → `!!!!!!!!!!_DE_test.loc` (allemand)
- `units.loc` → `!!!!!!!!!!_ES_units.loc` (espagnol)
- `ui_strings.loc` → `!!!!!!!!!!_RU_ui_strings.loc` (russe)
- `buildings.loc` → `!!!!!!!!!!_FR_buildings.loc` (français)

**Exemple complet de nommage** :
```
Fichier .pack: !!!!!!!!!!_FR_medieval_kingdoms.pack
  └── Contient:
      ├── text/db/!!!!!!!!!!_FR_test.loc          ← Préfixé
      ├── text/db/!!!!!!!!!!_FR_units.loc         ← Préfixé
      ├── text/db/!!!!!!!!!!_FR_buildings.loc     ← Préfixé
      └── text/db/!!!!!!!!!!_FR_ui_strings.loc    ← Préfixé
```

**Codes de langue** (codes ISO 639-1 en majuscules) :
- FR - Français
- DE - Allemand / Deutsch
- ES - Espagnol / Español
- EN - Anglais / English
- RU - Russe / Русский
- ZH - Chinois / 中文

##### Processus d'export par RPFM-CLI

1. **Extraction initiale** (lors de la création du projet) :
   ```bash
   rpfm-cli -p "chemin/vers/mod_source.pack" --extract-all --output "temp/extraction"
   ```

2. **Création du fichier de localisation traduit** :
   - Génération du fichier `.loc` avec les traductions d'une langue
   - **Préfixage obligatoire** : `!!!!!!!!!!_{LANG}_nom_original.loc`
   - Format : TSV (tab-separated values) avec encodage UTF-8
   - Structure :
     ```
     key1	texte_traduit_1
     key2	texte_traduit_2
     ```

3. **Création du pack de traduction** :
   - Le fichier .pack ET tous les .loc qu'il contient doivent être préfixés
   ```bash
   # Création d'un pack préfixé contenant des fichiers .loc préfixés
   rpfm-cli -p "output/!!!!!!!!!!_{LANG}_nom_mod.pack" \
            --add-file "text/db/!!!!!!!!!!_{LANG}_nom_original.loc"
   ```

   **IMPORTANT** : Les fichiers .loc ajoutés au pack doivent **déjà être préfixés** avant d'être intégrés dans le .pack

4. **Export multi-langues** :
   - Génération d'un pack **par langue**
   - Exemples :
     - `!!!!!!!!!!_FR_medieval_kingdoms.pack` (contient tous les fichiers traduits en français)
     - `!!!!!!!!!!_DE_medieval_kingdoms.pack` (contient tous les fichiers traduits en allemand)
     - `!!!!!!!!!!_ES_medieval_kingdoms.pack` (contient tous les fichiers traduits en espagnol)

##### Structure du pack de traduction exporté

```
!!!!!!!!!!_FR_nom_mod.pack                          ← Pack préfixé
├── text/
│   └── db/
│       ├── !!!!!!!!!!_FR_units.loc                ← Fichier préfixé
│       ├── !!!!!!!!!!_FR_ui_strings.loc           ← Fichier préfixé
│       ├── !!!!!!!!!!_FR_buildings.loc            ← Fichier préfixé
│       └── !!!!!!!!!!_FR_technologies.loc         ← Fichier préfixé
```

**IMPORTANT** :
- Le pack ne contient **AUCUN** fichier du mod source (scripts, modèles 3D, textures, etc.)
- Contient **UNIQUEMENT** les fichiers de localisation traduits
- **Tous les fichiers `.loc` à l'intérieur sont préfixés** avec `!!!!!!!!!!_{LANG}_`
- Le préfixage assure que les traductions ont priorité sur les fichiers originaux du mod source

##### Workflow d'export dans l'interface

Dans l'éditeur de traduction :

1. **Bouton [Exporter]** :
   - Sélection de la langue à exporter (ou toutes)
   - Choix du dossier de destination
   - Options :
     - [ ] Exporter seulement les traductions approuvées
     - [ ] Inclure les traductions en révision
     - [ ] Générer un rapport d'export

2. **Process d'export** :
   - Récupération des traductions depuis la base de données
   - **Génération des fichiers `.loc` préfixés** par langue :
     - `units.loc` → `!!!!!!!!!!_FR_units.loc`
     - `buildings.loc` → `!!!!!!!!!!_FR_buildings.loc`
     - etc.
   - **Création du pack préfixé** via RPFM-CLI contenant les fichiers préfixés :
     - Nom du pack : `!!!!!!!!!!_FR_nom_mod.pack`
     - Contenu : Tous les `.loc` déjà préfixés
   - Validation du pack généré (vérification du préfixage)
   - Notification de succès avec chemin du pack

3. **Fichiers générés** :
   ```
   output/
   ├── !!!!!!!!!!_FR_medieval_kingdoms.pack
   ├── !!!!!!!!!!_DE_medieval_kingdoms.pack
   ├── !!!!!!!!!!_ES_medieval_kingdoms.pack
   └── reports/
       ├── export_FR_2025-03-14.txt
       ├── export_DE_2025-03-14.txt
       └── export_ES_2025-03-14.txt
   ```

#### Export pour révision externe
- Export Excel/CSV par langue pour révision externe
- Format :
  - Colonnes : Clé | Source | Traduction | Statut | Commentaires
  - Un fichier par langue
- Sauvegarde de la mémoire de traduction (.tmx format standard)
- Génération de rapports de traduction (statistiques, qualité, progression)

### 9. Configuration et paramètres

#### Paramètres des installations de jeux
- **Détection automatique** au premier lancement
- **Scan des registres Windows** pour trouver Steam
- **Recherche des installations** dans:
  - `C:\Program Files (x86)\Steam\steamapps\common\`
  - `D:\SteamLibrary\steamapps\common\`
  - Autres bibliothèques Steam configurées
- **Configuration manuelle** des chemins
- **Validation** de l'intégrité des installations
- **Association des Steam App IDs** pour SteamCMD

#### Paramètres LLM
- **Sélection du provider actif** (GLOBAL pour tous les projets et langues):
  - Anthropic Claude
  - OpenAI GPT
  - DeepL
- **Configuration par provider**:
  - Anthropic: Clé API, modèle (Claude 3.5 Sonnet, Claude 3 Opus)
  - OpenAI: Clé API, modèle (GPT-4, GPT-4 Turbo, GPT-3.5)
  - DeepL: Clé API, plan (Free/Pro)
- **Paramètres de traduction**:
  - Ajustement des paramètres (température, max tokens)
  - Templates de prompts personnalisables par jeu/contexte
- **IMPORTANT** : Le changement de provider s'applique immédiatement à tous les nouveaux batches de traduction

#### Paramètres de traduction
- Taille des batchs
- Délai entre requêtes
- Nombre de threads parallèles
- Seuil de confiance minimum

#### Personnalisation
- Glossaires par jeu/faction
- Règles de traduction personnalisées
- Styles de traduction (formel/informel)
- Gestion des noms propres

## Interface utilisateur

### Écrans principaux

#### 1. Écran d'accueil
```
┌─────────────────────────────────────────────────────────┐
│  TWMT - Total War Mod Translator                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Jeu sélectionné: [▼ Total War: WARHAMMER III   ]     │
│                                                         │
│  Navigation:                                           │
│  ┌─────────────────────────────────────────────────┐  │
│  │  [Mods]  [Projects]  [Paramètres]               │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  Statistiques rapides pour WH3:                        │
│  ┌─────────────────────────────────────────────────┐  │
│  │  📦 45 mods dans Workshop                       │  │
│  │  📋 12 projets de traduction                    │  │
│  │  ✓  8 projets terminés                          │  │
│  │  ⚡ 4 projets en cours                          │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

#### 2. Écran "Mods" - Liste des mods du Workshop
```
┌─────────────────────────────────────────────────────────┐
│  Mods - Total War: WARHAMMER III                       │
├─────────────────────────────────────────────────────────┤
│  [◀ Retour] | 🔍 Rechercher un mod...                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Mods disponibles dans le Workshop:                    │
│  ┌─────────────────────────────────────────────────┐  │
│  │ 📦 Medieval Kingdoms                            │  │
│  │    Steam ID: 2886992456                         │  │
│  │    Version: 1.2.3 | Taille: 2.1 GB              │  │
│  │    [+ Créer projet de traduction]               │  │
│  ├─────────────────────────────────────────────────┤  │
│  │ 📦 Divide et Impera                             │  │
│  │    Steam ID: 2245493206                         │  │
│  │    Version: 4.0.1 | Taille: 850 MB              │  │
│  │    ✓ Projet existant: "DiE FR/ES"              │  │
│  │    [Ouvrir projet]                              │  │
│  ├─────────────────────────────────────────────────┤  │
│  │ 📦 SFO - Grimhammer III                        │  │
│  │    Steam ID: 1149625355                         │  │
│  │    Version: 3.2.0 | Taille: 1.5 GB              │  │
│  │    [+ Créer projet de traduction]               │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  Page 1/15 | 45 mods | < >                            │
└─────────────────────────────────────────────────────────┘
```

#### 3. Écran "Projects" - Liste des projets de traduction
```
┌─────────────────────────────────────────────────────────┐
│  Projects - Total War: WARHAMMER III                   │
├─────────────────────────────────────────────────────────┤
│  [◀ Retour] | 🔍 Rechercher... | Filtres: [Tous ▼]     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Projets de traduction:                                │
│  ┌─────────────────────────────────────────────────┐  │
│  │ ▶ Medieval Kingdoms - FR/DE/ES                  │  │
│  │   📊 FR: 75% ✓ | DE: 60% ⚡ | ES: 30% ⏳       │  │
│  │   ⚠ Mise à jour disponible (v1.2.2 → v1.2.3)  │  │
│  │   Modifié: il y a 2h                           │  │
│  │   [Ouvrir] [⚙]                                 │  │
│  ├─────────────────────────────────────────────────┤  │
│  │ ▶ Divide et Impera - ES                        │  │
│  │   📊 ES: 100% ✓ (Terminé)                      │  │
│  │   ✓ À jour avec le mod source                  │  │
│  │   Terminé: 15 mars 2025                        │  │
│  │   [Ouvrir] [⚙]                                 │  │
│  ├─────────────────────────────────────────────────┤  │
│  │ ▶ SFO Grimhammer - FR/RU                       │  │
│  │   📊 FR: 45% ⚡ | RU: 10% ⏳                   │  │
│  │   🔄 Traduction en cours...                    │  │
│  │   Modifié: il y a 30min                        │  │
│  │   [Ouvrir] [⚙]                                 │  │
│  ├─────────────────────────────────────────────────┤  │
│  │ ▶ Ancient Empires - FR (Brouillon)            │  │
│  │   📊 FR: 0% (Non commencé)                     │  │
│  │   Créé: hier                                   │  │
│  │   [Ouvrir] [⚙]                                 │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  Page 1/3 | 12 projets | < >                          │
└─────────────────────────────────────────────────────────┘
```

#### 4. Éditeur de traduction
```
┌───────────────────────────────────────────────────────────────┐
│ Medieval Kingdoms | WH3 | ⚠ v1.2.2→v1.2.3                    │
├───────────────────────────────────────────────────────────────┤
│ Langue: [▼ FR (75%) ] [+ Ajouter langue] | Vue: [Simple ▼] │
├───────────────────────────────────────────────────────────────┤
│ [Traduire tout] [Traduire MAJ] [Valider] [Exporter] | 🔍   │
├───────────────────────────────────────────────────────────────┤
│ Filtres: [✓ À traduire] [✓ Modifiées] [✓ En cours] [  OK] │
├────────┬──────────────┬──────────────┬──────┬──────┤
│ Clé    │ Source (EN)  │ Trad. FR     │ Stat │ ⚙   │
├────────┼──────────────┼──────────────┼──────┼──────┤
│ ui_01  │ New Campaign │ Nouvelle     │ ✓    │ ✏️   │
│        │              │ Campagne     │      │      │
├────────┼──────────────┼──────────────┼──────┼──────┤
│ ui_02⚠ │ Load Game    │ [modifié]    │ ⚡   │ ✏️   │
├────────┼──────────────┼──────────────┼──────┼──────┤
│ ui_03  │ Settings     │ Paramètres   │ ✓    │ ✏️   │
└────────┴──────────────┴──────────────┴─────────┴──────┴──────┘
│ Page 1/250 | 7500 entrées | 12 modifiées | < > |           │
└───────────────────────────────────────────────────────────────┘
```

#### 3. Vue comparative multi-langues
```
┌───────────────────────────────────────────────────────────────┐
│ Medieval Kingdoms | Vue: [Comparative ▼] | Langues: FR,DE,ES │
├───────────────────────────────────────────────────────────────┤
│ [Synchroniser tout] [Exporter tout] | 🔍 Recherche          │
├────────┬──────────────┬──────────┬──────────┬──────────┬────┤
│ Clé    │ Source (EN)  │ FR (75%) │ DE (60%) │ ES (30%) │ ⚙ │
├────────┼──────────────┼──────────┼──────────┼──────────┼────┤
│ ui_01  │ New Campaign │ Nouvelle │ Neue     │ Nueva    │ ✏️ │
│        │              │ Campagne │ Kampagne │ Campaña  │    │
├────────┼──────────────┼──────────┼──────────┼──────────┼────┤
│ ui_02  │ Load Game    │ Charger  │ Spiel    │ [vide]   │ ✏️ │
│        │              │ Partie   │ laden    │          │    │
└────────┴──────────────┴──────────┴──────────┴──────────┴────┘
```

#### 4. Dialogue de paramètres du projet
```
┌─────────────────────────────────────────────────────────────┐
│  Paramètres du projet - Medieval Kingdoms                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Nom du projet:                                            │
│  [Medieval Kingdoms - FR/DE/ES                         ]   │
│                                                             │
│  Jeu:                                                      │
│  Total War: WARHAMMER III (non modifiable)                 │
│                                                             │
│  Steam Workshop ID:                                        │
│  2886992456 (non modifiable)                               │
│                                                             │
│  ───────────────────────────────────────                   │
│  Paramètres de traduction                                 │
│  ───────────────────────────────────────                   │
│                                                             │
│  Lignes par batch: [  25  ] (1-100)                        │
│  ℹ️ Nombre de lignes traduites par requête LLM             │
│                                                             │
│  Batches en parallèle: [  3  ] (1-10)                      │
│  ℹ️ Nombre de requêtes simultanées au provider             │
│                                                             │
│  Prompt personnalisé (optionnel):                          │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ Ce mod ajoute des unités historiques médiévales.    │  │
│  │ Utiliser les termes français historiques pour les   │  │
│  │ unités (ex: "Chevalier" au lieu de "Knight").       │  │
│  │                                                      │  │
│  └─────────────────────────────────────────────────────┘  │
│  ℹ️ Complète le prompt du jeu configuré dans Settings      │
│                                                             │
│                            [Annuler]  [Enregistrer]        │
└─────────────────────────────────────────────────────────────┘
```

#### 5. Écran Paramètres - Prompts de contexte par jeu
```
┌─────────────────────────────────────────────────────────────┐
│  Paramètres - Contexte de traduction                       │
├─────────────────────────────────────────────────────────────┤
│  [◀ Retour] | Onglets: [LLM] [Jeux] [Prompts] [Avancé]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Prompts de contexte par jeu:                              │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ Jeu: [▼ Total War: WARHAMMER III              ]     │  │
│  │                                                      │  │
│  │ Prompt de contexte:                                 │  │
│  │ ┌──────────────────────────────────────────────┐    │  │
│  │ │ Tu traduis des textes du jeu Total War:     │    │  │
│  │ │ WARHAMMER III, un jeu de stratégie fantasy. │    │  │
│  │ │ Le contexte inclut des noms de factions     │    │  │
│  │ │ (Empire, Nains, Comtes Vampires), des unités│    │  │
│  │ │ militaires, des sorts et des technologies.  │    │  │
│  │ │ Conserve les noms propres en anglais sauf si│    │  │
│  │ │ une traduction officielle existe. Adapte le │    │  │
│  │ │ ton épique et médiéval-fantastique.         │    │  │
│  │ │                                              │    │  │
│  │ └──────────────────────────────────────────────┘    │  │
│  │                                                      │  │
│  │ [ Réinitialiser au défaut ]  [ Enregistrer ]        │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  ℹ️ Ce prompt sera utilisé pour tous les projets de ce jeu │
│  ℹ️ Les projets peuvent le compléter via leur propre prompt│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 6. Dialogue d'export
```
┌─────────────────────────────────────────────────────────────┐
│  Exporter les traductions - Medieval Kingdoms               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Sélectionner les langues à exporter:                      │
│  ☑ Français (FR) - 75% complété - 5,432 lignes             │
│  ☑ Allemand (DE) - 60% complété - 4,320 lignes             │
│  ☑ Espagnol (ES) - 30% complété - 2,160 lignes             │
│                                                             │
│  Options d'export:                                         │
│  ☑ Exporter seulement les traductions approuvées           │
│  ☐ Inclure les traductions en révision                     │
│  ☑ Générer un rapport d'export                             │
│                                                             │
│  Dossier de destination:                                   │
│  [E:\TWMT\exports\medieval_kingdoms            ] [Parcourir]│
│                                                             │
│  Fichiers qui seront générés:                              │
│  • !!!!!!!!!!_FR_medieval_kingdoms.pack                    │
│  • !!!!!!!!!!_DE_medieval_kingdoms.pack                    │
│  • !!!!!!!!!!_ES_medieval_kingdoms.pack                    │
│  • reports/export_FR_2025-03-14.txt                        │
│  • reports/export_DE_2025-03-14.txt                        │
│  • reports/export_ES_2025-03-14.txt                        │
│                                                             │
│  ⚠️ Les packs contiennent uniquement les traductions        │
│     (pas le mod source complet)                            │
│                                                             │
│                            [Annuler]  [Exporter]           │
└─────────────────────────────────────────────────────────────┘
```

### Workflow utilisateur type

1. **Premier lancement**
   - Lancement de TWMT
   - **Détection automatique des jeux Total War installés**
   - Configuration des chemins Steam Workshop
   - Configuration des clés API (Anthropic, OpenAI, DeepL)

2. **Sélection du jeu**
   - **Écran d'accueil** : Sélection du jeu via menu déroulant
   - Affichage des statistiques rapides (mods, projets)
   - Navigation vers **[Mods]** ou **[Projects]**

3. **Parcours via écran "Mods"**
   - Liste des mods disponibles dans le Workshop du jeu sélectionné
   - Scan automatique du dossier Workshop
   - Identification des mods avec Steam ID, version, taille
   - Indication si un projet de traduction existe déjà
   - **[+ Créer projet de traduction]** pour un nouveau mod

4. **Création de projet depuis "Mods"**
   - Sélection d'un mod dans la liste
   - **Sélection multiple des langues cibles** (FR, DE, ES, etc.)
   - Nom du projet (pré-rempli avec le nom du mod)
   - Association automatique avec l'ID Steam Workshop pour suivi
   - Utilisation du provider LLM configuré dans les paramètres

5. **Parcours via écran "Projects"**
   - Liste de **tous les projets de traduction** (tous statuts)
   - Filtrage par statut : Brouillon, En cours, Révision, Terminé
   - Recherche par nom de mod ou de projet
   - Indicateurs de progression par langue
   - Alertes de mises à jour disponibles
   - **[Ouvrir]** pour accéder à l'éditeur de traduction

6. **Extraction et analyse** (après création de projet)
   - TWMT lance RPFM-CLI automatiquement
   - Extraction des fichiers de localisation depuis le .pack
   - Détection automatique de la langue source
   - Import dans la base de données
   - Création des entrées pour chaque langue sélectionnée

7. **Traduction multi-langues**
   - Ouverture du projet dans l'éditeur
   - **Traduction parallèle** vers toutes les langues
   - Utilisation du même provider pour toutes les langues
   - Progression en temps réel par langue
   - Possibilité de pause/reprise par langue
   - Gestion de la mémoire de traduction partagée

8. **Révision et édition**
   - **Basculement entre langues** via sélecteur
   - **Vue comparative** multi-langues
   - Filtrage des traductions modifiées/à revoir
   - Édition manuelle avec aperçu temps réel
   - Validation par batch ou individuelle

9. **Synchronisation et mises à jour** (via écran Projects)
   - **Vérification automatique** des mises à jour du mod source
   - **Notification** dans la liste des projets (⚠ icône)
   - **Fusion intelligente** des changements
   - Re-traduction sélective des éléments modifiés
   - Préservation des traductions validées

10. **Export et publication**
    - **Génération des packs de traduction** :
      - Un pack `.pack` par langue (ex: `!!!!!!!!!!_FR_nom_mod.pack`)
      - Contient UNIQUEMENT les fichiers de localisation traduits
      - Tous les fichiers préfixés avec `!!!!!!!!!!_{LANG}_`
      - Compatible avec le mod source original
    - **Installation** :
      - L'utilisateur installe le mod source depuis Steam Workshop
      - Puis installe le pack de traduction dans le dossier `data`
      - Les fichiers préfixés prennent priorité sur les originaux
    - **Publication** :
      - Upload sur Steam Workshop comme mod séparé
      - Marqué comme "Traduction" avec dépendance au mod source
      - Indication de la langue dans le titre et la description
    - **Export multi-langues** :
      - Génération simultanée de plusieurs packs (un par langue)
      - Rapports d'export détaillés par langue

## Performance et optimisation

### Objectifs de performance
- **Chargement initial**: < 2 secondes pour 10k lignes
- **Scrolling**: 60 FPS constant dans le DataGrid
- **Recherche**: Résultats instantanés (< 100ms)
- **Traduction batch**: 100 lignes/minute minimum
- **Mémoire**: < 500MB RAM pour 50k lignes

### Stratégies d'optimisation

#### DataGrid virtualisé
- Rendu uniquement des lignes visibles
- Lazy loading des données
- Cache intelligent des cellules
- Recyclage des widgets

#### Base de données
- Index sur les colonnes fréquemment recherchées
- Pagination des requêtes
- Transactions batch pour les écritures
- WAL mode pour SQLite

#### Traduction LLM
- Queue avec priorités
- Retry exponential backoff
- Parallélisation des requêtes
- Cache des traductions identiques

## Sécurité et confidentialité

### Protection des données
- Clés API chiffrées dans Windows Credential Manager
- Pas d'envoi de données analytics
- Mode offline disponible (avec modèle local)
- Sauvegarde locale automatique

### Gestion des erreurs
- Retry automatique sur échec API
- Sauvegarde de l'état en cas de crash
- Logs détaillés pour debug
- Mode dégradé si LLM indisponible

## Évolutions futures

### Phase 1 (MVP)
- Fonctionnalités de base de traduction
- Support Claude API
- Export simple

### Phase 2
- Multi-provider LLM
- Mémoire de traduction avancée
- Collaboration multi-utilisateurs

### Phase 3
- Plugins pour types de contenu spécifiques
- Intégration directe avec Steam Workshop
- Traduction de textures/images avec texte

## Métriques de succès

1. **Adoption**: 1000+ utilisateurs actifs en 6 mois
2. **Performance**: 95% des sessions sans crash
3. **Productivité**: Réduction de 80% du temps de traduction
4. **Qualité**: Score de satisfaction > 4.5/5
5. **Engagement**: 50% d'utilisateurs récurrents mensuels

## Support et documentation

### Documentation utilisateur
- Guide de démarrage rapide
- Tutoriels vidéo
- FAQ complète
- Troubleshooting guide

### Support technique
- Forum communautaire
- Discord dédié
- Issue tracker GitHub
- Email support pour problèmes critiques

## Données de référence

### Steam App IDs des jeux Total War
```
Total War: WARHAMMER III         - 1142710
Total War: WARHAMMER II          - 594570
Total War: WARHAMMER             - 364360
Total War: ROME II               - 214950
Total War: ATTILA                - 325610
Total War: TROY                  - 1099410
Total War: THREE KINGDOMS        - 779340
Total War: PHARAOH               - 1937780
Total War: SHOGUN 2              - 34330
Total War: NAPOLEON              - 34030
Total War: EMPIRE                - 10500
```

### Structure des fichiers de localisation
- Format: `.loc` ou `.tsv`
- Encodage: UTF-8
- Structure: `key\ttext`
- Chemins typiques dans les mods:
  - `/text/db/*.loc`
  - `/text/localisation/*.tsv`

### Langues supportées
```
Allemand     - de
Anglais      - en
Chinois      - zh
Espagnol     - es
Français     - fr
Russe        - ru
```

## Intégration SteamCMD

### Configuration
```bash
# Téléchargement d'un mod via Steam Workshop
steamcmd +login anonymous +workshop_download_item [APP_ID] [MOD_ID] +quit

# Exemple pour WH3
steamcmd +login anonymous +workshop_download_item 1142710 2886992456 +quit
```

### Chemins de téléchargement
- Windows: `steamcmd\steamapps\workshop\content\[APP_ID]\[MOD_ID]\`
- À copier vers le dossier de travail TWMT pour traitement

### Surveillance des mises à jour
- Vérification périodique via API Steam Workshop
- Comparaison des timestamps de mise à jour
- Téléchargement automatique si nouvelle version détectée

## Conclusion

TWMT vise à devenir l'outil de référence pour la traduction de mods Total War, en combinant la puissance des LLM (Anthropic, OpenAI, DeepL) avec une interface optimisée pour gérer efficacement des volumes importants de texte. Les fonctionnalités de détection automatique des jeux, de traduction multi-langues simultanée et de suivi des mises à jour via Steam Workshop garantiront une expérience utilisateur fluide et professionnelle. L'accent sur la performance, la simplicité d'utilisation et la qualité des traductions garantira une adoption rapide par la communauté des moddeurs.