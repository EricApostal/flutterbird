import 'package:flutter/material.dart';

/// Splits [rawUrl] into scheme/path (dim) vs host (prominent) spans so the
/// host stands out in suggestion rows and the omnibox overlay, matching the
/// way most browser address bars style the authority.
TextSpan styledUrlSpan(ThemeData theme, String rawUrl) {
  final baseStyle = theme.textTheme.bodyMedium!;
  final primary = baseStyle.copyWith(color: theme.colorScheme.onSurface);
  final secondary = baseStyle.copyWith(
    color: theme.colorScheme.onSurface.withAlpha(140),
  );

  final url = rawUrl.trim();
  if (url.isEmpty) {
    return TextSpan(text: '', style: primary);
  }

  final schemeSeparatorIndex = url.indexOf('://');
  final authorityStart = schemeSeparatorIndex >= 0
      ? schemeSeparatorIndex + 3
      : 0;
  if (authorityStart >= url.length) {
    return TextSpan(text: url, style: primary);
  }

  final delimiters = ['/', '?', '#'];
  var authorityEnd = url.length;
  for (final delimiter in delimiters) {
    final index = url.indexOf(delimiter, authorityStart);
    if (index >= 0 && index < authorityEnd) {
      authorityEnd = index;
    }
  }

  final authority = url.substring(authorityStart, authorityEnd);
  if (authority.isEmpty) {
    return TextSpan(text: url, style: primary);
  }

  var hostCandidate = authority;
  final userInfoSeparator = hostCandidate.lastIndexOf('@');
  if (userInfoSeparator >= 0 && userInfoSeparator + 1 < hostCandidate.length) {
    hostCandidate = hostCandidate.substring(userInfoSeparator + 1);
  }

  if (hostCandidate.startsWith('[')) {
    final closingBracket = hostCandidate.indexOf(']');
    if (closingBracket > 0) {
      hostCandidate = hostCandidate.substring(0, closingBracket + 1);
    }
  } else {
    final colonIndex = hostCandidate.lastIndexOf(':');
    if (colonIndex > 0 && hostCandidate.indexOf(':') == colonIndex) {
      hostCandidate = hostCandidate.substring(0, colonIndex);
    }
  }

  if (hostCandidate.isEmpty) {
    return TextSpan(text: url, style: primary);
  }

  final hostStart = url.indexOf(hostCandidate, authorityStart);
  if (hostStart < 0) {
    return TextSpan(text: url, style: primary);
  }

  final hostEnd = hostStart + hostCandidate.length;
  final prefix = url.substring(0, hostStart);
  final suffix = url.substring(hostEnd);

  return TextSpan(
    style: secondary,
    children: [
      if (prefix.isNotEmpty) TextSpan(text: prefix),
      TextSpan(text: url.substring(hostStart, hostEnd), style: primary),
      if (suffix.isNotEmpty) TextSpan(text: suffix),
    ],
  );
}
