import 'package:flutter_test/flutter_test.dart';
import 'package:somityhub_app/main.dart';

void main() {
  testWidgets('shows configuration guidance when build variables are absent', (tester) async {
    await tester.pumpWidget(const SomityHubApp());
    expect(find.text('SomityHub'), findsOneWidget);
    expect(find.textContaining('Supabase configuration is missing'), findsOneWidget);
  });
}
