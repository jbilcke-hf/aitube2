// lib/widgets/api_key_dialog.dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({super.key});

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Enter HuggingFace API Key',
        style: TextStyle(
          color: AiTubeColors.onBackground,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: TextField(
        controller: _controller,
        obscureText: _obscureText,
        decoration: InputDecoration(
          labelText: 'API Key',
          labelStyle: const TextStyle(color: AiTubeColors.onSurfaceVariant),
          suffixIcon: IconButton(
            icon: Icon(
              _obscureText ? Icons.visibility : Icons.visibility_off,
              color: AiTubeColors.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _obscureText = !_obscureText),
          ),
        ),
      ),
      backgroundColor: AiTubeColors.surface,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AiTubeColors.onSurfaceVariant),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: AiTubeColors.primary,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}