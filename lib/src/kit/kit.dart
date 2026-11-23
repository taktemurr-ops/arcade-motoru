import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

/// Yeni arcade motorlarının ortak bölüm tanımı: tohum, zorluk, mod, mekanikler.
class ALevel {
  final LevelSpec spec;
  final ArcadeMeta meta;
  ALevel(this.spec) : meta = ArcadeMeta.of(spec);

  int get d => spec.difficulty;
  int get seed => spec.seed;
  bool has(String m) => spec.has(m);
  bool get goal => meta.goal;

  /// Kampanya hedefi: base + d*per; sonsuz/zen/zamanlı modlarda 0.
  int target(int base, int per) => goal ? base + d * per : 0;

  /// 0..1 arası zorluk oranı.
  double get k => (d - 1) / 9.0;
  double lerp(double a, double b) => a + (b - a) * k;
}

/// Tek dosyalık motorlar için kalıp kurallar.
class KitRules extends ArcadeRules<ALevel> {
  @override
  final String gameId;
  @override
  final List<String> optionalMechanics;
  @override
  final List<GameStat> gameStats;
  @override
  final List<MissionTemplate> missionTemplates;
  final ArcadeSim Function(ALevel) make;
  final ArcadeInput Function(ArcadeSim) botFn;
  final int ticks;

  KitRules(
    this.gameId, {
    required this.optionalMechanics,
    required this.gameStats,
    required this.missionTemplates,
    required this.make,
    required this.botFn,
    this.ticks = 60 * 60 * 6,
  });

  @override
  int get levelCount => 100000;

  @override
  ALevel generate(LevelSpec spec) => ALevel(spec);

  @override
  ArcadeMeta metaOf(ALevel l) => l.meta;

  @override
  ArcadeSim createSim(ALevel l) => make(l);

  @override
  ArcadeInput bot(ArcadeSim sim) => botFn(sim);

  @override
  int maxTicks(ALevel level) => ticks;
}

/// Bot yardımcıları.
ArcadeInput tapAt(double x, double y) => ArcadeInput(tap: true, down: true, x: x, y: y);
ArcadeInput holdAt(double x, double y) => ArcadeInput(down: true, x: x, y: y);
ArcadeInput dirInput(int dx, int dy) => ArcadeInput(dirX: dx, dirY: dy);
const ArcadeInput tapAny = ArcadeInput(tap: true, down: true, x: 500, y: 800);

/// Bir pointer bırakma olayını (sürükleme bitişi) izler.
class DragTracker {
  bool _was = false;
  double sx = -1, sy = -1, x = -1, y = -1;

  /// Bu tikte parmak kalktıysa true.
  bool released = false;
  bool get active => _was;

  void feed(ArcadeInput i) {
    released = false;
    if (i.down && i.hasPointer) {
      if (!_was) {
        sx = i.x;
        sy = i.y;
      }
      x = i.x;
      y = i.y;
      _was = true;
    } else if (_was) {
      released = true;
      _was = false;
    }
  }

  double get dx => x - sx;
  double get dy => y - sy;
}

double dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx, dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}

double angleTo(double ax, double ay, double bx, double by) => math.atan2(by - ay, bx - ax);

/// Nokta-segment uzaklığı.
double segDist(double px, double py, double ax, double ay, double bx, double by) {
  final vx = bx - ax, vy = by - ay;
  final l2 = vx * vx + vy * vy;
  var t = l2 == 0 ? 0.0 : ((px - ax) * vx + (py - ay) * vy) / l2;
  t = clampD(t, 0, 1);
  return dist(px, py, ax + vx * t, ay + vy * t);
}

// ---------------------------------------------------------------- çizim

/// Dünya arka planı: dikey gradyan + yumuşak ışık.
void paintSky(Canvas c, Color top, Color bottom) {
  const r = Rect.fromLTWH(0, 0, kWorldW, kWorldH);
  c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(r));
}

/// Parlak, gölgeli top.
void paintBall(Canvas c, Offset o, double r, Color col) {
  c.drawCircle(o + Offset(r * 0.15, r * 0.25), r, Paint()..color = Colors.black26);
  c.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(col, Colors.white, 0.55)!, col, Color.lerp(col, Colors.black, 0.35)!],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: o, radius: r)));
}

/// Gölgeli yuvarlak köşeli kutu.
void paintBox(Canvas c, Rect r, Color col, {double radius = 12, bool shade = true}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  if (shade) c.drawRRect(rr.shift(const Offset(0, 6)), Paint()..color = Colors.black26);
  c.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(col, Colors.white, 0.22)!, Color.lerp(col, Colors.black, 0.18)!],
        ).createShader(r));
  c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(r.left + 4, r.top + 3, r.width - 8, math.min(10.0, r.height / 3)), Radius.circular(radius / 2)),
      Paint()..color = Colors.white24);
}

/// Yere düşen yumuşak gölge.
void paintShadow(Canvas c, Offset o, double w) =>
    c.drawOval(Rect.fromCenter(center: o, width: w, height: w * 0.28), Paint()..color = Colors.black26);

/// Yarı saydam ızgara deseni (zemin dokusu).
void paintGrid(Canvas c, Rect r, double step, Color col) {
  final p = Paint()
    ..color = col
    ..strokeWidth = 2;
  for (var x = r.left; x <= r.right; x += step) {
    c.drawLine(Offset(x, r.top), Offset(x, r.bottom), p);
  }
  for (var y = r.top; y <= r.bottom; y += step) {
    c.drawLine(Offset(r.left, y), Offset(r.right, y), p);
  }
}

/// Patlama / parçacık halkası.
void paintBurst(Canvas c, Offset o, double age, Color col, {double size = 60}) {
  if (age < 0 || age > 1) return;
  final p = Paint()..color = col.withValues(alpha: clampD(1 - age, 0, 1));
  for (var i = 0; i < 10; i++) {
    final a = i / 10 * math.pi * 2;
    c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * (size * age), 8 * (1 - age) + 2, p);
  }
}

/// Basit, sabit sıralı parçacık listesi.
class Fx {
  final double x, y;
  final int born;
  final int color;
  Fx(this.x, this.y, this.born, this.color);
}

void paintFxList(Canvas c, List<Fx> fx, int now, ArcadePalette p) {
  for (final f in fx) {
    paintBurst(c, Offset(f.x, f.y), (now - f.born) / 30, p.piece(f.color));
  }
}

void pruneFx(List<Fx> fx, int now) => fx.removeWhere((f) => now - f.born > 30);
