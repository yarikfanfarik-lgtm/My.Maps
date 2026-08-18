import 'package:flutter_test/flutter_test.dart';
import 'package:navar/main.dart';

void main() {
  testWidgets('NavAR starts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const NavArApp());
    await tester.pump();

    expect(find.byType(NavArApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Карта'), findsOneWidget);
  });
}
