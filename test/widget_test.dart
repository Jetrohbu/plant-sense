import 'package:flutter_test/flutter_test.dart';
import 'package:plant_sense/main.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const PlantSenseApp());
    expect(find.text('PlantSense'), findsOneWidget);
  });
}
