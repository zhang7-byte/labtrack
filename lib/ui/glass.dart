import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'lock.dart';

/// Build-level switch for the frosted-glass treatment. Combined with the user's
/// "reduce animations" accessibility preference at runtime, this is how we fall
/// back to solid surfaces where blur is unsupported or too costly.
const bool kGlassEnabled = true;

bool glassActive(BuildContext context) =>
    kGlassEnabled && !MediaQuery.of(context).disableAnimations;

/// A translucent, background-blurred panel for *chrome* (nav bars, dialogs,
/// sheets). Falls back to a solid surface when glass is inactive. Keeps text
/// legible by tinting with the theme surface colour at high opacity.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 18,
    this.opacity = 0.72,
    this.borderRadius,
    this.border,
    this.sheen = false,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final BoxBorder? border;

  /// Adds a faint specular highlight gradient for a glassier "liquid glass"
  /// look. Painted behind the content so text stays crisp.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.zero;
    final active = glassActive(context);

    Widget body = child;
    // A faint top-down specular highlight gives the frosted panel a glassy
    // "liquid glass" sheen. Painted behind the content so text stays crisp. On
    // iOS the sheen is pushed further toward Apple's Liquid Glass look: a
    // brighter top specular, a soft light bounce at the bottom, and a crisp
    // bright hairline along the top edge (all clipped to the rounded shape).
    if (sheen && active) {
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      body = Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: ios
                        ? [
                            Colors.white.withValues(alpha: 0.30),
                            Colors.white.withValues(alpha: 0.06),
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.12),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.14),
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                    stops: ios
                        ? const [0.0, 0.14, 0.6, 1.0]
                        : const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Bright specular rim along the top edge — the tell-tale Liquid Glass
          // highlight. Clipped to the panel's rounded corners by the outer
          // ClipRRect below.
          if (ios)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          child,
        ],
      );
    }

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        // Opaque surface when not blurring keeps content legible.
        color: scheme.surface.withValues(alpha: active ? opacity : 1.0),
        borderRadius: radius,
        border: border,
      ),
      child: body,
    );

    if (!active) {
      return ClipRRect(borderRadius: radius, child: panel);
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      ),
    );
  }
}

/// The primary "new entry" action, as a frosted-glass extended FAB. Mirrors
/// [FloatingActionButton.extended]'s API (icon + label + onPressed + heroTag) but
/// renders as a blurred, legible pill. M3's default extended FAB fills with
/// `primaryContainer`, which this app themes to ~10% opacity, so the stock FAB
/// looks see-through over content. Falls back to a solid pill when glass is off.
class GlassFab extends StatelessWidget {
  const GlassFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.heroTag,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    // Disabled + dimmed in read-only (lockdown) mode — adding is blocked.
    return ValueListenableBuilder<bool>(
      valueListenable: appLock,
      builder: (context, locked, _) {
        final scheme = Theme.of(context).colorScheme;
        final active = glassActive(context);
        final radius = BorderRadius.circular(28);
        // A faint accent wash over the frosted paper keeps it reading as the
        // primary action while staying legible against the accent icon + label.
        final tint = Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.12), scheme.surface);

        Widget panel = Material(
          color: tint.withValues(alpha: active ? 0.74 : 1.0),
          child: InkWell(
            onTap: locked ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: IconTheme.merge(
                data: IconThemeData(color: scheme.primary, size: 22),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [icon, const SizedBox(width: 10), label],
                  ),
                ),
              ),
            ),
          ),
        );

        panel = ClipRRect(
          borderRadius: radius,
          child: active
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: panel)
              : panel,
        );

        final fab = Hero(
          tag: heroTag ?? 'glass-fab',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border:
                  Border.all(color: scheme.primary.withValues(alpha: 0.40)),
              boxShadow: [
                BoxShadow(
                    color: scheme.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: panel,
          ),
        );
        return locked ? Opacity(opacity: 0.4, child: fab) : fab;
      },
    );
  }
}

/// Shows a dialog over a blurred backdrop (frosted chrome). Falls back to a
/// normal dialog when glass is inactive.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  if (!glassActive(context)) {
    return showDialog<T>(context: context, builder: builder);
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, anim, _, child) {
      final t = Curves.easeOut.transform(anim.value);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
        child: FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(anim),
            child: child,
          ),
        ),
      );
    },
  );
}

/// An AlertDialog rendered as a frosted "liquid glass" card (translucent,
/// background-blurred, with a specular sheen) instead of a solid Material
/// surface. Drop-in for `AlertDialog` inside [showGlassDialog]; falls back to a
/// solid card when glass is inactive.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({super.key, this.title, this.content, this.actions});

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(28);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
          child: Material(
            type: MaterialType.transparency,
            child: GlassSurface(
              blur: 30,
              opacity: 0.6,
              sheen: true,
              borderRadius: radius,
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      DefaultTextStyle(
                        style: theme.textTheme.titleLarge!,
                        child: title!,
                      ),
                    if (content != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: DefaultTextStyle(
                          style: theme.textTheme.bodyMedium!
                              .copyWith(color: scheme.onSurfaceVariant),
                          child: content!,
                        ),
                      ),
                    if (actions != null && actions!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: OverflowBar(
                          spacing: 8,
                          overflowSpacing: 4,
                          alignment: MainAxisAlignment.end,
                          children: actions!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in a frosted action sheet.
class GlassAction {
  const GlassAction(this.icon, this.label, this.onTap,
      {this.destructive = false, this.mutates = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  /// Whether this action changes data (add / edit / delete). Read-only
  /// (lockdown) mode hides mutating actions; pass `mutates: false` for view-only
  /// actions like "Export PDF".
  final bool mutates;
}

/// A small actions menu anchored next to the button that triggered it (the
/// passed [context] should be near that button — e.g. the row that hosts a
/// trailing ⋮). Uses the themed translucent popup surface. Falls back to a
/// frosted bottom sheet if the anchor can't be resolved.
Future<void> showGlassActions(
    BuildContext context, List<GlassAction> actions,
    {Offset? at}) async {
  // In read-only (lockdown) mode, only non-mutating actions (e.g. export) show.
  if (appLock.value) {
    final allowed = actions.where((a) => !a.mutates).toList();
    if (allowed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Read-only mode is on — unlock it in Settings to edit.')));
      return;
    }
    actions = allowed;
  }
  final overlay = Overlay.of(context).context.findRenderObject();
  if (overlay is! RenderBox) {
    return _showGlassActionsSheet(context, actions);
  }
  // Anchor exactly where the user tapped the ⋮ (converted into the overlay's
  // coordinate space) so the menu opens next to the button instead of as a
  // bottom sheet; without a tap position, fall back to the triggering widget's
  // top-right corner. The frosted menu opens downward and shifts to stay
  // on-screen.
  final Offset anchor;
  if (at != null) {
    anchor = overlay.globalToLocal(at);
  } else {
    final box = context.findRenderObject();
    if (box is! RenderBox) {
      return _showGlassActionsSheet(context, actions);
    }
    anchor =
        box.localToGlobal(box.size.topRight(Offset.zero), ancestor: overlay);
  }
  final selected = await showGeneralDialog<int>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (ctx, _, _) =>
        _GlassMenu(anchor: anchor, overlaySize: overlay.size, actions: actions),
    transitionBuilder: (ctx, anim, _, child) {
      final t = Curves.easeOut.transform(anim.value);
      return FadeTransition(
        opacity: anim,
        child: Transform.scale(
          scale: 0.96 + 0.04 * t,
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
  if (selected != null) actions[selected].onTap();
}

/// A trailing "⋮" actions button that opens [showGlassActions] anchored exactly
/// where the user tapped, so the menu appears right next to the button (not as a
/// bottom sheet) on both desktop and mobile. Drop-in replacement for the inline
/// `IconButton(icon: Icon(Icons.more_vert), onPressed: () => showGlassActions(...))`
/// pattern.
class GlassMoreButton extends StatefulWidget {
  const GlassMoreButton({
    super.key,
    required this.actions,
    this.tooltip,
    this.icon = Icons.more_vert,
    this.visualDensity,
  });

  final List<GlassAction> actions;
  final String? tooltip;
  final IconData icon;
  final VisualDensity? visualDensity;

  @override
  State<GlassMoreButton> createState() => _GlassMoreButtonState();
}

class _GlassMoreButtonState extends State<GlassMoreButton> {
  Offset? _tapPosition;

  @override
  Widget build(BuildContext context) {
    // A Listener records the pointer-down location without competing with the
    // IconButton's own tap recognizer, so the menu can anchor at the click.
    return Listener(
      onPointerDown: (event) => _tapPosition = event.position,
      child: IconButton(
        tooltip: widget.tooltip,
        visualDensity: widget.visualDensity,
        icon: Icon(widget.icon),
        onPressed: () =>
            showGlassActions(context, widget.actions, at: _tapPosition),
      ),
    );
  }
}

/// A frosted "liquid glass" popup menu anchored near the ⋮ button. Each row pops
/// the menu with its index.
class _GlassMenu extends StatelessWidget {
  const _GlassMenu({
    required this.anchor,
    required this.overlaySize,
    required this.actions,
  });

  final Offset anchor;
  final Size overlaySize;
  final List<GlassAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const width = 224.0;
    const rowHeight = 48.0;
    final estHeight = actions.length * rowHeight + 12;

    var left = anchor.dx - width;
    if (left < 8) left = 8;
    if (left + width > overlaySize.width - 8) {
      left = overlaySize.width - 8 - width;
    }
    var top = anchor.dy;
    if (top + estHeight > overlaySize.height - 8) {
      top = (overlaySize.height - 8 - estHeight)
          .clamp(8.0, overlaySize.height - 8);
    }

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            type: MaterialType.transparency,
            // Clip the row ink (hover/splash) to the rounded shape so the
            // highlight never pokes past the menu's corners.
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: GlassSurface(
              blur: 30,
              opacity: 0.6,
              sheen: true,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++)
                    _GlassMenuRow(
                      action: actions[i],
                      onTap: () => Navigator.of(context).pop(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One hover-reactive row in [_GlassMenu]. The highlight is drawn as content
/// (inside GlassSurface's clip) so it sits on top of the frosted panel and stays
/// within the rounded corners.
class _GlassMenuRow extends StatefulWidget {
  const _GlassMenuRow({required this.action, required this.onTap});

  final GlassAction action;
  final VoidCallback onTap;

  @override
  State<_GlassMenuRow> createState() => _GlassMenuRowState();
}

class _GlassMenuRowState extends State<_GlassMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = widget.action;
    final fg = a.destructive ? scheme.error : scheme.onSurfaceVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover
              ? scheme.onSurface.withValues(alpha: 0.08)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(a.icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(a.label,
                    style:
                        a.destructive ? TextStyle(color: scheme.error) : null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet fallback (no anchor available).
Future<void> _showGlassActionsSheet(
    BuildContext context, List<GlassAction> actions) {
  return showGlassModalSheet<void>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                leading:
                    Icon(a.icon, color: a.destructive ? scheme.error : null),
                title: Text(a.label,
                    style:
                        a.destructive ? TextStyle(color: scheme.error) : null),
                onTap: () {
                  Navigator.pop(context);
                  a.onTap();
                },
              ),
          ],
        ),
      );
    },
  );
}

/// Shows a bottom sheet as a frosted panel (blurred, translucent), falling back
/// to a normal sheet when glass is inactive.
Future<T?> showGlassModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final active = glassActive(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    backgroundColor: active ? Colors.transparent : null,
    // A light scrim (instead of the default ~54% black) so the panel's
    // BackdropFilter blurs the actual page behind it — a heavy barrier would
    // leave it blurring a near-black scrim, which reads as a flat opaque sheet.
    barrierColor: active ? Colors.black.withValues(alpha: 0.16) : null,
    builder: (context) {
      if (!active) return builder(context);
      return GlassSurface(
        blur: 24,
        // Lower tint so the blurred content shows through as frosted glass.
        opacity: 0.6,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        child: builder(context),
      );
    },
  );
}
