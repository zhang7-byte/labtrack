import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../sync/cloud_config.dart';
import '../../sync/supabase_config.dart';
import '../../sync/sync_controller.dart';
import '../app_database_provider.dart';
import '../home_shell.dart';
import 'sync_scope.dart';

/// Login gate. The app requires a signed-in cloud account: first-time users can
/// enter their lab's cloud connection (URL + anon key) right here and sign in
/// without restarting; once configured + signed in, the app itself is shown.
/// [onConfigSaved] re-initialises Supabase after the connection is entered.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.onConfigSaved,
    required this.offline,
    required this.onContinueOffline,
  });

  final Future<void> Function() onConfigSaved;

  /// Whether the user chose to use the app local-only for this session.
  final bool offline;
  final VoidCallback onContinueOffline;

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: privacyAgreed,
      builder: (context, agreed, _) {
        // The app can only be entered once the privacy & data policy has been
        // accepted — this blocks both online (signed-in) and offline use, even
        // for a returning user whose sign-in session was restored.
        if (agreed && (offline || (sync.isConfigured && sync.isSignedIn))) {
          return const HomeShell();
        }
        return _AuthScreen(
          sync: sync,
          onConfigSaved: onConfigSaved,
          onContinueOffline: onContinueOffline,
        );
      },
    );
  }
}

class _AuthScreen extends StatefulWidget {
  const _AuthScreen({
    required this.sync,
    required this.onConfigSaved,
    required this.onContinueOffline,
  });

  final SyncController sync;
  final Future<void> Function() onConfigSaved;
  final VoidCallback onContinueOffline;

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final TapGestureRecognizer _policyTap =
      TapGestureRecognizer()..onTap = _showPolicy;
  bool _busy = false;
  bool _obscureKey = true;
  bool _loaded = false;
  bool _showConfig = false;
  bool _agreed = privacyAgreed.value;
  String? _error;
  String? _info;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final db = AppDatabaseProvider.of(context);
    readCloudConfig(db).then((cfg) {
      if (!mounted) return;
      setState(() {
        _url.text = cfg.$1;
        _key.text = cfg.$2;
        _showConfig = !SupabaseConfig.isConfigured;
      });
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _email.dispose();
    _password.dispose();
    _policyTap.dispose();
    super.dispose();
  }

  void _setAgreed(bool v) {
    setState(() => _agreed = v);
    savePrivacyAgreed(AppDatabaseProvider.of(context), v);
  }

  void _showPolicy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy & Data Policy'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(_policyText,
                style: const TextStyle(fontSize: 13, height: 1.45)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Checkbox + tappable "privacy and data policy" link. Gates all app entry.
  Widget _agreementRow(ColorScheme scheme) {
    return Row(
      children: [
        Checkbox(
          value: _agreed,
          onChanged: _busy ? null : (v) => _setAgreed(v ?? false),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
              children: [
                const TextSpan(text: 'I agree with the '),
                TextSpan(
                  text: 'privacy and data policy',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: _policyTap,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final url = _url.text.trim();
    final key = _key.text.trim();
    if (!url.startsWith('http') || key.isEmpty) {
      setState(() =>
          _error = 'Enter your Supabase URL (https://…) and anon key.');
      return;
    }
    await _run(() async {
      final db = AppDatabaseProvider.of(context);
      await saveCloudConfig(db, url: url, anonKey: key);
      await widget.onConfigSaved();
      if (mounted && !SupabaseConfig.isConfigured) {
        setState(() => _error = 'Could not connect with those values — '
            'double-check the URL and anon key.');
      }
    });
  }

  String? _validate({bool signup = false}) {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) return 'Enter a valid email.';
    if (_password.text.isEmpty) return 'Enter a password.';
    if (signup && _password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final configured = SupabaseConfig.isConfigured;
    final byEnv = SupabaseConfig.configuredByEnv;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.science_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 10),
                Text('LabTrack',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  configured
                      ? 'Sign in to continue'
                      : "Connect to your lab's cloud to begin",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),

                // Required privacy & data policy agreement — gates every entry
                // (sign in, create account, continue offline) until accepted.
                _agreementRow(scheme),
                if (!_agreed)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Text(
                        'You must accept the policy to sign in or continue.',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 11)),
                  ),
                const SizedBox(height: 20),

                // ---- Cloud connection ----
                if (configured)
                  Row(
                    children: [
                      const Icon(Icons.cloud_done_outlined,
                          size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Connected to ${SupabaseConfig.activeUrl}',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                      ),
                      if (!byEnv)
                        TextButton(
                          onPressed: () =>
                              setState(() => _showConfig = !_showConfig),
                          child: Text(_showConfig ? 'Hide' : 'Change'),
                        ),
                    ],
                  ),
                if (!configured || _showConfig) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _url,
                    enabled: !_busy && !byEnv,
                    decoration: const InputDecoration(
                        labelText: 'Supabase project URL',
                        hintText: 'https://YOUR.supabase.co'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    enabled: !_busy && !byEnv,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Anon / publishable key',
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!configured)
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.cloud_sync_outlined),
                      label: const Text('Connect'),
                    )
                  else
                    Text('Saved. Restart LabTrack to apply a changed connection.',
                        style: TextStyle(color: scheme.primary, fontSize: 12)),
                  const Divider(height: 32),
                ],

                // ---- Sign in (only once connected) ----
                if (configured) ...[
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (_busy || !_agreed)
                        ? null
                        : () {
                            final err = _validate();
                            if (err != null) {
                              setState(() => _error = err);
                              return;
                            }
                            _run(() => widget.sync
                                .signIn(_email.text, _password.text));
                          },
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: (_busy || !_agreed)
                        ? null
                        : () {
                            final err = _validate(signup: true);
                            if (err != null) {
                              setState(() => _error = err);
                              return;
                            }
                            _run(() async {
                              final session = await widget.sync
                                  .signUp(_email.text, _password.text);
                              if (!session && mounted) {
                                setState(() => _info =
                                    'Account created. If email confirmation is '
                                    'on, confirm via the email, then sign in.');
                              }
                            });
                          },
                    child: const Text('Create account'),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 14),
                  Text(_info!, textAlign: TextAlign.center),
                ],

                // Escape hatch: use the app local-only for this session. Data
                // stays on this device; sync resumes once you sign in.
                const Divider(height: 32),
                TextButton.icon(
                  onPressed:
                      (_busy || !_agreed) ? null : widget.onContinueOffline,
                  icon: const Icon(Icons.cloud_off_outlined, size: 18),
                  label: const Text('Continue offline (local only)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _policyText = '''
LabTrack — Privacy & Data Policy

LabTrack is a local-first laboratory management application developed by the Su Lab (MBBE, University of Hawaii at Manoa).

1. Local data
All of your data — projects, experiments, tasks, strains, reagents, cultures, primers, protocols, reports, images and settings — is stored locally on this device in an on-device database. It does not leave this device unless you explicitly enable Cloud Sync.

2. Optional cloud sync
If you configure Cloud Sync, your data is sent to and stored on the Supabase project whose URL and key you provide and control. Syncing only runs when you press "Push" or "Pull" (or when sync-on-close is enabled). If you never configure Cloud Sync, no data is transmitted anywhere.

3. No tracking
LabTrack contains no advertising, analytics, telemetry or third-party tracking. It collects no usage statistics and makes no network connection except to the Supabase backend you configure.

4. Notifications
Deadline and schedule reminders are generated and shown locally on this device. No reminder content is sent off-device.

5. Your control
You can export your data to PDF or a backup file at any time, and delete any or all of it from within the app.

By checking "I agree", you confirm that you have read and accept this Privacy & Data Policy. You must accept it to use LabTrack.''';
