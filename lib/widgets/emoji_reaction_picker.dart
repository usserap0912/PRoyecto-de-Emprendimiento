import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class EmojiReactionPicker {
  static const commonEmojis = <String>[
    '❤️',
    '👍',
    '😮',
    '😢',
    '😡',
    '🙏',
    '🛡️',
    '⚠️',
    '🚨',
    '👏',
    '💪',
    '✅',
    '👀',
    '🔥',
    '🤝',
    '💡',
    '📍',
    '🚓',
    '🚑',
    '🏠',
    '🌙',
    '☀️',
    '🙂',
    '🤔',
  ];

  static Future<String?> show(BuildContext context, {String? currentEmoji}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _EmojiReactionPickerSheet(currentEmoji: currentEmoji),
    );
  }
}

class _EmojiReactionPickerSheet extends StatefulWidget {
  const _EmojiReactionPickerSheet({this.currentEmoji});

  final String? currentEmoji;

  @override
  State<_EmojiReactionPickerSheet> createState() =>
      _EmojiReactionPickerSheetState();
}

class _EmojiReactionPickerSheetState extends State<_EmojiReactionPickerSheet> {
  final _customEmojiController = TextEditingController();

  @override
  void dispose() {
    _customEmojiController.dispose();
    super.dispose();
  }

  void _submitCustomEmoji() {
    final emoji = _customEmojiController.text.trim();
    if (emoji.isEmpty) return;
    Navigator.pop(context, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Reaccionar',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Elige un emoji o usa el teclado de emojis de tu dispositivo.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: EmojiReactionPicker.commonEmojis.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final emoji = EmojiReactionPicker.commonEmojis[index];
                  final selected = emoji == widget.currentEmoji;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Reaccionar con $emoji',
                    child: InkWell(
                      key: ValueKey('emoji_picker_$emoji'),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context, emoji);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('custom_emoji_field'),
                      controller: _customEmojiController,
                      maxLength: 16,
                      decoration: const InputDecoration(
                        labelText: 'Otro emoji',
                        hintText: 'Pega o escribe un emoji',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _submitCustomEmoji(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey('submit_custom_emoji'),
                    tooltip: 'Usar emoji',
                    onPressed: _submitCustomEmoji,
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
