import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ticket_app/utils/date_formatter.dart';

void main() {
  group('formatDateTime', () {
    test('memformat ISO-8601 tanpa timezone', () {
      expect(formatDateTime('2026-05-28T09:42:00'), '28 Mei 2026, 09:42');
    });

    test('mengembalikan teks asli jika format tidak dikenali', () {
      expect(formatDateTime('bukan tanggal'), 'bukan tanggal');
    });

    test('nilai kosong menghasilkan string kosong', () {
      expect(formatDateTime(null), '');
      expect(formatDateTime(''), '');
    });
  });

  group('formatDate', () {
    test('memformat tanggal tanpa jam', () {
      expect(formatDate('2026-05-28T09:42:00'), '28 Mei 2026');
    });
  });
}
