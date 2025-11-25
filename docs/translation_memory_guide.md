# Translation Memory - Guide complet

## Vue d'ensemble

La **Translation Memory (TM)** est un système qui stocke les traductions précédemment effectuées pour les réutiliser automatiquement, évitant ainsi de traduire deux fois le même texte et économisant des tokens LLM.

---

## 1. Interface utilisateur

### Écran principal

**Fichier** : `lib/features/translation_memory/screens/translation_memory_screen.dart:1`

### Structure de l'écran

```
┌─────────────────────────────────────────────────────┐
│ 🗃️ Translation Memory        [Import] [Export] [🧹] │
├────────────┬────────────────────────────────────────┤
│            │ 🔍 Search: [_____________] [Filter][↻] │
│ Statistics │                                         │
│            │ ┌─ Filters ─────────────────────────┐  │
│ • Total    │ │ Quality: [All ▼]                  │  │
│ • By lang  │ │ Language: [French ▼]              │  │
│ • Avg qual │ │ Game: [All ▼]          [Reset]    │  │
│ • Usage    │ └───────────────────────────────────┘  │
│ • Tokens   │                                         │
│   saved    │ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │
│            │ ┃ DataGrid - Entries Browser       ┃  │
│ [↻ Refresh]│ ┃ Quality | Source | Target | Game ┃  │
│            │ ┃ ────────┼────────┼────────┼───── ┃  │
│            │ ┃  95%    │ Hello  │ Bonjour│ TW3  ┃  │
│            │ ┃  87%    │ World  │ Monde  │ TW3  ┃  │
│            │ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │
│            │                                         │
│            │           [< 1 2 3 4 5 >]              │
└────────────┴────────────────────────────────────────┘
```

### Composants principaux

#### TmBrowserDataGrid
Grille éditable Syncfusion avec colonnes :
- **Quality** (100px) : Score de qualité avec indicateur visuel
- **Source Text** : Texte source avec prévisualisation
- **Target Text** : Texte traduit
- **Game Context** (120px) : Référence jeu/mod
- **Usage Count** : Nombre de réutilisations
- **Actions** : Bouton supprimer

#### TmStatisticsPanel
Panneau latéral gauche affichant :
- Total d'entrées
- Entrées par paire de langues
- Score de qualité moyen
- Nombre total de réutilisations
- Estimation des tokens économisés
- Taux de réutilisation (%)
- Bouton de rafraîchissement

#### TmFilterPanel
Panneau de filtres repliable avec :
- Filtre de qualité (Tous/Haute/Moyenne/Basse)
- Langue cible (dropdown)
- Contexte de jeu (dropdown)
- Bouton Reset

#### TmSearchBar
Recherche plein texte dans source/target

#### TmPaginationBar
Navigation pour grands ensembles de données

#### Dialogues d'action

**TmxImportDialog** :
- Import de fichiers TMX
- Options d'écrasement
- Validation des entrées
- Suivi de progression

**TmxExportDialog** :
- Export vers format TMX
- Filtrage des entrées
- Progression d'export

**TmCleanupDialog** :
- Nettoyage en masse
- Seuils configurables (qualité/âge)
- Aperçu des suppressions

---

## 2. Modèle de données

### TranslationMemoryEntry

**Fichier** : `lib/models/domain/translation_memory_entry.dart:1`

```dart
class TranslationMemoryEntry {
  final String id;                      // UUID unique
  final String sourceText;              // Texte source original
  final String sourceHash;              // Hash pour correspondance exacte
  final String targetLanguageId;        // UUID langue cible
  final String translatedText;          // Traduction
  final String? gameContext;            // Contexte jeu/mod (optionnel)
  final String? translationProviderId;  // Fournisseur (ChatGPT, Claude, etc.)
  final double? qualityScore;           // Score 0.0-1.0
  final int usageCount;                 // Compteur de réutilisations
  final int createdAt;                  // Timestamp création (Unix)
  final int lastUsedAt;                 // Dernière utilisation (Unix)
  final int updatedAt;                  // Dernière mise à jour (Unix)
}
```

### Modèles auxiliaires

#### TmMatch
Représente un résultat de correspondance :

```dart
class TmMatch {
  final String entryId;
  final String sourceText;
  final String targetText;
  final String targetLanguageCode;
  final double similarityScore;        // 0.0-1.0
  final TmMatchType matchType;         // exact | fuzzy | context
  final SimilarityBreakdown breakdown; // Détail du scoring
  final int usageCount;
  final int lastUsedAt;
  final double? qualityScore;
  final bool autoApplied;              // true si >95% similarité
}

enum TmMatchType {
  exact,    // Correspondance exacte (100%)
  fuzzy,    // Correspondance floue (85-99%)
  context   // Correspondance contextuelle
}
```

#### SimilarityBreakdown
Détail du calcul de similarité :

```dart
class SimilarityBreakdown {
  final double levenshteinScore;       // Distance d'édition (40% poids)
  final double jaroWinklerScore;       // Similarité Jaro-Winkler (30%)
  final double tokenScore;             // Score basé tokens (30%)
  final double contextBoost;           // Bonus contextuel (+5% ou +3%)
}
```

Score final = (0.4 × Levenshtein) + (0.3 × JaroWinkler) + (0.3 × Token) + ContextBoost

#### ScoreWeights
Poids configurables pour algorithmes :

```dart
class ScoreWeights {
  final double levenshteinWeight;      // 0.4 (40%)
  final double jaroWinklerWeight;      // 0.3 (30%)
  final double tokenWeight;            // 0.3 (30%)
}
```

#### TmStatistics
Statistiques agrégées :

```dart
class TmStatistics {
  final int totalEntries;
  final Map<String, int> entriesByLanguagePair;
  final double averageQuality;
  final int totalReuseCount;
  final int tokensSaved;               // Estimation (~50 tokens/réutilisation)
  final double averageFuzzyScore;
  final double reuseRate;              // % traductions TM vs LLM
}
```

---

## 3. Architecture des services

### Service principal

**Interface** : `lib/services/translation_memory/i_translation_memory_service.dart:1`
**Implémentation** : `lib/services/translation_memory/translation_memory_service_impl.dart:1`

#### Opérations CRUD

```dart
// Ajoute ou met à jour avec déduplication automatique
Future<TranslationMemoryEntry> addTranslation({
  required String sourceText,
  required String sourceLanguageId,
  required String targetLanguageId,
  required String translatedText,
  String? gameContext,
  String? translationProviderId,
  double? qualityScore,
});

// Liste paginée avec filtres optionnels
Future<List<TranslationMemoryEntry>> getEntries({
  int limit = 50,
  int offset = 0,
  String? targetLanguageId,
  double? minQuality,
  String? gameContext,
});

// Recherche plein texte (FTS5)
Future<List<TranslationMemoryEntry>> searchEntries({
  required String query,
  String? targetLanguageId,
  int limit = 50,
});

// Supprime une entrée
Future<void> deleteEntry(String id);

// Met à jour le score de qualité
Future<void> updateQuality(String id, double qualityScore);

// Incrémente le compteur d'utilisation
Future<void> incrementUsageCount(String id);
```

#### Opérations de correspondance

Délégué à **TmMatchingService** (`tm_matching_service.dart:1`) :

```dart
// Correspondance exacte par hash (O(1))
Future<TmMatch?> findExactMatch({
  required String sourceText,
  required String targetLanguageCode,
  String? gameContext,
});

// Correspondance floue avec 3 algorithmes
Future<List<TmMatch>> findFuzzyMatches({
  required String sourceText,
  required String targetLanguageCode,
  String? gameContext,
  double threshold = 0.85,
  int limit = 5,
});

// Essaie exact d'abord, puis fuzzy
Future<TmMatch?> findBestMatch({
  required String sourceText,
  required String targetLanguageCode,
  String? gameContext,
});
```

#### Import/Export

Délégué à **TmImportExportService** (`tm_import_export_service.dart:1`) :

```dart
// Import fichiers TMX avec options
Future<void> importFromTmx({
  required String filePath,
  bool overwriteExisting = false,
  void Function(int processed, int total)? onProgress,
});

// Export vers TMX avec filtres
Future<void> exportToTmx({
  required String filePath,
  String? targetLanguageId,
  double? minQuality,
  String? gameContext,
  void Function(int processed, int total)? onProgress,
});
```

#### Maintenance

```dart
// Supprime entrées basse qualité/anciennes
Future<int> cleanupLowQualityEntries({
  double minQuality = 0.3,
  int maxDaysSinceLastUse = 365,
});

// Statistiques agrégées
Future<TmStatistics> getStatistics();

// Gestion du cache
Future<void> clearCache();
Future<void> rebuildCache();
```

---

### Services spécialisés

#### SimilarityCalculator

**Fichier** : `lib/services/translation_memory/similarity_calculator.dart:1`

Calcule la similarité entre deux textes avec 3 algorithmes :

**1. Levenshtein (40% poids)** - Distance d'édition
- Mesure le nombre minimum d'opérations (insertion/suppression/substitution)
- Excellent pour détecter fautes de frappe
- Formule : `1 - (distance / max(len1, len2))`

**2. Jaro-Winkler (30% poids)** - Similarité de chaînes
- Favorise les correspondances au début de la chaîne
- Bon pour noms propres et textes courts
- Plus tolérant aux transpositions

**3. Token-based (30% poids)** - Comparaison de tokens
- Indépendant de l'ordre des mots
- Compare ensembles de mots (Jaccard similarity)
- Formule : `intersection(tokens) / union(tokens)`

**Bonus contextuel** :
- +5% si `gameContext` identique
- +3% si catégorie (1er mot du contexte) identique

```dart
class SimilarityCalculator {
  static const ScoreWeights defaultWeights = ScoreWeights(
    levenshteinWeight: 0.4,
    jaroWinklerWeight: 0.3,
    tokenWeight: 0.3,
  );

  double calculate({
    required String source1,
    required String source2,
    String? context1,
    String? context2,
    ScoreWeights weights = defaultWeights,
  });
}
```

#### TextNormalizer

**Fichier** : `lib/services/translation_memory/text_normalizer.dart:1`

Normalise le texte pour correspondance cohérente :
- Convertit en minuscules
- Supprime espaces multiples
- Normalise Unicode (NFD)
- Gère caractères spéciaux
- Préserve ponctuation significative

#### TmCache

**Fichier** : `lib/services/translation_memory/tm_cache.dart:1`

Cache en mémoire pour correspondances exactes :
- Structure : `Map<String, TranslationMemoryEntry>`
- Clé : `sourceHash:targetLanguageCode`
- Invalidation automatique lors de modifications
- Améliore performances de 10-100x pour recherches répétées

#### TmxService

**Fichier** : `lib/services/translation_memory/tmx_service.dart:1`

Support du format TMX 1.4b (Translation Memory eXchange) :

**Export** :
```dart
Future<void> exportToTmx({
  required List<TranslationMemoryEntry> entries,
  required String outputPath,
  String sourceLanguage = 'en',
});
```

Génère XML avec structure :
```xml
<?xml version="1.0" encoding="UTF-8"?>
<tmx version="1.4">
  <header
    creationtool="TWMT"
    creationtoolversion="1.0"
    srclang="en"
    datatype="plaintext"
    segtype="sentence"
    o-tmf="TWMT TMX"/>
  <body>
    <tu>
      <tuv xml:lang="en"><seg>Hello world</seg></tuv>
      <tuv xml:lang="fr"><seg>Bonjour monde</seg></tuv>
      <prop type="x-quality-score">0.95</prop>
      <prop type="x-usage-count">42</prop>
      <prop type="x-game-context">Total War 3</prop>
    </tu>
  </body>
</tmx>
```

**Import** :
```dart
Future<List<TranslationMemoryEntry>> importFromTmx({
  required String filePath,
  bool validateEntries = true,
});
```

Parse XML et valide :
- Structure TMX valide
- Présence des langues source/cible
- Métadonnées TWMT (si présentes)

---

## 4. Schéma de base de données

**Fichier** : `lib/database/schema.sql:245`

### Table principale

```sql
CREATE TABLE translation_memory (
    id TEXT PRIMARY KEY,
    source_text TEXT NOT NULL,
    source_hash TEXT NOT NULL,              -- Hash SHA-256 pour match exact
    source_language_id TEXT NOT NULL,
    target_language_id TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    game_context TEXT,                      -- Contexte jeu/mod (nullable)
    translation_provider_id TEXT,           -- Fournisseur (nullable)
    quality_score REAL,                     -- 0.0-1.0 (nullable)
    usage_count INTEGER NOT NULL DEFAULT 1, -- Compteur réutilisation
    created_at INTEGER NOT NULL,            -- Timestamp Unix
    last_used_at INTEGER NOT NULL,          -- Timestamp Unix
    updated_at INTEGER NOT NULL,            -- Timestamp Unix

    -- Clés étrangères
    FOREIGN KEY (source_language_id)
        REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (target_language_id)
        REFERENCES languages(id) ON DELETE RESTRICT,
    FOREIGN KEY (translation_provider_id)
        REFERENCES translation_providers(id) ON DELETE SET NULL,

    -- Contraintes
    UNIQUE(source_hash, target_language_id, game_context),
    CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
    CHECK (usage_count >= 1)
);
```

### Index de performance

**Impact : 100-800x amélioration de vitesse**

```sql
-- Index 1 : Match exact ultra-rapide
-- Usage : findExactMatch() - O(1) lookup
CREATE INDEX idx_tm_hash_lang_context
    ON translation_memory(source_hash, target_language_id, game_context);

-- Index 2 : Recherche par paire de langues
-- Usage : Filtrage par langue source/cible
CREATE INDEX idx_tm_source_lang
    ON translation_memory(source_language_id, target_language_id);

-- Index 3 : Tri par dernière utilisation
-- Usage : Cleanup, statistiques temporelles
CREATE INDEX idx_tm_last_used
    ON translation_memory(last_used_at DESC);

-- Index 4 : Filtrage par jeu et qualité
-- Usage : Recherche contextuelle, filtres UI
CREATE INDEX idx_tm_game_context
    ON translation_memory(game_context, quality_score DESC);
```

### Table de suivi d'utilisation

```sql
CREATE TABLE translation_version_tm_usage (
    id TEXT PRIMARY KEY,
    version_id TEXT NOT NULL,              -- FK: translation_versions.id
    tm_id TEXT NOT NULL,                   -- FK: translation_memory.id
    match_confidence REAL NOT NULL,        -- Score de correspondance 0.0-1.0
    applied_at INTEGER NOT NULL,           -- Timestamp Unix

    FOREIGN KEY (version_id)
        REFERENCES translation_versions(id) ON DELETE CASCADE,
    FOREIGN KEY (tm_id)
        REFERENCES translation_memory(id) ON DELETE CASCADE,

    CHECK (match_confidence >= 0 AND match_confidence <= 1)
);

-- Index pour requêtes par version
CREATE INDEX idx_tm_usage_version
    ON translation_version_tm_usage(version_id);

-- Index pour statistiques par entrée TM
CREATE INDEX idx_tm_usage_tm
    ON translation_version_tm_usage(tm_id);
```

### Vue FTS5 (Full-Text Search) - Prévu

```sql
-- Table virtuelle pour recherche plein texte optimisée
CREATE VIRTUAL TABLE translation_memory_fts USING fts5(
    id UNINDEXED,
    source_text,
    translated_text,
    game_context,
    content='translation_memory',
    content_rowid='id'
);

-- Triggers pour synchronisation automatique
CREATE TRIGGER tm_fts_insert AFTER INSERT ON translation_memory BEGIN
    INSERT INTO translation_memory_fts(id, source_text, translated_text, game_context)
    VALUES (new.id, new.source_text, new.translated_text, new.game_context);
END;

CREATE TRIGGER tm_fts_delete AFTER DELETE ON translation_memory BEGIN
    DELETE FROM translation_memory_fts WHERE id = old.id;
END;

CREATE TRIGGER tm_fts_update AFTER UPDATE ON translation_memory BEGIN
    UPDATE translation_memory_fts
    SET source_text = new.source_text,
        translated_text = new.translated_text,
        game_context = new.game_context
    WHERE id = new.id;
END;
```

**Avantages FTS5** :
- Recherche plein texte 100-1000x plus rapide
- Ranking BM25 pour pertinence
- Support opérateurs : AND, OR, NOT, NEAR
- Tokenisation intelligente

---

## 5. Fonctionnement conceptuel

### A. Ajout à la Translation Memory

```
Traduction effectuée (via LLM ou manuelle)
    ↓
1. Normalisation du texte source
   - Minuscules, espaces, Unicode NFD
    ↓
2. Calcul du hash source (SHA-256)
    ↓
3. Vérification d'existence
   Query: SELECT * FROM translation_memory
          WHERE source_hash = ?
          AND target_language_id = ?
          AND game_context = ?
    ↓
4a. SI EXISTE :
    - Incrémenter usage_count
    - Mettre à jour quality_score si meilleur
    - Mettre à jour last_used_at
    - Retourner entrée existante
    ↓
4b. SI NOUVEAU :
    - Créer nouvelle entrée
    - quality_score initial : 0.8 (configurable)
    - usage_count : 1
    - Timestamps : created_at, last_used_at, updated_at
    - Métadonnées : game_context, translation_provider_id
    ↓
5. Invalider cache pour cette clé
    ↓
6. Retourner TranslationMemoryEntry
```

### B. Recherche de correspondance

#### Stratégie 1 : Match exact (PRIORITAIRE, RAPIDE)

```
Texte à traduire : "Hello world"
    ↓
1. Normaliser texte
   "Hello world" → "hello world"
    ↓
2. Calculer hash
   SHA-256("hello world") → "5eb63bbb..."
    ↓
3. Vérifier cache
   Clé : "5eb63bbb...:fr"
    ├─ HIT → Retourner TmMatch immédiatement
    └─ MISS → Continuer
    ↓
4. Query database
   SELECT * FROM translation_memory
   WHERE source_hash = '5eb63bbb...'
   AND target_language_id = 'uuid-fr'
   AND (game_context = 'TW3' OR game_context IS NULL)
    ↓
5a. SI TROUVÉ :
    - Créer TmMatch
      • similarityScore : 1.0 (100%)
      • matchType : exact
      • autoApplied : true
    - Ajouter au cache
    - Retourner résultat
    ↓
5b. SI NON TROUVÉ :
    → Passer au match fuzzy
```

**Complexité** : O(1) avec index - ~0.1-1ms

#### Stratégie 2 : Match fuzzy (FALLBACK, LENT)

```
Pas de match exact trouvé
    ↓
1. Récupérer candidats
   SELECT * FROM translation_memory
   WHERE target_language_id = 'uuid-fr'
   AND (game_context = 'TW3' OR game_context IS NULL)
   ORDER BY quality_score DESC, usage_count DESC
   LIMIT 1000  -- Limite pour performance
    ↓
2. Pour chaque candidat :
    ↓
    a. Normaliser les deux textes
    ↓
    b. Calculer Levenshtein
       distance("hello world", "hello wonderful world")
       score = 1 - (distance / max_length)
       levenshteinScore = 0.82
    ↓
    c. Calculer Jaro-Winkler
       jaroWinklerScore = 0.89
    ↓
    d. Calculer Token-based
       tokens1 = ["hello", "world"]
       tokens2 = ["hello", "wonderful", "world"]
       intersection = ["hello", "world"] (2)
       union = ["hello", "world", "wonderful"] (3)
       tokenScore = 2/3 = 0.67
    ↓
    e. Calculer score pondéré
       baseScore = (0.4 × 0.82) + (0.3 × 0.89) + (0.3 × 0.67)
                 = 0.328 + 0.267 + 0.201
                 = 0.796
    ↓
    f. Appliquer bonus contextuel
       SI game_context identique : +0.05
       SI catégorie identique : +0.03
       finalScore = 0.796 + 0.05 = 0.846
    ↓
3. Filtrer résultats
   Garder seulement si finalScore ≥ 0.85 (seuil configurable)
    ↓
4. Trier résultats
   Critères : finalScore DESC, quality_score DESC, usage_count DESC
    ↓
5. Limiter résultats
   Garder top 5 (configurable)
    ↓
6. Créer TmMatch pour chaque résultat
   • similarityScore : 0.846
   • matchType : fuzzy
   • autoApplied : false (< 0.95)
   • breakdown : {levenshtein, jaroWinkler, token, contextBoost}
    ↓
7. Retourner List<TmMatch>
```

**Complexité** : O(n × m) où n = candidats, m = longueur texte - ~50-500ms

**Seuils de décision** :
- ≥ 95% : Auto-appliqué automatiquement
- 85-94% : Proposé à l'utilisateur
- < 85% : Ignoré

### C. Application d'une correspondance

```
Utilisateur accepte TmMatch (ou auto-appliqué)
    ↓
1. Appliquer traduction
   translation.targetText = tmMatch.targetText
    ↓
2. Enregistrer dans translation_version_tm_usage
   INSERT INTO translation_version_tm_usage (
       id, version_id, tm_id, match_confidence, applied_at
   ) VALUES (
       'uuid', 'version-uuid', 'tm-uuid', 0.92, 1234567890
   )
    ↓
3. Incrémenter usage_count dans TM
   UPDATE translation_memory
   SET usage_count = usage_count + 1,
       last_used_at = 1234567890
   WHERE id = 'tm-uuid'
    ↓
4. Mettre à jour qualité si applicable
   - Si utilisateur corrige : réduire quality_score
   - Si accepté tel quel : maintenir/augmenter légèrement
    ↓
5. Invalider cache
    ↓
6. Notifier UI (via Provider/ChangeNotifier)
```

### D. Maintenance et nettoyage

#### Cleanup automatique

```dart
Future<int> cleanupLowQualityEntries({
  double minQuality = 0.3,
  int maxDaysSinceLastUse = 365,
}) async {
  final cutoffTimestamp = DateTime.now()
      .subtract(Duration(days: maxDaysSinceLastUse))
      .millisecondsSinceEpoch ~/ 1000;

  // Supprime entrées basse qualité ET anciennes
  final deleted = await _repository.deleteByQualityAndAge(
    minQuality: minQuality,
    maxLastUsedAt: cutoffTimestamp,
  );

  await clearCache();
  return deleted;
}
```

**Critères de suppression** :
- `quality_score < 0.3` (configurable)
- `last_used_at > 365 jours` (configurable)
- Opérateur : AND (les deux conditions doivent être vraies)

**Quand exécuter** :
- Manuellement via UI (TmCleanupDialog)
- Planifié (ex: hebdomadaire)
- Sur seuil (ex: >10 000 entrées)

#### Calcul des statistiques

```dart
Future<TmStatistics> getStatistics() async {
  final stats = await _repository.getStatistics();
  final entriesByLang = await _repository.getEntriesByLanguage();

  return TmStatistics(
    totalEntries: stats['count'] ?? 0,
    entriesByLanguagePair: entriesByLang,
    averageQuality: stats['avg_quality'] ?? 0.0,
    totalReuseCount: stats['total_usage'] ?? 0,
    tokensSaved: (stats['total_usage'] ?? 0) * 50,  // ~50 tokens/réutilisation
    reuseRate: _calculateReuseRate(),
  );
}
```

**Métriques clés** :
- **Total entries** : Nombre d'entrées dans TM
- **Entries by language pair** : Distribution par paire de langues
- **Average quality** : Score moyen de qualité
- **Total reuse count** : Somme de tous les usage_count
- **Tokens saved** : Estimation (usage_count × 50)
- **Reuse rate** : % traductions TM vs LLM (période récente)

---

## 6. Exemple concret de bout en bout

### Scénario : Traduire "Hello world" du mod Total War 3

#### Première traduction (création)

```
1. Contexte initial
   - Aucune entrée TM pour "Hello world"
   - Langue source : Anglais (en)
   - Langue cible : Français (fr)
   - Game context : "Total War 3"

2. Processus de traduction
   User lance traduction → findBestMatch()
   ↓
   findExactMatch() → Aucun résultat
   ↓
   findFuzzyMatches() → Aucun résultat (TM vide)
   ↓
   Appel LLM (ChatGPT)
   Input: "Translate 'Hello world' to French"
   Output: "Bonjour monde"
   Tokens utilisés: ~50

3. Ajout à TM
   addTranslation(
     sourceText: "Hello world",
     sourceLanguageId: "uuid-en",
     targetLanguageId: "uuid-fr",
     translatedText: "Bonjour monde",
     gameContext: "Total War 3",
     translationProviderId: "chatgpt-uuid",
     qualityScore: 0.8  // Score initial par défaut
   )
   ↓
   Calcul hash: SHA-256("hello world") = "5eb63bbb..."
   ↓
   INSERT INTO translation_memory VALUES (
     'tm-uuid-001',
     'Hello world',
     '5eb63bbb...',
     'uuid-en',
     'uuid-fr',
     'Bonjour monde',
     'Total War 3',
     'chatgpt-uuid',
     0.8,
     1,
     1234567890,
     1234567890,
     1234567890
   )

4. Résultat
   - TM contient 1 entrée
   - Coût : 50 tokens LLM
```

#### Deuxième occurrence (match exact)

```
1. Nouvelle traduction demandée
   - Texte : "Hello world" (exactement identique)
   - Langue cible : Français (fr)
   - Game context : "Total War 3"

2. Recherche de correspondance
   findBestMatch() → findExactMatch()
   ↓
   Normalisation: "Hello world" → "hello world"
   Hash: SHA-256("hello world") = "5eb63bbb..."
   ↓
   Cache lookup: "5eb63bbb...:uuid-fr" → MISS
   ↓
   Query DB:
   SELECT * FROM translation_memory
   WHERE source_hash = '5eb63bbb...'
   AND target_language_id = 'uuid-fr'
   AND game_context = 'Total War 3'
   ↓
   RÉSULTAT TROUVÉ (0.5ms avec index)
   ↓
   Création TmMatch:
   {
     entryId: 'tm-uuid-001',
     sourceText: 'Hello world',
     targetText: 'Bonjour monde',
     similarityScore: 1.0,
     matchType: TmMatchType.exact,
     autoApplied: true,  // >95%
     qualityScore: 0.8,
     usageCount: 1
   }

3. Application automatique
   Traduction appliquée automatiquement (>95%)
   ↓
   INSERT INTO translation_version_tm_usage VALUES (
     'usage-uuid-001',
     'translation-version-uuid',
     'tm-uuid-001',
     1.0,
     1234567950
   )
   ↓
   UPDATE translation_memory
   SET usage_count = 2,
       last_used_at = 1234567950
   WHERE id = 'tm-uuid-001'
   ↓
   Cache mis à jour: "5eb63bbb...:uuid-fr" → TmEntry

4. Résultat
   - TM contient 1 entrée (usage_count=2)
   - Coût : 0 token LLM (100% économie)
   - Temps : <1ms vs ~2000ms pour LLM
```

#### Troisième occurrence (variante fuzzy)

```
1. Nouvelle traduction demandée
   - Texte : "Hello wonderful world"
   - Langue cible : Français (fr)
   - Game context : "Total War 3"

2. Recherche de correspondance
   findBestMatch() → findExactMatch()
   ↓
   Hash: SHA-256("hello wonderful world") = "9ab45def..."
   ↓
   Query DB: Aucun résultat (hash différent)
   ↓
   findFuzzyMatches()
   ↓
   Récupération candidats:
   SELECT * FROM translation_memory
   WHERE target_language_id = 'uuid-fr'
   AND game_context = 'Total War 3'
   → 1 candidat trouvé: "Hello world"

3. Calcul similarité pour "Hello world"
   source1: "hello wonderful world"
   source2: "hello world"
   ↓
   a. Levenshtein (40%)
      Distance: 10 caractères différents
      Longueur max: 21
      Score: 1 - (10/21) = 0.524
      Pondéré: 0.524 × 0.4 = 0.210
   ↓
   b. Jaro-Winkler (30%)
      Calcul: jaro_winkler("hello wonderful world", "hello world")
      Score: 0.867
      Pondéré: 0.867 × 0.3 = 0.260
   ↓
   c. Token-based (30%)
      Tokens1: ["hello", "wonderful", "world"]
      Tokens2: ["hello", "world"]
      Intersection: ["hello", "world"] (2)
      Union: ["hello", "wonderful", "world"] (3)
      Score: 2/3 = 0.667
      Pondéré: 0.667 × 0.3 = 0.200
   ↓
   d. Score de base
      0.210 + 0.260 + 0.200 = 0.670
   ↓
   e. Bonus contextuel
      Game context identique: +0.05
      Score final: 0.670 + 0.05 = 0.720
   ↓
   Résultat: 72% < seuil 85% → REJETÉ

4. Aucun match utilisable
   Appel LLM pour "Hello wonderful world"
   Output: "Bonjour monde merveilleux"
   Tokens: ~55
   ↓
   Ajout nouvelle entrée TM:
   {
     sourceText: "Hello wonderful world",
     sourceHash: "9ab45def...",
     translatedText: "Bonjour monde merveilleux",
     qualityScore: 0.8,
     usageCount: 1,
     gameContext: "Total War 3"
   }

5. Résultat
   - TM contient 2 entrées
   - Coût : 55 tokens LLM (match fuzzy insuffisant)
```

#### Quatrième occurrence (variante fuzzy acceptée)

```
1. Nouvelle traduction demandée
   - Texte : "Hello worlds"
   - Langue cible : Français (fr)
   - Game context : "Total War 3"

2. Recherche fuzzy
   Candidats: "Hello world", "Hello wonderful world"
   ↓
   Calcul pour "Hello world":
   ├─ Levenshtein: 0.917 (1 char différent)
   ├─ Jaro-Winkler: 0.967
   ├─ Token: 0.667 (tokens différents)
   ├─ Base: (0.917×0.4)+(0.967×0.3)+(0.667×0.3) = 0.857
   └─ Final: 0.857 + 0.05 = 0.907 (90.7%)
   ↓
   Calcul pour "Hello wonderful world":
   └─ Score: ~0.75 (trop bas)
   ↓
   Meilleur match: "Hello world" (90.7%)

3. Présentation à l'utilisateur
   TmMatch proposé:
   {
     sourceText: 'Hello world',
     targetText: 'Bonjour monde',
     similarityScore: 0.907,
     matchType: fuzzy,
     autoApplied: false,  // <95%
     breakdown: {
       levenshteinScore: 0.917,
       jaroWinklerScore: 0.967,
       tokenScore: 0.667,
       contextBoost: 0.05
     }
   }
   ↓
   UI affiche:
   "Match TM trouvé (90.7%): 'Bonjour monde'"
   [Accepter] [Modifier] [Rejeter]

4. Utilisateur accepte
   Application traduction: "Bonjour monde"
   ↓
   UPDATE translation_memory
   SET usage_count = 3, last_used_at = NOW()
   WHERE id = 'tm-uuid-001'
   ↓
   INSERT INTO translation_version_tm_usage...

5. Résultat
   - TM: 2 entrées ("Hello world" usage_count=3)
   - Coût : 0 token LLM (match fuzzy accepté)
   - Qualité préservée (90.7% très bon)
```

#### Après 6 mois : Cleanup

```
1. État de la TM
   - Entrée 1: "Hello world"
     • usage_count: 42
     • quality_score: 0.92 (amélioré par feedback)
     • last_used_at: Il y a 2 jours

   - Entrée 2: "Hello wonderful world"
     • usage_count: 1
     • quality_score: 0.65 (dégradé par corrections)
     • last_used_at: Il y a 400 jours

2. Exécution cleanup
   cleanupLowQualityEntries(
     minQuality: 0.7,
     maxDaysSinceLastUse: 365
   )
   ↓
   Query:
   DELETE FROM translation_memory
   WHERE quality_score < 0.7
   AND last_used_at < (NOW() - 365 days)
   ↓
   Entrée 2 supprimée (qualité 0.65 ET non utilisé depuis 400j)

3. Résultat final
   - TM contient 1 entrée de haute qualité
   - Tokens économisés: 42 × 50 = 2100 tokens
   - Coût évité: ~$0.06 (avec GPT-4)
```

---

## 7. Optimisations de performance

### Tableau récapitulatif

| Technique | Impact | Cas d'usage | Avant | Après |
|-----------|--------|-------------|-------|-------|
| **Hash indexing** | 100-800x | Match exact | Full scan 500ms | Index lookup 0.5ms |
| **Cache mémoire** | 10-100x | Recherches répétées | DB query 5ms | Memory read 0.05ms |
| **Index composites** | 50-200x | Filtres multiples | Multiple scans 200ms | Single lookup 2ms |
| **FTS5** (prévu) | 100-1000x | Recherche texte | LIKE query 2000ms | FTS5 BM25 5ms |
| **Pagination** | ∞ | Grandes listes | Load 10k rows 5s | Load 50 rows 50ms |

### Détail des optimisations

#### 1. Hash indexing

**Problème** : Recherche exacte nécessitait scan complet
```sql
-- AVANT (sans index)
SELECT * FROM translation_memory
WHERE source_text = 'Hello world'
AND target_language_id = 'uuid-fr';
-- Scan complet: O(n) → 500ms pour 10k entrées
```

**Solution** : Index sur hash pré-calculé
```sql
-- APRÈS (avec index)
SELECT * FROM translation_memory
WHERE source_hash = '5eb63bbb...'
AND target_language_id = 'uuid-fr';
-- B-tree lookup: O(log n) → 0.5ms
```

**Gain** : 1000x pour 10k entrées, 800x pour 100k

#### 2. Cache mémoire

**Implémentation** :
```dart
class TmCache {
  final Map<String, TranslationMemoryEntry> _cache = {};

  String _buildKey(String hash, String langCode)
    => '$hash:$langCode';

  TranslationMemoryEntry? get(String hash, String langCode) {
    final key = _buildKey(hash, langCode);
    return _cache[key];
  }

  void put(String hash, String langCode, TranslationMemoryEntry entry) {
    final key = _buildKey(hash, langCode);
    _cache[key] = entry;
  }

  void invalidate(String hash, String langCode) {
    final key = _buildKey(hash, langCode);
    _cache.remove(key);
  }
}
```

**Scénarios gagnants** :
- Traduction de textes répétitifs (menus, UI)
- Batch processing du même mod
- Re-traduction après corrections

**Exemple** :
```
Traduction de 100 instances de "Save" :
- Sans cache : 100 × 5ms = 500ms
- Avec cache : 1 × 5ms + 99 × 0.05ms = ~10ms
- Gain : 50x
```

#### 3. Index composites

**Cas d'usage** : Filtres UI combinés

```sql
-- Requête typique de l'UI
SELECT * FROM translation_memory
WHERE target_language_id = 'uuid-fr'
AND game_context = 'Total War 3'
AND quality_score > 0.7
ORDER BY quality_score DESC
LIMIT 50 OFFSET 100;

-- Sans index composite : 3 scans séquentiels
-- 1. Scan par target_language_id → 5000 rows
-- 2. Filter game_context → 1000 rows
-- 3. Filter quality_score → 800 rows
-- 4. Sort → 800 rows
-- Temps: ~200ms

-- Avec index idx_tm_game_context(game_context, quality_score DESC)
-- 1. Direct index scan → 800 rows triées
-- 2. Filter target_language_id → négligeable (index rapide)
-- Temps: ~2ms

-- Gain: 100x
```

#### 4. FTS5 (Full-Text Search) - Prévu

**Problème actuel** : Recherche floue inefficace
```dart
// Méthode actuelle : TOUTES les entrées chargées en mémoire
Future<List<TmMatch>> findFuzzyMatches(String query) async {
  // 1. Récupère TOUS les candidats (10k+ entrées)
  final candidates = await _repository.findAll(
    targetLanguageId: langId
  );

  // 2. Calcule similarité pour CHACUNE (10k+ calculs)
  for (final candidate in candidates) {
    final score = _calculator.calculate(query, candidate.sourceText);
    if (score >= 0.85) matches.add(...);
  }

  // Temps: 500-5000ms selon taille TM
}
```

**Solution FTS5** : Pré-filtrage rapide
```dart
// Avec FTS5 : Filtrage initial par BM25
Future<List<TmMatch>> findFuzzyMatches(String query) async {
  // 1. FTS5 trouve top 100 candidats pertinents
  final candidates = await _repository.findFts5Matches(
    query: query,
    limit: 100
  ); // Temps: 5ms (index FTS5)

  // 2. Calcule similarité précise pour 100 entrées seulement
  for (final candidate in candidates) {
    final score = _calculator.calculate(query, candidate.sourceText);
    if (score >= 0.85) matches.add(...);
  }

  // Temps total: 5ms + 50ms = 55ms
}
```

**Gain** : 100-1000x selon taille TM

**Requête FTS5** :
```sql
-- Recherche BM25 avec ranking
SELECT
  tm.*,
  bm25(translation_memory_fts) as rank
FROM translation_memory_fts
JOIN translation_memory tm ON translation_memory_fts.id = tm.id
WHERE translation_memory_fts MATCH ?
ORDER BY rank
LIMIT 100;
```

#### 5. Pagination

**Sans pagination** : Charge toutes les entrées
```dart
// ❌ MAUVAIS : Charge 10k entrées
final allEntries = await _repository.getAll();
// Temps: 5000ms, Mémoire: 50MB
```

**Avec pagination** : Charge par pages
```dart
// ✅ BON : Charge 50 entrées à la fois
final page = await _repository.getEntries(
  limit: 50,
  offset: currentPage * 50
);
// Temps: 50ms, Mémoire: 250KB
```

**Requête SQL paginée** :
```sql
SELECT * FROM translation_memory
WHERE target_language_id = ?
ORDER BY quality_score DESC, usage_count DESC
LIMIT 50 OFFSET ?;
```

**Gain** : ∞ (permet de gérer TM illimitées)

---

## 8. Import/Export TMX

### Format TMX 1.4b

**TMX** = Translation Memory eXchange (standard industrie)

#### Structure XML

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tmx SYSTEM "tmx14.dtd">
<tmx version="1.4">
  <header
    creationtool="TWMT"
    creationtoolversion="1.0.0"
    srclang="en"
    adminlang="en"
    datatype="plaintext"
    o-tmf="TWMT TMX"
    segtype="sentence"
    creationdate="20250115T143022Z"
  />
  <body>
    <!-- Translation Unit 1 -->
    <tu tuid="tm-uuid-001" creationdate="20250115T143022Z" changedate="20250120T091545Z">
      <!-- Source language -->
      <tuv xml:lang="en">
        <seg>Hello world</seg>
      </tuv>
      <!-- Target language -->
      <tuv xml:lang="fr">
        <seg>Bonjour monde</seg>
      </tuv>
      <!-- Custom TWMT properties -->
      <prop type="x-quality-score">0.95</prop>
      <prop type="x-usage-count">42</prop>
      <prop type="x-game-context">Total War 3</prop>
      <prop type="x-translation-provider">ChatGPT-4</prop>
    </tu>

    <!-- Translation Unit 2 -->
    <tu tuid="tm-uuid-002">
      <tuv xml:lang="en"><seg>Save game</seg></tuv>
      <tuv xml:lang="fr"><seg>Sauvegarder la partie</seg></tuv>
      <prop type="x-quality-score">0.88</prop>
      <prop type="x-usage-count">15</prop>
      <prop type="x-game-context">Total War 3</prop>
    </tu>
  </body>
</tmx>
```

#### Éléments clés

| Élément | Description | Exemple |
|---------|-------------|---------|
| `<tmx>` | Root element | `version="1.4"` |
| `<header>` | Métadonnées globales | Tool, langues, dates |
| `<body>` | Contenu TM | Liste des TUs |
| `<tu>` | Translation Unit | Une paire source/cible |
| `<tuv>` | Translation Unit Variant | Version linguistique |
| `<seg>` | Segment | Texte réel |
| `<prop>` | Property | Métadonnée custom |

#### Propriétés TWMT

| Propriété | Type | Description |
|-----------|------|-------------|
| `x-quality-score` | REAL | Score qualité 0.0-1.0 |
| `x-usage-count` | INTEGER | Nombre réutilisations |
| `x-game-context` | TEXT | Contexte jeu/mod |
| `x-translation-provider` | TEXT | Fournisseur traduction |

### Export TMX

#### Interface

```dart
Future<void> exportToTmx({
  required String filePath,
  String? targetLanguageId,
  double? minQuality,
  String? gameContext,
  void Function(int processed, int total)? onProgress,
});
```

#### Processus

```
1. Récupérer entrées avec filtres
   final entries = await _repository.getWithFilters(
     targetLanguageId: targetLanguageId,
     minQuality: minQuality,
     gameContext: gameContext,
   );
   // Ex: 1000 entrées filtrées

2. Initialiser XML
   final xml = XmlDocument([
     XmlElement(XmlName('tmx'), [
       XmlAttribute(XmlName('version'), '1.4')
     ], [
       _buildHeader(),
       _buildBody(entries, onProgress)
     ])
   ]);

3. Pour chaque entrée (avec callback progress)
   for (int i = 0; i < entries.length; i++) {
     final entry = entries[i];

     // Créer Translation Unit
     final tu = XmlElement(XmlName('tu'), [
       XmlAttribute(XmlName('tuid'), entry.id)
     ], [
       // Source TUV
       XmlElement(XmlName('tuv'), [
         XmlAttribute(XmlName('xml:lang'), entry.sourceLanguageCode)
       ], [
         XmlElement(XmlName('seg'), [], [XmlText(entry.sourceText)])
       ]),

       // Target TUV
       XmlElement(XmlName('tuv'), [
         XmlAttribute(XmlName('xml:lang'), entry.targetLanguageCode)
       ], [
         XmlElement(XmlName('seg'), [], [XmlText(entry.translatedText)])
       ]),

       // Properties
       _buildProperty('x-quality-score', entry.qualityScore.toString()),
       _buildProperty('x-usage-count', entry.usageCount.toString()),
       if (entry.gameContext != null)
         _buildProperty('x-game-context', entry.gameContext!),
     ]);

     // Callback progress
     onProgress?.call(i + 1, entries.length);
   }

4. Écrire fichier
   final file = File(filePath);
   await file.writeAsString(xml.toXmlString(pretty: true, indent: '  '));
```

#### Cas d'usage export

**1. Sauvegarde complète**
```dart
await tmService.exportToTmx(
  filePath: 'E:/backups/twmt_tm_full_2025-01-15.tmx',
);
// Exporte TOUTE la TM
```

**2. Export par jeu**
```dart
await tmService.exportToTmx(
  filePath: 'E:/exports/tw3_tm.tmx',
  gameContext: 'Total War 3',
);
// Exporte seulement TW3
```

**3. Export haute qualité**
```dart
await tmService.exportToTmx(
  filePath: 'E:/exports/high_quality_tm.tmx',
  minQuality: 0.8,
);
// Exporte seulement qualité ≥ 80%
```

**4. Export pour partage avec autre traducteur**
```dart
await tmService.exportToTmx(
  filePath: 'E:/share/french_tm.tmx',
  targetLanguageId: 'uuid-fr',
  minQuality: 0.7,
  onProgress: (processed, total) {
    print('Export: $processed/$total (${(processed/total*100).toStringAsFixed(1)}%)');
  },
);
```

### Import TMX

#### Interface

```dart
Future<void> importFromTmx({
  required String filePath,
  bool overwriteExisting = false,
  bool validateEntries = true,
  void Function(int processed, int total)? onProgress,
});
```

#### Processus

```
1. Lire et parser fichier XML
   final file = File(filePath);
   final xmlString = await file.readAsString();
   final document = XmlDocument.parse(xmlString);

2. Valider structure TMX
   final tmxElement = document.findElements('tmx').first;
   if (tmxElement.getAttribute('version') != '1.4') {
     throw TmxException('Unsupported TMX version');
   }

3. Extraire header
   final header = document.findElements('header').first;
   final sourceLanguage = header.getAttribute('srclang');

4. Parser Translation Units
   final tus = document.findAllElements('tu');
   final totalUnits = tus.length;

   for (int i = 0; i < tus.length; i++) {
     final tu = tus.elementAt(i);

     try {
       // Extraire TUVs (source + target)
       final tuvs = tu.findElements('tuv');
       if (tuvs.length < 2) continue;

       final sourceTuv = tuvs.first;
       final targetTuv = tuvs.last;

       final sourceText = sourceTuv.findElements('seg').first.innerText;
       final targetText = targetTuv.findElements('seg').first.innerText;
       final sourceLang = sourceTuv.getAttribute('xml:lang');
       final targetLang = targetTuv.getAttribute('xml:lang');

       // Extraire propriétés TWMT
       final props = tu.findElements('prop');
       double? qualityScore;
       int? usageCount;
       String? gameContext;

       for (final prop in props) {
         final type = prop.getAttribute('type');
         final value = prop.innerText;

         switch (type) {
           case 'x-quality-score':
             qualityScore = double.tryParse(value);
             break;
           case 'x-usage-count':
             usageCount = int.tryParse(value);
             break;
           case 'x-game-context':
             gameContext = value;
             break;
         }
       }

       // Valider si nécessaire
       if (validateEntries) {
         if (sourceText.isEmpty || targetText.isEmpty) continue;
         if (qualityScore != null && (qualityScore < 0 || qualityScore > 1)) {
           qualityScore = null;
         }
       }

       // Vérifier si existe déjà
       final sourceHash = _calculateHash(sourceText);
       final existing = await _repository.findByHash(
         sourceHash: sourceHash,
         targetLanguageId: _getLanguageId(targetLang),
         gameContext: gameContext,
       );

       if (existing != null && !overwriteExisting) {
         // Skip ou merge
         if (usageCount != null) {
           await _repository.updateUsageCount(
             existing.id,
             existing.usageCount + usageCount,
           );
         }
       } else {
         // Créer ou écraser
         await _repository.create(TranslationMemoryEntry(
           id: uuid.v4(),
           sourceText: sourceText,
           sourceHash: sourceHash,
           sourceLanguageId: _getLanguageId(sourceLang),
           targetLanguageId: _getLanguageId(targetLang),
           translatedText: targetText,
           gameContext: gameContext,
           qualityScore: qualityScore ?? 0.8,
           usageCount: usageCount ?? 1,
           createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
           lastUsedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
           updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
         ));
       }

       // Callback progress
       onProgress?.call(i + 1, totalUnits);

     } catch (e) {
       // Log erreur mais continue
       print('Error importing TU ${i+1}: $e');
     }
   }

5. Invalider cache
   await _cache.clear();

6. Retourner statistiques
   return ImportResult(
     totalProcessed: totalUnits,
     imported: importedCount,
     skipped: skippedCount,
     errors: errorCount,
   );
```

#### Gestion des conflits

| Scénario | overwriteExisting=false | overwriteExisting=true |
|----------|-------------------------|------------------------|
| Entrée n'existe pas | Créer nouvelle | Créer nouvelle |
| Entrée existe, même traduction | Skip | Mettre à jour metadata |
| Entrée existe, traduction différente | Skip | Écraser avec import |
| Entrée existe, quality différente | Garder max(existing, import) | Utiliser quality import |
| Entrée existe, usage différent | Additionner usage_count | Additionner usage_count |

#### Cas d'usage import

**1. Import initial**
```dart
await tmService.importFromTmx(
  filePath: 'E:/imports/memoq_export.tmx',
  overwriteExisting: false,
  validateEntries: true,
);
// Import TM d'un autre outil CAT
```

**2. Merge avec TM existante**
```dart
await tmService.importFromTmx(
  filePath: 'E:/imports/colleague_tm.tmx',
  overwriteExisting: false,  // Préserve entrées existantes
  onProgress: (p, t) => print('Merge: $p/$t'),
);
// Fusionne TM d'un collègue
```

**3. Restauration backup**
```dart
await tmService.importFromTmx(
  filePath: 'E:/backups/twmt_tm_2025-01-01.tmx',
  overwriteExisting: true,  // Restaure état complet
);
// Restaure depuis sauvegarde
```

### Compatibilité

| Outil CAT | Export vers TWMT | Import depuis TWMT | Notes |
|-----------|------------------|---------------------|-------|
| **SDL Trados** | ✅ Oui | ✅ Oui | TMX 1.4b standard |
| **memoQ** | ✅ Oui | ✅ Oui | Propriétés custom ignorées |
| **Wordfast** | ✅ Oui | ✅ Oui | TMX 1.4b natif |
| **OmegaT** | ✅ Oui | ✅ Oui | Open source |
| **MateCat** | ✅ Oui | ⚠️ Partiel | Web-based, limitations |
| **Smartcat** | ✅ Oui | ✅ Oui | Cloud TM support |

**Propriétés custom** (`x-*`) :
- Préservées lors export/import TWMT ↔ TWMT
- Ignorées par autres outils (pas d'erreur)
- Perdues lors round-trip vers autre outil

---

## 9. Chemins des fichiers clés

### Interface utilisateur

```
lib/features/translation_memory/
├── screens/
│   └── translation_memory_screen.dart          # Écran principal
├── widgets/
│   ├── tm_browser_data_grid.dart               # Grille Syncfusion
│   ├── tm_statistics_panel.dart                # Panneau statistiques
│   ├── tm_filter_panel.dart                    # Filtres
│   ├── tm_search_bar.dart                      # Recherche
│   ├── tm_pagination_bar.dart                  # Pagination
│   ├── tm_import_dialog.dart                   # Dialogue import TMX
│   ├── tm_export_dialog.dart                   # Dialogue export TMX
│   └── tm_cleanup_dialog.dart                  # Dialogue nettoyage
└── providers/
    └── tm_providers.dart                       # Providers Riverpod
```

### Modèles de données

```
lib/models/domain/
├── translation_memory_entry.dart               # Modèle principal
├── tm_match.dart                               # Résultat correspondance
├── tm_statistics.dart                          # Statistiques agrégées
├── similarity_breakdown.dart                   # Détail scoring
└── score_weights.dart                          # Poids algorithmes
```

### Services

```
lib/services/translation_memory/
├── i_translation_memory_service.dart           # Interface service
├── translation_memory_service_impl.dart        # Implémentation
├── tm_matching_service.dart                    # Logique matching
├── similarity_calculator.dart                  # Calculs similarité
├── text_normalizer.dart                        # Normalisation texte
├── tm_cache.dart                               # Cache en mémoire
├── tmx_service.dart                            # Support TMX
└── tm_import_export_service.dart               # Orchestration I/O
```

### Données

```
lib/repositories/
└── translation_memory_repository.dart          # Accès base de données

lib/database/
└── schema.sql                                  # Ligne 245 : table TM
```

---

## 10. Points clés à retenir

### Avantages

1. **Économie de coûts** 💰
   - Évite re-traduction → économise tokens LLM
   - Réduction de 30-70% des coûts selon taux de répétition
   - ROI positif dès 100 traductions répétées

2. **Match intelligent** 🧠
   - Exact (hash) : 100% précision, 0.5ms
   - Fuzzy (3 algorithmes) : 85-99% similarité, 50-500ms
   - Contexte-aware : +5% bonus si même jeu

3. **Auto-apply** ⚡
   - Correspondances >95% appliquées automatiquement
   - Zéro intervention utilisateur
   - Gain de temps massif sur textes répétitifs

4. **Qualité contrôlée** ✅
   - Score de qualité 0.0-1.0
   - Nettoyage automatique entrées basses qualité
   - Feedback utilisateur améliore scores

5. **Standard TMX** 🌐
   - Interopérable avec Trados, memoQ, Wordfast, etc.
   - Export/import sans perte
   - Collaboration entre outils

6. **Performance** 🚀
   - Index + cache → recherches ultra-rapides
   - Hash indexing : 100-800x amélioration
   - Gère 10k+ entrées sans ralentissement

7. **UI Fluent Design** 🎨
   - DataGrid éditable natif Windows
   - Statistiques temps réel
   - Filtres et recherche avancés

### Limites

1. **Fuzzy matching lent** ⏱️
   - Calculs intensifs sur grandes TM (>10k entrées)
   - FTS5 prévu pour résoudre (100-1000x gain)

2. **Contexte limité** 📝
   - Matching phrase par phrase (pas de contexte document)
   - Amélioration future : context-aware matching avec phrases adjacentes

3. **Qualité initiale** ⚠️
   - Score initial 0.8 arbitraire
   - Nécessite feedback utilisateur pour calibration
   - Amélioration future : scoring ML basé historique

4. **Pas de sous-segments** 🧩
   - Match phrase complète uniquement
   - Pas de réutilisation partielle (ex: "Save the game" vs "Save")
   - Amélioration future : sub-segment matching

### Métriques de succès

| Métrique | Bon | Excellent |
|----------|-----|-----------|
| **Taux de réutilisation** | 30-50% | >70% |
| **Qualité moyenne** | 0.7-0.8 | >0.85 |
| **Tokens économisés/jour** | 1000-5000 | >10000 |
| **Temps match exact** | <2ms | <0.5ms |
| **Temps match fuzzy** | <500ms | <100ms |
| **Taux auto-apply** | 20-40% | >50% |

### Workflow recommandé

1. **Phase initiale** (0-1000 traductions)
   - Importer TM existantes si disponibles
   - Valider qualité traductions manuellement
   - Ajuster seuils (minQuality, fuzzyThreshold)

2. **Phase croissance** (1000-10000 traductions)
   - Monitoring taux de réutilisation
   - Cleanup régulier (mensuel)
   - Export backups hebdomadaires

3. **Phase mature** (>10000 traductions)
   - Taux réutilisation >50%
   - Cleanup automatisé
   - Optimisation FTS5 activée
   - Partage TM entre projets similaires

### Cas d'usage idéaux

✅ **Excellent pour** :
- Traduction de mods de jeux (répétitions élevées)
- Menus et UI (textes identiques)
- Documentation technique (terminologie consistante)
- Séries de jeux (TW3, TW4 partagent vocabulaire)

⚠️ **Moins efficace pour** :
- Narration unique (dialogues jamais répétés)
- Textes créatifs (poésie, descriptions variées)
- Langage très contextuel (sarcasme, jeux de mots)

---

## Glossaire

| Terme | Définition |
|-------|------------|
| **TM** | Translation Memory - Base de données de traductions |
| **TU** | Translation Unit - Paire source/cible dans TMX |
| **TUV** | Translation Unit Variant - Version linguistique d'une TU |
| **TMX** | Translation Memory eXchange - Format XML standard |
| **FTS5** | Full-Text Search 5 - Module SQLite pour recherche texte |
| **BM25** | Best Match 25 - Algorithme de ranking textuel |
| **Hash** | Empreinte cryptographique unique d'un texte |
| **Fuzzy match** | Correspondance approximative (85-99% similarité) |
| **Exact match** | Correspondance exacte (100% similarité) |
| **Auto-apply** | Application automatique sans validation utilisateur |
| **Quality score** | Score de qualité 0.0-1.0 d'une traduction |
| **Usage count** | Nombre de fois qu'une traduction a été réutilisée |
| **Context boost** | Bonus de similarité pour contexte identique |
| **Levenshtein** | Algorithme de distance d'édition |
| **Jaro-Winkler** | Algorithme de similarité de chaînes |
| **Token-based** | Comparaison basée sur ensembles de mots |
| **CAT** | Computer-Assisted Translation - Outil de TAO |

---

## Ressources

### Documentation externe

- **TMX 1.4b Specification** : https://www.gala-global.org/tmx-14b
- **SQLite FTS5** : https://www.sqlite.org/fts5.html
- **Levenshtein Distance** : https://en.wikipedia.org/wiki/Levenshtein_distance
- **Jaro-Winkler** : https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance
- **BM25** : https://en.wikipedia.org/wiki/Okapi_BM25

### Fichiers liés dans le projet

- **Architecture services** : `docs/architecture_services.md`
- **Schéma database** : `docs/database_schema.md`
- **Guide utilisateur** : `docs/user_guide.md`
- **Specs complètes** : `docs/specs.md`

---

**Dernière mise à jour** : 2025-01-15
**Version** : 1.0.0
