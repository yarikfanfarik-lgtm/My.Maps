import 'package:flutter_test/flutter_test.dart';
import 'package:navar/main.dart';

void main() {
  test('NavAR root widget is defined', () {
    const app = NavArApp();
    expect(app, isA<NavArApp>());
  });
}
