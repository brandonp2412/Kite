import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

Future<TimelineMessage?> showComposerPollSheet(
  BuildContext context, {
  required String roomId,
  required TimelineController controller,
}) {
  return showModalBottomSheet<TimelineMessage>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.kiteColors.canvas,
    constraints: const BoxConstraints(maxWidth: 440),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(KiteRadii.lg)),
    ),
    builder: (_) => ComposerPollSheet(roomId: roomId, controller: controller),
  );
}

class ComposerPollSheet extends StatefulWidget {
  const ComposerPollSheet({
    super.key,
    required this.roomId,
    required this.controller,
  });

  final String roomId;
  final TimelineController controller;

  @override
  State<ComposerPollSheet> createState() => _ComposerPollSheetState();
}

class _ComposerPollSheetState extends State<ComposerPollSheet> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers =
      <TextEditingController>[TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canCreate {
    if (_questionController.text.trim().isEmpty) return false;
    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    return options.length >= 2 && options.toSet().length == options.length;
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final removed = _optionControllers.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _createPoll() {
    if (!_canCreate) return;
    final message = widget.controller.sendPoll(
      widget.roomId,
      question: _questionController.text,
      options: _optionControllers.map((controller) => controller.text).toList(),
    );
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: KiteMotion.resolve(context, KiteMotion.standard),
      curve: KiteMotion.standardCurve,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          key: const Key('poll-create-sheet'),
          padding: const EdgeInsets.fromLTRB(
            KiteSpacing.lg,
            KiteSpacing.sm,
            KiteSpacing.lg,
            KiteSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(KiteRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: KiteSpacing.lg),
              Row(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(KiteRadii.sm),
                    ),
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(
                        Icons.poll_outlined,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: KiteSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Create poll',
                          style: KiteTypography.title.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Ask a question and add up to six choices.',
                          style: KiteTypography.metadata.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KiteSpacing.md),
              TextField(
                key: const Key('poll-question-field'),
                controller: _questionController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Question',
                  hintText: 'What should we decide?',
                ),
              ),
              const SizedBox(height: KiteSpacing.sm),
              for (
                var index = 0;
                index < _optionControllers.length;
                index++
              ) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        key: Key('poll-option-field-$index'),
                        controller: _optionControllers[index],
                        textInputAction: index == _optionControllers.length - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Choice ${index + 1}',
                          hintText: 'Add a choice',
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2) ...<Widget>[
                      const SizedBox(width: KiteSpacing.xs),
                      IconButton(
                        key: Key('poll-remove-option-$index'),
                        tooltip: 'Remove choice ${index + 1}',
                        onPressed: () => _removeOption(index),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ],
                ),
                if (index != _optionControllers.length - 1)
                  const SizedBox(height: KiteSpacing.xs),
              ],
              const SizedBox(height: KiteSpacing.sm),
              if (_optionControllers.length < 6)
                TextButton.icon(
                  key: const Key('poll-add-option'),
                  onPressed: _addOption,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add choice'),
                ),
              const SizedBox(height: KiteSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('poll-create-confirm'),
                  onPressed: _canCreate ? _createPoll : null,
                  child: const Text('Create poll'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
