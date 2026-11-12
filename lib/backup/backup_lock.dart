class BackupLock {
  Object? _owner;

  bool get isHeld => _owner != null;

  bool heldByOther(Object me) => _owner != null && !identical(_owner, me);

  bool acquire(Object owner) {
    if (_owner != null) return false;
    _owner = owner;
    return true;
  }

  void release(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }
}
