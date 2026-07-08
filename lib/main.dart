import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database.dart';
import 'data/seed.dart';
import 'data/settings_repository.dart';
import 'data/trash_repository.dart';
import 'data/workspace_repository.dart';
import 'notifications/deadline_notifier.dart';
import 'notifications/notification_service.dart';
import 'notifications/priority_notifier.dart';
import 'notifications/schedule_notifier.dart';
import 'platform/single_instance.dart';
import 'platform/window_title_bar.dart';
import 'sync/cloud_config.dart';
import 'sync/supabase_config.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_prefs.dart';
import 'ui/account/auth_gate.dart';
import 'ui/account/sync_scope.dart';
import 'ui/lock.dart';
import 'ui/splash_screen.dart';
import 'ui/app_database_provider.dart';
import 'ui/backup/close_backup_dialog.dart';
import 'ui/closing_screen.dart';
import 'ui/home_shell.dart';
import 'ui/settings/app_background.dart';
import 'ui/settings/settings_theme.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mobile: draw edge-to-edge behind the system bars with transparent bars, so
  // the app's frosted background runs under the status and navigation bars
  // instead of leaving an opaque band. (Icon brightness is handled per-screen by
  // each AppBar.) No-op on desktop/web.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        // Stop Android drawing its own translucent "contrast" scrim behind the
        // gesture bar — that scrim is the dark band; with it off the app's frosted
        // background fills the area instead.
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  // Replace the native title bar with our own on desktop, keeping the native
  // window frame so resizing and Windows 11 snap layouts still work. macOS keeps
  // its traffic-light buttons (windowButtonVisibility), Windows/Linux don't.
  if (isDesktopWindow) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: defaultTargetPlatform == TargetPlatform.macOS,
    );
    await windowManager.setMinimumSize(const Size(640, 480));
    // Register the app so the "Launch at login" setting can enable/disable it.
    launchAtStartup.setup(
      appName: 'LabTrack',
      appPath: Platform.resolvedExecutable,
    );
  }

  // One long-lived database for the whole app session. Demonstration data is
  // seeded conditionally below (the user chooses on a brand-new install).
  final database = AppDatabase(null, false);
  // Ensure a default workspace exists and move any pre-workspace rows into it.
  await ensureDefaultWorkspace(database);
  // Resolve the demonstration-data choice: existing installs keep their data; a
  // brand-new, empty install defers to the first-run prompt in HomeShell.
  await resolveDemoData(database);
  // Restore read-only (lockdown) mode if it was left on.
  await loadAppLock(database);
  // Restore the privacy & data policy agreement (gates all app entry).
  await loadPrivacyAgreed(database);

  // Single-instance mode (user preference): if a copy is already running, focus
  // it and exit before any window is shown.
  if (isDesktopWindow &&
      !(await SettingsRepository(database).get()).allowMultipleInstances) {
    await enforceSingleInstance();
  }

  // Initialize Supabase from --dart-define, else the user's saved config. When
  // not yet configured, the login gate collects the connection on first run.
  final (cloudUrl, cloudKey) = await readCloudConfig(database);
  await SupabaseConfig.init(storedUrl: cloudUrl, storedKey: cloudKey);
  // Sweep the Trash of anything past its 30-day retention.
  unawaited(TrashRepository(database).purgeExpired(const Duration(days: 30)));

  runApp(LabTrackApp(database: database));
}

class LabTrackApp extends StatefulWidget {
  const LabTrackApp({super.key, required this.database});

  final AppDatabase database;

  @override
  State<LabTrackApp> createState() => _LabTrackAppState();
}

class _LabTrackAppState extends State<LabTrackApp>
    with WidgetsBindingObserver, WindowListener, TrayListener {
  final NotificationService _notifications = NotificationService();
  late final DeadlineNotifier _deadlineNotifier = DeadlineNotifier(
    widget.database,
    _notifications,
  );
  late final ScheduleNotifier _scheduleNotifier = ScheduleNotifier(
    widget.database,
    _notifications,
  );
  // Lets us show the close-backup dialog on the app's root navigator from the
  // window-close handler (which fires above the widget tree's normal context).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _closing = false;
  bool _showClosingScreen = false;
  bool _trayReady = false;
  // Set when the user chooses "Continue offline" at the login gate (this session).
  bool _offline = false;
  // Brief start screen on mobile; desktop skips straight to the app.
  bool _splashDone = isDesktopWindow;

  // The cloud-sync controller. Recreated by [_reloadSync] when the user enters a
  // new connection at the login gate, so first run connects without a restart.
  late SyncController _sync = SyncController(widget.database);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNotifications());
    // Show the start screen briefly on mobile, then reveal the app.
    if (!_splashDone) {
      Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _splashDone = true);
      });
    }
    // Intercept the window close (custom button, native X, Alt+F4) so we can
    // remind the user to back up first.
    if (isDesktopWindow) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
      trayManager.addListener(this);
      unawaited(_initTray());
    }
  }

  /// Sets up the system-tray icon + right-click menu (desktop only).
  Future<void> _initTray() async {
    try {
      // Windows uses the .ico; macOS/Linux status items need a PNG.
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon.png',
      );
      await trayManager.setToolTip('LabTrack');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'today', label: "Today's schedule"),
            MenuItem(
              key: 'priority',
              label: 'High priority tasks & experiments',
            ),
            MenuItem.separator(),
            MenuItem.submenu(
              label: 'Open to a section',
              submenu: Menu(
                items: [
                  for (var i = 0; i < homeSectionTitles.length; i++)
                    MenuItem(key: 'goto:$i', label: homeSectionTitles[i]),
                ],
              ),
            ),
            MenuItem.separator(),
            MenuItem(key: 'show', label: 'Open LabTrack'),
            MenuItem(key: 'exit', label: 'Exit'),
          ],
        ),
      );
      _trayReady = true;
    } catch (_) {
      _trayReady = false; // tray unsupported — minimise falls back to taskbar
    }
  }

  Future<void> _restoreWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Minimise to the tray (hide the window so only the tray icon remains). Falls
  /// back to a normal taskbar minimise if the tray didn't initialise.
  Future<void> _minimizeToTray() async {
    if (_trayReady) {
      await windowManager.hide();
    } else {
      await windowManager.minimize();
    }
  }

  /// Tray "Exit": bring the window back and run the normal close flow so the
  /// user still gets the back-up-or-not choice rather than quitting outright.
  Future<void> _exitViaDialog() async {
    await _restoreWindow();
    onWindowClose();
  }

  @override
  void onTrayIconMouseDown() => unawaited(_restoreWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null && key.startsWith('goto:')) {
      final i = int.tryParse(key.substring(5));
      if (i != null) {
        unawaited(_restoreWindow());
        homeSectionRequest.value = i; // HomeShell switches to this section
      }
      return;
    }
    switch (key) {
      case 'today':
        unawaited(_scheduleNotifier.announceToday());
      case 'priority':
        unawaited(announceHighPriority(widget.database, _notifications));
      case 'show':
        unawaited(_restoreWindow());
      case 'exit':
        unawaited(_exitViaDialog());
    }
  }

  /// Initialises notifications and starts the periodic deadline reminder at the
  /// user's chosen frequency, with an immediate first check.
  Future<void> _startNotifications() async {
    await _notifications.init();
    _deadlineNotifier.start();
    await _deadlineNotifier.checkNow();
    // Today's planned schedule, every launch.
    await _scheduleNotifier.notifyToday();
  }

  /// Re-initialises Supabase from the just-saved connection and recreates the
  /// sync controller, so a first-time user who enters their cloud connection at
  /// the login gate connects without restarting.
  Future<void> _reloadSync() async {
    final (url, key) = await readCloudConfig(widget.database);
    await SupabaseConfig.init(storedUrl: url, storedKey: key);
    _sync.dispose();
    setState(() => _sync = SyncController(widget.database));
  }

  /// Sync on close in the user's configured direction (default: push).
  Future<void> _syncOnClose() async {
    final mode = await readCloseSync(widget.database);
    switch (mode) {
      case CloseSync.push:
        await _sync.push();
      case CloseSync.pull:
        await _sync.pull();
    }
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    final ctx =
        _navigatorKey.currentState?.overlay?.context ??
        _navigatorKey.currentContext;
    // No UI to prompt with — just close (syncing first).
    if (ctx == null || !ctx.mounted) {
      await _finishClose(sync: true);
      return;
    }
    final (choice, sync) = await showCloseBackupDialog(ctx, widget.database);
    switch (choice) {
      case CloseChoice.cancel:
        return; // keep the window open
      case CloseChoice.minimizeToTray:
        await _minimizeToTray();
      case CloseChoice.quit:
        await _finishClose(sync: sync);
    }
  }

  /// Plays the goodbye animation, then does the (brief) teardown behind it so
  /// the close reads as a graceful fade instead of a frozen window.
  Future<void> _finishClose({bool sync = true}) async {
    _closing = true;
    if (mounted) setState(() => _showClosingScreen = true);
    // Make sure the closing screen has painted before we run any teardown.
    await WidgetsBinding.instance.endOfFrame;
    // Tomorrow's heads-up + (when chosen) a final cloud sync run while the
    // animation breathes; the sync is capped so a slow network can't hang close.
    await Future.wait<void>([
      _scheduleNotifier.notifyTomorrow(),
      if (sync)
        _syncOnClose().timeout(const Duration(seconds: 10), onTimeout: () {}),
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]);
    if (_trayReady) {
      try {
        await trayManager.destroy();
      } catch (_) {}
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    // With applicationShouldTerminateAfterLastWindowClosed = false (so minimise
    // to tray doesn't quit the app), destroying the window no longer ends the
    // process — exit explicitly on a real quit.
    exit(0);
  }

  @override
  void dispose() {
    _sync.dispose();
    _deadlineNotifier.dispose();
    if (isDesktopWindow) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check deadlines in case the app was open across a frequency interval.
      unawaited(_deadlineNotifier.checkNow());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // The Android back-button close flow already handled (or skipped) the
      // sync per the user's choice — don't double-sync as the app exits.
      if (suppressNextCloseSync) {
        suppressNextCloseSync = false;
        return;
      }
      // Sync when the app is backgrounded / closed (mobile has no close hook),
      // in the configured direction (default push).
      unawaited(_syncOnClose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsRepository(widget.database);
    return AppDatabaseProvider(
      database: widget.database,
      child: SyncScope(
        controller: _sync,
        // Drive theme / accent / density from settings so every screen respects
        // them with no per-component overrides.
        child: StreamBuilder<AppSetting>(
          stream: settings.watch(),
          builder: (context, snap) {
            final s = snap.data ?? SettingsRepository.defaults();
            final accent = Color(s.accentColor);
            final density = densityFromString(s.density);
            final customBg = hasCustomBackground(s);
            return MaterialApp(
              title: 'LabTrack',
              navigatorKey: _navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(
                brightness: Brightness.light,
                accent: accent,
                density: density,
                customBg: customBg,
              ),
              darkTheme: buildAppTheme(
                brightness: Brightness.dark,
                accent: accent,
                density: density,
                customBg: customBg,
              ),
              themeMode: themeModeFromString(s.themeMode),
              home: _splashDone
                  ? AuthGate(
                      onConfigSaved: _reloadSync,
                      offline: _offline,
                      onContinueOffline: () => setState(() => _offline = true),
                    )
                  : const SplashScreen(),
              builder: (context, child) {
                // Reserve room for the title bar so content doesn't slide under
                // it; on web/mobile there's no bar, so no inset.
                final inset = isDesktopWindow ? WindowTitleBar.height : 0.0;
                // A persistent "read-only mode" banner above the content when the
                // app is locked down (SafeArea keeps it below the phone status
                // bar; it sits below the desktop title bar).
                final content = ValueListenableBuilder<bool>(
                  valueListenable: appLock,
                  builder: (context, locked, _) {
                    final body = child ?? const SizedBox();
                    if (!locked) return body;
                    final scheme = Theme.of(context).colorScheme;
                    return Column(
                      children: [
                        SafeArea(
                          bottom: false,
                          // Material gives the Text a proper default style (no
                          // stray underline); a soft accent tint keeps it on
                          // brand with the warm-paper UI instead of a loud bar.
                          child: Material(
                            type: MaterialType.transparency,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.09),
                                border: Border(
                                  bottom: BorderSide(
                                    color: scheme.primary.withValues(
                                      alpha: 0.22,
                                    ),
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Read-only mode',
                                    style: TextStyle(
                                      color: scheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: body),
                      ],
                    );
                  },
                );
                return CallbackShortcuts(
                  bindings: {
                    // Esc goes back a page (pops the top route) when possible.
                    const SingleActivator(LogicalKeyboardKey.escape): () {
                      final nav = _navigatorKey.currentState;
                      if (nav != null && nav.canPop()) nav.maybePop();
                    },
                  },
                  child: Stack(
                    children: [
                      // Background + frosted surface fill the WHOLE window,
                      // including behind the title bar, so the bar reads as
                      // continuous frosting with no seam. Content is padded down
                      // below the bar.
                      Positioned.fill(
                        child: AppBackground(
                          setting: s,
                          child: Padding(
                            padding: EdgeInsets.only(top: inset),
                            child: content,
                          ),
                        ),
                      ),
                      // The title bar is the topmost layer: its logo and caption
                      // buttons paint after (above) the frosted BackdropFilter, so
                      // they stay sharp instead of being blurred into it.
                      if (isDesktopWindow)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: WindowTitleBar(
                            customBg: customBg,
                            navigatorKey: _navigatorKey,
                            onMinimize: isDesktopWindow
                                ? () => _minimizeToTray()
                                : null,
                          ),
                        ),
                      // Goodbye animation covers the whole window while closing.
                      if (_showClosingScreen)
                        const Positioned.fill(child: ClosingScreen()),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
