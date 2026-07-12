import 'package:flutter/material.dart';

/// PensaConnect brand tokens: "golden hour fellowship".
///
/// A warm dusk-to-gold palette meant to feel like walking into a
/// worship gathering as the sun goes down — deep, calm indigo giving
/// way to warm candlelight gold. Used across the app instead of the
/// generic Material seed-color purple.
class AppColors {
  AppColors._();

  /// Deep aubergine-indigo. Primary dark surface / on-light text.
  static const inkDusk = Color(0xFF241B3A);

  /// Near-black dusk. Base background in dark mode.
  static const deepDusk = Color(0xFF1C1730);

  /// Warm amber-gold. The signature accent — warmth, worship, light.
  static const emberGold = Color(0xFFE8963B);

  /// Muted green. Growth, prayer, community.
  static const verdantSage = Color(0xFF56795F);

  /// Soft warm off-white. Light-mode background.
  static const warmLinen = Color(0xFFFBF5EC);

  /// Soft rose. Welcome moments, highlights, badges.
  static const roseQuartz = Color(0xFFE8919B);
}

/// Shared shape language for the app.
class AppShapes {
  AppShapes._();

  /// The "chapel doorway" motif: a wide arch at the top, a quiet
  /// rectangle at the base. This is the app's one signature shape —
  /// used for cards, panels, and auth containers. Buttons stay pill
  /// shaped and avatars stay circular so the motif doesn't get diluted.
  static RoundedRectangleBorder archBorder({double top = 28, double bottom = 14}) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(top),
        topRight: Radius.circular(top),
        bottomLeft: Radius.circular(bottom),
        bottomRight: Radius.circular(bottom),
      ),
    );
  }

  static const pill = StadiumBorder();
}
