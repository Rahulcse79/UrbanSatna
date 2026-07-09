import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'profile_screen.dart';

const _states = <String, List<String>>{
  'Madhya Pradesh': ['Satna', 'Rewa', 'Jabalpur', 'Bhopal', 'Indore', 'Gwalior', 'Katni', 'Sagar'],
  'Uttar Pradesh': ['Lucknow', 'Kanpur', 'Varanasi', 'Prayagraj', 'Agra', 'Noida', 'Ghaziabad'],
  'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Nashik', 'Thane'],
  'Delhi': ['New Delhi', 'Dwarka', 'Rohini'],
  'Rajasthan': ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota'],
  'Bihar': ['Patna', 'Gaya', 'Muzaffarpur'],
  'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot'],
  'Karnataka': ['Bengaluru', 'Mysuru', 'Mangaluru'],
  'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai'],
  'West Bengal': ['Kolkata', 'Howrah', 'Durgapur'],
  'Telangana': ['Hyderabad', 'Warangal'],
  'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada'],
  'Punjab': ['Ludhiana', 'Amritsar', 'Chandigarh'],
  'Haryana': ['Gurugram', 'Faridabad', 'Panipat'],
  'Chhattisgarh': ['Raipur', 'Bhilai', 'Bilaspur'],
  'Jharkhand': ['Ranchi', 'Jamshedpur', 'Dhanbad'],
  'Odisha': ['Bhubaneswar', 'Cuttack'],
  'Kerala': ['Kochi', 'Thiruvananthapuram', 'Kozhikode'],
  'Assam': ['Guwahati', 'Silchar'],
  'Uttarakhand': ['Dehradun', 'Haridwar'],
  'Himachal Pradesh': ['Shimla', 'Dharamshala'],
  'Goa': ['Panaji', 'Margao'],
};
const _otherCity = 'Other';

/// Mandatory first-login gate: profile fields + location permission +
/// T&C acceptance. MainShell shows this until the profile is complete.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _manualCity = TextEditingController();
  final _pincode = TextEditingController();
  String? _state;
  String? _city;
  bool _locationGranted = false;
  bool _termsAccepted = false;
  bool _busy = false;

  Future<void> _requestLocation() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (!granted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationFailed)));
    }
    setState(() => _locationGranted = granted);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final city = _city == _otherCity ? _manualCity.text.trim() : _city;
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _state == null ||
        city == null ||
        city.isEmpty ||
        _pincode.text.trim().length != 6) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.fillAllFields)));
      return;
    }
    if (!_locationGranted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.locationRequired)));
      return;
    }
    if (!_termsAccepted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.acceptTermsFirst)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).patch<Map<String, dynamic>>(
        '/api/v1/me',
        data: {
          'full_name': _name.text.trim(),
          'address': _address.text.trim(),
          'state': _state,
          'city': city,
          'pincode': _pincode.text.trim(),
          'accept_terms': true,
        },
      );
      ref.invalidate(meProvider); // gate re-evaluates and opens the app
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
    final config = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    final cities = _state == null
        ? const <String>[]
        : [..._states[_state] ?? const [], _otherCity];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.completeProfileTitle),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).logout(),
            child: Text(l10n.logout),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.completeProfileHint,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.nameLabel,
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: l10n.addressLabel,
                prefixIcon: const Icon(Icons.home_outlined),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use — see login_screen.dart
              value: _state,
              isExpanded: true,
              items: [
                for (final s in _states.keys)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() {
                _state = v;
                _city = null;
              }),
              decoration: InputDecoration(
                labelText: l10n.stateLabel,
                prefixIcon: const Icon(Icons.map_outlined),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            // Keyed by state: switching state must rebuild this field,
            // otherwise the old city (absent from the new item list)
            // trips Flutter's dropdown assertion.
            DropdownButtonFormField<String>(
              key: ValueKey(_state),
              // ignore: deprecated_member_use — see login_screen.dart
              value: _city,
              isExpanded: true,
              items: [
                for (final c in cities)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: _state == null
                  ? null
                  : (v) => setState(() => _city = v),
              decoration: InputDecoration(
                labelText: l10n.cityFieldLabel,
                prefixIcon: const Icon(Icons.location_city_outlined),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            if (_city == _otherCity) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _manualCity,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.cityManualLabel,
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _pincode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: l10n.pincodeLabel,
                counterText: '',
                prefixIcon: const Icon(Icons.pin_drop_outlined),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: Icon(
                _locationGranted ? Icons.check_circle : Icons.my_location,
                color: _locationGranted ? Colors.green : null,
              ),
              label: Text(_locationGranted
                  ? l10n.locationAttached
                  : l10n.allowLocation),
              onPressed: _requestLocation,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _termsAccepted,
              onChanged: (v) =>
                  setState(() => _termsAccepted = v ?? false),
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.agreeToTerms,
                      style: Theme.of(context).textTheme.bodySmall),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => launchUrl(
                        Uri.parse(config?.termsUrl ??
                            'https://urbansatna.onrender.com/terms'),
                        mode: LaunchMode.externalApplication),
                    child: Text(l10n.termsLink),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => launchUrl(
                        Uri.parse(config?.privacyUrl ??
                            'https://urbansatna.onrender.com/privacy'),
                        mode: LaunchMode.externalApplication),
                    child: Text(l10n.privacyLink),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.continueLabel),
            ),
          ],
        ),
      ),
    );
  }
}
