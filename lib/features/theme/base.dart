import 'package:flutter/material.dart';

TextTheme getBaseTextTheme(TextTheme baseTextTheme) {
  return baseTextTheme.copyWith(
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 22,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 17,
    ),
    titleSmall: baseTextTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 15,
    ),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 14.5,
    ),
    labelMedium: baseTextTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 13,
    ),
    labelSmall: baseTextTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      fontSize: 12,
    ),
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 24,
    ),
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 16,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 14.5,
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 13,
    ),
    bodySmall: baseTextTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 11,
    ),
  );
}
