# TWMT — UI redesign — design spec

**Date:** 2026-04-14
**Status:** design · pending implementation plan
**Mockups:** `.superpowers/brainstorm/2035-1776190006/content/*.html` (visual companion)

---

## 1. Intent

Refonte globale de l'UI pour établir un fil conducteur UX clair. L'app a grossi au fil des versions sans direction d'ensemble ; un nouvel arrivant se perd, un power-user compose avec l'accumulation.

**Objectif principal** — efficacité power-user (densité, raccourcis, peu de clics) **tout en** racontant le workflow implicitement à travers l'organisation, sans mode débutant séparé.

---

## 2. Audience & priorités

| Audience | Besoin | Comment on y répond |
|---|---|---|
| Power-user | Traiter des milliers d'unités vite, lot par lot, avec contexte | Table dense + inspector + statusbar + raccourcis clavier visibles |
| Nouvel arrivant | Savoir quoi faire *maintenant* | Home dashboard actionnable + bande workflow 4 étapes + greeting personnalisé + next-action contextuelle sur chaque projet |
| Les deux | Lire confortablement des heures | Thèmes chauds ou froids au choix, typographie soignée, contraste mesuré |

**Non-objectif** — mode guidé séparé, onboarding en overlay/tour produit, assistant.

---

## 3. Information architecture

Sidebar groupée en **5 sections** nommées pour correspondre au workflow mental :

```
├── Sources          ← d'où vient le contenu
│   ├── Mods         (Steam Workshop detection)
│   └── Fichiers du jeu  (base game loc)
│
├── Travaux          ← là où on passe le temps
│   ├── Accueil      (dashboard)
│   └── Projets      (liste + drill-down + éditeur)
│
├── Ressources       ← assets transverses
│   ├── Glossaire
│   └── Mémoire      (TM)
│
├── Publication      ← sortie produit
│   ├── Compilation  (pack generation)
│   └── Steam Workshop
│
└── Système
    ├── Réglages
    └── Aide
```

**Game switcher** : reste dans la sidebar (sous le brand, au-dessus de Sources). Compact (34×22px jaquette + nom). Distinct de la navigation d'écrans.

**Règle IA** : un même écran ne réapparaît pas dans deux groupes. Les écrans actuels *Game Translation* et *Game Files* fusionnent dans `Sources / Fichiers du jeu` (le côté "Game Translation" devient un mode au sein de cet écran, pas un écran séparé).

---

## 4. Système de thèmes

Deux thèmes couplés (palette + typographie indissociables) au choix dans **Réglages › Apparence**.

### 4.1 — Atelier (défaut)

| Token | Valeur |
|---|---|
| `--bg` | `#1a1816` greige chaud |
| `--panel` | `#15130f` |
| `--panel-2` | `#1f1b17` |
| `--border` | `#2a2420` |
| `--text` | `#f5ecd9` |
| `--text-mid` | `#b8ad9c` |
| `--text-dim` | `#7a6f60` |
| `--accent` | `#d89a4a` ambre chaud |
| `--accent-fg` | `#1a1612` sur accent |
| `--ok` | `#9ecc8a` vert tilleul |
| `--warn` | `#d89a4a` (= accent) |
| `--err` | `#c47a6e` terracotta |
| `--llm` | `#b09edc` glycine |
| `--font-body` | Instrument Sans |
| `--font-display` | Instrument Serif *italic* |
| `--font-mono` | JetBrains Mono |

Ambiance : cabinet d'érudit, lisible en longue session, caractérielle.

### 4.2 — Forge

| Token | Valeur |
|---|---|
| `--bg` | `#0a0a0b` |
| `--panel` | `#0d0d10` |
| `--panel-2` | `#121215` |
| `--border` | `#1d1d22` |
| `--text` | `#e8e8ea` |
| `--accent` | `#00d4ff` cyan |
| `--accent-fg` | `#000` |
| `--ok` | `#00d4ff` (= accent) |
| `--warn` | `#ffaa00` |
| `--err` | `#ff3366` |
| `--llm` | `#c28eff` |
| `--font-body` | IBM Plex Sans |
| `--font-display` | IBM Plex Sans **500** (pas de serif italique) |
| `--font-mono` | IBM Plex Mono |

Ambiance : Linear/Raycast, précision technique, pas de décoration typographique.

### 4.3 — Règles de theming

- **Pas de mix** entre palette et typographie. Un utilisateur choisit un des deux thèmes, pas des fragments.
- **Toutes les couleurs passent par tokens** ; aucune valeur `#xxxxxx` en dur dans les composants.
- **Tous les textes décoratifs** (group labels, section titles, page titles) passent par `--font-display` avec `--font-display-style: italic|normal` selon le thème. Forge neutralise l'italique en caps-mono (`text-transform: uppercase; letter-spacing: 1.5px`).
- **Tout code/clé/chemin/métrique** passe par `--font-mono`.
- **Tous les chiffres dans les tables et stats** utilisent `font-variant-numeric: tabular-nums`.

---

## 5. Design tokens globaux

| Token | Valeur | Usage |
|---|---|---|
| `--r-xs` | 3px | chips, tiny elements |
| `--r-sm` | 4px | inputs inline, kbd hints |
| `--r-md` | 8px | boutons, selects, inputs principaux |
| `--r-lg` | 10px | cards, panels |
| `--r-pill` | 20px | filter pills (exception locale — pills exclusivement) |
| `--r-round` | 50% | flèches, puces, avatars |

**Règle radius** : `r=8px` est le standard mondial (validé sur EN/JA/KO/ZH). Pas de sélecteur utilisateur — choix de design figé. Exception unique : les *filter pills* en `r=20px` (composant assumé comme "pilule", labels toujours courts, pas utilisé pour des actions critiques).

### Espacements

Échelle 4px : `4 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 22 · 24 · 28`. Éviter 6, 11, 13, 15 — garder une grille cohérente.

### Scrollbars (custom, themées)

- Largeur : **20px** (identique vertical & horizontal)
- Track : transparent
- Thumb : `--border` avec 5px de padding interne (`border: 5px solid transparent; background-clip: padding-box;`)
- Thumb hover : `--accent`
- Radius thumb : 10px
- **Pas de flèches** (`::-webkit-scrollbar-button { display: none }`)
- Firefox : `scrollbar-width: thin; scrollbar-color: var(--border) transparent;`
- **Flutter** : `ScrollbarTheme` custom, jamais la scrollbar OS.

---

## 6. Grammaire de composants

### 6.1 Buttons

- `<Button variant="primary">` : bg=accent, fg=accent-fg, font-weight 500
- `<Button variant="secondary">` : bg=panel-2, border, fg=text
- `<Button variant="ghost">` : bg=transparent, border, fg=text
- `<Button variant="danger">` : border+fg en err
- Padding : `7-8px × 14-16px`
- `min-height: 32px`, `white-space: nowrap`, `flex-shrink: 0`
- `.kbd` optionnel à la fin (font-mono 10px, encadré)

### 6.2 Filter pills

- `r-pill` (20px), font-size 12px, padding `5px 12px`
- État off : bg=panel-2, fg=text-mid
- État on : bg=accent-bg, border=accent, fg=accent
- Compteur inline (`.ct`) en font-mono, text-faint

### 6.3 Status pills (dans listes)

- `r=8px` (pas 20px — ce sont des badges d'état, pas des filtres)
- Couleur par état : `ok` `warn` `llm` `man` (cf. grille TM)
- Font-mono 10px, letter-spacing, uppercase
- Toujours dans une colonne à largeur fixe (voir §7.1)

### 6.4 Inputs / selects

- `r=8px`, bg=panel-2, border
- Focus : border=accent (pas de shadow, pas de glow)
- Texte user en font-body, placeholder en font-mono text-dim
- Suffixe kbd hint optionnel à droite

### 6.5 Cards

- `r=10px`, bg=panel-2, border
- Hover : border=text-dim, `transform: translateY(-1px)`
- Selected : border=accent, bg=accent-bg
- Highlight (actionnable) : border=accent, bg=accent-bg, puce pulsée top-right (`box-shadow: 0 0 0 4px var(--accent-bg-2)`)

### 6.6 Tables (éditeur)

- Header 30-34px, font-mono 10-11px, caps, letter-spacing
- Row 38-44px selon densité
- Grid-template-columns **explicite à largeurs fixes** pour toutes les colonnes sauf au max 2 qui prennent `1fr`
- Row selected : bg=row-sel, bordure gauche 2px accent

### 6.7 Inspector (panneau droit éditeur)

- Largeur 280-340px
- Font-display italique pour les section-titles
- Texte source/cible dans des blocs `--panel-2` border, `r=4-6px`, padding généreux, line-height 1.5-1.6
- Cible en édition : bg=accent-bg, border=accent
- Suggestions empilées, chaque item cliquable avec pct/source en font-mono à droite

### 6.8 Toolbar d'écran

- Hauteur 48-64px selon écran
- `display: flex; gap: 12px; align-items: center`
- Sections séparées par `<div class="sep">` (1px × 22-24px bg=border)
- Crumb à gauche, actions primaires à droite via `margin-left: auto`
- Search/CmdK en cmdk (font-mono, `--panel-2`) vers l'extrême droite

### 6.9 Statusbar (bas de l'éditeur)

- Hauteur 26-28px
- Font-mono 10-11px, text-dim
- Métriques séparées par `·` (text-faint)
- Accent sur la métrique primaire (progression)

---

## 7. Archétypes d'écran

Les écrans se résument à 5 archétypes. Toute nouvelle feature doit se ranger dans un d'entre eux.

### 7.1 Liste filtrable

**Pour** : Mods · Projects · Glossary · Translation Memory

Structure :
1. Toolbar écran (crumb, compteur, actions globales)
2. **Toolbar filtre (double-ligne)** : ligne 1 = search + tri + colonnes + vue · ligne 2 = filter pills groupés par catégorie avec labels caps-mono (`État` / `Langue cible` / `Mise à jour`)
3. Liste en cards sur grid **à colonnes fixes** (ex: `56px 1fr 140px 200px 180px 150px`)
4. Chaque ligne a une **action contextuelle à droite** (full-width dans sa colonne, centrée)

**Règle critique** : pas de `auto auto` en grid-template-columns — cela casse l'alignement vertical des colonnes de droite entre les lignes.

### 7.2 Détail / overview

**Pour** : Project detail · Glossary entry detail · Mod detail

Structure :
1. Toolbar écran avec crumb du parent + nom de l'item en Instrument Serif
2. **Meta-bandeau** full-width : cover (110×68px) + titre + sub-meta font-mono + description + actions
3. Body en **2 colonnes 2fr / 1fr** : contenu principal gauche (liste de sous-entités : langues, traductions), stats agrégées droite

### 7.3 Éditeur dense

**Pour** : Translation Editor (unique instance)

Structure :
1. Toolbar 48-56px : crumb + select modèle + Skip TM toggle + sep + actions unités (Rules, Selection, Validate, Translate all primary) + sep + actions sortie (Generate pack, Workshop, Export TMX) + spacer + CmdK search
2. Body en **3 colonnes** : filters 200px / grid 1fr / inspector 280-340px
3. Statusbar 26-28px : metrics live (units, translated%, review, tokens, cost, TM reuse, encoding)

### 7.4 Dashboard

**Pour** : Home

Structure :
1. Main-header : greeting personnalisé (Instrument Serif, *"Bonsoir, Slavyk"*) + phrase d'état actionnable + Command + New project primary
2. **Workflow ribbon** — 4 cartes détachées (Détecter → Traduire → Compiler → Publier) avec flèches entre chaque, états done/current/next visuellement très distincts (gradient + halo accent pour current, opacity 0.65 pour next, ok pour done)
3. **Action grid** — 4 cartes actionnables chiffrées (pas de vanity metrics) : À revoir / Prêts à compiler / Mods mis à jour / Prêt à publier. Les cartes avec action urgente ont un dot pulsé top-right.
4. **Recent + Activity** — 2 colonnes 2fr/1fr : liste des projets récents avec next-action à droite (même pattern que §7.1) + feed d'activité horodaté à droite.

**Adaptation vide (nouveau user)** — pas de mode séparé. Les compteurs à 0, le workflow ribbon highlight l'étape 1, la carte actionnable centrale devient un gros CTA "Commence par détecter vos mods", *Recent* se transforme en guide 3 étapes. **C'est le contenu qui s'adapte à l'état, pas l'UI.**

### 7.5 Wizard / form

**Pour** : Pack Compilation · Steam Workshop Publish · Game Translation setup · New Project

Structure :
1. Toolbar : crumb + actions secondaires (preset, historique)
2. Body en **2 colonnes 380px / 1fr** :
    - Gauche : **formulaire sticky** (`position: sticky; top: 16px`) avec tous les champs, une *summary box* en tirets dashed qui affiche en temps réel les conséquences du formulaire (ex: nom final du pack généré, estimation de taille/durée), actions primaires en bas (Save secondary + Generate primary full-width)
    - Droite : zone dynamique (liste des éléments à sélectionner avec checkboxes + compteur + filtre, sorties post-génération en bas — BBCode, logs, confirmations)

**Règle** : la summary box n'est pas un résumé statique, c'est un *live preview* de ce que la soumission du formulaire va produire.

---

## 8. Règles globales de layout

1. **Grilles à colonnes fixes** dans toutes les listes multi-colonnes (jamais `auto auto`).
2. **Sticky forms** quand la zone de sélection est longue/scrollable.
3. **Chiffres en tabular-nums** partout — pas de chiffres qui dansent.
4. **Ellipse + title** pour les clés/noms longs (`text-overflow: ellipsis; white-space: nowrap;` + tooltip natif).
5. **Hover subtil partout** : border → text-dim, pas de changement de background par défaut (sauf cards).
6. **Focus visible** : border accent (jamais outline jaune navigateur).
7. **Min-width 1280px** pour l'app (Desktop Windows) — pas de responsive mobile, mais scaling propre jusqu'à 4K.
8. **Raccourcis clavier affichés** dans les boutons importants (`⌘K`, `⌘T`, `⌘⇧T`, etc.) — ils enseignent par répétition visuelle.

---

## 9. Cas Home — remplacement des vanity metrics

L'écran d'accueil actuel affiche *Total Projects · Translation Units · Translated · Words Translated*. Ces chiffres racontent l'histoire du compte, pas l'action à venir. **Ils disparaissent**, remplacés par :

| Ancien (vanity) | Nouveau (actionnable) |
|---|---|
| Total Projects | *À revoir* (projets avec unités needs-review) |
| Translation Units | *Prêts à compiler* (projets 100%) |
| Translated | *Mods mis à jour* (Workshop updates) |
| Words Translated | *Prêt à publier* (packs compilés en attente) |

Chaque carte est cliquable et mène à l'écran filtré correspondant. Les cartes avec un compte > 0 et une action urgente portent le highlight accent + dot pulsé.

---

## 10. Notes d'implémentation Flutter

- **ThemeExtension** : créer `TwmtThemeTokens extends ThemeExtension<TwmtThemeTokens>` qui porte tous les tokens (pas seulement les 8 du `ColorScheme` Material). Deux instances : `atelier` et `forge`.
- **Google Fonts** : les 4 familles (Instrument Sans, Instrument Serif, JetBrains Mono, IBM Plex Sans, IBM Plex Mono) sont chargeables via `google_fonts` package. Prévoir fallback système.
- **Scrollbar** : `ScrollbarTheme` dans le ThemeData : thumbColor = token border, hover = accent, radius 10, thickness 20, thumbVisibility à `true` dans les zones scrollables longues (liste de projets, éditeur).
- **Routing** : GoRouter conservé, mais la ShellRoute principale intègre les 5 groupes de nav (pas juste une liste à plat) via un widget `NavigationSidebar` stateful qui lit la route active.
- **Home** : un nouveau `HomeScreen` qui compose `WorkflowRibbon`, `ActionGrid`, `RecentList`, `ActivityFeed`. Chaque widget lit un provider Riverpod dédié pour son état.
- **Écrans existants à ré-architecturer** : `HomeScreen` (refait), `ProjectsScreen` (nouveau filter toolbar), `ProjectDetailScreen` (meta + langs + stats), `TranslationEditorScreen` (ajouter inspector panel + statusbar + dense grid), `PackCompilationScreen` (sticky form + selection list + BBCode).
- **Écrans peu impactés** : Glossary, TM, Settings, Help — adoptent les tokens de thème mais layout reste proche.

---

## 11. Scope

**Dans le scope de cette refonte :**
- IA de la sidebar (5 groupes)
- Système de thèmes (Atelier + Forge) avec sélecteur dans Réglages
- Nouveau Home (dashboard hybride)
- Nouvelle Toolbar + filter toolbar des listes
- Nouvelle grille de l'éditeur avec inspector + statusbar
- Nouveau Pack Compilation (sticky form)
- Scrollbars themées globales
- Design tokens (tailles, radius, espacements, typographie)

**Hors scope de cette refonte :**
- Refonte fonctionnelle : aucune feature ajoutée ou retirée, juste réorganisée
- Localization — on reste EN-only côté UI pour cette refonte, les 2 thèmes gèrent déjà la lisibilité CJK (r=8px validé)
- Light theme — les 2 thèmes sont dark. Un thème clair pourrait s'ajouter plus tard en respectant la même grammaire de tokens.
- Thème "parchemin Total War" — clin d'œil mentionné en brainstorm, pas prioritaire.

---

## 12. Open questions / à clarifier au plan d'implémentation

1. **Game switcher** : faut-il un écran/modal de sélection de jeu (avec jaquettes, stats par jeu) ou juste un dropdown compact dans la sidebar ?
2. **Données workflow** : d'où vient l'état *"2 projets à revoir"* — un provider dédié qui agrège, ou du cache des écrans existants ?
3. **Activité récente** : on la dérive de quoi — log événements existant ? DB de dates de modif ? À définir côté domain/repository.
4. **Migration des préférences** : les users existants ont quel thème au premier lancement post-refonte ? Proposition : Atelier par défaut, on garde leur theme mode (light/dark) system mais dark-only côté palette actuellement.
5. **Tests visuels** : golden tests par screen × thème (2 × N écrans) — volume et maintenance OK ?

---

## Mockups de référence

Dans `.superpowers/brainstorm/2035-1776190006/content/` :

- `home-v2.html` — dashboard hybride, les 2 thèmes
- `editor-mix.html` — éditeur dense (grammaire éditeur)
- `archetypes-extra.html` — Projects list + Project detail + Pack compilation
- `buttons-radius.html` — règles de radius, 2 thèmes
- `cjk-buttons.html` — validation CJK du r=8px
- `themes-demo.html` — système de tokens en vivant

Ces fichiers sont autonomes et peuvent servir de référence pixel-pour-pixel lors de l'implémentation.
