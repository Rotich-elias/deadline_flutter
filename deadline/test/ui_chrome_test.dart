import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deadline/theme.dart';
import 'package:deadline/ui/loading_page.dart';
import 'package:deadline/ui/powered_by_footer.dart';

Widget _wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: child,
    );

void main() {
  testWidgets('footer credits Teto Technologies', (tester) async {
    await tester.pumpWidget(
      _wrap(const Scaffold(body: Center(child: PoweredByFooter()))),
    );

    expect(
      find.textContaining('Powered by', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('teto technologies', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('loading page shows the brand, a spinner and the credit',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2220); // Note 9 panel
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const LoadingPage()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Deadlines&Notes'), findsOneWidget);
    expect(find.text('Sorting what is due next.'), findsOneWidget);
    expect(find.text('Getting things ready'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The credit line is pinned to the bottom of the screen, below the copy.
    final footer = tester.getCenter(
        find.textContaining('teto technologies', findRichText: true));
    final title = tester.getCenter(find.text('Deadlines&Notes'));
    expect(footer.dy, greaterThan(title.dy));
    expect(footer.dy, greaterThan(845 - 60));

    await tester.pumpWidget(const SizedBox.shrink()); // stop the pulse ticker
  });

  testWidgets('loading page block is centred like the native splash',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2220); // Note 9 panel
    tester.view.devicePixelRatio = 1.925;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const LoadingPage()));
    await tester.pump(const Duration(milliseconds: 100));

    final screen = tester.getSize(find.byType(LoadingPage));
    final content = tester.getRect(find.byKey(LoadingPage.contentKey));

    // The splash artwork is drawn centred by Android; if the live block drifts
    // from the window centre the hand-off becomes a visible jump.
    expect((content.center.dy - screen.height / 2).abs(), lessThan(1.5));
    expect((content.center.dx - screen.width / 2).abs(), lessThan(1.5));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading page still fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(640, 960); // 320 x 480 logical
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const LoadingPage()));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('teto technologies', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('boot error offers a retry and keeps the credit', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(BootErrorView(
          detail: 'database is locked', onRetry: () => retries++)),
    );

    expect(find.text('Could not start'), findsOneWidget);
    expect(find.text('database is locked'), findsOneWidget);
    expect(
      find.textContaining('teto technologies', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });
}
