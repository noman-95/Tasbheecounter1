import 'package:flutter_test/flutter_test.dart';
import 'package:tasbheecounter/main.dart';

void main() {
  testWidgets('Tasbih app starts', (tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Tasbih Counter'), findsOneWidget);
  });
}
