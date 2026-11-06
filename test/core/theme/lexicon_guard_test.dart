import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/copy_scan.dart';
import '../../test_helpers/app_sources.dart';

/// The brand book's lexicon, held on the copy: **one word per state, the same
/// on every screen**, none of the words its *Never* list bans, American
/// spelling throughout (color, catalog, canceled, -ize), and no em dash as
/// punctuation: the dash is the placeholder of a figure nobody could read, and
/// only that.
///
/// A source scan because the regression is one plausible string in a diff:
/// "Offline" reads as a fine label until the next screen says "Did not
/// answer" about the same server. The words live in `core/status/lexicon.dart`
/// and in the failure classification (`core/network/connection_failure.dart`);
/// this keeps the variants from coming back.
///
/// What it reads: every string literal in `lib/`, with its interpolations
/// blanked (an identifier such as `folded.offline` inside `${…}` is code, not
/// copy), and adjacent literals joined as Dart joins them, so a sentence
/// wrapped across lines is read whole. What it leaves alone, because none of it is read by a person:
///
///  * a literal matched against a wire value: after `==`, `!=` or `case`, as
///    a `switch` pattern (followed by `=>` or `||`), a map key or case label
///    (followed straight by `:`), an index (`json['IsPaused']`), or the
///    argument of `contains`/`startsWith`/`endsWith`;
///  * raw strings, which are patterns;
///  * a literal with no space in it that carries `/`, `-` or `_`: an API
///    path (`/api/v2/torrents/reannounce`), an RPC method
///    (`torrent-reannounce`), a key;
///  * directives (`import`, `export`, `part`).
///
/// Everything else is copy, including semantics labels and toasts. A banned
/// word that must stay is listed in [_allowed] with the reason it is not the
/// banned state.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .where((f) => !isServerStandIn(f.path))
      .toList(growable: false);

  test('lib/ has copy to scan', () {
    final count = libFiles.fold<int>(
      0,
      (sum, f) => sum + copyOf(f.path, f.readAsStringSync()).length,
    );
    // A lexer that silently found nothing would pass every check below.
    expect(count, greaterThan(5000));
  });

  test('no copy in lib/ uses a word the lexicon bans', () {
    final offenders = <String>[];
    for (final file in libFiles) {
      for (final literal in copyOf(file.path, file.readAsStringSync())) {
        for (final MapEntry(key: word, value: pattern) in _never.entries) {
          if (!pattern.hasMatch(literal.prose)) continue;
          if (_isAllowed(literal)) continue;
          offenders.add(
            '${literal.path}:${literal.line}  [$word]  "${literal.prose}"',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Copy here uses a word the brand book bans. Use the lexicon '
          '(StateWord, Lexicon, failureLabel/failureHeadline): Answering\u00A0· '
          'Did not answer\u00A0· Not set up\u00A0· Set up X\u00A0· Retry\u00A0· Stuck\u00A0· Stopped\u00A0· '
          'Waiting for approval\u00A0· Could not (never the contraction, never '
          '"Failed to"). The app writes American English: color, catalog, '
          'canceled, organize. A word '
          'that is not the banned state goes in '
          '_allowed with its reason.',
    );
  });

  test('no copy in lib/ uses an em dash as punctuation', () {
    final offenders = [
      for (final file in libFiles)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_emDashAsPunctuation(literal.prose) && !_isAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'An em dash between words is punctuation, and the app has none: '
          'rewrite with a full stop, a colon, a comma or "\u00A0· ". The dash '
          'stays only as the placeholder of a figure nobody could read '
          '(Lexicon.noFigure), and a range takes the en dash: S2 E4–E5.',
    );
  });

  group('the em dash matcher', () {
    test('catches a dash between two words or two holes', () {
      for (final prose in [
        'Saved \u2014 Radarr',
        '$copyHole \u2014 $copyHole',
        'Radarr did not answer \u2014 Retry',
        'Radarr\u2014Sonarr',
        '10\u201420',
        '($copyHole) \u2014 $copyHole',
      ]) {
        expect(_emDashAsPunctuation(prose), isTrue, reason: prose);
      }
    });

    test('lets the placeholder of a figure through', () {
      for (final prose in [
        '\u2014',
        '\u2014 in the queue',
        '\u2014 / 24',
        '\u2014s',
        'today\u00A0· \u2014',
        'Queue: \u2014',
        '↓ \u2014 ↑ \u2014',
        '$copyHole\u00A0· \u2014 free',
        // The en dash is the range's, and not this guard's business.
        'S2 E4–E5',
      ]) {
        expect(_emDashAsPunctuation(prose), isFalse, reason: prose);
      }
    });

    test('a planted literal fails through the same lexer, a comment does '
        'not', () {
      const planted =
          "final a = 'Saved \u2014 Radarr';\n"
          "final b = '\${first.title} \u2014 \${second.title}';"
          '\n'
          '// A comment \u2014 not copy.\n'
          "final c = count == null ? '\u2014' : '\$count in the queue';\n"
          "final d = '\u2014 in the queue';\n";
      final caught = [
        for (final literal in copyOf('lib/zz_planted.dart', planted))
          if (_emDashAsPunctuation(literal.prose)) literal.prose,
      ];
      expect(caught, ['Saved \u2014 Radarr', '$copyHole \u2014 $copyHole']);
    });
  });

  test('a sentence wrapped across adjacent literals is read whole', () {
    // Dart joins adjacent literals into one string, so a phrase split at the
    // wrap is one phrase on screen: read per literal, `'… try '` `'again.'`
    // hid a banned "try again" from every check above.
    const planted =
        "final a = 'Refresh the list and try '\n"
        "    // a comment between the halves\n"
        "    'again.';\n"
        "final b = ['try', 'again'];\n";
    final prose = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        literal.prose,
    ];
    expect(prose, ['Refresh the list and try again.', 'try', 'again']);
    expect(_never['Try again → Retry']!.hasMatch(prose.first), isTrue);
  });

  test('a contracted "could not" fails through the same lexer, a comment '
      'does not', () {
    // The app writes the phrase out: a straight or a curly apostrophe, in
    // either case, inside a literal is the contraction this entry bans.
    const planted = r"""
final a = 'Cupola couldn\'t reach it';
final b = "Couldn't add $title";
final c = 'Couldn’t load more';
// Couldn't, in a comment, is not copy.
final d = 'Could not add it';
final e = "The server couldn't check $it";
""";
    final caught = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        if (_never["Couldn't → Could not"]!.hasMatch(literal.prose))
          literal.prose,
    ];
    expect(caught, [
      "Cupola couldn't reach it",
      "Couldn't add $copyHole",
      'Couldn’t load more',
      "The server couldn't check $copyHole",
    ]);
  });

  test('"Failed to" fails through the same lexer; a comment, a wire value and '
      'a state word do not', () {
    // The app says "Could not" in a toast and a failure line alike. A server's
    // own message (`text == 'Failed to …'`) is matched, never shown, and
    // "Import failed" is a state, not the verb phrase this entry bans.
    const planted = r"""
final a = 'Failed to pause the job';
final b = "Failed to add $title";
// Failed to, in a comment, is not copy.
final c = 'Could not pause the job';
final d = 'Import failed';
final e = text == 'Failed to check Quick Connect status';
final f = 'failed to start';
""";
    final caught = [
      for (final literal in copyOf('lib/zz_planted.dart', planted))
        if (_never['Failed to → Could not']!.hasMatch(literal.prose))
          literal.prose,
    ];
    expect(caught, [
      'Failed to pause the job',
      'Failed to add $copyHole',
      'failed to start',
    ]);
  });

  group('the British spelling matcher', () {
    test('catches the British forms', () {
      for (final prose in [
        'Each service keeps its own colour',
        'Coloured, colouring, colourful, watercolour',
        'From the Seerr catalogue',
        'Cataloguing 3 catalogues',
        'Search cancelled.',
        'Cancelling the request',
        'Cancelled, background search was turned off.',
        'Behaviour',
        'Misbehaviour',
        'Add to favourites',
        'In honour of the host',
        'Neighbouring services',
        'Nothing is labelled',
        'Labelling the album',
        'Travelled, travelling, traveller',
        'A modelled response',
        'The signalled change, signalling',
        'An open-source licence',
        'Licences',
        'In the centre of the screen',
        '5 metres, 2 kilometres',
        'Home theatre',
        'Fibre connection',
        'A grey band, greyed out',
        'The artefact',
        'Dialogue',
        'A matter of judgement',
        'Ageing disks',
        'Whilst it runs',
        'Amongst the rest',
        'What we learnt',
        'Programme the box',
        'Defence, offence, pretence',
        // The -ise family, stem by stem.
        'Organise the files',
        'Organisation settings',
        'Did not recognise this server',
        'Unrecognised certificate',
        'Authorise the request',
        'Realised too late',
        'Apologise for the delay',
        'Prioritise the queue',
        'Summarise the week',
        'Customise the tabs',
        'Optimise the library',
        'Utilise the space',
        'Minimise the window',
        'Maximise the window',
        'Help finalise parsing',
        'Normalised titles',
        'Initialising the client',
        'Serialise the stack',
        'Visualise the queue',
        'Personalised for you',
        'Standardise the names',
        'Synchronise the clocks',
        'Categorise the releases',
        'Specialised search',
        'Localise the copy',
        'Sanitise the input',
        'Analyse the log',
        'Analysed twice',
        'Analysing the queue',
        'Emphasise the title',
        'Emphasises it, emphasising it',
        'Paralyse the queue',
        'Paralysed by a retry',
        'MINIMISE',
      ]) {
        expect(_britishSpelling.hasMatch(prose), isTrue, reason: prose);
      }
    });

    test('lets the American forms and the look-alike words through', () {
      for (final prose in [
        'Each service keeps its own color',
        'Colored, coloring, colorful',
        'From the Seerr catalog',
        'Search canceled.',
        'Canceling the request',
        'Cancellation is final',
        'Behavior',
        'Add to favorites',
        'In honor of the host',
        'Neighboring services',
        'Nothing is labeled',
        'Traveled, traveling, traveler',
        'An open-source license',
        'In the center of the screen',
        '5 meters, 2 kilometers',
        'Home theater',
        'A gray band, grayed out',
        'The artifact',
        'Dialog',
        'A matter of judgment',
        'Aging disks',
        'While it runs',
        'Among the rest',
        'What we learned',
        'Program the box',
        'Defense, offense, pretense',
        'Organize the files',
        'Minimize the window',
        'Help finalize parsing',
        'Analyze the log',
        'The analyses of the logs',
        'Emphasize the title',
        // The words a generic -ise pattern would trip on.
        'A promise, otherwise precise',
        'Exercise caution',
        'A surprise',
        'Advise Radarr first',
        'Compromise, revise, supervise, enterprise, franchise',
        'The analysis, the emphasis, the paralysis',
        'Organism, optimism, specialist, realism, surrealist',
        'A metered connection, a meter',
        'Centered, centering',
      ]) {
        expect(_britishSpelling.hasMatch(prose), isFalse, reason: prose);
      }
    });
  });

  test('every allow-list entry still matches something', () {
    // An entry whose site was fixed or moved is an exception nobody needs,
    // and it would quietly excuse the next occurrence in that file.
    final unused = <String>[];
    for (final entry in _allowed) {
      final source = File(entry.file).existsSync()
          ? File(entry.file).readAsStringSync()
          : '';
      final hit = copyOf(
        entry.file,
        source,
      ).any((literal) => literal.prose == entry.literal);
      if (!hit) unused.add('${entry.file}  "${entry.literal}"');
    }
    expect(unused, isEmpty);
  });
}

/// The *Never* list, as the copy spells it. Case-insensitive where the word
/// is banned in any case; a whole-label match where the word is fine inside a
/// sentence and banned only as a state or a verb on its own.
final _never = <String, RegExp>{
  'Pending → Waiting for approval': RegExp(
    r'\bpending\b',
    caseSensitive: false,
  ),
  'Offline / Online as a state': RegExp(
    r'\b(offline|online)\b',
    caseSensitive: false,
  ),
  'Connected': RegExp(r'\b(dis)?connected\b', caseSensitive: false),
  'Unreachable → Did not answer': RegExp(
    r'\bunreachable\b',
    caseSensitive: false,
  ),
  'not answering → did not answer': RegExp(
    r'\bnot answering\b',
    caseSensitive: false,
  ),
  'did not respond → did not answer': RegExp(
    r"\b(did not|didn't|does not|doesn't) respond",
    caseSensitive: false,
  ),
  'No response → did not answer': RegExp(
    r'\bno response\b',
    caseSensitive: false,
  ),
  'Down as a state': RegExp(r'^Down$'),
  'Not configured → Not set up': RegExp(
    r'\bnot configured\b',
    caseSensitive: false,
  ),
  'Connect X → Set up X': RegExp(r'\bConnect (\S)|^Connect$'),
  'Try again → Retry': RegExp(r'\btry again\b', caseSensitive: false),
  'Film → Movie': RegExp(r'\bfilms?\b', caseSensitive: false),
  'X copied to clipboard → Copied': RegExp(
    r'\b(name|hash) copied\b|\bcopied to (the )?clipboard\b',
    caseSensitive: false,
  ),
  'Paused → Stopped': RegExp(r'\bpaused\b', caseSensitive: false),
  'Stalled → Stuck': RegExp(r'\bstalled\b', caseSensitive: false),
  'Live': RegExp(r'\bLive\b'),
  'Instantly': RegExp(r'\binstantly\b', caseSensitive: false),
  'Please wait': RegExp(r'\bplease wait\b', caseSensitive: false),
  'Oops / Sorry': RegExp(r'\b(oops|sorry)\b', caseSensitive: false),
  'Error 401': RegExp(r'\bError \d{3}\b'),
  'Reannounce → Look for peers again': RegExp(
    r'\breannounce',
    caseSensitive: false,
  ),
  'Blocklist and search → Try another download': RegExp(
    r'\bblocklist and search\b',
    caseSensitive: false,
  ),
  'Snooze → Keep waiting': RegExp(r'\bsnooze', caseSensitive: false),
  'a bare Delete': RegExp(r'^Delete$'),
  "Couldn't → Could not": RegExp(r"\bcouldn['’]t\b", caseSensitive: false),
  'Failed to → Could not': RegExp(r'\bfailed to\b', caseSensitive: false),
  'Three dots at the end → no ellipsis': RegExp(r'\.\.\.$'),
  'Could not load X → the classification\'s headline': RegExp(
    r'\b(could not|failed to) load\b',
    caseSensitive: false,
  ),
  'British spelling → American': _britishSpelling,
};

/// The British spellings the app does not write: its copy is American English
/// (color, catalog, canceled, organize). Built from explicit stems, never from
/// a generic `\w+ise\b`, which would trip on promise, otherwise, precise,
/// exercise, surprise and advise.
///
/// `analyses` and `paralyses` are left out on purpose: they are also the plural
/// of analysis and paralysis, and plain American English.
final _britishSpelling = RegExp(
  [
    // -our: colour, favourite, honour, neighbour, behaviour, humour…
    r'(?:colo|favo|hono|neighbo|behavio|labo|humo|rumo|flavo|harbo|odo|armo'
        r'|savo|vapo|rigo|vigo|valo|tumo|endeavo|splendo)ur',
    // -ogue: catalogue (dialogue stays below, `dialog` is the American one).
    r'\bcatalogu(?:e|es|ed|ing)\b',
    r'\bdialogues?\b',
    // A doubled l before a suffix: cancelled, labelled, travelled, modelled…
    r'\b(?:cancell|labell|travell|modell|signall|fuell|levell|channell'
        r'|tunnell)(?:ed|ing|er|ers)\b',
    // -re: centre, metre, theatre, fibre, calibre…
    r'\b(?:centr|theatr|fibr|calibr|lustr|spectr|sombr)(?:e|es|ed|ing)\b',
    r'\b(?:kilo|milli|centi|deci)?metres?\b',
    // -ce: licence, defence, offence, pretence.
    r'\blicenc(?:e|es|ed|ing)\b',
    r'\b(?:defence|offence|pretence)(?:s|less)?\b',
    // Single words.
    r'\bgrey',
    r'\bartefacts?\b',
    r'\bjudgements?\b',
    r'\bageing\b',
    r'\b(?:whilst|amongst|learnt)\b',
    r'\bprogrammes?\b',
    r'\bcheques?\b',
    r'\btyres?\b',
    r'\bmould',
    r'\bplough',
    r'\bsceptic',
    r'\bjewellery\b',
    r'\baluminium\b',
    r'\bmanoeuvr',
    r'\bpractis(?:e|es|ed|ing)\b',
    r'\b(?:fulfil|enrol)\b',
    r'\b(?:skilful|wilful|instalments?)\b',
    // -ise by explicit stem: organise, recognise, authorise, realise…
    r'(?:organis|recognis|authoris|realis|apologis|prioritis|summaris'
        r'|customis|optimis|utilis|minimis|maximis|finalis|normalis'
        r'|initialis|serialis|visualis|personalis|standardis|synchronis'
        r'|categoris|specialis|localis|sanitis|capitalis|criticis|memoris'
        r'|mobilis|digitis|centralis|generalis|familiaris|harmonis|legalis'
        r'|materialis|modernis|rationalis|randomis|stabilis|symbolis'
        r'|sympathis|tokenis|virtualis|formalis|globalis|equalis|fertilis'
        r'|scrutinis|subsidis|characteris|computeris|hypnotis|idealis'
        r'|magnetis|jeopardis|pasteuris|publicis|popularis)'
        r'(?:e|es|ed|ing|ation|ations|er|ers)\b',
    // -yse: analyse, paralyse, catalyse (never the plural of -ysis).
    r'(?:analys|paralys|catalys)(?:e|ed|ing|er|ers)\b',
    r'emphasis(?:e|ed|es|ing)\b',
  ].join('|'),
  caseSensitive: false,
);

/// The words that stay, each with the reason it is not the banned state.
const _allowed = <({String file, String literal, String reason})>[
  (
    file: 'lib/features/settings/domain/service_key.dart',
    literal:
        'Unraid 7.2 and later have the API built in; on an older release, '
        'install the Unraid Connect plugin first. Then create an API key '
        'under Settings → Management Access → API Keys.',
    reason:
        'Unraid Connect is the name of the plugin that carries the API before '
        'Unraid 7.2, the words a person searches its app store for',
  ),
  (
    file: 'lib/features/settings/domain/service_key.dart',
    literal:
        'Before Unraid 7.2 the API comes with the Unraid Connect plugin, and '
        'the endpoint stays silent without it.',
    reason: 'Unraid Connect is the plugin\'s name, as above',
  ),
  (
    file: 'lib/features/tracearr/domain/models/tracearr_server.dart',
    literal: 'online',
    reason:
        "the name of the field Tracearr's health read uses for a server it "
        'reaches, read off the wire; never shown',
  ),
  (
    file: 'lib/features/discover/data/seerr_service.dart',
    literal: 'pending',
    reason:
        "the name of Seerr's own request filter, sent as `filter=pending` "
        'on the wire; never shown',
  ),
  (
    file: 'lib/features/unraid/presentation/unraid_screen.dart',
    literal: 'paused',
    reason:
        "libvirt's PAUSED: a VM held in memory, a state apart from shut off, "
        'which already reads "stopped"; the service\'s own term for its '
        'own state',
  ),
  (
    file: 'lib/features/unraid/domain/models/unraid_models.dart',
    literal: 'paused',
    reason:
        "Docker's paused container, apart from an exited one, which reads "
        '"stopped"',
  ),
  (
    file: 'lib/core/status/lexicon.dart',
    literal: 'Paused',
    reason:
        "a viewer's pause in a player (`StateWord.paused`): the session is "
        'still listed and holds its place; downloads stay "Stopped"',
  ),
  (
    file: 'lib/features/stream/domain/stream_semantics.dart',
    literal: 'paused',
    reason:
        "a viewer's pause in a player: \"stopped\" would say they ended "
        'playback, which is a different session state',
  ),
  (
    file: 'lib/features/dockge/presentation/dockge_stack_detail_screen.dart',
    literal: 'Down',
    reason:
        "the stack action is Docker Compose's own verb (`compose down`), "
        'not a state',
  ),
  (
    file:
        'lib/features/truenas/presentation/system/truenas_diagnostics_screen.dart',
    literal:
        'Debug-only: raw JSON-RPC responses from the connected server. Copy '
        'these to help finalize parsing.',
    reason: 'a debug-only diagnostic screen, not product copy',
  ),
  (
    file: 'lib/features/transmission/presentation/transmission_screen.dart',
    literal: 'reannounce',
    reason:
        'the menu item\'s value, a code key its switch matches; the item '
        'reads "Look for peers again"',
  ),
  (
    file: 'lib/features/dockge/domain/models/dockge_agent.dart',
    literal: 'online',
    reason: "Dockge's own agent status, the wire default the model parses",
  ),
  (
    file:
        'lib/features/qbittorrent/presentation/widgets/add_torrent_button.dart',
    literal: 'magnet:?xt=urn:btih:...',
    reason: 'the shape of a magnet link, a format example and not a sentence',
  ),
  (
    file: 'lib/core/widgets/reel_command_button.dart',
    literal: '$copyHole...',
    reason:
        'a width candidate the button measures its slot on: the busy label '
        'with the full set of trailing dots the waiting animation draws',
  ),
  (
    file: 'lib/features/prowlarr/domain/models/prowlarr_models.dart',
    literal: 'cancelled',
    reason:
        "Prowlarr's own command status, the wire value `isFinished` compares; "
        'never shown',
  ),
  (
    file: 'lib/features/jellyfin/domain/models/jellyfin_models.dart',
    literal: 'cancelled',
    reason:
        "Jellyfin's own scheduled-task state, the wire value the model "
        'compares; never shown',
  ),
  (
    file: 'lib/features/release_search/data/release_search_transport.dart',
    literal: 'cancelled',
    reason:
        "the `reason` of Dio's `requestCancelled`, a marker on the exception "
        'the search maps to its own wording; never shown',
  ),
];

bool _isAllowed(CopyLiteral literal) {
  if (_isNotConfiguredMarker(literal.prose)) return true;
  if (_isMachineString(literal.prose)) return true;
  return _allowed.any(
    (entry) => entry.file == literal.path && entry.literal == literal.prose,
  );
}

/// `'<Service> not configured'`, the throw `AsyncValueWidget` and its peers
/// detect to draw the not-set-up placeholder (the missing-config convention).
/// A marker, never drawn: the placeholder says *Radarr is not set up*.
bool _isNotConfiguredMarker(String prose) {
  const suffix = ' not configured';
  if (!prose.endsWith(suffix)) return false;
  final subject = prose.substring(0, prose.length - suffix.length);
  return subject == copyHole ||
      ServiceKey.values.any((service) => service.title == subject);
}

/// Whether [prose] uses the em dash (U+2014) as punctuation: a word, a figure
/// or an interpolation on either side of it (`Saved \u2014 Radarr`,
/// `∅ \u2014 ∅`, `10\u201420`).
///
/// The dash that stays is the placeholder of a figure nobody could read, and
/// that one always has an edge or a separator beside it rather than a word on
/// both sides: alone (`\u2014`), opening the phrase it counts
/// (`\u2014 in the queue`, `\u2014 / 24`, `\u2014s`) or closing one
/// (`today · \u2014`, `Queue: \u2014`).
bool _emDashAsPunctuation(String prose) {
  for (
    var i = prose.indexOf('\u2014');
    i >= 0;
    i = prose.indexOf('\u2014', i + 1)
  ) {
    final before = prose.substring(0, i).trimRight();
    final after = prose.substring(i + 1).trimLeft();
    if (before.isEmpty || after.isEmpty) continue;
    if (_closesWord.hasMatch(before[before.length - 1]) &&
        _opensWord.hasMatch(after[0])) {
      return true;
    }
  }
  return false;
}

/// The last character of a word, a figure or a hole, as the dash's left side.
final _closesWord = RegExp('[\\p{L}\\p{N}$copyHole)\\]"\'’]', unicode: true);

/// The first character of a word, a figure or a hole, as the dash's right side.
final _opensWord = RegExp('[\\p{L}\\p{N}$copyHole(\\["\'‘]', unicode: true);

/// An API path, an RPC method or a key: no space, and a `/`, `-` or `_`.
bool _isMachineString(String prose) =>
    !prose.contains(' ') && RegExp(r'[/_-]').hasMatch(prose);
