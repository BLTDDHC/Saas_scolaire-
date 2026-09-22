import 'package:flutter/material.dart';

/// Ombres EduPro — reproduction exacte de variables.css
class AppShadows {
  AppShadows._();

  // ---- Light Mode ----
  static const List<BoxShadow> xs = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0D000000)),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x14000000)),
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0A000000)),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, spreadRadius: -1, color: Color(0x14000000)),
    BoxShadow(offset: Offset(0, 2), blurRadius: 4, spreadRadius: -2, color: Color(0x0D000000)),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(offset: Offset(0, 10), blurRadius: 15, spreadRadius: -3, color: Color(0x14000000)),
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, spreadRadius: -4, color: Color(0x0A000000)),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(offset: Offset(0, 20), blurRadius: 25, spreadRadius: -5, color: Color(0x14000000)),
    BoxShadow(offset: Offset(0, 8), blurRadius: 10, spreadRadius: -6, color: Color(0x0A000000)),
  ];

  static const List<BoxShadow> xxl = [
    BoxShadow(offset: Offset(0, 25), blurRadius: 50, spreadRadius: -12, color: Color(0x26000000)),
  ];

  static const List<BoxShadow> inner = [
    BoxShadow(offset: Offset(0, 2), blurRadius: 4, color: Color(0x0D000000)),
  ];

  // ---- Dark Mode ----
  static const List<BoxShadow> darkXs = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x33000000)),
  ];

  static const List<BoxShadow> darkSm = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x4D000000)),
    BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x33000000)),
  ];

  static const List<BoxShadow> darkMd = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, spreadRadius: -1, color: Color(0x4D000000)),
    BoxShadow(offset: Offset(0, 2), blurRadius: 4, spreadRadius: -2, color: Color(0x33000000)),
  ];

  static const List<BoxShadow> darkLg = [
    BoxShadow(offset: Offset(0, 10), blurRadius: 15, spreadRadius: -3, color: Color(0x4D000000)),
    BoxShadow(offset: Offset(0, 4), blurRadius: 6, spreadRadius: -4, color: Color(0x33000000)),
  ];

  /// Ombre spéciale bouton primary
  static const List<BoxShadow> primaryButton = [
    BoxShadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x4D4F46E5)),
  ];

  static const List<BoxShadow> primaryButtonHover = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 12, color: Color(0x594F46E5)),
  ];

  /// Ombre du logo
  static const List<BoxShadow> logoIcon = [
    BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color(0x4D4F46E5)),
  ];
}
