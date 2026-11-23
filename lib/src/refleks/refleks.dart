import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/play_kit.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Refleks testi: üç tür deneme sırayla gelir.
///  0 Işık: ekran yeşile dönünce dokun (erken dokunuş can götürür).
///  1 Hedef: beliren daireye süresi bitmeden dokun.
///  2 Renk: üstte yazan renkteki düğmeye dokun.
class ReflexSim extends ArcadeSim {
  final ALevel level;
  int fast = 0, kind = 0, phase = 0, waitUntil = 0, shownAt = 0, done = 0, bestMs = 9999, sumMs = 0, lastEvent = 0, flash = 0;
  double tx = 500, ty = 800, tr = 110;
  int wantColor = 0;
  List<int> buttons = const [0, 1, 2, 3];
  late final int goalN = level.target(8, 2);
  late final int limitTicks = math.max(26, 60 - level.d * 3); // tepki sınırı

  ReflexSim(this.level) : super(level.meta) {
    _next();
  }

  void _next() {
    final kinds = [0, if (level.d >= 2) 1, if (level.d >= 3 || level.has('colors')) 2];
    kind = kinds[rng.nextInt(kinds.length)];
    phase = 0;
    waitUntil = ticks + 40 + rng.nextInt(90);
  }

  void _show() {
    phase = 1;
    shownAt = ticks;
    if (kind == 1) {
      tr = math.max(60, 120 - level.d * 6).toDouble();
      tx = 150 + rng.nextDouble() * 700;
      ty = 400 + rng.nextDouble() * 900;
    } else if (kind == 2) {
      final b = [0, 1, 2, 3];
      rng.shuffle(b);
      buttons = b;
      wantColor = rng.nextInt(4);
    }
  }

  Rect buttonRect(int i) => Rect.fromLTWH(80.0 + (i % 2) * 440, 700.0 + (i ~/ 2) * 380, 400, 340);

  void _success() {
    final ms = ((ticks - shownAt) * 1000 / kTicksPerSecond).round();
    bestMs = math.min(bestMs, ms);
    sumMs += ms;
    if (ms < 300) fast++;
    done++;
    score += math.max(10, 100 - ms ~/ 8);
    lastEvent = 1;
    flash = 15;
    if (goalN > 0 && done >= goalN) {
      win();
      return;
    }
    _next();
  }

  void _fail() {
    lastEvent = 3;
    flash = -20;
    hit();
    if (!over) _next();
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flash > 0) flash--;
    if (flash < 0) flash++;
    if (phase == 0) {
      if (input.tap) {
        _fail();
        return;
      }
      if (ticks >= waitUntil) _show();
      return;
    }
    if (ticks - shownAt > limitTicks + (kind == 2 ? 30 : 0)) {
      _fail();
      return;
    }
    if (!input.tap) return;
    switch (kind) {
      case 0:
        _success();
      case 1:
        if (input.hasPointer && dist(input.x, input.y, tx, ty) < tr + 10) {
          _success();
        } else {
          _fail();
        }
      default:
        for (var i = 0; i < 4; i++) {
          if (input.hasPointer && buttonRect(i).contains(Offset(input.x, input.y))) {
            buttons[i] == wantColor ? _success() : _fail();
            return;
          }
        }
    }
  }

  @override
  double get progress => goalN == 0 ? 0 : done / goalN;
  @override
  String get goalText => goalN == 0 ? '$done' : '$done/$goalN';
  @override
  Map<String, int> get stats => {'reactions': done, 'fast_reactions': fast};
  @override
  int get stars => lifeStars(this, 3);
}

ArcadeInput reflexBot(ArcadeSim sim) {
  final s = sim as ReflexSim;
  if (s.phase == 0 || s.ticks - s.shownAt < 14) return ArcadeInput.idle;
  switch (s.kind) {
    case 0:
      return tapAny;
    case 1:
      return tapAt(s.tx, s.ty);
    default:
      final i = s.buttons.indexOf(s.wantColor);
      final r = s.buttonRect(i);
      return tapAt(r.center.dx, r.center.dy);
  }
}

const _cols = [Color(0xFFE63946), Color(0xFF2A9D8F), Color(0xFFFFB703), Color(0xFF4361EE)];
const _colNames = ['●', '■', '▲', '◆'];

void paintReflex(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as ReflexSim;
  final waiting = s.phase == 0;
  final bg = s.kind == 0
      ? (waiting ? const Color(0xFF9D0208) : const Color(0xFF2B9348))
      : const Color(0xFF1D3557);
  paintSky(c, bg, Color.lerp(bg, Colors.black, 0.35)!);
  if (s.flash != 0) {
    c.drawRect(const Rect.fromLTWH(0, 0, kWorldW, kWorldH), Paint()..color = (s.flash > 0 ? Colors.white : Colors.black).withValues(alpha: s.flash.abs() / 40));
  }
  // zamanlayıcı halkası
  if (!waiting) {
    final lim = s.limitTicks + (s.kind == 2 ? 30 : 0);
    final f = clampD((s.ticks - s.shownAt) / lim, 0, 1);
    c.drawArc(Rect.fromCircle(center: const Offset(500, 300), radius: 90), -math.pi / 2, math.pi * 2 * (1 - f), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = Colors.white70);
  }
  switch (s.kind) {
    case 0:
      paintBall(c, const Offset(500, 800), 200, waiting ? const Color(0xFFE5383B) : const Color(0xFF55A630));
      paintText(c, waiting ? '…' : '!', const Offset(500, 800), 160, Colors.white);
    case 1:
      if (waiting) {
        paintText(c, '◎', const Offset(500, 800), 140, Colors.white30);
      } else {
        paintBall(c, Offset(s.tx, s.ty), s.tr, p.piece(1));
        c.drawCircle(Offset(s.tx, s.ty), s.tr * 0.55, Paint()..color = Colors.white);
        c.drawCircle(Offset(s.tx, s.ty), s.tr * 0.25, Paint()..color = p.piece(1));
      }
    default:
      if (!waiting) {
        paintBall(c, const Offset(500, 520), 90, _cols[s.wantColor]);
        paintText(c, _colNames[s.wantColor], const Offset(500, 520), 80, Colors.white);
        for (var i = 0; i < 4; i++) {
          paintBox(c, s.buttonRect(i).deflate(10), _cols[s.buttons[i]], radius: 40);
        }
      } else {
        paintText(c, '?', const Offset(500, 800), 160, Colors.white30);
      }
  }
  if (s.bestMs < 9999) paintText(c, '${s.bestMs} ms', const Offset(500, 1480), 56, Colors.white70);
}

Sfx? reflexSound(ArcadeSim sim) => switch ((sim as ReflexSim).lastEvent) {
      1 => Sfx.place,
      3 => Sfx.error,
      _ => null,
    };

KitRules reflexRules(String id) => KitRules(
      id,
      optionalMechanics: const ['colors'],
      gameStats: const [
        GameStat('reactions', 'Başarılı tepki', 'Reactions', scale: 200),
        GameStat('fast_reactions', '300 ms altı tepki', 'Reactions under 300 ms', scale: 50),
      ],
      missionTemplates: const [
        MissionTemplate('reactions', 'reactions', [20, 40, 80]),
        MissionTemplate('fast_reactions', 'fast_reactions', [5, 10, 20]),
      ],
      make: ReflexSim.new,
      botFn: reflexBot,
    );
