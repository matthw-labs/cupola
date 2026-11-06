import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/platform/secure_clipboard.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_access_rules.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:cupola/features/settings/presentation/widgets/connection_access_fields.dart';
import 'package:cupola/features/settings/presentation/widgets/invite_sheet.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_account_fields.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/core/widgets/service_mark_tile.dart';

/// One service's address and credentials, and the state of that connection.
///
/// This is where a red service gets fixed, so the screen leads with what is
/// wrong: the header states the saved connection in the service's own colour,
/// and a failed test names the actual cause: a rejected key, a wrong base
/// path, an untrusted certificate, rather than listing everything it could be.
class ServiceSettingsScreen extends ConsumerStatefulWidget {
  final ServiceKey service;

  /// Which connection this form edits. Null means the service's first one,
  /// which is what every caller meant before there could be a second.
  final String? instanceId;

  /// Whether this form is adding a connection rather than editing one.
  ///
  /// Distinct from a null [instanceId] because a new instance has no id to name
  /// until it is saved: minting one and passing it here would have the form
  /// look for something that is not in settings yet and quietly fall back to
  /// editing the first.
  final bool isNew;

  /// Injectable so a widget test can stay off a real socket; see
  /// [CertificateProber].
  final CertificateProber certificateProber;

  /// Injectable for the same reason: the real one reaches the host OS and, on
  /// iOS, can put a permission alert on screen.
  final LocalNetworkProbe localNetworkProbe;

  /// The Access choice to open on, for a gateway's remedy: the form scrolls to
  /// its Access row, with this choice made when the connection has none yet.
  final AccessKind? initialAccess;

  /// Opens on the address away, focused: the remedy of a connection only at
  /// home (`Add an address away`), whose fix is that field.
  final bool focusAway;

  /// A server another connection knows, to add: the connection that knows it
  /// ([foundFrom], a Seerr or a Prowlarr) and the name it gives it
  /// ([foundName]). The form asks that connection again and fills in what it
  /// says (address, key, name), so nothing secret travels in the location.
  final String? foundFrom;
  final String? foundName;

  /// An address to start the form on, for a connection added because another
  /// form's test found this service there (`Set up Emby`). Only the address:
  /// the key is this service's own and is never carried over.
  final String? prefillUrl;

  /// The gateway access the address was reached with, so a service behind the
  /// same proxy is not asked for it again. Held in memory beside the
  /// navigation rather than in the location, because it is secret.
  final ConnectionAccess? prefillAccess;

  const ServiceSettingsScreen({
    super.key,
    required this.service,
    this.instanceId,
    this.isNew = false,
    this.certificateProber = probeUntrustedCertificate,
    this.localNetworkProbe = probeLocalNetworkAccess,
    this.initialAccess,
    this.focusAway = false,
    this.foundFrom,
    this.foundName,
    this.prefillUrl,
    this.prefillAccess,
  });

  @override
  ConsumerState<ServiceSettingsScreen> createState() =>
      _ServiceSettingsScreenState();
}

class _ServiceSettingsScreenState extends ConsumerState<ServiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _labelController;

  /// The address away from home, empty when the connection has none.
  late final TextEditingController _awayController;

  /// The Access row: what this connection presents to a gateway in front of
  /// the service. The same controller and row the first-run walk uses.
  late final ConnectionAccessController _access;
  late ConnectionAccess _initialAccess;

  /// The Access row of the address away: the gateway in front of it is
  /// usually not the one at home (a tunnel, a proxy with a password).
  late final ConnectionAccessController _awayAccess;
  late ConnectionAccess _initialAwayAccess;

  /// Seerr only: how this connection signs in, the key or an account.
  late SeerrSignInWith _signInWith;
  late SeerrSignInWith _initialSignInWith;
  final _urlFocus = FocusNode();
  final _awayFocus = FocusNode();
  final _labelFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _credentialFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _urlFieldKey = GlobalKey<FormFieldState<String>>();
  final _awayFieldKey = GlobalKey<FormFieldState<String>>();
  final _labelFieldKey = GlobalKey<FormFieldState<String>>();
  final _usernameFieldKey = GlobalKey<FormFieldState<String>>();
  final _credentialFieldKey = GlobalKey<FormFieldState<String>>();
  final _passwordFieldKey = GlobalKey<FormFieldState<String>>();
  final _accessKey = GlobalKey();
  final _awayAccessKey = GlobalKey();

  /// The access the last test sent, which decides how its outcome is said.
  ConnectionAccess _testedAccess = const NoAccess();
  ConnectionAccess _testedAwayAccess = const NoAccess();

  /// The connections a token that just passed its test could also reach:
  /// their last failure was the same Access team. Empty when there is no
  /// offer to make.
  List<ServiceInstance> _shareCandidates = const [];

  /// The connection being edited, as it stood when the form opened.
  ///
  /// Only [ServiceInstance.id] is relied on afterwards: every write re-reads
  /// the live one by that id, so a value changed elsewhere while this form sat
  /// open is not clobbered by a stale copy.
  late final ServiceInstance _target;

  bool _saving = false;
  bool _testing = false;
  bool _revealApiKey = false;

  /// Result of the last "Test connection", or null when it has not been run
  /// since the fields last changed.
  ServiceDiagnosis? _testResult;

  /// The same test's answer at the address away, or null when the form has
  /// none.
  ServiceDiagnosis? _awayTestResult;

  /// The server this form was opened to add, once the connection that knows
  /// it has said so; see [ServiceSettingsScreen.foundFrom].
  ConnectionCandidate? _found;
  ProviderSubscription<AsyncValue<List<ConnectionCandidate>>>? _foundAsked;

  /// Field values as loaded, so leaving with edits can warn instead of silently
  /// discarding them.
  late final Map<String, String> _initialValues;

  ServiceKey get service => widget.service;

  bool get isPlex => service == ServiceKey.plex;

  /// Services authenticated with username/password rather than an API key.
  ///
  /// The registry owns this fact; see [ServiceKeyExtension.usesApiKey]. Spelled
  /// out here as its own three-way check, adding a credential-authenticated
  /// service meant this screen and the persistence layer could disagree about
  /// which fields the service even has.
  bool get usesCredentials => !service.usesApiKey;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(currentSettingsProvider);
    final named = widget.instanceId == null
        ? null
        : settings.instanceById(widget.instanceId!);
    _target = widget.isNew
        ? settings.newInstanceFor(service)
        // An id belonging to another service is ignored rather than trusted:
        // writing this form's fields onto a Sonarr would be silent corruption.
        : (named != null && named.service == service
              ? named
              : settings.primaryOf(service) ??
                    settings.newInstanceFor(service));

    _urlController = TextEditingController(text: _target.url);
    _apiKeyController = TextEditingController(
      text: usesCredentials ? '' : _target.credential,
    );
    _usernameController = TextEditingController(
      text: usesCredentials ? _target.username : '',
    );
    _passwordController = TextEditingController(
      text: usesCredentials ? _target.credential : '',
    );
    _labelController = TextEditingController(text: _target.label);
    _awayController = TextEditingController(text: _target.away?.url ?? '');

    _initialAccess = _target.access;
    _initialAwayAccess = _target.away?.access ?? const NoAccess();
    _signInWith = _initialSignInWith = _target.account == null
        ? SeerrSignInWith.apiKey
        : SeerrSignInWith.account;
    // A gateway's remedy is for the address the connection was reached at
    // when the gateway stopped it: away, its own Access row.
    final remedyAway =
        widget.initialAccess != null &&
        _target.away != null &&
        ref.read(connectionRouteProvider(_target.id)) == ConnectionRoute.away;
    _access = ConnectionAccessController(
      service,
      initial: widget.prefillAccess ?? _target.access,
      preselect: remedyAway ? null : widget.initialAccess,
    )..addListener(_onFieldChanged);
    _awayAccess = ConnectionAccessController(
      service,
      initial: _initialAwayAccess,
      preselect: remedyAway ? widget.initialAccess : null,
    )..addListener(_onFieldChanged);
    if (widget.focusAway) {
      // Opened by `Add an address away`: the fix is the empty field.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final field = _awayFieldKey.currentContext;
        if (field == null || !field.mounted) return;
        Scrollable.ensureVisible(field, alignment: 0.3);
        _awayFocus.requestFocus();
      });
    } else if (widget.initialAccess != null) {
      // Opened by a gateway's remedy: the fix is on the Access row.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = (remedyAway ? _awayAccessKey : _accessKey).currentContext;
        if (row != null && row.mounted) Scrollable.ensureVisible(row);
      });
    }

    _initialValues = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    // After the loaded values are taken, so a form opened on a proposed
    // address is unsaved, as one filled in by hand is.
    if (widget.prefillUrl case final url? when url.isNotEmpty) {
      _urlController.text = url;
    }
    for (final controller in _controllers.values) {
      controller.addListener(_onFieldChanged);
    }

    if ((widget.foundFrom, widget.foundName) case (final from?, final name?)) {
      // After the first frame: an answer already held arrives at once, and
      // filling the fields rebuilds the form.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _foundAsked = ref.listenManual(
          knownCandidatesProvider(from),
          (_, next) => _fillFound(next, name),
          fireImmediately: true,
        );
      });
    }
  }

  /// Fills the fields with what the connection that knows the server says,
  /// once: the address proposed for this device, the key when it gave one,
  /// and the name it uses beside the service. The fields stay the person's
  /// to change, and are unsaved until saved.
  void _fillFound(AsyncValue<List<ConnectionCandidate>> answer, String name) {
    if (answer is AsyncLoading) return;
    _foundAsked?.close();
    _foundAsked = null;
    final known = answer.asData?.value ?? const <ConnectionCandidate>[];
    final candidate = known
        .where((c) => c.service == service && c.displayName == name)
        .firstOrNull;
    if (candidate == null || !mounted) return;
    _urlController.text = candidate.proposal?.url ?? candidate.reportedUrl;
    if (candidate.apiKey case final key? when key.isNotEmpty) {
      _apiKeyController.text = key;
    }
    if (_labelController.text.trim().isEmpty) {
      _labelController.text = candidate.labelBesideService;
    }
    setState(() => _found = candidate);
  }

  Map<String, TextEditingController> get _controllers => {
    'url': _urlController,
    'apiKey': _apiKeyController,
    'username': _usernameController,
    'password': _passwordController,
    'label': _labelController,
    'away': _awayController,
  };

  /// Whether any field differs from what was loaded, the Access row's
  /// included: a choice whose fields are all empty is no access at all, so a
  /// form opened on Cloudflare Access by a remedy and left alone is not dirty.
  bool get _isDirty =>
      _access.access != _initialAccess ||
      _awayAccess.access != _initialAwayAccess ||
      _signInWith != _initialSignInWith ||
      _controllers.entries.any(
        (entry) => entry.value.text != _initialValues[entry.key],
      );

  /// Whether the form stands on an account rather than the key.
  bool get _signsInWithAccount =>
      service == ServiceKey.seerr && _signInWith == SeerrSignInWith.account;

  /// The connection as this form stands, for signing in: the address in its
  /// field, its access and its name, over what is saved.
  ServiceInstance _formConnection() {
    final live =
        ref.read(currentSettingsProvider).instanceById(_target.id) ?? _target;
    final away = _formAway;
    return live.copyWith(
      url: UrlUtils.normalizeBaseUrl(_urlController.text),
      access: _access.access,
      away: away,
      clearAway: away == null,
      label: _labelController.text.trim(),
    );
  }

  /// The address away as the form stands, with its access; null when its
  /// field is empty, which saves a connection reached only at home.
  ConnectionAddress? get _formAway {
    final url = UrlUtils.normalizeBaseUrl(_awayController.text);
    if (url.isEmpty) return null;
    return ConnectionAddress(url: url, access: _awayAccess.access);
  }

  /// Whether the field of the address away holds anything.
  bool get _hasAway => _awayController.text.trim().isNotEmpty;

  /// An account signed in from this form saved the address, the access and
  /// the name with it: they are no longer unsaved changes.
  void _adoptSignedIn() {
    _initialValues['url'] = _urlController.text;
    _initialValues['label'] = _labelController.text;
    _initialValues['apiKey'] = _apiKeyController.text;
    _initialValues['away'] = _awayController.text;
    _initialAccess = _access.access;
    _initialAwayAccess = _awayAccess.access;
    _initialSignInWith = SeerrSignInWith.account;
  }

  /// Takes on a name this connection was given somewhere other than here.
  ///
  /// There is exactly one writer: the *sibling's* form. Saving a second
  /// connection derives a name for the first one; see [_deriveSiblingLabels]
  /// and the first one's form is very often still on the stack underneath,
  /// holding the empty string it loaded when that connection was the only one
  /// there was. Coming back to it, [_needsLabel] is now true, so the field
  /// appears empty and its validator refuses to save a connection the user
  /// never touched and which *has* a name: one already on the badge, in the
  /// lens sheet and above its section in search.
  ///
  /// Only when the field holds exactly what it loaded. An adoption that
  /// overwrote a half-typed name would trade a stale field for a lost edit,
  /// which is the worse of the two.
  ///
  /// The listener is detached across the write so the assignment does not read
  /// as the user typing: that would clear a test result the values are still
  /// good for, and mark a form dirty that nobody has edited. Moving
  /// `_initialValues` along with it is the other half of the same point: the
  /// adopted name is the new baseline, not an unsaved change to warn about on
  /// the way out.
  void _adoptPersistedLabel(String persisted) {
    if (persisted == _labelController.text) return;
    if (_labelController.text != _initialValues['label']) return;

    _labelController.removeListener(_onFieldChanged);
    _labelController.text = persisted;
    _labelController.addListener(_onFieldChanged);
    _initialValues['label'] = persisted;
  }

  void _onFieldChanged() {
    // A test result describes the values that were tested; once they change it
    // is stale and claiming otherwise would be worse than showing nothing. The
    // header also switches to "unsaved changes" on the first edit, so the row
    // has to rebuild either way.
    setState(() {
      _testResult = null;
      _awayTestResult = null;
      _shareCandidates = const [];
    });
    // An address refused by the last save or test is asked again as it
    // changes, `Use https` included: its words leave once they are no longer
    // true, rather than at the next tap of Save.
    for (final field in [_urlFieldKey, _awayFieldKey]) {
      if (field.currentState?.hasError ?? false) field.currentState!.validate();
    }
  }

  @override
  void dispose() {
    _foundAsked?.close();
    for (final controller in _controllers.values) {
      controller.removeListener(_onFieldChanged);
    }
    _urlFocus.dispose();
    _awayFocus.dispose();
    _labelFocus.dispose();
    _usernameFocus.dispose();
    _credentialFocus.dispose();
    _passwordFocus.dispose();
    _urlController.dispose();
    _awayController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _labelController.dispose();
    for (final access in [_access, _awayAccess]) {
      access
        ..removeListener(_onFieldChanged)
        ..dispose();
    }
    super.dispose();
  }

  /// Verifies the values currently in the form without saving them.
  ///
  /// Onboarding has always had this; settings did not, so the only way to find
  /// out whether an edited URL or key worked was to save it and watch the
  /// service list go offline.
  Future<void> _testConnection() async {
    if (_testing || _saving) return;
    if (!_formKey.currentState!.validate()) {
      _revealFirstProblem();
      return;
    }
    _liftCredentialsFromAddress();

    // The answer to a test is rendered under the fields, and behind a reverse
    // proxy the wait for it can run to fifteen seconds, spending them behind
    // half a screen of keys is the one thing this screen can avoid. Dismissed
    // here rather than in each caller: the button, the return key and the
    // retest after trusting a certificate all come through this method.
    // After validation, so a rejected field keeps the caret where the fix is.
    FocusScope.of(context).unfocus();

    // The Access team this connection's last failure named, read before the
    // test replaces it: the offer to share a token that passes needs it.
    final team = _lastAccessTeam();
    setState(() {
      _testing = true;
      _testResult = null;
      _awayTestResult = null;
      _shareCandidates = const [];
    });
    try {
      final candidate = _updateServiceSettings(
        ref.read(currentSettingsProvider),
      );
      final candidateInstance = candidate.instanceById(_target.id) ?? _target;
      _testedAccess = candidateInstance.access;
      _testedAwayAccess = candidateInstance.away?.access ?? const NoAccess();
      // Both addresses at once, each as typed: the test is of the fields,
      // never of the address the connection's route happens to be on.
      // Through the local-network gate at home: a LAN address that fails
      // because the OS has not been allowed onto the network reports the
      // permission, and one the user allows while the alert is up is simply
      // tested again. The retest that used to be theirs to work out.
      final asked = await Future.wait([
        diagnoseThroughLocalNetworkGate(
          () => diagnoseInstance(
            candidateInstance,
            candidate,
            route: ConnectionRoute.home,
          ),
          url: candidateInstance.url,
          probe: widget.localNetworkProbe,
        ),
        if (candidateInstance.away != null)
          diagnoseInstance(
            candidateInstance,
            candidate,
            route: ConnectionRoute.away,
          ),
      ]);
      var result = asked.first;
      var away = asked.length > 1 ? asked[1] : null;

      // TLS exception flow, one address after the other: when a failure could
      // be explained by a certificate, offer to trust it and test that address
      // again. Every service can reach this since ADR-6.
      if (!mounted) return;
      result = await _trustAndRetest(result, ConnectionRoute.home) ?? result;
      if (away != null && mounted) {
        away = await _trustAndRetest(away, ConnectionRoute.away) ?? away;
      }

      // A token that passes on a connection that never failed here names no
      // team. When another connection was stopped by an Access team, this
      // address is asked once without the token: Access sends an
      // unauthenticated request to its team's sign-in, which names the team.
      var shareTeam = team;
      if (result.isConnected &&
          shareTeam == null &&
          _testedAccess is CloudflareServiceToken &&
          _anotherConnectionStoppedByAccess()) {
        final bare = await diagnoseInstance(
          candidateInstance.copyWith(access: const NoAccess()),
          candidate,
          route: ConnectionRoute.home,
        );
        shareTeam = accessTeamOf(bare.gateway);
      }

      if (!mounted) return;
      // A pass with the saved sign-in is the person asking at this
      // connection: its client sends the login once more on the next read.
      if (result.isConnected || (away?.isConnected ?? false)) {
        liftQbittorrentRefusalAfterPassingTest(ref, candidateInstance);
      }
      HapticFeedback.lightImpact();
      final shareable = result.isConnected
          ? _sameTeamConnections(shareTeam, _testedAccess)
          : const <ServiceInstance>[];
      setState(() {
        _testResult = result;
        _awayTestResult = away;
        _shareCandidates = shareable;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = ServiceDiagnosis.failed(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// When [result] failed in a way a certificate could explain, offers to
  /// trust the certificate of [route]'s address as typed, and tests that
  /// address again. Null when the probe found nothing; the plain http failure
  /// when the port serves http; [result] with the certificate attached when
  /// it was offered and not trusted, so the panel can offer it again
  /// ([_reviewCertificate]).
  ///
  /// Skipped once the server has answered (a rejected key rules the
  /// certificate out), and for an address away that did not answer at all:
  /// the probe would wait on the silent address a second time.
  Future<ServiceDiagnosis?> _trustAndRetest(
    ServiceDiagnosis result,
    ConnectionRoute route,
  ) async {
    if (!result.isDisconnected || !certProbeWorthwhile(result.reason)) {
      return null;
    }
    if (route == ConnectionRoute.away && _isSilent(result)) return null;
    final settings = _updateServiceSettings(ref.read(currentSettingsProvider));
    final (:url, :pin) = _typedAddress(settings, route);
    if (url.isEmpty) return null;
    final finding = await widget.certificateProber(
      url,
      pinnedFingerprint: pin ?? '',
    );
    if (finding == null || !mounted) return null;
    final found = result.withFinding(finding);
    if (found.certificateProbe == null) return found;
    return _offerTrust(found, route);
  }

  /// [route]'s address as the fields hold it, the one the test went to, and
  /// the certificate already trusted at its origin.
  ({String url, String? pin}) _typedAddress(
    SettingsModel settings,
    ConnectionRoute route,
  ) {
    final tested = settings.instanceById(_target.id) ?? _target;
    final url = route == ConnectionRoute.away
        ? tested.away?.url ?? ''
        : tested.url;
    return (url: url, pin: settings.pinForUrl(url));
  }

  /// Shows the certificate [result] carries and, once it is trusted, tests
  /// [route]'s address again. [result] itself when it is not trusted.
  Future<ServiceDiagnosis> _offerTrust(
    ServiceDiagnosis result,
    ConnectionRoute route,
  ) async {
    final probe = result.certificateProbe;
    if (probe == null) return result;
    final settings = _updateServiceSettings(ref.read(currentSettingsProvider));
    final tested = settings.instanceById(_target.id) ?? _target;
    final (:url, :pin) = _typedAddress(settings, route);
    final trust = await showCertTrustDialog(
      context,
      origin: UrlUtils.certOrigin(url) ?? url,
      probe: probe,
      previousFingerprint: pin,
      sharedWith: settings
          .servicesSharingOriginOf(url)
          .where((s) => s != service)
          .toList(),
    );
    if (!trust || !mounted) return result;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          ref
              .read(currentSettingsProvider)
              .copyWithTrustedCertificate(
                url: url,
                fingerprint: probe.certificate.fingerprint,
              ),
        );
    if (!mounted) return result;
    // The retest goes to the same connection and the same address the first
    // test did: `diagnoseService` folds every connection of the service, so
    // it could answer about a sibling never part of this trust decision.
    final retried = _updateServiceSettings(ref.read(currentSettingsProvider));
    return diagnoseInstance(
      retried.instanceById(_target.id) ?? tested,
      retried,
      route: route,
    );
  }

  /// `Check the certificate` under a panel whose certificate was offered and
  /// not trusted: the same question again, without testing first.
  Future<void> _reviewCertificate(ConnectionRoute route) async {
    final shown = route == ConnectionRoute.away ? _awayTestResult : _testResult;
    if (shown == null || shown.certificateProbe == null || _testing) return;
    setState(() => _testing = true);
    try {
      final next = await _offerTrust(shown, route);
      if (!mounted || identical(next, shown)) return;
      setState(() {
        if (route == ConnectionRoute.away) {
          _awayTestResult = next;
        } else {
          _testResult = next;
        }
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Whether [result] is an address that did not answer at all, which the
  /// form says differently when the other address answered (Q2: a router
  /// that cannot reach its own public address is common).
  static bool _isSilent(ServiceDiagnosis result) =>
      result.reason == ServiceFailureReason.unreachable ||
      result.reason == ServiceFailureReason.timeout;

  /// Takes each address's `user:password@` off it and puts it where it
  /// belongs: see [ConnectionAccessController.liftCredentialsFrom].
  void _liftCredentialsFromAddress() {
    _access.liftCredentialsFrom(
      _urlController,
      username: _usernameController,
      password: _passwordController,
    );
    _awayAccess.liftCredentialsFrom(
      _awayController,
      username: _usernameController,
      password: _passwordController,
    );
  }

  /// Confirms before dropping unsaved edits.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Discard changes?',
      message:
          'Your edits to the ${service.title} settings have not been saved.',
      confirmLabel: 'Discard changes',
      cancelLabel: 'Keep editing',
    );
    return result.confirmed;
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      _revealFirstProblem();
      return;
    }
    _liftCredentialsFromAddress();

    // Captured before the write: an edited address moves this service off an
    // origin whose certificate may have been pinned, at home or away, and
    // `_maybePromptCertTrust` below can only ever *add* a pin. Left behind,
    // the entry outlives the address: and because `pinForUrl` is keyed purely
    // by origin, any service later pointed back at it would silently reuse
    // the stale trust with no prompt.
    ServiceInstance? priorInstance;
    late SettingsModel updated;
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.update((current) {
      priorInstance = current.instanceById(_target.id);
      return updated = _updateServiceSettings(
        current,
      ).copyWithoutUnusedCertificatesOf(priorInstance);
    });
    final prior = priorInstance;
    if (!mounted) return;
    // Saving is the person's word that the credentials are worth trying
    // again, even unchanged (the password was fixed on the daemon, not here).
    // Transmission's client stops asking after a refusal, so as not to spend
    // the daemon's allowed failures, and only a new client asks again.
    if (service == ServiceKey.transmission) {
      ref.invalidate(transmissionClientProvider);
      ref.invalidate(transmissionClientForProvider);
    }

    // Offer to trust a self-signed certificate so the connection is
    // authenticated rather than blindly accepted. Only prompts when the
    // failure is specifically an untrusted certificate; a reachable server or
    // an unrelated failure just saves as before.
    //
    // And only when the save moved the connection: an address, the one away,
    // or what a gateway in front of either asks for. Anything else (a name, a
    // key, a viewer) leaves the certificate as it was, and used to wait out a
    // connection test first, two timeouts of it with the server down, before
    // closing on a label. "Test connection" runs that flow on demand.
    final saved = updated.instanceById(_target.id);
    final moved =
        prior == null || saved == null || saved.reachesDifferentlyFrom(prior);
    final pinned = moved
        ? await _maybePromptCertTrust(updated, notifier)
        : null;
    if (!mounted) return;
    if (pinned != null) updated = pinned;

    if (!mounted) return;
    Navigator.of(context).pop();
    SnackBarHelper.success(context, '${service.title} settings saved');
  }

  /// Returns the updated settings when the user trusts a certificate, else null.
  Future<SettingsModel?> _maybePromptCertTrust(
    SettingsModel updated,
    SettingsNotifier notifier,
  ) async {
    setState(() => _saving = true);
    try {
      // This connection, not the service: the origin whose certificate is about
      // to be probed, and offered for trust, has to be the one whose address
      // is in the field above.
      final target = updated.instanceById(_target.id);
      if (target == null) return null;
      final result = await diagnoseInstanceWithCertProbe(
        target,
        updated,
        probe: widget.certificateProber,
      );
      if (!mounted) return null;
      final probe = result.certificateProbe;
      if (probe == null) return null;

      final url = target.url;
      final trust = await showCertTrustDialog(
        context,
        origin: UrlUtils.certOrigin(url) ?? url,
        probe: probe,
        previousFingerprint: updated.pinForUrl(url),
        sharedWith: updated
            .servicesSharingOriginOf(url)
            .where((s) => s != service)
            .toList(),
      );
      if (!mounted || !trust) return null;

      // Pinned onto the settings as they are now: the probe and the dialog
      // took seconds, and what changed meanwhile (a Seerr session ending, a
      // second form) must not be written back as it was.
      await notifier.update(
        (current) => current.copyWithTrustedCertificate(
          url: url,
          fingerprint: probe.certificate.fingerprint,
        ),
      );
      final pinned = ref.read(currentSettingsProvider);
      return pinned;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SettingsModel _updateServiceSettings(SettingsModel current) {
    // Same normalisation onboarding applies, so a trailing slash or a scheme
    // typed in either screen ends up stored the one way the clients use.
    final url = UrlUtils.normalizeBaseUrl(_urlController.text);
    var next = _writeService(
      current,
      url: url,
      apiKey: _apiKeyController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      label: _labelController.text.trim(),
    );

    // The sibling that was alone until a moment ago has no name, and it is
    // about to need one: with two connections and one nameless, the badge and
    // every badge-bearing row would fall back to showing its id. Derived from
    // whatever actually tells the two apart: the port when they share a host,
    // the host when they do not, and editable in its own form afterwards.
    // Never the word "Default": that names a role, and the role moves.
    if (_labelController.text.trim().isNotEmpty) {
      next = _deriveSiblingLabels(next, url);
    }
    return next;
  }

  /// Writes this service's fields onto [current].
  ///
  /// Which of the two shapes to write is the registry's answer: one branch on
  /// the capability rather than a per-service chain. Routing a
  /// credential-authenticated service through the API-key path is what used to
  /// leave a saved username and password behind on a clear.
  SettingsModel _writeService(
    SettingsModel current, {
    required String url,
    required String apiKey,
    required String username,
    required String password,
    String? label,
  }) {
    // Re-read by id rather than reusing the copy captured at initState: the
    // chosen viewer, say, may have moved while this form was open and the
    // captured copy would put it back.
    final live = current.instanceById(_target.id) ?? _target;
    final away = _formAway;
    if (service == ServiceKey.seerr) {
      // A Seerr connection is the key or an account, never both. Choosing the
      // key forgets the account; choosing an account keeps whatever is saved
      // until an account signs in and takes the key's place.
      return current.copyWithInstance(
        _signsInWithAccount
            ? live.copyWith(
                url: url,
                label: label,
                access: _access.access,
                away: away,
                clearAway: away == null,
              )
            : live.copyWith(
                url: url,
                credential: apiKey,
                label: label,
                access: _access.access,
                away: away,
                clearAway: away == null,
                clearAccount: true,
              ),
      );
    }
    return current.copyWithInstance(
      live.copyWith(
        url: url,
        credential: usesCredentials ? password : apiKey,
        username: usesCredentials ? username : '',
        label: label,
        access: _access.access,
        away: away,
        clearAway: away == null,
      ),
    );
  }

  /// Brings the first field the last validation refused into view, focused,
  /// in the order the form draws them. A Test or a Save that stopped on a
  /// field off screen did nothing anyone could see: a second Radarr's empty
  /// Name sat above the fold while Test connection looked dead, and an
  /// address refused for `http://` sat above a Save that only dimmed.
  void _revealFirstProblem() {
    for (final (key, focus) in [
      (_labelFieldKey, _labelFocus),
      (_urlFieldKey, _urlFocus),
      (_awayFieldKey, _awayFocus),
      (_usernameFieldKey, _usernameFocus),
      (_credentialFieldKey, _credentialFocus),
      (_passwordFieldKey, _passwordFocus),
    ]) {
      final field = key.currentContext;
      if (!(key.currentState?.hasError ?? false)) continue;
      if (field == null || !field.mounted) continue;
      Scrollable.ensureVisible(
        field,
        alignment: 0.3,
        duration: AppAnimation.durationMd,
        curve: AppAnimation.standardCurve,
      );
      focus.requestFocus();
      return;
    }
  }

  /// Whether either address is refused for `http://` as it stands.
  bool get _refused =>
      cleartextRefusal(service, _urlController.text) != null ||
      cleartextRefusal(service, _awayController.text, optional: true) != null;

  Future<void> _removeConnection() async {
    final saved = ref.read(currentSettingsProvider).instanceById(_target.id);
    final what = saved?.away == null
        ? 'the saved address and credentials'
        : 'both saved addresses, their access and the credentials';
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.link_off_rounded,
      title: 'Remove ${service.title}?',
      message:
          'This deletes $what for ${service.title}. Nothing on the server '
          'itself is touched. This cannot be undone.',
      confirmLabel: 'Remove ${service.title}',
    );
    if (!result.confirmed || !mounted) return;

    final before = ref.read(currentSettingsProvider);
    final prior = before.instanceById(_target.id);
    final cleared = before
        // Drops the whole connection rather than blanking its fields, which
        // takes the chosen viewer with it. Clearing the viewer by service
        // would reach *every* instance of it, so removing one Jellyfin would
        // reset which person the other one reads through.
        .copyWithoutInstance(_target.id)
        // Forget its origins' pins too, at home and away, but only when
        // nothing else configured still reaches them: removing Sonarr must
        // never break Radarr's trust in the same reverse proxy, and with
        // instances that includes the service's own second connection behind
        // it.
        .copyWithoutUnusedCertificatesOf(prior);

    await ref.read(settingsProvider.notifier).updateSettings(cleared);

    // The lens outlives the connection it names unless something says
    // otherwise. Harmless while it is only ever *resolved*; `activeInstance`
    // falls back to the first instance when the id matches nothing, but the id
    // stays on disk for good, and the day a badge or a `?i=` NAMES it rather
    // than resolving it, the app is carrying a pointer to a server that was
    // deleted months ago.
    //
    // Only when it was this connection: clearing unconditionally would send a
    // lens deliberately parked on the second connection back to the first
    // because the user removed the third.
    if (ref.read(activeInstancesProvider)[service] == _target.id) {
      await ref.read(activeInstancesProvider.notifier).clear(service);
    }
    if (!mounted) return;

    Navigator.of(context).pop();
    SnackBarHelper.info(context, '${service.title} removed');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never blocks the iOS back gesture outright: `canPop` stays true unless
      // there is something to lose, and the guard only asks.
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !context.mounted) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // Written by the sibling's form while this one sat open; see
    // [_adoptPersistedLabel]. Listened for rather than read: this form is not
    // rebuilt by being returned to, so nothing else would notice.
    ref.listen(
      currentSettingsProvider.select(
        (s) => s.instanceById(_target.id)?.label ?? '',
      ),
      (_, persisted) => _adoptPersistedLabel(persisted),
    );

    final settings = ref.watch(currentSettingsProvider);
    // **This connection's** state, not the service's. `isServiceConfigured` is
    // true as soon as *any* instance is set up, which on the add-a-connection
    // form meant an empty page announcing "Answering" (the first connection's
    // status), offering a viewer picker bound to the first server, and showing
    // a Remove row for a connection that does not exist yet: its confirm
    // dialog removed nothing and simply popped the screen.
    final saved = settings.instanceById(_target.id);
    final isConfigured = saved?.isConfigured ?? false;
    // A Seerr account whose session ended keeps its connection: it can be
    // signed in again, or removed.
    final isSignedOut = saved?.isSignedOut ?? false;
    // A secret this device would not hand over keeps its connection too: it
    // is pasted again here, or the connection removed.
    final unreadSecret = saved?.unreadSecret;
    ref.listen(
      currentSettingsProvider.select(
        (s) => s.instanceById(_target.id)?.account?.session ?? '',
      ),
      (previous, next) {
        if (next.isNotEmpty && next != previous) setState(_adoptSignedIn);
      },
    );

    return AmbientScaffold(
      // The room takes the colour of the service being worked on.
      accent: service.accent,
      appBar: GlassAppBar.inPage(
        // The service's name alone. It read "Radarr Settings", which is the
        // name of a different page: *Service settings* is Radarr's own
        // configuration, read and written through Radarr's API, while this form
        // is how Cupola reaches it: address, key, certificate, connection
        // name. Two pages one word apart is how a user ends up on the wrong
        // one; the breadcrumb above already says Settings › Connections.
        pageTitle: service.title,
        actions: [_buildSaveAction()],
      ),
      body: Form(
        key: _formKey,
        // Every field built, never lazily: a Form validates only the fields
        // that exist, and a list builds only what is near the screen, so a
        // second Radarr's empty Name above the fold was skipped and saved.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(
                context,
                isConfigured: isConfigured,
                isSignedOut: isSignedOut,
                unreadSecret: unreadSecret,
              ),
              // Setup guidance is registry data, alongside the default port and
              // the credential breadcrumb this screen already reads from there.
              if (_found case final found?) ...[
                const SizedBox(height: AppSpacing.md),
                _buildInfoNote(context, _foundNote(found)),
              ],
              if (service.setupNote case final note?) ...[
                const SizedBox(height: AppSpacing.md),
                _buildInfoNote(context, note),
              ],
              const SizedBox(height: AppSpacing.xl),
              // Before the address on purpose: name the thing, then say where it
              // lives. By the time someone is here for a second connection they
              // are already thinking "these two are different"; that is the
              // moment the name costs nothing to give.
              if (_needsLabel(settings)) ...[
                _buildLabelField(settings),
                const SizedBox(height: AppSpacing.lg),
              ],
              _buildAddressField(away: false),
              _buildTrustedCertificateIndicator(settings, away: false),
              // Under the address, above who you are: a gateway answers before
              // the service does, so its token is part of reaching the address.
              // Below the credentials it sat under a Seerr account's Continue,
              // which signs in through that gateway and failed before the
              // token field was in view. One under each address: the gateway in
              // front of the address away is rarely the one at home.
              const SizedBox(height: AppSpacing.sm),
              _buildAccessRow(away: false),
              const SizedBox(height: AppSpacing.xl),
              // Away from home, a connection with no address away is reached
              // only on the home network: said here, above the field that
              // changes it, and nowhere as a fault.
              if (_onlyAtHomeNow(saved)) ...[
                _buildInfoNote(
                  context,
                  '${service.title} has no address away, so Cupola reaches it '
                  'only on your home Wi-Fi.',
                  icon: Icons.home_rounded,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _buildAddressField(away: true),
              _buildTrustedCertificateIndicator(settings, away: true),
              if (_hasAway) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildAccessRow(away: true),
              ],
              const SizedBox(height: AppSpacing.xl),
              if (service == ServiceKey.seerr) ...[
                _buildSignInWithChoice(),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_signsInWithAccount)
                SeerrAccountFields(
                  connection: _formConnection,
                  certificateProber: widget.certificateProber,
                  onUseApiKey: () =>
                      setState(() => _signInWith = SeerrSignInWith.apiKey),
                  onCheckAddress: _urlFocus.requestFocus,
                  onUseHttps: _useHttps,
                )
              else if (usesCredentials)
                _buildUsernameField()
              else
                _buildApiKeyField(),
              if (usesCredentials) ...[
                const SizedBox(height: AppSpacing.lg),
                _buildPasswordField(),
              ],
              const SizedBox(height: AppSpacing.xl),
              // An account not signed in yet has nothing to test: signing in
              // is its test.
              if (!_signsInWithAccount || (saved?.account?.isSignedIn ?? false))
                _buildTestConnectionRow(context),
              if (_testResult != null) ...[
                const SizedBox(height: AppSpacing.md),
                _buildTestResults(context, settings),
              ],
              if (_shareCandidates.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildShareOffer(context),
              ],
              // Directly under the connection test, because the ceiling is a
              // property of *this instance's path*: a stack can easily have Sonarr
              // behind a proxy and Radarr direct over Tailscale.
              if (SearchHeadroomCard.appliesTo(widget.service)) ...[
                const SizedBox(height: AppSpacing.lg),
                SearchHeadroomCard(service: widget.service),
              ],
              // A capability check, the same shape as `appliesTo` two lines up:
              // the picker belongs to any service whose library has to be entered
              // through a person, not to "Jellyfin" by name. Only once a
              // connection exists, because the viewer list comes from `/Users` on
              // the server. Offering it before there is a server to ask would be
              // a control that can only fail.
              // Bound to the connection this form edits. Read and written through
              // the service's flat projection, it listed the users of *this*
              // server and saved the chosen one onto the FIRST connection;
              // leaving that server pointed at a user id from a different user
              // table, which is the exact failure `ServiceInstance.viewerId`
              // exists to prevent.
              if (service.needsViewerSelection && isConfigured) ...[
                const SizedBox(height: AppSpacing.xxl),
                JellyfinViewerPicker(service: service, instanceId: _target.id),
              ],
              // Phones only: the app a Jellyfin or an Emby title plays in, or
              // asked each time.
              if (StreamPlayer.of(service).isNotEmpty && playsOnPhone()) ...[
                const SizedBox(height: AppSpacing.xxl),
                _buildPlayWithRow(),
              ],
              // How the operator adds a title nobody holds: Seerr's connection
              // only, and the operator's own (the requester adds nothing).
              if (service == ServiceKey.seerr &&
                  ref.watch(audienceProvider) == Audience.operator) ...[
                const SizedBox(height: AppSpacing.xxl),
                _buildAddingChoice(),
                // An invite is for the one who runs the Seerr, made from a
                // connection that signs in with the key: an account is a
                // household member's, with nothing to hand on.
                if (saved != null && isConfigured && saved.account == null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _buildInviteRow(saved.id),
                ],
              ],
              const SizedBox(height: AppSpacing.xxl),
              _buildConnectionsSection(context, settings),
              if (isConfigured || isSignedOut || unreadSecret != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _buildRemoveRow(context, twoAddresses: saved?.away != null),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The service, its host, and the state of the saved connection.
  ///
  /// Once the form is dirty the saved state no longer describes what is on
  /// screen, so it steps aside rather than contradicting the fields.
  Widget _buildHeader(
    BuildContext context, {
    required bool isConfigured,
    bool isSignedOut = false,
    UnreadSecret? unreadSecret,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The service's mark and its name, as its room names it, and under the
    // name what it is and how this connection stands.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: ServiceMarkTile(icon: service.icon),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: PageTitle.flush(
            service.title,
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${service.domain.label}\u00A0· ${service.apiVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_isDirty)
                  _HeaderStatus(
                    icon: Icons.edit_note_rounded,
                    label: 'Unsaved changes',
                    color: colorScheme.onSurfaceVariant,
                  )
                else if (isConfigured)
                  _SavedConnectionStatus(instanceId: _target.id)
                else if (unreadSecret != null)
                  // What happened on this device, amber: the field below is
                  // where it is pasted again.
                  _HeaderStatus(
                    icon: Icons.key_off_rounded,
                    label: unreadSecret == UnreadSecret.access
                        ? 'Saved access unreadable'
                        : failureLabel(
                            ServiceFailureReason.secretUnread,
                            credential: refusedCredentialOf(service),
                          ),
                    color: statusToneColor(
                      colorScheme,
                      StatusTone.warning,
                      surface: colorScheme.surfaceContainer,
                    ),
                  )
                else if (isSignedOut)
                  _HeaderStatus(
                    icon: Icons.logout_rounded,
                    label: StateWord.signedOut.label,
                    color: statusToneColor(
                      colorScheme,
                      StateWord.signedOut.tone!,
                      surface: colorScheme.surfaceContainer,
                    ),
                  )
                else
                  _HeaderStatus(
                    icon: Icons.add_link_rounded,
                    label: 'Not set up yet',
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // === Access ==============================================================

  /// The Cloudflare Access team this connection's last failure named, from
  /// the form's own last test or from Home's probe, or null.
  ///
  /// Read only where it was already asked (`ref.exists`): the form never
  /// probes on its own to find out.
  String? _lastAccessTeam() {
    final fromTest = accessTeamOf(_testResult?.gateway);
    if (fromTest != null) return fromTest;
    final key = (service: service, instanceId: _target.id);
    if (!ref.exists(instanceSummaryProvider(key))) return null;
    return accessTeamOf(
      ref.read(instanceSummaryProvider(key)).value?.failure?.gateway,
    );
  }

  /// The other connections whose last failure was the Access team [team],
  /// which a token that just passed its test may let through too.
  List<ServiceInstance> _sameTeamConnections(
    String? team,
    ConnectionAccess tested,
  ) {
    if (team == null || tested is! CloudflareServiceToken) return const [];
    final settings = ref.read(currentSettingsProvider);
    return [
      for (final other in settings.configuredInstances)
        if (other.id != _target.id && other.access != tested)
          if (_lastTeamOf(other) == team) other,
    ];
  }

  bool _anotherConnectionStoppedByAccess() => ref
      .read(currentSettingsProvider)
      .configuredInstances
      .any((other) => other.id != _target.id && _lastTeamOf(other) != null);

  String? _lastTeamOf(ServiceInstance instance) {
    final key = (service: instance.service, instanceId: instance.id);
    if (!ref.exists(instanceSummaryProvider(key))) return null;
    return accessTeamOf(
      ref.read(instanceSummaryProvider(key)).value?.failure?.gateway,
    );
  }

  List<String> _shareNames() {
    final settings = ref.read(currentSettingsProvider);
    return [
      for (final other in _shareCandidates)
        settings.connectionTitle(other.id, other.service, joiner: ' '),
    ];
  }

  /// The offer after a token passed its test: the same token for the
  /// connections the same Access team turned away.
  Widget _buildShareOffer(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            sharedTokenOffer(_shareNames()),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        TextButton(onPressed: _shareToken, child: const Text('Use it')),
      ],
    );
  }

  Future<void> _shareToken() async {
    final token = _testedAccess;
    if (token is! CloudflareServiceToken) return;
    final names = _shareNames();
    var settings = ref.read(currentSettingsProvider);
    for (final other in _shareCandidates) {
      final live = settings.instanceById(other.id);
      if (live == null) continue;
      settings = settings.copyWithInstance(live.copyWith(access: token));
    }
    await ref.read(settingsProvider.notifier).updateSettings(settings);
    if (!mounted) return;
    setState(() => _shareCandidates = const []);
    SnackBarHelper.success(context, sharedTokenSaved(names));
  }

  Widget _buildTestConnectionRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serviceTheme = ServiceTheme.fromAccent(service.accent);

    // Tonal rather than a saturated accent slab. Two reasons, and both hold for
    // all thirteen accents: a full-strength fill in Readarr's red or Unraid's
    // orange reads as an alarm on a control nothing is wrong with: red means
    // unreachable, amber a fault, and the accent cannot be its own
    // label colour over its own tint (Radarr amber measures ≈1.80:1 there in
    // light theme). The tint carries the identity, `onSurface` carries the
    // words.
    return FilledButton.icon(
      onPressed: _testing || _saving ? null : _testConnection,
      icon: _testing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onSurface,
              ),
            )
          : const Icon(Icons.wifi_tethering_rounded, size: 18),
      label: Text(_testing ? 'Testing…' : 'Test connection'),
      style: FilledButton.styleFrom(
        // Grows with the reading size instead of clipping its own label: a
        // 46pt button around a 20pt label has 26pt of chrome that must not
        // move when the label does.
        minimumSize: Size.fromHeight(
          TextScaleMetrics.boxHeight(context, base: 46, textHeight: 20),
        ),
        backgroundColor: serviceTheme.softContainer,
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: service.accent.withValues(alpha: 0.28)),
      ),
    );
  }

  /// The answers of the last test: one panel, as always, for a connection
  /// with one address; one for each address when it has two, said
  /// together when neither answered.
  Widget _buildTestResults(BuildContext context, SettingsModel settings) {
    final home = _testResult!;
    final away = _awayTestResult;
    if (away == null) return _buildTestResult(context, home);
    final homeSilent = _isSilent(home);
    final awaySilent = _isSilent(away);
    // Neither answered: no address is in use, whatever the route last said.
    if (homeSilent && awaySilent) return _buildBothSilent(context);
    // In use is what the test just saw, the way the route chooses: home when
    // it answers, away when only away does. The route itself moves on its
    // own clock, and an `in use` beside an address that did not answer here
    // contradicted the panel it stood in.
    final inUse = _routeInUse(settings) == null
        ? null
        : homeSilent
        ? ConnectionRoute.away
        : ConnectionRoute.home;
    Widget one(ServiceDiagnosis result, ConnectionRoute route, bool silent) =>
        // An address that did not answer while the other did is not a fault
        // of the fields: from here it could not be reached, which is what an
        // address away looks like from home, and the reverse.
        silent
        ? _buildNotChecked(context, route, inUse)
        : _buildTestResult(
            context,
            result,
            route: route,
            address: _addressLine(route, inUse),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        one(home, ConnectionRoute.home, homeSilent),
        const SizedBox(height: AppSpacing.sm),
        one(away, ConnectionRoute.away, awaySilent),
      ],
    );
  }

  /// The address the saved connection is reached at now, while the form
  /// still shows what is saved; null once an edit makes the fields another
  /// connection, or when there is only one address to be at. After a test,
  /// [_buildTestResults] says it from what the test saw.
  ConnectionRoute? _routeInUse(SettingsModel settings) {
    if (_isDirty || settings.instanceById(_target.id)?.away == null) {
      return null;
    }
    return ref.watch(connectionRouteProvider(_target.id));
  }

  /// `At home · nas.home.arpa:7878 · in use`: where an answer came from.
  String _addressLine(ConnectionRoute route, ConnectionRoute? inUse) {
    final raw = route == ConnectionRoute.away
        ? _awayController.text
        : _urlController.text;
    final host =
        service.extractHost(UrlUtils.normalizeBaseUrl(raw)) ?? raw.trim();
    final where = route == ConnectionRoute.away ? 'Away' : 'At home';
    return [where, host, if (route == inUse) 'in use'].join(dotSeparator);
  }

  /// Blue: [route]'s address did not answer from where this device is, and
  /// the other one did. Saved anyway (Q2): it is tried for real when it is
  /// the one the route needs.
  Widget _buildNotChecked(
    BuildContext context,
    ConnectionRoute route,
    ConnectionRoute? inUse,
  ) {
    final sentence = route == ConnectionRoute.away
        ? "Cupola tries it when the home address doesn't answer."
        : 'Cupola tries it first, and uses it whenever it answers.';
    return _ResultPanel(
      tone: StatusTone.info,
      icon: Icons.info_outline_rounded,
      title: 'Not checked from here',
      lines: [sentence],
      addresses: [_addressLine(route, inUse)],
    );
  }

  /// Red, naming both addresses: neither answered.
  Widget _buildBothSilent(BuildContext context) {
    final presentation = describeConnection(
      service,
      status: ServiceConnectionStatus.disconnected,
      reason: ServiceFailureReason.unreachable,
    );
    return _ResultPanel(
      tone: presentation.tone,
      icon: presentation.icon,
      title: presentation.label,
      outcome: 'Connection test failed.',
      lines: ['${service.title} did not answer at home or away.'],
      addresses: [
        _addressLine(ConnectionRoute.home, null),
        _addressLine(ConnectionRoute.away, null),
      ],
    );
  }

  /// One address's answer. [route] and [address] only when the form has two
  /// addresses: [route] picks the access the test sent there, [address]
  /// closes the panel with where the answer came from.
  Widget _buildTestResult(
    BuildContext context,
    ServiceDiagnosis result, {
    ConnectionRoute route = ConnectionRoute.home,
    String? address,
  }) {
    final presentation = describeConnection(
      service,
      status: result.status,
      reason: result.reason,
      gateway: result.gateway,
    );
    final tone = result.isConnected ? StatusTone.success : presentation.tone;
    final outcome = result.isConnected
        ? 'Connection test succeeded.'
        : 'Connection test failed.';
    final message = switch (result.status) {
      ServiceConnectionStatus.connected =>
        '${service.title} answered as expected.',
      ServiceConnectionStatus.notConfigured =>
        'Fill in the address and credentials first.',
      // `messageFor`, not `connectionFailureMessage`: a failure that already
      // reached its own verdict (a refused cross-origin redirect naming where
      // it was sent) says so verbatim, and everything else falls back to the
      // reason-derived sentence exactly as before.
      ServiceConnectionStatus.disconnected ||
      ServiceConnectionStatus.checking => _failureLine(result),
    };
    // A Cloudflare service token's test says what Access did with it.
    final tested = route == ConnectionRoute.away
        ? _testedAwayAccess
        : _testedAccess;
    final tokenOutcome = tested is CloudflareServiceToken
        ? cloudflareTokenTestOutcome(
            service,
            answered: result.isConnected,
            reason: result.reason,
            gateway: result.gateway,
          )
        : null;
    final said = tokenOutcome ?? message;

    // The version the server named, when it named one. A separate line rather
    // than more of [message] because it can carry its own tone: an answering
    // server on an unsupported release is a qualified pass, not a plain one.
    final versionNote = describeServerVersion(service, result.serverVersion);

    // Another service of the stack answered here: the headline says which
    // one, and the remedy below opens its form on this address.
    final other = result.isConnected ? null : result.answered;
    final banner = _ResultPanel(
      tone: tone,
      icon: result.isConnected
          ? Icons.check_circle_outline_rounded
          : presentation.icon,
      title: result.isConnected
          ? 'Answering'
          : other != null
          ? 'This is ${other.title}'
          : presentation.label,
      outcome: outcome,
      lines: [said],
      note: versionNote?.message,
      noteIsWarning: versionNote?.isWarning ?? false,
      addresses: [?address],
    );

    if (result.certificateProbe != null) {
      // Outside the banner for the reason the local network's button is:
      // the banner is one live region, and a button inside it is unreachable.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          banner,
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _testing ? null : () => _reviewCertificate(route),
              style: remedyFillStyle(context),
              child: Text(failureRemedy(ServiceFailureReason.tls)!),
            ),
          ),
        ],
      );
    }
    if (other != null) {
      // Outside the banner for the same reason as the controls around it:
      // the banner is one live region and hides its subtree from a screen
      // reader. Amber, the fill a fault's remedy wears, at the 44pt target
      // [remedyFillStyle] pins.
      final address =
          (route == ConnectionRoute.away
                  ? _awayController.text
                  : _urlController.text)
              .trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          banner,
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () => context.push(
                ServiceRoutes.addAt(other, address: address),
                extra: tested is NoAccess ? null : tested,
              ),
              style: remedyFillStyle(context),
              child: Text(Lexicon.setUp(other.title)),
            ),
          ),
        ],
      );
    }
    if (result.reason != ServiceFailureReason.localNetworkBlocked) {
      return banner;
    }
    // The one control that fixes this sits *outside* the banner, because the
    // banner excludes its own subtree from the semantics tree to read as a
    // single live region: a button in there would be unreachable to a screen
    // reader, which is precisely the user least able to go hunting through the
    // OS settings for a toggle nobody named.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        banner,
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _openLocalNetworkSettings,
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: const Text('Open Settings'),
          ),
        ),
      ],
    );
  }

  /// What the panel says under a failure: the failure's own sentence, or,
  /// once a certificate was offered and not trusted, what that certificate
  /// is. The failure's sentence asks to test again for a certificate Cupola
  /// will offer, and this one was offered already.
  String _failureLine(ServiceDiagnosis result) =>
      switch (result.certificateProbe) {
        null => result.messageFor(service),
        (rotated: true, certificate: _) =>
          '${service.title} sent a different certificate from the one you '
              'trusted. Check it before trusting it.',
        _ =>
          '${service.title} sent a certificate this device does not trust. '
              'If it is your own, check it and trust it.',
      };

  /// Takes the user to the toggle. When the host cannot get there, the route is
  /// spelled out instead of failing silently.
  Future<void> _openLocalNetworkSettings() async {
    final opened = await LocalNetworkPermission.openSettings();
    if (!opened && mounted) {
      SnackBarHelper.info(context, LocalNetworkPermission.remedy);
    }
  }

  /// A name for [instance], derived from what distinguishes it from [otherUrl],
  /// or null when only the port does.
  ///
  /// Null when they share a host and differ only by port: two arrs on one box,
  /// the overwhelmingly common homelab. The port is what tells them apart, but
  /// a port is not a name: the first Sonarr was called `30113`. The caller
  /// numbers it instead (`Sonarr 1`), beside the `Sonarr 2` a second one is
  /// usually given. Otherwise two shapes, in the order they tell the two apart:
  ///
  /// * the **first path segment**, when they share a host *and* a port:
  ///   `media.lan/radarr` beside `media.lan/radarr4k`, which is one reverse
  ///   proxy fronting both. This branch is not an edge case worth skipping: it
  ///   is the deployment ADR-6 exists to serve, those two instances necessarily
  ///   share a single certificate pin, and it is precisely where the user has
  ///   the least other signal to tell them apart. Without it both were labelled
  ///   `media`: what they have in **common**;
  /// * the **hostname**, when they are on different boxes.
  ///
  /// Falls back to the id only when nothing parses, which is better than empty.
  /// Never the word "Default": that names a role, and the role moves the first
  /// time the list is reordered.
  ///
  /// Uniqueness is the caller's job; see [_deriveSiblingLabels]. This answers
  /// "what is different about it", which can legitimately come out the same for
  /// two connections that really are near-identical.
  String? _derivedLabel(ServiceInstance instance, String otherUrl) {
    final mine = Uri.tryParse(instance.url);
    final other = Uri.tryParse(otherUrl);
    if (mine == null || mine.host.isEmpty) return instance.id;

    final sameHost = other != null && other.host == mine.host;
    if (sameHost) {
      if (mine.port != other.port) return null;
      final segment = mine.pathSegments
          .where((part) => part.isNotEmpty)
          .firstOrNull;
      if (segment != null) return segment;
    }
    return mine.host.split('.').first;
  }

  /// Names every sibling that has no name yet, and makes sure no two of them
  /// come out the same.
  ///
  /// The uniqueness pass is the half that was missing, and its absence was
  /// invisible from the field validator: that compares the typed name against
  /// the siblings *as they stand in the model*, where the one being derived
  /// still has an empty label. So a derivation that collided with what the user
  /// had just typed, or with another derivation, was written anyway, and two
  /// connections ended up sharing a name in the badge, the lens sheet and every
  /// provenance chip, with nothing on screen able to tell them apart.
  ///
  /// A colliding name is suffixed with what is left to distinguish it: the
  /// port, or failing that a counter. Ugly beats ambiguous, and it is editable
  /// in the sibling's own form the moment the user disagrees. A numbered name
  /// takes the next number free instead.
  SettingsModel _deriveSiblingLabels(SettingsModel next, String url) {
    final taken = <String>{
      for (final instance in _siblings(next))
        if (instance.label.isNotEmpty) instance.label.toLowerCase(),
      _labelController.text.trim().toLowerCase(),
    };

    var updated = next;
    for (final sibling in _siblings(next)) {
      if (sibling.label.isNotEmpty) continue;
      final derived = _derivedLabel(sibling, url);
      if (derived == null) {
        var number = next.instancesOf(service).indexOf(sibling) + 1;
        while (taken.contains('${service.title} $number'.toLowerCase())) {
          number++;
        }
        final numbered = '${service.title} $number';
        taken.add(numbered.toLowerCase());
        updated = updated.copyWithInstance(sibling.copyWith(label: numbered));
        continue;
      }
      final base = derived;
      var candidate = base;
      if (taken.contains(candidate.toLowerCase())) {
        final port = Uri.tryParse(sibling.url)?.port;
        candidate = port == null || port == 0 ? base : '$base:$port';
      }
      var counter = 2;
      while (taken.contains(candidate.toLowerCase())) {
        candidate = '$base $counter';
        counter++;
      }
      taken.add(candidate.toLowerCase());
      updated = updated.copyWithInstance(sibling.copyWith(label: candidate));
    }
    return updated;
  }

  /// The connections of this service other than the one on screen.
  List<ServiceInstance> _siblings(SettingsModel settings) => settings
      .instancesOf(service)
      .where((instance) => instance.id != _target.id)
      .toList(growable: false);

  /// Whether this form needs to ask for a name.
  ///
  /// Exactly when there is something to tell it apart from. One connection
  /// needs no name: it is "Radarr", and asking for one would be a field that
  /// earns nothing on the install almost everyone has.
  bool _needsLabel(SettingsModel settings) => _siblings(settings).isNotEmpty;

  Widget _buildLabelField(SettingsModel settings) {
    return TextFormField(
      key: _labelFieldKey,
      focusNode: _labelFocus,
      controller: _labelController,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Name',
        hintText: '4K, HD, Anime…',
        helperText:
            'Short. This is what tells it apart in search, in the queue, and '
            'before every add.',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.sell_outlined),
      ),
      validator: (value) {
        final name = (value ?? '').trim();
        if (name.isEmpty) return 'Give this one a name';
        final clash = _siblings(
          settings,
        ).any((other) => other.label.toLowerCase() == name.toLowerCase());
        // Two rows both called "4K" is the state this whole field exists to
        // prevent, so it is refused rather than allowed and disambiguated by
        // host somewhere downstream.
        if (clash) return 'Another ${service.title} already uses that name';
        return null;
      },
    );
  }

  /// The other connections of this service, and the way to add one.
  Widget _buildConnectionsSection(
    BuildContext context,
    SettingsModel settings,
  ) {
    final siblings = _siblings(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader.flush(
          title: 'Connections',
          showChevron: false,
          subtitle: siblings.isEmpty
              ? 'One ${service.title}. Add another if you run a second.'
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(
          children: [
            for (final sibling in siblings)
              SettingsCard.grouped(
                leading: Icon(service.icon),
                // The app's one rule for naming a connection, never its id.
                // A sibling that is the only other one set up has nothing to
                // be told apart from yet, and goes by its own label or the
                // service.
                title:
                    settings.connectionName(sibling.id) ??
                    (sibling.label.trim().isEmpty
                        ? service.title
                        : sibling.label.trim()),
                subtitle: _siblingLine(settings, sibling),
                accentColor: service.accent,
                semanticHint: 'edits that ${service.title} connection',
                onTap: () => context.push(
                  '/settings/service/${service.routeParam}?i=${sibling.id}',
                ),
              ),
            SettingsCard.grouped(
              leading: const Icon(Icons.add_rounded),
              title: 'Add another ${service.title}',
              subtitle: 'A second server, with its own address and key',
              accentColor: service.accent,
              semanticHint: 'adds a second ${service.title} connection',
              onTap: () =>
                  context.push('/settings/service/${service.routeParam}?new=1'),
            ),
          ],
        ),
      ],
    );
  }

  /// A sibling's line two: its setup and the address in use
  /// (`Home and away · radarr.example.net`), the setup said once any
  /// connection has an address away, the same rule as Connections.
  String _siblingLine(SettingsModel settings, ServiceInstance sibling) {
    final inUse = service.extractHost(
      ref.watch(connectionReachProvider(sibling.id))?.url ?? sibling.url,
    );
    if (inUse == null) return 'No address yet';
    if (!settings.instances.any((i) => i.away != null)) return inUse;
    final setup = sibling.away != null ? Lexicon.homeAndAway : Lexicon.homeOnly;
    return '$setup\u00A0· $inUse';
  }

  Widget _buildRemoveRow(BuildContext context, {required bool twoAddresses}) {
    return SettingsGroupCard(
      children: [
        // The row's default accent, like every other settings row: red means
        // unreachable and nothing else, and the confirmation says what goes.
        SettingsCard.grouped(
          leading: const Icon(Icons.link_off_rounded),
          title: 'Remove ${service.title}',
          subtitle: twoAddresses
              ? 'Deletes both addresses and credentials'
              : 'Deletes the saved address and credentials',
          onTap: _removeConnection,
        ),
      ],
    );
  }

  Widget _buildSaveAction() {
    if (_saving) {
      // Labelled, because the button is replaced rather than disabled: an
      // unlabelled spinner drops the control out of the tree entirely, so the
      // action appears to have vanished mid-save.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Semantics(
          label: 'Saving',
          excludeSemantics: true,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Dimmed, never disabled, while an address is refused: the tap brings
    // the refused field into view with its words, which a disabled Save
    // would leave the person to find.
    return TextButton.icon(
      onPressed: _saveSettings,
      style: _refused
          ? TextButton.styleFrom(
              foregroundColor: CupolaThemeColors.of(context).dimText,
            )
          : null,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Save'),
    );
  }

  /// A neutral, icon-led information banner used for per-service setup hints.
  /// What the form was filled in from, and what is left to do.
  String _foundNote(ConnectionCandidate found) {
    final source = found.source.service.title;
    return found.hasKey
        ? '$source knows this ${service.title}: its address and key are filled '
              'in. Test it, then save.'
        : '$source knows this ${service.title}: its address is filled in. '
              'Paste its key, test it, then save.';
  }

  /// Whether the app is away from home and this saved connection, with no
  /// address away, is reached only at home: `Only at home`, whose fix is the
  /// address away. True until one is saved, so the note does not fold away
  /// at the first letter typed and pull the field out from under the caret.
  bool _onlyAtHomeNow(ServiceInstance? saved) =>
      saved != null &&
      saved.isConfigured &&
      saved.away == null &&
      ref.watch(awayFromHomeProvider);

  Widget _buildInfoNote(
    BuildContext context,
    String message, {
    IconData icon = Icons.info_outline_rounded,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One of the connection's two addresses: [away] false is the address at
  /// home, the one the connection is saved by; true the optional one away
  /// from home, tried when the one at home does not answer.
  Widget _buildAddressField({required bool away}) {
    final controller = away ? _awayController : _urlController;
    final label = away ? 'Address away\u00A0· optional' : 'Address at home';
    // Rebuilds on every keystroke so the refusal and the warning track the
    // field.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // `http://` across the internet first: refused, on every platform.
        // Then the service's own reason (TrueNAS refuses http:// outright).
        final refusal = cleartextRefusal(service, value.text, optional: away);
        final warning = refusal ?? transportWarningFor(service, value.text);
        final help = away
            ? "Used when the home address doesn't answer. Leave it empty to "
                  'reach ${service.title} only at home.'
            // The default port comes from the registry, so this screen and
            // onboarding cannot disagree about it.
            : "Used on your home Wi-Fi. ${service.title}'s default port is "
                  '${service.defaultPort}.';
        final field = Semantics(
          label: label,
          hint: away
              ? 'Enter the ${service.title} address you reach from outside'
              : 'Enter the ${service.title} address on your home network',
          child: TextFormField(
            key: away ? _awayFieldKey : _urlFieldKey,
            controller: controller,
            focusNode: away ? _awayFocus : _urlFocus,
            decoration: InputDecoration(
              labelText: label,
              hintText: away
                  ? 'https://${service.routeParam}.example.com'
                  : 'https://your-server:${service.defaultPort}',
              // A live problem outranks the hint in the helper slot, in the
              // fault tone the field's refusal is drawn in after a save.
              helperText: warning ?? help,
              helperMaxLines: 5,
              errorMaxLines: 5,
              helperStyle: warning == null
                  ? null
                  : Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusToneColor(
                        Theme.of(context).colorScheme,
                        StatusTone.warning,
                      ),
                    ),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            // iOS otherwise rewrites `--` and quotes inside a typed address.
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            // Same rule as onboarding: a bare host is accepted here too and
            // normalised to HTTPS on save. Two rules for one field meant an
            // address typed during setup was rejected when reopened here.
            // An address that carries `user:password@` is accepted here and
            // cleaned on test or save: see [_liftCredentialsFromAddress].
            validator: (value) => _addressProblem(value ?? '', away: away),
          ),
        );
        if (refusal == null) return field;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field,
            const SizedBox(height: AppSpacing.sm),
            // The one remedy, in the one amber fill: the same address over
            // https, which the next test checks.
            FilledButton(
              onPressed: () => _useHttpsIn(controller),
              style: remedyFillStyle(context, compact: true),
              child: const Text('Use https'),
            ),
          ],
        );
      },
    );
  }

  /// What is wrong with [raw] as the address at home or ([away]) away, or
  /// null when it can be tested and saved.
  String? _addressProblem(String raw, {required bool away}) {
    if (raw.trim().isEmpty) return away ? null : 'Add the address at home';
    final malformed = UrlUtils.validateServiceHost(raw, allowCredentials: true);
    if (malformed != null) return malformed;
    if (cleartextRefusal(service, raw, optional: away) case final refused?) {
      return refused;
    }
    if (away &&
        isSameAddress(
          UrlUtils.normalizeBaseUrl(UrlUtils.withoutCredentials(raw)),
          UrlUtils.normalizeBaseUrl(
            UrlUtils.withoutCredentials(_urlController.text),
          ),
        )) {
      return 'This is the address at home. Use the one you reach from '
          'outside, or leave this empty.';
    }
    return null;
  }

  /// The Access row of one address: folded while it has nothing to send, as
  /// most addresses at home have.
  Widget _buildAccessRow({required bool away}) {
    final access = away ? _awayAccess : _access;
    return KeyedSubtree(
      key: away ? _awayAccessKey : _accessKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConnectionAccessFields(
            controller: access,
            foldWhenNone: true,
            changeLabel: away ? 'Change access away' : 'Change access at home',
            onMoveToCredential: (value) {
              if (value.isNotEmpty) _apiKeyController.text = value;
            },
          ),
          if (jellyfinKeyTravelsInQuery(service, access.access))
            const _JellyfinQueryKeyWarning(),
        ],
      ),
    );
  }

  /// A standing confirmation that this address's origin has a trusted
  /// self-signed certificate, with a way to revoke it: the address at home's,
  /// or ([away]) the one away's. Each address is trusted on its own, because
  /// a certificate belongs to its host, so each has its line under it.
  ///
  /// Rebuilds on every keystroke of the address field. [settings] is captured
  /// from the enclosing build, but the origin a trust decision applies to
  /// depends on what is actually typed, which the saved value may no longer
  /// match. Renders nothing for the overwhelming majority of services, which
  /// reach a certificate the OS already trusts and have never pinned one.
  Widget _buildTrustedCertificateIndicator(
    SettingsModel settings, {
    required bool away,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: away ? _awayController : _urlController,
      builder: (context, value, _) {
        final rawUrl = value.text;
        final pin = settings.pinForUrl(rawUrl);
        if (pin == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final origin = displayOrigin(UrlUtils.certOrigin(rawUrl) ?? rawUrl);
        final sharedWith = settings
            .servicesSharingOriginOf(rawUrl)
            .where((s) => s != service)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  sharedWith.isEmpty
                      ? 'Trusted self-signed certificate for $origin.'
                      : 'Trusted self-signed certificate for $origin, also '
                            'covers ${sharedWith.map((s) => s.title).join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _forgetCertificate(rawUrl),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: const Text('Forget'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Revokes the trusted certificate for [rawUrl]'s origin, after naming
  /// every other configured service the revocation also affects.
  Future<void> _forgetCertificate(String rawUrl) async {
    final settings = ref.read(currentSettingsProvider);
    final sharedWith = settings
        .servicesSharingOriginOf(rawUrl)
        .where((s) => s != service)
        .toList();

    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.gpp_bad_outlined,
      title: 'Forget this certificate?',
      message: sharedWith.isEmpty
          ? 'The next connection to this address will need to be trusted '
                'again.'
          : 'This also affects ${sharedWith.map((s) => s.title).join(', ')}: '
                'the next connection from any of them will need to be '
                'trusted again.',
      // Reversible: the next connection re-offers the trust prompt, so no
      // "cannot be undone" sentence: it would overstate the stakes.
      confirmLabel: 'Forget certificate',
    );
    if (!result.confirmed || !mounted) return;

    // From the settings as they are now, not as they were before the person
    // read the dialog.
    await ref
        .read(settingsProvider.notifier)
        .update(
          (current) =>
              current.copyWithTrustedCertificate(url: rawUrl, fingerprint: ''),
        );
    if (!mounted) return;
    SnackBarHelper.info(context, 'Certificate forgotten');
  }

  /// Where a Jellyfin title plays on a phone: the app the viewer chose, or
  /// `Ask every time`. Chosen in a sheet, saved on this device.
  Widget _buildPlayWithRow() {
    final chosen = ref.watch(streamPlayerChoiceOf(service));
    return SettingsCard.grouped(
      leading: const Icon(Icons.play_circle_outline_rounded),
      title: 'Play with',
      subtitle: chosen?.label ?? 'Ask every time',
      semanticHint: 'chooses the app a ${service.title} title plays in',
      onTap: () => chooseStreamPlayer(context, ref, service: service),
    );
  }

  /// Hands a household member the way into this Seerr: a QR and a link, in a
  /// sheet.
  Widget _buildInviteRow(String connectionId) {
    return SettingsGroupCard(
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.qr_code_2_rounded),
          title: 'Invite someone',
          subtitle: 'A QR or a link for their own account',
          semanticHint: 'shows an invite to this Seerr',
          onTap: () => showInviteSheet(context, connectionId: connectionId),
        ),
      ],
    );
  }

  /// The operator's choice of how a title nobody holds is added: through
  /// Seerr, which keeps the request, or straight to Radarr or Sonarr. One
  /// choice per device.
  Widget _buildAddingChoice() {
    final choice = ref.watch(operatorAddsViaProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Adding a title'),
        const SizedBox(height: AppSpacing.sm),
        SelectionPills<OperatorAddsVia>.wrap(
          values: OperatorAddsVia.values,
          selected: choice,
          labelBuilder: (value) => value.label,
          onSelected: (value) =>
              ref.read(operatorAddsViaProvider.notifier).set(value),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          switch (choice) {
            OperatorAddsVia.seerr =>
              'Requests go to Seerr, which approves them or waits for you, '
                  'then hands them to Radarr or Sonarr.',
            OperatorAddsVia.arr =>
              'Titles go straight to Radarr or Sonarr, with no request in '
                  'Seerr.',
          },
          style: theme.textTheme.bodySmall?.copyWith(
            color: CupolaThemeColors.of(context).dimText,
          ),
        ),
      ],
    );
  }

  /// Seerr's choice between the instance's API key and an account of one's
  /// own.
  Widget _buildSignInWithChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Sign in with'),
        const SizedBox(height: AppSpacing.sm),
        SelectionPills<SeerrSignInWith>.wrap(
          values: SeerrSignInWith.values,
          selected: _signInWith,
          labelBuilder: (choice) => choice.label,
          onSelected: (choice) => setState(() {
            _signInWith = choice;
            _testResult = null;
          }),
        ),
      ],
    );
  }

  /// The same address over https, for an `http://` one off the local
  /// network: a password is about to go.
  void _useHttps() => _useHttpsIn(_urlController);

  void _useHttpsIn(TextEditingController address) {
    address.text = address.text.trim().replaceFirst(
      RegExp('^http://', caseSensitive: false),
      'https://',
    );
  }

  Widget _buildApiKeyField() {
    final credentialPath = service.credentialPath;
    return Semantics(
      label: service.credentialLabel,
      hint: isPlex ? 'Enter a Plex device token' : 'Enter the API key',
      child: TextFormField(
        key: _credentialFieldKey,
        focusNode: _credentialFocus,
        controller: _apiKeyController,
        decoration: InputDecoration(
          labelText: service.credentialLabel,
          hintText: isPlex ? 'X-Plex-Token' : 'Enter your API key',
          // Where the credential lives inside the service's own interface. Same
          // registry fact onboarding shows under the same field, so someone who
          // set this up once recognises the breadcrumb when they come back to fix
          // it.
          // With an address away, the key it is asked for there is the same:
          // one server behind two doors.
          helperText: credentialPath == null && !_hasAway
              ? null
              : [
                  if (credentialPath != null)
                    '${service.title} → $credentialPath',
                  if (_hasAway)
                    'The same ${refusedCredentialOf(service)} at both '
                        'addresses.',
                ].join('\n'),
          helperMaxLines: 3,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reveal is offered alongside copy: checking a pasted key by eye
              // should not require putting it on the system clipboard, where any
              // other app can read it.
              IconButton(
                icon: Icon(
                  _revealApiKey
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                ),
                onPressed: () => setState(() => _revealApiKey = !_revealApiKey),
                tooltip: _revealApiKey
                    ? 'Hide ${service.credentialLabel}'
                    : 'Show ${service.credentialLabel}',
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: _copyApiKey,
                tooltip: 'Copy ${service.credentialLabel}',
              ),
            ],
          ),
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        // The last field ends the form by *checking* it, not by committing it:
        // saving an address that was never tried is how a wrong key ends up
        // persisted, and the test is one step short of the save anyway.
        onFieldSubmitted: (_) => _testConnection(),
        obscureText: !_revealApiKey,
        validator: _validateApiKey,
      ),
    );
  }

  Widget _buildUsernameField() {
    return Semantics(
      label: service.usernameLabel,
      hint: service == ServiceKey.nginxProxyManager
          ? 'Enter the email you sign in with'
          : 'Optional',
      child: TextFormField(
        key: _usernameFieldKey,
        focusNode: _usernameFocus,
        controller: _usernameController,
        decoration: InputDecoration(
          labelText: service.usernameLabel,
          // Optional for the download clients, which commonly run without auth
          // behind a reverse proxy. Nginx Proxy Manager is the exception: there
          // is no anonymous mode, and its login needs an email address.
          hintText: service == ServiceKey.nginxProxyManager
              ? 'The email you sign in with'
              : 'Optional',
        ),
        keyboardType: service == ServiceKey.nginxProxyManager
            ? TextInputType.emailAddress
            : TextInputType.text,
        textInputAction: TextInputAction.next,
        autocorrect: false,
      ),
    );
  }

  Widget _buildPasswordField() {
    return Semantics(
      label: 'Password',
      hint: 'Optional',
      child: TextFormField(
        key: _passwordFieldKey,
        focusNode: _passwordFocus,
        controller: _passwordController,
        decoration: const InputDecoration(
          labelText: 'Password',
          hintText: 'Optional',
        ),
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.done,
        // Same as the API-key field: the return key tests, it does not save.
        onFieldSubmitted: (_) => _testConnection(),
        obscureText: true,
      ),
    );
  }

  String? _validateApiKey(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return isPlex ? 'Plex token is required' : 'API Key is required';
    }

    // A Plex JSON Web Token expires after seven days and can only be renewed by
    // calling plex.tv, which this app never does. Accepting one would produce
    // software that works for a week and then fails with a 401 the user has no
    // way to interpret, so it is refused at the point of paste, where the
    // message can still say what to paste instead.
    if (isPlex && trimmed.startsWith('eyJ')) {
      return 'That is a temporary token, it expires in 7 days and Cupola '
          'cannot renew it. Paste a device token instead.';
    }

    return null;
  }

  /// How long a copied credential is left on the clipboard.
  ///
  /// Long enough to switch apps and paste, short enough that it is not still
  /// sitting there an hour later. Password managers land in the same range.
  static const Duration _copiedCredentialLifetime = Duration(seconds: 45);

  Future<void> _copyApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    // Two layers, in order of how much they actually protect. The host's own
    // sensitive-clip flags come first; they are the only thing that keeps the
    // key out of Android's copy preview and off Universal Clipboard, and a
    // plain copy is the fallback for every platform and OS version that has no
    // such flag, because a copy button that refuses to copy is worse than an
    // unhardened one. Either way the timed clear below still runs.
    final hardened = await SecureClipboard.copySecret(
      apiKey,
      expiresIn: _copiedCredentialLifetime,
    );
    if (!hardened) {
      await Clipboard.setData(ClipboardData(text: apiKey));
    }
    if (!mounted) return;
    // The wording is part of the mitigation, not chrome: the clipboard is a
    // shared surface: Android 13+ renders a preview of what was copied, and on
    // Apple platforms the general pasteboard syncs to the user's other devices
    // through Universal Clipboard, so the honest thing is to say the key left
    // the app and when it will be taken back.
    SnackBarHelper.info(
      context,
      '${service.credentialLabel} copied, the clipboard is cleared in '
      '${_copiedCredentialLifetime.inSeconds} seconds',
    );
    unawaited(_expireCopiedCredential(apiKey));
  }

  /// Takes [secret] back off the clipboard once it has had time to be pasted.
  ///
  /// Runs whether or not [SecureClipboard] hardened the copy, and it is the only
  /// half of this that runs at all on Android 12 and below, where there is no
  /// `EXTRA_IS_SENSITIVE` to set. Of the flagged platforms only iOS can expire a
  /// clip by itself, so this stays the thing that bounds how long the key sits
  /// there everywhere else.
  ///
  /// Static, and deliberately not tied to this widget's lifetime: leaving the
  /// screen is not a reason to leave a credential on the clipboard.
  ///
  /// The read-back only *spares* a clipboard it can actually see holding
  /// something else: the user copying over the key in the meantime, which is
  /// worth not destroying. An unreadable clipboard is cleared, not spared:
  /// since Android 10 `getPrimaryClip` answers null to any app that does not
  /// have window focus, and 45 seconds after the copy the user is by
  /// construction in the app they left to paste into. Treating that null as
  /// "something else is on the clipboard" is what used to make this never fire
  /// on Android in exactly the case it exists for, under a SnackBar promising
  /// it would.
  static Future<void> _expireCopiedCredential(String secret) async {
    await Future<void>.delayed(_copiedCredentialLifetime);
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current != null && current.text != secret) return;
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// One answer of a connection test, under the button: the tone's 10% wash,
/// a glyph and a title in the tone, the sentences in the page's quiet voice,
/// and, when the form has two addresses, where the answer came from.
///
/// A live region rather than an announcement: the panel appears below the
/// button while focus stays on it, so the verdict (the whole point of the
/// action) would otherwise have to be hunted for. `liveRegion` is the
/// mechanism both platforms honour; a programmatic announcement is dropped on
/// Android. The outcome is spelled out because the glyph and the tint are the
/// only things carrying it (the "Fill in the address" message, for one, never
/// says it failed).
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.tone,
    required this.icon,
    required this.title,
    required this.lines,
    this.outcome,
    this.note,
    this.noteIsWarning = false,
    this.addresses = const [],
  });

  final StatusTone tone;
  final IconData icon;
  final String title;
  final List<String> lines;

  /// What a screen reader hears first; the title, when null.
  final String? outcome;

  /// The server's version, amber when [noteIsWarning].
  final String? note;
  final bool noteIsWarning;

  /// Where the answer came from (`At home · nas.home.arpa:7878`), one line
  /// each, when the form has two addresses.
  final List<String> addresses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The wash keeps the tone's byte; the glyph and the verdict are walked
    // against that 10% wash over the page, which is what they land on.
    final fill = statusToneFill(colorScheme, tone);
    final color = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surface,
      tintAlpha: 0.10,
    );
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: [
        outcome ?? '$title.',
        ...lines,
        // Read out with the verdict rather than after it: a caveat the eye
        // catches from its amber has nothing carrying it to a screen reader.
        ?note,
        ...addresses,
      ].join(' '),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: fill.withValues(alpha: 0.10),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: fill.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                  for (final line in lines) ...[
                    const SizedBox(height: 2),
                    Text(line, style: quiet),
                  ],
                  if (note case final note?) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: noteIsWarning
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: statusToneColor(
                                colorScheme,
                                StatusTone.warning,
                                surface: colorScheme.surface,
                                tintAlpha: 0.10,
                              ),
                            )
                          : quiet,
                    ),
                  ],
                  if (addresses.isNotEmpty) const SizedBox(height: 2),
                  for (final address in addresses)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        address,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: CupolaThemeColors.of(context).dimText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The saved connection's state, watched live so trusting a certificate or
/// saving a new key updates the header without a reload.
///
/// Keyed on the **connection**, not the service. `serviceDiagnosisProvider`
/// folds every connection into its worst answer: the right shape for a row
/// that says "Radarr", and the wrong one over a form whose address field
/// belongs to exactly one server: it reported the first Radarr's state above
/// the second Radarr's credentials.
class _SavedConnectionStatus extends ConsumerWidget {
  const _SavedConnectionStatus({required this.instanceId});

  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = ref
        .watch(
          currentSettingsProvider.select((s) => s.instanceById(instanceId)),
        )
        ?.service;
    if (service == null) return const SizedBox.shrink();

    final async = ref.watch(instanceDiagnosisProvider(instanceId));
    final diagnosis = async.when(
      loading: () => const ServiceDiagnosis.checking(),
      error: (_, _) =>
          const ServiceDiagnosis(ServiceConnectionStatus.disconnected),
      data: (value) => value,
    );
    final presentation = describeConnection(
      service,
      status: diagnosis.status,
      reason: diagnosis.reason,
      gateway: diagnosis.gateway,
    );

    // "Answering · read-only key": a credential that reads and may not write
    // is a fact about this connection worth stating where it is replaced.
    // Asked only once the connection answers, and only of the services whose
    // one credential can be narrower than their writes
    // ([ServiceKeyExtension.hasScopedCredential]: Unraid, TrueNAS, Nginx Proxy
    // Manager and Plex).
    final qualifier =
        diagnosis.status == ServiceConnectionStatus.connected &&
            service.hasScopedCredential
        ? credentialScopeQualifier(
            service,
            ref.watch(capabilityGrantForProvider(instanceId)),
          )
        : null;

    return _HeaderStatus(
      icon: presentation.icon,
      label: qualifier == null
          ? presentation.label
          : '${presentation.label}\u00A0· $qualifier',
      color: statusToneColor(colorScheme, presentation.tone),
      busy: diagnosis.status == ServiceConnectionStatus.checking,
    );
  }
}

class _HeaderStatus extends StatelessWidget {
  const _HeaderStatus({
    required this.icon,
    required this.label,
    required this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The cost of letting a proxy own `Authorization` on a Jellyfin connection.
///
/// Jellyfin's own sign-in uses that header; when the Access row already sends
/// one, the client has no header left and puts the API key in the query string.
/// That works, and every proxy access log records it, so the form says so where
/// the choice is made rather than after the fact.
class _JellyfinQueryKeyWarning extends StatelessWidget {
  const _JellyfinQueryKeyWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.info_outline_rounded, size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'This proxy signs in with Authorization, so Jellyfin sends its '
              'API key in the request address (ApiKey=). Use a proxy credential '
              'on a header of its own, such as CF-Access-Client-Id and '
              'CF-Access-Client-Secret, to keep the key out of proxy logs.',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
