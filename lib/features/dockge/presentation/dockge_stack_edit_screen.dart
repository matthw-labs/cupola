import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _defaultCompose = '''services:
  app:
    image: nginx:latest
    restart: unless-stopped
    ports:
      - "8080:80"
''';

/// Compose editor for creating a new stack or editing an existing one.
class DockgeStackEditScreen extends ConsumerStatefulWidget {
  const DockgeStackEditScreen({super.key, this.name});

  /// The stack to edit. `null` creates a new stack.
  final String? name;

  bool get isNew => name == null;

  @override
  ConsumerState<DockgeStackEditScreen> createState() =>
      _DockgeStackEditScreenState();
}

class _DockgeStackEditScreenState extends ConsumerState<DockgeStackEditScreen> {
  final _nameCtrl = TextEditingController();
  final _yamlCtrl = TextEditingController();
  final _envCtrl = TextEditingController();
  bool _prefilled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _yamlCtrl.text = _defaultCompose;
      _prefilled = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yamlCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  /// Allowed stack-name shape, matching Dockge's own frontend validation:
  /// lowercase alphanumerics plus `_`/`-`, and must start with an alphanumeric.
  static final RegExp _namePattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  String get _effectiveName =>
      widget.isNew ? _nameCtrl.text.trim() : widget.name!;

  /// Whether the editor holds the stack's real contents.
  ///
  /// Always true when adding: the editor starts from the default template. When
  /// editing it stays false until the existing compose files have loaded, and
  /// that gate is the difference between saving a stack and erasing one.
  bool get _hasContent => widget.isNew || _prefilled;

  Future<void> _submit({required bool deploy}) async {
    final name = _effectiveName;
    if (name.isEmpty) {
      SnackBarHelper.error(context, 'Stack name is required');
      return;
    }
    if (widget.isNew && !_namePattern.hasMatch(name)) {
      SnackBarHelper.error(
        context,
        'Stack name may only contain lowercase letters, numbers, '
        'dashes and underscores, and must start with a letter or number',
      );
      return;
    }
    // Both guards below exist because neither `deployStack` nor `saveStack`
    // validates the YAML: whatever is in the field is written over the stack's
    // compose.yaml, and `deploy` then runs `up -d` against the result. An
    // editor that never loaded, or one the user emptied, would silently destroy
    // a working stack. The buttons are disabled in the first case; this is the
    // guard that actually has to hold.
    if (!_hasContent) {
      SnackBarHelper.error(context, 'Still loading the current compose file');
      return;
    }
    if (!widget.isNew && _yamlCtrl.text.trim().isEmpty) {
      SnackBarHelper.error(
        context,
        'compose.yaml is empty, that would wipe the stack',
      );
      return;
    }
    setState(() => _busy = true);
    final yaml = _yamlCtrl.text;
    final env = _envCtrl.text;
    final ok = await runDockgeAction(
      context,
      ref,
      action: (client) => deploy
          ? client.deployStack(
              name: name,
              composeYAML: yaml,
              composeENV: env,
              isAdd: widget.isNew,
            )
          : client.saveStack(
              name: name,
              composeYAML: yaml,
              composeENV: env,
              isAdd: widget.isNew,
            ),
      successMessage: deploy ? 'Deployed $name' : 'Saved $name',
      failureMessage: deploy ? 'Deploy failed' : 'Save failed',
      invalidate: [
        dockgeStackListProvider,
        dockgeStackDetailProvider(name),
        serviceKpiProvider(ServiceKey.dockge),
      ],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Checked **before** the detail provider is read, and it decides whether
    // it is read at all: this editor is reachable by deep link, the pre-tab
    // `/dashboard/dockge/stack/:name/edit` and `/dashboard/dockge/new` both
    // still rewrite onto it, so it can be the first Dockge thing the app
    // builds on an install that was never set up, and `dockgeClientProvider`
    // throws there. A provider that throws is a failed provider scheduling a
    // retry with backoff for a condition no waiting changes.
    final isConfigured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.dockge);

    // Prefill from the existing stack once.
    final detailAsync = widget.isNew || !isConfigured
        ? null
        : ref.watch(dockgeStackDetailProvider(widget.name!));
    if (detailAsync != null && !_prefilled) {
      detailAsync.whenDataKept((detail) {
        _yamlCtrl.text = detail.composeYAML;
        _envCtrl.text = detail.composeENV;
        _prefilled = true;
      });
    }

    return AmbientScaffold(
      accent: ServiceKey.dockge.accent,
      appBar: GlassAppBar.inPage(pageTitle: _title),
      body: SafeArea(
        // An empty editor is indistinguishable from a stack with no services,
        // and Save/Deploy would write it back as the truth. Until the real
        // compose file is in hand, show the load state instead of the editor.
        child: !isConfigured
            // Nothing to edit and nowhere to save it: an editor here would
            // take a compose file the user typed and fail on the write.
            ? TitledBody(
                title: _title,
                child: const NotConfiguredPlaceholder(serviceName: 'Dockge'),
              )
            : (detailAsync != null && !_prefilled)
            ? _loadState(detailAsync)
            : _editor(context),
      ),
    );
  }

  /// The page's name: a new stack, or the one being edited.
  String get _title => widget.isNew ? 'New stack' : 'Edit ${widget.name}';

  Widget _loadState(AsyncValue<DockgeStackDetail> detail) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        PageTitle.flush(_title),
        if (detail.hasError)
          AppErrorState(
            error: detail.error!,
            service: ServiceKey.dockge,
            onRetry: () =>
                ref.invalidate(dockgeStackDetailProvider(widget.name!)),
          )
        else
          AppSkeleton.detailBody(),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final canSubmit = !_busy && _hasContent;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        PageTitle.flush(_title),
        if (widget.isNew) ...[
          _Label('Stack name'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            decoration: _inputDecoration(context, 'my-stack'),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 16),
        ],
        _Label('compose.yaml'),
        const SizedBox(height: 6),
        _CodeField(controller: _yamlCtrl, minLines: 14),
        const SizedBox(height: 16),
        _Label('.env (optional)'),
        const SizedBox(height: 6),
        _CodeField(controller: _envCtrl, minLines: 4),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canSubmit ? () => _submit(deploy: false) : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canSubmit ? () => _submit(deploy: true) : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('Deploy'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusMd,
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge!.weight(FontWeight.w600),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.minLines});

  final TextEditingController controller;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: null,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.multiline,
      // The YAML editor lives or dies on columns lining up, so it goes through
      // `.mono` (a real family with fallbacks) rather than the 'monospace'
      // alias, which resolves to nothing on iOS/macOS. `bodySmall` already
      // carries the generous 1.40 leading that makes indented compose files
      // scannable.
      //
      // The colour is pinned to the dark-theme foreground because the panel
      // below it is pinned dark in *both* themes. Left theme-derived, this field
      // resolved to light-theme `onSurface` (#111827) on a #0A0B11 fill:
      // **1.11:1**, i.e. a compose editor whose contents were invisible in light
      // mode. Against the same fill the dark tone measures 17.55:1.
      style: Theme.of(context).textTheme.bodySmall!.mono.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
