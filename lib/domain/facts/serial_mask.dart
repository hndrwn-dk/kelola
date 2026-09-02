const serialMaskPrefix = '···· ';

const revealedSerialAuditTitle = 'Revealed serial number';

const revealedSerialAuditCommand = 'serial-reveal';

/// Masks a hardware serial for the details screen. Empty values are omitted.
String? maskSerial(String? serial) {
  final trimmed = serial?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return '$serialMaskPrefix${trimmed.length <= 4 ? trimmed : trimmed.substring(trimmed.length - 4)}';
}
