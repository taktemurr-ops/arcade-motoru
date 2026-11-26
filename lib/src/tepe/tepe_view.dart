import 'package:flutter/material.dart';

import 'package:studio_core/app/arcade_stage.dart';
import 'package:studio_core/core/arcade.dart';
import '../surus/drive_view.dart';
import '../texts.dart';

/// Tepe Tırmanışı renkleri: gün batımı gökyüzü, toprak tepeler.
const kHillClimbTheme = DriveTheme(Color(0xFF7F5539), Color(0xFF6C584C), Color(0xFFFFFFFF), Color(0xFFFFB703),
    sky: Color(0xFFFFB4A2));

void paintHillClimb(Canvas c, ArcadeSim s, ArcadePalette p, double t) => paintHill(c, s, p, t, arcadeLang, kHillClimbTheme);
