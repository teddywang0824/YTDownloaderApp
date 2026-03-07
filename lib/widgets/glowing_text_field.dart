import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A gradient-bordered input field with glow effect.
class GlowingTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData? prefixIcon;
  final Widget? suffixWidget;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  const GlowingTextField({
    super.key,
    required this.controller,
    this.hintText = '',
    this.prefixIcon,
    this.suffixWidget,
    this.enabled = true,
    this.onSubmitted,
  });

  @override
  State<GlowingTextField> createState() => _GlowingTextFieldState();
}

class _GlowingTextFieldState extends State<GlowingTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: AppColors.accentPurple.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: AppColors.accentCyan.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ]
            : [],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _isFocused ? AppColors.primaryGradient : null,
          border: !_isFocused
              ? Border.all(color: AppColors.borderLight, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.all(2), // Gradient border thickness
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgTertiary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Focus(
            onFocusChange: (focused) {
              setState(() => _isFocused = focused);
            },
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                  fontSize: 15,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: AppColors.accentCyan,
                        size: 22,
                      )
                    : null,
                suffixIcon: widget.suffixWidget != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: widget.suffixWidget,
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
