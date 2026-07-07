import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/server_url.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../l10n/gen/app_localizations.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String _countryCode = '+91';
  bool _otpSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _fullPhone => '$_countryCode${_phone.text.trim()}';

  bool get _phoneValid {
    final p = _phone.text.trim();
    // 10 digits for +91; other admin-enabled countries vary (8-12).
    final expected = _countryCode == '+91' ? (10, 10) : (8, 12);
    return p.length >= expected.$1 &&
        p.length <= expected.$2 &&
        p.split('').every((c) => '0123456789'.contains(c));
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
          .requestOtp(_fullPhone);
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
          .verifyOtp(_fullPhone, _otp.text.trim());
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
    final scheme = Theme.of(context).colorScheme;
    // Country list is remote-config data: launch with +91 only, expand
    // from the admin panel with zero app changes.
    final codes = ref.watch(appConfigProvider).maybeWhen(
        data: (c) => c.countryCodes, orElse: () => const ['+91']);
    if (!codes.contains(_countryCode) && codes.isNotEmpty) {
      _countryCode = codes.first;
    }
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(child: BrandLogo(size: 72)),
              const SizedBox(height: 16),
              Text(
                l10n.loginTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.loginSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: DropdownButtonFormField<String>(
                      initialValue: _countryCode,
                      items: [
                        for (final code in codes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: _otpSent
                          ? null
                          : (v) =>
                              setState(() => _countryCode = v ?? '+91'),
                      decoration: const InputDecoration(
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      enabled: !_otpSent,
                      keyboardType: TextInputType.phone,
                      maxLength: 12,
                      decoration: InputDecoration(
                        labelText: l10n.phoneLabel,
                        hintText: '9876543210',
                        counterText: '',
                        prefixIcon: const Icon(Icons.phone_android),
                        filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: l10n.otpLabel,
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
              const SizedBox(height: 40),
              const _ServerUrlFooter(),
            ],
          ),
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

    // Admin kill switch: hide the server URL from the UI entirely.
    if (!allowChange) return const SizedBox.shrink();

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
