import 'package:flutter_test/flutter_test.dart';
import 'package:navar/main.dart';

void main() {
  testWidgets('NavAR starts on the map screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NavArApp());

    expect(find.text('Карта'), findsOneWidget);
    expect(find.text('Транспорт'), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
  });
}
