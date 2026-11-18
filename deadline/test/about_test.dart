import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deadline/theme.dart';
import 'package:deadline/ui/about_page.dart';
import 'package:deadline/ui/privacy_page.dart';
import 'package:deadline/ui/powered_by_footer.dart';
import 'package:deadline/utils/company.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: child,
    );

void main() {
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('deadline/platform'),
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'appVersion':
            return '1.0.24+25';
          case 'openUrl':
            return true;
          default:
            return null;
        }
      },
    );
  });

  testWidgets('About page shows app name, version and website', (tester) async {
    await tester.pumpWidget(_wrap(const AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Deadlines&Notes'), findsOneWidget);
    expect(find.text('Version 1.0.24+25'), findsOneWidget);
    expect(find.text(Company.websiteLabel), findsOneWidget);
    expect(calls.any((c) => c.method == 'appVersion'), isTrue);
  });

  testWidgets('tapping the website row opens teto.co.ke', (tester) async {
    await tester.pumpWidget(_wrap(const AboutPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-website')));
    await tester.pumpAndSettle();

    final openCalls = calls.where((c) => c.method == 'openUrl').toList();
    expect(openCalls, hasLength(1));
    expect(openCalls.single.arguments, Company.websiteUrl);
  });

  testWidgets('tapping the footer opens teto.co.ke', (tester) async {
    await tester.pumpWidget(
      _wrap(const Scaffold(body: Center(child: PoweredByFooter()))),
    );

    await tester
        .tap(find.textContaining('teto technologies', findRichText: true));
    await tester.pumpAndSettle();

    final openCalls = calls.where((c) => c.method == 'openUrl').toList();
    expect(openCalls, hasLength(1));
    expect(openCalls.single.arguments, Company.websiteUrl);
  });

  testWidgets('tapping the privacy row opens the privacy policy',
      (tester) async {
    await tester.pumpWidget(_wrap(const AboutPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('about-privacy')));
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
  });
}
