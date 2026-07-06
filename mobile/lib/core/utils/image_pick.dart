import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/gen/app_localizations.dart';

const _maxImageBytes = 1000000; // product rule: PNG/JPG under 1 MB

/// Gallery picker enforcing the product rule (PNG/JPG, ≤ 1 MB).
/// Shows a snackbar and returns null when the pick is invalid.
Future<({Uint8List bytes, String mime})?> pickValidatedImage(
    BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final picked = await ImagePicker()
      .pickImage(source: ImageSource.gallery, imageQuality: 85);
  if (picked == null) return null;
  final name = picked.name.toLowerCase();
  final isPng = name.endsWith('.png');
  final isJpg = name.endsWith('.jpg') || name.endsWith('.jpeg');
  final bytes = await picked.readAsBytes();
  if ((!isPng && !isJpg) || bytes.length > _maxImageBytes) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.avatarInvalid)));
    return null;
  }
  return (bytes: bytes, mime: isPng ? 'image/png' : 'image/jpeg');
}
