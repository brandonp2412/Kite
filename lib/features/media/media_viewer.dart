import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kite/design/kite_tokens.dart';
import 'package:signals/signals_flutter.dart';

typedef MediaVisualBuilder = Widget Function(BuildContext context);
typedef MediaFullResolutionLoader = Future<MediaVisualBuilder> Function();
typedef MediaViewerActionHandler = Future<void> Function(MediaViewerItem item);

enum _MediaViewerAction { save, share }

@immutable
class _PendingMediaAction {
  const _PendingMediaAction({required this.itemId, required this.action});

  final String itemId;
  final _MediaViewerAction action;
}

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
    MediaViewerActionHandler? onSave,
    MediaViewerActionHandler? onShare,
  }) : super(
         opaque: true,
         barrierDismissible: false,
         transitionDuration: KiteMotion.deliberate,
         reverseTransitionDuration: KiteMotion.standard,
         pageBuilder: (context, animation, secondaryAnimation) => MediaViewer(
           items: items,
           initialIndex: initialIndex,
           onIndexChanged: onIndexChanged,
           onSave: onSave,
           onShare: onShare,
         ),
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           return child;
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
    this.onSave,
    this.onShare,
  }) : assert(items.length > 0),
       assert(initialIndex >= 0 && initialIndex < items.length);

  final List<MediaViewerItem> items;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;
  final MediaViewerActionHandler? onSave;
  final MediaViewerActionHandler? onShare;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _ResolvedMedia {
  const _ResolvedMedia({required this.index, required this.builder});

  final int index;
  final MediaVisualBuilder builder;
}

class _MediaViewerState extends State<MediaViewer> {
  static const double _dismissThreshold = 112;

  late final PageController _pageController;
  late final Signal<int> _currentIndex;
  final Signal<_ResolvedMedia?> _resolvedMedia = signal(null);
  final Signal<bool> _controlsVisible = signal(true);
  final Signal<double> _dismissOffset = signal(0);
  final Signal<bool> _isDismissDragging = signal(false);
  final Signal<_PendingMediaAction?> _pendingAction = signal(null);
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _routeAnimationListener;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = signal(widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadInitialFullResolution();
    });
  }

  void _loadInitialFullResolution() {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _loadFullResolution(widget.initialIndex);
      return;
    }

    void listener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      _routeAnimation = null;
      _routeAnimationListener = null;
      if (mounted) _loadFullResolution(widget.initialIndex);
    }

    _routeAnimation = animation;
    _routeAnimationListener = listener;
    animation.addStatusListener(listener);
  }

  @override
  void dispose() {
    final animation = _routeAnimation;
    final listener = _routeAnimationListener;
    if (animation != null && listener != null) {
      animation.removeStatusListener(listener);
    }
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
    if (_isDismissDragging.peek()) return;
    _controlsVisible.value = !_controlsVisible.peek();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _isDismissDragging.value = true;
    _controlsVisible.value = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final nextOffset = _dismissOffset.peek() + details.delta.dy;
    _dismissOffset.value = nextOffset.clamp(-240.0, 240.0);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDismissDragging.value = false;
    final offset = _dismissOffset.peek();
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss =
        offset.abs() >= _dismissThreshold || velocity.abs() >= 850;
    if (shouldDismiss) {
      _dismiss();
      return;
    }
    _dismissOffset.value = 0;
    _controlsVisible.value = true;
  }

  void _dismiss() {
    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) navigator!.pop();
  }

  void _movePage(int delta) {
    final target = (_currentIndex.peek() + delta).clamp(
      0,
      widget.items.length - 1,
    );
    if (target == _currentIndex.peek()) return;
    final duration = KiteMotion.resolve(context, KiteMotion.standard);
    if (duration == Duration.zero) {
      _pageController.jumpToPage(target);
      return;
    }
    _pageController.animateToPage(
      target,
      duration: duration,
      curve: KiteMotion.standardCurve,
    );
  }

  Future<void> _runAction(
    _MediaViewerAction action,
    MediaViewerItem item,
    MediaViewerActionHandler handler,
  ) async {
    if (_pendingAction.peek() != null) return;
    _pendingAction.value = _PendingMediaAction(itemId: item.id, action: action);
    try {
      await handler(item);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            action == _MediaViewerAction.save ? 'Media saved' : 'Media shared',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            action == _MediaViewerAction.save
                ? 'Could not save media'
                : 'Could not share media',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) _pendingAction.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _movePage(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _movePage(1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: const Key('media-viewer'),
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                key: const Key('media-gesture-surface'),
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: SignalBuilder(
                  builder: (context) {
                    final offset = _dismissOffset.value;
                    final isDragging = _isDismissDragging.value;
                    return AnimatedSlide(
                      key: const Key('media-dismiss-slide'),
                      offset: Offset(
                        0,
                        offset / MediaQuery.sizeOf(context).height,
                      ),
                      duration: isDragging
                          ? Duration.zero
                          : KiteMotion.resolve(context, KiteMotion.standard),
                      curve: KiteMotion.standardCurve,
                      child: RepaintBoundary(
                        child: PageView.builder(
                          key: const Key('media-page-view'),
                          controller: _pageController,
                          onPageChanged: _onPageChanged,
                          itemCount: widget.items.length,
                          itemBuilder: (context, index) => _MediaPage(
                            item: widget.items[index],
                            index: index,
                            itemCount: widget.items.length,
                            resolvedMedia: _resolvedMedia,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _MediaTopControls(
                currentIndex: _currentIndex,
                visible: _controlsVisible,
                dragging: _isDismissDragging,
                pendingAction: _pendingAction,
                items: widget.items,
                onDismiss: _dismiss,
                onSave: widget.onSave,
                onShare: widget.onShare,
                onRunAction: _runAction,
              ),
              _MediaCaptionOverlay(
                currentIndex: _currentIndex,
                visible: _controlsVisible,
                dragging: _isDismissDragging,
                items: widget.items,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPage extends StatelessWidget {
  const _MediaPage({
    required this.item,
    required this.index,
    required this.itemCount,
    required this.resolvedMedia,
  });

  final MediaViewerItem item;
  final int index;
  final int itemCount;
  final ReadonlySignal<_ResolvedMedia?> resolvedMedia;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${item.semanticLabel}, ${index + 1} of $itemCount',
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
    required this.dragging,
    required this.pendingAction,
    required this.items,
    required this.onDismiss,
    required this.onSave,
    required this.onShare,
    required this.onRunAction,
  });

  final ReadonlySignal<int> currentIndex;
  final ReadonlySignal<bool> visible;
  final ReadonlySignal<bool> dragging;
  final ReadonlySignal<_PendingMediaAction?> pendingAction;
  final List<MediaViewerItem> items;
  final VoidCallback onDismiss;
  final MediaViewerActionHandler? onSave;
  final MediaViewerActionHandler? onShare;
  final Future<void> Function(
    _MediaViewerAction action,
    MediaViewerItem item,
    MediaViewerActionHandler handler,
  )
  onRunAction;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isVisible = visible.value;
        final isDragging = dragging.value;
        final index = currentIndex.value;
        final item = items[index];
        final pending = pendingAction.value;
        final actionBlocked = pending != null;
        final saveBusy =
            pending?.itemId == item.id &&
            pending?.action == _MediaViewerAction.save;
        final shareBusy =
            pending?.itemId == item.id &&
            pending?.action == _MediaViewerAction.share;
        return IgnorePointer(
          ignoring: !isVisible,
          child: AnimatedOpacity(
            key: const Key('media-top-controls'),
            opacity: isVisible ? 1 : 0,
            duration: isDragging
                ? Duration.zero
                : KiteMotion.resolve(context, KiteMotion.standard),
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
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _MediaControlButton(
                            key: const Key('media-close'),
                            tooltip: 'Close media viewer',
                            icon: Icons.close_rounded,
                            onPressed: onDismiss,
                          ),
                        ),
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
                              '${index + 1} of ${items.length}',
                              key: const Key('media-counter'),
                              style: KiteTypography.metadata.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (onSave != null)
                                _MediaControlButton(
                                  key: const Key('media-save'),
                                  tooltip: saveBusy
                                      ? 'Saving media'
                                      : 'Save media',
                                  icon: Icons.download_rounded,
                                  busy: saveBusy,
                                  onPressed: actionBlocked
                                      ? null
                                      : () => onRunAction(
                                          _MediaViewerAction.save,
                                          item,
                                          onSave!,
                                        ),
                                ),
                              if (onShare != null) ...<Widget>[
                                if (onSave != null)
                                  const SizedBox(width: KiteSpacing.xs),
                                _MediaControlButton(
                                  key: const Key('media-share'),
                                  tooltip: shareBusy
                                      ? 'Sharing media'
                                      : 'Share media',
                                  icon: Icons.share_rounded,
                                  busy: shareBusy,
                                  onPressed: actionBlocked
                                      ? null
                                      : () => onRunAction(
                                          _MediaViewerAction.share,
                                          item,
                                          onShare!,
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

class _MediaControlButton extends StatelessWidget {
  const _MediaControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 48,
          child: IconButton(
            tooltip: tooltip,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black.withValues(alpha: 0.58),
            ),
            onPressed: onPressed,
            icon: busy
                ? const SizedBox.square(
                    key: Key('media-action-progress'),
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon),
          ),
        ),
      ),
    );
  }
}

class _MediaCaptionOverlay extends StatelessWidget {
  const _MediaCaptionOverlay({
    required this.currentIndex,
    required this.visible,
    required this.dragging,
    required this.items,
  });

  final ReadonlySignal<int> currentIndex;
  final ReadonlySignal<bool> visible;
  final ReadonlySignal<bool> dragging;
  final List<MediaViewerItem> items;

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isVisible = visible.value;
        final isDragging = dragging.value;
        final item = items[currentIndex.value];
        final caption = item.caption;
        if (caption == null) return const SizedBox.shrink();

        return IgnorePointer(
          child: AnimatedOpacity(
            key: const Key('media-caption-overlay'),
            opacity: isVisible ? 1 : 0,
            duration: isDragging
                ? Duration.zero
                : KiteMotion.resolve(context, KiteMotion.standard),
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
