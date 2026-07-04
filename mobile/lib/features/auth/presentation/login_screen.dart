import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/server_url.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController(text: '+91');
  final _otp = TextEditingController();
  bool _otpSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  bool get _phoneValid {
    final p = _phone.text.trim();
    return p.startsWith('+') &&
        p.length >= 11 &&
        p.substring(1).split('').every((c) => '0123456789'.contains(c));
  }

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!_phoneValid) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.phoneInvalid)));
      return;
    }
    setState(() => _busy = true);
    try {
      final devOtp = await ref
          .read(authControllerProvider.notifier)
          .requestOtp(_phone.text.trim());
      if (devOtp != null) _otp.text = devOtp; // dev backend returns the OTP
      setState(() => _otpSent = true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_otp.text.trim().length != 6) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.otpInvalid)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyOtp(_phone.text.trim(), _otp.text.trim());
      // Router redirect takes over once tokens are set.
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(
              l10n.loginTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phone,
              enabled: !_otpSent,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.phoneLabel,
                hintText: '+919876543210',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: l10n.otpLabel,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _busy ? null : (_otpSent ? _verify : _sendOtp),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_otpSent ? l10n.verifyLogin : l10n.sendOtp),
            ),
            if (_otpSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _otpSent = false;
                          _otp.clear();
                        }),
                child: Text(l10n.changePhone),
              ),
            const Spacer(),
            const _ServerUrlFooter(),
          ],
        ),
      ),
    );
  }
}

/// Shows which server the app talks to; editable only when the
/// admin-controlled flag allows it (default: allowed).
class _ServerUrlFooter extends ConsumerWidget {
  const _ServerUrlFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = ref.watch(serverUrlProvider);
    final allowChange = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c.allowServerUrlChange, orElse: () => true);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            '${l10n.serverLabelShort}: $url',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (allowChange)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit, size: 16),
            tooltip: l10n.settingsTitle,
            onPressed: () => context.push('/settings'),
          ),
      ],
    );
  }
}
