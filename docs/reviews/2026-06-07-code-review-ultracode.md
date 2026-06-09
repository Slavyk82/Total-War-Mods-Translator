Voici le rapport de revue de code final.

---

# Revue de code — Total War Mods Translator

## Résumé exécutif

Cette revue consolide 53 constats vérifiés sur l'application Flutter Total War Mods Translator. Les défauts les plus graves sont fonctionnels et directement visibles par l'utilisateur : la recherche par regex est complètement cassée (colonne SQL inexistante), l'annulation d'une saisie dans la mémoire de traduction provoque un crash, le pipeline de compilation ignore les résolutions de conflits et le hardcodage de l'AppID Workshop publie vers le mauvais jeu Steam pour 8 des 9 jeux supportés. Au-delà des bugs isolés, trois patterns systémiques dominent : des écritures multi-tables non transactionnelles laissant des données orphelines, des mutations d'état/`setState` après dispose dans des callbacks asynchrones non gardés, et un encodage de chemin fragile par substitution de chaînes qui corrompt silencieusement les fichiers `.loc`.

## Décompte par sévérité

| Sévérité | Nombre |
|----------|--------|
| Critique | 0 |
| Élevé | 9 |
| Moyen | 24 |
| Faible | 20 |
| **Total** | **53** |

---

## Élevé

### Correctness

**La recherche par regex référence une colonne inexistante `translation_unit_id` — toute recherche regex échoue**
`lib/services/search/utils/regex_query_builder.dart:48`
Le JOIN utilise `tv.translation_unit_id = tu.id`, mais la colonne réelle de la clé étrangère dans `translation_versions` est `unit_id`. SQLite lève `no such column: tv.translation_unit_id` à l'analyse de la requête, donc toute recherche regex (quel que soit `searchIn`) renvoie systématiquement une `SearchDatabaseException`. Atteignable depuis l'UI via `search_providers.dart:119`.
```sql
LEFT JOIN translation_versions tv ON tv.translation_unit_id = tu.id
```
**Correctif** : remplacer la condition par `LEFT JOIN translation_versions tv ON tv.unit_id = tu.id`.

**Le bouton Annuler du dialogue d'édition de TM renvoie un `bool` dans un `showDialog<String>`, crash à l'annulation**
`lib/features/translation_memory/widgets/tm_edit_dialog.dart:123`
Le dialogue est ouvert via `showDialog<String>` (`tm_browser_datagrid.dart:343`). Le bouton Annuler appelle `Navigator.of(context).pop(false)` : Flutter tente de caster `false as String?` et lève `type 'bool' is not a subtype of type 'String?'`. Toute annulation explicite crashe de façon fiable (Enregistrer fonctionne car il renvoie une String ; le dismiss par barrière renvoie null, OK).
```dart
onTap: _saving ? null : () => Navigator.of(context).pop(false),
```
**Correctif** : remplacer par `Navigator.of(context).pop()` (l'appelant traite déjà null comme « aucun changement »).

### Data-integrity

**Les résolutions de conflits de compilation ne sont jamais appliquées à la génération du pack**
`lib/features/pack_compilation/providers/compilation_editor_notifier.dart:257-307`
`generatePack` itère sur chaque projet sélectionné et copie tous ses fichiers TSV `.loc` dans la structure du pack sans aucune référence aux choix de l'utilisateur. `CompilationConflictService.applyResolutions`/`getWinningEntry` ne servent qu'à l'affichage de l'analyse à l'écran (`getWinningEntry` n'a aucun appelant). Le choix « utiliser le premier / le second / ignorer » n'a donc aucun effet sur le `.pack` produit : le résultat dépend uniquement de l'ordre de traitement et de l'écrasement de fichiers. Le workflow de résolution est purement cosmétique (il ne fait que supprimer le dialogue d'avertissement avant compilation).
```dart
for (final projectId in projectIds) {
  final result = await locFileService.generateLocFilesGroupedBySource(...);
  await packUtils.copyTsvFilesToPackStructure(tsvPaths, tempDir); // aucune résolution appliquée
}
```
**Correctif** : lire `compilationConflictResolutionsStateProvider` dans `generatePack` et n'émettre que la valeur gagnante pour chaque conflit résolu, en supprimant les entrées perdantes/ignorées avant la copie.

**`copyTsvFilesToPackStructure` écrase silencieusement les fichiers `.loc` de même nom entre projets**
`lib/services/file/pack_export_utils.dart:46-69`
Pendant la compilation, chaque TSV est copié dans un `tempDir` partagé via un chemin interne dérivé du seul nom de fichier. Si deux projets produisent un `.loc` de même nom interne, le second `tsvFile.copy(targetPath)` écrase le premier sans fusion ni avertissement. Combiné au constat ci-dessus, les collisions de clés se résolvent en « dernier écrivain gagne » selon l'ordre d'itération, faisant disparaître des traductions des projets antérieurs du pack compilé.
```dart
final internalPath = tsvFileName.replaceAll('__', '/');
final targetPath = path.join(tempDir.path, internalPath);
await tsvFile.copy(targetPath); // écrase tout fichier de même nom déjà présent
```
**Correctif** : détecter les fichiers cibles existants et fusionner les lignes (en appliquant résolutions/déduplication par clé) au lieu d'écraser, ou nommer par projet avant fusion ; a minima logguer/lever sur collision.

**La reconstruction du chemin de pack corrompt les chemins internes quand les noms contiennent des doubles underscores**
`lib/services/file/pack_export_utils.dart:55` (encodage en `loc_file_service_impl.dart:498`)
Le pipeline encode un chemin interne `.loc` dans un nom de fichier TSV en remplaçant `/` par `__`, puis l'inverse par `replaceAll('__', '/')`. Ce round-trip est lossy : tout `__` faisant partie d'un segment réel (répertoire ou nom de base) est transformé à tort en séparateur. Round-trip vérifié : `text/db/...campaign__startpos.loc` redevient `...campaign/startpos.loc.tsv` (faux). Le TSV est placé au mauvais chemin interne, le jeu charge le mauvais `.loc` ou aucun (traduction silencieusement cassée).
```dart
final internalPath = tsvFileName.replaceAll('__', '/');
// produit depuis : '${outputLocPath.replaceAll('/', '__')}.tsv'
```
**Correctif** : ne pas encoder l'arborescence dans le nom de fichier par substitution. Générer les TSV directement sous la bonne arborescence relative, ou transporter le chemin interne en métadonnée explicite (ex. un record `(tsvPath, internalPath)`).

**L'AppID Workshop est hardcodé sur WH3 (1142710) — mauvaise app pour les 8 autres jeux supportés**
`lib/features/steam_publish/screens/workshop_publish_screen.dart:258` (aussi `steam_publish_screen.dart:272`, `steam_publish_action_cell.dart:339`)
L'app supporte 9 jeux Total War, chacun avec son `steamAppId` distinct. Les écrans de publication unitaire et par lot construisent `WorkshopPublishParams` avec un `appId` hardcodé `'1142710'` (TW:WH3). Pour un autre jeu, steamcmd publie/met à jour l'item Workshop contre la mauvaise app Steam : Steam rejette la mise à jour d'un item appartenant à une autre app, ou une nouvelle publication est créée sous WH3 au lieu du jeu sélectionné. Le bon pattern existe déjà ailleurs (`published_subs_cache_provider.dart` via `selectedGameProvider` + `getGameByCode().steamAppId`).
```dart
final params = WorkshopPublishParams(appId: '1142710', // TW:WH3
  publishedFileId: _item!.publishedSteamId!, ...);
```
**Correctif** : résoudre le `steamAppId` du jeu sélectionné et le passer comme `appId` pour les chemins unitaire et par lot, ainsi qu'à `openGameLauncher()`.

**La suppression de projet s'exécute hors transaction, FK désactivées et triggers globaux supprimés — risque de suppression partielle et corruption inter-projets**
`lib/services/projects/project_deletion_service.dart:46-219`
`deleteProject` désactive `foreign_keys`, met `synchronous=OFF`, supprime globalement tous les triggers FTS/cache/progress, puis exécute une longue série de DELETE sans transaction englobante. En cas d'échec à mi-parcours, le bloc catch ne recrée que les triggers et restaure les PRAGMA ; les lignes déjà supprimées ne sont pas annulées, laissant le projet à moitié supprimé avec des index FTS/cache incohérents. Pire, la suppression des triggers est un changement de schéma global : toute écriture concurrente sur `translation_units`/`translation_versions` pendant la fenêtre de suppression (ex. traduction par lot en cours) contourne silencieusement la maintenance FTS et cache pour d'AUTRES projets, corrompant leur index de recherche et leur cache de vue.
```dart
await db.execute('PRAGMA foreign_keys = OFF');
await db.execute('PRAGMA synchronous = OFF');
await _disableAllTriggers(db); // aucun db.transaction(...) autour des DELETE
```
**Correctif** : envelopper toute la séquence dans `db.transaction` pour un rollback atomique, et sérialiser les suppressions contre les autres écrivains (TransactionManager / verrou global d'écriture) afin que les triggers ne soient jamais supprimés pendant des écritures concurrentes. Envisager de garder les FK actives dans la transaction.

**La suppression d'une langue de projet présente le même danger non-transactionnel / triggers globaux**
`lib/services/projects/project_language_deletion_service.dart:66-177`
`deleteProjectLanguage` désactive `foreign_keys` et `synchronous`, supprime les triggers FTS/cache/progress partagés, et exécute une série de DELETE sans transaction. Un échec en cours de séquence laisse la `project_language` partiellement supprimée (versions/historique/cache désynchronisés), seuls les triggers/PRAGMA étant restaurés dans le catch. Les triggers supprimés étant globaux, toute écriture concurrente sur `translation_versions` pendant la suppression contourne la maintenance FTS/cache pour des langues de projet sans rapport. Atteignable via `ProjectLanguageRepository.delete`.
```dart
await db.execute('PRAGMA foreign_keys = OFF');
await _disableTriggers(db);
await db.rawDelete( ... ) // série de DELETE, pas de db.transaction
```
**Correctif** : envelopper les étapes dans `db.transaction` pour un rollback atomique et empêcher les écrivains concurrents pendant la suppression des triggers, ou effectuer une suppression scopée n'exigeant pas la suppression de triggers globaux.

**L'export ignore projectId/targetLanguageId/filtres et exporte toute la base**
`lib/features/import_export/services/import_export_service.dart:108-130, 164-185`
`executeExport` et `previewExport` appellent `_versionRepository.getAll()`, qui renvoie toutes les `TranslationVersion` de TOUS les projets et TOUTES les langues cibles. `ExportSettings` porte `projectId`, `targetLanguageId` et `filterOptions`, mais aucun n'est appliqué. Un utilisateur qui choisit d'exporter un seul projet/langue obtiendrait toutes les traductions de l'app (fuite de données inter-projets/inter-langues, fichier énorme et erroné). `previewExport` a le même défaut. Note : la feature ne semble pas encore branchée à un écran utilisateur, mais le défaut se manifestera dès le câblage de l'UI.
```dart
final versionsResult = await _versionRepository.getAll();
// settings.projectId / targetLanguageId / filterOptions jamais utilisés
```
**Correctif** : ne récupérer que les versions pour `settings.projectId` + `settings.targetLanguageId` (via `getByProjectLanguage` ou une requête jointe filtrée) et appliquer `settings.filterOptions` avant de construire les lignes. Idem dans `previewExport`.

---

## Moyen

### Concurrency

**Le collage presse-papier déclenche N appels `handleCellEdit` concurrents non attendus (race sur read-modify-write DB et pile d'annulation)**
`lib/features/translation_editor/widgets/grid_actions_handler.dart:119-121`
`handlePaste` boucle sur toutes les mises à jour et invoque `onCellEdit` (qui résout vers `handleCellEdit` async) sans `await`. Lancer des dizaines/centaines d'éditions concurrentes entrelace les enregistrements d'annulation (pile d'annulation dans un ordre non déterministe) et affiche le toast de succès AVANT que les éditions ne se terminent — l'utilisateur peut donc voir un toast « succès » et des dialogues d'erreur simultanément. Note : les clés étant uniques par unitId, il n'y a pas de race read-modify-write sur la même ligne ni de corruption DB.
```dart
for (final entry in updates.entries) { onCellEdit(entry.key, entry.value); }
if (context.mounted) { FluentToast.success(context, ...pasted(count: validLines)); }
```
**Correctif** : rendre `onCellEdit` Future-returning et l'`await` séquentiellement, ou ajouter un chemin de mise à jour par lot en une transaction ; n'afficher le toast de succès qu'après complétion.

**`setState` après dispose dans l'auto-détection de jeu (pas de garde mounted dans finally/callbacks)**
`lib/features/settings/widgets/general/game_installations_section.dart:141-207`
`_autoDetectGame` et `_autoDetectAllGames` attendent un service de détection async puis appellent `setState` inconditionnellement dans le bloc `finally` (et dans les callbacks `.when` ok) sans garde `mounted`. Si l'utilisateur quitte l'onglet pendant une détection (les scans Steam prennent plusieurs secondes), le State est disposé et ces `setState` lèvent `setState() called after dispose()`. Le `WorkshopSection` voisin garde correctement chaque `setState`, prouvant que ce fichier est l'incohérent.
```dart
} finally { setState(() => _isDetecting = false); } // aucune garde mounted
```
**Correctif** : envelopper chaque `setState` post-await dans `if (mounted)`, y compris ceux des callbacks `.when` ok.

**La publication par lot écrit l'ID Workshop en DB en fire-and-forget, en course avec l'invalidation de la liste**
`lib/features/steam_publish/providers/batch_workshop_publish_notifier.dart:201`
Dans `onItemComplete` (callback synchrone), `_saveWorkshopId(item, publishResult.workshopId)` est appelé sans `await`. `_saveWorkshopId` est async et persiste `publishedSteamId`/`publishedAt`. Après `service.publishBatch()`, `ref.invalidate(publishableItemsProvider)` peut s'exécuter avant la fin des écritures DB, donc la liste rafraîchie peut montrer des items comme non publiés alors que l'upload a réussi — l'utilisateur risque de re-publier. Le chemin de publication unitaire attend correctement son enregistrement avant d'invalider.
```dart
_saveWorkshopId(item, publishResult.workshopId); // non attendu
```
**Correctif** : faire en sorte que `onItemComplete` attende l'enregistrement, ou collecter les Futures et `await Future.wait(pendingSaves)` avant `ref.invalidate`.

**La publication unitaire lit la sortie de steamcmd avant le drainage des flux stdout/stderr**
`lib/services/steam/workshop_publish_service_impl.dart:786-802`
`_runSteamCmd` attend `exitCode` et retourne immédiatement `stdout.toString()`. Contrairement à `_runBatchProcess` (qui utilise un `outputCompleter` attendant `onDone`), ce chemin n'attend pas la fin du drainage des listeners. Le processus peut sortir alors que de la sortie est encore en file dans le flux Dart, donc `run.output` peut être tronqué. L'appelant teste `'Login Failure'`/`'Invalid Password'`/`'Failed to update workshop item'` sur une sortie potentiellement tronquée : un échec de login ou un item supprimé peut être manqué et rapporté comme succès, et `detectedWorkshopId` perdu.
```dart
final exitCode = await _currentProcess!.exitCode.timeout(...);
return (exitCode: exitCode, output: stdout.toString(), ...);
```
**Correctif** : comme le chemin par lot, enregistrer des handlers `onDone` sur stdout/stderr complétant un Completer, et l'`await` (avec court timeout) après `exitCode` avant de lire `stdout.toString()`.

**`retry()` et `startUpdates()` se disputent `_progressSubscription`/`_currentProjectId` partagés**
`lib/providers/mods/mod_update_provider.dart:119-263, 341-352`
`startUpdates()` (lancé en fire-and-forget depuis `whats_new_dialog.dart:101`) et `retry()` sont tous deux async et non gardés, et appellent `_updateProject()` qui mute les champs à slot unique `_progressSubscription` et `_currentProjectId`. Si l'utilisateur déclenche un retry pendant que la boucle de `startUpdates()` traite un autre projet, le retry annule l'abonnement de progression du projet en cours et écrase `_currentProjectId`. Le projet en téléchargement cesse de recevoir les mises à jour, et un `cancelAll()` ultérieur ciblera le mauvais projet.
```dart
_progressSubscription?.cancel();
_progressSubscription = steamService.progressStream.listen((p) => _updateProgress(projectId, p));
_currentProjectId = projectId;
```
**Correctif** : sérialiser l'exécution des mises à jour (worker/queue unique ou garde de ré-entrance) et suivre les abonnements/current-id par projet plutôt qu'un slot partagé unique.

### Correctness

**La détection de clés dupliquées à la validation n'inspecte que l'aperçu de 10 lignes, pas le fichier**
`lib/features/import_export/services/import_preview_service.dart:87-110`
La détection de doublons de `validateImport` itère sur `preview.previewRows`, plafonné à 10 lignes (`fileData.rows.take(10)`). Le texte d'avertissement dit « clés dupliquées dans l'aperçu », mais l'import traite tout le fichier. Les clés dupliquées au-delà des 10 premières lignes ne sont jamais signalées, donnant aux utilisateurs de gros fichiers un faux sentiment d'absence de doublons.
```dart
for (final row in preview.previewRows) { // 10 premières lignes seulement
  if (keys.contains(key)) { duplicateKeys.add(key); }
```
**Correctif** : relire le fichier complet quand `checkDuplicates` est activé et scanner toutes les lignes, ou stocker l'ensemble complet sur le preview.

**`migrateLegacyHashes` peut boucler indéfiniment si `updateHash` échoue pour une ligne**
`lib/services/translation_memory/tm_maintenance_service.dart:216-262`
La boucle de migration récupère les lots avec `offset:0` fixe, comptant sur le fait que chaque ligne traitée soit supprimée ou voie son hash réécrit en 64 caractères. Mais si `updateHash` retourne Err (executeQuery convertit les erreurs DB en Err sans lever), la ligne n'est ni supprimée ni migrée. `getEntriesWithLegacyHashes` ordonnant par id, cette même ligne défaillante revient en premier à chaque itération, et la boucle `while(true)` ne progresse jamais → blocage. Déclencheur réaliste : erreur DB transitoire (verrou, I/O, disque plein).
```dart
final updateResult = await _repository.updateHash(entry.id, newHash);
if (updateResult.isOk) { migratedCount++; }
// sinon : la ligne reste legacy, offset reste 0 → refetch éternel
```
**Correctif** : détecter qu'un lot ne fait aucun progrès (aucune ligne migrée ni supprimée) et abandonner avec erreur, ou avancer un curseur d'id pour passer outre les lignes en échec.

### Data-integrity

**L'écriture des timestamps `translation_version` à l'import de pack est en millisecondes alors que le reste de l'app utilise les secondes**
`lib/features/translation_editor/services/pack_import_service.dart:306, 314-333`
`executeImport` horodate `createdAt`/`updatedAt` avec `DateTime.now().millisecondsSinceEpoch`, alors que tous les autres écrivains de `TranslationVersion` utilisent `~/ 1000` (secondes). Les versions nouvellement insérées persistent donc des timestamps ~1000x plus grands, et les lignes mises à jour reçoivent `updated_at` en ms. Cela pollue `version_updated_at` (utilisé par l'index de tri par récence du cache de vue), faisant remonter à tort les lignes touchées par l'import dans les vues triées par récence, et casse tout rendu/filtre de date supposant des secondes. Note : la corruption de « version courante » initialement craint n'est pas atteignable (une seule version par unité/langue).
```dart
final now = DateTime.now().millisecondsSinceEpoch; // devrait être ~/ 1000
```
**Correctif** : utiliser `~/ 1000` pour `createdAt`/`updatedAt` ; garder une valeur ms séparée uniquement pour le suffixe d'id si l'unicité est souhaitée.

**Ajouter une langue n'est pas transactionnel — un échec d'insert de version laisse une `project_language` orpheline**
`lib/features/projects/widgets/add_language_dialog.dart:239-277`
`_addLanguages` insère la ligne `project_language`, puis un lot de `TranslationVersion`, en deux appels DB indépendants sans transaction. Si `insertBatch` échoue, la `project_language` est déjà commitée, laissant une langue configurée sans aucune version : les statistiques se calculent sur une langue vide et la langue ne peut jamais être pleinement traduite. Avec plusieurs langues sélectionnées, un échec précoce laisse aussi les langues déjà traitées à moitié créées.
```dart
final result = await projectLangRepo.insert(projectLanguage);
final versionResult = await translationVersionRepo.insertBatch(versionsToInsert); // pas de transaction commune
```
**Correctif** : envelopper l'insert de `project_language` et l'`insertBatch` (idéalement toute la boucle) dans une transaction unique, ou supprimer la `project_language` insérée dans le catch avant de remonter l'erreur.

**La création de projet ignore le résultat de l'insert `project_language` et n'est pas transactionnelle avec l'insert du projet**
`lib/features/projects/widgets/create_project/create_project_dialog.dart:239-253`
`_createProject` vérifie `projectRepo.insert(project)` mais ignore entièrement le retour de `projectLangRepo.insert(projectLanguage)`. Si cet insert échoue, le code continue silencieusement : le provisionnement du glossaire et l'initialisation des fichiers se font sur un projet sans langue cible. Le projet s'ouvrira ensuite sur « This project has no target language ». Le commentaire au-dessus prétend même que le résolveur est fait en premier pour éviter « un projet à moitié créé sans ligne project_language ».
```dart
await projectLangRepo.insert(projectLanguage); // résultat ignoré, jamais vérifié
```
**Correctif** : capturer et vérifier le Result ; en cas d'erreur, annuler (supprimer le projet) ou remonter l'échec. Préférer envelopper les deux inserts dans une transaction.

**Projet orphelin laissé en DB quand l'initialisation de traduction de jeu échoue**
`lib/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart:176-258`
`_createProject` insère le Project, les `project_languages`, provisionne les glossaires, puis lance `initializeProject` (extraction de pack). Le résultat de `initializeProject` (qui retourne un Result, pas une exception) n'est PAS vérifié : en cas d'échec d'init, le code tombe jusqu'à `Navigator.pop(projectId)` et rapporte un succès tout en laissant un projet orphelin non initialisé en DB, sans erreur affichée. Aucun rollback dans le catch, contrairement à `ModsScreenController._createProjectFromMod`.
```dart
final result = await projectRepo.insert(project);
... await initService.initializeProject(...) // .isErr non vérifié
} catch (e) { setState(() => _errorMessage = e.toString()); } // pas de rollback
```
**Correctif** : suivre `projectId` et le supprimer en cas d'échec, et vérifier explicitement le Result de `initializeProject`.

**Définir manuellement un ID Workshop sur une compilation non publiée écrit `published_at=0`, la marquant en permanence comme obsolète**
`lib/features/steam_publish/widgets/steam_id_editing.dart:52`
Quand l'utilisateur saisit un ID Workshop pour une compilation jamais publiée (`publishedAt == null`), `saveWorkshopId` appelle `compilationRepo.updateAfterPublish(id, parsed, item.publishedAt ?? 0)`, écrivant `published_at = 0`. Le filtre/compteur « obsolète » utilise `e.publishedAt != null && e.exportedAt > e.publishedAt!`. Avec `publishedAt` à 0 (non-null), toute compilation générée est signalée obsolète à jamais. La branche projet de la même fonction n'a pas ce défaut (elle laisse `publishedAt` à null).
```dart
await compilationRepo.updateAfterPublish(item.compilation.id, parsed, item.publishedAt ?? 0);
```
**Correctif** : ne pas écrire `published_at=0` lors d'une simple association d'ID. Préserver le `publishedAt` existant (méthode dédiée ne mettant à jour que `published_steam_id`), en miroir de la branche projet.

**`addNewUnits` insère l'unité et ses versions sans transaction (écriture partielle)**
`lib/services/mods/mod_update_analysis_service.dart:442-504`
Pour chaque nouvelle unité, le code insère la `TranslationUnit` puis boucle pour insérer une `TranslationVersion` par langue de projet, chaque écriture étant séparée et sans transaction englobante. Si un insert de version échoue (ou crash/scan interrompu en milieu de boucle), l'unité reste avec un ensemble de versions manquant ou partiel — un état que le reste de l'app suppose impossible (le cache de vue se crée par version via trigger). Les échecs d'insert ne sont loggués qu'en warning et l'unité est quand même comptée comme ajoutée.
```dart
final insertResult = await _unitRepository.insert(unit);
for (final language in languages) {
  final versionResult = await _versionRepository.insert(version);
  if (versionResult.isErr) { _logger.warning(...); }
}
unitsAdded++;
```
**Correctif** : envelopper l'insert de l'unité et de ses versions par langue dans une transaction unique ; sur erreur, rollback (ou au moins ne pas compter l'unité comme ajoutée).

**L'export CSV ne protège pas `source_term`/`target_term` contenant virgules ou guillemets**
`lib/services/glossary/glossary_export_service.dart:55-59`
`exportToCsv` n'entoure de guillemets que le champ `notes` quand il contient une virgule, et n'échappe jamais les guillemets internes. `sourceTerm` et `targetTerm` sont écrits bruts. Un terme contenant une virgule (ex. « Empire, The ») produit une ligne CSV malformée, et l'importeur de l'app (`line.split(',')`) la découpe dans les mauvaises colonnes. Les allers-retours export→import corrompent silencieusement les données.
```dart
final escapedNotes = notes.contains(',') ? '"$notes"' : notes;
sink.writeln('${entry.sourceTerm},${entry.targetTerm},$escapedNotes');
```
**Correctif** : utiliser un encodeur CSV correct (paquet `csv`) ou un helper qui entoure de guillemets tout champ contenant `,`, `"` ou saut de ligne et double les guillemets internes, appliqué aux trois colonnes. Refléter les mêmes règles côté import.

**L'import CSV utilise `split(',')` naïf qui parse mal les champs entre guillemets et les virgules dans les termes**
`lib/services/glossary/glossary_import_service.dart:76-85`
`importFromCsv` parse chaque ligne avec `line.split(',')`. Tout terme ou note contenant légitimement une virgule — y compris les champs entre guillemets écrits par l'exporteur de l'app — est découpé en colonnes supplémentaires, donc `sourceTerm`/`targetTerm` sont tronqués/décalés. Les guillemets ne sont pas retirés, donc une note entre guillemets s'importe avec ses guillemets littéraux. Importe silencieusement de mauvais termes de glossaire.
```dart
final parts = line.split(',');
final sourceTerm = parts[0].trim();
final targetTerm = parts[1].trim();
```
**Correctif** : remplacer `split(',')` par un vrai parseur CSV (`CsvToListConverter` ou une fonction respectant les champs entre guillemets doubles et les guillemets échappés).

**L'import TMX rejette les unités dont `xml:lang` n'est pas strictement égal à `srclang` (variantes régionales / multi-cible)**
`lib/services/translation_memory/tmx_service.dart:401-428`
`_parseTranslationUnit` décide quelle `tuv` est la source par pure égalité de chaîne `lang == defaultSourceLang` (header `srclang`, défaut 'en'). Les TMX réels utilisent souvent des codes régionaux (`srclang='en'` mais `tuv xml:lang='en-US'`/'en-GB') ; aucun ne correspond, donc `sourceText` reste null et toute l'unité est silencieusement ignorée comme « incomplète ». De plus, quand une unité a plusieurs `tuv` non-source, seule la dernière survit (écrasement dans la boucle).
```dart
if (lang == defaultSourceLang) { sourceText = text; }
else { targetText = text; } // écrasé par chaque tuv non-source suivante
if (sourceText == null || targetText == null) { return null; } // ignorée
```
**Correctif** : comparer les langues par sous-balise de base (insensible à la casse, partie avant le `-`) plutôt qu'égalité stricte, et gérer explicitement plusieurs `tuv` cibles (choisir la langue cible demandée ou émettre une entrée par cible).

**Le découpeur de script SQL miscompte `CASE...END`, fusionnant vues/triggers/seed en une seule instruction**
`lib/services/database/migration_service.dart:237-243`
`_splitSqlScript` suit l'imbrication `BEGIN...END` en comptant chaque mot-clé, mais les expressions SQL `CASE...END` se terminent aussi par `END` sans `BEGIN` correspondant. La vue `v_project_language_stats` contient plusieurs `CASE WHEN ... END` : `beginEndDepth` devient négatif (min -6) et ne revient jamais à 0, donc plus aucun point-virgule n'est traité comme terminateur. Tout le reste du fichier (vues, triggers, seed INSERTs) s'effondre en une seule « instruction » de ~14 468 caractères. Cela ne fonctionne sur installation neuve que parce que `sqflite_common_ffi` tolère les chaînes multi-instructions ; le parseur est fonctionnellement cassé et tout consommateur strict (ex. `splitSqlScriptForTesting`) reçoit de mauvais découpages, et un seul objet en échec dans le bloc fusionné fait échouer tout ce qui suit avec une localisation d'erreur inutile.
```dart
if (_isKeywordAt(script, i, 'BEGIN')) { beginEndDepth++; }
else if (_isKeywordAt(script, i, 'END')) { beginEndDepth--; }
```
**Correctif** : ne décrémenter sur `END` que lorsqu'il ferme réellement un bloc trigger, ou clamper `beginEndDepth` à 0 ; mieux, détecter le contexte `CREATE TRIGGER ... BEGIN` plutôt que de compter les `BEGIN`/`END` bruts.

### Performance

**Re-fetch des langues de projet par unité — l'import devient O(n) de requêtes redondantes**
`lib/services/projects/project_initialization_service_impl.dart:227`
Dans la boucle d'import par entrée (qui itère sur chaque unité, potentiellement des dizaines de milliers), le code appelle `_languageRepository.getByProject(projectId)` une fois pour chaque unité juste pour créer les versions. Les langues du projet ne changent pas pendant l'import : une requête DB supplémentaire par unité sur le chemin d'import le plus chaud, ralentissant matériellement l'initialisation.
```dart
totalUnitsImported++;
final languagesResult = await _languageRepository.getByProject(projectId); // dans la boucle par entrée
```
**Correctif** : récupérer les langues une seule fois avant les boucles fichier/entrée et réutiliser la liste mise en cache.

### Resource-leak

**L'abonnement à `logStream` dans `ProjectInitializationDialog` n'est jamais annulé (fuite de StreamSubscription)**
`lib/features/projects/widgets/project_initialization_dialog.dart:49-62`
`_listenToLogs()` appelle `widget.logStream.listen(...)` mais ne stocke ni n'annule jamais le `StreamSubscription` retourné. `dispose()` ne dispose que le `ScrollController`. Le stream étant un broadcast détenu par un singleton de service (non auto-disposé), l'abonnement (et la closure capturant le State) fuit pour la durée de vie de l'app à chaque ouverture du dialogue, et chaque init re-broadcast vers tous les abonnements fuités. `create_project_dialog` fait correctement `await logSubscription.cancel()`.
```dart
void _listenToLogs() { widget.logStream.listen((logMessage) { ... }); } // abonnement non retenu
```
**Correctif** : stocker `_logSub = widget.logStream.listen(...)` et appeler `_logSub?.cancel()` dans `dispose()`.

**`TextEditingController` fuité dans `showLocalPackNameDialog`**
`lib/features/mods/utils/mods_dialog_helper.dart:31-66`
Cet helper statique alloue `TextEditingController(text: defaultName)`, l'attache à un `TextField`, mais ne le dispose jamais : rien n'appelle `controller.dispose()`. Chaque ouverture du dialogue « nommer le pack local » fuit un controller et ses ressources natives.
```dart
static Future<String?> showLocalPackNameDialog(BuildContext context, String defaultName) async {
  final controller = TextEditingController(text: defaultName);
  return showDialog<String>( ... ); // jamais disposé
}
```
**Correctif** : envelopper le dialogue dans un petit `StatefulWidget` qui possède le controller et le dispose, ou `await` le résultat et appeler `controller.dispose()` dans un `finally`.

**`extractAllFiles` fuit les abonnements stdout/stderr et peut tronquer la sortie capturée**
`lib/services/rpfm/mixins/rpfm_extraction_mixin.dart:358`
Les stdout/stderr du processus sont piped dans des `StringBuffer` via `.listen(...)` mais les `StreamSubscription` retournés ne sont jamais stockés ni annulés. La méthode attend `exitCode` puis lit immédiatement `stderr.toString()`. Rien ne garantit que les flux ont été entièrement drainés à la complétion d'`exitCode`, donc le stderr utilisé pour le message d'erreur (`parseErrorMessage`) peut être incomplet/vide. Le chemin pack-add voisin fait correctement `.transform(utf8.decoder).join()` avant `exitCode`.
```dart
currentProcess!.stderr.transform(utf8.decoder).listen((data) { stderr.write(data); });
final exitCode = await currentProcess!.exitCode.timeout(...);
final error = RpfmOutputParser.parseErrorMessage(stderr.toString());
```
**Correctif** : capturer stdout/stderr en Futures via `.join()` AVANT d'attendre `exitCode`, puis les `await` après pour des buffers complets sans abonnements fuités.

### Security

**L'extraction de ZIP n'a pas de protection contre le path traversal (zip-slip)**
`lib/services/rpfm/rpfm_cli_manager.dart:374`
`_extractZip` joint chaque nom d'entrée d'archive directement sur le répertoire de sortie et l'écrit, sans vérifier que le chemin résolu reste dans `outputDir`. Une archive de release malveillante/altérée avec des entrées comme `..\..\Windows\...\evil.exe` ou des chemins absolus serait écrite hors du répertoire prévu (zip-slip classique). De plus, aucun contrôle d'intégrité (checksum/signature) sur l'asset téléchargé. La source étant les releases GitHub en HTTPS, l'exploitation requiert une compromission upstream ou un MITM, mais l'extraction est inconditionnellement vulnérable.
```dart
final filePath = path.join(outputDir, filename);
if (file.isFile) { ... await File(filePath).writeAsBytes(data); }
```
**Correctif** : avant écriture, normaliser et vérifier que la cible reste dans `outputDir` (`path.normalize` + `path.isWithin`) ; sauter/rejeter les entrées qui s'échappent. Vérifier optionnellement un checksum publié.

### State-management

**Mutation de l'état du Notifier depuis des callbacks de progression async sans garde de dispose**
`lib/features/settings/providers/maintenance_providers.dart:242-245`
`rebuildTranslationMemory` et `migrateLegacyHashes` passent des callbacks `onProgress` faisant `state = state.copyWith(...)` pendant l'appel async de longue durée, sans garde `ref.mounted`. Si le provider maintenance autoDispose est disposé en cours d'opération (utilisateur quittant les réglages), l'écriture de `state` lève un StateError. L'erreur est convertie en Err par le service, mais le bloc catch du notifier réécrit alors `state` sur le notifier disposé, ce qui relance un StateError non capturé qui s'échappe en erreur de zone non gérée. `language_settings_providers.dart` garde le même pattern avec `if (ref.mounted)`.
```dart
onProgress: (processed, total, added) {
  state = state.copyWith(progressMessage: 'Processing: ...');
},
```
**Correctif** : garder chaque mutation avec `if (!ref.mounted) return;` avant `state = ...` (idem dans `migrateLegacyHashes` et `UpdateDownloader.downloadUpdate`).

**Le callback de progression de l'import TMX appelle `setState` sans garde mounted ; le dialogue est dismissible par barrière pendant l'import**
`lib/features/translation_memory/widgets/tmx_import_dialog.dart:386-391`
`_startImport` passe un `onProgress` appelant inconditionnellement `setState`. Le dialogue est affiché sans `barrierDismissible:false`, donc l'utilisateur peut tapoter à l'extérieur pour le fermer pendant l'import. Après fermeture, le State est disposé mais `importFromTmx` continue d'appeler `onProgress`, déclenchant `setState() called after dispose()`. L'import lui-même se termine côté provider (pas de corruption de données).
```dart
onProgress: (processed, total) {
  setState(() { _processedEntries = processed; _totalEntries = total; });
},
```
**Correctif** : garder le callback avec `if (!mounted) return;` avant `setState`, et/ou passer `barrierDismissible: false`.

**`deleteEntry` et `incrementUsageCount` n'invalident pas le cache d'exact-match, renvoyant des entrées périmées/supprimées**
`lib/services/translation_memory/translation_memory_service_impl.dart:171-175, 142-145`
`addTranslation`/`addTranslationsBatch`/`updateTargetText`/`importFromTmx` appellent tous `clearCache()` après mutation, mais pas `deleteEntry` ni `incrementUsageCount`. Le cache d'exact-match (`TmCache`, singleton sans TTL) est consulté avant le repository. Après suppression d'une entrée, un `findExactMatch` ultérieur sur le même texte source renvoie le `TmMatch` en cache de la ligne supprimée, réappliquant une traduction supprimée aux unités (problème d'intégrité) ; `incrementUsageCount` laisse de même un `usageCount` périmé.
```dart
Future<Result<void, ...>> deleteEntry({required String entryId}) =>
    _crudService.deleteEntry(entryId: entryId); // pas de clearCache()
```
**Correctif** : envelopper `deleteEntry` (et idéalement `incrementUsageCount`) comme les autres mutateurs — `await clearCache()` sur succès, ou invalider la clé de cache spécifique.

### Concurrency (suite)

**`BatchTranslationCache.lookup` ignore le résultat de `synchronized()`, exécute des effets de bord deux fois**
`lib/services/translation/batch_translation_cache.dart:91-128`
`lookup()` enveloppe sa logique dans `synchronized(_lock, () {...})` mais ne retourne jamais la valeur de la closure. Les `return CacheHit/CachePending/CacheMiss` sont jetés et le contrôle tombe toujours dans le bloc « default return » (le commentaire « should not reach here » est faux : on l'atteint toujours). Le premier bloc n'est pas mort : ses effets de bord s'exécutent. Pour un hit, `cached.useCount++` s'exécute dans le premier bloc ET de nouveau dans le second, double-incrémentant `useCount` à chaque lookup. Note : cela n'inverse pas le classement LRU (mise à l'échelle uniforme x2), mais gonfle `totalUseCount` et la structure dupliquée est fragile.
```dart
synchronized(_lock, () {
  if (cached != null && ...) { cached.useCount++; return CacheHit(...); }
});
// Default return (should not reach here ...) — l'atteint toujours
final cached = _cache[sourceHash];
if (cached != null && ...) { cached.useCount++; return CacheHit(...); }
```
**Correctif** : retourner le résultat de `synchronized()` (`return synchronized(_lock, () { ... });`) et supprimer le bloc de fall-through dupliqué.

---

## Faible

### Concurrency

**`handleBulkAccept/Reject/handleValidate` ignorent les échecs individuels de mise à jour**
`lib/features/translation_editor/widgets/grid_actions_handler.dart:147-153, 294-301`
Dans `handleValidate` et `performDelete`, la branche `err` par ligne est un bloc vide avec seulement un commentaire ; rien n'est loggué et l'échec est silencieusement avalé. `successCount` ne compte que les `ok`, donc le toast est exact, mais l'utilisateur n'a aucune indication que certaines lignes ont échoué ni de trace pour diagnostic.
```dart
result.when(ok: (_) => successCount++, err: (error) { /* Log error but continue */ });
```
**Correctif** : logguer l'erreur via `loggingServiceProvider` dans la branche `err` et signaler un échec partiel quand `successCount < selectedRows.length`.

**L'annulation par lot ne stoppe pas l'opération non-traduction en cours, et le projet actif n'est pas marqué annulé**
`lib/features/projects/providers/bulk_operations_notifier.dart:226-236`
`cancel()` met `isCancelled=true` et n'appelle `runner.stop()` que pour translate/translateReviews. Pour rescan, forceValidate et generatePack, il n'y a pas d'arrêt coopératif : l'opération en cours s'achève et son résultat écrase l'entrée `inProgress` en succeeded/failed ; seuls les projets non démarrés passent en cancelled. Un utilisateur qui annule une longue génération de pack continue de générer le pack courant sans moyen d'interrompre, et la timeline montre ce projet comme succeeded.
```dart
final usesRunner = state.operationType == BulkOperationType.translate || ...translateReviews;
if (usesRunner) { await runner.stop(); }
```
**Correctif** : passer un token d'annulation à `runHeadlessValidationRescan` et `exportToPack` pour abandonner l'opération en cours, et marquer le projet actif comme annulé quand il est interrompu.

**`RpfmServiceImpl.cancel()` pendant la création de pack peut ne pas abandonner la boucle / entrer en conflit avec des opérations concurrentes**
`lib/services/rpfm/mixins/rpfm_pack_operations_mixin.dart:29`
`isCancelled` est un unique booléen partagé sur le service singleton. `createPack` le remet à false au début, et les méthodes d'extraction le remettent à false dans leurs `finally`. Si une extraction et une création de pack se chevauchent, le reset peut effacer une annulation en attente, donc `cancel()` est silencieusement ignoré. Il n'y a pas de token par opération : un cancel destiné à l'opération A peut être observé par B ou perdu. Danger latent de gestion d'état (la réalité d'une concurrence inter-features n'est pas prouvée).
```dart
isCancelled = false; // createPack et finally d'extraction
Future<void> cancel() async { _isCancelled = true; _currentProcess?.kill(); _currentProcess = null; }
```
**Correctif** : utiliser un token/identifiant d'opération par opération, ou garantir qu'une seule opération RPFM s'exécute à la fois et que `cancel()` cible l'active.

**`SettingsRepository.setValue` effectue un upsert read-then-write non atomique**
`lib/repositories/settings_repository.dart:150-205`
`setValue` interroge une ligne existante puis insère ou met à jour conditionnellement hors transaction (dans `executeQuery`, pas `executeTransaction`). Deux appels `setValue` concurrents pour une même clé nouvelle peuvent tous deux observer « non trouvé » et tenter un INSERT ; le second viole la contrainte UNIQUE avec `ConflictAlgorithm.abort` et échoue. Fenêtre étroite (premières écritures concurrentes de la même clé nouvelle).
```dart
final existingMaps = await database.query(tableName, where: 'key = ?', ...);
if (existingMaps.isNotEmpty) { await database.update(...) }
else { await database.insert(..., conflictAlgorithm: ConflictAlgorithm.abort); }
```
**Correctif** : envelopper dans `executeTransaction`, ou utiliser un seul `INSERT ... ON CONFLICT(key) DO UPDATE`.

**`BatchTranslationCache` annoncé thread-safe mais le verrou est un no-op ; `registerPending` a une race TOCTOU entre lots parallèles**
`lib/services/translation/batch_translation_cache.dart:278-279`
`synchronized<T>(...) => action();` est un simple pass-through sans exclusion mutuelle, alors que la doc affirme « Thread-safe ». Dans `LlmCacheManager.processUnitsForCache`, `lookup()` et `registerPending()` sont dans des boucles séparées avec des points `await`. Deux lots parallèles peuvent observer `CacheMiss` pour le même texte source et tous deux le traiter : `registerPending` retournant false ne retire pas le texte de `uncachedSourceTexts`, donc le lot perdant renvoie le texte au LLM de façon redondante. Conséquence : travail LLM redondant (coût/latence), traductions correctes, pas de corruption d'état.
```dart
T synchronized<T>(Object lock, T Function() action) => action(); // pas de mutex réel
```
**Correctif** : effectuer lookup et registerPending atomiquement par texte source en une passe synchrone sans `await` intermédiaire, ou faire que `registerPending` renvoie le Future en attente existant quand il perd la course. Supprimer la mention thread-safe trompeuse ou implémenter un vrai mutex async.

### Correctness

**`retry()` n'efface pas l'`errorMessage` périmé à cause de la sémantique de `copyWith`**
`lib/providers/mods/mod_update_provider.dart:344-347`
`ModUpdateQueue.retry()` appelle `info.copyWith(status: pending, errorMessage: null)` pour effacer l'erreur, mais `copyWith` implémente `errorMessage ?? this.errorMessage`, donc passer null est un no-op et l'ancien message est retenu. Même piège pour tous les champs nullables. Masqué dans l'UI car le bloc d'erreur est gardé sur `isFailed`, mais le modèle en mémoire porte une erreur périmée entre états.
```dart
_updateQueue[projectId] = info.copyWith(status: ModUpdateStatus.pending, errorMessage: null);
```
**Correctif** : utiliser un sentinel/`ValueGetter` dans `copyWith` pour distinguer « non passé » de « mis à null », ou construire un `ModUpdateInfo` frais avec `errorMessage` effacé.

**`NavigationState.copyWith` ne peut pas annuler les champs ; `clearLastProject/clearLastMod` laissent un état mémoire périmé**
`lib/config/router/navigation_state_provider.dart:18-28, 61-91`
`copyWith` utilise `lastProjectId ?? this.lastProjectId`, donc passer null ne peut effacer un champ. `setLastProjectId(null)` retire la valeur de SharedPreferences mais fait `state = state.copyWith(lastProjectId: null)`, qui conserve l'ancienne valeur non-null en mémoire. La suppression est persistée sur disque mais l'état mémoire reste incohérent jusqu'au prochain `_loadState()`. Le notifier semble actuellement non référencé ailleurs (impact latent).
```dart
if (projectId == null) { await prefs.remove(_keyLastProjectId); }
state = state.copyWith(lastProjectId: projectId); // null ignoré par copyWith
```
**Correctif** : construire l'état effacé explicitement, ou ajouter un `copyWith` à base de sentinel pour pouvoir appliquer null.

### Data-integrity

**Le lookup ligne→modèle de la DataGrid matche sur un champ texte non unique, pouvant lier les actions à la mauvaise entrée**
`lib/features/settings/widgets/llm_custom_rules_data_source.dart:43-46`
`buildRow` récupère le modèle avec `firstWhere` sur la valeur texte `ruleText` plutôt qu'un id unique. Il n'y a pas d'index unique ni de garde anti-doublon sur `rule_text`, donc deux règles de texte identique sont créables. La case « activé » de la seconde ligne dupliquée opère alors sur l'id de la première. (Le cas `IgnoredSourceText` est protégé par un index UNIQUE + garde de service ; les actions edit/delete utilisent le bon modèle par cellule — seule la case « activé » est touchée.)
```dart
final rule = rules.firstWhere((r) => r.ruleText == row.getCells()[1].value, orElse: () => rules.first);
```
**Correctif** : transporter le modèle complet dans la cellule 0 et le lire via `row.getCells()[0].value as LlmCustomRule`, en miroir de `language_settings_data_source`, éliminant le `firstWhere` par texte.

### Error-handling

**`_parseResponse` d'Anthropic utilise des casts non-null pour les tokens d'usage, contrairement aux autres providers**
`lib/services/llm/providers/anthropic_provider.dart:412-414`
Anthropic caste `usage` en Map requis et `input_tokens`/`output_tokens` en int requis. Si la réponse omet `usage` ou un champ de token (ou renvoie un non-int), cela lève, ce qui est rattrapé et re-emballé en `LlmResponseParseException` — une réponse parfaitement traduite est rapportée comme échec de parsing. Tous les autres providers (OpenAI, DeepSeek, Gemini) gardent avec `as ...? ?? 0`.
```dart
final usage = data['usage'] as Map<String, dynamic>;
final inputTokens = usage['input_tokens'] as int;
```
**Correctif** : refléter les autres providers : `as Map<String, dynamic>? ?? {}` et `as int? ?? 0`.

**Le handler `catchError` de persistance d'événement est du code mort car `_persistEvent` avale toutes les erreurs en interne**
`lib/services/shared/event_bus.dart:120-136`
`publish()` attache `.catchError` à `_persistEvent` pour logguer les échecs, mais `_persistEvent` enveloppe tout son corps dans un try/catch qui ne fait que logguer sans rethrow. Le Future retourné se complète donc toujours avec succès, et le `.catchError` ne peut jamais se déclencher. La gestion d'erreur dupliquée est trompeuse ; tout code futur s'appuyant sur ce catchError (métriques) ne déclencherait jamais. (Impact limité : `persistEvents` défaut false.)
```dart
unawaited(_persistEvent(...).catchError((e, st) { _logger.warning(...); }));
Future<void> _persistEvent(...) async { try { ... } catch (e, st) { _logger.error(...); } }
```
**Correctif** : soit retirer le try/catch interne de `_persistEvent` et laisser le `catchError` de publish gérer, soit supprimer le `catchError` redondant. Garder une source unique de vérité pour le log d'échec.

### Performance

**Statistiques par langue récupérées séquentiellement (N+1) dans le chemin chaud de chargement de la liste des projets**
`lib/features/projects/providers/projects_screen_providers.dart:560-580`
`_computeOne` boucle sur chaque langue de projet et fait `await versionRepo.getLanguageStatistics(projLang.id)` une à une, et `_loadAll` appelle `_computeOne` séquentiellement pour chaque projet. Total de roundtrips DB en O(projets × langues_par_projet), tous sérialisés. Avec beaucoup de projets/langues, cela bloque le rendu de la liste, et chaque invalidation répète le scan complet. Les lookups langues/jeux ont été délibérément batchés mais pas la requête de statistiques.
```dart
for (final projLang in langResult.unwrap()) {
  final statsResult = await versionRepo.getLanguageStatistics(projLang.id);
```
**Correctif** : ajouter une requête de statistiques par lot (`getLanguageStatisticsByIds` renvoyant une map par `projectLanguageId`), ou a minima calculer les projets en concurrence avec `Future.wait`.

**L'écriture de la clé API en stockage sécurisé et l'invalidation du provider à chaque frappe**
`lib/features/settings/widgets/llm_provider_section.dart:94`
Le `TokenTextField` de la clé API câble `onChanged` directement vers `onSaveApiKey`, qui fait une écriture `flutter_secure_storage` suivie de `ref.invalidateSelf()`. Chaque caractère tapé déclenche une écriture chiffrée + une reconstruction complète du provider (qui relit les 5 clés). Pour une clé de ~100 caractères, c'est ~100 cycles chiffrer+écrire et 100 reconstructions. Aucun debounce (contrairement au slider de rate-limit). Pas de bug de correction (l'état converge vers la dernière valeur).
```dart
onChanged: (_) => widget.onSaveApiKey(), // -> write + invalidateSelf à chaque frappe
```
**Correctif** : débouncer l'enregistrement (comme `_rateLimitDebounce`), ou enregistrer à la perte de focus / soumission.

**`buildRow` de la grille glossaire fait un `indexOf` O(n) par ligne (O(n²) par frame)**
`lib/features/glossary/widgets/glossary_datagrid.dart:283`
`buildRow` résout l'entrée backing avec `entries[_dataGridRows.indexOf(row)]`. `indexOf` est un scan linéaire, donc le rendu des lignes visibles est O(lignes_visibles × N) par reconstruction (hover/sort/scroll) — exactement le danger que la grille TM voisine a été réécrite pour éviter (pattern `rowAt` O(1) documenté). Sur de grands glossaires, cela bloque le thread principal. (La sous-revendication « mauvaise résolution par égalité de DataGridRow dupliquée » est réfutée : pas de `==` surchargé, donc identité.)
```dart
final entry = entries[_dataGridRows.indexOf(row)];
```
**Correctif** : lire l'entrée directement via la cellule actions qui la porte déjà : `row.getCells()[3].value as GlossaryEntry` (O(1)), en miroir de `_TmDataSource.rowAt`.

**Rendu de liste O(n²) via `values.toList()` répété dans l'itemBuilder**
`lib/features/mods/widgets/mod_update_dialog.dart:35-43`
L'`itemBuilder` du `ListView.separated` appelle `updateQueue.values.toList()[index]` pour chaque item, matérialisant tout l'iterable `values` (O(n)) à chaque build. `modUpdateQueue` est un provider observé, donc chaque tick de progression reconstruit et re-matérialise la map. Mineur pour de petites files mais inutile sur un chemin chaud fréquemment mis à jour.
```dart
itemCount: updateQueue.values.length,
itemBuilder: (_, index) => _UpdateItem(updateInfo: updateQueue.values.toList()[index]),
```
**Correctif** : matérialiser la liste une fois : `final items = updateQueue.values.toList();` puis utiliser `items.length` et `items[index]`.

**`FixCacheTriggersMigration` n'a pas d'`isApplied()` et re-scanne les versions manquantes à chaque démarrage**
`lib/services/database/migrations/migration_fix_cache_triggers.dart:31-103`
Cette migration ne surcharge pas `isApplied()` (le défaut de base renvoie false), donc `execute()` s'exécute à chaque démarrage. Elle drop/recrée deux triggers puis appelle `_repairMissingTranslationVersions`, qui exécute un COUNT joignant `translation_units` et `project_languages` à chaque lancement, même si le correctif est appliqué depuis longtemps. Contrairement à la migration des problèmes de validation, pas de court-circuit par marqueur. (La requête est scopée par projet et indexée, donc impact réel mais mineur.)
```dart
@override
Future<bool> execute() async { ... await _repairMissingTranslationVersions(); }
// pas de surcharge isApplied() ; la base renvoie false
```
**Correctif** : surcharger `isApplied()` pour renvoyer true une fois un marqueur satisfait, afin de sauter le scan de réparation aux démarrages suivants.

**`WorkshopMetadataService.fetchAndStore` interroge le même enregistrement jusqu'à trois fois**
`lib/services/steam/workshop_metadata_service.dart:57-89`
`fetchAndStore` appelle `existsByWorkshopId`, puis `getByWorkshopId` pour l'id, puis ENCORE `getByWorkshopId` dans le calcul de `createdAt` du constructeur `WorkshopMod`. Trois roundtrips DB pour un enregistrement, et une fenêtre TOCTOU. (Note : cette méthode n'a actuellement aucun appelant en production.)
```dart
final existsResult = await _repository.existsByWorkshopId(workshopId);
final existingResult = await _repository.getByWorkshopId(workshopId);
createdAt: ... ? (await _repository.getByWorkshopId(workshopId)).when(...) : now,
```
**Correctif** : récupérer l'enregistrement existant une seule fois avec `getByWorkshopId`, réutiliser son id et `createdAt`, et supprimer les lookups redondants (pattern déjà propre dans `fetchAndStoreBatch`).

### Resource-leak

**Le chemin de timeout de processus fuit les abonnements de flux et l'entrée de la map des processus actifs**
`lib/services/shared/process_service.dart:88-123`
Dans `run()` (et `runWithStreaming`), au timeout, `onTimeout` appelle `process.kill()` et lève `TimeoutException`. Le throw saute les `await stdoutSub.cancel()`, `await stderrSub.cancel()` et `_activeProcesses.remove(process.pid)` suivants, sautant au catch qui renvoie Err. La fuite durable est l'entrée `_activeProcesses` jamais retirée (Process gardé vivant indéfiniment). (Note : aucun appelant en production trouvé actuellement.)
```dart
exitCode = await process.exitCode.timeout(config.timeout!, onTimeout: () {
  process.kill(); throw TimeoutException(...);
});
await stdoutSub.cancel(); _activeProcesses.remove(process.pid); // sautés au timeout
```
**Correctif** : envelopper le corps dans try/finally qui annule les abonnements et retire le pid quel que soit le timeout/erreur, ou capturer le pid avant l'await et nettoyer dans le catch.

### Security

**Zip-slip path traversal à l'extraction de steamcmd.zip**
`lib/services/steam/steamcmd_manager.dart:258-274`
`_extractZip` joint chaque nom d'entrée d'archive sur `outputDir` sans valider que le chemin résolu reste à l'intérieur. Une archive forgée avec une entrée `..\..\..\Windows\System32\evil.exe` serait écrite hors du répertoire prévu. L'archive est récupérée en HTTPS depuis le CDN Valve (source fixe et de confiance, ce qui limite l'exploitabilité), mais la routine d'extraction est intrinsèquement non sûre ; une compromission CDN/MITM/DNS permettrait une écriture de fichier arbitraire.
```dart
final filePath = path.join(outputDir, filename);
await File(filePath).create(recursive: true);
await File(filePath).writeAsBytes(data);
```
**Correctif** : normaliser le chemin joint (`path.normalize`) et vérifier `path.isWithin(outputDir, normalized)` avant création/écriture ; sauter ou rejeter les entrées qui s'échappent.

### State-management

**Les helpers d'invalidation/préchargement de `TmCache` utilisent un format de clé incompatible avec le seul écrivain (`findExactMatch`)**
`lib/services/translation_memory/tm_cache.dart:110-123, 168-179, 188-226`
`findExactMatch` écrit/lit les clés sous la forme `'$sourceHash:$normalizedLangCode'` (deux-points, hash en premier). Mais `generateExactMatchKey`, `preloadEntries` et `invalidateLanguagePair` construisent `'<srcLang>_<tgtLang>_<hash>'` (underscore, langues en premier). Ces espaces de clés sont mutuellement inaccessibles : `invalidateLanguagePair` ne matchera jamais les entrées de `findExactMatch`. Code latent/mort aujourd'hui (ces helpers n'ont aucun appelant), mais échouera silencieusement à invalider dès qu'un appelant les câble.
```dart
final cacheKey = '$sourceHash:$normalizedLangCode'; // écrivain
final languagePairPrefix = '${sourceLanguageCode}_${targetLanguageCode}_'; // invalidateur
```
**Correctif** : unifier sur une fonction unique de génération de clé. Faire que `findExactMatch` appelle `generateExactMatchKey` (en alignant ordre/séparateur) afin que les helpers opèrent sur le même espace de clés.

### Concurrency (suite)

**`autoDispose ModUpdateQueue` écrit l'état dans des callbacks async après une possible disposition**
`lib/providers/mods/mod_update_provider.dart:199-262`
`ModUpdateQueue` est un notifier `@riverpod` (autoDispose). `_updateProject` attend `steamService.downloadMod()` et `versionRepo.insert()` (longs), puis dans les callbacks `when` assigne `state = Map.from(_updateQueue)`. Le seul watcher le maintenant vivant est `ModUpdateDialog`, et le téléchargement est lancé en fire-and-forget. Si le dialogue est fermé (bouton « Hide ») en cours de téléchargement, ces écritures post-await s'exécutent sur un notifier disposé et lèvent un StateError, qui re-déclenche un second throw non capturé via le catch. `onDispose` n'annule que l'abonnement. (Pas de corruption DB : l'insert se termine avant l'écriture qui lève.)
```dart
ref.onDispose(() { _progressSubscription?.cancel(); });
_updateStatusWithVersion(projectId, ModUpdateStatus.completed, version); // state = ... après awaits
```
**Correctif** : garder chaque mutation post-await avec un check disposed/`ref.mounted` et retourner tôt si disposé ; ne pas ré-entrer dans `_updateStatusWithError` depuis le catch quand la cause est la disposition.

---

## Thèmes transverses & recommandations

Quatre patterns systémiques expliquent la majorité des constats et offrent les correctifs à plus fort levier :

**1. Écritures multi-tables non transactionnelles (le thème dominant en intégrité des données).**
On le retrouve partout : ajout de langue, création de projet, création de traduction de jeu, `addNewUnits`, suppression de projet et de langue, `SettingsRepository.setValue`. À chaque fois, plusieurs écritures DB liées s'exécutent sans transaction englobante, laissant des lignes orphelines, des projets/langues à moitié créés ou des index FTS/cache désynchronisés en cas d'échec partiel. **Recommandation à fort levier** : introduire (ou systématiser) un helper transactionnel et l'appliquer à toutes les séquences « insérer parent + enfants » et « supprimer parent + enfants ». Les suppressions de projet/langue (Élevé) sont prioritaires car elles désactivent en plus des triggers *globaux* sans sérialiser les écrivains concurrents, ce qui peut corrompre des données *d'autres* projets.

**2. Mutations d'état / `setState` après dispose dans des callbacks async non gardés.**
Auto-détection de jeu, import TMX, providers de maintenance, `ModUpdateQueue`. Le pattern est identique : un callback `onProgress`/`finally` capture le State/Notifier et écrit `state`/`setState` après un `await`, sans garde `mounted`/`ref.mounted`. Le projet possède déjà le bon pattern (`WorkshopSection`, `language_settings_providers`, `create_project_dialog`), ce qui rend ces divergences faciles à corriger. **Recommandation** : règle de revue systématique « toute écriture d'état après `await` doit être précédée d'une garde mounted », et envisager un lint custom.

**3. Lecture de sortie de processus / fuites d'abonnements de flux.**
`extractAllFiles`, la publication unitaire steamcmd, `ProjectInitializationDialog.logStream`, `process_service` au timeout. Deux variantes : (a) lire `stdout/stderr` avant le drainage complet des flux après `exitCode` (sortie tronquée → erreurs manquées), et (b) ne jamais stocker/annuler les `StreamSubscription`. Le bon pattern (`.join()` avant `exitCode` ; stocker et annuler l'abonnement) existe déjà dans les chemins voisins. **Recommandation** : aligner tous les chemins de gestion de processus sur le pattern par lot/pack-add déjà correct.

**4. Encodage de chemin et parsing par substitution/`split` naïfs.**
L'encodage `__` ↔ `/` des chemins `.loc` (corruption silencieuse + écrasement), le CSV `split(',')` (export et import), le matching TMX par égalité stricte, et le découpeur SQL `CASE...END`. Tous partagent la même cause : un parsing/encodage maison fragile au lieu d'un format/encodeur robuste. **Recommandation** : remplacer ces routines maison par des bibliothèques éprouvées (paquet `csv`, métadonnée de chemin explicite plutôt qu'encodage par substitution, comparaison de langue par sous-balise) — ce sont des sources de corruption *silencieuse*, donc les plus insidieuses.

**Hors de ces thèmes**, deux bugs fonctionnels isolés méritent un correctif immédiat car ils cassent des fonctionnalités entières de façon déterministe et triviale à corriger : la recherche regex (colonne `unit_id`) et le crash d'annulation du dialogue TM (`pop()` au lieu de `pop(false)`). Le hardcodage de l'AppID Workshop est également un correctif simple à fort impact (résoudre via `selectedGameProvider`), tout comme l'application effective des résolutions de conflits de compilation, sans laquelle un workflow entier est trompeusement cosmétique.

Enfin, plusieurs constats Faible concernent du **code mort ou non câblé** (export full-DB, `TmCache` helpers, `fetchAndStore`, `process_service`, `NavigationState`) : sans impact aujourd'hui, mais ce sont des pièges armés qui se déclencheront dès qu'un appelant sera ajouté. Ils valent un correctif opportuniste ou, a minima, un commentaire d'avertissement.