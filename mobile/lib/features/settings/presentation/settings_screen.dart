import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.serverUrlLabel,
                  helperText: l10n.serverUrlHelp,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                validator: _validateUrl,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: Text(l10n.save)),
              const SizedBox(height: 8),
              TextButton(onPressed: _reset, child: Text(l10n.resetToDefault)),
            ],
          ),
        ),
      ),
    );
  }
}
