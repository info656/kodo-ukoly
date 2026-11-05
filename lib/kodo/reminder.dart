/// Native reminders belong to dates explicitly set on this device. Portal dates
/// are delivered by the server through the owner's existing private ntfy channel.
Map<String, dynamic> reminderMetadata(
  Map<String, dynamic> current,
  DateTime? due,
) {
  final old = DateTime.tryParse(current['due'] as String? ?? '')?.toUtc();
  final next = due?.toUtc();
  final changed = old != next;
  return {
    ...current,
    'due': next?.toIso8601String(),
    if (changed) 'reminder_delivery': 'device',
    if (changed) 'reminder_token': null,
  };
}

bool usesDeviceReminder(Map<String, dynamic> metadata) =>
    metadata['reminder_delivery'] != 'server';
