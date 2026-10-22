import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = 32,
    this.iconSize = 17,
    this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final double iconSize;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.alpha(AppColors.accent, .17)
            : AppColors.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: active
                ? AppColors.alpha(AppColors.accent, .38)
                : const Color(0xFF2B323D),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: disabled
                  ? AppColors.faint.withValues(alpha: .45)
                  : (foreground ??
                        (active
                            ? const Color(0xFFC9D8FF)
                            : const Color(0xFFC7CEDB))),
            ),
          ),
        ),
      ),
    );
  }
}

class ToastButton extends StatelessWidget {
  const ToastButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.height = 34,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Color foreground = danger
        ? AppColors.danger
        : primary
        ? const Color(0xFFBCD0FF)
        : const Color(0xFFB7C0CE);
    final Color background = danger
        ? const Color(0xFF2A1C20)
        : primary
        ? AppColors.alpha(AppColors.accent, .16)
        : AppColors.panel2;
    final Color border = danger
        ? const Color(0xFF6B3435)
        : primary
        ? AppColors.alpha(AppColors.accent, .4)
        : const Color(0xFF2F3743);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
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

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget child,
}) {
  final bool desktop = MediaQuery.sizeOf(context).width >= 700;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x9E030508),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: Align(
              alignment: desktop ? Alignment.center : Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(0, desktop ? .025 : .08),
                  end: Offset.zero,
                ).animate(curved),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.all(desktop ? 20 : 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 540,
                        maxHeight:
                            MediaQuery.sizeOf(context).height *
                            (desktop ? .86 : .92),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.kicker,
    required this.title,
    this.subtitle,
    required this.onClose,
    required this.body,
    this.footer,
    this.headerTrailing,
  });

  final String kicker;
  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final Widget body;
  final Widget? footer;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181D25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF343C48)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0xA8000000),
              blurRadius: 55,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(kicker.toUpperCase(), style: AppText.kicker),
                        const SizedBox(height: 3),
                        Text(title, style: AppText.title),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.35,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (headerTrailing != null) ...<Widget>[
                    headerTrailing!,
                    const SizedBox(width: 5),
                  ],
                  _CloseButton(onPressed: onClose),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 2, 15, 14),
                child: body,
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 13),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                  color: Color(0xFF151A21),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.close, size: 17, color: AppColors.muted),
        ),
      ),
    );
  }
}

class SheetField extends StatelessWidget {
  const SheetField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 8.5,
              letterSpacing: .8,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class SheetToggleRow extends StatelessWidget {
  const SheetToggleRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF11151B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: AppColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: AppColors.alpha(AppColors.accent, .7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  IconData? icon,
  Color iconColor = const Color(0xFFFFB0A6),
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final double screenWidth = MediaQuery.sizeOf(context).width;
  final double side = math.max(16.0, (screenWidth - 380) / 2);
  final double bottomInset = MediaQuery.paddingOf(context).bottom;

  final Widget text = Text(
    message,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      fontSize: 11.5,
      height: 1.25,
      color: Color(0xFFD7DEE9),
    ),
  );

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: icon == null
          ? text
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 8),
                Flexible(child: text),
              ],
            ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      // Clear the minimap + bottom control bar so buttons stay reachable.
      margin: EdgeInsets.only(
        left: side,
        right: side,
        bottom: 108 + bottomInset,
      ),
      elevation: 8,
      dismissDirection: DismissDirection.horizontal,
      duration:
          duration ??
          (actionLabel == null
              ? const Duration(milliseconds: 1700)
              : const Duration(milliseconds: 3600)),
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction),
    ),
  );
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String cancel = 'Cancel',
  String confirm = 'Delete',
  bool danger = true,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: Text(
        message,
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: AppColors.muted,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: danger ? AppColors.danger : AppColors.accent,
          ),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}
