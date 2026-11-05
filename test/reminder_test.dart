import 'package:flutter_test/flutter_test.dart';
import 'package:zest/kodo/reminder.dart';

void main() {
  test('a title edit preserves server delivery and token', () {
    final m = {
      'due': '2026-11-20T09:00:00+00:00',
      'reminder_delivery': 'server',
      'reminder_token': 'revision',
      'tags': ['Keep'],
    };
    final next = reminderMetadata(
      m,
      DateTime.parse('2026-11-20T10:00:00+01:00'),
    );
    expect(next['reminder_delivery'], 'server');
    expect(next['reminder_token'], 'revision');
    expect(usesDeviceReminder(next), false);
    expect(next['tags'], ['Keep']);
  });
  test('an explicit mobile date change uses native reminder', () {
    final next = reminderMetadata({
      'due': '2026-11-20T09:00:00Z',
      'reminder_delivery': 'server',
      'reminder_token': 'revision',
    }, DateTime.parse('2026-11-21T09:00:00Z'));
    expect(usesDeviceReminder(next), true);
    expect(next['reminder_token'], null);
  });
  test('clearing a deadline clears the server token', () {
    expect(
      reminderMetadata({
        'due': '2026-11-20T09:00:00Z',
        'reminder_delivery': 'server',
      }, null)['due'],
      null,
    );
  });
  test('timestamps from server retain their instant in local display', () {
    final raw = DateTime.parse('2026-11-20T09:00:00+00:00');
    final local = raw.toLocal();
    expect(local.isUtc, false);
    expect(local.isAtSameMomentAs(raw), true);
  });
  test('previous app dates default to native delivery', () {
    expect(usesDeviceReminder({}), true);
  });
}
