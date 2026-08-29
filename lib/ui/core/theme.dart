import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors
  static const Color bgColor = Color(0xFF030303);
  static const Color activeCyan = Color(0xFF00E5FF);
  static const Color alertRed = Color(0xFFFF1A1A);
  static const Color inactiveGray = Color(0xFF444444);
  static const Color textMuted = Color(0x99FFFFFF);
  static const Color panelBg = Color(0x80000000); // semi-transparent panels

  // Gradients
  static const Gradient metallicDarkRed = LinearGradient(
    begin: Alignment(0.87, -0.5), // approx 150deg
    end: Alignment(-0.87, 0.5),
    colors: [
      Color(0xFF8A0000),
      Color(0xFF4D0000),
      Color(0xFF110000),
    ],
    stops: [0.0, 0.4, 1.0],
  );

  static const Gradient rpmGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xFFFFCC00), // Yellow
      Color(0xFFFF6600), // Orange
      Color(0xFFFF1A1A), // Red
      Color(0xFF990000), // Dark Red
    ],
    stops: [0.0, 0.4, 0.7, 1.0],
  );

  // Typography
  static TextStyle get orbitronTitle => GoogleFonts.orbitron(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        color: Colors.white,
        letterSpacing: 1.5,
      );

  static TextStyle get orbitronLabel => GoogleFonts.orbitron(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: textMuted,
        letterSpacing: 3.0,
      );

  static TextStyle get tekoHuge => GoogleFonts.teko(
        fontSize: 115,
        fontWeight: FontWeight.w700,
        height: 0.8,
        color: Colors.white,
        letterSpacing: -2.0,
      );

  static TextStyle get tekoTelltale => GoogleFonts.teko(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: Colors.white,
      );

  static TextStyle get tekoSensor => GoogleFonts.teko(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: Colors.white,
      );

  static TextStyle get interBody => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      );

  static TextStyle get interLabel => GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: textMuted,
        letterSpacing: 1.0,
      );
}
