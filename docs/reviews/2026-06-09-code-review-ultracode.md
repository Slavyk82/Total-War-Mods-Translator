# Revue de code complète — Total War Mods Translator

Date : 2026-06-09

## Résumé exécutif

Cette revue indépendante de TWMT (Total War Mods Translator, ~237k lignes Dart/Flutter) a porté sur 22 shards couvrant l'export de packs, l'éditeur de traduction, l'import/export, la mémoire de traduction, les glossaires, la base de données, la recherche, l'intégration Steam et l'infrastructure. Elle met en évidence trois défauts critiques touchant la sortie principale de l'application : une régression d'export qui produit des tables `.loc` non converties (texte TSV brut au lieu de binaire), et deux failles d'intégrité multi-langues qui écrivent ou orphelinent silencieusement des traductions dans la mauvaise langue. Au-delà du critique, des thèmes récurrents émergent : résolution de version sans filtrage par langue, opérations multi-écritures non transactionnelles, avalement d'erreurs masquant des échecs en succès, et état mutable partagé sur des singletons. Chaque constat ci-dessous a survécu à une vérification adversariale (25 constats réfutés et écartés), et `flutter analyze` était propre (0 problème) au moment de la revue.

## Décompte par sévérité

| Sévérité | Nombre |
|----------|--------|
| Critique | 3 |
| Élevé | 6 |
| Moyen | 23 |
| Faible | 43 |

## Critique

### Intégrité des données

### Régression d'export : les fichiers générés portent l'extension .loc, donc createPack n'exécute jamais la conversion --tsv-to-binary

fichier `lib/services/file/loc_file_service_impl.dart:312-338; lib/services/file/pack_export_utils.dart:53-66; lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:99-161` · catégorie data-integrity · confiance high

**Problème** : Depuis le commit bc1e587 (« honor conflict resolutions »), `GeneratedLocFile.internalPath` est le chemin `.loc` brut (`buildLocInternalPath` renvoie par ex. `text/db/!!!!!!!!!!_fr_twmt_x.loc`, sans suffixe `.tsv`). `copyTsvFilesToPackStructure` écrit chaque fichier TSV à `tempDir/internalPath`, c.-à-d. avec une extension `.loc`. Or `createPack()` filtre `allFiles.where((f) => f.toLowerCase().endsWith('.tsv'))`, ensemble désormais toujours vide, donc la branche TSV (la seule qui passe `--tsv-to-binary schemaFile` et convertit réellement le texte TSV en table binaire) n'est jamais empruntée. L'exécution retombe dans la branche de repli `.loc` (lignes 105-160) qui fait `pack add` SANS `--tsv-to-binary`, fourrant ainsi le texte TSV brut dans le pack sous un chemin `.loc`.

```dart
// loc_file_service_impl.dart
final outputLocPath = buildLocInternalPath(sourceLocFile, langLower, prefix: prefix); // text/db/..._x.loc
generatedFiles.add(GeneratedLocFile(tsvPath: filePath, internalPath: outputLocPath));
// pack_export_utils.dart
final targetPath = path.join(tempDir.path, internalPath); // ends in .loc
// rpfm_pack_operations_mixin.dart
final tsvFiles = allFiles.where((f) => f.toLowerCase().endsWith('.tsv')).toList(); // now empty
```

**Impact** : Tout export `.pack` standard (`exportToPack`) et toute compilation de pack produisent désormais des packs dont les tables loc sont du texte TSV brut plutôt que du `.loc` binaire, c.-à-d. des traductions corrompues/illisibles en jeu. C'est la sortie principale de l'application ; tous les utilisateurs de la version actuelle sont affectés.

**Recommandation** : Faire en sorte que le nom de fichier sur disque dans `copyTsvFilesToPackStructure` se termine par `.tsv` (cible `tempDir/$internalPath.tsv`) afin que le filtre `.tsv` de `createPack` corresponde et que `--tsv-to-binary` s'exécute, tandis que `replaceAll('.tsv','')` récupère le chemin interne `.loc`. Ajouter un test de bout en bout vérifiant que `createPack` reçoit bien des entrées `.tsv` et invoque la branche `--tsv-to-binary`. Mettre à jour le test de merge pour refléter le nom `.tsv` sur disque.

### Les éditions de cellules inspecteur/grille écrivent dans la MAUVAISE version de langue en projet multilingue

fichier `lib/features/translation_editor/screens/actions/editor_actions_cell_edit.dart:13-95 (handleCellEdit), 97-179 (handleApplySuggestion)` · catégorie data-integrity · confiance high

**Problème** : `handleCellEdit` et `handleApplySuggestion` résolvent la version à mettre à jour via `versionRepo.getByUnit(unitId)` puis prennent `versions.first`. `getByUnit` ne filtre que sur `unit_id` avec `orderBy: 'created_at DESC'`, sans filtre `project_language_id`. Une `TranslationVersion` est créée par langue de projet pour chaque unité, toutes estampillées du MÊME `createdAt: now`. Pour tout projet à 2+ langues cibles, `getByUnit().first` renvoie donc une version de langue arbitraire (l'ordre sur `created_at` égaux est indéfini en SQLite). L'éditeur est pourtant scopé à un `languageId`/`projectLanguageId` précis.

```dart
final versionsResult = await versionRepo.getByUnit(unitId); ... final currentVersion = versions.first; ... await versionRepo.update(updatedVersion);
```

**Impact** : Dans tout projet multi-cibles, les éditions manuelles dans le champ cible de l'inspecteur (`onSave -> handleCellEdit`) et les suggestions TM appliquées écrasent silencieusement une AUTRE langue que celle affichée. La langue éditée semble inchangée tandis qu'une langue sœur est corrompue. L'entrée d'historique persistée et l'action d'annulation sont également enregistrées contre le mauvais `versionId`. Les projets monolingues ne sont pas affectés, ce qui rend le bug difficile à reproduire.

**Recommandation** : Résoudre la version avec la langue de l'éditeur : appeler `final projectLanguageId = await getProjectLanguageId();` puis récupérer via `versionRepo.getByUnitAndProjectLanguage(unitId: unitId, projectLanguageId: projectLanguageId)` (méthode déjà existante) dans `handleCellEdit` et `handleApplySuggestion` avant toute mutation. En défense en profondeur, donner aux versions par langue des `created_at` distincts (ou ordonner `getByUnit` de façon déterministe).

### L'import écrit le languageId brut dans project_language_id, produisant des versions orphelines invisibles à l'éditeur/export

fichier `lib/features/import_export/services/import_executor.dart:318-329` · catégorie data-integrity · confiance high

**Problème** : Lors de la création d'une nouvelle version, l'exécuteur assigne `projectLanguageId: settings.targetLanguageId` directement. Or `settings.targetLanguageId` est un id de langue, PAS un id de ligne `project_languages`. Le côté export prouve la sémantique attendue : il résout d'abord via `getByProjectAndLanguage(...)` puis requête par `projectLanguage.id`. L'import saute cette résolution, donc la colonne `project_language_id` reçoit une valeur qui ne correspond à aucun `project_languages.id`.

```dart
final newVersion = TranslationVersion(
  id: _uuid.v4(),
  unitId: unit.id,
  projectLanguageId: settings.targetLanguageId,  // <-- raw languageId, not project_languages.id
```

**Impact** : Les traductions importées sont écrites avec une clé étrangère invalide (`project_language_id`). Elles n'apparaissent pas dans l'éditeur et sont exclues de l'export — l'utilisateur voit un import « réussi » (`successCount` incrémenté, historique enregistré) mais les données sont effectivement perdues/orphelines. Affecte tout import CSV/JSON/Excel qui crée de nouvelles versions.

**Recommandation** : Résoudre l'id `project_language` une fois avant le traitement des lignes, exactement comme l'export : appeler `_projectLanguageRepository.getByProjectAndLanguage(settings.projectId, settings.targetLanguageId)` et passer `projectLanguage.id` à `_createNewVersion`. Injecter le `ProjectLanguageRepository` dans `ImportExecutor`. Faire échouer l'import avec une erreur claire si la ligne `project_language` n'existe pas.

## Élevé

### Intégrité des données

### importBatch laisse l'index FTS et le cache de vue obsolètes lors d'une annulation (lignes committées sans synchro index/cache)

fichier `lib/repositories/mixins/translation_version_batch_mixin.dart:464-521, 477-482, 523-603` · catégorie data-integrity · confiance high

**Problème** : Avec `disableTriggers=true` (>50 entités), `importBatch` DROP les triggers FTS-insert/update et cache en amont, puis écrit les lignes par lots. Le contrôle d'annulation (lignes 479-482) fait un `return` anticipé depuis le corps de la transaction. Comme la fonction retourne une valeur (sans lever d'exception), `executeTransaction` COMMITTE la transaction. Le bloc de reconstruction manuelle FTS/cache/progression (523-603) ne s'exécute qu'après la boucle d'écriture normale, donc il est entièrement sauté à l'annulation. Le bloc `finally` recrée les triggers mais ne synchronise pas rétroactivement les lignes déjà écrites.

**Impact** : Après l'annulation d'un gros import de pack, la vue d'éditeur (`translation_view_cache`) et la recherche plein texte (`translation_versions_fts`) deviennent silencieusement incohérentes avec les données réelles : les traductions importées semblent absentes dans la grille et sont introuvables, alors qu'elles existent. Persiste jusqu'à ce qu'une édition non liée retouche chaque ligne. Concerne uniquement les imports >50 entrées annulés en cours.

**Recommandation** : Sur le chemin d'annulation, soit (a) lever une exception pour forcer un rollback atomique de toutes les écritures, soit (b) exécuter la reconstruction FTS/cache/progression pour les lignes traitées avant de retourner. Le plus simple : remplacer le `return` anticipé par le lancement d'une `CancelledException` dédiée et la traiter comme « aucun changement » côté appelant.

### Les méthodes batch écrivent des timestamps en millisecondes dans des colonnes qui stockent des secondes Unix

fichier `lib/repositories/mixins/translation_version_batch_mixin.dart:300, 362, 475, 498, 602` · catégorie data-integrity · confiance high

**Problème** : Partout dans l'app, les colonnes `*_at` sont stockées en SECONDES Unix (`millisecondsSinceEpoch ~/ 1000`, triggers `strftime('%s','now')`). Mais dans ce mixin les deux chemins bulk calculent `final now = DateTime.now().millisecondsSinceEpoch;` SANS diviser par 1000, puis l'écrivent comme timestamp. À la ligne 498 `map['updated_at'] = now;` écrase la valeur en secondes fournie par l'appelant par des millisecondes pour chaque version UPDATE, et la ligne 602 écrit des ms dans `project_languages.updated_at`. Le commentaire de `pack_import_service.dart` documente explicitement cette classe de bug, pourtant le mixin la réintroduit.

**Impact** : Les versions mises à jour et leurs `project_languages` reçoivent des timestamps ~1000x dans le futur (an ~52000 interprété en secondes). Le tri par récence, l'ordre « récemment édité » et le filtre « Export outdated » de l'écran Projets sont corrompus pour tout projet touché par un apply TM >50 lignes (`upsertBatchOptimized`) ou un update d'import (`importBatch`).

**Recommandation** : Utiliser les secondes de façon cohérente : `final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;` dans les deux méthodes, conformément au reste du code. Ne conserver une valeur en millisecondes que là où un suffixe d'id en a besoin.

### deleteLanguage détruit la mémoire de traduction avant de vérifier que la langue peut réellement être supprimée

fichier `lib/features/settings/providers/language_settings_providers.dart:179-211` · catégorie data-integrity · confiance high

**Problème** : `deleteLanguage()` appelle d'abord `tmRepository.deleteByLanguageId(languageId)`, qui supprime définitivement toute ligne de TM où `source_language_id` OU `target_language_id` correspond. Seulement APRÈS, il appelle `repository.delete(languageId)`. Si la suppression de langue échoue alors sur une contrainte de clé étrangère (langue encore référencée par des projets), la branche err renvoie le message convivial « cette langue est utilisée dans un ou plusieurs projets » — mais les entrées de TM sont déjà irrémédiablement perdues alors que la langue n'a PAS été supprimée. Les deux opérations ne partagent pas de transaction.

```dart
final tmCleanupResult = await tmRepository.deleteByLanguageId(languageId);
if (tmCleanupResult.isErr) { ... }
final deleteResult = await repository.delete(languageId);
return deleteResult.when(
  ok: (_) { ... },
  err: (error) {
    ... 'This language is used in one or more projects. Remove it from all projects before deleting.'
```

**Impact** : Un utilisateur qui tente de supprimer une langue personnalisée encore attachée à un projet obtient une erreur indiquant que la suppression a été bloquée, alors que toutes ses entrées de mémoire de traduction (source et cible) pour cette langue ont déjà été effacées. Perte de TM silencieuse et irréversible déguisée en non-opération.

**Recommandation** : Inverser l'ordre : tenter d'abord `repository.delete(languageId)` et ne supprimer les entrées de TM qu'après succès, OU envelopper les deux opérations dans une seule transaction DB pour que la suppression de TM soit annulée si la suppression de langue échoue. Alternativement, pré-vérifier l'usage en projet avant de toucher la TM.

### La recherche de version existante ignore la langue cible ; peut écraser/fusionner la traduction d'une autre langue

fichier `lib/features/import_export/services/import_executor.dart:217-235` · catégorie data-integrity · confiance high

**Problème** : `_processVersion` appelle `getByUnit(unit.id)` qui renvoie TOUTES les versions de l'unité pour CHAQUE `project_language_id`, ordonnées `created_at DESC`. Il opère ensuite inconditionnellement sur `versionsResult.value.first`. Pour une unité ayant déjà des traductions en plusieurs langues (ex. français et allemand), importer des données françaises mettra à jour/fusionnera la version la plus récemment créée — possiblement l'allemande. Le même `.first` aveugle est utilisé dans `import_conflict_detector.dart` (lignes 97-102).

```dart
final versionsResult = await _versionRepository.getByUnit(unit.id);
if (versionsResult.isOk && versionsResult.value.isNotEmpty) {
  return await _updateExistingVersion(
    existingVersion: versionsResult.value.first,  // first across ALL languages
```

**Impact** : Importer pour une langue cible peut silencieusement écraser ou fusionner la traduction existante d'une autre langue, corrompant des données non liées. La détection de conflits compare aussi contre la mauvaise langue.

**Recommandation** : Utiliser `getByUnitAndProjectLanguage(unitId, resolvedProjectLanguageId)` (déjà présente, lignes 327-346) au lieu de `getByUnit(...).value.first`, après résolution de l'id `project_language`. Appliquer le même correctif dans `import_conflict_detector.dart`.

### Correctness

### La détection d'achèvement de publication par lot casse quand une ligne de statut steamcmd est scindée entre deux lectures stdout

fichier `lib/services/steam/workshop_publish_service_impl.dart:520-646` · catégorie correctness · confiance high

**Problème** : Dans `_runBatchProcess`, chaque événement de données stdout est décodé via `String.fromCharCodes(data)` et découpé en lignes indépendamment, sans tampon de report entre événements. L'achèvement n'est détecté QUE sur ces lignes par événement (`Success.`, `Item Updated`, `PublishFileID`, `Failed to update workshop item`, `ERROR!`). Le pipe OS ne garantit pas qu'une ligne arrive dans une seule lecture. Contrairement au chemin de publication unique qui re-scanne le buffer accumulé complet, le chemin batch n'a AUCUN repli sur buffer complet. Une ligne d'achèvement scindée n'est jamais reconnue, donc `completedInChunk` ne reçoit jamais l'index et `currentChunkPos` n'avance pas.

```dart
if (exitCode != 0) {
  final stderr = await stderrFuture;
  final error = RpfmOutputParser.parseErrorMessage(stderr);
  logger.warning('Failed to add .loc file: $error'); // continues, then returns Ok
}
```

**Impact** : Quand une ligne d'achèvement/succès est scindée entre deux lectures (plus probable sur disque lent / gros packs / machine chargée), l'élément qui vient de réussir n'est jamais marqué comme terminé. `currentChunkPos` reste figé, donc chaque élément suivant du chunk voit sa progression/succès/erreur attribués au mauvais index. Après la sortie du processus, tous les éléments non appariés — y compris ceux réellement publiés — sont signalés comme « steamcmd process terminated unexpectedly » et leurs Workshop IDs ne sont jamais sauvegardés en DB (la liste les affiche comme à republier). L'UI batch montre alors de fausses erreurs et une progression désalignée.

**Recommandation** : Maintenir un tampon de lignes persistant entre événements stdout : ajouter les octets décodés à un buffer, extraire uniquement les lignes complètes (terminées par `\r`/`\n`), conserver la ligne partielle de fin pour l'événement suivant, et vider le reste sur `onDone`. Appliquer la même chose à stderr. Ajouter une passe de réconciliation finale sur le buffer complet (`rawOutput`) après la sortie pour marquer tout élément dont `Success`/`PublishFileID` apparaît réellement.

### La recherche de texte cible référence des colonnes inexistantes (tv.language_code, tv.project_id, tv.file_name) — searchTranslationVersions échoue toujours

fichier `lib/services/search/utils/fts_query_builder.dart:82-118 (et _buildFilterClause 233-288)` · catégorie correctness · confiance high

**Problème** : `buildTranslationVersionsQuery` sélectionne `tv.language_code`, joint `LEFT JOIN languages l ON tv.language_code = l.code` et ordonne sur la table de base `translation_versions tv`. Mais la table `translation_versions` n'a PAS de colonne `language_code` — le code de langue ne se dérive que via `project_languages -> languages`. De plus, avec un `SearchFilter`, `_buildFilterClause` (préfixe `tv`) émet `tv.project_id IN (...)`, `tv.language_code IN (...)`, `tv.file_name IN (...)` — aucune de ces colonnes n'existe sur `translation_versions` (`project_id` et `file_name` sont sur `translation_units`). Chaque requête lève une erreur SQLite « no such column ».

```dart
SELECT ... tv.language_code, l.name as language_name, ...
FROM translation_versions_fts fts
INNER JOIN translation_versions tv ON fts.version_id = tv.id
...
LEFT JOIN languages l ON tv.language_code = l.code   // tv.language_code does not exist
```

**Impact** : La recherche de texte cible (`SearchScope.target -> searchTranslationVersions`) est totalement non fonctionnelle : chaque appel lève une `DatabaseException` et retourne `Err`. Pire, `searchAll()` appelle `searchTranslationVersions` et avale silencieusement l'`Err` dans sa boucle de combinaison (`if (result.isOk)`), donc les scopes « All Fields » et « Source & Target » ne renvoient JAMAIS de correspondances de texte traduit, sans aucune erreur visible — les résultats apparaissent silencieusement incomplets.

**Recommandation** : Dériver `language_code` via la chaîne de jointures : joindre `project_languages pl ON tv.project_language_id = pl.id` puis `languages l ON pl.language_id = l.id`, sélectionner `l.code AS language_code`. Pour les filtres sur versions, router les prédicats `project_id`/`file_name`/langue vers les bonnes tables (`tu.project_id`, `tu.file_name`, `l.code`), ou construire une clause de filtre spécifique aux versions. Ajouter un test d'intégration exécutant une recherche scope cible avec et sans `SearchFilter` contre le schéma réel.

## Moyen

### Intégrité des données

### La normalisation TM agressive fait collisionner des chaînes sources distinctes sur le hash de correspondance exacte et applique automatiquement de mauvaises traductions

fichier `lib/services/translation_memory/tm_matching_service.dart:68-131` · catégorie data-integrity · confiance high

**Problème** : `findExactMatch` calcule le hash de recherche comme `sha256(_normalizer.normalize(sourceText))`. Les `NormalizationOptions` par défaut activent `removeMarkup=true`, `lowercase=true` et `normalizePunctuation=true`. Le même `normalize()` est utilisé à l'ÉCRITURE des entrées. Résultat : `Attack` et `ATTACK` (entre autres) hashent vers la même valeur (`attack`). Une recherche exacte renvoie alors une entrée TM dont la vraie source ne différait que par la casse/markup, et `findExactMatch` la marque avec `exactMatchSimilarity` (1.0), `matchType=exact`, `autoApplied=true`. `TmLookupHandler` écrit ensuite la cible verbatim avec `status=translated`, sans relecture.

**Impact** : Des traductions sont auto-appliquées (et persistées comme `translated`, non `needsReview`) pour des chaînes sources qui ne sont PAS réellement identiques à l'entrée TM — seulement égales après minusculisation/strip-markup/collapse-ponctuation. Pour du texte Total War, la casse et les balises `[[col:...]]` sont signifiantes ; la cible stockée peut donc porter une mauvaise casse ou un markup absent/incohérent. Deux sources réellement différentes fusionnent aussi en TM en partageant un `sourceHash`.

**Recommandation** : Calculer le hash de correspondance exacte à partir d'une normalisation bien plus conservatrice (par ex. uniquement Unicode NFC + trim de fin, en préservant casse, markup et ponctuation), en réservant la normalisation agressive au seul scoring de similarité flou. Garder le hash d'écriture identique au hash de lecture. Si une correspondance exacte insensible à la casse est voulue, traiter ces correspondances comme floues/`needsReview` plutôt que 100% auto-appliquées.

### L'export TMX écrit des IDs de langue DB internes (lang_xx) comme xml:lang quand la langue cible est auto-détectée

fichier `lib/services/translation_memory/tm_import_export_service.dart:108-168` · catégorie data-integrity · confiance high

**Problème** : Quand `targetLanguageCode` est null, `exportToTmx` lit une ligne et fixe `tgtLang = peekResult.value.first.targetLanguageId`. Or `targetLanguageId` est l'id du dépôt au format `lang_<code>`. Cette valeur brute est passée telle quelle à `exportToTmxStreaming(targetLanguage: tgtLang)`, qui l'écrit verbatim comme attribut `xml:lang="lang_fr"` ; aucun `stripLanguagePrefix`. Le chemin de la langue source est aussi incohérent : la branche explicite utilise le code nu (`fr`) tandis que la DB stocke `lang_fr`.

**Impact** : Les exports auto-détectés produisent un TMX dont `xml:lang` est une balise non standard (`lang_fr`) que d'autres outils TAO rejettent ou mésinterprètent. Le ré-import d'un tel fichier dans TWMT stocke un `targetLanguageId` incohérent, qui échoue ensuite à se résoudre via `LanguageRepository.getByCode`, rendant les entrées importées non appariables.

**Recommandation** : Normaliser les valeurs de langue en codes ISO nus avant de les écrire dans le TMX, par ex. `tgtLang = stripLanguagePrefix(peekResult.value.first.targetLanguageId)`. S'assurer que les branches explicite et auto-détectée émettent la même forme de code, et que `persistTmxEntries` passe les codes entrants par `normalizeLanguageId`.

### L'import glossaire CSV/Excel écrit les entrées sous un code de langue cible arbitraire, les orphelinant de la vraie langue du glossaire

fichier `lib/features/glossary/widgets/glossary_import_dialog.dart:29, 59-67, 298-303` · catégorie data-integrity · confiance high

**Problème** : Le dialogue d'import laisse l'utilisateur choisir un `target_language_code` libre dans une liste codée en dur (défaut `'fr'`) et le passe verbatim à `importCsv`. Or chaque glossaire est strictement scopé à une paire `(game_code, target_language_id)`. Les entrées importées sont stockées avec le code choisi, sans vérifier qu'il correspond à la vraie langue cible du glossaire. Les lectures filtrent par code de langue cible (`LOWER(target_language_code)=LOWER(?)`).

```dart
String _targetLanguage = 'fr';
...
await ref.read(glossaryImportStateProvider.notifier).importCsv(
      glossaryId: widget.glossaryId,
      filePath: _selectedFilePath!,
      targetLanguageCode: _targetLanguage,
      skipDuplicates: _skipDuplicates,
    );
```

**Impact** : Si le glossaire est par ex. allemand mais que l'utilisateur laisse le défaut `'fr'`, les termes importés sont écrits avec `target_language_code='fr'`. Ils ne sont jamais appariés/substitués lors de la traduction pour la vraie langue du glossaire, ni envoyés à la synchro DeepL. L'utilisateur voit une bannière de succès alors que les termes sont effectivement orphelins pour le chemin de matching (ils restent toutefois visibles dans la datagrid non filtrée par langue).

**Recommandation** : Ne pas demander la langue dans le dialogue d'import. Résoudre la langue cible du glossaire depuis son `target_language_id` (charger le `Glossary`, retrouver le code) et la passer à l'appel d'import, ou au minimum valider le code choisi contre la langue du glossaire et rejeter/corriger les incohérences.

### La détection de doublons est sensible à la casse et non trimée, contredisant le matching/validation insensibles à la casse partout ailleurs

fichier `lib/repositories/glossary_repository.dart:353-365` · catégorie data-integrity · confiance high

**Problème** : `findDuplicateEntry` apparie avec `source_term = ?` (exact, sensible casse) et `target_language_code = ?` (casse exacte). `addEntry`, `importFromCsv/Tbx/Excel` s'appuient là-dessus pour rejeter les doublons. Mais partout ailleurs les termes sont traités sans casse : `getEntriesByGlossary` utilise `LOWER(...)`, `validateGlossary` clé sur `${targetLanguageCode}:${sourceTerm.toLowerCase()}`, le dédoublonnage de stats utilise `toLowerCase`, et `GlossaryMatcher` apparie sans casse par défaut. Ainsi `Sword`/`sword` passent le contrôle de doublon et sont insérés en lignes distinctes.

```dart
where: 'glossary_id = ? AND target_language_code = ? AND source_term = ?',
whereArgs: [glossaryId, targetLanguageCode, sourceTerm],
```

**Impact** : Les doublons variant en casse s'accumulent silencieusement à l'import/ajout. Ils sont ensuite signalés comme doublons par `validateGlossary`/`getGlossaryStats`, les deux variantes produisent des correspondances/substitutions, alors que `skipDuplicates` semble fonctionner. La fusion de migration (`_mergeEntriesDedup`) utilise `LOWER(TRIM(...))` et en collapse certains plus tard, causant des comptes incohérents pré/post migration.

**Recommandation** : Rendre `findDuplicateEntry` cohérent avec le reste : comparer `LOWER(TRIM(source_term)) = LOWER(TRIM(?))` et `LOWER(target_language_code) = LOWER(?)`. `addEntry` trim déjà `sourceTerm` avant l'appel, mais la comparaison SQL doit normaliser la casse pour réellement attraper les doublons.

### trg_update_project_language_progress recréé sans le bump de projects.updated_at, dégradant définitivement le trigger

fichier `lib/repositories/translation_version_repository.dart:457-475 (et schema.sql:845-868)` · catégorie data-integrity · confiance high

**Problème** : La définition canonique de `trg_update_project_language_progress` met à jour `project_languages.progress_percent` ET propage le changement vers `projects.updated_at`. `clearBatch` DROP ce trigger pour les lots >50 et, dans son `finally`, le recrée inline SANS la seconde instruction `UPDATE projects SET updated_at...`. Il utilise aussi un `CREATE TRIGGER` simple (pas `IF NOT EXISTS`). Le helper partagé `_recreateTriggers` (utilisé par `acceptBatch`/`rejectBatch`/`updateValidationBatch`) inclut bien le bump ; seul `clearBatch` diverge. De plus `clearBatch` n'appelle jamais `_bumpProjectsUpdatedAtForVersions`.

**Impact** : Après le premier clear-batch de >50 versions dans une session DB, la définition vivante du trigger perd définitivement la maintenance de `projects.updated_at`. Dès lors, les éditions de statut sur une ligne ne bumpent plus `projects.updated_at`, donc le filtre rapide « Export outdated » de l'écran Projets cesse de détecter les éditions pour les projets concernés jusqu'au redémarrage de l'app — et les opérations de clear ne marquent jamais le projet comme à exporter.

**Recommandation** : Faire en sorte que `clearBatch` réutilise le helper partagé `_recreateTriggers` au lieu d'une définition inline, et ajouter l'appel `await _bumpProjectsUpdatedAtForVersions(txn, versionIds, now);` (comme le font déjà `acceptBatch`/`rejectBatch`/`updateValidationBatch`). Tous les triggers recréés par les méthodes batch resteront identiques à `schema.sql`.

### L'import JSON coerce les valeurs null/numériques via toString(), transformant les null en la chaîne littérale "null"

fichier `lib/features/import_export/services/utils/import_file_reader.dart:50-58` · catégorie data-integrity · confiance medium

**Problème** : La branche JSON mappe chaque valeur avec `v.toString()`. Une valeur null JSON devient la chaîne littérale `"null"`, les nombres/booléens deviennent leur forme texte. En aval, l'exécuteur ne traite une valeur comme absente que si `row[targetColumn] == null` (null Dart), ce qui n'arrive jamais ici — donc un `{"target_text": null}` JSON est importé comme la traduction de 4 caractères `null`.

```dart
.map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
```

**Impact** : Les imports JSON avec valeurs cible nulles écrivent le texte littéral `"null"` comme traduction (marquée `status=translated` car non vide), corrompant silencieusement le contenu. Les clés/valeurs numériques sont aussi stringifiées, ce qui peut désaligner les clés existantes. (Une clé cible absente est en revanche correctement traitée comme null.)

**Recommandation** : Sauter les valeurs nulles ou les mapper explicitement en chaînes vides, par ex. `MapEntry(k.toString(), v == null ? '' : v.toString())`, et décider délibérément si les clés absentes doivent être omises du map plutôt que coercées.

### applyModifiedSourceTexts met à jour le texte source et réinitialise les versions en deux transactions séparées (non atomique)

fichier `lib/services/mods/mod_update_analysis_service.dart:347-380` · catégorie data-integrity · confiance high

**Problème** : `applyModifiedSourceTexts` effectue deux opérations DB indépendantes NON enveloppées dans une seule transaction : (1) `updateSourceTexts(...)` écrit le nouveau `source_text` dans sa propre transaction, puis (2) `resetStatusForUnitKeys(...)` lance un UPDATE séparé pour remettre `status` à `pending`. Aucune transaction partagée ni rollback ne lie les deux.

```dart
final updateResult = await _unitRepository.updateSourceTexts(...);
if (updateResult.isErr) { return Err(...); }
// ... separate, non-atomic call:
final resetResult = await _versionRepository.resetStatusForUnitKeys(...);
```

**Impact** : Si le processus crashe ou si l'étape 2 échoue après l'étape 1, le projet reste incohérent : `source_text` reflète le nouveau texte amont tandis que les versions gardent l'ancien statut (`done`/`translated`) et le texte traduit obsolète. Comme l'unité n'est plus détectée comme modifiée (son `source_text` est déjà à jour), l'étape 2 ne se relance jamais — l'incohérence est permanente. Le traducteur n'est jamais invité à re-relire la chaîne modifiée, et un export peut livrer une traduction qui ne correspond plus à sa source. S'exécute automatiquement à chaque scan Workshop.

**Recommandation** : Envelopper les deux écritures dans une seule `DatabaseService.transaction` pour que la mise à jour de `source_text` et la réinitialisation de statut committent ou rollback ensemble. Passer la `txn` aux helpers batch (ou ajouter des variantes acceptant une `txn`).

### ProcessService capture la sortie en annulant les souscriptions stdout/stderr immédiatement à la sortie, tronquant la sortie

fichier `lib/services/shared/process_service.dart:88-122, 204-238` · catégorie data-integrity · confiance medium

**Problème** : `run()` et `runWithStreaming()` attendent `process.exitCode` puis, dans le `finally`, annulent immédiatement les `StreamSubscription` stdout/stderr. La complétion de `process.exitCode` ne garantit que la fin du processus OS ; les pipes Dart peuvent encore avoir des données bufferisées non livrées. Annuler les souscriptions avant le drainage complet jette la fin de la sortie.

```dart
exitCode = await process.exitCode;
...
} finally {
  await stdoutSub.cancel();   // streams may not be fully drained yet
  await stderrSub.cancel();
  _activeProcesses.remove(pid);
}
```

**Impact** : Les appelants qui parsent le stdout capturé (`runSimple`, `isExecutableAvailable`, détection/version steam) peuvent recevoir par intermittence une sortie tronquée, causant une mauvaise détection de version, des messages d'erreur manqués, ou des échecs mal classés. La course est dépendante du timing et difficile à reproduire.

**Recommandation** : Drainer les flux jusqu'à complétion avant de lire les buffers : convertir les écouteurs en futures (`subscription.asFuture()` ou `process.stdout.transform(utf8.decoder).join()`) et les attendre avec `process.exitCode` via `Future.wait([...])` avant de construire le `ProcessResult`. N'annuler les souscriptions qu'après leur complétion.

### L'auto-fix de variables manquantes ajoute les placeholders en fin de chaîne, produisant des chaînes de jeu cassées

fichier `lib/services/validation/translation_validation_service.dart:205-222` · catégorie data-integrity · confiance high

**Problème** : Quand la traduction manque des variables présentes dans la source (`{0}`, `%s`, `${var}`), le problème est signalé ERROR et marqué `autoFixable` avec `autoFixValue = '$translatedText ${missingVariables.join(' ')}'`. Le « fix » concatène simplement les tokens manquants en fin de texte. Pour les chaînes Total War, la position du placeholder est sémantiquement signifiante (interpolée à l'exécution). `applyAllAutoFixes()` applique ceci automatiquement.

```dart
autoFixable: true,
autoFixValue: '$translatedText ${missingVariables.join(' ')}',
```

**Impact** : Les utilisateurs appliquant l'auto-fix (surtout « tout corriger ») obtiennent silencieusement des traductions corrompues avec des placeholders pendant en fin de chaîne. La sortie est exportée dans des fichiers `.loc`/`.pack` prêts pour le jeu, donc la corruption arrive jusqu'à l'UI du jeu.

**Recommandation** : Ne pas fournir d'`autoFixValue` qui ajoute aveuglément les placeholders. Soit marquer `missingVariables` comme `autoFixable=false` (rapport seul), soit implémenter un fix positionnel qui réinsère chaque placeholder à sa position source. Au minimum, exclure ce fix de `applyAllAutoFixes`.

### Correctness

### La vérification d'équilibre de markup réordonne les balises par type, masquant de vrais déséquilibres de balises entrelacées

fichier `lib/services/translation/utils/text_parser_utils.dart:78-110` · catégorie correctness · confiance medium

**Problème** : `extractMarkupTags` ajoute les balises groupées par TYPE plutôt qu'en ordre du document : d'abord toutes les XML (`<...>`), puis toutes les double-bracket (`[[...]]`), puis les single-bracket BBCode. `areTagsBalanced` est une vérification de nesting basée sur une pile qui dépend de l'ordre du document. Comme la liste est réordonnée, une chaîne mal imbriquée mais groupée par type comme `[[col:red]]<b>text[[/col]]</b>` est signalée équilibrée alors que l'ordre réel entrelacé est malformé.

**Impact** : La validation de déséquilibre de markup donne de mauvais résultats pour les chaînes mêlant XML et balises crochet : de vrais déséquilibres (qui peuvent casser le rendu en jeu) passent silencieusement, et le groupement par type peut aussi inverser un verdict correct. Cela affaiblit une vérification que l'app annonce comme protégeant l'intégrité des balises.

**Recommandation** : Faire émettre par `extractMarkupTags` les balises en ordre du document (collecter toutes les correspondances avec leur offset de début sur les trois patterns, puis trier par index de début avant de retourner) afin que `areTagsBalanced` opère sur la vraie séquence.

### La branche d'ajout .loc héritée et les échecs TMX/loc reportent un succès d'export malgré un échec total

fichier `lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:111-160, 228-239` · catégorie error-handling · confiance high

**Problème** : Dans la branche de repli `.loc` héritée de `createPack`, un code de sortie RPFM non nul pour un fichier ajouté ne fait que journaliser un warning et la boucle continue. Après la boucle, la méthode ne vérifie que `File(outputPackPath).exists()` (le pack vide créé à l'étape 1 existe toujours) et retourne `Ok`. Si RPFM rejette tous les fichiers, `createPack` retourne `Ok` avec un pack essentiellement vide. La branche TSV, elle, retourne `Err` au premier échec — sémantiques d'échec incohérentes.

```dart
if (exitCode != 0) {
  final stderr = await stderrFuture;
  final error = RpfmOutputParser.parseErrorMessage(stderr);
  logger.warning('Failed to add .loc file: $error'); // continues, then returns Ok
}
```

**Impact** : L'utilisateur obtient un export « terminé » et une ligne d'historique d'export pour un pack ne contenant aucune traduction utilisable, sans erreur remontée. Perte de données silencieuse déguisée en succès. (Note : ce chemin de repli n'est emprunté que lorsque l'entrée ne contient aucun `.tsv` — une condition héritée/limite, pas le chemin d'export principal.)

**Recommandation** : Suivre les échecs par fichier dans la branche héritée et retourner `Err` (ou au moins un résultat d'échec partiel) quand aucun fichier n'a été ajouté avec succès ; après la boucle, vérifier que le pack contient le nombre attendu d'entrées loc (via `listPackContents`) plutôt que la simple existence du fichier.

### La substitution de glossaire fait un replaceAll global insensible à la position par correspondance, causant des substitutions erronées et en cascade

fichier `lib/services/glossary/utils/glossary_matcher.dart:212-240` · catégorie correctness · confiance medium

**Problème** : `applySubstitutions` trie les correspondances par position de début décroissante « pour éviter les décalages d'index », mais appelle ensuite pour chaque correspondance `result.replaceAll(RegExp(escape(match.matchedText), ...), match.entry.targetTerm)`. `replaceAll` remplace TOUTES les occurrences dans toute la chaîne, donc le tri décroissant n'a aucun sens. (1) Le pattern de remplacement n'a aucun ancrage de limite de mot, donc un terme source `cat` se substitue dans `category`. (2) Chaque passe réécrit toute la chaîne et la sortie d'une substitution antérieure peut correspondre au pattern d'une suivante, causant des substitutions en cascade.

```dart
final sourceTermEscaped = RegExp.escape(match.matchedText);
final pattern = RegExp(
  sourceTermEscaped,
  caseSensitive: match.entry.caseSensitive,
);
result = result.replaceAll(pattern, match.entry.targetTerm);
```

**Impact** : Le post-traitement de « substitution » de glossaire peut corrompre silencieusement les chaînes traduites : remplacements partiels de mot, doubles substitutions, et remplacements d'occurrences non liées. Pour du texte `.loc` de jeu, cela produit une sortie altérée. (Note : `applySubstitutions` n'a pas de chemin appelant dans le pipeline de traduction/export actuel.)

**Recommandation** : Appliquer les substitutions positionnellement sur les plages réelles de correspondance (reconstruction de chaîne par substring + remplacement, comme `highlightMatches`), ou au minimum ancrer le pattern avec des limites de mot et se protéger contre la re-correspondance du texte déjà substitué. Supprimer le commentaire trompeur sur le tri décroissant.

### WorkshopPublishServiceImpl est un singleton lazy partagé avec un état de run mutable non synchronisé

fichier `lib/services/steam/workshop_publish_service_impl.dart:55-61, 276-283, 887-891` · catégorie concurrency · confiance medium

**Problème** : Le service est enregistré comme singleton lazy mais détient un état mutable par opération : `_isCancelled`, `_currentProcess`, et deux `StreamController` broadcast. `publish()` remet `_isCancelled = false` dans son `finally` et `cancel()` met `_isCancelled = true` et `_currentProcess = null`. Le notifier de publication unique et celui de batch résolvent la MÊME instance. Si un second consommateur touche le service pendant qu'une opération est en cours (par ex. un `cancel()` parasite depuis le `silentCleanup` d'un écran disposé), il mute les mêmes champs sans garde d'appartenance d'opération.

**Impact** : Interférence inter-écrans : un `cancel` ou un dispose sur un écran de publication peut écraser l'annulation d'une publication en cours non liée, ou tuer le processus steamcmd d'un batch en cours. Échecs difficiles à reproduire, dépendants de l'état, plutôt qu'un crash déterministe.

**Recommandation** : Soit enregistrer le service de publication comme factory (instance fraîche par opération), soit sérialiser les opérations avec une garde/mutex explicite et cesser de muter `_isCancelled`/`_currentProcess` partagés depuis `cancel()` sans vérifier quelle opération les possède. Capturer le `Process` dans une variable locale dans chaque méthode de run et passer un jeton d'annulation scopé à l'opération plutôt que de s'appuyer sur le champ partagé.

### La recherche regex utilise l'opérateur SQLite REGEXP jamais enregistré — searchWithRegex échoue toujours

fichier `lib/services/search/utils/regex_query_builder.dart:44-53, 86-91` · catégorie correctness · confiance high

**Problème** : `buildRegexQuery` émet `tu.source_text REGEXP '$pattern'` et un CASE utilisant REGEXP. SQLite (y compris `sqflite_common_ffi`) ne fournit PAS de fonction REGEXP intégrée — elle doit être enregistrée via une fonction personnalisée. Un grep sur tout le dépôt montre que REGEXP/`createFunction`/`registerFunction` n'est jamais enregistré sur la connexion DB. Toute recherche regex exécute donc du SQL contenant une fonction inconnue et SQLite lève « no such function: REGEXP ».

```dart
CASE
  WHEN tu.source_text REGEXP '$pattern' THEN 'source_text'
  ELSE 'translated_text'
END as matched_field
...
WHERE $regexCondition  // REGEXP never registered on the connection
```

**Impact** : Chaque recherche regex (`SearchOptions.useRegex == true`) échoue avec une `SearchDatabaseException`. Dans le provider UI, l'erreur est capturée et convertie en résultats vides, donc la fonctionnalité regex retourne silencieusement rien pour toutes les entrées.

**Recommandation** : Enregistrer une fonction REGEXP sur la connexion SQLite à l'ouverture (`sqflite_common_ffi` supporte `createFunction` via l'API sqlite3 sous-jacente), ou supprimer/désactiver le chemin de recherche regex tant qu'il n'est pas soutenu par une vraie implémentation. Ajouter un test exécutant une recherche regex de bout en bout contre la vraie DB.

### Les guillemets doubles de recherche par phrase sont échappés, corrompant les requêtes phrase FTS5

fichier `lib/services/search/utils/fts_query_builder.dart:362-367` · catégorie correctness · confiance medium

**Problème** : Quand `SearchOptions.phraseSearch` est actif, le provider enveloppe le texte en `'"$ftsQuery"'` pour former une phrase FTS5. `_sanitizeFtsQuery` fait alors `query.replaceAll('"','""')`, doublant chaque guillemet double. Le MATCH est interpolé dans des guillemets simples (`'$sanitizedQuery'`), donc le doublage n'est PAS nécessaire pour la sécurité SQL et change l'expression FTS5 : `"cavalry unit"` devient `""cavalry unit""`, que FTS5 parse comme une phrase vide suivie de tokens.

```dart
var sanitized = query
    .replaceAll('"', '""')  // Escape double quotes  <-- corrupts FTS5 phrases
    .replaceAll("'", "''")
    .trim();
```

**Impact** : La recherche de phrase exacte renvoie de mauvais résultats au lieu de la correspondance de phrase demandée. Les utilisateurs activant « recherche par phrase » obtiennent une sortie incorrecte.

**Recommandation** : Ne pas échapper `"` par doublage ici. Dans un littéral SQL entre guillemets simples, seul le guillemet simple doit être doublé ; les guillemets doubles FTS5 délimitant les phrases doivent être préservés. Supprimer l'étape `.replaceAll('"','""')` (ou n'échapper que les guillemets simples), et ajouter des tests pour les requêtes phrase.

### Les correspondances et surlignages FTS cible/TM débordent dans validation_issues / la mauvaise colonne

fichier `lib/services/search/utils/fts_query_builder.dart:94-118, 153-169` · catégorie correctness · confiance medium

**Problème** : `translation_versions_fts` indexe à la fois `translated_text` (col 0) et `validation_issues` (col 1). `buildTranslationVersionsQuery` utilise un MATCH non qualifié, donc une requête correspond aussi dans le JSON `validation_issues`, retournant des faux positifs de « texte traduit ». Pour la mémoire de traduction, le MATCH couvre `source_text`(0) et `translated_text`(1) mais `snippet()` est codé en dur sur la colonne 1, donc une correspondance trouvée uniquement dans `source_text` produit un surlignage vide/incorrect.

```dart
WHERE translation_versions_fts MATCH '$sanitizedQuery' // also matches validation_issues column
...
snippet(translation_memory_fts, 1, ...) // always col 1 even if match was in source_text
```

**Impact** : La recherche de texte cible fait remonter des entrées ne correspondant qu'à des chaînes internes de validation (que l'utilisateur n'a jamais saisies/vues), et les surlignages TM pointent vers la mauvaise colonne. Résultats confus et peu fiables ; principalement cosmétique à modéré.

**Recommandation** : Contraindre le MATCH à la colonne voulue via la syntaxe de colonne FTS5 (par ex. `{translated_text} : <query>`) afin d'exclure `validation_issues` de la recherche utilisateur. Pour la TM, choisir la colonne du snippet selon la colonne qui a matché, ou générer des surlignages par colonne.

### Performance

### addNewUnits émet une requête getByKey N+1 plus une transaction par unité pour chaque nouvelle clé

fichier `lib/services/mods/mod_update_analysis_service.dart:444-523` · catégorie performance · confiance high

**Problème** : Pour chaque nouvelle unité, `addNewUnits` exécute un SELECT `getByKey` séparé puis ouvre une `DatabaseService.transaction` individuelle qui insère l'unité plus une version par langue de projet. Aucun batching : un mod introduisant N nouvelles clés produit N SELECTs + N transactions, chacune avec (1 + nombre de langues) INSERTs. Le contrôle d'existence `getByKey` est aussi redondant car les inserts utilisent déjà `ConflictAlgorithm.abort` et ces clés ont été classées « nouvelles » précisément parce qu'absentes.

```dart
for (final newUnit in analysis.newUnitsData) {
  final existingResult = await _unitRepository.getByKey(projectId, newUnit.key);
  if (existingResult.isOk) { ... continue; }
  ...
  await DatabaseService.transaction((txn) async { ... });
}
```

**Impact** : Les gros mods (overhaul Total War, souvent des milliers de clés) déclenchent des milliers d'allers-retours séquentiels sur la connexion SQLite FFI lors d'un scan auto-appliqué, sur le chemin de l'isolate qui pilote l'UI. Les scans Workshop semblent lents / figés quand un gros mod fraîchement mis à jour ajoute beaucoup de clés.

**Recommandation** : Supprimer le contrôle `getByKey` par unité (s'appuyer sur `ConflictAlgorithm.abort` / un insert batché) et batcher les inserts : collecter unités et versions et les insérer en une seule transaction avec des INSERTs multi-lignes (à l'image du batching déjà utilisé dans `updateSourceTexts`/`reactivateByKeys`). Au minimum, déplacer toute la boucle dans une seule transaction.

### Gestion d'état

### Le toggle de case à cocher par ligne dans la grille d'import de pack ne repeint pas la ligne (notifyListeners manquant)

fichier `lib/features/translation_editor/widgets/pack_import_dialog.dart:85-98, 721-724` · catégorie state-management · confiance high

**Problème** : Le champ `selectedKeys` de la source de données est la même référence de `Set` que `_selectedKeys` du dialogue. Le callback `onSelectionChanged` par ligne mute `_selectedKeys` et appelle `setState`, mais n'appelle jamais `_dataSource.updateSelection(...)`/`notifyListeners()`. Un `setState` parent reconstruit le widget `SfDataGrid` mais Syncfusion ne réexécute PAS `buildRow` sauf si le `DataGridSource` notifie. `_toggleSelectAll` appelle correctement `_dataSource?.updateSelection(_selectedKeys)`.

```dart
onSelectionChanged: (key, selected) {
  setState(() {
    if (selected) { _selectedKeys.add(key); } else { _selectedKeys.remove(key); }
  });
  // missing: _dataSource?.updateSelection(_selectedKeys);
},
```

**Impact** : L'utilisateur coche/décoche une seule ligne et la case dans la grille semble ne pas réagir (seul le compteur de pied de page bouge). La sélection par ligne paraît cassée et peut conduire à importer le mauvais sous-ensemble d'entrées car les coches visibles ne correspondent plus à `_selectedKeys`.

**Recommandation** : Dans le closure `onSelectionChanged`, après avoir muté `_selectedKeys`, appeler `_dataSource?.updateSelection(_selectedKeys)` à l'intérieur du `setState`, comme le fait `_toggleSelectAll`, afin que la grille repeigne la ligne basculée.

### Concurrence

### L'analyse de conflits n'a pas de jeton de requête ; des changements de sélection rapides peuvent laisser une analyse obsolète

fichier `lib/features/pack_compilation/providers/compilation_conflict_providers.dart:25-41` · catégorie concurrency · confiance medium

**Problème** : `CompilationConflictAnalysis.analyze` met `AsyncLoading`, attend `service.analyzeConflicts(...)`, puis écrit inconditionnellement le résultat dans `state`. Aucun jeton de génération/requête. L'écran déclenche ceci (non attendu) à chaque changement de `(selectedProjectIds, selectedLanguageId)`. Si l'utilisateur bascule des projets rapidement, deux appels `analyze` concurrents s'exécutent ; celui dont la requête DB finit en DERNIER gagne, pas nécessairement celui de la dernière sélection.

```dart
Future<void> analyze({...}) async {
  state = const AsyncLoading();
  final service = ref.read(compilationConflictServiceProvider);
  final result = await service.analyzeConflicts(...);
  result.when(
    ok: (analysis) => state = AsyncData(analysis),
    err: (error) => state = AsyncError(error, StackTrace.current),
  );
}
```

**Impact** : Les conflits affichés (et les IDs positionnels `conflict_0`, `conflict_1`...) peuvent correspondre à une sélection de projets plus ancienne que l'actuelle. Comme les résolutions sont appariées par ces IDs positionnels, un utilisateur peut résoudre des conflits qui ne correspondent plus à la sélection courante, et `_buildExcludedKeysByProject` exclut alors les mauvaises clés à la génération.

**Recommandation** : Capturer un id de requête monotone croissant (ou le tuple projectIds/languageId) avant l'await, et après l'await, écarter le résultat si une requête plus récente a démarré (ou si la sélection courante ne correspond plus à `analyzedProjectIds`/`languageId`).

### Gestion d'erreurs

### Une erreur getByKey traitée comme « non trouvé », masquant les échecs DB et risquant un insert de clé en double

fichier `lib/features/import_export/services/import_executor.dart:144-166` · catégorie error-handling · confiance high

**Problème** : `_processRow` traite `unitsResult.isErr` comme « l'unité n'existe pas, en créer une nouvelle ». Mais `getByKey` retourne `Err` à la fois pour le cas « non trouvé » ET pour toute vraie erreur de base de données (DB verrouillée, ligne malformée, I/O), car `executeQuery` enveloppe tout `throw` en `Err`. Sur une erreur DB transitoire pour une clé qui existe réellement, le code procède à `_createNewUnit` et appelle `insert` avec le même `(project_id, key)`. Le détecteur de conflits a le problème inverse : sur `Err` il retourne null, sautant silencieusement le signalement de conflit.

```dart
if (unitsResult.isErr) {
  final createResult = await _createNewUnit(...);  // assumes 'not found' on ANY error
```

**Impact** : Les erreurs DB durant l'import sont silencieusement réinterprétées comme « nouvelle unité », menant à des tentatives d'insert parasites et des messages d'erreur trompeurs au lieu de remonter le vrai échec. La détection de conflits peut sous-signaler les conflits lorsqu'une lecture échoue transitoirement.

**Recommandation** : Distinguer « non trouvé » d'une « vraie erreur ». Soit ajouter un type de résultat/exception « non trouvé » dédié (ou un `findByKey` retournant `Result<TranslationUnit?, ...>`) et ne créer une nouvelle unité que quand la lecture n'a définitivement rien trouvé ; propager les vraies erreurs DB comme erreurs de ligne plutôt que de les avaler.

### Le filtre de langue source compare des codes de pack jeu à des codes de langue DB, laissant la source sélectionnable comme cible de traduction (ex. chinois→chinois)

fichier `lib/features/game_translation/widgets/create_game_translation/step_select_targets.dart:90-94` · catégorie data-integrity · confiance high

**Problème** : L'étape 2 construit la liste des langues cibles en excluant la source via `lang.code.toLowerCase() != sourceCode`, où `sourceCode` est extrait du nom de fichier du pack (`local_xx.pack`). Ces codes de fichier suivent le schéma Total War (`cn`, `br`, `jp`, `kr`, `cz`, `tw`...) tandis que la table `languages` seedée utilise des codes ISO (`en`, `de`, `zh`...). Pour un pack dont le code de fichier diffère du code DB — ex. `local_cn.pack` (chinois) — la comparaison `'zh' != 'cn'` est vraie, donc la langue source n'est PAS filtrée et apparaît sélectionnable. Aucune garde de second niveau : `_createProject` insère chaque cible sans exclusion de source.

```dart
final sourceCode =
    state.selectedSourcePack?.languageCode.toLowerCase();
final availableLanguages = languages
    .where((lang) => lang.code.toLowerCase() != sourceCode)
    .toList();
```

**Impact** : Un utilisateur choisissant un pack source non anglais peut sélectionner la même langue comme cible et créer un projet qui « traduit » une langue vers elle-même, gaspillant du coût LLM/DeepL et créant une ligne `project_language` corrompue de même langue. Empoisonne aussi le suffixe de nom de projet et l'auto-provisioning de glossaire. (Avec les données seedées actuelles, la collision n'est réellement exploitable que pour le chinois — pack `cn`/`tw` vs DB `zh`.)

**Recommandation** : Filtrer la liste des cibles via une identité de langue stable, pas le code de nom de fichier brut. Résoudre le pack source en sa `Language` DB (mapper code de pack -> code DB) et exclure par `language.id`. Ajouter une garde défensive dans `_createProject` qui retire/bloque toute cible dont l'id égale l'id de langue source résolu avant l'insertion.

### Les écouteurs de synchro de défilement bidirectionnelle se battent quand les deux panneaux de diff ont des hauteurs différentes

fichier `lib/features/translation/widgets/version_comparison_dialog.dart:46-57` · catégorie correctness · confiance medium

**Problème** : Les deux contrôleurs de défilement sont câblés en permanence pour se refléter (`_syncScrolling` est `final = true`, jamais basculé). Quand le panneau gauche défile, son écouteur appelle `_rightScrollController.jumpTo(...)`. `jumpTo` notifie ses écouteurs SYNCHRONEMENT, donc l'écouteur droit refait immédiatement `_leftScrollController.jumpTo(...)`. Aucune garde de ré-entrance. Les deux panneaux affichant des textes différents (ancienne vs nouvelle version), leur `maxScrollExtent` diffère ; quand le panneau le plus court clampe l'offset demandé, le `jumpTo` réfléchi ramène le panneau le plus long à la valeur clampée.

```dart
_leftScrollController.addListener(() {
  if (_syncScrolling && _leftScrollController.hasClients) {
    _rightScrollController.jumpTo(_leftScrollController.offset);
  }
});
_rightScrollController.addListener(() {
  if (_syncScrolling && _rightScrollController.hasClients) {
    _leftScrollController.jumpTo(_rightScrollController.offset);
  }
});
```

**Impact** : Sur toute comparaison où les deux versions diffèrent assez en longueur pour produire des extents différents (le cas courant), l'utilisateur ne peut pas lire le bas de la version la plus longue : le défilement est épinglé au max du panneau le plus court. Dégrade la fonction centrale de ce dialogue.

**Recommandation** : Ajouter une garde de ré-entrance, par ex. un drapeau `bool _syncing` positionné/effacé autour de chaque `jumpTo`, et sortir de l'écouteur tant que `_syncing` est vrai. Alternativement, piloter les deux panneaux depuis un `ScrollController` partagé / `LinkedScrollControllerGroup` pour un clamping symétrique.

### API mal utilisée

### copyWith ne peut pas remettre les champs nullables à null (aveuglement au null) dans la plupart des modèles de domaine

fichier `lib/models/domain/translation_version.dart:160-187` · catégorie api-misuse · confiance medium

**Problème** : Presque tous les modèles utilisent l'idiome `field: arg ?? this.field`, qui rend impossible de réinitialiser un champ nullable à null via `copyWith`. Le défaut est concrètement déclenché : `handleRejectTranslation` (`editor_actions_validation.dart`) construit `version.copyWith(translatedText: null, status: pending, validationIssues: null, ...)` pour effacer une traduction, mais les deux arguments null sont des no-ops, donc l'ancien `translatedText` et `validationIssues` sont conservés. Le repository sérialise ensuite l'entité entière, réécrivant le texte obsolète en DB et laissant l'index FTS peuplé. `LlmCustomRule.copyWith` montre le bon pattern avec un drapeau `clearProjectId`.

```dart
translatedText: translatedText ?? this.translatedText,  // cannot set back to null
```

**Impact** : La fonction « Rejeter la traduction » de l'éditeur ne vide pas réellement le texte rejeté ni ses problèmes de validation (seul le statut passe à `pending`). Plus largement, toute opération devant effacer un champ nullable via `copyWith` (dépublier un pack, réinitialiser une erreur de batch) conserve silencieusement des données obsolètes.

**Recommandation** : Pour les champs nullables devant légitimement être effaçables, suivre le précédent `LlmCustomRule` et ajouter des drapeaux `clearX` explicites (ou utiliser un sentinelle/wrapper Optional) sur `copyWith` pour au moins `Project` (`published*`/`completedAt`), `TranslationVersion` (`translatedText`/`validationIssues`) et `TranslationBatch` (`errorMessage`/`startedAt`/`completedAt`). Pour `handleRejectTranslation`, préférer le chemin SQL dédié qui met `translated_text` à NULL.

## Faible

### Correctness

### Le compteur final de succès du batch et le taux de succès excluent les unités appariées par TM, sous-rapportant l'achèvement

fichier `lib/services/translation/translation_orchestrator_impl.dart:416-426` · catégorie correctness · confiance high

**Problème** : `successfulUnits` n'est incrémenté que dans `ValidationPersistenceHandler.validateAndSave`, qui s'exécute pour les traductions LLM/cache. Les correspondances TM exactes/floues sont persistées séparément par `TmLookupHandler._applyTmMatchesBatch` et n'alimentent que `skippedUnits`/`processedUnits`/`tmReuseRate` ; elles ne bumpent jamais `successfulUnits`. L'orchestrateur calcule pourtant `successRate = successfulUnits/units.length` et le message « Batch complete: ${successfulUnits}/${units.length} ». `BatchCompletedEvent.completedUnits` est aussi fixé à `successfulUnits`.

**Impact** : Un batch où la plupart des unités ont été résolues depuis la TM rapporte un compte et un pourcentage de succès trompeusement bas (ex. « 12/100 (12% success) ») alors que les 100 unités ont été traduites. Cela fausse les chiffres du tableau de bord/activité et peut faire croire à l'utilisateur que la traduction a échoué.

**Recommandation** : Inclure les unités appariées par TM dans la comptabilité de succès — soit incrémenter `successfulUnits` lors de l'application des correspondances TM, soit calculer le compte/taux affiché comme `successfulUnits + tmMatchedUnitIds.length` (et fixer `BatchCompletedEvent.completedUnits` en conséquence).

### RateLimiter.acquire() ne timeout jamais et fuit/bloque les appelants si disposé ou affamé

fichier `lib/services/llm/utils/rate_limiter.dart:83-90, 145-168` · catégorie concurrency · confiance high

**Problème** : `acquire()` met en file un `Completer` et retourne son future, complété uniquement par le `_processQueue` périodique (100ms) quand `tryAcquire` réussit. `dispose()` annule le timer et vide la file SANS compléter les completers en attente (`_queue.clear()`). Tout appelant en attente d'`acquire()` au moment du dispose bloque pour toujours. `reset()` a le même défaut. Aucun chemin d'annulation : une requête qui ne peut jamais satisfaire le token bucket attend indéfiniment.

```dart
void dispose() {
  _queueTimer?.cancel();
  _queue.clear();   // pending completers never completed -> awaiting callers hang
}
```

**Impact** : Latent : ce code est de l'infrastructure générique. Le seul appelant en production (`WorkshopApiServiceImpl`) ne configure pas de `tokensPerMinute` (chemin de famine mort) et ne dispose jamais le service, donc le deadlock ne se matérialise sur aucun chemin actuel. Reste un piège de robustesse pour tout futur appelant.

**Recommandation** : Sur `dispose()`/`reset()`, compléter les completers en attente avec une erreur (`completeError(StateError('RateLimiter disposed'))`) avant de vider. Ajouter un max-wait/timeout à `acquire()`. Se prémunir contre `estimatedTokens` dépassant la capacité du bucket (rejeter ou plafonner) pour que `_processQueue` ne bloque pas sur un élément de tête insatisfiable.

### DiffCalculator LCS alloue une table DP O(m*n), risquant un usage mémoire énorme / des saccades sur de longs textes

fichier `lib/services/history/diff_calculator.dart:41-60` · catégorie performance · confiance medium

**Problème** : `_longestCommonSubsequence` construit une table DP `List<List<int>>` complète `(m+1) x (n+1)` pour un diff caractère par caractère. Le doc de la classe affirme « adapté jusqu'à 10k caractères » ; à 10k x 10k cela représente ~100 millions de cellules, soit des centaines de Mo à plus d'un Go de heap, alloué synchronement sur l'isolate UI dans `compareVersions()`.

```dart
final dp = List.generate(
  m + 1,
  (_) => List.filled(n + 1, 0),
);
```

**Impact** : Comparer deux longues versions de traduction peut faire flamber la mémoire et bloquer le thread UI (voire OOM). Les chaînes de traduction sont généralement courtes, donc cela se déclenche rarement, mais une seule longue entrée (paragraphe/dialogue) fait figer la vue de comparaison d'historique.

**Recommandation** : Borner la longueur d'entrée avant l'algorithme quadratique (par ex. repli sur un diff au niveau mot ou un LCS en espace linéaire de type Hirschberg pour les grandes entrées), ou plafonner avec une garde explicite et dégrader vers `calculateWordDiff` quand l'un des textes dépasse un seuil.

### L'extraction de code de langue utilise replaceAll('.pack','') qui peut corrompre les codes contenant 'pack'

fichier `lib/services/game/game_localization_service.dart:104-107, 163-170` · catégorie correctness · confiance medium

**Problème** : `detectLocalizationPacks` et `getLanguageCodeFromPath` extraient le code de langue via `fileName.substring(6).replaceAll('.pack', '')`. `replaceAll` retire TOUTES les occurrences de la sous-chaîne `.pack`, pas seulement l'extension de fin. Les codes standards (en, fr, de...) ne sont pas affectés, mais un nom inattendu comme `local_xx.pack.pack` serait altéré.

```dart
final languageCode = fileName
    .substring(6) // Remove 'local_'
    .replaceAll('.pack', '');
```

**Impact** : Mauvaise détection en cas limite de codes de langue pour des noms de fichier non standards ; faible probabilité vu la convention fixe `local_xx.pack`, mais la logique est incorrecte et pourrait produire un code vide ou malformé ensuite utilisé comme identifiant de langue.

**Recommandation** : Ne retirer que le suffixe connu, par ex. `path.basenameWithoutExtension(entity.path)` après le préfixe `local_`, ou remplacer spécifiquement le `.pack` de fin (vérification `endsWith`) au lieu de `replaceAll`.

### Le diff TSV de chemin cible retire TOUTES les sous-chaînes '.tsv', pas seulement l'extension

fichier `lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:179-180` · catégorie correctness · confiance medium

**Problème** : `final targetPath = relativePath.replaceAll('.tsv', '').replaceAll('\\', '/');` utilise un `replaceAll` global. Tout chemin source `.loc` dont le nom contient légitimement la sous-chaîne `.tsv` (ex. `data.tsv_table.loc.tsv`) verrait toutes les occurrences retirées, altérant le chemin interne. Ne devrait retirer que l'extension de fin.

```dart
final targetPath = relativePath.replaceAll('.tsv', '').replaceAll('\\\\', '/');
```

**Impact** : Mauvais chemin interne dans le pack pour le (rare) loc dont le nom contient `.tsv` ; la table loc serait placée au mauvais chemin et ignorée par le jeu. Faible probabilité mais bug de correctness latent, qui devient actif une fois le constat #1 corrigé et cette branche à nouveau empruntée.

**Recommandation** : Utiliser un strip de suffixe seul, par ex. `relativePath.endsWith('.tsv') ? relativePath.substring(0, relativePath.length - 4) : relativePath` avant de normaliser les séparateurs.

### La recherche regex ignore l'offset et le compteur total de pagination est faux dans des fonctionnalités de recherche non câblées

fichier `lib/features/search/providers/search_providers.dart:85-96` · catégorie correctness · confiance high

**Problème** : `searchResults` construit `SearchResultsModel` avec `totalCount: results.length` — le nombre de lignes de la page COURANTE, pas le total sur toutes les pages. `totalPages = ceil(totalCount / pageSize)` et `hasNextPage = currentPage < totalPages` ; avec une page pleine de 50 résultats, `totalCount=50 => totalPages=1 => hasNextPage=false`. De plus, `searchAll()` n'a pas de paramètre `offset` et ne le transmet jamais à ses sous-recherches, donc chaque demande de page pour le scope par défaut « All Fields » retourne les mêmes top-N.

```dart
return SearchResultsModel(
  results: results,
  totalCount: results.length, // Note: This is a simplification
  currentPage: page,
  pageSize: pageSize,
  query: query,
);
```

**Impact** : La pagination est effectivement morte pour toute requête dépassant une page ; les utilisateurs ne voient silencieusement que la première page. Faible aujourd'hui car la fonctionnalité de recherche est du code mort non câblé (aucun écran/route ne consomme ces widgets/providers), donc aucun utilisateur ne peut atteindre les contrôles cassés. Latent mais réel dès que la fonctionnalité sera branchée.

**Recommandation** : Retourner un vrai total depuis le service (un COUNT(*) séparé sur le même MATCH FTS + filtres), et le passer comme `totalCount`. Ajouter un paramètre `offset` à `searchAll` et le pousser dans chaque sous-requête puis fusionner, ou implémenter une seule requête UNION avec ORDER BY rank global et LIMIT/OFFSET. Mettre à jour `_executeSearch` pour transmettre `offset`.

### Les scans concurrents partagent un unique contrôleur de log de scan broadcast, entrelaçant les lignes de progression

fichier `lib/services/mods/workshop_scanner_service.dart:44-56` · catégorie concurrency · confiance medium

**Problème** : `WorkshopScannerService` est un singleton lazy avec un `StreamController<ScanLogMessage>.broadcast()` réutilisé pour chaque invocation `scanMods`. `scanMods` n'a aucune garde de ré-entrance. Un second scan (changement de jeu sélectionné ou refresh pendant un scan en cours) s'exécute concurremment et émet dans le même contrôleur ; sans id de corrélation par scan, le terminal mêle les lignes des deux scans.

```dart
final StreamController<ScanLogMessage> _scanLogController =
    StreamController<ScanLogMessage>.broadcast();
...
void _emitLog(String message, [ScanLogLevel level = ScanLogLevel.info]) {
  if (!_scanLogController.isClosed) { _scanLogController.add(ScanLogMessage(...)); }
}
```

**Impact** : Si deux scans se chevauchent (basculement de jeu rapide ou refresh pendant un scan), le terminal de scan affiche une progression altérée et hors-ordre et des totaux ne correspondant pas à une seule exécution, induisant l'utilisateur en erreur. Les écritures DB sont indépendantes par pack donc elles ne corrompent pas, mais la progression visible est incohérente.

**Recommandation** : Sérialiser les scans avec une garde/mutex de ré-entrance dans `scanMods` (rejeter ou mettre en file un second scan tant qu'un tourne), ou tagger chaque `ScanLogMessage` d'un id de scan et filtrer le terminal sur le scan courant. Au minimum, court-circuiter un appel `scanMods` quand un scan est déjà actif.

### BackgroundWorkerService exécute les tâches strictement en série ; maxConcurrentTasks jamais honoré

fichier `lib/services/shared/background_worker_service.dart:229-249` · catégorie concurrency · confiance high

**Problème** : `_processQueue()` vérifie la limite de concurrence, retire UNE tâche, puis fait `await _executeTask(task)` avant toute autre chose. Comme la tâche en cours est attendue inline, le drainage de la file interne est strictement sériel et `maxConcurrentTasks` (défaut 4) n'est jamais utilisé pour exécuter plusieurs tâches en file en parallèle. (La concurrence jusqu'à `maxConcurrentTasks` est atteignable via plusieurs appels `enqueue` rapides, mais le backlog en file ne se déploie jamais sur tous les slots.)

```dart
final task = _queue.removeFirst();
await _executeTask(task);   // blocks; next task only starts after this finishes
if (_queue.isNotEmpty) {
  _processQueue();
}
```

**Impact** : Tout consommateur de ce service pour du travail parallèle voit un débit entièrement sérialisé pour un backlog en file. Faible aujourd'hui : le service n'a aucun appelant en production (infrastructure morte/latente), mais c'est un piège de correctness pour tout futur appelant.

**Recommandation** : Ne pas attendre l'exécution par tâche dans la boucle de répartition. Lancer les tâches jusqu'à `maxConcurrentTasks` sans attendre (`while (_activeTasks.length < maxConcurrentTasks && _queue.isNotEmpty) { unawaited(_executeTask(_queue.removeFirst())); }`), et faire que `_executeTask` rappelle `_processQueue()` à la complétion pour remplir les slots libérés.

### Le redirect hérité perd les paramètres de requête lors de la migration d'anciennes URLs

fichier `lib/config/router/app_router.dart:100-116, 124` · catégorie correctness · confiance medium

**Problème** : `appRouterRedirect` construit le nouveau chemin uniquement depuis `state.uri.path` et n'ajoute que la queue du chemin (`path.substring(legacy.length)`). Il ne réajoute jamais `state.uri.query`. Une URL héritée portant une query string serait redirigée sans le paramètre.

```dart
final tail = path.substring(legacy.length);
bestMatch = '$newPrefix$tail'; // query string from state.uri is never re-appended
```

**Impact** : Tout deep-link hérité ou raccourci persistant qui s'appuyait sur un paramètre de requête le perd après redirect, de sorte que l'écran cible se monte sans son filtre/état voulu. Faible portée : `legacyRedirects` est un shim de compatibilité d'un seul cycle, et toutes les URLs porteuses de query que l'app génère utilisent déjà les nouveaux préfixes (donc ne passent pas par le redirect). Aucun déclencheur vivant aujourd'hui.

**Recommandation** : Lors de la construction de `bestMatch`, préserver la query : si `state.uri.query` est non vide, ajouter `'?${state.uri.query}'`. Soit changer `appRouterRedirect` pour accepter l'`Uri` complète, soit faire réattacher `state.uri.query` au chemin retourné par le callback de redirect.

### StringSimilarity la clé de cache LRU collisionne sur le délimiteur '|'

fichier `lib/utils/string_similarity.dart:75, 124-131` · catégorie correctness · confiance medium

**Problème** : La clé de cache est construite comme `'$s1|$s2'`. Toute chaîne d'entrée contenant `|` produit des clés ambiguës : `levenshtein('a|b','c')` et `levenshtein('a','b|c')` mappent tous deux vers `'a|b|c'`. La première distance calculée est alors retournée pour la seconde paire (différente). Les chaînes `.loc` contiennent fréquemment des `|`.

```dart
final cacheKey = '$s1|$s2';
```

**Impact** : Si le cache est un jour activé (l'API publique y invite pour les recherches TM), les résultats de similarité/distance se corrompent silencieusement pour toute chaîne contenant `|`, dégradant la qualité de correspondance TM et les décisions de dédoublonnage. Latent : `enableCache()` n'a aucun appelant en production.

**Recommandation** : Utiliser un délimiteur qui ne peut apparaître dans les entrées (par ex. `'\u0000'`), ou clé sur un record/tuple, ou hacher les deux longueurs dans la clé. Ajouter un test unitaire avec des entrées contenant `|`.

### StringSimilarity.enableCache(maxSize:) ignore silencieusement son argument

fichier `lib/utils/string_similarity.dart:26-28, 127-129` · catégorie correctness · confiance high

**Problème** : `enableCache` accepte un paramètre `maxSize` mais ne le stocke jamais ; le `LinkedHashMap` est créé non borné et l'éviction compare toujours contre la constante de compilation `_defaultCacheSize` (1000). Appeler `enableCache(maxSize: 50)` ou `enableCache(maxSize: 100000)` n'a aucun effet sur le plafond réel.

```dart
static void enableCache({int maxSize = _defaultCacheSize}) {
  _cache = LinkedHashMap<String, int>();  // maxSize discarded
}
...
if (_cache!.length >= _defaultCacheSize) {  // always the constant
```

**Impact** : Les appelants ne peuvent pas régler la taille du cache ; une demande de petit cache croît quand même jusqu'à 1000 entrées, et une demande de cache plus grand est silencieusement tronquée à 1000. Latent : `enableCache` n'est invoqué nulle part actuellement.

**Recommandation** : Stocker `maxSize` dans un champ statique fixé par `enableCache` et l'utiliser comme seuil d'éviction au lieu de `_defaultCacheSize`.

### BatchOperationState.complete() ne peut pas effacer currentItem (le libellé obsolète persiste)

fichier `lib/providers/batch/batch_operations_provider.dart:142-148` · catégorie correctness · confiance high

**Problème** : `complete()` appelle `state.copyWith(isInProgress: false, currentItem: null)` pour effacer le libellé d'élément en cours. Mais `copyWith` résout `currentItem` via `currentItem ?? this.currentItem`, donc passer null donne l'ANCIENNE valeur. Le même pattern null-coalescing affecte tous les champs nullables (`currentItem`, `errorMessage`).

```dart
void complete() {
  state = state.copyWith(
    isInProgress: false,
    currentItem: null,
  );
}
// copyWith: currentItem: currentItem ?? this.currentItem  // null is ignored
```

**Impact** : Le défaut de code est réel, mais `batchOperationProvider.currentItem` n'a aucun consommateur dans l'UI (aucun widget ne l'affiche ; l'écran steam_publish utilise un autre notifier qui efface correctement). L'état obsolète est donc latent sans rendu observé.

**Recommandation** : Utiliser un sentinelle (par ex. `ValueGetter<String?>?` pour les champs nullables, comme déjà fait correctement dans `ModUpdateInfo.copyWith`) pour que les appelants distinguent « laisser inchangé » de « mettre à null ». `complete()` passerait alors `currentItem: () => null`.

### RescanState.copyWith ne peut pas effacer les champs nullables (error/plan/progress), donc une erreur obsolète ne peut jamais être désactivée

fichier `lib/features/bootstrap/providers/validation_rescan_provider.dart:40-60` · catégorie state-management · confiance medium

**Problème** : `copyWith` utilise l'idiome `value ?? this.value` pour `error`, `plan` et `progress`. Une fois `error` positionné, aucun `copyWith` ultérieur ne peut le remettre à null — `error: null` est indistinguable de « non fourni ».

```dart
RescanState copyWith({... Object? error, ...}) =>
    RescanState(
      ...
      error: error ?? this.error,  // cannot be cleared once set
      ...
    );
```

**Impact** : Latent : tout futur chemin devant récupérer d'une erreur antérieure (retenter le rescan, réutiliser le contrôleur keepAlive entre ouvertures de dialogue) verrait l'erreur/plan obsolète et se comporterait comme si l'échec précédent était toujours courant. Faible aujourd'hui car le contrôleur est keepAlive et effectivement à usage unique par exécution.

**Recommandation** : Ajouter des drapeaux clear explicites (`bool clearError`, `bool clearPlan`) à l'image du pattern de `ReleaseNotesState.copyWith`, ou réinitialiser l'état à `const RescanState()` au début de `prepare()`/`start()` avant de réexécuter.

### TranslationVersion equality/hashCode omettent validationSchemaVersion

fichier `lib/models/domain/translation_version.dart:194-221` · catégorie state-management · confiance medium

**Problème** : `validationSchemaVersion` est un vrai champ (sérialisé, inclus dans `copyWith` et `fromJson/toJson`) utilisé pour décider quelles lignes le rescan de validation doit retraiter. Cependant il est exclu d'`operator==` et de `hashCode`. Deux instances ne différant QUE par `validationSchemaVersion` se comparent égales.

```dart
return other is TranslationVersion &&
    ...
    other.validationIssues == validationIssues &&
    other.createdAt == createdAt &&
    other.updatedAt == updatedAt;  // validationSchemaVersion not compared
```

**Impact** : Risque de correctness latent : si un consommateur s'appuie sur `==` pour détecter qu'une version a changé (par ex. sauter un rebuild UI ou une re-persistance après que le rescan bumpe la version de schéma), le bump de version de schéma est invisible et l'état hérité obsolète est conservé. Aucun chemin actif ne s'appuie là-dessus aujourd'hui.

**Recommandation** : Inclure `validationSchemaVersion` dans `operator==` et `hashCode` pour que l'égalité reflète l'état persisté complet, conformément aux autres champs.

### Intégrité des données

### La normalisation TMX auto-détectée (couverte en Moyen) — voir aussi ci-dessous les défauts d'intégrité faibles

### handleEditTranslation persiste le texte brut sans la normalisation appliquée partout ailleurs

fichier `lib/features/translation_editor/screens/actions/editor_actions_validation.dart:470-495` · catégorie data-integrity · confiance medium

**Problème** : `handleEditTranslation` (invoqué depuis le bouton Edit par problème via `ValidationEditDialog`) écrit le `newText` du dialogue directement dans `version.translatedText` sans appeler `TranslationTextUtils.normalizeTranslation`. Tous les autres chemins d'écriture acceptant du texte utilisateur/LLM normalisent d'abord les séquences d'échappement. L'invariant de l'éditeur (le texte cible stocké contient toujours du vrai whitespace) est rompu : une valeur éditée contenant un `\n` littéral peut atterrir non normalisée en DB.

```dart
final editedVersion = version.copyWith(
  translatedText: newText,
  status: TranslationVersionStatus.translated,
  validationIssues: null,
  isManuallyEdited: true,
```

**Impact** : Une correction saisie via le dialogue Edit de validation peut stocker du whitespace/séquences d'échappement non canoniques, qui font ensuite un aller-retour ambigu dans l'inspecteur (`unescapeFromDisplay` collapse les `\n` littéraux et les vrais retours à la ligne ensemble) et peuvent différer de la façon dont le même texte serait stocké via le chemin de cellule normal. Faible car le dialogue Edit de validation est un chemin peu emprunté et la plupart des corrections sont des textes courts.

**Recommandation** : Normaliser avant de persister : `translatedText: TranslationTextUtils.normalizeTranslation(newText)` dans `handleEditTranslation`, comme dans `handleCellEdit`/`handleApplySuggestion`.

### L'écriture projectRepo.update() effectuée dans le chemin de lecture/chargement du provider de liste de projets

fichier `lib/features/projects/providers/projects_screen_providers.dart:527-559` · catégorie data-integrity · confiance medium

**Problème** : `_computeOne`, invoqué depuis `_loadAll()` (build) et `refreshProject()`, effectue un `projectRepo.update(updatedProject)` pour rétro-remplir l'URL d'image du mod alors qu'il ne fait que charger des projets pour affichage. `_loadAll` exécute tous les `_computeOne` concurremment via `Future.wait`. Une écriture en effet de bord d'un chargement de rendu de liste signifie que `refreshProject` et un `_loadAll` concurrent peuvent faire courir deux `update()` sur la même ligne.

```dart
final hasValidImage = project.imageUrl != null && await File(project.imageUrl!).exists();
if (!hasValidImage && project.isModTranslation) {
  ...
  await projectRepo.update(updatedProject);
  project = updatedProject;
}
```

**Impact** : Surtout bénin car `updatedAt` est maintenu constant et l'écriture est idempotente (même chemin d'image découvert), mais c'est une écriture cachée dans un build de provider pouvant tourner concurremment avec un autre chargement de la même ligne, et elle émet des écritures DB à chaque rendu qui découvre une nouvelle image. Sous des tempêtes d'invalidation de provider, cela ajoute du trafic d'écriture évitable et une course last-writer-wins sur la colonne de métadonnées.

**Recommandation** : Déplacer l'écriture de rétro-remplissage d'image hors du chemin de chargement vers une action one-shot explicite (passe de maintenance dédiée ou déclenchée après création), ou la garder pour qu'elle ne s'exécute qu'une fois par projet par session. Au minimum, garantir que `refreshProject` et `_loadAll` ne peuvent pas rétro-remplir la même ligne concurremment.

### La normalisation agressive TMX écrit des IDs DB internes comme xml:lang — voir Moyen

### L'import n'est pas transactionnel : les échecs partiels laissent des unités/versions à demi écrites

fichier `lib/features/import_export/services/import_executor.dart:74-132` · catégorie data-integrity · confiance medium

**Problème** : `executeImport` traite les lignes une par une avec des appels de repository indépendants (insert unit, insert/update version, recordChange) sans transaction englobante ni rollback. Si `_createNewUnit` réussit mais l'insert de version suivant échoue, l'unité orpheline demeure. Il n'y a aucune frontière d'atomicité.

```dart
for (int i = 0; i < rows.length; i++) {
  ...
  final result = await _processRow(...);  // each row = multiple independent, non-transactional writes
```

**Impact** : Un échec à mi-parcours d'un gros import laisse des données incomplètes (unités sans versions, certaines lignes appliquées et d'autres non) que l'utilisateur ne peut détecter ni annuler facilement. Le pire cas réaliste est un import incomplet de lignes par ailleurs internes-valides (SQLite rend chaque instruction atomique individuellement ; l'historique n'est écrit qu'après succès de la version, donc pas de lignes d'historique orphelines), plutôt qu'une corruption de données. `ImportResult` enregistre toutefois les erreurs par ligne, donc les échecs sont remontés.

**Recommandation** : Envelopper la séquence d'écritures par ligne (ou tout l'import) dans une transaction via le support transactionnel des repositories, pour qu'une ligne s'applique entièrement ou rollback. Au minimum, garantir qu'un échec d'écriture de version annule l'unité qui vient d'être créée.

### Le client DeepL tag_handling XML corrompt les balises de jeu contenant des chevrons, cassant l'aller-retour .loc

fichier `lib/services/llm/utils/deepl_api_client.dart:83-90; deepl_text_processor.dart:28-31` · catégorie data-integrity · confiance medium

**Problème** : Les requêtes DeepL sont envoyées avec `tag_handling: 'xml'`. DeepL parse alors la source comme du XML : toute séquence `<...>` est traitée comme markup. `preprocessText` n'échappe que le `\n` littéral ; il n'échappe pas le `<`/`&` parasites. Si la source contient un `<` non équilibré ou non-XML (ex. `HP < 50`) ou un `&` nu (ex. `Tom & Jerry`), le parser XML de DeepL peut le supprimer/réordonner/altérer, et `postprocessText` ne restaure que le placeholder de retour à la ligne.

```dart
'tag_handling': 'xml',
...
String preprocessText(String text) {
  return text.replaceAll(r'\n', newlinePlaceholder); // only \n handled; raw < > & passed to XML parser
}
```

**Impact** : Les chaînes contenant un `<` parasite ou un `&` nu peuvent être silencieusement altérées par le parser XML de DeepL. La valeur traduite réécrite dans le `.loc`/`.pack` perd ou corrompt ces caractères. Perte d'intégrité silencieuse — aucune exception car la forme de réponse est valide. Risque résiduel étroit : pour les balises `<tag>` bien formées, `tag_handling=xml` est le comportement voulu et un validateur de préservation de markup attrape les déséquilibres ; seuls les `<` non équilibrés et `&` nus échappent à la détection, sur le seul chemin du fournisseur DeepL.

**Recommandation** : Soit échapper les métacaractères XML (`&`, `<`, `>`) dans `preprocessText` avant l'envoi (et les déséchapper en postprocess), en n'enveloppant comme vrai markup que le placeholder de retour à la ligne voulu, soit basculer `tag_handling` à off / `html` uniquement quand le contenu est connu comme sûr. Ajouter un test d'aller-retour avec des chaînes comme `HP < 50 & MP > 10`.

### findMatchingTerms incrémente le usage_count persistant en effet de bord, le gonflant lors des contrôles de cohérence et de validation

fichier `lib/services/glossary/glossary_matching_service.dart:63-67, 163-170` · catégorie data-integrity · confiance high

**Problème** : `findMatchingTerms` appelle inconditionnellement `_repository.incrementUsageCount(entryIds)` pour chaque entrée appariée. `checkConsistency` appelle `findMatchingTerms` purement pour vérifier la traduction, pourtant cette vérification de style lecture bump définitivement `usage_count` (et `updated_at`) sur les entrées appariées.

```dart
if (matchedEntries.isNotEmpty) {
  final entryIds = matchedEntries.map((e) => e.id).toList();
  await _repository.incrementUsageCount(entryIds);
}
```

**Impact** : Les statistiques `usage_count`/`usedInTranslations` (`usageRate`, `unusedEntries`) deviendraient gonflées et peu fiables, et `updated_at` est churné, ce qui peut interférer avec la détection de resync DeepL (comparaison de timestamps). Faible aujourd'hui car le chemin impliqué (`checkConsistency`/`findMatchingTerms`) n'a aucun appelant en production.

**Recommandation** : Séparer le chemin de matching en lecture seule du chemin de suivi d'usage. N'incrémenter `usage_count` que depuis `applySubstitutions` (l'application réelle au moment de la traduction), et rendre `findMatchingTerms`/`checkConsistency` sans effet de bord, ou passer un drapeau `trackUsage` explicite par défaut à false pour les appelants de cohérence/validation.

### La création de glossaire DeepL peut fuir des glossaires côté serveur quand l'insert du mapping local échoue

fichier `lib/services/glossary/deepl_glossary_sync_service.dart:111-146` · catégorie error-handling · confiance medium

**Problème** : `ensureGlossarySynced` appelle `createDeepLGlossary` (qui crée un glossaire sur les serveurs DeepL et retourne son id), puis insère plus tard le mapping de suivi via `insertDeepLMapping`. Si quoi que ce soit entre la création réussie et l'insert lève une exception (par ex. `getByProjectAndLanguage`, ou l'insert lui-même échoue sur une contrainte), le catch extérieur retourne une erreur mais l'id du glossaire DeepL fraîchement créé est perdu — aucun `deleteDeepLGlossary` compensatoire.

```dart
final deeplGlossaryId = createResult.value;
final glossary = await _glossaryRepository.getGlossaryById(glossaryId);
...
await _glossaryRepository.insertDeepLMapping(mapping);
```

**Impact** : Des glossaires orphelins s'accumulent sur le compte DeepL (chaque création consomme un slot ; DeepL limite le nombre). Sur des syncs échoués répétés, le compte peut atteindre la limite, après quoi tout `createDeepLGlossary` échoue avec 4xx jusqu'à purge manuelle via le tableau de bord DeepL.

**Recommandation** : Envelopper la comptabilité post-création dans un try/catch qui appelle `_deeplService.deleteDeepLGlossary(deeplGlossaryId)` en cas d'échec avant de retourner l'erreur, pour qu'un glossaire côté serveur ne soit jamais créé sans mapping local le suivant.

### L'import TBX ne lit que les deux premiers langSets et ignore xml:lang, mal-étiquetant la langue cible et perdant les entrées multilingues

fichier `lib/services/glossary/glossary_import_service.dart:321-358` · catégorie data-integrity · confiance medium

**Problème** : `_parseTbxEntries` traite le langSet d'index 0 comme source et l'index 1 comme cible purement par position, ignorant l'attribut `xml:lang`. Un termEntry TBX valide peut lister les langues dans n'importe quel ordre, ou contenir plus de deux langSets. Tout langSet au-delà de l'index 1 est silencieusement perdu, et si le terme de langue source se trouve au second langSet, source/cible sont inversés.

```dart
if (i == 0 && term != null && term.isNotEmpty) {
  sourceTerm = term;
} else if (i == 1 && term != null && term.isNotEmpty) {
  targetTerm = term;
  targetLanguage = lang;
}
```

**Impact** : Importer des fichiers TBX standards/multilingues produit des termes source/cible inversés ou des termes valides silencieusement perdus, et assigne un `target_language_code` dérivé de l'ordre du fichier plutôt que de la langue du glossaire. L'aller-retour avec l'export TBX de l'app fonctionne seulement parce que `exportToTbx` écrit toujours source d'abord, cible ensuite.

**Recommandation** : Sélectionner les langSets source et cible en appariant leur `xml:lang` à la langue source demandée et à la langue cible du glossaire, au lieu de l'index positionnel ; sauter ou signaler les entrées dépourvues des langues attendues plutôt que de deviner par ordre.

### La recréation de triggers par batch omet trg_translation_versions_fts_insert de la récupération à l'ouverture

fichier `lib/services/database/database_service.dart:141-208` · catégorie error-handling · confiance medium

**Problème** : `_ensureCriticalTriggersExist` (la récupération défensive à l'ouverture pour les triggers que les opérations batch droppent) ne recrée que `trg_update_project_language_progress`, `trg_translation_versions_fts_update` et `trg_update_cache_on_version_change`. Les chemins bulk du mixin droppent aussi `trg_translation_versions_fts_insert` ; il ne figure pas dans la map de récupération.

**Impact** : Lacune de défense en profondeur seulement : si un DROP survivait un jour (futur chemin batch non transactionnel, ou scénario de commit partiel), le trigger FTS-insert ne serait pas restauré à la prochaine ouverture, et les traductions nouvellement insérées cesseraient silencieusement d'être indexées pour la recherche plein texte. Risque actuellement faible car tous les drops sont dans des transactions qui rollback atomiquement.

**Recommandation** : Ajouter `trg_translation_versions_fts_insert` (la variante `AFTER INSERT ... WHEN new.translated_text IS NOT NULL` de `schema.sql`) à la map `criticalTriggers` pour que la récupération à l'ouverture couvre chaque trigger droppé par le code batch.

### L'initialisation de projet insère unités et versions ligne par ligne avec contrôles d'existence par unité, sans batching/transaction

fichier `lib/services/projects/project_initialization_service_impl.dart:198-265` · catégorie performance · confiance medium

**Problème** : Pour chaque entrée parsée, le code effectue un `getByKey()` attendu, puis un `insert()` attendu de l'unité, puis un `insert()` attendu par langue de projet pour la version — tous séquentiels, un aller-retour à la fois, sans transaction. Pour un mod avec des dizaines de milliers d'entrées x N langues, c'est O(entrées x langues) instructions DB individuelles attendues. Chaque insert déclenche aussi les triggers FTS/cache/progression individuellement.

```dart
for (final entry in locFile.entries) {
  final existingResult = await _unitRepository.getByKey(projectId, entry.key);
  ...
  final insertResult = await _unitRepository.insert(unit);
  ...
  for (final language in projectLanguages) {
    final versionResult = await _versionRepository.insert(version);
```

**Impact** : L'import de gros mods est lent (plusieurs milliers d'allers-retours DB sériels et de déclenchements de triggers). Pas un bug de correctness mais un coût significatif au temps d'initialisation pour les gros packs.

**Recommandation** : Envelopper l'import dans une seule transaction et utiliser des inserts batchés (`insertBatch`) pour unités et versions ; remplacer le `getByKey` par ligne par un seul fetch en amont des clés existantes du projet, ou utiliser `INSERT OR IGNORE`/`ON CONFLICT`. Envisager de désactiver les triggers FTS/cache pendant l'import bulk comme le font déjà les services de suppression.

### Error-handling

### L'heuristique de filtre de contenu Anthropic classe à tort des traductions légitimement vides comme violations de politique

fichier `lib/services/llm/providers/anthropic_provider.dart:396-406` · catégorie error-handling · confiance medium

**Problème** : `_parseResponse` lève `LlmContentFilteredException` quand `responseText.trim().isEmpty && content.isNotEmpty`. Anthropic n'a pas de stop_reason `content_filter` ; un bloc de texte vide peut survenir pour des raisons bénignes (le modèle n'a renvoyé que du whitespace, `max_tokens` atteint avant tout texte, hoquet transitoire). Le code attribue tout bloc de contenu vide-mais-présent à un filtrage de sécurité et affiche un message disant que le texte source « viole les politiques d'usage ».

```dart
if (stopReason == 'content_filter' ||
    (responseText.trim().isEmpty && content.isNotEmpty)) {
  ... throw LlmContentFilteredException( ... 'violates usage policies' ... )
```

**Impact** : Les utilisateurs obtiennent une fausse erreur « contenu bloqué par les filtres de sécurité » pour des réponses vides bénignes, érodant la confiance et les envoyant inutilement vers DeepL. La vraie cause (par ex. `max_tokens` trop bas → tronqué/vide) est masquée, rendant le vrai correctif introuvable.

**Recommandation** : Ne traiter comme filtré-contenu que les valeurs de stop_reason indiquant réellement un filtrage (par ex. `refusal`) ; pour un contenu vide avec stop_reason comme `max_tokens` ou null, lever une `LlmResponseParseException`/erreur de réponse vide distincte avec le vrai stop_reason plutôt qu'un message de politique de contenu.

### Concurrence

### incrementVersion relit la version dans une requête séparée, en course avec les incréments concurrents

fichier `lib/services/concurrency/optimistic_lock_manager.dart:243-269` · catégorie concurrency · confiance medium

**Problème** : `incrementVersion` effectue un `UPDATE ... SET version = version + 1` atomique, puis émet un SELECT `getCurrentVersion()` SÉPARÉ (hors transaction) pour rapporter la nouvelle version. L'UPDATE est atomique mais le SELECT suivant n'y est pas couplé. Si deux appelants incrémentent concurremment, les deux UPDATEs s'appliquent (+2) mais les deux SELECTs peuvent observer la même valeur post-deux, donc les deux appelants reçoivent le même numéro de version.

```dart
final count = await _db.rawUpdate(
  'UPDATE $tableName SET version = version + 1, updated_at = ? WHERE id = ?',
  [now, recordId],
);
...
final versionResult = await getCurrentVersion(tableName, recordId);
```

**Impact** : Latent : `incrementVersion` (et tout `OptimisticLockManager`) n'a aucun appelant en production. Le défaut décrit (numéros de version dupliqués/sautés sous concurrence, défaisant la garantie de verrouillage optimiste) ne peut causer aucun défaut runtime aujourd'hui, mais devrait être corrigé avant câblage.

**Recommandation** : Faire l'incrément et la lecture dans une seule instruction (SQLite `UPDATE ... RETURNING version`) ou envelopper l'UPDATE + SELECT dans une seule `_db.transaction` pour que la lecture reflète exactement l'incrément de cet appelant.

### Sécurité

### executeWithMultipleSavepoints interpole des noms de savepoint fournis par l'appelant dans le SQL

fichier `lib/services/concurrency/transaction_manager.dart:208-234` · catégorie security · confiance medium

**Problème** : Le nom de savepoint `op.name` est interpolé directement dans du SQL brut : `txn.execute('SAVEPOINT ${op.name}')`, `'RELEASE SAVEPOINT ${op.name}'` et `'ROLLBACK TO SAVEPOINT ${op.name}'`. Les noms de SAVEPOINT ne peuvent pas être paramétrés en SQLite, donc tout nom contenant whitespace, guillemets ou point-virgule casse l'instruction ou permet une injection. Contrairement à `executeWithSavepoint` qui génère un nom uuid sûr, cette méthode fait confiance verbatim à la chaîne de l'appelant.

```dart
await txn.execute('SAVEPOINT ${op.name}');
...
await txn.execute('ROLLBACK TO SAVEPOINT ${op.name}');
```

**Impact** : Si un appelant dérivait un nom de savepoint d'une entrée externe/pilotée par données, ce serait un vecteur d'injection SQL ; même avec des appelants de confiance, un nom avec un espace ou un tiret corromprait silencieusement les instructions. Latent : `executeWithMultipleSavepoints` n'a aucun appelant ; vulnérabilité hypothétique dans du code mort.

**Recommandation** : Valider `op.name` contre une liste blanche d'identifiants stricte (`^[A-Za-z_][A-Za-z0-9_]*$`) et rejeter sinon, ou ignorer le nom fourni et générer un identifiant sûr interne comme le fait `executeWithSavepoint`.

### validateFilePath la denylist de traversée rejette des noms légitimes et est fragile à l'ordre

fichier `lib/utils/validators.dart:183-191` · catégorie security · confiance low

**Problème** : La garde de traversée de chemin fait un contrôle de sous-chaîne `path.contains('..')` (les contrôles `..\\`/`../` suivants sont morts puisque `..` a déjà matché). C'est une denylist, pas un contrôle basé sur normalisation : elle rejette des noms de fichier valides contenant deux points consécutifs (`my..backup.csv`) comme « traversée de chemin interdite », tandis que le contrôle de chemin absolu `path.contains(':')` rejette aussi tout chemin avec une lettre de lecteur n'importe où.

```dart
if (path.contains('..') || path.contains('..\\') || path.contains('../')) {
  return 'Path traversal not allowed';
}
...
if (path.contains(':') || path.startsWith('\\\\')) {
  return 'Absolute paths not allowed';
}
```

**Impact** : Faux positifs : les utilisateurs avec des noms de fichier légitimes contenant `..` ou des chemins relatifs sont bloqués. Cela penche du côté sûr (rejet), donc ce n'est pas un trou d'injection, mais c'est un validateur incorrect. Latent : `validateFilePath` n'a aucun appelant dans tout le dépôt.

**Recommandation** : Valider par normalisation du chemin (`p.normalize`) et vérifier que le résultat reste dans `baseDirectory`, plutôt que par correspondance de sous-chaîne. Si l'on garde le contrôle simple, conditionner sur des segments de chemin égaux à `..` (split sur séparateurs) plutôt qu'une sous-chaîne `..` quelconque, et ne rejeter `:` qu'à l'index 1 pour une lettre de lecteur.

### Cache d'identifiants steamcmd / ressources

### La vérification d'identifiants en cache apparie le nom d'utilisateur comme sous-chaîne non bornée de config.vdf

fichier `lib/services/steam/workshop_publish_service_impl.dart:862-872` · catégorie correctness · confiance medium

**Problème** : `_hasCachedCredentials` minusculise le nom d'utilisateur et tout `config.vdf` et fait `lowerConfig.contains(lowerUsername)`. Ce test de sous-chaîne naïf : un nom court (`sam`) matche si ces caractères apparaissent n'importe où dans le VDF (dans un autre nom de compte, un chemin, un champ de token), et il ne vérifie pas que l'entrée est une vraie entrée de login/ConnectCache pour cet utilisateur.

**Impact** : Faux positif : le service conclut que des identifiants en cache existent et lance `+login <username>` sans mot de passe/code Steam Guard alors que le cache est pour un autre compte ou périmé. steamcmd sort 0 à cause de `+quit` sans être réellement connecté ; l'échec d'auth est néanmoins capté par le scan de sortie texte (« Login Failure », etc.) plutôt qu'un succès silencieux, mais l'utilisateur reçoit une erreur générique confuse.

**Recommandation** : Parser la structure VDF et confirmer que le nom d'utilisateur apparaît comme sous-clé Accounts/ConnectCache pour ce compte précis, ou au minimum exiger une correspondance avec limite de mot/entre guillemets (matcher `"<username>"` comme clé VDF entre guillemets) plutôt qu'une sous-chaîne nue.

### _runBatchProcess n'a pas de timeout global ; seul un timer d'inactivité de 3 minutes garde un steamcmd figé

fichier `lib/services/steam/workshop_publish_service_impl.dart:666-681` · catégorie error-handling · confiance medium

**Problème** : Le `_runSteamCmd` de publication unique enveloppe `exitCode` dans un timeout dur de 5 minutes. Le `_runBatchProcess` batch ne s'appuie que sur un timer d'inactivité périodique qui tue le processus seulement après 3 minutes de silence TOTAL de sortie. Un steamcmd qui continue d'émettre une sortie périodique (heartbeat/progression) sans jamais terminer un élément ne déclenchera jamais le timer d'inactivité, donc `await _currentProcess!.exitCode` peut bloquer indéfiniment sans borne supérieure.

**Impact** : Un steamcmd coincé qui débite encore de la sortie peut figer toute la publication batch indéfiniment sans récupération automatique ; l'utilisateur doit annuler manuellement. Faible probabilité mais non borné quand cela survient.

**Recommandation** : Ajouter un plafond dur (`exitCode.timeout(maxBatchChunkDuration, onTimeout: kill)`) au chunk batch en plus du timer d'inactivité, à l'image du chemin de publication unique, en dimensionnant le plafond selon le nombre d'éléments du chunk.

### Les résolutions de conflit stockées avec translation_version_id NULL font que getConflictHistory ne retourne rien

fichier `lib/services/concurrency/conflict_resolver.dart:596-616, 317-328, 110-127` · catégorie data-integrity · confiance high

**Problème** : `_storeResolution` écrit la colonne `translation_version_id` depuis `conflict.metadata?['translation_version_id']`. Cette clé de metadata n'est peuplée que par `checkForConflicts()`. Le point d'entrée public `detectConflict()` ne la fixe jamais (metadata par défaut null). Pour tout conflit créé via `detectConflict -> resolveConflict`, la ligne stockée a donc `translation_version_id = NULL`. `getConflictHistory()` filtre avec `where: 'translation_version_id = ?'`, ce qui ne matche jamais NULL.

```dart
'translation_version_id': conflict.metadata?['translation_version_id'],
...
where: 'translation_version_id = ?',
whereArgs: [translationVersionId],
```

**Impact** : Latent : toute la classe `ConflictResolver` est du code mort (enregistrée comme singleton lazy mais aucun consommateur). Aucune résolution n'est donc réellement stockée ni interrogée dans l'app en cours d'exécution ; l'historique d'audit silencieusement perdu ne se matérialise pas aujourd'hui mais mordrait dès le câblage du sous-système.

**Recommandation** : Persister une clé fiable. Soit stocker `conflict.translationUnitId` dans `translation_version_id` (ou ajouter une requête d'historique basée sur `translation_unit_id`), et faire en sorte que `detectConflict` accepte/propage le `translation_version_id` de façon cohérente. Au minimum, faire requêter `getConflictHistory` par `translation_unit_id` qui est toujours peuplé.

### executeReadOnly ne fournit ni isolation transactionnelle ni prévention d'écriture malgré son contrat

fichier `lib/services/concurrency/transaction_manager.dart:260-278` · catégorie api-misuse · confiance high

**Problème** : Le commentaire de doc indique que cette méthode est « optimisée pour les opérations de lecture, prévient les écritures accidentelles » et « SQLite supporte les transactions DEFERRED pour les lectures ». L'implémentation appelle simplement `query(_db)` en passant le `Database` brut sans wrapper transactionnel ni application read-only. Le callback reçoit un handle `Database` complet et peut exécuter des écritures arbitraires ; il n'y a pas non plus de snapshot cohérent sur plusieurs lectures.

```dart
// SQLite supports DEFERRED transactions for reads
final result = await query(_db);
return Ok(result);
```

**Impact** : Latent : `executeReadOnly` n'a aucun appelant en production (seul `TransactionManager` est câblé via GetIt). Aucun appelant n'est trompé aujourd'hui et aucune donnée n'est corrompue ; c'est une incohérence doc-vs-implémentation sur une API inutilisée.

**Recommandation** : Soit envelopper le callback dans une vraie transaction deferred/read (ou une `readTransaction` si disponible) pour donner un snapshot cohérent, soit corriger la documentation pour indiquer qu'aucune isolation n'est fournie. Ne pas annoncer une prévention d'écriture non appliquée.

### Cache et UI faible coût

### waitForFileRelease utilise une ouverture en lecture non exclusive et ne peut détecter un fichier verrouillé

fichier `lib/services/file/pack_export_utils.dart:232-277` · catégorie concurrency · confiance medium

**Problème** : La méthode est documentée pour détecter quand RPFM/Windows tient encore le fichier pack (« Try to open the file for reading with exclusive access ») mais elle ouvre avec `file.open(mode: FileMode.read)`. Sous Windows une ouverture en lecture utilise un accès partagé (FILE_SHARE_READ) et réussit même si un autre processus tient le fichier ouvert en écriture avec un partage coopératif. Une ouverture en lecture ne peut donc pas détecter un verrou en écriture, et le commentaire « exclusive access » est faux.

```dart
final randomAccessFile = await file.open(mode: FileMode.read);
```

**Impact** : L'export peut procéder pendant que RPFM/AV tient encore le pack ouvert via un verrou coopératif partagé, mais la fonction n'est pas le no-op décrit : elle détecte significativement les verrous deny-share les plus courants (scan AV après écriture). Faiblesse mineure / durcissement de documentation plutôt qu'une régression de corruption intermittente.

**Recommandation** : Pour détecter un verrou en écriture, il faut demander un accès en écriture/exclusif (par ex. ouverture `FileMode.append`/`writeOnlyAppend`, ou rename-puis-rename) ; lire seul ne peut prouver que l'écrivain a relâché. Au minimum, ouvrir dans un mode écriture (sans tronquer) et traiter `FileSystemException` comme « encore verrouillé », et corriger le commentaire.

### L'arrêt de l'app (checkpoint WAL) est fire-and-forget et lié à AppLifecycleState.detached peu fiable

fichier `lib/main.dart:308-343` · catégorie data-integrity · confiance medium

**Problème** : `_AppLifecycleObserver.didChangeAppLifecycleState` n'exécute le nettoyage que quand `state == AppLifecycleState.detached`, et invoque `_cleanupAsync()` sans l'attendre (le callback est void). `_cleanupAsync()` attend `DatabaseService.checkpointWal()` puis dispose l'`EventBus`. Sous Windows desktop, aucun `WindowListener`/`setPreventClose` n'est enregistré, donc l'état `detached` — s'il est livré — arrive juste avant le teardown du processus, qui peut sortir avant que `PRAGMA wal_checkpoint` ne se termine. Le commentaire « await to ensure completion » au site d'appel est trompeur.

```dart
if (state == AppLifecycleState.detached) {
  debugPrint('🧹 Application shutting down, cleaning up resources...');
  _cleanupAsync(); // not awaited; process may exit before checkpoint completes
}
```

**Impact** : Le chemin de nettoyage documenté est effectivement mort/best-effort. Sous WAL avec recovery au prochain démarrage, cela ne cause AUCUNE perte de données ni corruption (les transactions committées sont durables dans le WAL) — seulement un merge/truncate différé du WAL. La machinerie d'arrêt propre prévue (`ServiceLocator.dispose` -> `DatabaseService.close` avec checkpoint TRUNCATE) n'est de plus jamais invoquée en production.

**Recommandation** : Enregistrer un `WindowListener` window_manager avec `setPreventClose(true)` et effectuer le checkpoint+dispose attendu dans `onWindowClose` avant `destroy()`. S'appuyer sur `AppLifecycleState.detached` pour le teardown desktop n'est pas fiable ; au minimum, attendre le nettoyage synchronement dans un handler de fermeture qui bloque la destruction de fenêtre jusqu'à la fin du checkpoint. Corriger le commentaire trompeur au site d'appel.

### Les StreamControllers broadcast des services publish/steamcmd ne sont jamais fermés (dispose du singleton jamais appelé)

fichier `lib/services/steam/workshop_publish_service_impl.dart:55-58, 910-915` · catégorie resource-leak · confiance medium

**Problème** : `WorkshopPublishServiceImpl` (singleton lazy) crée `_progressController` et `_outputController` (broadcast) et ne les ferme que dans `dispose()`. Rien n'appelle `dispose()` sur un singleton lazy GetIt pour la durée de vie de l'app. `SteamCmdServiceImpl` (aussi singleton lazy) a le même pattern. Le notifier de publication unique souscrit à chaque publication et annule ses souscriptions, donc la fuite est bornée, mais les contrôleurs eux-mêmes ne sont jamais relâchés.

**Impact** : Mineur : les contrôleurs vivent pour toute la durée du processus. Pas une fuite croissante car les souscriptions sont annulées par opération, mais si le singleton était recréé/remplacé (tests, hot restart, reset du locator) les anciens contrôleurs fuiraient. Surtout un problème d'hygiène/correctness de test.

**Recommandation** : Enregistrer un callback de dispose avec GetIt (`registerLazySingleton(..., dispose: (s) => s.dispose())`) pour que les contrôleurs soient fermés au reset du locator, ou recréer le service par opération. Confirmer que `dispose()` est câblé partout où le locator est réinitialisé.

### Performance et UI à faible impact

### La barre de pagination est vivante pendant une recherche active mais ses contrôles sont morts et ses comptes faux

fichier `lib/features/translation_memory/widgets/tm_pagination_bar.dart:23-26, 84-87` · catégorie performance · confiance medium

**Problème** : Quand le champ de recherche a du texte, la grille bascule sur `tmSearchResultsProvider` qui ignore page/offset et retourne jusqu'à `limit: 1000` correspondances. La barre de pagination dérive pourtant toujours son nombre de pages et son texte « showing X-Y of Z » de `tmEntriesCountProvider` — le compte total de lignes non filtré par recherche. Cliquer une page (qui appelle `setPage`) n'a aucun effet car le provider de recherche ne lit jamais l'état de page.

```dart
final countAsync = ref.watch(tmEntriesCountProvider(
      targetLang: filterState.targetLanguage,
    ));
...
final totalPages = (totalCount / _itemsPerPage).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();
```

**Impact** : Pendant la recherche, l'utilisateur voit des contrôles de page cliquables et un libellé de plage qui contredisent ce que la grille montre (recherche plafonnée à 1000 sans pagination). Cliquer page 2/Suivant/Dernier semble ne rien faire, et les chiffres « showing X-Y of Z » sont dénués de sens pour la vue filtrée. Confus, et peut masquer le fait que les résultats de recherche sont tronqués à 1000.

**Recommandation** : Quand `filterState.searchText` est non vide, masquer la barre de pagination (ou afficher un simple compteur de résultats) puisque le chemin de recherche n'est pas paginé. Alternativement, piloter la barre depuis la longueur des résultats de recherche tant qu'une recherche est active.

### La validation de chemin recompute tout à chaque ligne de log streamée (O(n) par entrée)

fichier `lib/widgets/logs/log_console_window.dart:62-73, 90-97, 302-303` · catégorie performance · confiance medium

**Problème** : Chaque `LogEntry` entrant déclenche `setState`, et `build()` recompute le getter `_visible`, qui itère toute la liste `_entries` (jusqu'à `_maxEntries = 5000`), exécute `e.format().toLowerCase().contains(q)` par entrée, et reconstruit la `ListView`. Pendant une exécution de traduction bruyante émettant beaucoup de lignes par seconde, c'est un scan O(n) par ligne, sur le thread UI tant que la console est ouverte.

```dart
List<LogEntry> get _visible {
  final q = _search.trim().toLowerCase();
  return _entries.where((e) {
    if (!_activeLevels.contains(e.level)) return false;
    if (q.isEmpty) return true;
    return e.format().toLowerCase().contains(q);
  }).toList();
}
```

**Impact** : Avec la console ouverte et des milliers d'entrées bufferisées (surtout avec un filtre de recherche non vide, qui force `format()`+`toLowerCase` sur les 5000 à chaque frame), les opérations bruyantes en logs peuvent causer des saccades/pertes de frames. Borné par 5000 mais gaspilleur. N'a lieu que tant que la fenêtre console est montée.

**Recommandation** : Mettre en cache la liste filtrée et ne la recomputer que lorsque les filtres/recherche changent ou lorsque des entrées sont ajoutées (filtrage incrémental append-only). Au minimum, throttler/debouncer le `setState` dans `_onEntry` (batcher les entrées arrivant dans une frame) et pré-calculer le texte minusculisé une fois par entrée.

### handlePaste fait un scan firstWhere O(n*m) par ligne collée et lève/capture pour les non-correspondances

fichier `lib/features/translation_editor/widgets/grid_actions_handler.dart:90-110` · catégorie performance · confiance medium

**Problème** : Pour chaque ligne TSV collée, `dataSource.translationRows.firstWhere((row) => row.key == key)` effectue un scan linéaire de toutes les lignes et s'appuie sur un `StateError` levé (capturé) pour le cas non-trouvé. Avec une grande grille et un gros collage, c'est O(linesPasted * rowCount), et le contrôle de flux par exception s'exécute une fois par clé non appariée. La source de données maintient déjà une map id->row (`_rowsById`) mais aucun index key->row.

```dart
final matchingRow = dataSource.translationRows.firstWhere(
  (row) => row.key == key,
); // O(n) per line, throws when key absent
```

**Impact** : Coller un gros bloc dans un projet de dizaines de milliers d'unités devient lent et alloue/capture des exceptions pour chaque clé non appariée. Non corrupteur, mais une saccade notable sur de gros collages.

**Recommandation** : Construire une `Map<String, TranslationRow>` clée par `row.key` une fois avant la boucle (ou l'exposer depuis `EditorDataSource`), et chercher avec `map[key]` au lieu de `firstWhere`+try/catch.

### Éditer une compilation existante ne persiste pas les changements de formulaire/projet avant de générer le pack

fichier `lib/features/pack_compilation/providers/compilation_editor_notifier.dart:242-246` · catégorie data-integrity · confiance medium

**Problème** : `generatePack` n'appelle `saveCompilation` que quand `!state.isEditing` (mode création). En mode édition, il saute la sauvegarde et construit le pack depuis le `state` en mémoire (selectedProjectIds, prefix, name). Le pack est donc généré depuis la sélection éditée, mais ces éditions ne sont jamais réécrites en DB — seul `updateAfterGeneration(compilationId, packPath)` s'exécute.

```dart
// First save if needed
if (!state.isEditing) {
  final saved = await saveCompilation(gameInstallationId);
  if (!saved) return null;
}
```

**Impact** : Après avoir édité la liste de projets/le préfixe d'une compilation et cliqué Compiler (sans Sauvegarder séparément), le `.pack` produit reflète la nouvelle sélection mais rouvrir la compilation montre l'ancienne sélection stockée. L'analyse de conflits que l'utilisateur a revue (depuis la sélection vivante) ne correspondra pas non plus à l'enregistrement persisté. État incohérent/confus ; potentiel de regénérer un pack différent plus tard.

**Recommandation** : En mode édition, persister l'état courant du formulaire avant de générer (appeler `saveCompilation(gameInstallationId)` et abandonner en cas d'échec), à l'image du chemin de création, pour que la ligne DB corresponde au pack généré.

### La vérification des notes de version re-frappe l'API GitHub à chaque démarrage quand la version installée est en retard

fichier `lib/features/release_notes/services/release_notes_service.dart:55-75` · catégorie performance · confiance medium

**Problème** : `checkShouldShowReleaseNotes` ne marque une version comme vue qu'au premier lancement (lastSeen vide) ou quand l'utilisateur rejette explicitement le dialogue. Quand `lastSeenVersion != currentVersion`, il fetch toujours la dernière release GitHub, et si `release.version != currentVersion` (build installé plus ancien que la release la plus récente — exactement la situation après que l'utilisateur a différé la mise à jour), il retourne null SANS marquer la version courante comme vue. Rien n'étant persisté, le lancement suivant répète le fetch réseau.

```dart
if (release.version == currentVersion) {
  return release;
}
// Version mismatch - fail silently
debugPrint('[ReleaseNotes] Version mismatch: ...');
return null;  // currentVersion never marked seen -> re-fetches next launch
```

**Impact** : Un utilisateur en retard d'une ou plusieurs versions encourt un appel API GitHub à chaque démarrage indéfiniment, sans qu'aucun dialogue de notes de version ne soit montré pour rompre la boucle. Mineur, mais c'est de l'I/O réseau répété inutile au démarrage et cela peut atteindre les limites de débit GitHub sur des IPs partagées.

**Recommandation** : Sur la branche de mismatch de version, persister `currentVersion` via `markVersionAsSeen(currentVersion)` avant de retourner null, pour que le fetch ne soit pas répété aux démarrages suivants pour le même build installé.

### Les champs de clé API écrivent en stockage sécurisé et rechargent tous les paramètres provider à chaque frappe

fichier `lib/features/settings/widgets/llm_provider_section.dart:94` · catégorie performance · confiance high

**Problème** : Le `TokenTextField` de clé API utilise `onChanged: (_) => widget.onSaveApiKey()`, sans debounce. Chaque frappe appelle par ex. `updateAnthropicApiKey` qui fait `_secureStorage.write(...)` suivi de `ref.invalidateSelf()`. `invalidateSelf` réexécute `LlmProviderSettings.build()`, qui effectue cinq `_secureStorage.read()` séquentiels plus plusieurs `getString/getInt` DB. Chaque caractère tapé déclenche donc une écriture chiffrée + cinq lectures chiffrées + ~6 lectures DB.

```dart
TokenTextField(
  controller: widget.apiKeyController,
  ...
  onChanged: (_) => widget.onSaveApiKey(),
)
```

**Impact** : Taper/coller une clé API produit une rafale d'opérations de chiffrement/déchiffrement flutter_secure_storage et de rechargements complets de paramètres provider. flutter_secure_storage sur Windows est comparativement lent ; cela cause du lag de saisie et du churn inutile. La garde `_initialLoadDone` empêche d'écraser les contrôleurs, donc c'est de la performance et non de la correctness, mais reste de l'I/O crypto par frappe.

**Recommandation** : Debouncer `onSaveApiKey` (le fichier importe déjà `dart:async` et utilise un debounce à base de Timer pour le slider de rate-limit), ou sauvegarder à la perte de focus / `onEditingComplete` au lieu de `onChanged`.

### Le champ texte de chemin de jeu déclenche l'auto-provisioning de glossaire et un rechargement complet des paramètres à chaque frappe

fichier `lib/features/settings/widgets/general/game_installations_section.dart:120, 215-223` · catégorie performance · confiance high

**Problème** : Le `TextFormField` de chemin de jeu câble `onChanged: (value) => _saveGamePath(game.code, value)`, sans debounce. `_saveGamePath` appelle `updateGamePath`, qui à chaque appel : (1) écrit le chemin partiel en DB, (2) appelle `ref.invalidateSelf()` forçant `build()` à relire les ~15 clés de paramètres, et (3) quand le champ est non vide, déclenche `provisionForGame(gameCode)` — une opération touchant la DB — pour le chemin à demi tapé.

```dart
onChanged: (value) => _saveGamePath(game.code, value),
...
Future<void> _saveGamePath(String gameCode, String path) async {
  await ref.read(generalSettingsProvider.notifier).updateGamePath(gameCode, path);
}
```

**Impact** : Pendant que l'utilisateur tape un chemin de jeu, l'app effectue une écriture DB, un rechargement complet multi-clés de paramètres et un auto-provision de glossaire par frappe. Les futures `provisionForGame()` non attendues se chevauchent, causant du churn DB redondant. `provisionForGame` se clé sur `game_code` (pas la chaîne tapée) et est idempotent, donc pas de mauvais provisioning ni de corruption — uniquement du travail gaspillé sur une DB locale.

**Recommandation** : Debouncer la sauvegarde `onChanged` (par ex. un Timer comme le slider de rate-limit l'utilise déjà), et ne déclencher `provisionForGame` qu'à la validation (`onEditingComplete` / sélecteur de fichier / détection) plutôt qu'à chaque caractère.

### TokenCalculator le cache est FIFO, pas LRU comme documenté

fichier `lib/services/llm/utils/token_calculator.dart:13-16, 48-63, 181-189` · catégorie performance · confiance high

**Problème** : `_addToCache` évince `_cache.keys.first` (ordre d'insertion) en cas de débordement, en faisant un cache FIFO, pas LRU — les doc-commentaires et `getCacheStatistics` annoncent LRU. `calculateTokens` ne déplace pas un hit en fin de liste, donc les chaînes fréquemment réutilisées (même prompt système / termes de glossaire répétés) sont évincées tandis que des chaînes ponctuelles demeurent.

```dart
void _addToCache(String text, int tokens) {
  if (_cache.length >= _maxCacheSize) {
    final firstKey = _cache.keys.first;  // FIFO eviction, not LRU
    _cache.remove(firstKey);
  }
  _cache[text] = tokens;
}
```

**Impact** : Pour de grands ensembles de traduction avec >10k chaînes distinctes, les entrées les plus chaudes sont évincées en premier, dégradant le cache jusqu'à le rendre quasi inutile et réexécutant l'encodage tiktoken (CPU sur l'isolate UI) bien plus que prévu — une vraie régression de perf sur les gros mods. Le label « LRU » trompeur peut masquer la cause lors du profilage.

**Recommandation** : Implémenter un vrai LRU (par ex. remove+reinsert sur hit, ou re-keyer à l'accès) ou renommer en FIFO et ajuster la doc. Confirmer que tous les accès restent sur un seul isolate ; sinon, garder la map.

## Thèmes transverses

1. **Résolution de version/langue sans filtrage par langue.** Trois défauts d'intégrité majeurs (édition de cellule, deux chemins d'import) partagent la même racine : utiliser `getByUnit(unitId).first` ou écrire `targetLanguageId` brut au lieu de résoudre le `project_language_id` scopé à la langue affichée. La méthode correcte (`getByUnitAndProjectLanguage`) existe déjà et est utilisée ailleurs. Action : auditer tout accès aux `TranslationVersion` et imposer systématiquement une résolution par `project_language_id`, et donner des `created_at` distincts aux versions par langue pour supprimer l'ambiguïté d'ordre.

2. **Opérations multi-écritures non transactionnelles.** Plusieurs flux (import par ligne, `applyModifiedSourceTexts` source+statut, `deleteLanguage` TM+langue, `addNewUnits`, init de projet, création de glossaire DeepL) effectuent des séquences d'écritures DB liées sans transaction englobante ni compensation. Action : envelopper chaque séquence d'écritures liées dans une `DatabaseService.transaction` (en propageant la `txn` aux helpers/repositories), garantissant atomicité et rollback. Cela corrige aussi plusieurs des défauts de batching/performance en passant.

3. **Avalement d'erreurs transformant les échecs en succès silencieux.** La branche `.loc` héritée retourne `Ok` malgré des échecs RPFM, `searchAll` jette l'`Err` de `searchTranslationVersions`, l'import compte `successCount` pour des versions orphelines, et les imports avalent les erreurs DB en « non trouvé ». Action : distinguer « rien trouvé » d'« échec réel », propager les `Err` au lieu de les masquer, et vérifier le résultat effectif (nombre d'entrées loc, FK valide) plutôt que de simples préconditions comme l'existence d'un fichier.

4. **État mutable partagé sur singletons et absence de jetons de génération.** Les services Steam (publish/steamcmd singletons avec `_isCancelled`/`_currentProcess`), le scanner Workshop (contrôleur broadcast partagé), et l'analyse de conflits (pas de jeton de requête) souffrent d'interférences concurrentes ou d'écritures en course. Action : sérialiser les opérations avec des gardes de ré-entrance, scoper l'état d'annulation par opération (jeton d'annulation), et invalider les résultats asynchrones obsolètes via un id de requête monotone.

5. **L'idiome `field ?? this.field` dans copyWith empêche d'effacer les champs nullables.** Présent dans la plupart des modèles de domaine et concrètement déclenché par « Rejeter la traduction » (qui ne vide pas le texte), `BatchOperationState.complete()` et `RescanState`. Le précédent `LlmCustomRule.copyWith` (drapeau `clearX`) montre le bon pattern. Action : adopter des drapeaux `clearX` ou des sentinelles `ValueGetter` pour les champs nullables réellement effaçables.

6. **Lecture de processus et parsing de flux fragiles.** `ProcessService` annule les souscriptions avant drainage (sortie tronquée), la détection batch steamcmd parse ligne par événement sans tampon de report, et la console de logs re-filtre tout à chaque ligne. Action : drainer les flux jusqu'à `onDone` avant de lire les buffers, maintenir un tampon de lignes persistant entre événements stdout/stderr, et ajouter une réconciliation finale sur le buffer complet.

## Périmètre & méthode

Cette revue a couvert 22 shards sur environ 237k lignes de code. Chaque constat a fait l'objet d'une vérification adversariale par lecture directe du code source, des sites d'appel et de l'historique git : 25 constats candidats ont été réfutés et écartés, et plusieurs sévérités ont été ajustées à la baisse lorsque la vérification a révélé un chemin mort, un déclencheur irréaliste ou un impact surévalué. Les constats restants sont ceux dont chaque prémisse porteuse a résisté à la tentative de réfutation. `flutter analyze` était propre (0 problème) au moment de la revue ; aucun constat ne relève de ce que l'analyseur statique capterait déjà (variables inutilisées, awaits manquants signalés par le linter, etc.).