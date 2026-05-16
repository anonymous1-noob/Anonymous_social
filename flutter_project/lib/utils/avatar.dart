import 'dart:math';
import 'package:flutter/material.dart';

class AnonymousAvatar {
  static final _colors = [
    Colors.blue,
    Colors.deepPurple,
    Colors.teal,
    Colors.orange,
    Colors.indigo,
    Colors.green,
  ];

  static Color colorFromId(String id) {
    final index = id.hashCode % _colors.length;
    return _colors[index.abs()];
  }

  static String nameFromId(String id) {
    final adjectives = ["Silent", "Hidden", "Mysterious", "Calm", "Curious"];
    final nouns = ["Fox", "Owl", "Wolf", "Tiger", "Raven"];

    final r = Random(id.hashCode);
    return "${adjectives[r.nextInt(adjectives.length)]} "
           "${nouns[r.nextInt(nouns.length)]}";
  }
}
ImageProvider? safeNetworkImageProvider(dynamic url) {
  final value = url?.toString().trim() ?? '';
  if (value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  final hasValidHost = uri != null && uri.hasScheme && uri.host.isNotEmpty;
  final isNetworkScheme = uri?.scheme == 'http' || uri?.scheme == 'https';

  if (!hasValidHost || !isNetworkScheme) return null;
  return NetworkImage(value);
}
