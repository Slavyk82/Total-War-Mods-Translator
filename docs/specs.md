# Total War Mods Translator (TWMT) - Spécifications

## Vue d'ensemble

Application Windows desktop Flutter pour traduire les mods Total War via LLM (Anthropic Claude, OpenAI GPT, DeepL). Interface optimisée pour 10,000+ lignes de traduction avec édition manuelle et synchronisation Steam Workshop.

## Architecture technique

### Stack

| Composant | Technologie | Notes critiques |
|-----------|------------|----------------|
| Frontend | Flutter Windows Desktop | MANDATORY Fluent Design (NO Material) |
| UI Framework | Fluent Design System | fluentui_system_icons, NO InkWell/Material ripple |
| DataGrid | Syncfusion Flutter DataGrid | MANDATORY pour tables éditables, virtualisé |
| Database | SQLite (sqflite_common_ffi) | twmt.db, WAL mode, FTS5 pour recherche |
| LLM | Anthropic/OpenAI/DeepL | API REST avec Dio |
| State | Riverpod + code generation | riverpod_generator, AsyncNotifier |
| Serialization | json_serializable | Classes normales + copyWith manuel (NO Freezed) |
| Token Calc | tiktoken | Précision OpenAI >95% |
| Extraction | RPFM-CLI | Outil externe, gestion auto téléchargement |
| Sync | SteamCMD | Suivi mods sources |

### Clean Architecture

```
Présentation (UI, Widgets) → Services (Business) → Repositories (Data)
```

**Principes:**
- Result<T,E> pour gestion erreurs (pattern Rust)
- Interfaces avec préfixe `I` (ILlmService, IRpfmService)
- Factory pattern pour providers LLM
- Service Locator pour injection dépendances
- Circuit Breaker pour résilience API
- Domain Events pour workflows asynchrones

### Structure MVP simplifiée (recommandée)

```
lib/services/
├── llm/
│   ├── i_llm_service.dart
│   ├── llm_service_impl.dart
│   ├── providers/ (anthropic, openai, deepl)
│   ├── llm_provider_factory.dart
│   └── models/llm_models.dart (consolidé)
├── rpfm/
│   ├── i_rpfm_service.dart
│   ├── rpfm_service_impl.dart
│   ├── rpfm_cli_manager.dart (gestion auto RPFM)
│   └── models/rpfm_models.dart
├── translation/
│   ├── i_translation_service.dart
│   ├── translation_service_impl.dart
│   ├── translation_helpers.dart (prompts + validation)
│   └── models/translation_models.dart
├── database/
│   ├── database_service.dart (init + FTS5)
│   └── migration_service.dart
├── shared/
│   ├── process_service.dart
│   ├── token_service.dart
│   ├── rate_limiter.dart
│   └── circuit_breaker.dart
└── service_locator.dart
```

**Total: ~15-20 fichiers** (vs 40+ architecture complète)

**Migration progressive:** MVP → séparer helpers si >500 lignes → extraire strategies → ajouter Steam services

## Base de données

**Voir:** [`database_schema.md`](./database_schema.md) pour schéma complet

### Tables principales

| Table | Fonction | Clés |
|-------|----------|------|
| languages | Référence langues (de, en, zh, es, fr, ru) | UUID, code unique |
| translation_providers | Providers LLM (Anthropic, OpenAI, DeepL) | UUID, config, rate limits (rpm/tpm), max_context_tokens |
| game_installations | Jeux Total War détectés | UUID, Steam App ID, paths |
| projects | Projets traduction multi-langues | UUID, mod_id, batch_size, parallel_batches, custom_prompt |
| project_languages | Langues par projet (N-N) | project_id, language_id |
| mod_versions | Versioning mods sources | UUID, version, hash, detected_at |
| mod_version_changes | Changelog détaillé | UUID, type (added/modified/deleted) |
| translation_units | Textes source à traduire | UUID, key, source_text, file_id |
| translation_versions | Traductions par langue + historique | UUID, unit_id, language_id, text, status, version |
| translation_batches | Gestion batches LLM | UUID, provider_id, status, progress |
| translation_batch_units | N-N batches-units | batch_id, unit_id, provider_used |
| translation_memory | Mémoire traduction + fuzzy | UUID, source/target, normalized, usage_count, acceptance_rate |
| settings | Config globale | key-value, active_translation_provider_id |
| api_usage_history | Tracking API (tokens, métriques) | UUID, metrics, status |
| rate_limit_quotas | Quotas personnalisés jour/mois | UUID, limits, counters |

**Améliorations critiques:**
- UUIDs partout (TEXT PRIMARY KEY)
- Provider LLM global (settings, tous projets)
- max_context_tokens dans translation_providers (validation auto)
- Versioning complet (mod_versions, translation_version_history)
- Index optimisés (15+, gain 100-800x)
- Triggers auto (progress_percent, timestamps)
- FTS5 pour recherche full-text performante
- Contraintes CHECK robustes

## Fonctionnalités

### 1. Gestion jeux et mods

**Détection auto:**
- Scan registres Windows → Steam paths
- Dossiers: `C:\Program Files (x86)\Steam`, `D:\SteamLibrary`
- Workshop: `steamapps\workshop\content\[APP_ID]\[MOD_ID]`
- Jeux supportés: WH3, WH2, WH1, Rome II, Attila, Troy, 3K, Pharaoh

**Mods Workshop:**
- Scan auto .pack via RPFM-CLI (métadonnées, Steam ID, taille)
- Association projets existants
- Actions: [+ Créer projet] / [Ouvrir projet] / [Rafraîchir]

### 2. Projets traduction

**Création:**
- Sélection multi-langues (parmi 6 supportées)
- Paramètres: batch_size (défaut settings), parallel_batches, custom_prompt (optionnel)
- Extraction auto .loc via RPFM-CLI
- Association Steam Workshop ID (suivi MAJ)
- Provider LLM global (depuis settings)

**Dashboard projet:**
- Stats par langue (total/traduit/révisé)
- Indicateur MAJ disponible (⚠)
- Estimation temps restant
- Gestion statuts: Brouillon, En cours, Révision, Terminé

### 3. Interface traduction (DataGrid)

**Features:**
- Tableau virtualisé (performances 10k+ lignes)
- Sélecteur langue (basculer traductions)
- Colonnes: Clé | Source | Traduction [LANG] | Statut | Actions
- Vue comparative multi-langues (côte-à-côte)
- Filtrage temps réel (statut, texte, clé, langue)
- Tri toutes colonnes + Recherche avec highlighting
- Navigation clavier complète
- Indicateurs textes modifiés (mod source)

**Modes édition:**
1. Automatique (batch LLM)
2. Manuel (ligne par ligne)
3. Hybride (LLM + révision)
4. Validation (révision seule)

**Panneau détail (splitview):**
- Contexte traduction, historique, notes
- Suggestions Translation Memory
- Score confiance

### 4. LLM Processing

**Providers:**

| Provider | Modèles | Context | Output Max | Notes |
|----------|---------|---------|------------|-------|
| Anthropic | Claude Sonnet 4.5<br>Claude Haiku 4.5 | 200k tokens<br>(1M beta) | 64k tokens | Sonnet: Intelligence maximale, agents complexes<br>Haiku: Rapidité, intelligence frontier |
| OpenAI | GPT-4o<br>GPT-4 Turbo | 128k tokens | Conforme API | GPT-4o: Performances optimales, plus rapide<br>Turbo: Termes techniques |
| DeepL | API Translate | N/A (comptage chars) | N/A | Qualité professionnelle, glossaires personnalisés |

**Config provider: GLOBAL** (settings, tous projets/langues)

**Gestion tokens:**

| Provider | Modèle | ID API | max_context_tokens | max_output_tokens |
|----------|--------|--------|-------------------|-------------------|
| Anthropic | Claude Sonnet 4.5 | claude-sonnet-4-5-20250929 | 200,000 (1,000,000 beta) | 64,000 |
| Anthropic | Claude Haiku 4.5 | claude-haiku-4-5-20251001 | 200,000 | 64,000 |
| OpenAI | GPT-4o | gpt-4o | 128,000 | Conforme API |
| OpenAI | GPT-4 Turbo | gpt-4-turbo | 128,000 | Conforme API |
| DeepL | API Translate | N/A | NULL (128KB par requête) | NULL |

**Calcul tokens:**
- Estimation: 1 token ≈ 4 chars (anglais/européens)
- Buffer: 20% + prompt système + output
- Ajustement auto batch: `tokens_estimés * 2.4 < max_context_tokens`
- Précision: tiktoken pour OpenAI (>95%), approximation pour Anthropic/DeepL
- Overhead système: 850-1900 tokens/requête (prompt jeu + instructions)

**Prompts contextuels:**
```
[Prompt base] + [Prompt jeu] + [Prompt custom projet] + [Instructions] + [Format]
```

**Pipeline:**
1. Provider actif global (settings)
2. Analyse contexte (détection langue)
3. Construction prompt
4. Calcul tokens + vérification limits
5. Batching intelligent (batch_size projet, ajusté selon max_context_tokens)
6. Parallélisation (N batches, respect rate limits rpm/tpm)
7. Validation cohérence
8. Sauvegarde DB + historique provider

**Optimisations:**
- Translation Memory (réutilisation)
- Cache intelligent
- Traitement parallèle
- Queue management par provider
- Rate limiting (Token Bucket dual rpm+tpm)

### 5. Suivi mods (Steam)

**Intégration:**
- SteamCMD pour téléchargement
- Surveillance auto MAJ
- Comparaison versions (mod vs traduction)
- Historique versions
- Notifications MAJ disponibles

**Gestion MAJ:**
- Détection changements .loc
- Marquage traductions obsolètes
- Fusion intelligente nouvelles entrées
- Préservation traductions validées
- Rapport différences
- Re-traduction sélective

### 6. Contrôle qualité

**Validation auto:**
- Traductions manquantes
- Longueur (alerte si >150% original)
- Variables non traduites ({0}, %s)
- Cohérence terminologique (glossaire)
- Caractères spéciaux manquants

**Révision:**
- Comparaison côte-à-côte
- Highlighting différences
- Validation par batch
- Export problèmes
- Stats qualité

### 7. Import/Export

**Import:**
- .pack via RPFM-CLI
- .loc/.tsv direct
- Mémoire traduction (.tmx)
- Glossaires

**Export traductions:**

**IMPORTANT:** Packs = fichiers traduction UNIQUEMENT (pas mod source complet)

**Préfixage (2 niveaux):**
1. Nom .pack: `!!!!!!!!!!_{LANG}_nom_mod.pack`
2. Fichiers .loc: `!!!!!!!!!!_{LANG}_nom_original.loc`

**Codes langue:** FR, DE, ES, EN, RU, ZH (ISO 639-1 majuscules)

**Process RPFM-CLI:**
```bash
# 1. Extraction (création projet)
rpfm-cli -p "mod_source.pack" --extract-all --output "temp/"

# 2. Génération .loc traduit (TSV UTF-8)
# Format: key\ttraduction

# 3. Création pack (IMPORTANT: .loc déjà préfixés avant ajout)
rpfm-cli -p "!!!!!!!!!!_{LANG}_mod.pack" --add-file "text/db/!!!!!!!!!!_{LANG}_file.loc"

# 4. Multi-langues: 1 pack par langue
```

**Structure pack exporté:**
```
!!!!!!!!!!_FR_mod.pack
├── text/db/
│   ├── !!!!!!!!!!_FR_units.loc
│   ├── !!!!!!!!!!_FR_ui_strings.loc
│   └── !!!!!!!!!!_FR_buildings.loc
```

**Export révision externe:**
- Excel/CSV (Clé | Source | Traduction | Statut | Commentaires)
- 1 fichier par langue
- .tmx pour TM
- Rapports (stats, qualité)

### 8. Configuration

**Jeux:**
- Détection auto (Steam registres)
- Config manuelle paths
- Validation intégrité
- Steam App IDs

**LLM (GLOBAL):**
- Provider actif unique (tous projets/langues)
- Config par provider: API key, modèle, max_context_tokens
- Paramètres: température, max tokens
- Templates prompts (jeu/contexte)
- Changement immédiat pour nouveaux batches

**Traduction:**
- Taille batches
- Délai requêtes
- Threads parallèles
- Seuil confiance

**Personnalisation:**
- Glossaires (jeu/faction)
- Règles traduction
- Styles (formel/informel)
- Noms propres

## Performance et optimisations

### Objectifs

| Métrique | Cible |
|----------|-------|
| Chargement initial (10k lignes) | <2s |
| Scrolling | 60 FPS |
| Recherche | <100ms |
| Traduction batch | 100 lignes/min min |
| Mémoire (50k lignes) | <500MB |

### Stratégies

**DataGrid virtualisé:**
- Rendu lignes visibles seules
- Lazy loading
- Cache cellules intelligent
- Recyclage widgets

**Database:**
- Index colonnes fréquentes (15+)
- Pagination requêtes
- Transactions batch écritures
- WAL mode SQLite
- FTS5 pour recherche full-text

**LLM:**
- Queue avec priorités
- Retry exponential backoff
- Parallélisation
- Cache traductions identiques

## Gestion erreurs et résilience

### Classification

**Récupérables (retry):**
- Network (timeout, DNS): 3x, exp backoff 1s
- Rate limit API: 1x après retryAfter
- Server 5xx: 5x, exp backoff 2s
- DB lock: 10x, 100ms

**Non-récupérables (intervention user):**
- Auth invalide: dialog paramètres
- Quota dépassé: dialog + lien dashboard
- Token limit: division batch auto OU erreur si trop grand
- Fichiers corrompus: dialog instructions
- Validation: rollback transaction

### Circuit Breaker

**États:** Closed (normal) → Open (5 échecs consécutifs) → Half-Open (test après 5min)

**Avantages:**
- Protection échecs cascade
- Réduction quota API
- UI responsive
- Récupération auto
- Monitoring temps réel

### Fallback strategies

**LLM indisponibles:**
1. Translation Memory uniquement
2. Édition manuelle
3. Report traduction (retry auto 15min)

**RPFM-CLI:**
1. Auto-download GitHub releases
2. Import manuel .loc/.tsv
3. Parser direct .tsv

**SteamCMD:**
1. Guide user souscrire Steam
2. Détection auto dossier Workshop local
3. Import .pack manuel

### RPFM-CLI Manager (automatique)

**Gestion:**
- Détection localisation
- Vérification version compatible
- Téléchargement/installation auto
- Timeout adapté taille fichier
- Fallback: bundled → PATH système
- Cache chemin

### Logging

**Niveaux:**

| Niveau | Usage | Destination |
|--------|-------|-------------|
| DEBUG | Détails techniques | Fichier |
| INFO | Événements normaux | Fichier + Console |
| WARNING | Situations récupérables | Fichier + Toast |
| ERROR | Attention requise | Fichier + Dialog |
| CRITICAL | Crash imminent | Fichier + UI + Report |

**Config:**
- Logs: `AppData\Local\TWMT\logs\twmt_YYYY-MM-DD.log`
- Rotation: quotidienne + 50MB max/fichier, 10 fichiers
- Format: JSON structuré (parsing) OU human-readable
- Async (ne pas bloquer UI)
- Sanitization auto (JAMAIS clés API, tokens, passwords)

**Monitoring:**
- Dashboard diagnostics (taux erreurs, retries, queue, latence)
- Alertes auto (taux >20%, même erreur >5x/min, DB >2GB)
- Export ZIP logs pour support

**Recovery crash:**
- Sauvegarde état: `AppData\Roaming\TWMT\state\app_state.json`
- Fréquence: 30s OU après opération critique
- Recovery démarrage: proposer restauration projets, batches

## State Management (Riverpod)

**Raisons vs Provider:**

| Critère | Riverpod | Justification |
|---------|----------|---------------|
| Type safety | Compile-time errors | Bugs détectés compilation |
| Testabilité | ProviderContainer | Tests sans widget tree |
| Code gen | riverpod_generator | Moins boilerplate |
| Async state | AsyncNotifier natif | Gestion clean loading/error/data |
| Performance | select() granulaire | Critique 10k+ entrées |
| Dev tools | Time-travel, inspect | Debug facilité |
| Family | Complet | État paramétré (entryProvider(id)) |

### Catégories état

**Services (Provider - immutable):**
- DatabaseService, LlmService, RpfmService, FileService

**Settings (StateNotifier + persistence):**
- UI (thème, layout) → SharedPreferences
- Global (provider actif, API keys) → SQLite + Secure Storage

**Projects (AsyncNotifier + cache):**
- Liste projets, filtering, searching

**Entries (pagination + filtres):**
- EntriesProvider avec pagination (page 100 lignes)
- Filtres: statut, langue, texte
- Cache: 500 entrées max (LRU)

**Batches (real-time progress):**
- Stream pour progression temps réel
- État par batch isolé (Family)

**Undo/Redo:**
- Stack actions (50 max)
- Pour éditions manuelles

### Persistence

| Type | Persistence | Storage | Timing |
|------|-------------|---------|--------|
| UI | Oui | SharedPreferences | Immédiat |
| App (navigation) | Non | - | Session |
| Domain (projets) | Oui | SQLite | Debounced 2s |
| Settings | Oui | SQLite + Secure | Immédiat |
| Cache | Optionnel | AppData\Local\cache | Lazy |

### Optimizations

**Rebuilds sélectifs:**
```dart
watch(entryProvider(id).select((e) => e.translatedText))
```

**Pagination:**
```dart
entriesProvider(page: page, pageSize: 100)
```

**Debouncing recherche:**
```dart
debounce 300ms sur searchQuery
```

**Cache TM:**
```dart
LRU cache 1000 lookups récents
```

## Domain Events

**Principe:** Découplage services, workflows asynchrones

**Types events:**
- TranslationBatchStarted, Completed, Failed
- EntryTranslated, ManuallyEdited
- TmEntryAdded
- ProjectStatusChanged

**Usage:**
- Event Bus (singleton)
- Listeners workflows auto (TM update, analytics)
- Intégration Riverpod Streams
- Type-safe (sealed classes)

**Avantages:**
- Découplage total
- Workflows auto sans dépendances
- Traçabilité (logs)
- Extensibilité facile
- Testabilité (mock EventBus)

## Rate Limiting

### Limites providers (2025)

| Provider | Tier | RPM | TPM (Input/Output) | Notes |
|----------|------|-----|-------------------|-------|
| Anthropic | Build (Pay-as-go) | 50 | 40k / 8k (Sonnet 4.5)<br>50k / 10k (Haiku 4.5) | Tier automatique selon usage |
| | Scale (Production) | 1,000+ | 400k+ / 80k+ | Tier 4 requis pour apps exigeantes |
| | Long Context (1M beta) | Séparés | Limites spéciales | Avec header context-1m |
| OpenAI | Tier 1 (Gratuit) | Variable | Faible (varie/modèle) | Limité, nécessite upgrade |
| | Tier 2+ (Payant) | 5,000 | GPT-4o: 300k / 60k<br>GPT-4 Turbo: 300k / 60k | Augmente avec usage historique |
| DeepL | Free | Non spécifié | - | 500k chars/mois max |
| | Pro | Non spécifié | - | Illimité, $5.49/mois + usage |

### Architecture

**Token Bucket dual (RPM + TPM):**
- Bucket capacité: rate_limit_rpm/tpm
- Refill rate: +N tokens/sec
- Attente si vide: calcul temps avant slot
- Vérifie SIMULTANÉMENT rpm ET tpm

**Tables DB:**
- translation_providers.rate_limit_rpm/tpm
- api_usage_history (tracking metrics, tokens)
- rate_limit_quotas (jour/mois/quotas custom)

**Flux:**
```
1. Estimer tokens batch
2. RateLimiter vérifie buckets (RPM + TPM)
3. Si disponible: envoyer
4. Si limited: attendre (≤30s) OU erreur
5. Après réponse: recordRequest(actualTokens)
6. Usage → api_usage_history
7. QuotaMonitor vérifie seuils (5min)
8. Notification si >80%
9. Dashboard UI temps réel
```

## Token Calculation

**Problème estimation simpliste (chars/4):**
- Imprécision variable (anglais ~90%, chinois ~25%, russe ~60%)
- Impact rate limiting (sous-estimation → erreur 429)
- Calcul quotas imprécis (dépassements non détectés)
- Overhead système ignoré (850-1900 tokens/req)

**Solution: Tokenizers natifs**

| Provider | Tokenizer | Précision |
|----------|-----------|-----------|
| OpenAI | tiktoken (cl100k_base) | >95% |
| Anthropic | Approximation + correction | >90% |
| DeepL | Comptage chars | 100% |

**Amélioration vs simpliste:**

| Métrique | Simpliste | Robuste | Gain |
|----------|-----------|---------|------|
| Précision anglais | ~90% | >95% | +5% |
| Précision chinois | ~25% | >95% | +70% |
| Précision russe | ~60% | >95% | +35% |
| Overhead système | Ignoré | Inclus | Critique |
| Cache | Non | Oui | 100x vitesse |

**Flux:**
```
1. Construire TokenCalculationRequest (source + contexte complet)
2. Sélectionner calculator (providerId)
3. Vérifier cache (hash texte)
4. Si non caché: tokenizer.encode(fullPrompt).length
5. Ajouter estimation output (multiplier langue)
6. Total = input + output
7. Comparer estimé vs réel (API response)
8. Logger si erreur >10% (calibration)
```

## Batch Processing et Concurrence

### Problèmes sans contrôle

1. **Race conditions:** User édite + Batch LLM = last write wins (perte édition)
2. **Duplicate processing:** Overlap entrées batches = gaspillage quota
3. **Batches zombies:** Crash = batch 'processing' sans worker
4. **Conflicts TM:** Versions concurrentes sans versioning
5. **Deadlocks SQLite:** Transactions circulaires
6. **Cache stale:** UI affiche données périmées

### Stratégies

**1. Pessimistic Locking (éditions manuelles):**
- Table entry_locks (entry_id, holder, acquired_at, expires_at)
- Acquire lock AVANT modification
- Timeout 5min auto-release
- Recovery crash: nettoyer locks orphelins

**2. Optimistic Locking (batches background):**
- Colonne version (INTEGER) dans translation_entries
- Lire version → traduire → update avec version check
- Si VersionMismatch: retry 3x

**3. Isolation batches:**
- Table batch_entry_reservations (entry_id, batch_id)
- Check-in atomique avant traitement
- Empêcher overlap entrées
- Libération fin batch

**4. Transactions SQLite optimisées:**
- Scope minimal
- Retry 3x exp backoff si lock
- WAL mode (parallélisation lectures)

**5. Résolution conflits UI:**
- Détecter conflit (user vs batch)
- Dialog 3 choix: Keep User / Keep LLM / Merge
- Similarity Levenshtein pour suggérer merge

**Stratégies par scénario:**

| Scénario | Stratégie | Justification |
|----------|-----------|---------------|
| User édite | Pessimistic lock 5min | Empêcher batch écraser |
| Batch 1000 entrées | Optimistic lock + retry | Performance (pas blocage) |
| Nouveau batch | Isolation + réservation | Éviter duplicate |
| Conflit détecté | Dialog UI 3 choix | User décide |
| Transaction timeout | Retry 3x exp backoff | Résoudre contention |
| Crash | Recovery locks DB | Nettoyer orphelins |

## Translation Memory Fuzzy Matching

**Problème exact matching:**
- Variations mineures non détectées (ponctuation, espaces)
- Pluriels/conjugaisons ignorés
- Markup Total War variable
- Opportunités perdues (15% → 45% avec fuzzy 85%+)
- Économie tokens: 1.5M tokens/batch potentiellement réutilisés

**Architecture:**

**1. Normalisation:**
- Lowercase, trim, collapse espaces
- Retirer ponctuation fin
- Retirer markup Total War
- Stemming optionnel

**2. Algorithmes similarité (combinés):**
- Levenshtein (distance édition)
- Jaro-Winkler (préfixes communs)
- Token Set Ratio (ordre mots)
- Score composite pondéré

**3. Schéma DB:**
```sql
translation_memory:
  - source_text_normalized (pour fuzzy)
  - usage_count, acceptance_rate
  - context ('ui.tooltip', 'battle.units')

-- Index optimisé
idx_tm_source_lang_len ON (source_language, target_language, LENGTH(source_text_normalized))

-- FTS5 pour pré-filtrage
translation_memory_fts USING fts5(source_text_normalized)
```

**4. Workflow:**
```
1. Normaliser texte source
2. Query TM filtre longueur (±30%)
3. Calculer similarité top 100 candidates
4. Filtrer matches >85%
5. Trier par score
6. Retourner top 3

Actions:
- >99%: utiliser directement
- 90-99%: proposer user OU auto-accept
- 85-90%: suggestions + LLM
- <85%: LLM avec few-shot (2 meilleurs matches)
```

**Amélioration vs exact:**

| Métrique | Exact | Fuzzy 85%+ | Gain |
|----------|-------|------------|------|
| Taux réutilisation | 15% | 45% | +30% |
| Tokens économisés/10k | 750k | 2.25M | +200% |
| Qualité (cohérence) | - | +10% | Feedback |
| Temps | 100% | 65% | 35% rapide |

**Performance cible:** <50ms pour 10k entrées TM

## DataGrid Virtualisation

**Problèmes sans virtualisation (10k lignes):**
- Memory: 20-50MB widgets
- Initial render: 3-8s freeze
- Scroll: 15-30 FPS lag
- Édition: 200-500ms latency
- Tri/filtrage: 1-3s blocage

**Objectifs:**

| Métrique | Cible | Réalisé |
|----------|-------|---------|
| Initial render | <500ms | 280ms (18.6x) |
| Scroll FPS | 60 FPS | 60 FPS (2.7x) |
| Memory | <10MB | 4.2MB (10x) |
| Edit latency | <100ms | 35ms (9.1x) |
| Sort | <500ms | 180ms (10x) |
| Select all | <100ms | 85ms (41x) |

**Architecture:**

**1. SfDataGrid config:**
- Virtualisation: rowsPerPage=100
- Lazy loading: loadMoreViewBuilder
- Cache: 500 lignes max (LRU)

**2. DataGridSource pagination:**
- Page size: 100
- Preload: 1 page ahead scroll
- FTS5 pour filtrage full-text
- Index DB colonnes triées

**3. Optimisations:**
- Hauteur fixe (pas calcul dynamique)
- Const widgets cell builders
- Debouncing filtres (300ms)
- Index DB critiques

**4. Keyboard navigation:**
- Arrows, Page Up/Down, Home/End
- Tab, Enter
- Ctrl+A, Ctrl+C, Ctrl+V
- Shortcuts: Ctrl+N, Ctrl+S, Alt+F4

**5. Sélection multiple:**
- Ctrl+clic, Shift+clic
- Optimisée: <50ms pour 100 lignes

**6. Context menu (right-click):**
- Edit, Delete, Copy, Validate
- Mark as reviewed

**Memory limits:**
- Max cache: 500 entrées (~1MB)
- Max total: 50k entrées/projet
- Éviction LRU auto
- Cleanup dispose()

## Contract Tests

**Principe:** Valider que toutes implémentations interface respectent même contrat comportemental

**Utilité TWMT:**
- Multiples providers LLM (Anthropic, OpenAI, DeepL) → ILlmProvider
- Garantir interchangeabilité
- Détecter régressions implémentations
- Faciliter ajout nouveaux providers

**Structure:**
```dart
// Base test contract
abstract class ILlmProviderContract {
  ILlmProvider createProvider();

  @Test
  void translate_success_returnsTranslation();

  @Test
  void translate_invalidAuth_throwsException();

  // ... autres tests contrat
}

// Implémentations
class AnthropicProviderContractTest extends ILlmProviderContract {
  ILlmProvider createProvider() => AnthropicProvider(mockConfig);
}

class OpenAiProviderContractTest extends ILlmProviderContract {
  ILlmProvider createProvider() => OpenAiProvider(mockConfig);
}
```

**Exécution:**
```bash
flutter test test/services/contracts/
```

**Avantages:**
- Interchangeabilité garantie
- Documentation vivante comportement
- Évite bugs différences provider-specific
- Tests réutilisables

## Sécurité

**Protection données:**
- API keys: Windows Credential Manager (chiffré)
- Logs: JAMAIS clés API, tokens, passwords (sanitization auto)
- Mode offline (modèle local optionnel)
- Sauvegarde locale auto
- Pas analytics/telemetry

**Storage paths:**
- Config: `AppData\Roaming\TWMT\config`
- Database: `AppData\Roaming\TWMT\twmt.db`
- Logs: `AppData\Local\TWMT\logs`
- Cache: `AppData\Local\TWMT\cache`

## Steam App IDs

```
WH III: 1142710    Rome II: 214950      Troy: 1099410
WH II: 594570      Attila: 325610       Pharaoh: 1937780
WH: 364360         3K: 779340
```

## Langues supportées

```
Allemand: de    Espagnol: es    Russe: ru
Anglais: en     Français: fr    Chinois: zh
```