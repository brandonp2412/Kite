import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

@immutable
final class TimelineLinkPreviewData {
  const TimelineLinkPreviewData({
    required this.uri,
    required this.title,
    required this.description,
  });

  final Uri uri;
  final String title;
  final String description;
}

abstract interface class TimelineLinkOpenPort {
  Future<void> open(Uri uri);
}

typedef TimelineExternalUriLauncher = Future<bool> Function(Uri uri);

final class PlatformTimelineLinkOpenPort implements TimelineLinkOpenPort {
  const PlatformTimelineLinkOpenPort({this.launcher});

  final TimelineExternalUriLauncher? launcher;

  @override
  Future<void> open(Uri uri) async {
    if ((uri.scheme != 'http' && uri.scheme != 'https') || !uri.hasAuthority) {
      return;
    }
    await (launcher ?? _launchExternal)(uri);
  }

  static Future<bool> _launchExternal(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final class DeterministicTimelineLinkOpenPort implements TimelineLinkOpenPort {
  DeterministicTimelineLinkOpenPort({this.latency = Duration.zero});

  final Duration latency;
  final List<Uri> opened = <Uri>[];

  @override
  Future<void> open(Uri uri) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    opened.add(uri);
  }
}

TimelineLinkPreviewData? timelineLinkPreviewForText(String body) {
  final match = RegExp(
    r'https?://[^\s<>()]+',
    caseSensitive: false,
  ).firstMatch(body);
  final raw = match?.group(0);
  if (raw == null) return null;
  final normalized = raw.replaceFirst(RegExp(r'[.,!?;:]+$'), '');
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasAuthority) return null;

  final host = uri.host.replaceFirst(
    RegExp(r'^www\.', caseSensitive: false),
    '',
  );
  final path = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  final description = path.isEmpty
      ? 'Shared link'
      : path.take(2).map(Uri.decodeComponent).join(' › ');
  return TimelineLinkPreviewData(
    uri: uri,
    title: host.isEmpty ? uri.toString() : host,
    description: description,
  );
}

class TimelineLinkPreviewCard extends StatelessWidget {
  const TimelineLinkPreviewCard({
    super.key,
    required this.preview,
    required this.onOpen,
  });

  final TimelineLinkPreviewData preview;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open link ${preview.title}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          key: const Key('timeline-link-preview'),
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(KiteRadii.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('timeline-link-preview-open'),
            onTap: onOpen,
            child: SizedBox(
              height: 76,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 76,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: colors.primaryContainer),
                      child: Icon(
                        Icons.link_rounded,
                        size: 30,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KiteSpacing.sm,
                        vertical: KiteSpacing.xs,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            preview.title,
                            key: const Key('timeline-link-preview-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KiteTypography.body.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.xxs),
                          Text(
                            preview.description,
                            key: const Key('timeline-link-preview-description'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KiteTypography.metadata.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: KiteSpacing.xxs),
                          Text(
                            preview.uri.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KiteTypography.metadata.copyWith(
                              color: colors.primary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: KiteSpacing.sm),
                    child: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
