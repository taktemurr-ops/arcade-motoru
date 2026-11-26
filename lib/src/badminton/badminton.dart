import 'dart:math' as math;

import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/arcade_duel.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import '../kit/kit.dart';

/// Badminton (üstten görünüm, oyuncu altta, rakip üstte). Tüy top yere
/// değmeden havada karşılanır; hava direnci yüzünden uzun vuruşlar dik
/// düşer. Raket parmağı izler; top menzile girince vuruş kendiliğinden
/// olur, raketin neresine değdiği yönü belirler. Yukarı kaydır: smaç
/// (top yüksekteyse), aşağı kaydır: file önüne kısa top. Top rakip sahada
/// yere değerse sayı senin; dışarı düşerse ya da fileye takılırsa rakibin.
const double kBdL = 230, kBdR = 770, kBdT = 200, kBdB = 1400, kBdNet = 800, kBdNetH = 62;
const double kBdG = 0.2, kBdDrag = 0.985, kBdReach = 105, kBdHitZ = 230;
const double kBdMinY = 860, kBdMaxY = 1530, kBdPSpeed = 21;

class BadmintonSim extends ArcadeSim implements DuelSim {
  final ALevel level;
  double bx = 500, by = 1300, bz = 80, vx = 0, vy = 0, vz = 0;
  bool live = false, netChecked = false;
  int lastHitter = 0;
  double px = 500, py = 1350, cx = 500, cy = 250, ctx = 500, cty = 250;
  int power = 0, rivalPower = 0, server = 0, serveWait = 0, pause = 0;
  int myPts = 0, cpuPts = 0, myGames = 0, cpuGames = 0, ptsToWin = 11, gamesToWin = 1, rally = 0;
  int pointsWon = 0, matchesWon = 0, smashes = 0, bestRally = 0, pointsLost = 0, drops = 0;
  int lastEvent = 0; // 1 vuruş, 2 sayı aldın, 3 sayı verdin, 4 smaç
  int flash = 0, flashTicks = 0; // 1 SAYI, 2 DIŞARI, 3 SAYI ×, 4 SET, 5 SET ×, 6 FİLE
  int swingAt = -100, rivalSwingAt = -100;
  ArcadeInput? _rival;
  bool duel = false;

  BadmintonSim(this.level) : super(level.meta) {
    _setupMatch();
  }

  int get d => level.d;
  bool get matchMode => meta.goal;

  void _setupMatch() {
    myPts = cpuPts = myGames = cpuGames = 0;
    ptsToWin = d <= 3 ? 7 : (d <= 7 ? 11 : 15);
    gamesToWin = d >= 9 ? 2 : 1;
    server = 0;
    _newPoint();
  }

  void _newPoint() {
    live = false;
    rally = 0;
    netChecked = false;
    pause = 0;
    px = 500;
    py = 1320;
    cx = 500;
    cy = kWorldH - 1320;
    ctx = cx;
    cty = cy;
    serveWait = 0;
    _placeServe();
  }

  void _placeServe() {
    if (server == 0) {
      bx = px + 30;
      by = py - 40;
    } else {
      bx = cx - 30;
      by = cy + 40;
    }
    bz = 90;
    vx = vy = vz = 0;
  }

  void _say(int f) {
    flash = f;
    flashTicks = 60;
  }

  /// (bx,by,bz)'den (tx,ty)'ye T tikte inecek hızlar; fileyi [clear] payla geçer.
  void _launch(double tx, double ty, int t0, {double clear = 20}) {
    var t = math.max(10, t0);
    for (var k = 0; k < 40; k++) {
      final ok = _netOk(tx, ty, t, clear);
      if (ok) break;
      t += 2;
    }
    _setVel(tx, ty, t);
    live = true;
    netChecked = false;
  }

  (double, double, double) _vel(double tx, double ty, int t) {
    final s = (1 - math.pow(kBdDrag, t)) / (1 - kBdDrag);
    // Yerçekimi payı: vz0 = 0 ile T tik sonra z kaybı
    var z = 0.0, w = 0.0;
    for (var i = 0; i < t; i++) {
      z += w;
      w = w * kBdDrag - kBdG;
    }
    return ((tx - bx) / s, (ty - by) / s, (-bz - z) / s);
  }

  void _setVel(double tx, double ty, int t) {
    final v = _vel(tx, ty, t);
    vx = v.$1;
    vy = v.$2;
    vz = v.$3;
  }

  bool _netOk(double tx, double ty, int t, double clear) {
    final v = _vel(tx, ty, t);
    var y = by, z = bz, uy = v.$2, uz = v.$3;
    for (var i = 0; i < t; i++) {
      final y0 = y;
      y += uy;
      z += uz;
      uy *= kBdDrag;
      uz = uz * kBdDrag - kBdG;
      if ((y0 - kBdNet) * (y - kBdNet) <= 0) return z > kBdNetH + clear;
    }
    return true;
  }

  /// Vuruş: [side] 0 alttaki, 1 üstteki oyuncu (kendi bakışıyla aynı kurallar).
  void _hitBy(int side, {bool serve = false}) {
    final rx = side == 0 ? px : kWorldW - cx;
    // Kendi bakışında (alttaymış gibi) koordinatlar
    final lx = side == 0 ? bx : kWorldW - bx;
    final off = clampD((lx - rx) / kBdReach, -1, 1);
    final pw = side == 0 ? power : rivalPower;
    final lz = bz;
    var tx = 500 + off * 245;
    double ty;
    int t;
    var clear = 22.0;
    if (serve) {
      ty = kBdT + 160;
      t = 66;
      tx = 500 - off * 120;
    } else if (pw > 0 && lz > 120) {
      // Smaç: dik ve hızlı
      ty = kBdNet - 260 - (1 - off.abs()) * 80;
      t = 20;
      clear = 6;
      bz = math.max(bz, 210);
      if (side == 0) smashes++;
      lastEvent = 4;
    } else if (pw < 0) {
      // File önü
      ty = kBdNet - 110;
      t = 34;
      clear = 10;
      if (side == 0) drops++;
    } else {
      ty = kBdT + 120 + (1 - off.abs()) * 60;
      t = 66;
    }
    if (side == 1) {
      tx = kWorldW - tx;
      ty = kWorldH - ty;
    }
    _launch(tx, ty, t, clear: clear);
    if (side == 0) {
      power = 0;
      swingAt = ticks;
    } else {
      rivalPower = 0;
      rivalSwingAt = ticks;
    }
    lastHitter = side;
    rally++;
    if (lastEvent != 4) lastEvent = 1;
  }

  void _cpuHit({bool serve = false}) {
    final r = rng;
    final away = px < 500 ? 1.0 : -1.0;
    var tx = 500 + (r.chance(0.35 + d * 0.05) ? away : (r.nextDouble() * 2 - 1)) * (120 + r.nextDouble() * (90 + d * 6));
    double ty;
    int t;
    var clear = 22.0;
    final roll = r.nextDouble();
    if (serve) {
      ty = kBdB - 160;
      t = 66;
    } else if (bz > 150 && roll < 0.08 + d * 0.025) {
      ty = kBdNet + 280 + r.nextDouble() * 200;
      t = 22;
      clear = 6;
      bz = math.max(bz, 200);
    } else if (roll < 0.25) {
      ty = kBdNet + 120 + r.nextDouble() * 60;
      t = 36;
      clear = 10;
    } else {
      ty = kBdB - 120 - r.nextDouble() * 220;
      t = 62 + r.nextInt(10);
    }
    final err = serve ? 0.02 : (0.2 - d * 0.013);
    if (r.chance(err)) {
      if (r.chance(0.5)) {
        tx = 500 + (r.chance(0.5) ? 1 : -1) * (300 + r.nextDouble() * 60);
      } else {
        ty = kBdB + 70 + r.nextDouble() * 60;
      }
    }
    _launch(tx, ty, t, clear: clear);
    lastHitter = 1;
    rivalSwingAt = ticks;
    rally++;
    lastEvent = 1;
  }

  void _point(bool mine) {
    live = false;
    bestRally = math.max(bestRally, rally);
    if (mine) {
      pointsWon++;
      score += 100 + rally * 10;
      lastEvent = 2;
    } else {
      pointsLost++;
      lastEvent = 3;
    }
    pause = 50;
    if (!matchMode) {
      _say(mine ? 1 : 3);
      if (!mine && !meta.zen) {
        shield = 0;
        hit();
      }
      server = mine ? 0 : 1;
      return;
    }
    if (mine) {
      myPts++;
    } else {
      cpuPts++;
    }
    _say(mine ? 1 : 3);
    final cap = ptsToWin + 4;
    bool gameWon(int a, int b) => a >= ptsToWin && (a - b >= 2 || a >= cap);
    if (gameWon(myPts, cpuPts) || gameWon(cpuPts, myPts)) {
      final me = myPts > cpuPts;
      if (me) {
        myGames++;
      } else {
        cpuGames++;
      }
      myPts = 0;
      cpuPts = 0;
      _say(me ? 4 : 5);
      if (myGames >= gamesToWin) {
        matchesWon++;
        score += 500;
        win();
        return;
      }
      if (cpuGames >= gamesToWin) {
        if (meta.zen) {
          _setupMatch();
          return;
        }
        shield = 0;
        hit();
        return;
      }
    }
    // Sayıyı alan servis atar.
    server = mine ? 0 : 1;
  }

  @override
  void onLifeLost() {
    if (matchMode) {
      _setupMatch();
    } else {
      _newPoint();
    }
  }

  @override
  void update(ArcadeInput input) {
    lastEvent = 0;
    if (flashTicks > 0) flashTicks--;
    if (power > 0) power--;
    if (power < 0) power++;
    if (input.swipe == 0) power = 30;
    if (input.swipe == 2) power = -30;
    _movePlayer(input);
    final rival = _rival;
    if (rivalPower > 0) rivalPower--;
    if (rivalPower < 0) rivalPower++;
    if (rival != null) {
      if (rival.swipe == 0) rivalPower = 30;
      if (rival.swipe == 2) rivalPower = -30;
      _moveRival(rival);
    }
    if (pause > 0) {
      pause--;
      if (pause == 0) _newPoint();
      return;
    }
    if (!live) {
      _serve(input);
      if (rival == null) _moveCpu();
      return;
    }
    if (rival == null) _moveCpu();
    _step();
  }

  void _serve(ArcadeInput input) {
    serveWait++;
    _placeServe();
    if (server == 0) {
      if ((input.tap || input.swipe == 0 || serveWait > 180) && serveWait > 20) _hitBy(0, serve: true);
    } else if (_rival != null) {
      final r = _rival!;
      if ((r.tap || r.swipe == 0 || serveWait > 180) && serveWait > 20) _hitBy(1, serve: true);
    } else if (serveWait > 50) {
      _cpuHit(serve: true);
    }
  }

  void _movePlayer(ArcadeInput i) {
    var tx = px, ty = py;
    if (i.down && i.hasPointer) {
      tx = i.x;
      ty = i.y - 40;
    }
    if (i.dirX != 0) tx = px + i.dirX * 40;
    if (i.dirY != 0) ty = py + i.dirY * 40;
    px = moveToward(px, clampD(tx, kBdL - 120, kBdR + 120), kBdPSpeed);
    py = moveToward(py, clampD(ty, kBdMinY, kBdMaxY), kBdPSpeed * 0.75);
  }

  void _moveRival(ArcadeInput raw) {
    final i = mirrorInput(raw);
    var tx = cx, ty = cy;
    if (i.down && i.hasPointer) {
      tx = i.x;
      ty = i.y + 40;
    }
    if (i.dirX != 0) tx = cx + i.dirX * 40;
    if (i.dirY != 0) ty = cy + i.dirY * 40;
    cx = moveToward(cx, clampD(tx, kBdL - 120, kBdR + 120), kBdPSpeed);
    cy = moveToward(cy, clampD(ty, kWorldH - kBdMaxY, kWorldH - kBdMinY), kBdPSpeed * 0.75);
    ctx = cx;
    cty = cy;
  }

  /// Topun [side] tarafında vurulabilir yüksekliğe indiği nokta.
  (double, double, double)? predict(int side, {double zMax = 160}) {
    var x = bx, y = by, z = bz, ux = vx, uy = vy, uz = vz;
    for (var k = 0; k < 300; k++) {
      x += ux;
      y += uy;
      z += uz;
      ux *= kBdDrag;
      uy *= kBdDrag;
      uz = uz * kBdDrag - kBdG;
      final mine = side == 0 ? y > kBdNet + 30 : y < kBdNet - 30;
      if (mine && z < zMax && uz < 0) return (x, y, z);
      if (z <= 0) return (x, y, 0);
    }
    return null;
  }

  void _moveCpu() {
    final sp = 6.8 + d * 0.55;
    if (live && lastHitter == 0 && by < kBdNet + (10 - d) * 40) {
      final p = predict(1);
      if (p != null) {
        ctx = p.$1;
        cty = clampD(p.$2, kWorldH - kBdMaxY, kWorldH - kBdMinY);
      }
    } else if (!live || lastHitter == 1) {
      ctx = 500 + (bx - 500) * 0.3;
      cty = 320;
    }
    cx = moveToward(cx, ctx, sp);
    cy = moveToward(cy, cty, sp * 0.75);
  }

  void _step() {
    final y0 = by;
    bx += vx;
    by += vy;
    bz += vz;
    vx *= kBdDrag;
    vy *= kBdDrag;
    vz = vz * kBdDrag - kBdG;
    if (!netChecked && (y0 - kBdNet) * (by - kBdNet) <= 0) {
      netChecked = true;
      if (bz < kBdNetH) {
        _say(6);
        _point(lastHitter == 1);
        return;
      }
    }
    if (bz <= 0) {
      bz = 0;
      final side = by > kBdNet ? 0 : 1;
      final inside = bx >= kBdL - 4 && bx <= kBdR + 4 && by >= kBdT - 4 && by <= kBdB + 4;
      if (side == lastHitter) {
        _point(lastHitter == 1);
      } else if (!inside) {
        _say(2);
        _point(lastHitter == 1);
      } else {
        _point(lastHitter == 0);
      }
      return;
    }
    if (bz < kBdHitZ && bz > 18) {
      if (lastHitter == 1 && by > kBdNet + 20) {
        if ((bx - px).abs() < kBdReach && (by - py).abs() < 70) _hitBy(0);
      } else if (lastHitter == 0 && by < kBdNet - 20) {
        if (_rival != null) {
          if ((bx - cx).abs() < kBdReach && (by - cy).abs() < 70) _hitBy(1);
        } else if ((bx - cx).abs() < kBdReach * 0.85 && (by - cy).abs() < 60) {
          _cpuHit();
        }
      }
    }
  }

  // ---- DuelSim ----
  @override
  set rivalInput(ArcadeInput? input) => _rival = input;

  @override
  void enableDuel() {
    duel = true;
    lives = 1;
  }

  @override
  int get duelWinner => won ? 0 : (dead ? 1 : -1);

  @override
  List<double> netState() => [
        ticks.toDouble(), bx, by, bz, vx, vy, vz, //
        live ? 1.0 : 0.0, lastHitter.toDouble(), netChecked ? 1.0 : 0.0,
        px, py, cx, cy, ctx, cty,
        power.toDouble(), rivalPower.toDouble(), server.toDouble(), serveWait.toDouble(), pause.toDouble(),
        myPts.toDouble(), cpuPts.toDouble(), myGames.toDouble(), cpuGames.toDouble(),
        ptsToWin.toDouble(), gamesToWin.toDouble(), rally.toDouble(),
        flash.toDouble(), flashTicks.toDouble(), lastEvent.toDouble(), score.toDouble(),
        won ? 1.0 : 0.0, dead ? 1.0 : 0.0, swingAt.toDouble(), rivalSwingAt.toDouble(),
      ];

  @override
  void applyNetState(List<double> s) {
    if (s.length < 36) return;
    int n(int i) => s[i].round();
    ticks = n(0);
    bx = s[1];
    by = s[2];
    bz = s[3];
    vx = s[4];
    vy = s[5];
    vz = s[6];
    live = s[7] > 0.5;
    lastHitter = n(8);
    netChecked = s[9] > 0.5;
    px = s[10];
    py = s[11];
    cx = s[12];
    cy = s[13];
    ctx = s[14];
    cty = s[15];
    power = n(16);
    rivalPower = n(17);
    server = n(18);
    serveWait = n(19);
    pause = n(20);
    myPts = n(21);
    cpuPts = n(22);
    myGames = n(23);
    cpuGames = n(24);
    ptsToWin = n(25);
    gamesToWin = n(26);
    rally = n(27);
    flash = n(28);
    flashTicks = n(29);
    lastEvent = n(30);
    score = n(31);
    if (s[32] > 0.5 && !won) win();
    if (s[33] > 0.5 && !dead) {
      lives = 1;
      shield = 0;
      hit();
    }
    swingAt = n(34);
    rivalSwingAt = n(35);
  }

  @override
  List<double> lerpNet(List<double> a, List<double> b, double f) => lerpAt(a, b, f, const [1, 2, 3, 10, 11, 12, 13]);

  @override
  void mirrorView() {
    bx = kWorldW - bx;
    by = kWorldH - by;
    vx = -vx;
    vy = -vy;
    lastHitter = 1 - lastHitter;
    final ox = px, oy = py;
    px = kWorldW - cx;
    py = kWorldH - cy;
    cx = kWorldW - ox;
    cy = kWorldH - oy;
    ctx = kWorldW - ctx;
    cty = kWorldH - cty;
    final pw = power;
    power = rivalPower;
    rivalPower = pw;
    server = 1 - server;
    final mp = myPts, mg = myGames;
    myPts = cpuPts;
    myGames = cpuGames;
    cpuPts = mp;
    cpuGames = mg;
    final sa = swingAt;
    swingAt = rivalSwingAt;
    rivalSwingAt = sa;
    if (lastEvent == 2) {
      lastEvent = 3;
    } else if (lastEvent == 3) {
      lastEvent = 2;
    }
    const swap = {1: 3, 3: 1, 4: 5, 5: 4};
    flash = swap[flash] ?? flash;
  }

  @override
  bool useBooster() {
    if (over) return false;
    power = 600;
    return true;
  }

  @override
  double get progress {
    if (!matchMode) return 0;
    final per = 1 / gamesToWin;
    return (myGames * per + per * (myPts / ptsToWin).clamp(0.0, 0.95)).clamp(0.0, 1.0);
  }

  @override
  String get goalText => matchMode ? (gamesToWin > 1 ? '$myGames-$cpuGames • $myPts-$cpuPts' : '$myPts-$cpuPts') : '$pointsWon';

  @override
  Map<String, int> get stats => {
        'points_won': pointsWon,
        'matches_won': matchesWon,
        'smashes': smashes,
        'best_rally': bestRally,
        'drop_shots': drops,
      };

  @override
  int get stars {
    if (!won) return 0;
    final q = cpuGames == 0 ? (pointsLost <= ptsToWin ~/ 2 ? 3 : 2) : 1;
    return math.min(lifeStars(this, 3), q);
  }
}

/// Bot: tüy topun ineceği yere koşar, raketin rakipten uzak yanıyla vurur;
/// top yüksekse smaç dener.
ArcadeInput badmintonBot(ArcadeSim sim) {
  final s = sim as BadmintonSim;
  if (!s.live) {
    if (s.server == 0 && s.pause == 0 && s.serveWait > 25) return ArcadeInput(down: true, x: s.px.roundToDouble(), y: (s.py + 40).roundToDouble(), tap: true);
    return ArcadeInput(down: true, x: 500, y: 1360);
  }
  if (s.lastHitter == 1) {
    final p = s.predict(0, zMax: 150);
    if (p != null) {
      final away = s.cx > 500 ? -1.0 : 1.0;
      final tx = p.$1 - away * 0.5 * kBdReach;
      final high = p.$3 > 125;
      final near = (s.by - p.$2).abs() < 260 && s.by > kBdNet;
      return ArcadeInput(
        down: true,
        x: clampD(tx, 0, kWorldW).roundToDouble(),
        y: clampD(p.$2 + 40, 0, kWorldH).roundToDouble(),
        swipe: near && high && s.power == 0 ? 0 : -1,
      );
    }
  }
  return const ArcadeInput(down: true, x: 500, y: 1340);
}

class BadmintonRules extends KitRules {
  BadmintonRules(super.gameId)
      : super(
          optionalMechanics: const [],
          gameStats: const [
            GameStat('points_won', 'Kazanılan sayı', 'Points won', scale: 500),
            GameStat('matches_won', 'Kazanılan maç', 'Matches won', scale: 40),
            GameStat('smashes', 'Smaç', 'Smashes', scale: 200),
            GameStat('best_rally', 'En uzun ralli', 'Longest rally', scale: 30),
            GameStat('drop_shots', 'File önü top', 'Drop shots', scale: 150),
          ],
          missionTemplates: const [
            MissionTemplate('points_won', 'points_won', [125, 250, 500]),
            MissionTemplate('matches_won', 'matches_won', [5, 10, 20], coinReward: 80),
            MissionTemplate('smashes', 'smashes', [40, 100, 200]),
          ],
          make: BadmintonSim.new,
          botFn: badmintonBot,
          ticks: 60 * 60 * 12,
        );

  /// Bilgisayara karşı ve çevrimiçi masa (gerçek zamanlı düello).
  @override
  int get localPlayers => 2;
}

BadmintonRules badmintonRules(String id) => BadmintonRules(id);
