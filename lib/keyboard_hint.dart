import 'package:fluent_ui/fluent_ui.dart';

/// A compact, reusable hint for a keyboard action.
class KeyboardHint extends StatelessWidget {
  const KeyboardHint({
    required this.keyLabel,
    required this.actionLabel,
    super.key,
  });

  final String keyLabel;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final color = theme.inactiveColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Text(actionLabel, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
