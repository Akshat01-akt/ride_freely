import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'tokens.dart';

/// Input with a glow when focused and an animated show/hide toggle for passwords.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  bool _focused = false;
  late bool _hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AnimatedContainer(
      duration: AppMotion.hover,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: _focused ? [BoxShadow(color: AppColors.fuchsia.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))] : const [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: _hidden,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: widget.icon == null
              ? null
              : AnimatedSwitcher(
                  duration: AppMotion.tap,
                  child: Icon(widget.icon, key: ValueKey(_focused), color: _focused ? AppColors.fuchsia : onSurface.withValues(alpha: 0.55)),
                ),
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: AnimatedSwitcher(
                    duration: AppMotion.tap,
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(
                      _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      key: ValueKey(_hidden),
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
