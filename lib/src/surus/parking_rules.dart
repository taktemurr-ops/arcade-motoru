import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';
import 'park_rules.dart';

class ParkingRules extends ParkRules {
  ParkingRules(String gameId)
      : super(gameId, const [
          GameStat('cars_parked', 'Park edilen araç', 'Cars parked', scale: 50),
          GameStat('perfect_parks', 'Hızlı park', 'Quick parks', scale: 20),
        ], const [
          MissionTemplate('cars_parked', 'cars_parked', [16, 33, 50]),
          MissionTemplate('perfect_parks', 'perfect_parks', [6, 13, 20]),
        ]);
}

