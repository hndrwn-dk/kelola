class EphemeralPassword {
  String? _value;

  void set(String value) {
    _value = value;
  }

  String? read() => _value;

  void clear() {
    _value = null;
  }

  bool get isSet => _value != null;

  @override
  String toString() => 'EphemeralPassword(isSet: $isSet)';
}
