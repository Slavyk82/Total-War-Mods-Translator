# Revue de code complète (v2) — Total War Mods Translator

Date : 2026-06-09

## Résumé exécutif

Cette seconde passe de revue indépendante de TWMT (Total War Mods Translator, application Windows desktop Flutter/Dart, ~237k lignes) a consolidé les constats de l'ensemble des shards (export de packs/RPFM, éditeur de traduction, import/export, mémoire de traduction, glossaires, base de données, recherche, intégration Steam, mods, historique, validation, infrastructure de concurrence). Après dédoublonnage et fusion des constats redondants entre shards, 39 défauts confirmés subsistent. Aucun défaut critique n'a survécu à la vérification cette fois ; le risque se concentre sur sept constats de sévérité Élevée touchant l'intégrité des données et la correction des fonctionnalités centrales.

Au-delà des constats individuels, plusieurs **thèmes récurrents** structurent la dette :

1. **Confusion millisecondes / secondes sur les colonnes `*_at`.** La convention du dépôt stocke des SECONDES Unix (`millisecondsSinceEpoch ~/ 1000`, triggers `strftime('%s','now')`), mais de multiples modules écrivent ou lisent des millisecondes : l'application en masse de la TM corrompt `created_at`/`updated_at` (Élevé), et le glossaire, la recherche (`_parseTimestamp`, filtres de date), `ConflictResolver` et `OptimisticLockManager` mélangent les unités (Faible à Moyen). Plusieurs de ces derniers sont latents (code dormant ou colonne non affichée) mais constituent un piège systémique.

2. **Divergence d'un même trigger/DDL recréé en ligne par les chemins batch.** `importBatch`/`upsertBatchOptimized` recréent `trg_update_project_language_progress` sans le bump `projects.updated_at`, dégradant durablement le trigger vivant (Élevé), tandis que d'autres méthodes batch passent par le helper partagé correct. Même racine que le back-fill d'image qui déclenche involontairement ce trigger (Moyen).

3. **Avalement d'erreurs transformant les échecs en succès silencieux.** Le repli `.loc` de `createPack` masque une perte partielle de fichiers, les handlers Accept/Reject/Edit ignorent le `Result` de `update`, `setProjects` est avalé puis « Compilation saved » est affiché, l'export saute des lignes sur erreur DB, et `markAsCurrent` est ignoré. Racine commune : ne pas distinguer « rien trouvé » d'« échec réel » et ne pas vérifier les `Result`.

4. **Tables/colonnes inexistantes derrière du code dormant.** `ConflictResolver`, `OptimisticLockManager`, `PessimisticLockManager` et `BatchIsolationManager` ciblent des tables (`conflict_resolutions`, `entry_locks`, `batch_entry_reservations`) ou une colonne (`version`) absentes du schéma. Tous enregistrés au locator mais jamais appelés : impact actuel nul, mais pièges runtime garantis dès câblage.

5. **État mutable partagé sur singletons et chemins d'annulation non scopés.** L'état `_isCancelled`/`_currentProcess` partagé sur `RpfmServiceImpl` (Moyen) et l'annulation de mise à jour de mod écrasée par un statut `completed`/`failed` (Moyen) partagent l'absence de jeton d'opération.

6. **Corruption silencieuse déclenchée par des actions utilisateur ciblées.** L'inspecteur ressuscite une traduction effacée au changement de sélection (Élevé), l'auto-fix des doubles espaces écrase les retours à la ligne (Moyen), la détection `modifiedNumbers` corrompt les numéros de version via son auto-fix (Moyen), et le cache d'exact-match TM contourne la garde anti-collision de normalisation (Élevé).

Chaque constat ci-dessous a survécu à une vérification adversariale par lecture directe du code, des sites d'appel et du schéma : plusieurs sévérités ont été ajustées à la baisse lorsque la vérification a révélé un chemin mort, un déclencheur irréaliste ou un impact surévalué, et les candidats dont une prémisse porteuse s'effondrait ont été écartés. `flutter analyze` était propre (0 problème) au moment de la revue ; aucun constat ne relève de ce que l'analyseur statique capterait déjà.

## Décompte par sévérité

| Sévérité | Nombre |
|----------|--------|
| Critique | 0 |
| Élevé | 7 |
| Moyen | 18 |
| Faible | 14 |

## Élevé

### Intégrité des données

### importBatch et upsertBatchOptimized recréent trg_update_project_language_progress sans le bump projects.updated_at, dégradant le trigger pour toute la session DB

fichier `lib/repositories/mixins/translation_version_batch_mixin.dart:369-387, 615-633` · catégorie data-integrity · confiance high

**Problème** : Pour les lots > 50 lignes, `importBatch` (import de `.pack`) et `upsertBatchOptimized` (application de la TM) suppriment `trg_update_project_language_progress` puis le recréent EN LIGNE. La copie en ligne omet le bloc final présent dans `schema.sql` (lignes 862-867) : `UPDATE projects SET updated_at = strftime('%s','now') WHERE id = (SELECT project_id FROM project_languages WHERE id = NEW.project_language_id)`. `CREATE TRIGGER` étant une modification de schéma persistée, le trigger vivant perd définitivement ce bump après le batch. C'est le bug que le commentaire de `clearBatch` (`translation_version_repository.dart:461-463`) décrit et que le helper partagé `_recreateTriggers` (`translation_version_repository.dart:916-941`) corrige ; `clearBatch`/`acceptBatch`/`rejectBatch`/`updateValidationBatch` utilisent le helper, mais `importBatch` et `upsertBatchOptimized` gardent la version cassée en ligne.

```dart
CREATE TRIGGER trg_update_project_language_progress
AFTER UPDATE ON translation_versions
WHEN NEW.status != OLD.status
BEGIN
  UPDATE project_languages SET progress_percent = (...), updated_at = strftime('%s','now')
  WHERE id = NEW.project_language_id;
  -- MANQUE : UPDATE projects SET updated_at = ... (présent dans schema.sql)
END
```

**Impact** : Après tout import de pack ou application de TM portant sur plus de 50 unités, le trigger vivant cesse de propager les éditions ligne à ligne vers `projects.updated_at` pour le reste de la session. Le filtre « Export outdated » de l'écran Projets ne détecte alors plus les modifications : l'utilisateur croit son projet à jour à l'export alors qu'il ne l'est pas. La dégradation est silencieuse et persiste au-delà de la session (la récupération à l'ouverture `_ensureCriticalTriggersExist` ne recrée un trigger que s'il est ABSENT, jamais s'il est cassé-mais-présent ; `_recreateTriggers` utilise `CREATE TRIGGER IF NOT EXISTS` et ne remplace donc pas le trigger amputé).

**Recommandation** : Remplacer les deux blocs de recréation en ligne par un appel au helper partagé `_recreateTriggers`, afin que le trigger recréé soit strictement identique à `schema.sql`. Idéalement, factoriser la définition du trigger en une source unique pour éviter de futures divergences.

### L'inspecteur ressuscite une traduction effacée/modifiée hors champ via le flush au changement de sélection

fichier `lib/features/translation_editor/widgets/editor_inspector_panel.dart:174-219` · catégorie data-integrity · confiance high

**Problème** : Pour une ligne unique sélectionnée, `_targetController` est lié à cette unité. Si la traduction de cette ligne est modifiée par un autre chemin pendant qu'elle reste sélectionnée — typiquement « Clear translation » (`GridActionsHandler.handleClear` -> `clearBatch`) — la base est mise à jour, `refreshProviders()` ré-émet les rows et le listener appelle `_rebindIfNeeded`. Comme `_boundUnitId == row.id` n'a pas changé, la resynchronisation n'a lieu QUE dans la branche `if (_boundUnitId != row.id)` ; le contrôleur conserve donc l'ancien texte. Au changement de sélection suivant, `_flushDirtyIfNeeded` compare ce texte obsolète au texte persisté (désormais vide), constate une différence et déclenche `widget.onSave(previousId, ancienTexte)`, réécrivant l'ancienne traduction par-dessus la valeur effacée.

```dart
void _flushDirtyIfNeeded(List<TranslationRow>? rows) {
  final previousPersisted = rows[prevIdx].translatedText ?? '';
  final currentText = unescapeFromDisplay(_targetController.text);
  if (currentText != previousPersisted) {
    widget.onSave(previousId, currentText); // réécrit l'ancien texte
  }
}
```

**Impact** : Perte/corruption silencieuse de données. Effacer (Clear) la traduction de la ligne actuellement ouverte dans l'inspecteur, puis cliquer sur une autre ligne, annule l'opération et restaure l'ancien texte sans avertissement, avec en prime une entrée TM et un historique parasites (`handleCellEdit` repasse `status` à `translated` et ré-ajoute l'entrée TM). Note : `handleAcceptTranslation` ne modifie pas le texte (aucune résurrection), et `handleRejectTranslation` sous le filtre `needsReview` fait sortir la ligne de la vue filtrée (`prevIdx < 0` court-circuite le flush) — le vecteur réellement non gardé est donc « Clear » sous une vue non filtrante.

**Recommandation** : Resynchroniser le contrôleur quand le texte persisté de l'unité liée change, même à id constant : dans `_rebindIfNeeded`, si `_boundUnitId == row.id` mais que `escapeForDisplay(row.translatedText)` diffère du contenu du contrôleur ET que le champ n'a pas le focus, mettre à jour le contrôleur. Alternativement, ne flusher que si le champ a réellement été édité par l'utilisateur (drapeau `dirty` positionné par `onChanged`) plutôt que de comparer aveuglément contrôleur vs persisté.

### La resync DeepL ignore les suppressions/éditions d'entrées : le glossaire DeepL garde des termes obsolètes

fichier `lib/repositories/glossary_repository.dart:551-578`, `lib/services/glossary/deepl_glossary_sync_service.dart:72-83` · catégorie data-integrity · confiance high

**Problème** : `doesMappingNeedResync` décide d'une resync uniquement via `MAX(updated_at) > mapping.syncedAt`. Or supprimer une entrée (`deleteEntry`/`deleteEntries`) ne touche aucun `updated_at` d'entrée sœur, et `_updateGlossaryEntryCount` est un no-op explicite. Éditer une entrée puis en supprimer une autre laisse `MAX(updated_at)` au maximum d'avant l'édition. Le mapping stocke pourtant `entryCount` au moment du sync (`deepl_glossary_sync_service.dart:147`) mais cette valeur n'est JAMAIS relue pour comparaison. `ensureGlossarySynced` réutilise alors l'ancien `deeplGlossaryId` et le glossaire côté DeepL conserve indéfiniment les termes supprimés. Aucun trigger SQLite n'existe sur `glossary_entries`.

```dart
final lastUpdated = result.first['last_updated'] as int;
return lastUpdated > mapping.syncedAt; // n'attrape pas les suppressions
```

**Impact** : Après suppression d'un terme dans TWMT, les traductions DeepL continuent d'appliquer le terme supprimé, produisant des traductions incohérentes avec le glossaire local — sans déclenchement automatique de resync hormis un `forceResync` manuel. Facteur atténuant : le problème est récupérable (réajouter n'importe quelle entrée bumpe `updated_at`) et ne concerne que les utilisateurs de la synchro DeepL.

**Recommandation** : Inclure les suppressions dans la détection : comparer le nombre d'entrées courant à `mapping.entryCount` (déjà persisté) en plus de `MAX(updated_at) > syncedAt`, ou marquer le glossaire « dirty » lors de tout delete/insert/update d'entrée. Renvoyer `needsResync=true` si `entryCount` diffère.

### deleteLanguage détruit la mémoire de traduction avant un échec FK glossaire (perte de données)

fichier `lib/features/settings/providers/language_settings_providers.dart:179-204` · catégorie data-integrity · confiance high

**Problème** : `deleteLanguage` pré-vérifie uniquement l'usage par les projets via `projectLanguageRepository.countByLanguageId` (FK `project_languages.language_id`, `ON DELETE RESTRICT`), puis supprime irréversiblement toutes les entrées TM via `tmRepository.deleteByLanguageId` (où `source_language_id` OU `target_language_id` correspond), et enfin appelle `repository.delete(languageId)`. Or la table `glossaries` possède aussi une FK RESTRICT vers `languages` (`target_language_id`, `schema.sql:287`), `PRAGMA foreign_keys = ON` étant actif. Cette référence n'est NI vérifiée NI nettoyée : un glossaire est provisionné quand la langue est ajoutée à un projet (`GlossaryAutoProvisioningService.provisionForProjectLanguage`), mais retirer la langue de tous les projets ne supprime PAS le glossaire (aucun cleanup dans `project_language_deletion_service`). Séquence : (1) créer une langue custom, (2) l'ajouter à un projet -> glossaire provisionné, (3) la retirer du projet -> `project_languages` vide mais glossaire persistant, (4) supprimer la langue -> `countByLanguageId == 0` donc la pré-vérif passe, `deleteByLanguageId` efface la TM, puis `repository.delete` échoue sur la FK du glossaire.

```dart
final usageResult = await projectLanguageRepository.countByLanguageId(languageId);
... // glossaires non vérifiés
final tmCleanupResult = await tmRepository.deleteByLanguageId(languageId); // TM détruite
final deleteResult = await repository.delete(languageId); // peut échouer sur FK glossaires
```

**Impact** : Le commentaire (lignes 179-183) garantit qu'un delete bloqué est un « true no-op », mais c'est faux : les entrées de TM (source ET cible) sont supprimées définitivement alors que la langue reste en base à cause du glossaire orphelin. Les deux opérations sont dans des `executeQuery` séparés, sans transaction ni rollback. L'utilisateur voit une erreur d'échec de suppression mais a déjà perdu sa TM.

**Recommandation** : Avant toute suppression de TM, vérifier aussi l'usage par les glossaires (compter les `glossaries` où `target_language_id = languageId`) et bloquer comme pour les projets ; OU englober `deleteByLanguageId` + `delete(language)` dans une seule transaction SQLite afin que l'échec FK annule la suppression de TM. La transaction est la solution robuste car elle couvre toute future FK RESTRICT non anticipée.

### Le cache d'exact-match TM contourne la garde anti-collision de normalisation et auto-applique une mauvaise traduction

fichier `lib/services/translation_memory/tm_matching_service.dart:105-214`, `lib/services/translation_memory/tm_cache.dart:183-188` · catégorie data-integrity · confiance high

**Problème** : La clé de cache d'exact-match est `<sourceHash>:<targetCode>` où `sourceHash` provient du normaliseur AGRESSIF (lowercase + suppression de markup + ponctuation). Des sources Total War distinctes comme `Attack`/`ATTACK`, ou ne différant que par du markup `[[col:...]]`, collisionnent donc sur la même clé. La garde anti-collision (lignes 130-197), qui re-vérifie l'égalité via `conservativeExactNormalize` et rétrograde un faux exact en fuzzy non-auto-appliqué, ne s'exécute QUE sur un cache miss. Sur un cache hit (lignes 111-114) le `TmMatch` mémorisé est renvoyé tel quel (`return Ok(cached)`) sans re-vérification contre le `sourceText` courant. Le `TmCache` est un singleton (factory `_instance`) et le provider est `keepAlive: true`, donc l'effet persiste sur la session.

```dart
final cached = _cache.getExactMatch(cacheKey);
if (cached != null) {
  return Ok(cached); // garde anti-collision (l.130-197) jamais réévaluée
}
```

**Impact** : Corruption de données de traduction. Exemple : lookup `Attack` (vrai exact) -> cache `autoApplied=true, matchType=exact` ; puis lookup `ATTACK` -> hit sur la même clé -> reçoit le match exact auto-appliqué pour `ATTACK`, écrit par `tm_lookup_handler` comme `status=translated`, `source=tmExact`, sans revue manuelle. La collision marche dans les deux sens (un vrai exact peut être rétrogradé en fuzzy non-appliqué). Le déclenchement exige que les deux formes soient interrogées dans la même session (plausible lors d'une passe de traduction en masse), l'effet est borné à une entrée TM, et la traduction reste sémantiquement liée (même lemme).

**Recommandation** : Inclure la distinction conservatrice dans la clé de cache (hacher aussi `conservativeExactNormalize(sourceText)`), OU re-exécuter la vérification `conservativeExactNormalize(sourceText) == conservativeExactNormalize(cached.sourceText)` sur un cache hit et rétrograder/recalculer si elle échoue. Ne jamais renvoyer un match exact mémorisé sans confronter le `sourceText` réellement demandé.

### Timestamps en millisecondes écrits dans created_at/updated_at lors de l'application en masse des correspondances TM

fichier `lib/services/translation/handlers/tm_lookup_handler.dart:368-387`, `lib/repositories/mixins/translation_version_batch_mixin.dart:269-294, 336-348` · catégorie data-integrity · confiance high

**Problème** : Dans le chemin de production `_applyTmMatchesBatch`, les `TranslationVersion` sont construites avec `createdAt`/`updatedAt = DateTime.now().millisecondsSinceEpoch` (millisecondes, SANS `~/ 1000`). `upsertBatchOptimized` écrit ensuite `toMap(entity)` directement (INSERT, ligne 285) ou ne préserve que `created_at` côté UPDATE (laissant `updated_at` en ms). Or partout ailleurs ces colonnes stockent des SECONDES Unix (`translation_version_repository.dart:367/489/601/707` utilisent `~/ 1000`, triggers `strftime('%s','now')`), et le même mixin documente explicitement (ligne 303) que des ms « pousseraient les timestamps ~1000x dans le futur et corrompraient le tri par récence ». La valeur ms erronée est aussi recopiée dans le cache via `version_updated_at = tv.updated_at` (ligne 342, et trigger `trg_update_cache_on_version_change`).

```dart
final now = DateTime.now().millisecondsSinceEpoch; // ligne 368 -> devrait être ~/ 1000
...
createdAt: now, updatedAt: now,
```

**Impact** : Les lignes `translation_versions` créées/mises à jour par l'application en masse de la TM obtiennent un `created_at`/`updated_at` ~1000x trop grand (an ~33000). Cela corrompt durablement le tri/filtre par récence (`ORDER BY created_at DESC`, `version_updated_at DESC`) et fausse `translation_view_cache.version_updated_at`. Le contenu de traduction lui-même reste correct ; seule la sémantique temporelle est corrompue. (Nuance : `CHECK(created_at <= updated_at)` n'existe PAS sur `translation_versions`, et `createdAt == updatedAt`, donc aucune violation de contrainte n'en résulte.)

**Recommandation** : Utiliser des secondes dans `_applyTmMatchesBatch` : `final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;` (idem pour le chemin déprécié `applyTmMatch`). Vérifier que `toMap` n'effectue aucune conversion et que toutes les fabriques de `TranslationVersion` alimentant le repository fournissent des secondes.

### Correction

### _updateProject crée une ModVersion factice et ne déclenche aucune détection/application de changements

fichier `lib/providers/mods/mod_update_provider.dart:228-272` · catégorie correctness · confiance high

**Problème** : Après le téléchargement du mod via SteamCMD, `_updateProject` insère une `ModVersion` avec un commentaire `// TODO: Implement change detection logic` (ligne 233), `versionString = DateTime.now().toIso8601String()` et `unitsAdded`/`unitsModified`/`unitsDeleted` tous à 0, puis la marque comme version courante. Aucun appel à `ModUpdateAnalysisService.analyzeChanges`/`addNewUnits`/`applyModifiedSourceTexts` n'est effectué (le vrai pipeline existe dans `project_analysis_handler.dart` mais appartient au chemin du scan Workshop, pas au bouton « Tout mettre à jour »). Le flux « Mettre à jour le mod » télécharge le nouveau pack mais n'applique AUCUNE modification aux unités/versions.

```dart
// TODO: Implement change detection logic
final newVersion = ModVersion(... versionString: DateTime.now().toIso8601String(), unitsAdded: 0, unitsModified: 0, unitsDeleted: 0, ...);
```

**Impact** : L'utilisateur lance une mise à jour depuis `ModUpdateDialog`, voit « Mis à jour vers la version X » (basé sur un timestamp ISO, pas une vraie version de mod), mais les nouvelles clés, textes sources modifiés et clés supprimées du pack téléchargé ne sont jamais répercutés en base. Les compteurs affichés (0/0/0) sont faux. La détection réelle ne se produit qu'au prochain scan Workshop, pas via ce bouton. Pas de corruption ni de crash, mais une fonctionnalité utilisateur centrale silencieusement non fonctionnelle avec feedback trompeur.

**Recommandation** : Brancher `_updateProject` sur `ProjectAnalysisHandler`/`ModUpdateAnalysisService` après le téléchargement (extraire le `packFilePath` téléchargé, appeler `analyzeChanges` puis les `apply`), et renseigner `unitsAdded/Modified/Deleted` et un `versionString` réel. À défaut, désactiver/masquer ce chemin pour ne pas afficher un succès trompeur.

## Moyen

### Intégrité des données

### importBatch met à jour updated_at de TOUS les project_languages (UPDATE sans clause WHERE)

fichier `lib/repositories/mixins/translation_version_batch_mixin.dart:598-610` · catégorie data-integrity · confiance high

**Problème** : Dans le chemin « triggers désactivés » d'`importBatch` (imports > 50 entrées), la reconstruction de progression exécute `UPDATE project_languages SET progress_percent = (...), updated_at = ?` SANS clause WHERE. La sous-requête corrélée recalcule `progress_percent` par ligne (donc correct), mais l'absence de WHERE écrit `updated_at = now` sur TOUTES les lignes de `project_languages` de la base. C'est incohérent avec la méthode sœur `upsertBatchOptimized` (lignes 352-365) qui scope avec `WHERE id = ?` (`projectLanguageId`, disponible dans le scope mais non passé ici), et avec le trigger qui ne touche que `NEW.project_language_id`.

```dart
await txn.rawUpdate('''
  UPDATE project_languages
  SET progress_percent = (... WHERE tv.project_language_id = project_languages.id ...),
  updated_at = ?
''', [now]); // <-- aucune clause WHERE : touche toutes les langues
```

**Impact** : Après un import de pack > 50 entrées dans un projet/langue, `updated_at` de toutes les langues de tous les autres projets est avancé à l'instant de l'import, corrompant le tri par récence, l'ordre « récemment édité » et le filtre « Export outdated » pour des projets non concernés, et provoquant une réécriture inutile de toute la table. `progress_percent` reste correct ; pas de perte de données ni de crash.

**Recommandation** : Ajouter une clause de portée comme dans `upsertBatchOptimized` : terminer la requête par `WHERE id = ?` avec `[now, projectLanguageId]` (`projectLanguageId` est déjà calculé plus haut dans la méthode).

### La fusion (merge) écrase la traduction importée par une chaîne vide existante

fichier `lib/features/import_export/services/import_executor.dart:345` · catégorie data-integrity · confiance high

**Problème** : Dans le chemin `ConflictResolution.merge`, le texte conservé est `existingVersion.translatedText ?? translatedText`. L'opérateur `??` ne se rabat sur la valeur importée que si l'existant est `null`, PAS s'il vaut la chaîne vide `''`. Or `clearBatch` remet `translated_text` à `''` (et `status` à `pending`) : `'' ?? translatedText` vaut `''`, donc la traduction importée est jetée. Le détecteur de conflits (`import_conflict_detector.dart:123-153`) signale un conflit dès qu'une version existe sans vérifier si elle est vide, donc le chemin merge est atteignable.

```dart
final mergedText = existingVersion.translatedText ?? translatedText;
```

**Impact** : Lors d'un import avec résolution « merge » sur une unité dont la traduction a été effacée (status pending, texte vide), la traduction importée est silencieusement perdue : la version reste vide. Pire, une entrée d'historique « Import merged » est enregistrée avec un texte vide, masquant la perte. Conditionné à une combinaison précise (version préalablement effacée + choix explicite « merge »).

**Recommandation** : Traiter la chaîne vide comme absence de valeur : `final mergedText = (existingVersion.translatedText?.isNotEmpty ?? false) ? existingVersion.translatedText : translatedText;` et n'enregistrer l'historique/le succès que si un contenu réel est conservé.

### Le back-fill d'image en lecture bombarde updated_at via le trigger et marque faussement le projet « Export outdated »

fichier `lib/features/projects/providers/projects_screen_providers.dart:558-573` · catégorie data-integrity · confiance high

**Problème** : Dans `_computeOne` (chemin de chargement de la liste des projets), quand l'image du mod est absente/périmée mais découverte sur disque, le code construit `updatedProject` avec `metadata: updatedMetadata.toJsonString()` et `updatedAt: project.updatedAt` (volontairement préservé) puis appelle `projectRepo.update(updatedProject)`. Or `trg_projects_updated_at` est déclaré `AFTER UPDATE OF ... metadata ... WHEN NEW.updated_at = OLD.updated_at` et exécute alors `UPDATE projects SET updated_at = strftime('%s','now')`. `metadata` étant une colonne surveillée, le back-fill remplit exactement la condition du trigger et bumpe `updated_at` à maintenant, défaisant l'intention du code.

```dart
final updatedProject = project.copyWith(
  metadata: updatedMetadata.toJsonString(),
  updatedAt: project.updatedAt, // préservé… mais le trigger sur metadata bumpe quand même
);
...
if (_imageBackfilledProjectIds.add(project.id)) {
  await projectRepo.update(updatedProject);
}
```

**Impact** : Le simple affichage de l'écran Projets repousse `projects.updated_at` à l'instant courant pour tout projet dont l'image vient d'être auto-découverte, sans édition utilisateur. `isModifiedSinceLastExport` renvoie alors true, affichant à tort le statut/filtre « Export outdated » et remontant le projet dans le tri « Date Modified ». Bornes : ne concerne que les projets déjà exportés au moins une fois (`lastPackExport != null`), et le back-fill ne se ré-exécute que si le fichier image persisté n'existe plus (garde `_imageBackfilledProjectIds` + vérification d'existence) — pas perpétuellement, mais la donnée corrompue reste persistée jusqu'au prochain export réel.

**Recommandation** : Ne pas faire passer le back-fill par un UPDATE touchant `metadata`, ou neutraliser le bump : ré-écrire `updated_at` à sa valeur d'origine dans la même transaction après l'`update`, déplacer l'URL d'image hors de `metadata` (colonne dédiée non surveillée), ou exclure ce write du trigger.

### Réactivation non atomique : un échec à l'étape 2 perd définitivement le statut needsReview

fichier `lib/services/mods/mod_update_analysis_service.dart:634-661` · catégorie data-integrity · confiance high

**Problème** : `reactivateObsoleteUnits` exécute deux écritures dans des transactions séparées (autocommit chacune). Étape 1 (`reactivateByKeys`) met `is_obsolete=0` ET `source_text=nouveau texte` dans la même requête. Étape 2 (`setNeedsReviewForUnitKeys`) passe les versions en `needsReview`. Si l'étape 2 échoue (ou crash entre les deux), l'unité est déjà réactivée avec le NOUVEAU `source_text` mais ses traductions gardent leur ancien statut. Au scan suivant, l'unité est active et `existingUnit.sourceText == packSourceText` (`analyzeChanges:158-164`), donc elle n'est plus classée ni `reactivated` ni `modified` : le passage en `needsReview` manqué n'est jamais rejoué.

```dart
final reactivateResult = await _unitRepository.reactivateByKeys(... sourceTextUpdates ...); // step1: is_obsolete=0 + source_text=new
final reviewResult = await _versionRepository.setNeedsReviewForUnitKeys(...); // step2 (séparé) - si échec, perte définitive
```

**Impact** : Des unités précédemment obsolètes, revenues dans le mod avec un texte source potentiellement différent, restent marquées `translated`/`approved` alors qu'elles devraient repasser en review. Le traducteur valide/exporte une traduction obsolète — corruption silencieuse non auto-réparable. Conditionné à un échec/crash spécifique sur l'étape 2 après commit de l'étape 1, sur des unités précisément réactivées (cas rare).

**Recommandation** : Envelopper les deux étapes dans une seule transaction (`DatabaseService.transaction`), soit inverser l'ordre pour reproduire l'auto-réparation de `applyModifiedSourceTexts` : mettre `needsReview` AVANT et `source_text` en dernier, afin qu'un échec laisse l'unité encore détectable au prochain scan.

### L'auto-fix des doubles espaces écrase les retours à la ligne et tabulations (corruption de contenu .loc)

fichier `lib/services/validation/translation_validation_service.dart:268-278` · catégorie data-integrity · confiance high

**Problème** : Le contrôle de doubles espaces se déclenche sur `translatedText.contains('  ')` (deux espaces littéraux), mais l'auto-fix appliqué est `translatedText.replaceAll(RegExp(r'\s+'), ' ')`. La classe `\s` couvre aussi `\n`, `\r`, `\t`. Donc si une chaîne contient à la fois un double espace ET des retours à la ligne légitimes, l'auto-fix remplace toutes les séquences de blancs (y compris `\n`) par un seul espace. L'existence de `lib/services/database/migrations/migration_fix_escaped_newlines.dart` confirme que les `\n` réels sont sémantiquement significatifs dans le contenu `.loc`.

```dart
if (translatedText.contains('  ')) { ... autoFixValue: translatedText.replaceAll(RegExp(r'\s+'), ' ') }
```

**Impact** : Les chaînes Total War multi-lignes (tooltips, descriptions) perdent leurs retours à la ligne lors d'un clic sur auto-fix, la traduction étant corrompue de façon invisible (collapse en une seule ligne). Nécessite une combinaison d'entrée spécifique (double espace + newline/tab) ET un geste utilisateur explicite (opt-in), d'où Moyen plutôt qu'Élevé.

**Recommandation** : Remplacer uniquement les espaces horizontaux multiples : `replaceAll(RegExp(r'[ \t]{2,}'), ' ')` (ou `RegExp(r' {2,}')`). Ne jamais inclure `\n`/`\r` dans le motif de normalisation des doubles espaces.

### Perte définitive d'une action undo/redo quand l'opération échoue (désync de la pile)

fichier `lib/services/history/undo_redo_manager.dart:172-207` · catégorie data-integrity · confiance high

**Problème** : Dans `undo()`, l'action est retirée par `_undoStack.removeLast()` AVANT `await action.undo()`. Si `undo()` lève (échec DB, version introuvable, base verrouillée), le bloc catch ne fait rien d'utile : la condition `_undoStack.isEmpty || _undoStack.last != _undoStack.last` est tautologiquement fausse (`x != x`), le commentaire « add it back » n'est jamais exécuté, puis `rethrow`. L'action dépilée n'est jamais réinsérée. Identique pour `redo()`. L'appelant (`editor_actions_undo_redo.dart`) attrape l'exception et n'affiche qu'un toast.

```dart
final action = _undoStack.removeLast();
await action.undo();   // si throw -> action perdue
_redoStack.add(action);
...
} catch (e) {
  if (_undoStack.isEmpty || _undoStack.last != _undoStack.last) { /* no-op */ }
  rethrow;
}
```

**Impact** : Après un échec d'undo, l'action disparaît de la pile : l'utilisateur voit « undo failed » mais ne peut plus jamais réessayer cet undo, alors que la modification DB n'a pas été annulée (l'update repository est atomique, donc l'état des données reste cohérent). Désynchronisation pile/contenu réel et perte silencieuse d'une étape d'historique d'édition.

**Recommandation** : Réinsérer l'action avant de propager l'erreur : `} catch (e) { _undoStack.add(action); rethrow; }` (et symétriquement `_redoStack.add(action)` dans `redo()`). Supprimer le code mort à condition tautologique.

### Correction

### Détection 'modifiedNumbers' en faux positif sur les numéros de version (ex: 1.0.0) → auto-fix corrompt la chaîne

fichier `lib/services/validation/translation_validation_service.dart:388-407, 456-472` · catégorie correctness · confiance medium

**Problème** : `_numberPattern = RegExp(r'\d+')` capture chaque groupe de chiffres séparément, donc une traduction `1.0.0` donne `["1","0","0"]` et une source `100` donne `["100"]`. La normalisation retire `.` et `,`, donc `1.0.0` devient `100` et `normalizedTranslated.contains("100")` est vrai. `_findFormattedNumber` construit alors le motif `1[\s ,.]?0[\s ,.]?0` qui capture `1.0.0` ; comme la version dépouillée vaut `100`, c'est signalé `modifiedNumbers` (severity error, `autoFixable=true`).

```dart
final separatorPattern = r'[\s  ,.]?'; final patternStr = number.split('').join(separatorPattern);
```

**Impact** : L'auto-fix `_fixModifiedNumbers` exécute `result.replaceAll('1.0.0', '100')`, transformant un numéro de version légitime en `100`. Reproduit : source « Requires patch 100 to run » + traduction « Necessite la version 1.0.0 » -> auto-fix produit « Necessite la version 100 ». Le cas du séparateur de milliers FR/DE (`1.000`) est aussi atteint. Déclenchement nécessitant une coïncidence (le nombre source ne doit pas apparaître littéralement dans la traduction), mais facilement reproductible, avec une corruption proposée comme correction « sûre ».

**Recommandation** : Restreindre la détection de reformatage aux vrais séparateurs de milliers (exiger des groupes de 3 chiffres, ex. `^\d{1,3}([\s.,]\d{3})+$`) et/ou n'autoriser que l'espace/espace insécable comme séparateur. Ancrer le match sur des frontières de mot pour éviter de capturer des sous-séquences.

### Filtres de date en millisecondes alors que la base stocke des secondes

fichier `lib/services/search/utils/fts_query_builder.dart:286-293, 341-345`, `lib/services/search/utils/regex_query_builder.dart:174-179`, `lib/services/search/utils/query_builder.dart:95-104` · catégorie correctness · confiance high

**Problème** : Les quatre builders construisent la clause de date avec `filter.minDate!.millisecondsSinceEpoch` / `maxDate!.millisecondsSinceEpoch`, alors que `created_at`/`updated_at` sont stockés en SECONDES Unix. La valeur ms est ~1000x plus grande que la valeur stockée.

```dart
final timestamp = filter.minDate!.millisecondsSinceEpoch; // devrait être ~/ 1000
conditions.add('$tablePrefix.created_at >= $timestamp');
```

**Impact** : Un filtre `minDate` compare `created_at >= 1717000000000` (ms) contre des valeurs ~`1717000000` (s) : aucune ligne ne passe (0 résultat) ; `maxDate` (`<=`) laisse tout passer. Le filtrage par plage de dates est cassé dans les 4 builders. Nuance : aucun appelant vivant ne renseigne actuellement `minDate`/`maxDate` (le champ est exposé par l'API publique `SearchFilter` mais non câblé en UI), d'où Moyen plutôt qu'Élevé.

**Recommandation** : Diviser par 1000 : `(filter.minDate!.millisecondsSinceEpoch ~/ 1000)` et `(filter.maxDate!.millisecondsSinceEpoch ~/ 1000)` dans chaque clause, conformément à la convention du dépôt.

### Filtre regex par langue référence une colonne inexistante (tv.language_code)

fichier `lib/services/search/utils/regex_query_builder.dart:169` · catégorie correctness · confiance high

**Problème** : `_buildFilterClause` émet `tv.language_code IN (...)` pour `filter.languageCodes`. Or `translation_versions` ne possède PAS de colonne `language_code` (`schema.sql:165-183` : la langue passe par `project_language_id -> project_languages -> languages`), et `buildRegexQuery` ne joint ni `project_languages` ni `languages`. Le builder FTS versions, lui, route correctement vers `l.code` via les jointures.

```dart
_addListFilter(conditions, filter.languageCodes, 'tv.language_code'); // colonne inexistante
```

**Impact** : Toute recherche regex (`searchWithRegex`) avec un filtre `languageCodes` non vide génère un SQL invalide -> `DatabaseException` « no such column: tv.language_code », remontée en `SearchDatabaseException`. Le filtrage regex par langue est entièrement non fonctionnel. Exposition plus étroite que « toute recherche regex » : la recherche regex est déjà dégradée (seuls les patterns littéraux passent, les métacaractères lèvent `UnsupportedError`).

**Recommandation** : Soit joindre `project_languages`/`languages` et filtrer sur `l.code` (comme `_buildVersionFilterClause` de `fts_query_builder`), soit retirer le filtre langue du chemin regex et le documenter. Ne pas référencer une colonne inexistante.

### La recherche par préfixe FTS5 (caval*) est silencieusement dégradée en terme exact

fichier `lib/services/search/utils/fts_query_builder.dart:449`, `lib/services/search/utils/query_builder.dart:33-45` · catégorie correctness · confiance high

**Problème** : Le flux passe par deux sanitizers. Le legacy `buildFtsQuery` détecte `caval*` comme opérateur FTS (`\w+\*`) et le conserve. Puis `buildTranslationUnitsQuery`/`VersionsQuery`/`MemoryQuery` rappellent `_sanitizeFtsQuery` qui, ligne 449, applique `RegExp(r'[^\w\s\-_."\']+')` -> remplace l'astérisque (et les parenthèses) par un espace. `caval*` devient `caval`.

```dart
sanitized = sanitized.replaceAll(RegExp(r'[^\w\s\-_."' + "'" + r']+'), ' '); // supprime *, ( )
```

**Impact** : La recherche par préfixe annoncée dans la doc ne fonctionne pas : `caval*` ne matche plus `cavalry`/`cavalier` mais seulement le token exact `caval` (souvent 0 résultat), sur les trois recherches FTS. Les parenthèses de groupement FTS sont aussi supprimées, altérant la précédence des requêtes booléennes (les mots-clés `OR`/`AND` survivent toutefois). Pas de corruption de données ni de faille (l'anti-injection reste assuré).

**Recommandation** : Autoriser explicitement les opérateurs FTS5 légitimes (`*` en suffixe de token, parenthèses) dans la regex de nettoyage du `sql_builder`, ou ne pas re-nettoyer une requête déjà construite/validée par le builder legacy.

### Toute la résolution de conflit par clé (useFirst/useSecond/skip) est du code mort : jamais alimentée par l'UI

fichier `lib/features/pack_compilation/providers/compilation_conflict_providers.dart:70-109`, `lib/features/pack_compilation/widgets/conflicting_projects_panel.dart`, `lib/features/pack_compilation/widgets/project_conflicts_detail_dialog.dart` · catégorie correctness · confiance high

**Problème** : `CompilationConflictResolutionsState.setResolution`/`setDefaultResolution` et `CompilationConflictAnalysis.updateWithResolutions` ne sont appelés par AUCUN widget de la feature. Les UI de conflit ne font qu'afficher et permettre la désélection de projets entiers. Par conséquent `_buildExcludedKeysByProject` (`compilation_editor_notifier.dart:205-235`) lit toujours des résolutions vides (`if (resolution == null) continue`) et n'exclut jamais aucune clé ; `excludeKeys` est toujours `const {}`. Les providers de garde (`canProceedWithCompilation`, `unresolvedConflictCount`, `conflictsNeedingResolution`) ne sont eux-mêmes jamais consommés.

```dart
void setResolution(...) { state = state.setResolution(...); } // jamais appelé dans la feature
```

**Impact** : L'utilisateur ne peut pas choisir, clé par clé, quelle traduction conserver. La fusion retombe systématiquement sur le comportement par défaut (first-writer-wins par ordre). La machinerie de résolution donne une fausse impression de contrôle. Ni corruption de données ni crash : fallback documenté.

**Recommandation** : Soit câbler une vraie UI de résolution par clé qui appelle `setResolution` puis `updateWithResolutions`, soit retirer le code mort. À minima, rendre l'ordre de fusion déterministe et signifiant puisque c'est le seul mécanisme réellement actif.

### La boîte d'avertissement de conflits avant compilation se base sur des conflits jamais marqués résolus

fichier `lib/features/pack_compilation/screens/pack_compilation_editor_screen.dart:289-296`, `lib/features/pack_compilation/models/conflict_analysis_result.dart:40-42` · catégorie correctness · confiance high

**Problème** : Le callback de compilation lit `analysis.hasUnresolvedConflicts`, qui parcourt `conflicts.any((c) => !c.isResolved && !c.canAutoResolve)`. Or `c.isResolved` (`resolution != null`) n'est positionné que via `updateWithResolutions`, jamais appelé (constat précédent). De plus `_buildSummary` force `duplicateCount: 0`, donc `canAutoResolve` est toujours false. `hasUnresolvedConflicts` se réduit donc à `conflicts.isNotEmpty`.

```dart
if (analysis != null && analysis.hasUnresolvedConflicts) { ... } // toujours vrai s'il y a des collisions
```

**Impact** : Le dialogue « conflits non résolus, forcer la compilation ? » s'affiche systématiquement dès qu'il existe ≥1 collision, sans jamais refléter un état résolu, et le compteur `unresolvedCount` est trompeur. Ce n'est pas bloquant (« forcer » poursuit la compilation via le fallback par défaut) ; défaut de correction/UX, pas de perte de données.

**Recommandation** : Soit dériver l'état résolu depuis le provider de résolutions réel (`compilationConflictResolutionsStateProvider`), comme `canProceedWithCompilation`/`unresolvedConflictCount`, soit clarifier que l'avertissement signale seulement la présence de collisions fusionnées automatiquement.

### Concurrence

### État d'annulation/processus mutable partagé sur le singleton RpfmServiceImpl

fichier `lib/services/rpfm/rpfm_service_impl.dart:27-98` · catégorie concurrency · confiance medium

**Problème** : `IRpfmService` est enregistré en lazy singleton (`core_service_locator.dart:94-95`) et porte un état mutable partagé `_isCancelled` et `_currentProcess`. `createPack` remet `isCancelled=false` en début d'opération (`rpfm_pack_operations_mixin.dart:30`) ; `cancel()` met `isCancelled=true`, tue `_currentProcess` et le remet à null, sans notion d'opération propriétaire. Les mixins d'extraction remettent aussi `isCancelled=false` dans leur `finally`. `cancel()` est câblé sur des flux INDÉPENDANTS partageant le même singleton (`project_initialization_service_impl.dart:357` via `extractLocalizationFilesAsTsv`, `compilation_editor_notifier.dart:119` via `createPack`, `pack_import_service`). Aucun verrou/jeton dans `lib/services/rpfm`.

```dart
Process? _currentProcess;
bool _isCancelled = false;
...
Future<void> cancel() async {
  _isCancelled = true;
  _currentProcess?.kill();
  _currentProcess = null;
}
```

**Impact** : Si deux opérations RPFM se chevauchent (extraction + création de pack), l'une peut réinitialiser le flag d'annulation de l'autre, ou `cancel()` peut tuer le mauvais processus / un processus déjà remplacé. Dart étant mono-isolate il n'y a pas de data race stricte, mais l'entrelacement aux points `await` suffit. Reachability conditionnelle : aucun chemin UI courant ne lance deux opérations RPFM simultanément (dialogues de progression bloquants).

**Recommandation** : Encapsuler `isCancelled` + `currentProcess` dans un objet d'opération (token) créé par appel, ou sérialiser strictement les opérations RPFM (verrou) et documenter qu'une seule opération est permise à la fois.

### Annulation d'une mise à jour de mod écrasée par un statut completed/failed (et version persistée)

fichier `lib/providers/mods/mod_update_provider.dart:357-372, 322-354` · catégorie concurrency · confiance high

**Problème** : `cancelAll()` met l'entrée de la file en `cancelled` et appelle `steamService.cancel()`, mais l'appel `_updateProject` déjà en vol continue son `await downloadResult.when(...)`. Les helpers `_updateStatusWithVersion`/`_updateStatusWithError` ne vérifient que `ref.mounted` et `info != null` — jamais si le statut courant est déjà `cancelled`. Selon le timing : soit le download se termine en erreur `DOWNLOAD_CANCELLED` et le statut repasse à `failed` (cas fréquent, écrase `cancelled`) ; soit il se termine en succès et une `ModVersion` est insérée ET marquée courante, le statut repassant à `completed`.

```dart
void _updateStatusWithVersion(...) {
  if (!ref.mounted) return;
  final info = _updateQueue[projectId]; // pas de check 'cancelled'
  if (info != null) { ... state = Map.from(_updateQueue); }
}
```

**Impact** : Une mise à jour explicitement annulée peut malgré tout créer une ligne `mod_versions` marquée `is_current=1` et s'afficher comme terminée. Incohérence entre l'intention (annulé) et l'état réel. Le symptôme `cancelled`->`failed` est probable ; la persistance d'une version a une fenêtre plus étroite (atténuée par le fait que la `ModVersion` est actuellement un placeholder TODO).

**Recommandation** : Avant d'écrire `completed`/`failed`/la nouvelle version, vérifier que `_updateQueue[projectId]?.status != ModUpdateStatus.cancelled` (et ne pas insérer/`markAsCurrent` si annulé). Idéalement propager un flag d'annulation dans `_updateProject` pour court-circuiter l'insertion après `cancel()`.

### Gestion d'erreurs

### Le repli .loc de createPack masque une perte de fichiers de traduction

fichier `lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:153-176` · catégorie error-handling · confiance high

**Problème** : Dans la branche de repli legacy (`.loc`), chaque fichier que RPFM refuse n'est que journalisé en warning (`logger.warning('Failed to add .loc file')`), `locAddedOk` n'étant incrémenté qu'en cas de succès. La fonction ne retourne `Err` que si AUCUN fichier n'a pu être ajouté (`locAddedOk == 0`). Si 9 fichiers sur 10 sont ajoutés et 1 échoue, `createPack` retourne `Ok(outputPackPath)` alors qu'un fichier de localisation est silencieusement absent. La vérification finale (lignes 250-258) ne contrôle que l'existence du pack et sa taille, pas la présence de tous les fichiers d'entrée. Incohérent avec la branche TSV (lignes 232-241) qui échoue durement au premier fichier rejeté.

```dart
if (exitCode != 0) {
  final stderr = await stderrFuture;
  final error = RpfmOutputParser.parseErrorMessage(stderr);
  logger.warning('Failed to add .loc file: $error');
} else {
  locAddedOk++;
}
...
if (locAddedOk == 0) { ... return Err(...); }
```

**Impact** : Un pack peut être produit avec succès apparent tout en ayant perdu une partie des traductions (perte de données masquée). Atténuation : ce chemin est explicitement un repli legacy, emprunté uniquement quand `tsvFiles.isEmpty` alors que des `.loc` existent ; le pipeline d'export normal produit des TSV et emprunte la branche durcie.

**Recommandation** : Aligner la branche `.loc` sur la branche TSV : comptabiliser le nombre d'échecs et, si `locAddedOk < totalLocFiles`, retourner `Err` (ou remonter explicitement la liste des fichiers non ajoutés) plutôt que de masquer l'échec partiel derrière un `Ok`.

### Accept/Reject/Edit d'une issue ignorent le Result de versionRepo.update (échec masqué)

fichier `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:431, 461, 501` · catégorie error-handling · confiance high

**Problème** : `handleRejectTranslation`, `handleAcceptTranslation` et `handleEditTranslation` appellent `await versionRepo.update(...)` sans vérifier le `Result` (typé `Result<TranslationVersion, TWMTDatabaseException>`, qui retourne `Err` sans lever en cas d'échec). Contrairement à `handleCellEdit` (qui teste `updateResult.isErr` et lève), l'échec d'écriture est silencieusement avalé : `refreshProviders()` est appelé inconditionnellement et un log « success » est émis.

```dart
await versionRepo.update(acceptedVersion); // Result ignoré
ref.read(loggingServiceProvider).info('Translation accepted despite issues', ...);
refreshProviders();
```

**Impact** : Si la mise à jour échoue (verrou DB, contrainte), l'utilisateur voit la ligne disparaître de la vue `needsReview` après refresh alors que rien n'a été persisté, ou croit avoir corrigé/accepté/rejeté une traduction qui ne l'a pas été. Échec masqué en succès apparent. Conditionné à un échec DB (rare sur base SQLite locale).

**Recommandation** : Vérifier le résultat : `final r = await versionRepo.update(...); if (r.isErr) { log + EditorDialogs.showErrorDialog(...); return; }` avant de logger le succès et de rafraîchir, comme dans `handleCellEdit`.

### Échec de persistance de la liste de projets (setProjects) avalé : « Compilation saved » et pack généré malgré l'erreur DB

fichier `lib/features/pack_compilation/providers/compilation_editor_notifier.dart:156-160, 181-185, 190-191, 451-454` · catégorie error-handling · confiance high

**Problème** : Dans `saveCompilation`, le `Result<void>` de `compilationRepo.setProjects(...)` est ignoré dans les deux branches (édition ligne 157, création ligne 182), contrairement aux `update`/`insert` juste au-dessus qui sont contrôlés. L'état passe ensuite inconditionnellement à `successMessage: 'Compilation saved'` et renvoie `true`. `setProjects`/`updateAfterGeneration` passent par `executeTransaction`/`executeQuery` qui retournent `Err` sans relancer, donc l'échec n'est pas capté par le `try/catch` de `saveCompilation`. `generatePack` poursuit sur ce `true` potentiellement mensonger.

```dart
await compilationRepo.setProjects(state.compilationId!, ...); // Result ignoré
state = state.copyWith(successMessage: 'Compilation saved'); return true;
```

**Impact** : Si l'écriture de `compilation_projects` échoue, l'utilisateur voit « Compilation saved » et un pack est produit (depuis l'état mémoire), mais la sélection persistée ne correspond pas au pack généré. À la réouverture, la compilation affiche une liste de projets différente. Échec masqué par un succès ; conditionné à un échec d'écriture DB.

**Recommandation** : Vérifier `setProjects(...).isErr` et propager l'erreur (positionner `errorMessage`, renvoyer `false`) avant d'afficher le succès ; idem pour `updateAfterGeneration` (au moins logger/avertir).

### Toute erreur 'Failed to update workshop item' est interprétée comme item supprimé

fichier `lib/services/steam/workshop_publish_service_impl.dart:231-240, 620-638` · catégorie error-handling · confiance high

**Problème** : Le code teste `run.output.contains('Failed to update workshop item')` et retourne directement `WorkshopItemNotFoundException` (« item no longer exists on Steam »). Or steamcmd émet ce même préfixe générique pour de nombreuses causes (Access Denied, k_EResultLimitExceeded, contenu rejeté, erreur réseau transitoire) ; le suffixe entre parenthèses (le vrai code de résultat) est ignoré.

```dart
if (run.output.contains('Failed to update workshop item')) { ... return Err(WorkshopItemNotFoundException(...)); }
```

**Impact** : Un échec récupérable (droits, quota, réseau) est présenté comme « l'item n'existe plus sur Steam ». L'utilisateur peut alors supprimer/réinitialiser le `publishedSteamId` localement et créer un doublon, ou abandonner une mise à jour qui aurait réussi. Atténuation : le notifier ne réinitialise PAS automatiquement le `publishedSteamId` ; la création de doublon nécessite une action manuelle sur la foi du message trompeur.

**Recommandation** : Distinguer les causes : ne classer en `WorkshopItemNotFound` que si le message indique explicitement l'absence de fichier (k_EResultFileNotFound) ; sinon renvoyer une `WorkshopPublishException` générique en conservant le détail entre parenthèses.

## Faible

### Correction

### ConflictResolver et OptimisticLockManager ciblent une table/colonnes inexistantes

fichier `lib/services/concurrency/conflict_resolver.dart:599-622`, `lib/services/concurrency/optimistic_lock_manager.dart:49-185` · catégorie correctness · confiance high

**Problème** : `ConflictResolver` utilise la table `conflict_resolutions`, absente de `schema.sql` et de toute migration. `OptimisticLockManager` suppose une colonne `version` sur les tables ciblées (`translation_versions` n'en a pas). Les deux sont enregistrés au `CoreServiceLocator` mais jamais appelés. Ils écrivent en outre les `*_at` en `millisecondsSinceEpoch` contre la convention secondes.

```dart
await _db.insert('conflict_resolutions', { ... 'detected_at': conflict.currentTimestamp.millisecondsSinceEpoch, ... }); // table absente + ms au lieu de s
```

**Impact** : Code dormant : tout appel futur échouerait à l'exécution (« no such table conflict_resolutions » / « no such column version »), et les horodatages en ms corrompraient le tri. Aucun impact tant que non appelé, mais piège pour le prochain développeur qui les câblerait.

**Recommandation** : Soit supprimer ces managers et leur enregistrement, soit créer le schéma correspondant (table, colonne `version`) et corriger les horodatages en secondes (`~/ 1000`).

### ConflictResolver lit translation_versions.updated_at comme des millisecondes alors qu'il est stocké en secondes

fichier `lib/services/concurrency/conflict_resolver.dart:413-447` · catégorie correctness · confiance medium

**Problème** : `checkForConflicts` fait `DateTime.fromMillisecondsSinceEpoch((results.first['updated_at'] as int?) ?? ...)`. Comme `updated_at` est en SECONDES, l'interpréter en ms produit un `currentTimestamp` vers 1970 (facteur 1000), passé à `detectConflict` puis `_suggestStrategy`.

```dart
currentTimestamp: DateTime.fromMillisecondsSinceEpoch((results.first['updated_at'] as int?) ?? now.millisecondsSinceEpoch),
```

**Impact** : Latent et doublement neutralisé en pratique : `_suggestStrategy` IGNORE `currentTimestamp` (la stratégie dépend de `similarityScore`/`conflictType` ; `checkForConflicts` produit toujours `versionMismatch -> manualResolve`), et `ConflictResolver` n'est appelé par aucun code de production. Le mélange ms/secondes mordrait si la résolution était branchée ET si le timestamp était réellement utilisé.

**Recommandation** : Lire `updated_at` comme des secondes : `DateTime.fromMillisecondsSinceEpoch((updated_at as int) * 1000)`, en cohérence avec `translation_version.dart`.

### Tables entry_locks / batch_entry_reservations inexistantes dans le schéma

fichier `lib/services/concurrency/pessimistic_lock_manager.dart:143-154`, `lib/services/concurrency/batch_isolation_manager.dart:79-104` · catégorie correctness · confiance high

**Problème** : `PessimisticLockManager` opère sur `entry_locks` et `BatchIsolationManager` sur `batch_entry_reservations`, tables absentes du schéma et de toute migration. Les écritures `*_at` y sont en `millisecondsSinceEpoch`. Les deux managers sont enregistrés en lazy singleton (`core_service_locator.dart:127-137`) mais aucune méthode n'est appelée en production.

```dart
'reserved_at': now.millisecondsSinceEpoch, // table batch_entry_reservations absente du schéma + ms au lieu de secondes
```

**Impact** : Toute future utilisation lèverait « no such table » (verrou jamais acquis / réservation impossible). Impact actuel nul (code mort, enregistrement lazy donc constructeurs jamais exécutés). Le mélange ms/secondes est sans conséquence en isolement car les managers relisent et comparent en ms de façon interne cohérente.

**Recommandation** : Soit créer les tables manquantes (colonnes `*_at` en secondes), soit retirer ce code mort du locator. Si conservé, aligner les écritures sur des secondes.

### L'undo/redo écrit dans un UndoRedoManager autoDispose recréé à chaque accès : pile perdue

fichier `lib/features/translation_editor/providers/editor_providers.dart:30-33`, `lib/features/translation_editor/screens/actions/editor_actions_cell_edit.dart:17-81` · catégorie correctness · confiance high

**Problème** : `undoRedoManagerProvider` est un provider autoDispose (`isAutoDispose: true`) retournant `UndoRedoManager()`. Tous les consommateurs utilisent `ref.read` (jamais `ref.watch`), donc aucun listener ne maintient le provider en vie : l'instance est jetée dès la fin du cycle de lecture et `recordAction` opère sur une instance immédiatement disposée. Un AUTRE provider du même nom (`history_providers.dart`, keepAlive) n'est jamais utilisé par l'éditeur. `handleUndo`/`handleRedo` ne sont appelés nulle part (aucun raccourci Ctrl+Z) et n'appellent pas `refreshProviders`.

```dart
@riverpod
UndoRedoManager undoRedoManager(Ref ref) {
  return UndoRedoManager(); // autoDispose + ref.read => instance jetée, pile perdue
}
```

**Impact** : La pile d'annulation de l'éditeur est toujours vide. Impact entièrement latent : aucune UI ne déclenche undo/redo aujourd'hui (l'historique persistant réel est géré séparément par `historyService.recordChange`). Se manifesterait dès qu'un bouton/raccourci serait branché.

**Recommandation** : Utiliser le provider keepAlive de `history_providers.dart`, ou marquer `undoRedoManagerProvider` en `@Riverpod(keepAlive: true)`. Ajouter `refreshProviders()` après un undo/redo réussi. Supprimer le doublon de provider.

### Le source_text n'est jamais mis à jour quand l'utilisateur choisit 'utiliser l'import' malgré sourceTextDiffers signalé

fichier `lib/features/import_export/services/import_executor.dart:303-368`, `lib/features/import_export/services/import_conflict_detector.dart:136-152` · catégorie correctness · confiance high

**Problème** : Le détecteur calcule `sourceTextDiffers`, mais `_updateExistingVersion` (et plus largement le chemin « unité existante ») ne met jamais à jour `unit.sourceText` : seul `translation_versions.translated_text` est modifié. La résolution `useImported` ne touche que la version. `updateSourceTexts` existe mais n'est jamais appelé par l'executor.

```dart
// _updateExistingVersion ne référence jamais sourceColumn / unit.sourceText
```

**Impact** : Quand un mod a modifié un texte source et que l'utilisateur résout par « utiliser l'import », le `source_text` reste l'ancienne valeur : désynchronisation source/traduction. Atténuation : `sourceTextDiffers` n'est lu par AUCUN provider/écran (seulement des tests), donc le narratif « UI signale puis trahit » ne tient pas ici, et le rafraîchissement du source passe normalement par un autre chemin (`updateSourceTexts` lors d'une re-détection).

**Recommandation** : Lorsqu'une unité existe, que `sourceColumn` est mappée et que le texte source importé diffère, mettre à jour `unit.sourceText` (avec `updatedAt`) via `unitRepository.update` dans le même flux, ou documenter/désactiver explicitement le signalement `sourceTextDiffers`.

### copyWith ne peut pas remettre selectedLanguageId à null : updateLanguage(null) laisse l'ancienne langue tout en vidant projets et préfixe

fichier `lib/features/pack_compilation/models/compilation_editor_state.dart:71`, `lib/features/pack_compilation/providers/compilation_editor_notifier.dart:56-64` · catégorie correctness · confiance medium

**Problème** : `updateLanguage(null)` appelle `copyWith(selectedLanguageId: null, prefix: '', selectedProjectIds: const {})`. Mais `copyWith` fait `selectedLanguageId: selectedLanguageId ?? this.selectedLanguageId`, ignorant le null passé. Résultat : préfixe et projets effacés mais `selectedLanguageId` conservé — état incohérent.

```dart
selectedLanguageId: selectedLanguageId ?? this.selectedLanguageId, // null ignoré
```

**Impact** : Actuellement non déclenchable : le `DropdownButton` n'émet que des `l.id` non nuls (la branche `if (languageId == null)` est du code mort). Piège latent si un appel `updateLanguage(null)` était ajouté (ex. bouton « effacer »).

**Recommandation** : Pour les champs réellement annulables, adopter un pattern de clearing explicite (sentinel/flag `clearLanguage`) ou gérer la branche null sans passer par `copyWith`.

### Le mapping code->ID de langue en cache mémoire n'est jamais invalidé après suppression/recréation d'une langue

fichier `lib/services/translation_memory/tm_matching_service.dart:29, 69-85`, `lib/services/translation_memory/tm_crud_service.dart:28, 43-63` · catégorie correctness · confiance medium

**Problème** : `TmMatchingService` et `TmCrudService` mémorisent `_languageCodeToId` pour la vie du service (providers `keepAlive: true`). Aucun chemin n'invalide cette map. Si une langue custom est supprimée puis recréée avec le même code mais un ID différent, `_resolveLanguageId` renvoie l'ancien ID.

```dart
final Map<String, String> _languageCodeToId = {}; // jamais purgé
```

**Impact** : Bénin. La « corruption FK » est réfutée : `FOREIGN KEY ... ON DELETE RESTRICT` + `PRAGMA foreign_keys = ON` fait échouer franchement (Err) tout INSERT/UPDATE avec un ID obsolète ; en lecture, un ID obsolète produit zéro résultat. Le seul effet réel est des lookups TM transitoirement vides dans un cas de bord rare (suppression + recréation même code sans redémarrage), auto-réparable au prochain lancement.

**Recommandation** : Exposer une invalidation du mapping (purge sur suppression/création de langue) ou résoudre l'ID sans cache mémoire de longue durée.

### La recherche regex duplique les résultats par langue/version (JOIN non dédupliqué)

fichier `lib/services/search/utils/regex_query_builder.dart:81-101` · catégorie correctness · confiance medium

**Problème** : `buildRegexQuery` fait `FROM translation_units tu LEFT JOIN translation_versions tv ON tv.unit_id = tu.id` sans `DISTINCT` ni `GROUP BY`. Une unité ayant N versions (N langues) produit N lignes (mêmes `tu.id`), et le consommateur les convertit 1:1 en `SearchResult` sans déduplication.

```dart
FROM translation_units tu
LEFT JOIN translation_versions tv ON tv.unit_id = tu.id
```

**Impact** : Quand `searchIn='source'` ou `'both'` et qu'une unité a plusieurs traductions, le même résultat source apparaît plusieurs fois, gonflant la liste et le `resultCount` de l'historique. Purement cosmétique (pas de corruption ni crash). Pour `searchIn='target'` chaque version distincte est légitime.

**Recommandation** : Dédupliquer par unité quand on cherche dans la source (`GROUP BY tu.id` ou `DISTINCT`), ou clarifier la granularité attendue (par version vs par unité).

### _parseTimestamp interprète des secondes comme des millisecondes

fichier `lib/services/search/search_service_impl.dart:527-533` · catégorie correctness · confiance high

**Problème** : `_parseTimestamp` fait `DateTime.fromMillisecondsSinceEpoch(timestamp)` alors que `created_at`/`updated_at`/`last_used_at` sont stockés en secondes. Un timestamp seconde ~1.717e9 interprété comme ms donne une date en janvier 1970.

```dart
if (timestamp is int) {
  return DateTime.fromMillisecondsSinceEpoch(timestamp); // secondes traitées comme ms
}
```

**Impact** : Les dates `createdAt`/`updatedAt` des `SearchResult` sont fausses d'un facteur 1000. Impact actuel nul : aucun widget/provider de la feature search ne lit ces champs (0 occurrence dans `lib/features/search`). Donnée latente erronée, visible seulement si une future UI exploitait ces dates.

**Recommandation** : Multiplier par 1000 avant conversion : `DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)`, ou utiliser un helper unifié respectant la convention secondes.

### Incohérence du comptage des reverts entre statistiques globales et par-version (double comptage global)

fichier `lib/services/history/history_service_impl.dart:139, 165, 347`, `lib/repositories/translation_version_history_repository.dart:299-310` · catégorie correctness · confiance high

**Problème** : Un revert appelle `recordChange` deux fois : `'Before revert to version $historyId'` puis `'Reverted to version $historyId'`. `countReverts` (SQL) compte via `change_reason LIKE '%Reverted%' OR change_reason LIKE '%revert%'` (LIKE insensible à la casse) : les deux lignes matchent -> 2 par revert. `getStatisticsForVersion` compte via `changeReason.contains('Reverted')` (Dart, sensible casse) : seule la ligne « Reverted... » matche -> 1 par revert.

```dart
WHERE change_reason LIKE '%Reverted%' OR change_reason LIKE '%revert%'  // matche aussi 'Before revert to version ...'
```

**Impact** : Divergence ~x2 entre comptage global et par-version. Impact actuel nul : `historyStatisticsProvider`/`versionHistoryStatisticsProvider` ne sont consommés par aucun widget (seules les définitions `.g.dart` existent). La valeur gonflée n'est jamais affichée.

**Recommandation** : Unifier la détection sur un marqueur unique non ambigu (ex. ne compter que les motifs commençant par « Reverted to »), en alignant la requête SQL et le `contains()` Dart.

### applyAllAutoFixes ignore les correctifs doubles-espaces et nombres, et écrase les fixes en chaîne

fichier `lib/services/validation/translation_validation_service.dart:78-129` · catégorie correctness · confiance high

**Problème** : `applyAllAutoFixes` ne traite que `whitespaceIssue` puis `missingVariables`. Or (a) `missingVariables` n'est plus auto-fixable (`autoFixable=false` fixé ligne 219), branche morte ; (b) `modifiedNumbers` et le second `whitespaceIssue` (doubles espaces) ne sont jamais appliqués ; (c) chaque branche part de `translatedText` original via `issue.autoFixValue` puis affecte `fixedText`, donc une seconde correction écraserait la première.

**Impact** : Si un appelant utilisait `applyAllAutoFixes` en attendant tous les correctifs, ceux des nombres et doubles espaces seraient perdus. Impact actuel limité : aucun consommateur en production (l'UI applique les corrections individuellement via `issue.autoFixValue`).

**Recommandation** : Itérer sur tous les `issues` où `autoFixable && autoFixValue != null` de façon composable (enchaîner sur `fixedText`), ou documenter que la méthode ne couvre qu'un sous-ensemble. Supprimer la branche morte `missingVariables`.

### Intégrité des données

### La suppression d'une langue personnalisée n'invalide pas le cache TM singleton

fichier `lib/features/settings/providers/language_settings_providers.dart:199-215`, `lib/services/translation_memory/tm_cache.dart:117-131` · catégorie data-integrity · confiance high

**Problème** : `deleteLanguage` appelle `tmRepository.deleteByLanguageId(languageId)` directement sur le repository, contournant la façade `TranslationMemoryServiceImpl` (seul endroit appelant `clearCache()`). Le `TmCache` est un singleton process-wide et le provider TM est `keepAlive: true`. La clé de cache est le code bare (`fr`), donc les exact-matches en cache survivent à la suppression.

```dart
final tmCleanupResult = await tmRepository.deleteByLanguageId(languageId);
// ... aucune invalidation du TmCache singleton ici
```

**Impact** : `findExactMatch` peut continuer à renvoyer une traduction issue d'une entrée TM supprimée tant que l'entrée de cache vit. Fortement atténué : `deleteLanguage` bloque la suppression tant que la langue est rattachée à un projet, et les consommateurs de `findExactMatch` opèrent sur des projets dont la cible doit être rattachée ; après suppression, plus aucun projet ne cible ce code. Le seul chemin réaliste est la recréation du même code.

**Recommandation** : Après un `deleteByLanguageId` réussi, vider le cache TM (`ITranslationMemoryService.clearCache()` ou `TmCache().invalidateLanguagePair(code, code)`), comme les mutations passant par la façade.

### OptimisticLockManager écrit updated_at en millisecondes sur des tables stockant des secondes

fichier `lib/services/concurrency/optimistic_lock_manager.dart:133-137, 248, 256-258, 305, 351` · catégorie data-integrity · confiance medium

**Problème** : `updateWithVersionCheck`, `incrementVersion`, `resetVersion` et `batchUpdateWithVersionCheck` ajoutent `'updated_at': DateTime.now().millisecondsSinceEpoch` sur des tables génériques passées par le caller (la doc cite `translation_versions`, en secondes). Aucune méthode mutante n'a d'appelant en production.

```dart
'updated_at': DateTime.now().millisecondsSinceEpoch,
```

**Impact** : Latent (zéro appelant). Si utilisées contre `translation_versions`, `updated_at` deviendrait ~1000x trop grand, corrompant le tri par récence. La mention d'une violation de `CHECK(created_at <= updated_at)` est inexacte (un `updated_at` plus grand satisfait la contrainte ; et cette contrainte n'existe que sur `compilations`/`glossaries`).

**Recommandation** : Convertir en secondes (`~/ 1000`) pour `updated_at`, ou rendre la dérivation du timestamp explicite/paramétrable.

### Horodatages du glossaire stockés en millisecondes alors que la convention projet est en secondes

fichier `lib/services/glossary/glossary_service_impl.dart:83, 271, 353`, `lib/repositories/glossary_repository.dart:419`, `lib/services/glossary/deepl_glossary_sync_service.dart:139`, `lib/services/glossary/glossary_auto_provisioning_service.dart:70` · catégorie correctness · confiance high

**Problème** : Tout le module glossaire écrit `created_at`/`updated_at`/`synced_at` via `DateTime.now().millisecondsSinceEpoch` SANS `~/ 1000`, contre la convention secondes. En interne le module reste cohérent (la comparaison de resync compare ms vs ms), mais la divergence est un piège. `glossary_migration_service.dart:46-53` documente d'ailleurs explicitement ce bug et un contournement (`updated_at + 1` pour court-circuiter le trigger).

```dart
final now = DateTime.now().millisecondsSinceEpoch; // attendu: ~/ 1000
```

**Impact** : Pas d'impact visible aujourd'hui (pas d'affichage de ces dates, comparaisons internes homogènes, triggers `WHEN NEW.updated_at = OLD.updated_at` jamais déclenchés car le code écrit toujours un nouveau timestamp). Risque latent pour tout lecteur transverse supposant des secondes, et incohérence de données entre tables.

**Recommandation** : Aligner sur la convention : diviser par 1000 à l'écriture pour toutes les colonnes `*_at` du module, ou centraliser via un helper unique partagé. Migrer les données existantes le cas échéant.

### revertToVersion non atomique : la version peut être modifiée alors que l'opération renvoie une erreur

fichier `lib/services/history/history_service_impl.dart:103-174` · catégorie data-integrity · confiance medium

**Problème** : `revertToVersion` enchaîne sans transaction : (1) `recordChange` de l'état courant, (2) `_versionRepository.update(...)` qui écrit réellement le texte historique (autocommit), puis (3) `recordChange` du revert. Si l'étape 3 échoue, la fonction retourne `Err` alors que la version a DÉJÀ été modifiée à l'étape 2.

**Impact** : L'appelant reçoit `Err` et croit le revert échoué (toast « restore failed », pas d'invalidation des providers), alors que le texte a été remplacé en base et que l'entrée d'audit du revert manque. Probabilité d'échec de l'étape 3 après succès de l'étape 2 très faible (même base SQLite locale) ; pas de perte/corruption de données, seulement audit manquant + message trompeur.

**Recommandation** : Encapsuler les trois opérations dans une seule `executeTransaction`, ou au minimum réordonner pour que l'enregistrement d'audit du revert précède (ou partage la transaction avec) la mise à jour de la version.

### Gestion d'erreurs

### L'export omet silencieusement des lignes en cas d'échec de lecture d'unité tout en signalant un succès

fichier `lib/features/import_export/services/import_export_service.dart:127-128, 184-185` · catégorie error-handling · confiance medium

**Problème** : Dans `executeExport` et `previewExport`, `final unitResult = await _unitRepository.getById(version.unitId); if (unitResult.isErr) continue;`. `getById` renvoie `Err` aussi bien pour « non trouvé » que pour une erreur DB réelle. Toute erreur fait passer la ligne à la trappe sans la compter, et la fonction renvoie `Ok(ExportResult)` avec un `rowCount` diminué.

```dart
if (unitResult.isErr) continue;
```

**Impact** : Une erreur DB transitoire (ou une version orpheline) pendant l'export produit un fichier incomplet sans avertissement, le `rowCount` masquant l'omission. Probabilité faible (intégrité référentielle FK + erreur transitoire au milieu de l'export d'une ligne, rare sur SQLite local).

**Recommandation** : Propager une vraie erreur DB en `Err` (en distinguant not-found), ou au minimum compter/retourner le nombre de lignes ignorées dans `ExportResult`.

### stderr non drainé avant lecture dans downloadMod (message d'erreur tronqué)

fichier `lib/services/steam/steamcmd_service_impl.dart:117-152` · catégorie error-handling · confiance medium

**Problème** : `downloadMod` lit `stderr.toString()` immédiatement après `await exitCode`, sans attendre la fin du drain des flux stdout/stderr (la complétion de `Process.exitCode` ne garantit pas le drain complet). Le chemin de publication a précisément été corrigé avec un `outputCompleter` signalé par les `onDone` ; `downloadMod` ne l'a pas.

```dart
final errorMsg = _parseErrorMessage(stderr.toString());
```

**Impact** : Purement diagnostic : `_parseErrorMessage` peut renvoyer « Unknown error » ou une ligne partielle alors que steamcmd avait émis une cause précise. La décision succès/échec repose sur `exitCode` et l'existence du répertoire, pas sur stderr ; aucun risque de corruption ni de faux résultat.

**Recommandation** : Reprendre le pattern du chemin publish : attendre un `Completer` signalé par les `onDone` de stdout et stderr (avec timeout court) avant de lire les buffers.

### Collision de noms de fichiers VDF en batch → mauvais contenu publié sur un item Workshop

fichier `lib/services/steam/vdf_generator.dart:26`, `lib/services/steam/workshop_publish_service_impl.dart:383-394` · catégorie data-integrity · confiance medium

**Problème** : Le chemin du VDF est dérivé uniquement de `DateTime.now().millisecondsSinceEpoch` : `workshop_item_${...}.vdf`. Dans `publishBatch`, `generateVdf` est appelé SANS `outputDir`, donc tous les VDF du batch sont écrits dans la même racine `systemTemp` (et non dans le `tempDir` unique de chaque item). Deux items avec la même milliseconde produiraient le même `vdfPath` ; la seconde écriture écraserait la première, et la commande émettrait `+workshop_build_item <même chemin>` deux fois.

```dart
final vdfPath = path.join(dir, 'workshop_item_${DateTime.now().millisecondsSinceEpoch}.vdf');
```

**Impact** : Un mod du batch pourrait être republié avec la config d'un autre (mauvais `publishedFileId`, titre, dossier de contenu), remonté comme « success ». Probabilité de déclenchement extrêmement faible : entre deux captures s'intercalent obligatoirement `createTemp` + la copie d'un `.pack` multi-Mo, ce qui rend un écart sub-milliseconde quasi impossible. Défaut latent à correction triviale.

**Recommandation** : Rendre le nom unique indépendamment de l'horloge : placer le VDF dans le `tempDir` unique de chaque item (`path.join(tempDir.path, 'workshop_item.vdf')`), ou ajouter un compteur/UUID.

### Gestion d'erreurs

### Échec silencieux de markAsCurrent lors d'une mise à jour de mod

fichier `lib/providers/mods/mod_update_provider.dart:251-263` · catégorie error-handling · confiance high

**Problème** : Dans `_updateProject`, après l'insertion de la `ModVersion`, `await versionRepo.markAsCurrent(version.id)` ignore le `Result` retourné (`Future<Result<ModVersion, TWMTDatabaseException>>`, qui retourne `Err` sans lever). Le code passe ensuite directement à `_updateStatusWithVersion(..., ModUpdateStatus.completed, version)` sans vérifier `isErr` ; l'erreur n'est pas captée par le `try/catch`.

```dart
final insertResult = await versionRepo.insert(newVersion);
...
  ok: (version) async {
    await versionRepo.markAsCurrent(version.id); // Result ignoré
    _updateStatusWithVersion(projectId, ModUpdateStatus.completed, version);
  },
```

**Impact** : Si `markAsCurrent` échoue, l'UI affiche `completed` alors qu'aucune version n'est `is_current=1` en base. Probabilité très basse : `version` vient d'un insert réussi (la branche « introuvable » est quasi impossible), seul un échec transactionnel DB rare est plausible, et `markAsCurrent` étant atomique l'état DB resterait cohérent. Cette branche est de plus un placeholder TODO non finalisé.

**Recommandation** : Capturer le `Result` et router vers `_updateStatusWithError(...)` en cas d'échec au lieu de marquer `completed`. Idéalement, exécuter `insert` + `markAsCurrent` dans une seule transaction atomique.

## Périmètre & méthode

Cette revue v2 a consolidé les constats de l'ensemble des shards (file-pack-rpfm, repos-batch, database, translation-editor, import-export, steam-publish, pack-compilation, glossary, translation-memory, settings, projects, mods, search, concurrency-shared, history-activity, utils-validation, providers-di). Les constats redondants entre shards ont été fusionnés et regroupés par sévérité puis par catégorie.

Chaque constat a fait l'objet d'une vérification adversariale par lecture directe du code source, des sites d'appel et du schéma SQLite : plusieurs sévérités ont été ajustées à la baisse lorsque la vérification a révélé un chemin mort (code enregistré au locator mais jamais appelé), un déclencheur irréaliste (fenêtre de course quasi fermée), ou un impact surévalué (champ peuplé mais non consommé par l'UI, contrainte `CHECK` inexistante). Les constats restants sont ceux dont chaque prémisse porteuse a résisté à la tentative de réfutation. `flutter analyze` était propre (0 problème) au moment de la revue ; aucun constat ne relève de ce que l'analyseur statique capterait déjà.

Plusieurs défauts de sévérité Faible sont des pièges latents sur du code dormant (managers de concurrence ciblant des tables inexistantes, undo/redo non câblé, filtres de recherche non consommés) : leur impact utilisateur actuel est nul, mais ils sont conservés car ils mordraient au premier câblage et signalent une dette structurelle (tables manquantes, convention ms/secondes violée).

## Addendum — Audit de régression des correctifs récents (diff 64250c2..HEAD)

Lors de la première passe de cette revue v2, le shard dédié à la régression des correctifs récents avait échoué (interférence avec l'état git). Il a été relancé hors de tout contexte git, par lecture directe du code et des diffs des commits 2082a2a, 4588eb4 et d84e36a — les correctifs appliqués pour résoudre les constats de la revue précédente. `flutter analyze` reste propre (0 problème) ; aucun des constats ci-dessous n'est détectable par l'analyseur statique.

Cet audit cible spécifiquement les **régressions introduites par les correctifs** : changements de mode d'échec, correctifs incomplets (un frère réparé, l'autre laissé cassé), ou drapeaux ajoutés mais non câblés. Chaque constat a survécu à une vérification adversariale par lecture du code réel et du diff.

**Recoupements avec les constats existants de cette revue** (signalés ici, non dupliqués) :

- Le constat « Le garde-fou anti-collision du match exact TM est neutralisé » (ci-dessous, Élevé) est **distinct mais voisin** de « Le cache d'exact-match TM contourne la garde anti-collision de normalisation » (section Élevé, `tm_matching_service.dart:105-214`). Le constat existant porte sur le contournement de la garde par un **cache hit** ; la régression ci-dessous porte sur un **chemin différent** : même sur un cache miss où la garde s'exécute et rétrograde correctement la correspondance en `fuzzy`/`autoApplied:false`, `TmLookupHandler` ne lit jamais ces drapeaux et auto-applique quand même la correspondance en `translated`. Les deux convergent vers la même corruption (mauvaise traduction silencieusement appliquée) mais via des maillons non recouvrants.
- Le constat « RegexQueryBuilder filtre toujours sur `tv.language_code` » (ci-dessous, Moyen) **prolonge** le constat existant « Filtre regex par langue référence une colonne inexistante (tv.language_code) » (section Moyen, `regex_query_builder.dart`). Le point neuf de l'audit de régression : le **frère FTS a été réparé dans ce même correctif** (introduction de `_buildVersionFilterClause` routant vers `l.code`) tandis que le builder Regex strictement équivalent a été laissé sur la colonne inexistante — asymétrie introduite par le correctif lui-même.

### Décompte par sévérité (addendum)

| Sévérité | Nombre |
|----------|--------|
| Critique | 0 |
| Élevé | 1 |
| Moyen | 3 |
| Faible | 2 |

### Élevé

#### Intégrité des données

#### Le garde-fou anti-collision du match exact TM est neutralisé : la correspondance rétrogradée est quand même auto-appliquée comme 'translated'

fichier `lib/services/translation/handlers/tm_lookup_handler.dart:310-327, 137-142, 372-388` · catégorie data-integrity · confiance high

**Problème** : Le correctif dans `tm_matching_service.dart` (`findExactMatch`, lignes 145-197) détecte une collision de hash issue de la normalisation agressive (ex. `Attack` vs `ATTACK`, ou différences de markup) et rétrograde la correspondance en `matchType: fuzzy` + `autoApplied: false`, avec le commentaire explicite « so the wrong translation is never silently applied ». Or `TmLookupHandler._findExactMatch` (lignes 310-327) retourne CE match dès qu'il est non-null, sans jamais lire `autoApplied` ni `matchType`. `performLookup` l'ajoute alors à `allExactMatches` (lignes 137-142) — sans aucune garde, contrairement à la phase fuzzy qui exige `similarityScore >= autoAcceptTmThreshold` — et `_applyTmMatchesBatch` (lignes 372-388) l'écrit en base avec `status: TranslationVersionStatus.translated`. La rétrogradation ne change que la valeur de `translationSource` (`tmExact` -> `tmFuzzy`) ; elle n'empêche pas l'application automatique qu'elle prétend bloquer. Le drapeau `autoApplied` introduit n'est lu nulle part dans le flux de traduction de production (vérifié par grep : positionné dans `tm_matching_service`, `tm_cache`, le modèle `tm_match`, mais consommé seulement par un test).

```dart
if (exactMatchResult.isOk && exactMatchResult.unwrap() != null) {
  return exactMatchResult.unwrap()!; // autoApplied/matchType ignorés
}
```

**Impact** : Une mauvaise traduction (sensible en Total War : casse, markup `[[col:...]]`, ponctuation) est toujours écrite silencieusement comme version `translated`, exactement le scénario que le correctif annonce empêcher. Pire, un match rétrogradé à faible similarité (ex. 60 %) passe sans le filtre de seuil appliqué aux vrais fuzzy. Correctif incomplet. Le déclencheur exige une entrée TM préexistante dont la source ne diffère que par des caractères normalisés-agressivement, cas réaliste dans Total War et que la garde est explicitement censée couvrir.

**Recommandation** : Dans `_findExactMatch`, ne retourner la correspondance comme exacte que si `match.autoApplied == true` (ou `match.matchType == TmMatchType.exact`) ; sinon la router vers le chemin fuzzy non-auto-appliqué / la laisser pour traduction LLM, afin que `status: translated` ne soit jamais écrit pour une collision rétrogradée.

### Moyen

#### Régression

#### Import TBX : les fichiers sans xml:lang sur la racine martif et dont la source n'est pas l'anglais n'importent plus aucune entrée

fichier `lib/services/glossary/glossary_import_service.dart:338-373, 206, 258, 274` · catégorie regression · confiance high

**Problème** : Le nouveau `_parseTbxEntries` (lignes 338-373) identifie la source par la correspondance `_normalizeLang(lang) == normalizedSourceLang`, où `normalizedSourceLang` dérive de `defaultLang`. Or `defaultLang = martif.getAttribute('xml:lang') ?? 'en'` (ligne 206) : de nombreux fichiers TBX ne portent pas d'attribut `xml:lang` sur la racine `martif` (la langue est déclarée par `langSet`). Pour un fichier bilingue dont la source n'est pas l'anglais (ex. de->fr) et sans `xml:lang` `martif`, `defaultLang` vaut `'en'`, aucun `langSet` ne matche, `sourceTerm` reste null, tous les `langSet` deviennent des `targetCandidates`, et le garde `if (sourceTerm != null && targetCandidates.isNotEmpty)` (ligne 362) échoue : zéro entrée importée. La fonction retourne alors `Ok(0)` (ligne 274) sans erreur explicite (le garde ligne 258 `errors.isNotEmpty && importedCount == 0` ne se déclenche pas, aucune entrée n'ayant été tentée).

```dart
if (_normalizeLang(lang) == normalizedSourceLang && sourceTerm == null) {
  sourceTerm = term;
} else {
  targetCandidates.add(MapEntry(lang, term));
}
```

**Impact** : Régression de perte de données silencieuse à l'import : l'ancien code positionnel (1er `langSet` = source, 2e = cible) importait ces fichiers correctement, indépendamment de la langue. Désormais l'import renvoie 0 entrée sans erreur explicite pour tout TBX non-anglais sans `xml:lang` `martif`. Impact limité au cas double-condition : (1) absence de `xml:lang` sur `martif` ET (2) langue source non anglaise. Le cas dominant du domaine TWMT (mods Total War à source anglaise -> X) continue de fonctionner car `defaultLang='en'` matche le `langSet` anglais. Aucun test ne couvre l'import TBX.

**Recommandation** : Prévoir un repli : si aucun `langSet` ne correspond à `normalizedSourceLang`, retomber sur la sémantique positionnelle (premier `langSet` = source) au lieu de tout abandonner ; ou déduire la langue source du premier `langSet` rencontré quand la racine `martif` ne déclare pas `xml:lang`.

#### Correctif incomplet : RegexQueryBuilder._buildFilterClause filtre toujours sur la colonne inexistante tv.language_code (le sibling FTS a été corrigé, pas celui-ci)

fichier `lib/services/search/utils/regex_query_builder.dart:169, 95-97` · catégorie regression · confiance medium

**Problème** : Ce même diff a corrigé le routage des prédicats du builder FTS versions en introduisant `_buildVersionFilterClause` (`fts_query_builder.dart:309`) qui route correctement le filtre de langue vers `l.code` via les jointures `project_languages` -> `languages`, parce que `translation_versions` n'a PAS de colonne `language_code` (`schema.sql:165-183`, elle n'a que `project_language_id`). Mais le builder Regex parallèle n'a pas été touché : `_buildFilterClause` continue d'émettre `_addListFilter(conditions, filter.languageCodes, 'tv.language_code')`, et `buildRegexQuery` ne joint que `translation_units tu LEFT JOIN translation_versions tv ... LEFT JOIN projects p` (lignes 95-97), sans jointure vers `project_languages`/`languages`. Chemin atteignable et non gardé : `search_providers.dart:142-149` transmet `query.filter` tel quel à `searchWithRegex` dès que `useRegex` est vrai, sans dépouiller `languageCodes`.

```dart
_addListFilter(conditions, filter.languageCodes, 'tv.language_code'); // colonne inexistante; aucune jointure languages dans buildRegexQuery
```

**Impact** : Toute recherche regex (`searchWithRegex`) accompagnée d'un filtre `languageCodes` génère `WHERE ... AND tv.language_code IN (...)` et échoue à l'exécution avec « no such column: tv.language_code », remontant comme `SearchDatabaseException` opaque. La fonctionnalité de recherche regex filtrée par langue reste cassée alors que la branche FTS strictement équivalente a été réparée dans le même correctif. Panne ciblée d'une combinaison (regex littéral + filtre langue) d'un seul mode de recherche, sans perte de données ni crash global, mais combinaison réellement supportée et incohérence flagrante avec le frère réparé.

**Recommandation** : Répliquer la logique de `_buildVersionFilterClause` dans `RegexQueryBuilder` : router `languageCodes` vers `l.code` et ajouter les jointures `LEFT JOIN project_languages pl ON tv.project_language_id = pl.id` / `LEFT JOIN languages l ON pl.language_id = l.id`, ou retirer le prédicat de langue de ce builder si non supporté.

#### Correction

#### Correctif incomplet : `_correctIssue` (handleEditTranslation) ne vide pas validationIssues — le drapeau clearValidationIssues ajouté n'y est pas utilisé

fichier `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:492-496` · catégorie correctness · confiance medium

**Problème** : Le diff ajoute à `TranslationVersion.copyWith` les drapeaux `clearTranslatedText`/`clearValidationIssues` précisément parce que l'idiome `x ?? this.x` ne peut pas remettre un champ nullable à null. Il les applique dans le chemin `_clearTranslation` (`clearValidationIssues: true`). Mais dans le bloc sœur — modifié par le même diff (ajout de la normalisation ligne 492 : `translatedText: normalizedText`) — l'appel conserve `validationIssues: null`. Or dans le nouveau `copyWith` (`translation_version.dart:184-186`), `validationIssues: null` retombe sur `clearValidationIssues ? null : (validationIssues ?? this.validationIssues)` ; comme `clearValidationIssues` vaut `false` et `validationIssues` vaut `null`, l'ANCIENNE valeur est conservée (no-op). `update(editedVersion)` réécrit ensuite la map complète, persistant l'ancienne chaîne. Note : le même défaut existe aussi dans `handleAcceptTranslation` (ligne 457, `validationIssues: null`) — deux chemins sœurs touchés.

```dart
final editedVersion = version.copyWith(
  translatedText: normalizedText,
  status: TranslationVersionStatus.translated,
  validationIssues: null, // no-op: ne vide PAS le champ
  isManuallyEdited: true,
  ...);
```

**Impact** : Après une correction manuelle d'une unité signalée en validation, le champ `validationIssues` stocké n'est jamais effacé ; le statut passe à `translated` mais les anciens problèmes restent attachés à la version et continuent d'apparaître (`hasValidationIssues` renvoie `true` d'après la chaîne non vide, indépendamment du statut), donnant l'impression que la correction n'a pas pris. C'est exactement la classe de bug que le correctif prétend résoudre, laissée sur ce chemin sœur. Pas de corruption de données ni de crash, mais incohérence d'état visible utilisateur sur un chemin de correction courant.

**Recommandation** : Remplacer `validationIssues: null` par `clearValidationIssues: true` dans `handleEditTranslation` (ligne 496) et `handleAcceptTranslation` (ligne 457), de manière cohérente avec `_clearTranslation`.

### Faible

#### Intégrité des données

#### L'import d'un fichier .loc volumineux peut être silencieusement perdu en totalité (timeout de transaction 30s)

fichier `lib/services/projects/project_initialization_service_impl.dart:247-298`, `lib/services/database/database_service.dart:419-447` · catégorie data-integrity · confiance low

**Problème** : Le correctif regroupe désormais TOUTES les insertions d'un fichier (unités + versions par langue) dans une seule transaction `DatabaseService.transaction(...)`, sans argument `timeout`. Or `DatabaseService.transaction` (lignes 419-447) applique un timeout par défaut de 30 secondes et, en cas de dépassement, lève `TWMTDatabaseException`. Cette exception est attrapée par le bloc catch de l'import (ligne 281), qui se contente de logger un warning, de retirer les clés de `existingKeys`, d'émettre un `_addLog(... warning)` et de CONTINUER avec le fichier suivant ; l'opération globale renvoie `Ok`. Aucun chunking ni garde n'annule ce comportement.

```dart
await DatabaseService.transaction((txn) async {
  for (final unit in unitsToInsert) {
    await txn.insert('translation_units', unit.toJson(), conflictAlgorithm: ConflictAlgorithm.abort);
    for (final language in projectLanguages) { /* insert version */ }
  }
});
totalUnitsImported += unitsToInsert.length;
// catch -> log warning + continue (entire file dropped on 30s timeout)
```

**Impact** : Régression de mode d'échec vs l'ancien code, qui insérait chaque unité/version individuellement (`_unitRepository.insert`/`_versionRepository.insert`, sans plafond global de durée) : un import lent mais réussi pouvait auparavant aboutir entièrement, alors qu'au-delà de 30s tout le batch d'un fichier est désormais annulé et l'import se termine en succès avec un compteur `totalUnitsImported` réduit. Confiance basse : l'objectif même du correctif (transaction batchée) est dramatiquement plus rapide que les inserts ligne-à-ligne, donc le seuil de 30s est bien plus difficile à atteindre ; le déclenchement réel est peu probable. Nuance : la doc de `database_service.dart:407-409` précise que `.timeout()` cesse d'attendre mais n'annule PAS la transaction SQLite sous-jacente, donc l'effet garanti est surtout une INCOHÉRENCE (compteur/journal erronés, clés retirées de `existingKeys`) plutôt qu'une perte certaine.

**Recommandation** : Soit passer un `timeout` explicite plus généreux (proportionnel au nombre d'entrées) à `DatabaseService.transaction`, soit découper en sous-transactions par lots (chunks) bornés en taille pour garantir qu'aucun fichier ne soit perdu à cause du plafond de 30s. À défaut, élever la sévérité du log et surfacer l'échec à l'utilisateur plutôt que de renvoyer `Ok`.

#### Régression

#### Pagination réactivée pour des scopes de recherche qui n'honorent pas l'offset (contenu dupliqué entre pages)

fichier `lib/features/search/providers/search_providers.dart:101-103, 142-150, 180-186` · catégorie regression · confiance high

**Problème** : Le correctif remplace `totalCount: results.length` par l'heuristique `offset + results.length + (pageIsFull ? 1 : 0)`, appliquée uniformément à TOUS les scopes. Or `_executeSearch` ne transmet `offset` qu'aux scopes `source`/`key`/`target` (`searchTranslationUnits` / `searchTranslationVersions`). Pour `SearchScope.both`, `SearchScope.all` (`searchAll`) et le mode regex (`searchWithRegex`), l'offset n'est PAS accepté par le service (signatures sans `offset`, vérifiées dans `i_search_service.dart`). Le scope par défaut est `SearchScope.all` (`search_query_model.dart:163`).

```dart
final pageIsFull = results.length >= pageSize;
final totalCount = offset + results.length + (pageIsFull ? 1 : 0);
```

**Impact** : Sur une page pleine en scope `all`/`both`/regex (cas par défaut), `hasNextPage` passe désormais à `true`. En cliquant sur Suivant, `page` augmente et `offset` est recalculé, mais le service ignore l'offset et renvoie les MÊMES `pageSize` premières lignes — contenu identique sous un numéro de page différent. Avant le correctif, `totalCount == results.length` donnait `totalPages == 1` et le bouton Suivant restait désactivé : limité mais cohérent. Facteur atténuant majeur (sévérité abaissée à Faible) : ce chemin d'affichage n'est PAS câblé dans une UI vivante — `searchResultsProvider` n'est jamais `.watch`/`.read` pour ses résultats, et le widget `SearchPaginationControls` (qui lit `hasNextPage` / déclenche `onNextPage`) n'est instancié nulle part ; il n'existe aucun écran de recherche. Un utilisateur final ne peut donc pas déclencher la duplication aujourd'hui. Le défaut de code est réel mais non atteignable via l'UI actuelle.

**Recommandation** : N'appliquer l'heuristique `+1` que pour les scopes qui transmettent réellement l'offset (`source`/`key`/`target`, hors regex). Pour `all`/`both`/regex, conserver `totalCount = offset + results.length` sans le `+1` (ou désactiver Suivant), afin de ne pas proposer une page suivante qui rejoue les mêmes lignes.
