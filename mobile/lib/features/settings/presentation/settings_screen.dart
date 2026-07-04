import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/server_url.dart';
import '../../../l10n/gen/app_localizations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final text = value?.trim() ?? '';
    final uri = Uri.tryParse(text);
    final valid = uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
    return valid ? null : AppLocalizations.of(context).serverUrlInvalid;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final message = AppLocalizations.of(context).serverUrlSaved;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(serverUrlProvider.notifier).set(_controller.text);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reset() async {
    await ref.read(serverUrlProvider.notifier).reset();
    _controller.text = ref.read(serverUrlProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Admin-controlled: when false the URL is visible but locked.
    final allowChange = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c.allowServerUrlChange, orElse: () => true);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                enabled: allowChange,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.serverUrlLabel,
                  helperText: allowChange
                      ? l10n.serverUrlHelp
                      : l10n.serverManagedByAdmin,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  suffixIcon:
                      allowChange ? null : const Icon(Icons.lock_outline),
                ),
                validator: _validateUrl,
                onFieldSubmitted: allowChange ? (_) => _save() : null,
              ),
              const SizedBox(height: 16),
              if (allowChange) ...[
                FilledButton(onPressed: _save, child: Text(l10n.save)),
                const SizedBox(height: 8),
                TextButton(onPressed: _reset, child: Text(l10n.resetToDefault)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
