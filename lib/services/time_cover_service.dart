import 'package:flutter/services.dart';

/// Resolves optional launch cover assets by traditional Chinese double-hour.
///
/// Put images in `assets/time_covers/` with one of these names:
/// `zi`, `chou`, `yin`, `mao`, `chen`, `si`, `wu`, `wei`, `shen`, `you`, `xu`,
/// `hai`, using `.png`, `.jpg`, `.jpeg`, or `.webp`.
///
/// Missing assets are treated as "no custom cover" instead of an error.
class TimeCoverService {
  const TimeCoverService();

  static const List<String> _extensions = ['png', 'jpg', 'jpeg', 'webp'];

  String branchFor(DateTime time) {
    final hour = time.hour;
    if (hour == 23 || hour == 0) return 'zi';
    if (hour <= 2) return 'chou';
    if (hour <= 4) return 'yin';
    if (hour <= 6) return 'mao';
    if (hour <= 8) return 'chen';
    if (hour <= 10) return 'si';
    if (hour <= 12) return 'wu';
    if (hour <= 14) return 'wei';
    if (hour <= 16) return 'shen';
    if (hour <= 18) return 'you';
    if (hour <= 20) return 'xu';
    return 'hai';
  }

  Future<String?> resolveAsset(DateTime time) async {
    final branch = branchFor(time);
    for (final extension in _extensions) {
      final path = 'assets/time_covers/$branch.$extension';
      try {
        await rootBundle.load(path);
        return path;
      } catch (_) {
        // Try the next supported extension.
      }
    }
    return null;
  }
}
