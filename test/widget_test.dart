import 'package:flutter_test/flutter_test.dart';
import 'package:xp_p323b_windows/main.dart';

void main() {
  testWidgets('shows XP-P323B printer management screen', (tester) async {
    await tester.pumpWidget(const XpPrinterWindowsApp());
    expect(find.text('Xprinter XP-P323B'), findsOneWidget);
    expect(find.text('تعريف Windows الرسمي'), findsOneWidget);
    expect(find.text('إعدادات الطباعة'), findsOneWidget);
  });
}
