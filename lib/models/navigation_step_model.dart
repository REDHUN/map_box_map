import '../utils/geo_utils.dart';

class NavigationStep {
  final String instruction;
  final double distance; // Distance in meters for this step
  final double duration; // Expected duration in seconds
  final LatLng location; // The exact coordinate where the maneuver happens
  final String maneuverType; // e.g. 'turn', 'depart', 'arrive'
  final String modifier; // e.g. 'right', 'left', 'straight'
  final int
  geometryIndex; // the index in the full route polyline where this step starts

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    required this.maneuverType,
    required this.modifier,
    required this.geometryIndex,
  });

  /// Factory to parse from Mapbox Directions API 'step' JSON object.
  factory NavigationStep.fromJson(
    Map<String, dynamic> json,
    int pointIndexOffset,
  ) {
    final maneuver = json['maneuver'] ?? {};
    final locationRaw = maneuver['location'] as List<dynamic>? ?? [0.0, 0.0];

    // Mapbox puts longitude first: [lng, lat]
    final latLng = LatLng(
      (locationRaw[1] as num).toDouble(),
      (locationRaw[0] as num).toDouble(),
    );

    // Some simple fallback parsing
    return NavigationStep(
      instruction: maneuver['instruction'] ?? 'Proceed',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      location: latLng,
      maneuverType: maneuver['type'] ?? 'unknown',
      modifier: maneuver['modifier'] ?? 'none',
      // geometryIndex requires accumulation from waypoints, handled in route parser
      geometryIndex: pointIndexOffset,
    );
  }
}
