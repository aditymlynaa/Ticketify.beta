import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ticket_app/main.dart';

void main() {
  testWidgets('halaman login tampil saat aplikasi dibuka tanpa sesi', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Masuk ke akun'), findsOneWidget);
    expect(find.text('Daftar sekarang'), findsOneWidget);
  });
}
