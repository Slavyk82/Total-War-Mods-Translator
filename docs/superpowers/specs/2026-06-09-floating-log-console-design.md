# Design — Fenêtre de logs flottante (Floating Log Console)

**Date:** 2026-06-09
**Statut:** Validé (en attente de plan d'implémentation)

## 1. Objectif

Permettre à l'utilisateur de consulter l'intégralité des logs de la **session
courante** dans une fenêtre interne **déplaçable**, **redimensionnable** et
**non bloquante** : on peut la glisser sur le côté et continuer à utiliser
l'application normalement, les logs se mettant à jour en **live**. La fenêtre
est ouverte/fermée depuis une tuile « Logs » placée sous « Settings » dans la
barre latérale.

## 2. Contraintes & décisions

- **Source de données :** uniquement le tampon mémoire de `ILoggingService`
  (= exactement la session courante depuis le lancement). Les fichiers `.log`
  sur disque ne sont PAS lus pour l'affichage (ils peuvent mélanger plusieurs
  sessions d'un même jour) ; ils restent accessibles via le bouton « Ouvrir le
  dossier ».
- **Capacité tampon :** `maxRecentLogs` passe de 500 à **5000** pour couvrir une
  session entière, y compris les traductions par lot (logging-heavy).
- **Non bloquant :** la fenêtre vit dans l'arbre Flutter via le `builder` de
  `MaterialApp.router` et reste **sous** les vrais modaux (`showDialog`).
- **Pas de persistance** de la position/taille : réinitialisées à chaque
  ouverture.
- **Approche retenue : A** — widget piloté par Riverpod monté dans le `builder`
  (rejet de l'`OverlayEntry` impératif et de la 2ᵉ fenêtre OS `window_manager`).

## 3. Contrôles de la fenêtre

- Filtre par niveau (DEBUG / INFO / WARN / ERROR), tous actifs par défaut.
- Recherche texte (filtre les lignes contenant le mot-clé).
- Copier tout (presse-papiers) / Vider l'affichage courant.
- Ouvrir le dossier des logs (`AppData\Local\TWMT\logs`) dans l'explorateur.
- Déplaçable (drag sur l'en-tête), redimensionnable (poignée coin bas-droit),
  bouton fermer (X), bouton réduire (minimize → barre compacte).

## 4. Composants

### a) État global — `lib/providers/log_window_provider.dart`
- `enum LogWindowVisibility { closed, open, minimized }`
- `LogWindowController extends Notifier<LogWindowVisibility>` exposant
  `open()`, `close()`, `toggleOpen()`, `minimize()`, `restore()`.
- **Seul** état partagé. Position, taille, filtres et recherche restent locaux
  au widget (pas de persistance).

### b) Widget — `lib/widgets/logs/log_console_window.dart`
- `ConsumerStatefulWidget`, rendu seulement si `visibility != closed`.
- État local : `Offset _position`, `Size _size`, `Set<String> _activeLevels`
  (tous actifs par défaut), `String _search`, `List<LogEntry> _entries`,
  `ScrollController`, `bool _stickToBottom`.
- `initState` : seed depuis `logger.recentLogs`, puis abonnement à
  `logger.logStream` pour l'ajout live. `dispose` annule l'abonnement et le
  `ScrollController`.
- Positionné dans le `Stack` via `Positioned(left: _position.dx, top: _position.dy)`.
- **En-tête** (zone de drag via `GestureDetector.onPanUpdate` → maj `_position`,
  clampé à l'écran) : titre + icône console, bouton réduire, bouton fermer (X).
- **Barre d'outils** : chips de filtre par niveau (toggle), champ de recherche,
  bouton Copier (`Clipboard.setData`), bouton Vider (vide `_entries` local),
  bouton « Ouvrir le dossier ».
- **Corps** : `ListView.builder` des entrées filtrées (niveau + recherche),
  style monospace repris de `ScanTerminalWidget`, couleurs via
  `LogEntry.levelColor`, auto-scroll si `_stickToBottom` (désactivé dès que
  l'utilisateur remonte manuellement, réactivé en bas de liste).
- **Poignée de redimensionnement** : coin bas-droit (`GestureDetector.onPanUpdate`
  → maj `_size`, bornée par des tailles min).
- **État réduit** (`minimized`) : petite barre compacte (titre + restaurer +
  fermer) ancrée en bas, au lieu de la fenêtre complète.

### c) Montage — `lib/main.dart`
Le `builder` de `MaterialApp.router` enveloppe l'enfant dans un `Stack` :
`[ _AppStartupTasks(child), const LogConsoleOverlay() ]`. `LogConsoleOverlay`
watch le provider et rend `LogConsoleWindow` quand `visibility != closed`.

### d) Bouton sidebar — `lib/widgets/navigation/navigation_sidebar.dart`
Nouvelle tuile `_LogConsoleButton` rendue juste après la boucle des groupes de
nav (visuellement sous « Settings »), dans la `ListView`. Style calqué sur
`_NavItemTile` (icône `FluentIcons.window_console_20_*`, label « Logs »).
`watch(logWindowProvider)` pour surligner quand ouverte ; tap → `toggleOpen()`.

### e) Service — `logging_service.dart` / `i_logging_service.dart`
- `maxRecentLogs` : 500 → **5000**.
- Ajout de `String? get logFilePath` à l'interface `ILoggingService` (déjà
  présent sur l'impl concrète). L'action « Ouvrir le dossier » ouvre
  `File(logFilePath).parent` via le pattern `Process.start('explorer', …)`
  existant (cf. `pack_compilation_editor_screen.dart`).

## 5. Flux de données

`logger.recentLogs` (seed) → `_entries`. Puis `logStream` → append à `_entries`
(+ trim à 5000 côté widget pour borner la RAM) → rebuild → filtrage (niveau +
recherche) → rendu. Le tampon mémoire est la **seule** source = exactement la
session courante.

## 6. Gestion des erreurs

- Abonnement au stream avec `onError` qui ne casse pas l'UI.
- « Ouvrir le dossier » : si `logFilePath == null` (logging non initialisé) →
  bouton désactivé ; échec `Process.start` → toast d'erreur via le service de
  toasts existant.
- Drag/resize clampés aux limites de l'écran pour ne jamais perdre la fenêtre
  hors-cadre.

## 7. i18n

Nouvelles clés sous `t.widgets.logConsole` (titre, labels des boutons,
placeholder recherche, libellés de niveaux) + `items.logs` pour la tuile
sidebar. Ajout dans tous les fichiers de traduction slang existants.

## 8. Tests

- `log_window_provider_test.dart` : transitions open/close/minimize/toggle.
- `log_console_window_test.dart` (widget) : seed depuis un `ILoggingService`
  mock ; arrivée d'un log via stream → ligne affichée ; filtre par niveau
  masque/affiche ; recherche filtre ; bouton Vider vide la vue.
- `navigation_sidebar_test.dart` : présence de la tuile « Logs » sous Settings +
  tap appelle le toggle.

## 9. Hors périmètre (YAGNI)

- Pas de persistance position/taille.
- Pas de lecture des fichiers `.log` historiques dans l'UI (bouton « Ouvrir le
  dossier » suffit).
- Pas de 2ᵉ fenêtre OS native.
- Pas d'export/partage de logs depuis la fenêtre (le dossier est accessible).
