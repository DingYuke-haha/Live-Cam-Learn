import 'package:flutter/material.dart';
import '../services/app_config.dart';

/// Toggle switch for Scene/Object capture modes
class ModeToggle extends StatelessWidget {
  final CaptureMode currentMode;
  final ValueChanged<CaptureMode> onModeChanged;
  final bool enabled;

  const ModeToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFD54F),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            label: 'Scene',
            mode: CaptureMode.scene,
            isSelected: currentMode == CaptureMode.scene,
          ),
          _buildModeButton(
            label: 'Object',
            mode: CaptureMode.object,
            isSelected: currentMode == CaptureMode.object,
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required CaptureMode mode,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: enabled && !isSelected ? () => onModeChanged(mode) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF8C00) : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
