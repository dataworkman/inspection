import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:store_inspection_mobile/annotations/annotation_state.dart';
import 'package:store_inspection_mobile/screens/annotation_screen.dart';

/// A solid-color photo of the given size, encoded as PNG.
Future<Uint8List> solidPng(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = color);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> decode(Uint8List bytes) => decodeImageFromList(bytes);

Future<Color> pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(255, data.getUint8(offset), data.getUint8(offset + 1),
      data.getUint8(offset + 2));
}

bool isRed(Color c) => c.r > 0.8 && c.g < 0.3 && c.b < 0.3;
bool isBlue(Color c) => c.b > 0.8 && c.r < 0.3 && c.g < 0.3;

AnnotationMark stroke(double x0, double y0, double x1, double y1,
        {double width = 6, Color color = const Color(0xffff0000)}) =>
    AnnotationMark(
      x: x0,
      y: y0,
      endX: x1,
      endY: y1,
      points: [Offset(x0, y0), Offset(x1, y1)],
      note: '',
      tool: AnnotationTool.pen,
      color: color,
      strokeWidth: width,
    );

void main() {
  group('geometry', () {
    test('a wide photo in a tall canvas is letterboxed top and bottom', () {
      final rect = AnnotationGeometry.imageRect(
          const Size(400, 200), const Size(300, 600));

      expect(rect.width, 300);
      expect(rect.height, 150);
      expect(rect.center, const Offset(150, 300));
    });

    test('a tall photo in a wide canvas is letterboxed left and right', () {
      final rect = AnnotationGeometry.imageRect(
          const Size(200, 400), const Size(600, 300));

      expect(rect.height, 300);
      expect(rect.width, 150);
      expect(rect.center, const Offset(300, 150));
    });

    test('an empty size gives an empty rect', () {
      expect(AnnotationGeometry.imageRect(Size.zero, const Size(10, 10)),
          Rect.zero);
    });
  });

  group('rendering the annotated image', () {
    testWidgets('draws the marks onto the photo at its own resolution',
        (tester) async {
      await tester.runAsync(() async {
        final photo =
            await decode(await solidPng(200, 100, const Color(0xff0000ff)));

        final bytes = await AnnotationRenderer.render(
          image: photo,
          marks: [stroke(0.1, 0.5, 0.9, 0.5)],
          displayWidth: 200,
        );
        final result = await decode(bytes!);

        expect([result.width, result.height], [200, 100]);
        expect(isRed(await pixel(result, 100, 50)), isTrue,
            reason: 'on the stroke');
        expect(isBlue(await pixel(result, 100, 10)), isTrue,
            reason: 'the photo elsewhere');
        expect(isBlue(await pixel(result, 2, 50)), isTrue,
            reason: 'before the stroke starts');
      });
    });

    testWidgets('large photos are scaled down and strokes scale with them',
        (tester) async {
      await tester.runAsync(() async {
        final photo =
            await decode(await solidPng(4096, 2048, const Color(0xff0000ff)));

        // Drawn on a 400 px wide preview with a 10 px stroke.
        final bytes = await AnnotationRenderer.render(
          image: photo,
          marks: [stroke(0.1, 0.5, 0.9, 0.5, width: 10)],
          displayWidth: 400,
        );
        final result = await decode(bytes!);

        expect([result.width, result.height], [2048, 1024]);
        // 10 px on 400 px becomes 51 px on 2048 px: 20 px from the line is still painted.
        expect(isRed(await pixel(result, 1024, 512 - 20)), isTrue);
        expect(isBlue(await pixel(result, 1024, 512 - 60)), isTrue);
      });
    });

    testWidgets('the letterbox is not part of the result', (tester) async {
      await tester.runAsync(() async {
        final photo =
            await decode(await solidPng(300, 100, const Color(0xff00ff00)));

        final bytes = await AnnotationRenderer.render(
            image: photo,
            marks: [stroke(0.2, 0.5, 0.8, 0.5)],
            displayWidth: 300);
        final result = await decode(bytes!);

        expect(result.width / result.height, closeTo(3, 0.01));
      });
    });
  });

  group('the annotation screen', () {
    late Uint8List photoBytes;
    AnnotationResult? result;
    var finished = false;

    Future<void> open(WidgetTester tester,
        {int width = 320, int height = 220}) async {
      result = null;
      finished = false;
      await tester.runAsync(() async {
        photoBytes = await solidPng(width, height, const Color(0xff0000ff));
      });
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<AnnotationResult>(
                    MaterialPageRoute(
                      builder: (_) => AnnotationScreen(
                        file: XFile.fromData(photoBytes,
                            name: 'p.png', mimeType: 'image/png'),
                      ),
                    ),
                  );
                  finished = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.text('Annotate photo'), findsOneWidget);
    }

    Future<Rect> photoRect(WidgetTester tester) async =>
        tester.getRect(find.byType(Image));

    Future<void> done(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
    }

    List<Map<String, dynamic>> marks() =>
        (jsonDecode(result!.payload)['marks'] as List)
            .cast<Map<String, dynamic>>();

    testWidgets('marks are stored relative to the photo, not the canvas',
        (tester) async {
      await open(tester);
      final rect = await photoRect(tester);

      // Drag from the photo's center to a point a quarter across.
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.center + Offset(rect.width / 4, 0));
      await gesture.up();
      await tester.pump();
      await done(tester);

      final mark = marks().single;
      expect(mark['x'], closeTo(0.5, 0.02));
      expect(mark['y'], closeTo(0.5, 0.02));
      expect(mark['end_x'], closeTo(0.75, 0.03));
      final payload = jsonDecode(result!.payload) as Map<String, dynamic>;
      expect(payload['image'], {'width': 320.0, 'height': 220.0});
    });

    testWidgets('drawing in the letterbox does nothing', (tester) async {
      await open(tester,
          width: 220, height: 320); // portrait: bars at the sides
      final rect = await photoRect(tester);
      expect(rect.left, greaterThan(20),
          reason: 'the photo is letterboxed at the sides');

      final gesture =
          await tester.startGesture(Offset(rect.left - 15, rect.center.dy));
      await gesture.moveTo(Offset(rect.left + 60, rect.center.dy));
      await gesture.up();
      await tester.tapAt(Offset(rect.left - 10, rect.top + 20));
      await tester.pump();
      await done(tester);

      expect(marks(), isEmpty);
      expect(result!.file, isNull,
          reason: 'nothing drawn, so the original is used');
    });

    testWidgets('finishing with marks gives an annotated copy at photo size',
        (tester) async {
      await open(tester);
      final rect = await photoRect(tester);

      final gesture =
          await tester.startGesture(rect.topLeft + const Offset(20, 20));
      await gesture.moveTo(rect.bottomRight - const Offset(20, 20));
      await gesture.up();
      await tester.pump();
      await done(tester);

      final file = result!.file!;
      await tester.runAsync(() async {
        final annotated = await decode(await file.readAsBytes());
        expect([annotated.width, annotated.height], [320, 220]);
      });
    });

    testWidgets('the text tool asks what to write', (tester) async {
      await open(tester);
      final rect = await photoRect(tester);

      await tester.tap(find.byTooltip('Text'));
      await tester.pump();
      await tester.tapAt(rect.center);
      await tester.pumpAndSettle();
      expect(find.text('Add text'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Cracked seal');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await done(tester);

      final mark = marks().single;
      expect(mark['tool'], 'text');
      expect(mark['note'], 'Cracked seal');
      expect(mark['x'], closeTo(0.5, 0.02));
    });

    testWidgets('cancelling the text prompt adds nothing', (tester) async {
      await open(tester);
      final rect = await photoRect(tester);

      await tester.tap(find.byTooltip('Text'));
      await tester.pump();
      await tester.tapAt(rect.center);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await done(tester);

      expect(marks(), isEmpty);
    });

    testWidgets('the chosen color is used for new marks', (tester) async {
      await open(tester);
      final rect = await photoRect(tester);

      await tester.tap(find.byKey(const ValueKey('color-ff1e88e5')));
      await tester.pump();
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.center + const Offset(40, 0));
      await gesture.up();
      await tester.pump();
      await done(tester);

      expect(marks().single['color'], 0xff1e88e5);
    });
  });

  test('the default color is the first swatch, so it starts out selected', () {
    expect(AnnotationState().color.toARGB32(),
        AnnotationToolbar.colors.first.toARGB32());
  });
}
