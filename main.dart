import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false,
  home: FlappyGame(),
));

enum GameState { ready, playing, over }

class Pipe {
  double x;
  final double gapY;
  bool scored = false;
  Pipe(this.x, this.gapY);
}

class FlappyGame extends StatefulWidget {
  const FlappyGame({super.key});
  @override
  State<FlappyGame> createState() => _FlappyGameState();
}

class _FlappyGameState extends State<FlappyGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = Random();
  Duration _last = Duration.zero;

  GameState state = GameState.ready;
  double w = 400, h = 800;
  double birdY = 400, vel = 0;
  double groundOffset = 0;
  int score = 0, best = 0;
  final List<Pipe> pipes = [];

  // Everything scales with screen height so it feels the same on any device.
  double get s => h / 800;
  double get gravity => 1800 * s;
  double get jump => -560 * s;
  double get speed => 170 * s;
  double get gap => 190 * s;
  double get spacing => 260 * s;
  double get pipeW => 70 * s;
  double get birdR => 16 * s;
  double get groundH => 90 * s;
  double get birdX => w * 0.28;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _reset() {
    birdY = h / 2;
    vel = 0;
    score = 0;
    pipes.clear();
    state = GameState.ready;
  }

  void _flap() {
    switch (state) {
      case GameState.ready:
        state = GameState.playing;
        vel = jump;
      case GameState.playing:
        vel = jump;
      case GameState.over:
        _reset();
    }
    HapticFeedback.selectionClick();
  }

  void _tick(Duration elapsed) {
    final dt = min((elapsed - _last).inMicroseconds / 1e6, 0.05);
    _last = elapsed;

    if (state == GameState.ready) {
      // Gentle idle bobbing
      birdY = h / 2 + sin(elapsed.inMilliseconds / 250) * 8 * s;
      groundOffset = (groundOffset + speed * dt) % (24 * s);
    } else if (state == GameState.playing) {
      _update(dt);
    }
    setState(() {});
  }

  void _update(double dt) {
    vel += gravity * dt;
    birdY += vel * dt;
    groundOffset = (groundOffset + speed * dt) % (24 * s);

    // Spawn pipes
    if (pipes.isEmpty || pipes.last.x < w - spacing) {
      final margin = 90 * s;
      final minY = margin + gap / 2;
      final maxY = h - groundH - margin - gap / 2;
      pipes.add(Pipe(w + pipeW, minY + _rng.nextDouble() * (maxY - minY)));
    }

    for (final p in pipes) {
      p.x -= speed * dt;
      if (!p.scored && p.x + pipeW < birdX - birdR) {
        p.scored = true;
        score++;
        best = max(best, score);
      }
      // Collision with pipe
      final overlapX = birdX + birdR > p.x && birdX - birdR < p.x + pipeW;
      if (overlapX &&
          (birdY - birdR < p.gapY - gap / 2 ||
              birdY + birdR > p.gapY + gap / 2)) {
        _die();
      }
    }
    pipes.removeWhere((p) => p.x + pipeW < 0);

    // Ground / ceiling
    if (birdY + birdR > h - groundH) {
      birdY = h - groundH - birdR;
      _die();
    }
    if (birdY - birdR < 0) {
      birdY = birdR;
      vel = 0;
    }
  }

  void _die() {
    if (state == GameState.over) return;
    state = GameState.over;
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.space) {
          _flap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth != w || c.maxHeight != h) {
            w = c.maxWidth;
            h = c.maxHeight;
            if (state == GameState.ready) birdY = h / 2;
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _flap(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _GamePainter(this)),
                Align(
                  alignment: const Alignment(0, -0.75),
                  child: Text('$score',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                      )),
                ),
                if (state != GameState.playing) Center(child: _banner()),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _banner() {
    final over = state == GameState.over;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(over ? 'GAME OVER' : 'FLAPPY FLUTTER',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const SizedBox(height: 8),
          if (over)
            Text('Score $score   •   Best $best',
                style: const TextStyle(fontSize: 18, color: Colors.amber)),
          const SizedBox(height: 8),
          Text(over ? 'Tap to retry' : 'Tap / Space to flap',
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final _FlappyGameState g;
  _GamePainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, s = g.s;

    // Sky
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4FC3F7), Color(0xFFB3E5FC)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Pipes
    final pipeFill = Paint()..color = const Color(0xFF43A047);
    final pipeEdge = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * s;
    final capH = 28 * s, capExtra = 6 * s;

    for (final p in g.pipes) {
      final topH = p.gapY - g.gap / 2;
      final botY = p.gapY + g.gap / 2;
      final botH = h - g.groundH - botY;

      void pipe(Rect body, Rect cap) {
        for (final r in [body, cap]) {
          final rr = RRect.fromRectAndRadius(r, Radius.circular(4 * s));
          canvas.drawRRect(rr, pipeFill);
          canvas.drawRRect(rr, pipeEdge);
        }
      }

      pipe(Rect.fromLTWH(p.x, 0, g.pipeW, topH),
          Rect.fromLTWH(p.x - capExtra, topH - capH, g.pipeW + capExtra * 2, capH));
      pipe(Rect.fromLTWH(p.x, botY, g.pipeW, botH),
          Rect.fromLTWH(p.x - capExtra, botY, g.pipeW + capExtra * 2, capH));
    }

    // Ground
    final gy = h - g.groundH;
    canvas.drawRect(Rect.fromLTWH(0, gy, w, g.groundH),
        Paint()..color = const Color(0xFFDEB887));
    canvas.drawRect(
        Rect.fromLTWH(0, gy, w, 14 * s), Paint()..color = const Color(0xFF7CB342));
    final stripe = Paint()..color = const Color(0x22000000);
    for (double x = -g.groundOffset; x < w; x += 24 * s) {
      canvas.drawRect(Rect.fromLTWH(x, gy + 14 * s, 12 * s, 8 * s), stripe);
    }

    // Bird (tilts with velocity)
    canvas.save();
    canvas.translate(g.birdX, g.birdY);
    canvas.rotate((g.vel / (700 * s)).clamp(-0.5, 1.0));
    final r = g.birdR;
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xFFFFD54F));
    canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = const Color(0xFFF57F17)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * s);
    // Wing
    canvas.drawOval(Rect.fromCenter(center: Offset(-r * 0.4, r * 0.2), width: r, height: r * 0.6),
        Paint()..color = const Color(0xFFFFB300));
    // Eye
    canvas.drawCircle(Offset(r * 0.4, -r * 0.3), r * 0.3, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(r * 0.5, -r * 0.3), r * 0.14, Paint()..color = Colors.black);
    // Beak
    final beak = Path()
      ..moveTo(r * 0.8, 0)
      ..lineTo(r * 1.5, r * 0.15)
      ..lineTo(r * 0.8, r * 0.4)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFFF7043));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GamePainter old) => true;
}