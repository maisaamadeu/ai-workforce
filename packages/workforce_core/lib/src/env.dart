import 'dart:io';

import 'contracts.dart';

const allowedEnvKeys = {
  'PATH',
  'HOME',
  'USER',
  'LOGNAME',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'TMPDIR',
  'TMP',
  'TEMP',
  'SYSTEMROOT',
  'WINDIR',
  'PATHEXT',
  'COMSPEC',
  'USERPROFILE',
  'APPDATA',
  'LOCALAPPDATA',
  'HOMEDRIVE',
  'HOMEPATH',
  'SHELL',
  'TERM',
};

const _detectedByProvider = {
  ProviderId.claudeCode: ['ANTHROPIC_API_KEY'],
  ProviderId.codex: ['OPENAI_API_KEY'],
  ProviderId.cursor: ['CURSOR_API_KEY'],
  ProviderId.copilot: [
    'COPILOT_PROVIDER_API_KEY',
    'COPILOT_PROVIDER_BASE_URL',
    'COPILOT_PROVIDER_TYPE',
  ],
};

Map<String, String> sanitizeEnv(
  Map<String, String> source, {
  required bool allowMetered,
}) {
  final next = <String, String>{};
  for (final entry in source.entries) {
    if (allowedEnvKeys.contains(entry.key)) next[entry.key] = entry.value;
  }
  if (allowMetered) {
    for (final key in blockedMeteredEnv) {
      final value = source[key];
      if (value != null && value.isNotEmpty) next[key] = value;
    }
  }
  return next;
}

Map<String, String> sanitizeProcessEnv({required bool allowMetered}) {
  return sanitizeEnv(Platform.environment, allowMetered: allowMetered);
}

Map<ProviderId, bool> detectMeteredEnv(Map<String, String> source) {
  return {
    for (final provider in ProviderId.values)
      provider: _detectedByProvider[provider]!.any((key) {
        final value = source[key];
        return value != null && value.isNotEmpty;
      }),
  };
}
