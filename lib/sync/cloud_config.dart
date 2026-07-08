import 'package:flutter/foundation.dart';

import '../data/database.dart';

/// Whether the user has accepted the privacy & data policy (device-local).
/// Gates all app entry; kept in sync with `sync_meta` by [savePrivacyAgreed] /
/// [loadPrivacyAgreed].
final privacyAgreed = ValueNotifier<bool>(false);

// Device-local keys in sync_meta (never synced/backed-up).
const _kUrl = 'supabase_url';
const _kKey = 'supabase_anon_key';
const _kPrivacyAgreed = 'privacy_agreed';

/// The Supabase URL + anon key the user saved on this device (empty if unset).
Future<(String url, String anonKey)> readCloudConfig(AppDatabase db) async {
  final rows = await (db.select(db.syncMeta)
        ..where((t) => t.key.isIn([_kUrl, _kKey])))
      .get();
  final map = {for (final r in rows) r.key: r.value};
  return (map[_kUrl] ?? '', map[_kKey] ?? '');
}

/// Persists the Supabase URL + anon key locally (takes effect on next launch).
Future<void> saveCloudConfig(AppDatabase db,
    {required String url, required String anonKey}) async {
  await db.into(db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: _kUrl, value: url.trim()));
  await db.into(db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: _kKey, value: anonKey.trim()));
}

/// Whether the user has accepted the in-app privacy & data policy on this device.
Future<bool> readPrivacyAgreed(AppDatabase db) async {
  final row = await (db.select(db.syncMeta)
        ..where((t) => t.key.equals(_kPrivacyAgreed)))
      .getSingleOrNull();
  return row?.value == '1';
}

/// Loads the stored agreement into [privacyAgreed] (call once at startup).
Future<void> loadPrivacyAgreed(AppDatabase db) async {
  privacyAgreed.value = await readPrivacyAgreed(db);
}

/// Records acceptance (or withdrawal) of the privacy & data policy locally.
Future<void> savePrivacyAgreed(AppDatabase db, bool agreed) async {
  privacyAgreed.value = agreed;
  await db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(
      key: _kPrivacyAgreed, value: agreed ? '1' : ''));
}
