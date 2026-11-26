import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_motoru/badminton.dart' as badminton;
import 'package:arcade_motoru/ucurtma.dart' as ucurtma;
import 'package:studio_core/core/arcade.dart';
import 'package:studio_core/core/arcade_duel.dart';
import 'package:studio_core/core/level_plan.dart';

/// Çevrimiçi düello: ağ durumu taşınabilir, ayna iki kez uygulanınca aynı.
void main() {
  for (final (name, rules) in [
    ('badminton', badminton.badmintonRules('oyun-badminton')),
    ('ucurtma', ucurtma.kiteRules('oyun-ucurtma-savasi')),
  ]) {
    test('$name düello durumu', () {
      expect(rules.localPlayers, 2);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);
      final lv = rules.generate(planner.spec(40));
      final a = rules.createSim(lv);
      for (var i = 0; i < 300 && !a.over; i++) {
        a.tick(rules.bot(a));
      }
      final st = (a as DuelSim).netState();
      final b = rules.createSim(lv);
      final bd = b as DuelSim;
      bd.applyNetState(st);
      expect(bd.netState(), st);
      bd.mirrorView();
      bd.mirrorView();
      final again = bd.netState();
      for (var i = 0; i < st.length; i++) {
        expect((again[i] - st[i]).abs() < 1e-6, isTrue, reason: '$name alan $i');
      }
      // Karşı oyuncu girdisiyle de ilerler.
      bd.rivalInput = const ArcadeInput(down: true, x: 500, y: 1300);
      for (var i = 0; i < 120; i++) {
        b.tick(ArcadeInput.idle);
      }
      expect(b.ticks >= st[0].round(), isTrue);
    });
  }
}
