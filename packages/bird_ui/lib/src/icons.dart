import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// The icons of the interface, drawn on a 16 by 16 grid as Firefox's are.
enum BirdGlyph {
  picker, inspector, console, debugger, network, styleEditor, performance,
  memory, storage, accessibility, application, close, meatball, dockBottom,
  dockLeft, dockRight, dockWindow, search, trash, filter, gear, plus, reload,
  chevronRight, chevronDown, chevronUp, twistyRight, twistyDown, pause, play,
  stepOver, stepIn, stepOut, deactivate, prettyPrint, eye, eyeOff, check,
  error, warning, info, prompt, result, command, folder, file, script, globe,
  copy, responsive, record, stop, importFile, save, sun, moon, print, target,
  database, cookie, paneToggle, rotate, sortUp, sortDown, circle, logpoint,
  blackbox, stopwatch, splitConsole, editorMode, domain, frame, image,
  // The browser's own.
  back, forward, home, star, starFilled, lock, lockOff, extension, download,
  menu, sidebar, tabs, pin, pinFilled, location, microphone, bell, shield,
  pictureInPicture, openExternal, update, help, computer, fullscreenExit,
  chevronUpDown, minus,
}

class BirdIcon extends StatelessWidget {
  const BirdIcon(this.glyph, {super.key, this.size = 16, this.color});

  final BirdGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GlyphPainter(glyph, color ?? context.bird.icon),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final BirdGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);
    void rect(double l, double t, double r, double b, [double radius = 1.5]) =>
        canvas.drawRRect(
          RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)),
          stroke,
        );
    void circle(double x, double y, double r, [Paint? paint]) =>
        canvas.drawCircle(Offset(x, y), r, paint ?? stroke);
    void poly(List<double> points, {bool close = false, Paint? paint}) {
      final path = Path()..moveTo(points[0], points[1]);
      for (var i = 2; i < points.length; i += 2) {
        path.lineTo(points[i], points[i + 1]);
      }
      if (close) path.close();
      canvas.drawPath(path, paint ?? stroke);
    }

    void text(String value, double size, [double dy = 0]) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: BirdFonts.mono,
            fontFamilyFallback: BirdFonts.monoFallback,
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(8 - painter.width / 2, 8 - painter.height / 2 + dy),
      );
      painter.dispose();
    }

    switch (glyph) {
      case BirdGlyph.picker:
        poly([6.5, 13, 3, 13, 2, 12, 2, 3, 3, 2, 12, 2, 13, 3, 13, 6.5]);
        poly([7.5, 7.5, 14, 10, 11.2, 11.2, 10, 14], close: true);
      case BirdGlyph.inspector:
        rect(2, 2, 14, 14);
        poly([7, 7, 12.5, 9.2, 10, 10, 9.2, 12.5], close: true);
      case BirdGlyph.console:
        rect(1.5, 2.5, 14.5, 13.5);
        poly([4, 6, 6.5, 8, 4, 10]);
        line(8, 10.5, 11.5, 10.5);
      case BirdGlyph.debugger:
        poly([2, 3.5, 9, 3.5, 14, 8, 9, 12.5, 2, 12.5], close: true);
      case BirdGlyph.network:
        line(2, 4, 11, 4);
        line(5, 8, 14, 8);
        line(2, 12, 9, 12);
      case BirdGlyph.styleEditor:
        text('{}', 11, -0.5);
      case BirdGlyph.performance:
        poly([1.5, 11, 5, 6, 7.5, 9.5, 11, 3.5, 14.5, 8]);
        line(1.5, 14, 14.5, 14);
      case BirdGlyph.memory:
        circle(8, 8, 6);
        line(8, 8, 8, 2.5);
        line(8, 8, 12.5, 11.5);
      case BirdGlyph.storage:
        canvas.drawOval(const Rect.fromLTRB(2.5, 2, 13.5, 6), stroke);
        line(2.5, 4, 2.5, 12);
        line(13.5, 4, 13.5, 12);
        canvas.drawArc(const Rect.fromLTRB(2.5, 10, 13.5, 14), 0, math.pi, false, stroke);
        canvas.drawArc(const Rect.fromLTRB(2.5, 6, 13.5, 10), 0, math.pi, false, stroke);
      case BirdGlyph.accessibility:
        circle(8, 3, 1.4, fill);
        line(2.5, 5.5, 13.5, 5.5);
        poly([5.5, 14.5, 7, 9.5, 7, 5.5]);
        poly([10.5, 14.5, 9, 9.5, 9, 5.5]);
      case BirdGlyph.application:
        rect(2, 2, 7, 7);
        rect(9, 2, 14, 7);
        rect(2, 9, 7, 14);
        rect(9, 9, 14, 14);
      case BirdGlyph.close:
        line(4, 4, 12, 12);
        line(12, 4, 4, 12);
      case BirdGlyph.meatball:
        circle(3, 8, 1.4, fill);
        circle(8, 8, 1.4, fill);
        circle(13, 8, 1.4, fill);
      case BirdGlyph.dockBottom:
        rect(1.5, 2.5, 14.5, 13.5);
        canvas.drawRect(const Rect.fromLTRB(2, 9, 14, 13), fill);
      case BirdGlyph.dockLeft:
        rect(1.5, 2.5, 14.5, 13.5);
        canvas.drawRect(const Rect.fromLTRB(2, 3, 6.5, 13), fill);
      case BirdGlyph.dockRight:
        rect(1.5, 2.5, 14.5, 13.5);
        canvas.drawRect(const Rect.fromLTRB(9.5, 3, 14, 13), fill);
      case BirdGlyph.dockWindow:
        rect(1.5, 4.5, 11.5, 13.5);
        poly([4.5, 4.5, 4.5, 2.5, 14.5, 2.5, 14.5, 10.5, 11.5, 10.5]);
      case BirdGlyph.search:
        circle(6.5, 6.5, 4);
        line(9.5, 9.5, 14, 14);
      case BirdGlyph.trash:
        line(2.5, 4, 13.5, 4);
        poly([6, 4, 6, 2.5, 10, 2.5, 10, 4]);
        poly([4, 4, 4.8, 14, 11.2, 14, 12, 4]);
        line(6.5, 6.5, 6.8, 11.5);
        line(9.5, 6.5, 9.2, 11.5);
      case BirdGlyph.filter:
        poly([2, 3, 14, 3, 9.5, 8.5, 9.5, 13.5, 6.5, 12, 6.5, 8.5], close: true);
      case BirdGlyph.gear:
        circle(8, 8, 2.2);
        circle(8, 8, 4.6);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(8 + 4.6 * math.cos(a), 8 + 4.6 * math.sin(a), 8 + 6.4 * math.cos(a), 8 + 6.4 * math.sin(a));
        }
      case BirdGlyph.plus:
        line(8, 3, 8, 13);
        line(3, 8, 13, 8);
      case BirdGlyph.reload:
        canvas.drawArc(const Rect.fromLTRB(3, 3, 13, 13), -0.2, math.pi * 1.7, false, stroke);
        poly([13.4, 2.8, 13.2, 7, 9.2, 6.4]);
      case BirdGlyph.chevronRight:
        poly([6, 4, 10, 8, 6, 12]);
      case BirdGlyph.chevronDown:
        poly([4, 6, 8, 10, 12, 6]);
      case BirdGlyph.chevronUp:
        poly([4, 10, 8, 6, 12, 10]);
      case BirdGlyph.twistyRight:
        poly([5.5, 4, 12, 8, 5.5, 12], close: true, paint: fill);
      case BirdGlyph.twistyDown:
        poly([4, 5.5, 12, 5.5, 8, 12], close: true, paint: fill);
      case BirdGlyph.pause:
        canvas.drawRect(const Rect.fromLTRB(4.5, 3, 6.8, 13), fill);
        canvas.drawRect(const Rect.fromLTRB(9.2, 3, 11.5, 13), fill);
      case BirdGlyph.play:
        poly([4.5, 3, 13, 8, 4.5, 13], close: true);
      case BirdGlyph.stepOver:
        canvas.drawArc(const Rect.fromLTRB(2.5, 3, 13, 12), math.pi * 1.08, math.pi * 0.86, false, stroke);
        poly([13.5, 3.5, 13, 7.5, 9.2, 6.6]);
        circle(8, 12.5, 1.7, fill);
      case BirdGlyph.stepIn:
        line(8, 1.5, 8, 8.5);
        poly([5, 6, 8, 9, 11, 6]);
        circle(8, 13, 1.7, fill);
      case BirdGlyph.stepOut:
        line(8, 2, 8, 9);
        poly([5, 5, 8, 2, 11, 5]);
        circle(8, 13, 1.7, fill);
      case BirdGlyph.deactivate:
        poly([2, 4.5, 9.5, 4.5, 13, 8, 9.5, 11.5, 2, 11.5], close: true);
        line(2.5, 13.5, 13.5, 2.5);
      case BirdGlyph.prettyPrint:
        text('{ }', 9);
      case BirdGlyph.eye:
      case BirdGlyph.eyeOff:
        final path = Path()
          ..moveTo(1.5, 8)
          ..quadraticBezierTo(8, 1.5, 14.5, 8)
          ..quadraticBezierTo(8, 14.5, 1.5, 8);
        canvas.drawPath(path, stroke);
        circle(8, 8, 2.2);
        if (glyph == BirdGlyph.eyeOff) line(2.5, 13.5, 13.5, 2.5);
      case BirdGlyph.check:
        poly([3, 8.5, 6.5, 12, 13, 4]);
      case BirdGlyph.error:
        circle(8, 8, 6.5, fill);
        final cross = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(5.7, 5.7), const Offset(10.3, 10.3), cross);
        canvas.drawLine(const Offset(10.3, 5.7), const Offset(5.7, 10.3), cross);
      case BirdGlyph.warning:
        poly([8, 1.5, 15, 14, 1, 14], close: true, paint: fill);
        final mark = Paint()
          ..color = const Color(0xFF3A3000)
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(8, 6), const Offset(8, 9.8), mark);
        canvas.drawCircle(const Offset(8, 12), 0.95, mark);
      case BirdGlyph.info:
        circle(8, 8, 6.5, fill);
        final mark = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(8, 7.5), const Offset(8, 11.5), mark);
        canvas.drawCircle(const Offset(8, 4.8), 1, mark);
      case BirdGlyph.prompt:
        poly([3.5, 4, 7.5, 8, 3.5, 12]);
        poly([8.5, 4, 12.5, 8, 8.5, 12]);
      case BirdGlyph.command:
        poly([6, 4, 10, 8, 6, 12]);
      case BirdGlyph.result:
        line(3, 8, 13, 8);
        poly([7, 4, 3, 8, 7, 12]);
      case BirdGlyph.folder:
        poly([1.5, 13, 1.5, 3, 6, 3, 7.5, 5, 14.5, 5, 14.5, 13], close: true);
      case BirdGlyph.file:
      case BirdGlyph.script:
        poly([3, 1.5, 9.5, 1.5, 13, 5, 13, 14.5, 3, 14.5], close: true);
        poly([9.5, 1.5, 9.5, 5, 13, 5]);
        if (glyph == BirdGlyph.script) text('JS', 5.5, 2);
      case BirdGlyph.globe:
      case BirdGlyph.domain:
        circle(8, 8, 6);
        canvas.drawOval(const Rect.fromLTRB(5, 2, 11, 14), stroke);
        line(2, 8, 14, 8);
      case BirdGlyph.copy:
        rect(5, 5, 13.5, 14);
        poly([3, 11, 2.5, 11, 2.5, 2, 11, 2, 11, 3]);
      case BirdGlyph.responsive:
        rect(1.5, 2.5, 10.5, 13.5);
        rect(9, 6, 14.5, 13.5);
      case BirdGlyph.record:
        circle(8, 8, 6);
        circle(8, 8, 3, fill);
      case BirdGlyph.stop:
        canvas.drawRRect(RRect.fromLTRBR(4, 4, 12, 12, const Radius.circular(1)), fill);
      case BirdGlyph.importFile:
        line(8, 2, 8, 10);
        poly([5, 7, 8, 10, 11, 7]);
        poly([2.5, 10.5, 2.5, 13.5, 13.5, 13.5, 13.5, 10.5]);
      case BirdGlyph.save:
        poly([2.5, 2.5, 11, 2.5, 13.5, 5, 13.5, 13.5, 2.5, 13.5], close: true);
        rect(5, 9, 11, 13.5, 0);
        line(5.5, 2.5, 5.5, 5.5);
        line(5.5, 5.5, 10, 5.5);
      case BirdGlyph.sun:
        circle(8, 8, 3);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(8 + 5 * math.cos(a), 8 + 5 * math.sin(a), 8 + 6.5 * math.cos(a), 8 + 6.5 * math.sin(a));
        }
      case BirdGlyph.moon:
        final path = Path()
          ..moveTo(10, 2.5)
          ..cubicTo(4, 3, 2.5, 8, 4.5, 11)
          ..cubicTo(7, 14.5, 12, 14, 13.5, 10)
          ..cubicTo(9, 11.5, 6.5, 6.5, 10, 2.5);
        canvas.drawPath(path, stroke);
      case BirdGlyph.print:
        poly([4.5, 6, 4.5, 2, 11.5, 2, 11.5, 6]);
        poly([4.5, 11.5, 2, 11.5, 2, 6, 14, 6, 14, 11.5, 11.5, 11.5]);
        rect(4.5, 9.5, 11.5, 14, 0);
      case BirdGlyph.target:
        circle(8, 8, 4.5);
        circle(8, 8, 1.2, fill);
        line(8, 1, 8, 4);
        line(8, 12, 8, 15);
        line(1, 8, 4, 8);
        line(12, 8, 15, 8);
      case BirdGlyph.database:
        canvas.drawOval(const Rect.fromLTRB(3, 2, 13, 5.5), stroke);
        line(3, 3.8, 3, 12.5);
        line(13, 3.8, 13, 12.5);
        canvas.drawArc(const Rect.fromLTRB(3, 10.5, 13, 14), 0, math.pi, false, stroke);
      case BirdGlyph.cookie:
        circle(8, 8, 6);
        circle(6, 6, 0.9, fill);
        circle(10, 8, 0.9, fill);
        circle(7, 10.5, 0.9, fill);
      case BirdGlyph.paneToggle:
        rect(1.5, 2.5, 14.5, 13.5);
        line(6, 2.5, 6, 13.5);
        line(10.5, 2.5, 10.5, 13.5);
      case BirdGlyph.rotate:
        rect(5, 5, 11, 14);
        canvas.drawArc(const Rect.fromLTRB(2, 1.5, 10, 9.5), math.pi, math.pi / 2, false, stroke);
        poly([5, 0.5, 6.5, 1.8, 5, 3.4]);
      case BirdGlyph.sortUp:
        poly([4.5, 10, 8, 6, 11.5, 10], close: true, paint: fill);
      case BirdGlyph.sortDown:
        poly([4.5, 6, 8, 10, 11.5, 6], close: true, paint: fill);
      case BirdGlyph.circle:
        circle(8, 8, 4, fill);
      case BirdGlyph.logpoint:
        poly([2, 4, 10, 4, 14, 8, 10, 12, 2, 12], close: true, paint: fill);
      case BirdGlyph.blackbox:
        rect(2.5, 2.5, 13.5, 13.5);
        line(3, 13, 13, 3);
      case BirdGlyph.stopwatch:
        circle(8, 9, 5.2);
        line(8, 9, 8, 6);
        line(6.5, 1.8, 9.5, 1.8);
        line(8, 1.8, 8, 3.8);
      case BirdGlyph.splitConsole:
        rect(1.5, 2.5, 14.5, 13.5);
        line(1.5, 8.5, 14.5, 8.5);
        poly([3.8, 10, 5.4, 11.2, 3.8, 12.4]);
      case BirdGlyph.editorMode:
        rect(1.5, 2.5, 14.5, 13.5);
        line(7.5, 2.5, 7.5, 13.5);
        line(3.5, 5.5, 5.5, 5.5);
        line(3.5, 8, 5.5, 8);
      case BirdGlyph.frame:
        rect(2, 3, 14, 13);
        line(2, 6, 14, 6);
      case BirdGlyph.image:
        rect(2, 3, 14, 13);
        circle(5.8, 6.2, 1.2, fill);
        poly([2.5, 12, 7, 8.5, 9.5, 10.5, 11.5, 9, 13.5, 11]);
      case BirdGlyph.back:
        line(2.5, 8, 14, 8);
        poly([7, 3.5, 2.5, 8, 7, 12.5]);
      case BirdGlyph.forward:
        line(2, 8, 13.5, 8);
        poly([9, 3.5, 13.5, 8, 9, 12.5]);
      case BirdGlyph.home:
        poly([2, 8, 8, 2.5, 14, 8]);
        poly([3.5, 7, 3.5, 13.5, 6.5, 13.5, 6.5, 10, 9.5, 10, 9.5, 13.5, 12.5, 13.5, 12.5, 7]);
      case BirdGlyph.star:
      case BirdGlyph.starFilled:
        const star = [8.0, 1.8, 9.9, 5.8, 14.3, 6.4, 11.1, 9.4, 11.9, 13.8, 8.0, 11.7, 4.1, 13.8, 4.9, 9.4, 1.7, 6.4, 6.1, 5.8];
        if (glyph == BirdGlyph.starFilled) poly(star, close: true, paint: fill);
        poly(star, close: true);
      case BirdGlyph.lock:
        rect(3.5, 7, 12.5, 14);
        canvas.drawPath(
          Path()
            ..moveTo(5.3, 7)
            ..lineTo(5.3, 5)
            ..arcToPoint(const Offset(10.7, 5), radius: const Radius.circular(2.7))
            ..lineTo(10.7, 7),
          stroke,
        );
      case BirdGlyph.lockOff:
        rect(3.5, 7, 12.5, 14);
        canvas.drawPath(
          Path()
            ..moveTo(5.3, 7)
            ..lineTo(5.3, 5)
            ..arcToPoint(const Offset(10.7, 5), radius: const Radius.circular(2.7))
            ..lineTo(10.7, 7),
          stroke,
        );
        line(1.8, 2, 14.2, 14.4);
      case BirdGlyph.extension:
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 5)
            ..lineTo(6, 5)
            ..arcToPoint(const Offset(10, 5), radius: const Radius.circular(2))
            ..lineTo(11.5, 5)
            ..lineTo(11.5, 7.5)
            ..arcToPoint(const Offset(11.5, 11.5), radius: const Radius.circular(2))
            ..lineTo(11.5, 14)
            ..lineTo(2.5, 14)
            ..close(),
          stroke,
        );
      case BirdGlyph.download:
        line(8, 2, 8, 10);
        poly([4.5, 7, 8, 10.5, 11.5, 7]);
        line(3, 13.8, 13, 13.8);
      case BirdGlyph.menu:
        line(2.5, 4, 13.5, 4);
        line(2.5, 8, 13.5, 8);
        line(2.5, 12, 13.5, 12);
      case BirdGlyph.sidebar:
        rect(1.5, 2.5, 14.5, 13.5);
        line(6, 2.5, 6, 13.5);
        line(3.2, 5, 4.3, 5);
        line(3.2, 7.2, 4.3, 7.2);
      case BirdGlyph.tabs:
        rect(1.5, 2.5, 14.5, 13.5);
        line(1.5, 6, 14.5, 6);
        line(7, 2.5, 7, 6);
      case BirdGlyph.pin:
      case BirdGlyph.pinFilled:
        const pin = [5.5, 2.0, 10.5, 2.0, 10.0, 7.0, 12.2, 9.8, 3.8, 9.8, 6.0, 7.0];
        if (glyph == BirdGlyph.pinFilled) poly(pin, close: true, paint: fill);
        poly(pin, close: true);
        line(8, 10, 8, 14.5);
      case BirdGlyph.location:
        canvas.drawPath(
          Path()
            ..moveTo(8, 14.5)
            ..cubicTo(8, 14.5, 3, 9.8, 3, 6.5)
            ..arcToPoint(const Offset(13, 6.5), radius: const Radius.circular(5))
            ..cubicTo(13, 9.8, 8, 14.5, 8, 14.5),
          stroke,
        );
        circle(8, 6.5, 1.7);
      case BirdGlyph.microphone:
        rect(6, 1.8, 10, 9.5, 2);
        canvas.drawArc(const Rect.fromLTRB(3.5, 3, 12.5, 12), 0, math.pi, false, stroke);
        line(8, 12, 8, 14.5);
      case BirdGlyph.bell:
        canvas.drawPath(
          Path()
            ..moveTo(2.8, 12)
            ..cubicTo(5, 10, 3.8, 3, 8, 3)
            ..cubicTo(12.2, 3, 11, 10, 13.2, 12)
            ..close(),
          stroke,
        );
        line(8, 1.5, 8, 3);
        canvas.drawArc(const Rect.fromLTRB(6.4, 11.4, 9.6, 14.6), 0, math.pi, false, stroke);
      case BirdGlyph.shield:
        canvas.drawPath(
          Path()
            ..moveTo(8, 1.8)
            ..lineTo(13.5, 3.8)
            ..cubicTo(13.5, 9.5, 11.5, 12.5, 8, 14.5)
            ..cubicTo(4.5, 12.5, 2.5, 9.5, 2.5, 3.8)
            ..close(),
          stroke,
        );
      case BirdGlyph.pictureInPicture:
        rect(1.5, 2.5, 14.5, 13.5);
        canvas.drawRRect(RRect.fromLTRBR(8, 8, 12.8, 11.8, const Radius.circular(0.8)), fill);
      case BirdGlyph.openExternal:
        poly([7, 3, 3, 3, 3, 13, 13, 13, 13, 9]);
        poly([9.5, 2.5, 13.5, 2.5, 13.5, 6.5]);
        line(13.2, 2.8, 7.8, 8.2);
      case BirdGlyph.update:
        canvas.drawArc(const Rect.fromLTRB(2, 2, 14, 14), 0, math.pi * 2, false, stroke);
        line(8, 11.2, 8, 5);
        poly([5.5, 7.5, 8, 5, 10.5, 7.5]);
      case BirdGlyph.help:
        circle(8, 8, 6.2);
        text('?', 9.5, 0.3);
      case BirdGlyph.computer:
        rect(2.5, 3, 13.5, 11);
        line(1, 13.5, 15, 13.5);
      case BirdGlyph.fullscreenExit:
        poly([6, 2.5, 6, 6, 2.5, 6]);
        poly([10, 2.5, 10, 6, 13.5, 6]);
        poly([6, 13.5, 6, 10, 2.5, 10]);
        poly([10, 13.5, 10, 10, 13.5, 10]);
      case BirdGlyph.chevronUpDown:
        poly([5, 6, 8, 3, 11, 6]);
        poly([5, 10, 8, 13, 11, 10]);
      case BirdGlyph.minus:
        line(3, 8, 13, 8);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
