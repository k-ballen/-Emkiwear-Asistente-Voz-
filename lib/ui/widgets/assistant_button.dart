import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

/// Reusable floating action button for the Emki Voice Assistant,
/// designed to be included across all screens in the application.
class AssistantFloatingButton extends StatelessWidget {
  final VoidCallback? onTap;

  const AssistantFloatingButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: const Text(
            '¿Necesitas ayuda?',
            style: TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        FloatingActionButton(
          heroTag: null,
          onPressed: onTap ?? () => showAssistantModal(context),
          backgroundColor: const Color(0xFF6A1B9A),
          elevation: 6,
          child: const Icon(Icons.mic_rounded, size: 30, color: Colors.white),
        ),
      ],
    );
  }
}
