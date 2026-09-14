import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:signals/signals_flutter.dart';

typedef MediaVisualBuilder = Widget Function(BuildContext context);
typedef MediaFullResolutionLoader = Future<MediaVisualBuilder> Function();

@immutable
class MediaViewerItem {
  const MediaViewerItem({
    required this.id,
    required this.heroTag,
    required this.semanticLabel,
    required this.thumbnailBuilder,
    required this.loadFullResolution,
    this.caption,
  });

  final String id;
  final Object heroTag;
  final String semanticLabel;
  final MediaVisualBuilder thumbnailBuilder;
  final MediaFullResolutionLoader loadFullResolution;
  final InlineSpan? caption;
}

class MediaViewerRoute extends PageRouteBuilder<void> {
  MediaViewerRoute({
    required List<MediaViewerItem> items,
    int initialIndex = 0,
    ValueChanged<int>? onIndexChanged,
  }) : super(
         opaque: true,
         barrierDismissible: false,
         transitionDuration: KiteMotion.deliberate,
         reverseTransitionDuration: KiteMotion.standard,
         pageBuilder: (context, animation, secondaryAnimation) => MediaViewer(
           items: items,
           initialIndex: initialIndex,
           onIndexChanged: onIndexChanged,
         ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final reducedMotion = KiteMotion.prefersReducedMotion(context);
           if (reducedMotion) return child;
           return FadeTransition(
             opacity: CurvedAnimation(
               parent: animation,
               curve: KiteMotion.standardCurve,
               reverseCurve: KiteMotion.standardCurve.flipped,
             ),
             child: child,
           );
         },
       ) {
    assert(items.isNotEmpty);
    assert(initialIndex >= 0 && initialIndex < items.length);
  }
}

class MediaViewer extends SignalStatefulWidget {
  const MediaViewer({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onIndexChanged,
  }) : assert(items.length > 0),
       assert(initialIndex >= 0 && initialIndex < items.length);

  final List<MediaViewerItem> items;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _ResolvedMedia {
  const _ResolvedMedia({required this.index, required this.builder});

  final int index;
  final MediaVisualBuilder builder;
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _pageController;
  late final Signal<int> _currentIndex;
  final Signal<_ResolvedMedia?> _resolvedMedia = signal(null);
  final Signal<bool> _controlsVisible = signal(true);
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = signal(widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFullResolution(widget.initialIndex);
    });
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFullResolution(int index) async {
    final generation = ++_loadGeneration;
    _resolvedMedia.value = null;
    final builder = await widget.items[index].loadFullResolution();
    if (!mounted ||
        generation != _loadGeneration ||
        _currentIndex.peek() != index) {
      return;
    }
    _resolvedMedia.value = _ResolvedMedia(index: index, builder: builder);
  }

  void _onPageChanged(int index) {
    if (_currentIndex.peek() == index) return;
    _currentIndex.value = index;
    widget.onIndexChanged?.call(index);
    _loadFullResolution(index);
  }

  void _toggleControls() {
    _controlsVisible.value = !_controlsVisible.peek();
  }

  void _dismiss() {
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) navigator!.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('media-viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            key: const Key('media-gesture-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: PageView.builder(
              key: const Key('media-page-view'),
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.items.length,
              itemBuilder: (context, index) => _MediaPage(
                item: widget.items[index],
                index: index,
                resolvedMedia: _resolvedMedia,
              ),
            ),
          ),
          _MediaTopControls(
            currentIndex: _currentIndex,
            visible: _controlsVisible,
            itemCount: widget.items.length,
            onDismiss: _dismiss,
          ),
          _MediaCaptionOverlay(
            currentIndex: _currentIndex,
            visible: _controlsVisible,
            items: widget.items,
          ),
        ],
      ),
    );
  }
}

class _MediaPage extends StatelessWidget {
  const _MediaPage({
    required this.item,
    required this.index,
    required this.resolvedMedia,
  });

  final MediaViewerItem item;
  final int index;
  final ReadonlySignal<_ResolvedMedia?> resolvedMedia;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: item.semanticLabel,
      image: true,
      child: Stack(
        key: Key('media-page-${item.id}'),
        fit: StackFit.expand,
        children: <Widget>[
          Hero(
            tag: item.heroTag,
            child: RepaintBoundary(
              child: KeyedSubtree(
                key: Key('media-thumbnail-${item.id}'),
                child: item.thumbnailBuilder(context),
              ),
            ),
          ),
          SignalBuilder(
            builder: (context) {
              final resolved = resolvedMedia.value;
              if (resolved == null || resolved.index != index) {
                return const SizedBox.shrink();
              }
              return RepaintBoundary(
                child: AnimatedOpacity(
                  key: Key('media-full-${item.id}'),
                  opacity: 1,
                  duration: KiteMotion.resolve(context, KiteMotion.fast),
                  curve: KiteMotion.standardCurve,
                  child: resolved.builder(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MediaTopControls extends StatelessWidget {
  const _MediaTopControls({
    required this.currentIndex,
    required this.visible,
    required this.itemCount,
    required this.onDismiss,
  });

  final ReadonlySignal<int> currentIndex;
  final ReadonlySignal<bool> visible;
  final int itemCount;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isVisible = visible.value;
        final index = currentIndex.value;
        return IgnorePointer(
          ignoring: !isVisible,
          child: AnimatedOpacity(
            key: const Key('media-top-controls'),
            opacity: isVisible ? 1 : 0,
            duration: KiteMotion.resolve(context, KiteMotion.standard),
            curve: KiteMotion.standardCurve,
            child: Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KiteSpacing.sm,
                    KiteSpacing.sm,
                    KiteSpacing.sm,
                    0,
                  ),
                  child: Row(
                    children: <Widget>[
                      _MediaControlButton(
                        key: const Key('media-close'),
                        tooltip: 'Close media viewer',
                        icon: Icons.close_rounded,
                        onPressed: onDismiss,
                      ),
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(KiteRadii.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KiteSpacing.sm,
                            vertical: KiteSpacing.xs,
                          ),
                          child: Text(
                            '${index + 1} of $itemCount',
                            key: const Key('media-counter'),
                            style: KiteTypography.metadata.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 48, height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MediaControlButton extends StatelessWidget {
  const _MediaControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black.withValues(alpha: 0.58),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MediaCaptionOverlay extends StatelessWidget {
  const _MediaCaptionOverlay({
    required this.currentIndex,
    required this.visible,
    required this.items,
  });

  final ReadonlySignal<int> currentIndex;
  final ReadonlySignal<bool> visible;
  final List<MediaViewerItem> items;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isVisible = visible.value;
        final item = items[currentIndex.value];
        final caption = item.caption;
        if (caption == null) return const SizedBox.shrink();

        return IgnorePointer(
          child: AnimatedOpacity(
            key: const Key('media-caption-overlay'),
            opacity: isVisible ? 1 : 0,
            duration: KiteMotion.resolve(context, KiteMotion.standard),
            curve: KiteMotion.standardCurve,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.74),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      KiteSpacing.lg,
                      KiteSpacing.xxl,
                      KiteSpacing.lg,
                      KiteSpacing.lg,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        key: const Key('media-caption'),
                        text: TextSpan(
                          style: KiteTypography.body.copyWith(
                            color: Colors.white,
                          ),
                          children: <InlineSpan>[caption],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
