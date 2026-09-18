mixin AsyncControllerLifecycle {
  bool _controllerDisposed = false;
  int _controllerLifecycleGeneration = 0;

  bool get controllerDisposed => _controllerDisposed;

  int captureControllerLifecycle() => _controllerLifecycleGeneration;

  bool isControllerLifecycleCurrent(int generation) {
    return !_controllerDisposed && generation == _controllerLifecycleGeneration;
  }

  bool disposeControllerLifecycle() {
    if (_controllerDisposed) return false;
    _controllerDisposed = true;
    _controllerLifecycleGeneration += 1;
    return true;
  }
}
