import 'package:flutter_test/flutter_test.dart';
import 'package:xp_p323b_windows/main.dart';

void main() {
  testWidgets('shows XP-P323B printer management screen', (tester) async {
    await tester.pumpWidget(const XpPrinterWindowsApp());
    await tester.pumpAndSettle();

    expect(find.text('Xprinter XP-P323B'), findsOneWidget);

    // The home screen uses a lazy ListView, so scroll to lower sections
    // before asserting that their widgets have been built.
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('تعريف Windows الرسمي'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('تعريف Windows الرسمي'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('فتح تعريف XP-P323B الرسمي'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('فتح تعريف XP-P323B الرسمي'), findsOneWidget);
  });
}
