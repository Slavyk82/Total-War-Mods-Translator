import '../database/database_service.dart';
import '../shared/logging_service.dart';

/// Service to fix missing hyphens in French translations.
///
/// French language uses hyphens extensively in compound words, reflexive
/// pronouns, dialogue inversions, and common expressions. LLM translations
/// sometimes omit these hyphens.
///
/// This service runs at application startup to restore missing hyphens
/// in existing French translations.
class FrenchHyphenFixer {
  FrenchHyphenFixer._();

  /// Common French hyphen patterns organized by category.
  ///
  /// Each pattern is a tuple of (incorrect form without hyphen, correct form with hyphen).
  /// Patterns are case-insensitive for matching.
  static const List<(String, String)> hyphenPatterns = [
    // =========================================================================
    // REFLEXIVE PRONOUNS WITH -MÊME
    // =========================================================================
    ('lui même', 'lui-même'),
    ('elle même', 'elle-même'),
    ('eux mêmes', 'eux-mêmes'),
    ('elles mêmes', 'elles-mêmes'),
    ('moi même', 'moi-même'),
    ('toi même', 'toi-même'),
    ('nous mêmes', 'nous-mêmes'),
    ('vous même', 'vous-même'),
    ('vous mêmes', 'vous-mêmes'),
    ('soi même', 'soi-même'),

    // =========================================================================
    // COMMON ADVERBS AND EXPRESSIONS
    // =========================================================================
    ('peut être', 'peut-être'),
    ('c\'est à dire', 'c\'est-à-dire'),
    ('vis à vis', 'vis-à-vis'),
    ('au dessus', 'au-dessus'),
    ('au dessous', 'au-dessous'),
    ('au delà', 'au-delà'),
    ('au dedans', 'au-dedans'),
    ('au dehors', 'au-dehors'),
    ('au devant', 'au-devant'),
    ('en dessous', 'en-dessous'),
    ('en dehors', 'en-dehors'),
    ('en dedans', 'en-dedans'),
    ('en deçà', 'en-deçà'),
    ('là bas', 'là-bas'),
    ('là haut', 'là-haut'),
    ('là dessus', 'là-dessus'),
    ('là dessous', 'là-dessous'),
    ('là dedans', 'là-dedans'),
    ('ci dessus', 'ci-dessus'),
    ('ci dessous', 'ci-dessous'),
    ('ci contre', 'ci-contre'),
    ('ci joint', 'ci-joint'),
    ('ci inclus', 'ci-inclus'),
    ('ci après', 'ci-après'),
    ('ci devant', 'ci-devant'),
    ('par dessus', 'par-dessus'),
    ('par dessous', 'par-dessous'),
    ('par delà', 'par-delà'),
    ('par derrière', 'par-derrière'),
    ('par devant', 'par-devant'),
    ('tout à fait', 'tout-à-fait'),  // sometimes hyphenated
    ('sur le champ', 'sur-le-champ'),
    ('d\'ores et déjà', 'd\'ores-et-déjà'),  // alternative form

    // =========================================================================
    // DIALOGUE INVERSIONS (VERBS WITH PRONOUNS)
    // Common patterns with -t- euphonic and inverted pronouns
    // =========================================================================
    // With -t- euphonic (for verbs ending in vowel)
    ('a t il', 'a-t-il'),
    ('a t elle', 'a-t-elle'),
    ('a t on', 'a-t-on'),
    ('y a t il', 'y a-t-il'),
    ('va t il', 'va-t-il'),
    ('va t elle', 'va-t-elle'),
    ('va t on', 'va-t-on'),
    ('sera t il', 'sera-t-il'),
    ('sera t elle', 'sera-t-elle'),
    ('sera t on', 'sera-t-on'),
    ('aura t il', 'aura-t-il'),
    ('aura t elle', 'aura-t-elle'),
    ('aura t on', 'aura-t-on'),
    ('ira t il', 'ira-t-il'),
    ('ira t elle', 'ira-t-elle'),
    ('ira t on', 'ira-t-on'),
    ('viendra t il', 'viendra-t-il'),
    ('viendra t elle', 'viendra-t-elle'),
    ('pourra t il', 'pourra-t-il'),
    ('pourra t elle', 'pourra-t-elle'),
    ('pourra t on', 'pourra-t-on'),
    ('devra t il', 'devra-t-il'),
    ('devra t elle', 'devra-t-elle'),
    ('devra t on', 'devra-t-on'),
    ('dira t il', 'dira-t-il'),
    ('dira t elle', 'dira-t-elle'),
    ('dira t on', 'dira-t-on'),
    ('fera t il', 'fera-t-il'),
    ('fera t elle', 'fera-t-elle'),
    ('fera t on', 'fera-t-on'),
    ('saura t il', 'saura-t-il'),
    ('saura t elle', 'saura-t-elle'),
    ('voudra t il', 'voudra-t-il'),
    ('voudra t elle', 'voudra-t-elle'),
    ('faudra t il', 'faudra-t-il'),
    ('restera t il', 'restera-t-il'),
    ('restera t elle', 'restera-t-elle'),
    ('arrivera t il', 'arrivera-t-il'),
    ('arrivera t elle', 'arrivera-t-elle'),
    ('trouvera t il', 'trouvera-t-il'),
    ('trouvera t elle', 'trouvera-t-elle'),
    ('parviendra t il', 'parviendra-t-il'),
    ('parviendra t elle', 'parviendra-t-elle'),
    ('réussira t il', 'réussira-t-il'),
    ('réussira t elle', 'réussira-t-elle'),
    ('survivra t il', 'survivra-t-il'),
    ('survivra t elle', 'survivra-t-elle'),
    ('tombera t il', 'tombera-t-il'),
    ('tombera t elle', 'tombera-t-elle'),

    // Simple inversions (verb-pronoun, no -t-)
    ('dit il', 'dit-il'),
    ('dit elle', 'dit-elle'),
    ('dit on', 'dit-on'),
    ('fait il', 'fait-il'),
    ('fait elle', 'fait-elle'),
    ('fait on', 'fait-on'),
    ('est il', 'est-il'),
    ('est elle', 'est-elle'),
    ('est ce', 'est-ce'),
    ('sont ils', 'sont-ils'),
    ('sont elles', 'sont-elles'),
    ('était il', 'était-il'),
    ('était elle', 'était-elle'),
    ('était ce', 'était-ce'),
    ('étaient ils', 'étaient-ils'),
    ('étaient elles', 'étaient-elles'),
    ('fut il', 'fut-il'),
    ('fut elle', 'fut-elle'),
    ('fut ce', 'fut-ce'),
    ('furent ils', 'furent-ils'),
    ('furent elles', 'furent-elles'),
    ('serait il', 'serait-il'),
    ('serait elle', 'serait-elle'),
    ('serait ce', 'serait-ce'),
    ('seraient ils', 'seraient-ils'),
    ('seraient elles', 'seraient-elles'),
    ('ont ils', 'ont-ils'),
    ('ont elles', 'ont-elles'),
    ('avait il', 'avait-il'),
    ('avait elle', 'avait-elle'),
    ('avaient ils', 'avaient-ils'),
    ('avaient elles', 'avaient-elles'),
    ('eut il', 'eut-il'),
    ('eut elle', 'eut-elle'),
    ('aurait il', 'aurait-il'),
    ('aurait elle', 'aurait-elle'),
    ('auraient ils', 'auraient-ils'),
    ('auraient elles', 'auraient-elles'),
    ('peut il', 'peut-il'),
    ('peut elle', 'peut-elle'),
    ('peut on', 'peut-on'),
    ('peuvent ils', 'peuvent-ils'),
    ('peuvent elles', 'peuvent-elles'),
    ('pouvait il', 'pouvait-il'),
    ('pouvait elle', 'pouvait-elle'),
    ('pouvait on', 'pouvait-on'),
    ('put il', 'put-il'),
    ('put elle', 'put-elle'),
    ('pourrait il', 'pourrait-il'),
    ('pourrait elle', 'pourrait-elle'),
    ('pourrait on', 'pourrait-on'),
    ('pourraient ils', 'pourraient-ils'),
    ('doit il', 'doit-il'),
    ('doit elle', 'doit-elle'),
    ('doit on', 'doit-on'),
    ('doivent ils', 'doivent-ils'),
    ('devait il', 'devait-il'),
    ('devait elle', 'devait-elle'),
    ('devait on', 'devait-on'),
    ('dut il', 'dut-il'),
    ('dut elle', 'dut-elle'),
    ('devrait il', 'devrait-il'),
    ('devrait elle', 'devrait-elle'),
    ('devrait on', 'devrait-on'),
    ('veut il', 'veut-il'),
    ('veut elle', 'veut-elle'),
    ('veut on', 'veut-on'),
    ('veulent ils', 'veulent-ils'),
    ('voulait il', 'voulait-il'),
    ('voulait elle', 'voulait-elle'),
    ('voulut il', 'voulut-il'),
    ('voudrait il', 'voudrait-il'),
    ('sait il', 'sait-il'),
    ('sait elle', 'sait-elle'),
    ('sait on', 'sait-on'),
    ('savent ils', 'savent-ils'),
    ('savait il', 'savait-il'),
    ('savait elle', 'savait-elle'),
    ('saurait il', 'saurait-il'),
    ('saurait on', 'saurait-on'),
    ('voit il', 'voit-il'),
    ('voit elle', 'voit-elle'),
    ('voit on', 'voit-on'),
    ('voient ils', 'voient-ils'),
    ('voyait il', 'voyait-il'),
    ('voyait on', 'voyait-on'),
    ('vit il', 'vit-il'),
    ('vit elle', 'vit-elle'),
    ('verrait il', 'verrait-il'),
    ('prend il', 'prend-il'),
    ('prend elle', 'prend-elle'),
    ('prend on', 'prend-on'),
    ('prennent ils', 'prennent-ils'),
    ('prit il', 'prit-il'),
    ('prit elle', 'prit-elle'),
    ('vient il', 'vient-il'),
    ('vient elle', 'vient-elle'),
    ('viennent ils', 'viennent-ils'),
    ('venait il', 'venait-il'),
    ('vint il', 'vint-il'),
    ('vint elle', 'vint-elle'),
    ('viendrait il', 'viendrait-il'),
    ('faut il', 'faut-il'),
    ('fallait il', 'fallait-il'),
    ('fallut il', 'fallut-il'),
    ('faudrait il', 'faudrait-il'),
    ('reste t il', 'reste-t-il'),
    ('semble t il', 'semble-t-il'),
    ('paraît il', 'paraît-il'),
    ('suffit il', 'suffit-il'),
    ('cria t il', 'cria-t-il'),
    ('cria t elle', 'cria-t-elle'),
    ('demanda t il', 'demanda-t-il'),
    ('demanda t elle', 'demanda-t-elle'),
    ('répondit il', 'répondit-il'),
    ('répondit elle', 'répondit-elle'),
    ('ajouta t il', 'ajouta-t-il'),
    ('ajouta t elle', 'ajouta-t-elle'),
    ('murmura t il', 'murmura-t-il'),
    ('murmura t elle', 'murmura-t-elle'),
    ('pensa t il', 'pensa-t-il'),
    ('pensa t elle', 'pensa-t-elle'),
    ('reprit il', 'reprit-il'),
    ('reprit elle', 'reprit-elle'),
    ('s\'écria t il', 's\'écria-t-il'),
    ('s\'écria t elle', 's\'écria-t-elle'),
    ('s\'exclama t il', 's\'exclama-t-il'),
    ('s\'exclama t elle', 's\'exclama-t-elle'),

    // =========================================================================
    // COMPOUND NUMBERS (21-99 with hyphens)
    // =========================================================================
    ('vingt et un', 'vingt-et-un'),
    ('vingt deux', 'vingt-deux'),
    ('vingt trois', 'vingt-trois'),
    ('vingt quatre', 'vingt-quatre'),
    ('vingt cinq', 'vingt-cinq'),
    ('vingt six', 'vingt-six'),
    ('vingt sept', 'vingt-sept'),
    ('vingt huit', 'vingt-huit'),
    ('vingt neuf', 'vingt-neuf'),
    ('trente et un', 'trente-et-un'),
    ('trente deux', 'trente-deux'),
    ('trente trois', 'trente-trois'),
    ('trente quatre', 'trente-quatre'),
    ('trente cinq', 'trente-cinq'),
    ('trente six', 'trente-six'),
    ('trente sept', 'trente-sept'),
    ('trente huit', 'trente-huit'),
    ('trente neuf', 'trente-neuf'),
    ('quarante et un', 'quarante-et-un'),
    ('quarante deux', 'quarante-deux'),
    ('quarante trois', 'quarante-trois'),
    ('quarante quatre', 'quarante-quatre'),
    ('quarante cinq', 'quarante-cinq'),
    ('quarante six', 'quarante-six'),
    ('quarante sept', 'quarante-sept'),
    ('quarante huit', 'quarante-huit'),
    ('quarante neuf', 'quarante-neuf'),
    ('cinquante et un', 'cinquante-et-un'),
    ('cinquante deux', 'cinquante-deux'),
    ('cinquante trois', 'cinquante-trois'),
    ('cinquante quatre', 'cinquante-quatre'),
    ('cinquante cinq', 'cinquante-cinq'),
    ('cinquante six', 'cinquante-six'),
    ('cinquante sept', 'cinquante-sept'),
    ('cinquante huit', 'cinquante-huit'),
    ('cinquante neuf', 'cinquante-neuf'),
    ('soixante et un', 'soixante-et-un'),
    ('soixante deux', 'soixante-deux'),
    ('soixante trois', 'soixante-trois'),
    ('soixante quatre', 'soixante-quatre'),
    ('soixante cinq', 'soixante-cinq'),
    ('soixante six', 'soixante-six'),
    ('soixante sept', 'soixante-sept'),
    ('soixante huit', 'soixante-huit'),
    ('soixante neuf', 'soixante-neuf'),
    ('soixante dix', 'soixante-dix'),
    ('soixante et onze', 'soixante-et-onze'),
    ('soixante douze', 'soixante-douze'),
    ('soixante treize', 'soixante-treize'),
    ('soixante quatorze', 'soixante-quatorze'),
    ('soixante quinze', 'soixante-quinze'),
    ('soixante seize', 'soixante-seize'),
    ('soixante dix sept', 'soixante-dix-sept'),
    ('soixante dix huit', 'soixante-dix-huit'),
    ('soixante dix neuf', 'soixante-dix-neuf'),
    ('quatre vingt', 'quatre-vingt'),
    ('quatre vingts', 'quatre-vingts'),
    ('quatre vingt un', 'quatre-vingt-un'),
    ('quatre vingt deux', 'quatre-vingt-deux'),
    ('quatre vingt trois', 'quatre-vingt-trois'),
    ('quatre vingt quatre', 'quatre-vingt-quatre'),
    ('quatre vingt cinq', 'quatre-vingt-cinq'),
    ('quatre vingt six', 'quatre-vingt-six'),
    ('quatre vingt sept', 'quatre-vingt-sept'),
    ('quatre vingt huit', 'quatre-vingt-huit'),
    ('quatre vingt neuf', 'quatre-vingt-neuf'),
    ('quatre vingt dix', 'quatre-vingt-dix'),
    ('quatre vingt onze', 'quatre-vingt-onze'),
    ('quatre vingt douze', 'quatre-vingt-douze'),
    ('quatre vingt treize', 'quatre-vingt-treize'),
    ('quatre vingt quatorze', 'quatre-vingt-quatorze'),
    ('quatre vingt quinze', 'quatre-vingt-quinze'),
    ('quatre vingt seize', 'quatre-vingt-seize'),
    ('quatre vingt dix sept', 'quatre-vingt-dix-sept'),
    ('quatre vingt dix huit', 'quatre-vingt-dix-huit'),
    ('quatre vingt dix neuf', 'quatre-vingt-dix-neuf'),

    // =========================================================================
    // COMPOUND WORDS COMMON IN FRENCH
    // =========================================================================
    // Time-related
    ('avant garde', 'avant-garde'),
    ('après midi', 'après-midi'),
    ('demi heure', 'demi-heure'),
    ('demi journée', 'demi-journée'),
    ('demi tour', 'demi-tour'),
    ('demi frère', 'demi-frère'),
    ('demi soeur', 'demi-sœur'),

    // Position/Direction
    ('contre attaque', 'contre-attaque'),
    ('contre offensive', 'contre-offensive'),
    ('contre ordre', 'contre-ordre'),
    ('contre mesure', 'contre-mesures'),
    ('contre coup', 'contre-coup'),
    ('contre pied', 'contre-pied'),
    ('contre sens', 'contre-sens'),
    ('contre courant', 'contre-courant'),
    ('en tête', 'en-tête'),
    ('face à face', 'face-à-face'),
    ('tête à tête', 'tête-à-tête'),
    ('corps à corps', 'corps-à-corps'),
    ('dos à dos', 'dos-à-dos'),
    ('côte à côte', 'côte-à-côte'),
    ('coude à coude', 'coude-à-coude'),
    ('nez à nez', 'nez-à-nez'),
    ('main dans la main', 'main-dans-la-main'),
    ('au fur et à mesure', 'au-fur-et-à-mesure'),

    // Military/Combat (relevant for Total War)
    ('avant poste', 'avant-poste'),
    ('arrière garde', 'arrière-garde'),
    ('arrière plan', 'arrière-plan'),
    ('chef d\'oeuvre', 'chef-d\'œuvre'),
    ('garde du corps', 'garde-du-corps'),
    ('homme d\'armes', 'homme-d\'armes'),
    ('fait d\'armes', 'fait-d\'armes'),
    ('porte étendard', 'porte-étendard'),
    ('porte drapeau', 'porte-drapeau'),
    ('porte parole', 'porte-parole'),
    ('sang froid', 'sang-froid'),
    ('sans peur', 'sans-peur'),
    ('sauve qui peut', 'sauve-qui-peut'),
    ('pied à terre', 'pied-à-terre'),
    ('passe partout', 'passe-partout'),
    ('laissez passer', 'laissez-passer'),
    ('cessez le feu', 'cessez-le-feu'),

    // Geography/Places
    ('nord est', 'nord-est'),
    ('nord ouest', 'nord-ouest'),
    ('sud est', 'sud-est'),
    ('sud ouest', 'sud-ouest'),
    ('pays bas', 'Pays-Bas'),
    ('moyen âge', 'Moyen-Âge'),

    // People/Titles
    ('beau père', 'beau-père'),
    ('belle mère', 'belle-mère'),
    ('beau frère', 'beau-frère'),
    ('belle soeur', 'belle-sœur'),
    ('beau fils', 'beau-fils'),
    ('belle fille', 'belle-fille'),
    ('grand père', 'grand-père'),
    ('grand mère', 'grand-mère'),
    ('grand oncle', 'grand-oncle'),
    ('grand tante', 'grand-tante'),
    ('petit fils', 'petit-fils'),
    ('petite fille', 'petite-fille'),
    ('petits enfants', 'petits-enfants'),
    ('arrière grand père', 'arrière-grand-père'),
    ('arrière grand mère', 'arrière-grand-mère'),
    ('nouveau né', 'nouveau-né'),
    ('mort vivant', 'mort-vivant'),
    ('morts vivants', 'morts-vivants'),
    ('loup garou', 'loup-garou'),
    ('loups garous', 'loups-garous'),
    ('haut placé', 'haut-placé'),
    ('bien aimé', 'bien-aimé'),
    ('bien aimée', 'bien-aimée'),
    ('mal aimé', 'mal-aimé'),
    ('tout puissant', 'tout-puissant'),
    ('toute puissante', 'toute-puissante'),
    ('tout terrain', 'tout-terrain'),

    // Actions/States
    ('court circuit', 'court-circuit'),
    ('coupe gorge', 'coupe-gorge'),
    ('bouche à oreille', 'bouche-à-oreille'),
    ('main d\'oeuvre', 'main-d\'œuvre'),
    ('faire part', 'faire-part'),
    ('savoir faire', 'savoir-faire'),
    ('savoir vivre', 'savoir-vivre'),
    ('laisser aller', 'laisser-aller'),
    ('laisser faire', 'laisser-faire'),
    ('va et vient', 'va-et-vient'),
    ('aller retour', 'aller-retour'),
    ('remue ménage', 'remue-ménage'),
    ('cache cache', 'cache-cache'),
    ('pêle mêle', 'pêle-mêle'),
    ('rendez vous', 'rendez-vous'),
    ('trompe l\'oeil', 'trompe-l\'œil'),
    ('cul de sac', 'cul-de-sac'),
    ('hors d\'oeuvre', 'hors-d\'œuvre'),
    ('mise en scène', 'mise-en-scène'),

    // Adjectives/Qualities
    ('bien être', 'bien-être'),
    ('mal être', 'mal-être'),
    ('à peu près', 'à-peu-près'),
    ('long terme', 'long-terme'),
    ('court terme', 'court-terme'),
    ('moyen terme', 'moyen-terme'),
    ('sur mesure', 'sur-mesure'),
    ('haut de gamme', 'haut-de-gamme'),
    ('bas de gamme', 'bas-de-gamme'),
    ('sous sol', 'sous-sol'),
    ('sous main', 'sous-main'),
    ('sous entendu', 'sous-entendu'),
    ('sous estimé', 'sous-estimé'),
    ('sur estimé', 'sur-estimé'),
    ('bien fondé', 'bien-fondé'),
    ('mal fondé', 'mal-fondé'),

    // Objects/Things
    ('arc en ciel', 'arc-en-ciel'),
    ('gratte ciel', 'gratte-ciel'),
    ('couvre feu', 'couvre-feu'),
    ('rez de chaussée', 'rez-de-chaussée'),
    ('chauffe eau', 'chauffe-eau'),
    ('tire bouchon', 'tire-bouchon'),
    ('ouvre boîte', 'ouvre-boîte'),
    ('lave vaisselle', 'lave-vaisselle'),
    ('lave linge', 'lave-linge'),
    ('sèche cheveux', 'sèche-cheveux'),
    ('essuie glace', 'essuie-glace'),
    ('abat jour', 'abat-jour'),
    ('chou fleur', 'chou-fleur'),
    ('pomme de terre', 'pomme-de-terre'),
    ('chef lieu', 'chef-lieu'),

    // Game-specific terms (Total War context)
    ('hors la loi', 'hors-la-loi'),
    ('arrière pays', 'arrière-pays'),
    ('empire empire', 'empire-empire'),
    ('haut elfe', 'haut-elfe'),
    ('hauts elfes', 'hauts-elfes'),
    ('demi elfe', 'demi-elfe'),
    ('demi elfes', 'demi-elfes'),
    ('homme lézard', 'homme-lézard'),
    ('hommes lézards', 'hommes-lézards'),
    ('homme bête', 'homme-bête'),
    ('hommes bêtes', 'hommes-bêtes'),
    ('semi divine', 'semi-divine'),
    ('semi divin', 'semi-divin'),
    ('sous race', 'sous-race'),
    ('auto destruction', 'auto-destruction'),
    ('auto défense', 'auto-défense'),
    // Spelling corrections for faction names
    ('Bretonni', 'Bretonnie'),
    ('bretonni', 'Bretonnie'),

    // Miscellaneous common expressions
    ('prêt à porter', 'prêt-à-porter'),
    ('en plein air', 'en-plein-air'),
    ('à brûle pourpoint', 'à-brûle-pourpoint'),
    ('à contre coeur', 'à-contre-cœur'),
    ('à contre courant', 'à-contre-courant'),
    ('à demi mot', 'à-demi-mot'),
    ('de temps en temps', 'de-temps-en-temps'),
    ('de ci de là', 'de-ci-de-là'),
    ('d\'arrache pied', 'd\'arrache-pied'),
    ('d\'un seul coup', 'd\'un-seul-coup'),
    ('non sens', 'non-sens'),
    ('non lieu', 'non-lieu'),
    ('non dit', 'non-dit'),
    ('non stop', 'non-stop'),
    ('non voyant', 'non-voyant'),
    ('pince sans rire', 'pince-sans-rire'),
    ('qu\'en dira t on', 'qu\'en-dira-t-on'),
  ];

  /// Fix missing hyphens in French translations.
  ///
  /// Scans all French translations and restores missing hyphens
  /// using pattern matching. Only updates records that actually change.
  ///
  /// Returns the number of translations fixed.
  static Future<int> fixMissingHyphens() async {
    final logging = LoggingService.instance;

    try {
      logging.debug('Checking for missing hyphens in French translations...');

      // Get French language project_language IDs
      final frenchProjectLanguages = await DatabaseService.database.rawQuery('''
        SELECT pl.id
        FROM project_languages pl
        INNER JOIN languages l ON pl.language_id = l.id
        WHERE l.code = 'fr'
      ''');

      if (frenchProjectLanguages.isEmpty) {
        logging.debug('No French project languages found, skipping hyphen fix');
        return 0;
      }

      final plIds = frenchProjectLanguages.map((r) => "'${r['id']}'").join(',');
      logging.debug('Found ${frenchProjectLanguages.length} French project language(s)');

      // Count potential matches first
      int totalFixed = 0;
      const batchSize = 500;

      // Process each pattern
      for (final (incorrect, correct) in hyphenPatterns) {
        // Skip if pattern already has hyphen (shouldn't happen but safety check)
        if (incorrect.contains('-')) continue;

        // Build case-insensitive search pattern
        // We need to find the pattern as a whole word/phrase
        final searchPattern = incorrect.toLowerCase();

        // Find translations with this pattern
        final matches = await DatabaseService.database.rawQuery('''
          SELECT id, translated_text
          FROM translation_versions
          WHERE project_language_id IN ($plIds)
            AND translated_text IS NOT NULL
            AND LOWER(translated_text) LIKE ?
          LIMIT $batchSize
        ''', ['%$searchPattern%']);

        if (matches.isEmpty) continue;

        // Update each match
        for (final row in matches) {
          final id = row['id'] as String;
          final text = row['translated_text'] as String;

          // Apply case-insensitive replacement
          final newText = _replaceIgnoreCase(text, incorrect, correct);

          if (newText != text) {
            await DatabaseService.database.rawUpdate('''
              UPDATE translation_versions
              SET translated_text = ?, updated_at = ?
              WHERE id = ?
            ''', [newText, DateTime.now().millisecondsSinceEpoch ~/ 1000, id]);
            totalFixed++;
          }
        }
      }

      if (totalFixed > 0) {
        logging.info('Fixed missing hyphens in $totalFixed French translations');

        // Rebuild FTS index for updated translations
        try {
          await DatabaseService.execute('''
            INSERT INTO translation_versions_fts(translation_versions_fts) VALUES('rebuild')
          ''').timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              logging.warning('FTS rebuild timed out after hyphen fix');
            },
          );
        } catch (e) {
          logging.warning('FTS rebuild skipped after hyphen fix: $e');
        }
      } else {
        logging.debug('No missing hyphens found in French translations');
      }

      return totalFixed;
    } catch (e, stackTrace) {
      logging.error('Failed to fix French hyphens', e, stackTrace);
      return 0;
    }
  }

  /// Replace text case-insensitively while preserving the original case of surrounding text.
  static String _replaceIgnoreCase(String text, String from, String to) {
    final lowerText = text.toLowerCase();
    final lowerFrom = from.toLowerCase();

    final buffer = StringBuffer();
    int lastEnd = 0;

    int index = lowerText.indexOf(lowerFrom, lastEnd);
    while (index != -1) {
      // Add text before match
      buffer.write(text.substring(lastEnd, index));

      // Check word boundaries to avoid partial matches
      final isWordStart = index == 0 ||
          !_isWordChar(text.codeUnitAt(index - 1));
      final isWordEnd = index + from.length >= text.length ||
          !_isWordChar(text.codeUnitAt(index + from.length));

      if (isWordStart && isWordEnd) {
        // Apply replacement, preserving first letter case
        final originalFirst = text[index];
        if (originalFirst.toUpperCase() == originalFirst) {
          // Original starts with uppercase, capitalize replacement
          buffer.write(to[0].toUpperCase());
          buffer.write(to.substring(1));
        } else {
          buffer.write(to);
        }
      } else {
        // Not a word boundary match, keep original
        buffer.write(text.substring(index, index + from.length));
      }

      lastEnd = index + from.length;
      index = lowerText.indexOf(lowerFrom, lastEnd);
    }

    // Add remaining text
    buffer.write(text.substring(lastEnd));

    return buffer.toString();
  }

  /// Check if character is a word character (letter or digit).
  static bool _isWordChar(int codeUnit) {
    // a-z, A-Z, 0-9, or common accented characters
    return (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
        (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0xC0 && codeUnit <= 0xFF); // Latin Extended-A (accents)
  }
}
