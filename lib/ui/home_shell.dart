import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/project_repository.dart';
import '../data/seed.dart';
import '../sync/sync_prefs.dart';
import 'account/sync_scope.dart';
import 'app_database_provider.dart';
import 'glass.dart';
import 'lock.dart';
import 'board/board_screen.dart';
import 'cloning/clone_list_screen.dart';
import 'cultures/active_cultures_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'deadlines/deadlines_screen.dart';
import 'experiments/experiment_list_screen.dart';
import 'primers/primer_list_screen.dart';
import 'projects/project_list_screen.dart';
import 'protocols/protocol_list_screen.dart';
import 'reagents/reagent_list_screen.dart';
import 'report/report_list_screen.dart';
import 'schedule/schedule_screen.dart';
import 'settings/settings_screen.dart';
import 'strains/strain_list_screen.dart';
import 'tasks/task_list_screen.dart';
import 'workspace/workspace_screen.dart';

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label, this.screen);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget screen;
}

const _dests = <_Dest>[
  _Dest(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard',
      DashboardScreen()),
  _Dest(Icons.science_outlined, Icons.science, 'Projects', ProjectListScreen()),
  _Dest(Icons.view_kanban_outlined, Icons.view_kanban, 'Board', BoardScreen()),
  _Dest(Icons.event_outlined, Icons.event, 'Deadlines', DeadlinesScreen()),
  _Dest(Icons.calendar_month_outlined, Icons.calendar_month, 'Schedule',
      ScheduleScreen()),
  _Dest(Icons.biotech_outlined, Icons.biotech, 'Experiments',
      ExperimentListScreen()),
  _Dest(Icons.checklist_outlined, Icons.checklist, 'Tasks', TaskListScreen()),
  _Dest(Icons.coronavirus_outlined, Icons.coronavirus, 'Strains',
      StrainListScreen()),
  _Dest(Icons.inventory_2_outlined, Icons.inventory_2, 'Reagents',
      ReagentListScreen()),
  _Dest(Icons.bubble_chart_outlined, Icons.bubble_chart, 'Cultures',
      ActiveCulturesScreen()),
  _Dest(Icons.biotech_outlined, Icons.biotech, 'Primers', PrimerListScreen()),
  _Dest(Icons.donut_large_outlined, Icons.donut_large, 'Cloning',
      CloneListScreen()),
  _Dest(Icons.menu_book_outlined, Icons.menu_book, 'Protocols',
      ProtocolListScreen()),
  _Dest(Icons.assessment_outlined, Icons.assessment, 'Report',
      ReportListScreen()),
  _Dest(Icons.workspaces_outlined, Icons.workspaces, 'Workspace',
      WorkspaceScreen()),
  _Dest(Icons.settings_outlined, Icons.settings, 'Settings', SettingsScreen()),
];

const _primaryCount = 4; // first four go in the bottom bar

/// Section labels in nav order (index-aligned with [_dests]); used by the
/// system-tray "Open to a section" menu.
final homeSectionTitles = [for (final d in _dests) d.label];

/// Set by the tray menu to ask the HomeShell to switch to a section by index.
final ValueNotifier<int> homeSectionRequest = ValueNotifier<int>(-1);

/// App home. Adaptive navigation: a NavigationRail on wide screens, and a bottom
/// NavigationBar (with a "More" sheet for the inventory sections) on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    homeSectionRequest.addListener(_onSectionRequest);
    // First run on a brand-new install: ask whether to seed demonstration data.
    if (demoDataUndecided) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskDemoData());
    }
  }

  @override
  void dispose() {
    homeSectionRequest.removeListener(_onSectionRequest);
    super.dispose();
  }

  /// Switch sections in response to a tray-menu "Open to a section" request.
  void _onSectionRequest() {
    final v = homeSectionRequest.value;
    if (v < 0 || !mounted) return;
    if (v < _dests.length && v != _index) setState(() => _index = v);
    homeSectionRequest.value = -1; // consume the request
  }

  /// One-time first-run prompt offering to seed demonstration data on a
  /// brand-new install. Skipped if real data already arrived (e.g. a cloud pull).
  Future<void> _maybeAskDemoData() async {
    if (!demoDataUndecided || !mounted) return;
    final db = AppDatabaseProvider.of(context);
    final hasData = (await ProjectRepository(db).watchAll().first).isNotEmpty;
    if (!mounted) return;
    if (hasData) {
      await setSeedDecision(db, include: false);
      return;
    }
    final include = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        title: const Text('Add demonstration data?'),
        content: const Text(
            'Start with example projects, experiments, strains, reagents, '
            'cultures and more so you can explore LabTrack right away? You can '
            'remove it anytime in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Start empty')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add examples')),
        ],
      ),
    );
    if (!mounted) return;
    await setSeedDecision(db, include: include ?? false);
    if (mounted) setState(() {});
  }

  void _openMore() {
    showGlassModalSheet<void>(
      context: context,
      // Scroll-controlled + a height-capped scrollable list so every section is
      // reachable: there are more "More" entries than fit a min-height column,
      // which previously clipped the last items with no way to scroll to them.
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (int i = _primaryCount; i < _dests.length; i++)
                ListTile(
                  leading: Icon(
                      _index == i ? _dests[i].selectedIcon : _dests[i].icon),
                  title: Text(_dests[i].label),
                  selected: _index == i,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _index = i);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell(context);
    // Android/iOS: intercept the system back button at the root to confirm
    // closing (and offer to sync first). Pushed screens, sheets and dialogs
    // pop normally — this only fires when there's nothing left to pop.
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) return shell;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose(context);
      },
      child: shell,
    );
  }

  /// Asks whether to close the app and (if signed in) whether to sync first,
  /// then exits. Uses the configured sync direction and suppresses the
  /// lifecycle auto-sync so the user's choice isn't overridden on the way out.
  Future<void> _confirmClose(BuildContext context) async {
    final db = AppDatabaseProvider.of(context);
    final sync = SyncScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var doSync = sync.isSignedIn;

    final close = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => GlassAlertDialog(
          title: const Text('Close LabTrack?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Do you want to close the app?'),
              if (sync.isSignedIn)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: doSync,
                    onChanged: (v) => setLocal(() => doSync = v ?? false),
                    title: const Text('Sync to the cloud first'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Close')),
          ],
        ),
      ),
    );
    if (close != true) return;

    // The lifecycle handler must not sync again as the app exits.
    suppressNextCloseSync = true;
    if (doSync && sync.isSignedIn) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Syncing before closing…')));
      final mode = await readCloseSync(db);
      final op = mode == CloseSync.push ? sync.push() : sync.pull();
      await op.timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    await SystemNavigator.pop();
  }

  Widget _shell(BuildContext context) {
    // Cross-fade between sections (~180ms) so moving areas doesn't snap.
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(_index),
        child: _dests[_index].screen,
      ),
    );
    // Phones (short side < 600 dp) get the floating bottom island in BOTH
    // orientations; tablets/desktop get the side rail.
    final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;

    if (!isPhone) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final extended = constraints.maxWidth >= 1100;
          return Scaffold(
            body: Row(
              children: [
                // Scrollable so the rail never overflows when there are many
                // destinations on a short window — but with no visible scrollbar.
                ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: SizedBox(
                        width: extended ? 240 : 72,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            for (int i = 0; i < _dests.length; i++)
                              _RailItem(
                                icon: _dests[i].icon,
                                selectedIcon: _dests[i].selectedIcon,
                                label: _dests[i].label,
                                selected: _index == i,
                                extended: extended,
                                onTap: () => setState(() => _index = i),
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // No hard rule between sidebar and content — the bg-sidebar
                // tone shift does the zoning, softened by a rounded top-left
                // corner so the content reads as a card against the rail.
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16)),
                    child: body,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final selected = _index < _primaryCount ? _index : _primaryCount;
    return Scaffold(
      // No extendBody: the body is laid out ABOVE the bottom bar, so per-tab
      // FABs and scrollable content never hide behind it. The bar handles its
      // own SafeArea (home indicator) inset.
      body: body,
      bottomNavigationBar: _bottomBar(context, selected),
    );
  }

  /// Custom bottom bar reforged in the IT之家 style: a full-width frosted bar
  /// flush to the bottom edge; each tab is a line icon above its label, and the
  /// selected tab sets its (filled) icon inside a filled accent rounded badge
  /// with an accent label.
  Widget _bottomBar(BuildContext context, int selected) {
    final scheme = Theme.of(context).colorScheme;
    final items = <(IconData, IconData, String)>[
      for (int i = 0; i < _primaryCount; i++)
        (_dests[i].icon, _dests[i].selectedIcon, _dests[i].label),
      (Icons.more_horiz, Icons.more_horiz, 'More'),
    ];
    return GlassSurface(
      blur: 26,
      opacity: 0.66,
      sheen: true,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: Border(
        top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavButton(
                      icon: items[i].$1,
                      selectedIcon: items[i].$2,
                      label: items[i].$3,
                      selected: i == selected,
                      onTap: () {
                        if (i < _primaryCount) {
                          setState(() => _index = i);
                        } else {
                          _openMore();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination in the desktop side rail. Reacts to hover with a clear
/// full-item highlight and a pointer cursor; the selected item gets an accent
/// tint. [extended] lays the label beside the icon, else below it.
class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.14)
        : (_hover
            ? scheme.onSurface.withValues(alpha: 0.07)
            : Colors.transparent);
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    final weight = selected ? FontWeight.w600 : FontWeight.w500;
    final iconWidget =
        Icon(selected ? widget.selectedIcon : widget.icon, size: 22, color: fg);
    final content = widget.extended
        ? Row(
            children: [
              const SizedBox(width: 12),
              iconWidget,
              const SizedBox(width: 14),
              Expanded(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: fg, fontSize: 14, fontWeight: weight)),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 4),
              Text(widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 11, fontWeight: weight)),
            ],
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(
              horizontal: widget.extended ? 10 : 8, vertical: 3),
          padding: EdgeInsets.symmetric(
              horizontal: widget.extended ? 8 : 0,
              vertical: widget.extended ? 12 : 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// One tab in [_HomeShellState._bottomBar]. Selected: the filled icon inside a
/// filled accent rounded badge with an accent label. Unselected: a muted line
/// icon and label.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              selected ? selectedIcon : icon,
              size: 22,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.0,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
