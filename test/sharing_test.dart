import 'package:flutter_test/flutter_test.dart';
import 'package:zest/kodo/sharing.dart';

void main() {
  test('shared webpage preserves URL and supplied title', () {
    expect(
      parseKodoShare({
        'text': 'https://example.com/article?a=1&b=2',
        'title': 'Článek',
      }),
      {'title': 'Článek', 'body': 'https://example.com/article?a=1&b=2'},
    );
  });
  test('ordinary text and a colon are allowed', () {
    expect(
      parseKodoShare({'text': 'Úkol: zavolat klientovi'})?['title'],
      'Úkol: zavolat klientovi',
    );
  });
  test('unsafe schemes and oversized input are rejected', () {
    for (final text in [
      'javascript:alert(1)',
      'file:///etc/passwd',
      'data:text/html,secret',
      'ftp://example.com',
      'kodoukoly://share',
      'https://example.com\njavascript:alert(1)',
      'x' * 15001,
      '  ',
    ]) {
      expect(
        parseKodoShare({'text': text}),
        null,
        reason: text.substring(0, text.length.clamp(0, 80)),
      );
    }
  });
  test('long titles are bounded without changing link body', () {
    final v = parseKodoShare({
      'text': 'https://example.com',
      'title': 'a' * 300,
    });
    expect(v?['title']?.length, 200);
    expect(v?['body'], 'https://example.com');
  });
  test('malformed native payloads do not create requests', () {
    for (final value in [
      null,
      'url',
      {'text': 42},
      {},
    ]) {
      expect(parseKodoShare(value), null);
    }
  });
}
