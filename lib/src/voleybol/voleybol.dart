import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Voleybol (2B): solda sen, sağda rakip. Parmağını sürükle = koş,
/// dokun = zıpla. Top kendi sahana düşerse can gider; rakip sahaya
/// düşürürsen sayı senin.
const double kGround = 1350, kNetX = 500, kNetH = 230, kBlobR = 72, kBallR = 36, kGrav = 0.36, kHitSpeed = 16.5;

class Blob {
  double x, y = kGround, vx = 0, vy = 0;
  Blob(this.x);
  bool get onGround => y >= kGround;
}

class VolleySim extends ArcadeSim {
  final ALevel level;
  final Blob me = Blob(250), ai = Blob(750);
  double bx = 250, by = 650, bvx = 0, bvy = 0;
  int myPts = 0, aiPts = 0, touches = 0, spikes = 0, serveIn = 50, lastEvent = 0;
  bool serveMine = true;
  double aiErr = 0;
  late final int goalN = level.target(5, 0) == 0 ? 0 : 5 + level.d ~/ 2;

  VolleySim(this.level) : super(level.meta);

  void _serve() {
    bx = serveMine ? 250 : 750;
    by = 650;
    bvx = 0;
    bvy = 0;
    me.x = 250;
    ai.x = 750;
    aiErr = 0;
  }

  void _moveBlob(Blob b, double targetX, bool jump, double lo, double hi, double speed) {
    b.vx = clampD(targetX - b.x, -speed, speed);
    b.x = clampD(b.x + b.vx, lo, hi);
    if (jump && b.onGround) b.vy = -15;
    b.vy += 0.75;
    b.y = math.min(kGround, b.y + b.vy);
    if (b.onGround) b.vy = 0;
  }

  bool _collide(Blob b) {
    final dx = bx - b.x, dy = by - b.y;
    final d = math.sqrt(dx * dx + dy * dy);
    if (d < kBlobR + kBallR && dy < 10) {
      final nx = dx / d, ny = dy / d;
      bx = b.x + nx * (kBlobR + kBallR);
      by = b.y + ny * (kBlobR + kBallR);
      final sp = kHitSpeed + (b.onGround ? 0 : 2.5);
      bvx = nx * sp + b.vx * 0.3;
      bvy = ny * sp + math.min(0.0, b.vy) * 0.2;
      return true;
    }
    return false;
  }

  /// Saf: topun y = yLine'a inerken x'i (duvar/file yansımaları kaba).
  double predictX(double yLine) {
    var x = bx, y = by, vx = bvx, vy = bvy;
    for (var k = 0; k < 400; k++) {
      vy += kGrav;
      x += vx;
      y += vy;
      if (x < kBallR || x > kWorldW - kBallR) vx = -vx;
      if ((x - kNetX).abs() < kBallR + 8 && y > kGround - kNetH) vx = -vx;
      if (vy > 0 && y >= yLine) return x;
    }
    return x;
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    // Oyuncu
    var tx = me.x;
    if (input.down && input.hasPointer) tx = input.x;
    if (input.dirX != 0) tx = me.x + input.dirX * 20;
    final jump = (input.tap && input.hasPointer && input.y < 1000) || input.swipe == 0 || input.dirY < 0;
    _moveBlob(me, tx, jump, kBlobR, kNetX - kBlobR - 8, 10);
    // Rakip
    final land = predictX(kGround - 110);
    final aiTarget = bvx >= 0 || bx > kNetX ? (land > kNetX ? land + 58 + aiErr : 750.0) : 750.0;
    final aiJump = bx > kNetX && (bx - ai.x).abs() < 90 && by > kGround - 420 && by < kGround - 220 && bvy > 0 && level.d >= 4;
    _moveBlob(ai, aiTarget, aiJump, kNetX + kBlobR + 8, kWorldW - kBlobR, 6.5 + level.d * 0.45);
    if (serveIn > 0) {
      serveIn--;
      if (serveIn == 0) _serve();
      return;
    }
    bvy += kGrav;
    bx += bvx;
    by += bvy;
    if (bx < kBallR) {
      bx = kBallR;
      bvx = bvx.abs();
    } else if (bx > kWorldW - kBallR) {
      bx = kWorldW - kBallR;
      bvx = -bvx.abs();
    }
    // file
    if ((bx - kNetX).abs() < kBallR + 8 && by > kGround - kNetH - kBallR) {
      if (by < kGround - kNetH) {
        bvy = -bvy.abs() * 0.7;
        by = kGround - kNetH - kBallR;
      } else {
        bx = bx < kNetX ? kNetX - kBallR - 8 : kNetX + kBallR + 8;
        bvx = -bvx * 0.6;
      }
    }
    if (_collide(me)) {
      touches++;
      if (!me.onGround) spikes++;
      lastEvent = 1;
      // Rakibin bir sonraki karşılamadaki yanılgısı
      final errMax = 150 - level.d * 6.0;
      aiErr = (rng.nextDouble() * 2 - 1) * errMax + (me.onGround ? 0 : (rng.nextDouble() * 2 - 1) * 40);
    }
    if (_collide(ai)) lastEvent = 1;
    if (by >= kGround - kBallR) {
      if (bx < kNetX) {
        aiPts++;
        serveMine = true;
        lastEvent = 3;
        serveIn = 70;
        hit();
      } else {
        myPts++;
        serveMine = false;
        score += 100;
        lastEvent = 2;
        serveIn = 70;
        if (goalN > 0 && myPts >= goalN) win();
      }
      bvx = bvy = 0;
      by = kGround - kBallR;
    }
  }

  @override
  void onLifeLost() {
    serveIn = 70;
  }

  @override
  double get progress => goalN == 0 ? 0 : myPts / goalN;
  @override
  String get goalText => '$myPts : $aiPts';
  @override
  Map<String, int> get stats => {'points_won': myPts, 'touches': touches, 'spikes': spikes};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: topun iniş noktasının biraz arkasında durur; topu sağa-yukarı
/// açıyla karşılar. Top fileye yakın ve alçaksa zıplayıp smaç dener.
ArcadeInput volleyBot(ArcadeSim sim) {
  final s = sim as VolleySim;
  if (s.serveIn > 0) return holdAt(250, 1300);
  if (s.bx > kNetX + 40 && s.bvx > 0) return holdAt(260, 1300);
  final land = s.predictX(kGround - 110);
  if (land > kNetX) return holdAt(260, 1300);
  // Karşılama açısını seç: fileyi aşıp rakip sahaya, rakipten uzağa düşen.
  var bestO = 62.0, bestScore = -1e9;
  for (var o = 15.0; o <= 95; o += 5) {
    const rr = kBlobR + kBallR;
    final nx = o / rr, ny = -math.sqrt(math.max(0.0, 1 - nx * nx));
    var x = land, y = kGround - rr * -ny, vx = nx * kHitSpeed, vy = ny * kHitSpeed;
    var ok = false, landX = 0.0;
    for (var k = 0; k < 300; k++) {
      vy += kGrav;
      x += vx;
      y += vy;
      if (x > kWorldW - kBallR) vx = -vx.abs();
      if ((x - kNetX).abs() < kBallR + 10 && y > kGround - kNetH - kBallR - 12) break;
      if (y >= kGround - kBallR) {
        ok = x > kNetX + kBallR;
        landX = x;
        break;
      }
    }
    if (!ok) continue;
    final sc = (landX - s.ai.x).abs() - (o - 62).abs() * 0.5;
    if (sc > bestScore) {
      bestScore = sc;
      bestO = o;
    }
  }
  final target = clampD(land - bestO, kBlobR, kNetX - kBlobR - 8);
  return holdAt(target, 1300);
}

void paintVolley(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as VolleySim;
  paintSky(c, const Color(0xFF48CAE4), const Color(0xFFFFE8D6));
  c.drawCircle(const Offset(830, 260), 90, Paint()..color = const Color(0xFFFFD166));
  // deniz
  c.drawRect(const Rect.fromLTWH(0, 900, kWorldW, 120), Paint()..color = const Color(0xFF0096C7));
  c.drawRect(const Rect.fromLTWH(0, 1000, kWorldW, kWorldH - 1000), Paint()..color = const Color(0xFFF4D58D));
  final sand = Paint()..color = const Color(0x22000000);
  for (var i = 0; i < 40; i++) {
    c.drawCircle(Offset((i * 131.0) % kWorldW, 1380 + (i * 47.0) % 200), 4, sand);
  }
  // file
  c.drawRect(const Rect.fromLTWH(kNetX - 6, kGround - kNetH, 12, kNetH), Paint()..color = const Color(0xFF6C757D));
  final net = Paint()
    ..color = Colors.white70
    ..strokeWidth = 2;
  for (var yy = kGround - kNetH; yy < kGround - kNetH + 100; yy += 20) {
    c.drawLine(Offset(kNetX - 6, yy), Offset(kNetX + 6, yy), net);
  }
  paintBox(c, const Rect.fromLTWH(kNetX - 12, kGround - kNetH - 14, 24, 24), Colors.white, radius: 6, shade: false);
  void blob(Blob b, Color col, bool lookRight) {
    paintShadow(c, Offset(b.x, kGround + 8), kBlobR * 2);
    c.drawArc(Rect.fromCircle(center: Offset(b.x, b.y), radius: kBlobR), math.pi, math.pi, true, Paint()..color = col);
    final ex = b.x + (lookRight ? 28 : -28);
    c.drawCircle(Offset(ex, b.y - 36), 15, Paint()..color = Colors.white);
    final lx = clampD((s.bx - ex) / 60, -6, 6), ly = clampD((s.by - (b.y - 36)) / 60, -6, 6);
    c.drawCircle(Offset(ex + lx, b.y - 36 + ly), 7, Paint()..color = Colors.black);
  }

  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  blob(s.me, blink ? Colors.white54 : p.piece(0), true);
  blob(s.ai, p.piece(2), false);
  if (s.serveIn == 0 || s.serveIn > 60) {
    paintShadow(c, Offset(s.bx, kGround + 8), 50);
    paintBall(c, Offset(s.bx, s.by), kBallR, Colors.white);
    c.drawArc(Rect.fromCircle(center: Offset(s.bx, s.by), radius: kBallR), s.ticks * 0.1, 1.6, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0xFFFFB703));
  }
  paintText(c, '${s.myPts}', const Offset(250, 200), 90, Colors.white);
  paintText(c, '${s.aiPts}', const Offset(750, 200), 90, Colors.white70);
}

Sfx? volleySound(ArcadeSim sim) => switch ((sim as VolleySim).lastEvent) {
      1 => Sfx.tap,
      2 => Sfx.coin,
      3 => Sfx.error,
      _ => null,
    };

KitRules volleyRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('points_won', 'Kazanılan sayı', 'Points won', scale: 50),
        GameStat('touches', 'Topa dokunuş', 'Touches', scale: 300),
        GameStat('spikes', 'Smaç', 'Spikes', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('points_won', 'points_won', [5, 10, 20]),
        MissionTemplate('touches', 'touches', [20, 50, 100]),
      ],
      make: VolleySim.new,
      botFn: volleyBot,
    );
