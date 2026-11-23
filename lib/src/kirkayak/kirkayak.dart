import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Kırkayak: bahçenin altında böcek avcısısın; parmağınla sağa-sola (ve
/// alt bölgede yukarı-aşağı) sürükle, otomatik ateş edersin. Kırkayak
/// mantarlara ve kenarlara çarptıkça bir sıra iner; vurulan parça mantara
/// dönüşür ve kırkayak ikiye bölünür. Kırkayak sana değerse can gider.
const int kCols = 20, kRows = 30;
const double kC = 50, kTop = 60, kZoneTop = kTop + 24 * kC;

class Seg {
  int col, row, dir;
  bool head;
  Seg(this.col, this.row, this.dir, this.head);
}

class Shot {
  double x, y;
  Shot(this.x, this.y);
}

class CentSim extends ArcadeSim {
  final ALevel level;
  final Map<int, int> mush = {}; // hücre → can (1..4)
  final List<Seg> segs = [];
  final List<Shot> shots = [];
  final List<Fx> fx = [];
  double x = 500, y = kTop + 28 * kC;
  int wave = 0, killed = 0, mushShot = 0, cooldown = 0, lastEvent = 0, moveEvery = 8, pause = 0;
  late final int waves = level.target(2, 0) == 0 ? 0 : 2 + level.d ~/ 3;

  CentSim(this.level) : super(level.meta) {
    final n = 22 + level.d * 3;
    for (var i = 0; i < n; i++) {
      final c = rng.nextInt(kCols), r = 2 + rng.nextInt(kRows - 8);
      mush[c * 100 + r] = 4;
    }
    _wave();
  }

  void _wave() {
    wave++;
    segs.clear();
    final len = 8 + math.min(level.d, 6);
    for (var i = 0; i < len; i++) {
      segs.add(Seg(i, 0, 1, i == len - 1));
    }
    moveEvery = math.max(3, 8 - level.d ~/ 2 - wave ~/ 2);
  }

  Offset cellCenter(int c, int r) => Offset((c + 0.5) * kC, kTop + (r + 0.5) * kC);

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (input.down && input.hasPointer) {
      x = moveToward(x, input.x, 22);
      y = moveToward(y, clampD(input.y - 120, kZoneTop + 20, kTop + kRows * kC - 30), 18);
    } else {
      x += input.dirX * 14;
      y += input.dirY * 12;
    }
    x = clampD(x, 30, kCols * kC - 30);
    y = clampD(y, kZoneTop + 20, kTop + kRows * kC - 30);
    if (pause > 0) {
      pause--;
      if (pause == 0) _wave();
      return;
    }
    if (cooldown > 0) cooldown--;
    if (cooldown == 0) {
      shots.add(Shot(x, y - 40));
      cooldown = 7;
    }
    for (final sh in shots) {
      sh.y -= 34;
    }
    // atış çarpışmaları
    for (final sh in [...shots]) {
      final c = (sh.x / kC).floor(), r = ((sh.y - kTop) / kC).floor();
      if (r < 0) {
        shots.remove(sh);
        continue;
      }
      Seg? hitS;
      for (final s in segs) {
        if (s.col == c && s.row == r) hitS = s;
      }
      if (hitS != null) {
        shots.remove(sh);
        final i = segs.indexOf(hitS);
        segs.removeAt(i);
        // arkasındaki parça yeni baş olur
        if (i - 1 >= 0 && i - 1 < segs.length) segs[i - 1].head = true;
        mush[hitS.col * 100 + hitS.row] = 4;
        killed++;
        score += hitS.head ? 100 : 10;
        fx.add(Fx(sh.x, sh.y, ticks, 2));
        lastEvent = 2;
        continue;
      }
      final k = c * 100 + r;
      final m = mush[k];
      if (m != null) {
        shots.remove(sh);
        if (m <= 1) {
          mush.remove(k);
          mushShot++;
          score += 1;
        } else {
          mush[k] = m - 1;
        }
        lastEvent = lastEvent == 0 ? 1 : lastEvent;
      }
    }
    // kırkayak hareketi (baştan kuyruğa: her parça bir öncekini izler)
    if (ticks % moveEvery == 0) {
      // Zincirler: baş parçalar kendi yönünde gider, takipçiler önündekinin eski yerine.
      final old = [for (final s in segs) (s.col, s.row, s.dir)];
      for (var i = segs.length - 1; i >= 0; i--) {
        final s = segs[i];
        if (s.head) {
          final nc = s.col + s.dir;
          final blocked = nc < 0 || nc >= kCols || mush.containsKey(nc * 100 + s.row);
          if (blocked) {
            s.row++;
            s.dir = -s.dir;
            if (s.row >= kRows) s.row = 24;
          } else {
            s.col = nc;
          }
        } else if (i + 1 < segs.length) {
          final (c, r, d) = old[i + 1];
          s.col = c;
          s.row = r;
          s.dir = d;
        }
      }
    }
    for (final s in segs) {
      final o = cellCenter(s.col, s.row);
      if (dist(o.dx, o.dy, x, y) < kC * 0.75) {
        lastEvent = 3;
        hit();
        return;
      }
    }
    shots.removeWhere((s) => s.y < kTop);
    pruneFx(fx, ticks);
    if (segs.isEmpty) {
      score += 200;
      lastEvent = 4;
      if (waves > 0 && wave >= waves) {
        win();
        return;
      }
      pause = 60;
    }
  }

  @override
  void onLifeLost() {
    // kırkayağı yukarı geri gönder
    final len = segs.length;
    segs.clear();
    for (var i = 0; i < len; i++) {
      segs.add(Seg(i, 0, 1, i == len - 1));
    }
  }

  @override
  double get progress => waves == 0 ? 0 : (wave - (segs.isEmpty ? 0 : 1)) / waves;
  @override
  String get goalText => waves == 0 ? '$killed' : '$wave/$waves';
  @override
  Map<String, int> get stats => {'segments_shot': killed, 'mushrooms_cleared': mushShot};
  @override
  int get stars => lifeStars(this, 3);
}

/// Bot: en alçaktaki parçanın sütununa gider; parça oyuncu bölgesine
/// yaklaşırsa ondan uzak sütuna kaçar.
ArcadeInput centBot(ArcadeSim sim) {
  final s = sim as CentSim;
  if (s.segs.isEmpty) return holdAt(500, kTop + 29 * kC + 120);
  Seg? low;
  for (final g in s.segs) {
    if (low == null || g.row > low.row || (g.row == low.row && g.head)) low = g;
  }
  final l = low!;
  var tx = (l.col + 0.5 + l.dir * 1.0) * kC;
  var ty = kTop + 29 * kC;
  // yakındaki parçalardan kaç
  for (final g in s.segs) {
    final o = s.cellCenter(g.col, g.row);
    if (o.dy > kZoneTop - kC * 2 && (o.dx - s.x).abs() < kC * 3) {
      tx = o.dx < 500 ? o.dx + kC * 5 : o.dx - kC * 5;
      ty = kTop + 29.4 * kC;
    }
  }
  return holdAt(clampD(tx, 30, 970), ty + 120);
}

void paintCent(Canvas c, ArcadeSim sim, ArcadePalette p, double t) {
  final s = sim as CentSim;
  paintSky(c, const Color(0xFF132A13), const Color(0xFF31572C));
  c.drawRect(const Rect.fromLTWH(0, kZoneTop, kCols * kC, 6 * kC), Paint()..color = Colors.black12);
  for (final e in s.mush.entries) {
    final o = s.cellCenter(e.key ~/ 100, e.key % 100);
    final hp = e.value;
    c.drawRect(Rect.fromCenter(center: o + const Offset(0, 10), width: 16, height: 20), Paint()..color = const Color(0xFFF1FAEE));
    c.drawArc(Rect.fromCenter(center: o, width: kC * 0.9, height: kC * 0.8 * (0.5 + hp / 8)), math.pi, math.pi, true, Paint()..color = Color.lerp(const Color(0xFFE63946), const Color(0xFF8D6E63), (4 - hp) / 4)!);
    c.drawCircle(o + const Offset(-8, -8), 4, Paint()..color = Colors.white70);
  }
  for (final g in s.segs) {
    final o = s.cellCenter(g.col, g.row);
    paintBall(c, o, kC * 0.46, g.head ? const Color(0xFFFFB703) : const Color(0xFF80B918));
    if (g.head) {
      c.drawCircle(o + Offset(g.dir * 10.0, -6), 6, Paint()..color = Colors.black);
      c.drawLine(o + const Offset(-6, -20), o + const Offset(-14, -34), Paint()
        ..strokeWidth = 3
        ..color = Colors.black);
      c.drawLine(o + const Offset(6, -20), o + const Offset(14, -34), Paint()
        ..strokeWidth = 3
        ..color = Colors.black);
    }
  }
  for (final sh in s.shots) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sh.x, sh.y), width: 8, height: 26), const Radius.circular(4)), Paint()..color = const Color(0xFFFFF3B0));
  }
  paintFxList(c, s.fx, s.ticks, p);
  final blink = s.shield > 0 && (s.ticks ~/ 5).isOdd;
  final body = Path()
    ..moveTo(s.x, s.y - 34)
    ..lineTo(s.x + 30, s.y + 24)
    ..lineTo(s.x - 30, s.y + 24)
    ..close();
  c.drawPath(body, Paint()..color = blink ? Colors.white54 : p.piece(0));
  c.drawCircle(Offset(s.x, s.y + 4), 10, Paint()..color = Colors.white);
}

Sfx? centSound(ArcadeSim sim) => switch ((sim as CentSim).lastEvent) {
      2 => Sfx.place,
      3 => Sfx.lose,
      4 => Sfx.win,
      _ => null,
    };

KitRules centRules(String id) => KitRules(
      id,
      optionalMechanics: const [],
      gameStats: const [
        GameStat('segments_shot', 'Vurulan parça', 'Segments shot', scale: 500),
        GameStat('mushrooms_cleared', 'Temizlenen mantar', 'Mushrooms cleared', scale: 300),
      ],
      missionTemplates: const [
        MissionTemplate('segments_shot', 'segments_shot', [40, 80, 160]),
        MissionTemplate('mushrooms_cleared', 'mushrooms_cleared', [10, 20, 40]),
      ],
      make: CentSim.new,
      botFn: centBot,
    );
