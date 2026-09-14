import 'package:flutter/material.dart';
import 'package:kite/features/media/media_viewer.dart';

class MediaViewerFixture {
  MediaViewerFixture() : loadCounts = List<int>.filled(3, 0) {
    items = List<MediaViewerItem>.generate(3, _buildItem, growable: false);
  }

  final List<int> loadCounts;
  late final List<MediaViewerItem> items;

  MediaViewerItem _buildItem(int index) {
    final labels = <String>['Harbour at dusk', 'Forest path', 'City lights'];
    final captions = <InlineSpan>[
      const TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: 'Auckland harbour',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: ' · evening walk'),
        ],
      ),
      const TextSpan(
        children: <InlineSpan>[
          TextSpan(text: 'Weekend '),
          TextSpan(
            text: 'trail',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          TextSpan(text: ' after the rain'),
        ],
      ),
      const TextSpan(text: 'Last stop before home'),
    ];

    return MediaViewerItem(
      id: 'fixture-$index',
      heroTag: 'fixture-media-$index',
      semanticLabel: labels[index],
      thumbnailBuilder: (context) =>
          _FixtureMediaVisual(index: index, detailed: false),
      loadFullResolution: () {
        loadCounts[index]++;
        return Future<MediaVisualBuilder>.value(
          (context) => _FixtureMediaVisual(index: index, detailed: true),
        );
      },
      caption: captions[index],
    );
  }
}

class _FixtureMediaVisual extends StatelessWidget {
  const _FixtureMediaVisual({required this.index, required this.detailed});

  final int index;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    const palettes = <List<Color>>[
      <Color>[Color(0xFF102A43), Color(0xFF2D7A8A), Color(0xFFF4B860)],
      <Color>[Color(0xFF15291D), Color(0xFF39734B), Color(0xFF9BC18B)],
      <Color>[Color(0xFF1B1736), Color(0xFF483D8B), Color(0xFFD183C9)],
    ];
    final palette = palettes[index];

    return Center(
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Align(
                alignment: Alignment(0.58 - index * 0.18, -0.2),
                child: Icon(
                  index == 1 ? Icons.park_rounded : Icons.landscape_rounded,
                  size: detailed ? 132 : 116,
                  color: Colors.white.withValues(alpha: detailed ? 0.34 : 0.24),
                ),
              ),
              if (detailed)
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 24,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
