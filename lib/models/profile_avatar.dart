import 'package:flutter/material.dart';

/// Single avatar option for the profile (icon-based for anonymity and no asset dependency).
class ProfileAvatar {
  const ProfileAvatar({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;
}

/// Curated set of avatars shown across the app (bids, wins, profile).
/// Users pick one; it appears with their nickname for a consistent, privacy-first identity.
const List<ProfileAvatar> kProfileAvatars = [
  ProfileAvatar(id: '0', icon: Icons.diamond_outlined, label: 'Diamond'),
  ProfileAvatar(id: '1', icon: Icons.star_outline, label: 'Star'),
  ProfileAvatar(id: '2', icon: Icons.favorite_border, label: 'Heart'),
  ProfileAvatar(id: '3', icon: Icons.auto_awesome, label: 'Spark'),
  ProfileAvatar(id: '4', icon: Icons.watch_outlined, label: 'Watch'),
  ProfileAvatar(id: '5', icon: Icons.style_outlined, label: 'Style'),
  ProfileAvatar(id: '6', icon: Icons.celebration_outlined, label: 'Celebration'),
  ProfileAvatar(id: '7', icon: Icons.bolt_outlined, label: 'Bolt'),
  ProfileAvatar(id: '8', icon: Icons.anchor, label: 'Anchor'),
  ProfileAvatar(id: '9', icon: Icons.rocket_launch_outlined, label: 'Rocket'),
  ProfileAvatar(id: '10', icon: Icons.nightlight_outlined, label: 'Moon'),
  ProfileAvatar(id: '11', icon: Icons.wb_sunny_outlined, label: 'Sun'),
];

const String kDefaultAvatarId = '0';

ProfileAvatar getProfileAvatarById(String? id) {
  if (id == null || id.isEmpty) {
    return kProfileAvatars.first;
  }
  return kProfileAvatars.firstWhere(
    (a) => a.id == id,
    orElse: () => kProfileAvatars.first,
  );
}

/// Public display name: nickname if set, otherwise fallback (e.g. displayName or "Bidder").
String getPublicDisplayName(Map<String, dynamic>? userData, {String fallback = 'Bidder'}) {
  if (userData == null) return fallback;
  final nickname = userData['nickname'] as String?;
  if (nickname != null && nickname.trim().isNotEmpty) return nickname.trim();
  final displayName = userData['displayName'] as String?;
  if (displayName != null && displayName.trim().isNotEmpty) return displayName.trim();
  return fallback;
}
