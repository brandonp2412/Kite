import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:kite/features/timeline/timeline_controller.dart';

class TimelinePollCard extends StatelessWidget {
  const TimelinePollCard({
    super.key,
    required this.messageId,
    required this.poll,
    required this.onVote,
  });

  final String messageId;
  final TimelinePoll poll;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totalVotes = poll.totalVotes;
    return Semantics(
      container: true,
      label:
          'Poll: ${poll.question}. $totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}${poll.isEnded ? '. Poll ended' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 248, maxWidth: 360),
        child: DecoratedBox(
          key: Key('message-poll-$messageId'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(KiteRadii.md),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
              width: KiteStroke.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(KiteSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(KiteRadii.sm),
                      ),
                      child: SizedBox.square(
                        dimension: 34,
                        child: Icon(
                          Icons.poll_outlined,
                          size: 19,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: KiteSpacing.sm),
                    Text(
                      'Poll',
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (poll.isEnded || poll.isEnding)
                      Container(
                        key: Key('poll-state-$messageId'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: KiteSpacing.xs,
                          vertical: KiteSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(KiteRadii.pill),
                        ),
                        child: Text(
                          poll.isEnding ? 'Ending…' : 'Ended',
                          style: KiteTypography.metadata.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: KiteSpacing.sm),
                Text(
                  poll.question,
                  key: Key('poll-question-$messageId'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: KiteTypography.body.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: KiteSpacing.sm),
                for (final option in poll.options) ...<Widget>[
                  _PollOptionRow(
                    messageId: messageId,
                    option: option,
                    poll: poll,
                    onVote: onVote,
                  ),
                  if (option.id != poll.options.last.id)
                    const SizedBox(height: KiteSpacing.xs),
                ],
                const SizedBox(height: KiteSpacing.sm),
                Row(
                  children: <Widget>[
                    Text(
                      '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                      key: Key('poll-vote-count-$messageId'),
                      style: KiteTypography.metadata.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      poll.isEnded
                          ? 'Final results'
                          : poll.selectedOptionId == null
                          ? 'Tap to vote'
                          : 'Vote recorded',
                      style: KiteTypography.metadata.copyWith(
                        color: poll.selectedOptionId == null || poll.isEnded
                            ? colors.onSurfaceVariant
                            : colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.messageId,
    required this.option,
    required this.poll,
    required this.onVote,
  });

  final String messageId;
  final TimelinePollOption option;
  final TimelinePoll poll;
  final ValueChanged<String> onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = poll.selectedOptionId == option.id;
    final votes = poll.votesFor(option.id);
    final total = poll.totalVotes;
    final fraction = total == 0 ? 0.0 : votes / total;
    final enabled = !poll.isEnded && !poll.isEnding;
    return Semantics(
      button: enabled,
      selected: selected,
      label:
          '${option.label}, $votes ${votes == 1 ? 'vote' : 'votes'}${selected ? ', selected' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('poll-option-$messageId-${option.id}'),
          onTap: enabled ? () => onVote(option.id) : null,
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          child: SizedBox(
            height: 46,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.secondaryContainer.withValues(alpha: 0.74)
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(KiteRadii.sm),
                    border: Border.all(
                      color: selected
                          ? colors.primary.withValues(alpha: 0.62)
                          : colors.outlineVariant.withValues(alpha: 0.58),
                      width: selected
                          ? KiteStroke.emphasis
                          : KiteStroke.hairline,
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(KiteRadii.sm),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      key: Key('poll-progress-$messageId-${option.id}'),
                      tween: Tween<double>(end: fraction),
                      duration: KiteMotion.resolve(
                        context,
                        KiteMotion.standard,
                      ),
                      curve: KiteMotion.standardCurve,
                      builder: (context, value, child) => FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(
                          color: colors.primary.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KiteSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: KiteSpacing.xs),
                      Expanded(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KiteTypography.body.copyWith(
                            color: colors.onSurface,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: KiteSpacing.sm),
                      Text(
                        total == 0 ? '0%' : '${(fraction * 100).round()}%',
                        key: Key('poll-percent-$messageId-${option.id}'),
                        style: KiteTypography.metadata.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
