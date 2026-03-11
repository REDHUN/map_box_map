import '../utils/geo_utils.dart';
import 'navigation_step_model.dart';
import '../core/polyline_decoder.dart';

class NavigationRoute {
  final double distance; // Total route distance in meters
  final double duration; // Total route duration in seconds
  final List<LatLng> routePoints; // Decoded full geometry of the route
  final List<NavigationStep> steps; // Detailed steps

  NavigationRoute({
    required this.distance,
    required this.duration,
    required this.routePoints,
    required this.steps,
  });

  /// Factory to parse the 'route' object directly from Mapbox Directions API response.
  factory NavigationRoute.fromJson(Map<String, dynamic> json) {
    final distance = (json['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['duration'] as num?)?.toDouble() ?? 0.0;

    // Decode geometry
    final geometryStr = json['geometry'] as String? ?? '';
    // Mapbox Directions API usually uses precision 5 for default v5,
    // but sometimes 6 depending on specific 'geometry=polyline6' request query
    final points = PolylineDecoder.decodePolyline(geometryStr, precision: 6);

    // Parse legs/steps
    final stepsList = <NavigationStep>[];
    final legs = json['legs'] as List<dynamic>? ?? [];

    // We use the route geometry itself as the source of truth.
    // For each step, find the nearest point on the full route *ahead of the
    // last matched point*. This gives significantly more stable and accurate
    // step indexing than relying purely on decoded step geometry lengths.
    int lastMatchedIndex = 0;

    for (var leg in legs) {
      final legSteps = leg['steps'] as List<dynamic>? ?? [];
      for (var stepJson in legSteps) {
        final maneuver = stepJson['maneuver'] as Map<String, dynamic>? ?? {};
        final locationRaw = maneuver['location'] as List<dynamic>? ?? [0.0, 0.0];
        final stepLocation = LatLng(
          (locationRaw[1] as num).toDouble(),
          (locationRaw[0] as num).toDouble(),
        );

        final geometryIndex = _findNearestRouteIndex(
          routePoints: points,
          target: stepLocation,
          startIndex: lastMatchedIndex,
        );

        stepsList.add(NavigationStep.fromJson(stepJson, geometryIndex));
        lastMatchedIndex = geometryIndex;
      }
    }

    return NavigationRoute(
      distance: distance,
      duration: duration,
      routePoints: points,
      steps: stepsList,
    );
  }

  static int _findNearestRouteIndex({
    required List<LatLng> routePoints,
    required LatLng target,
    required int startIndex,
  }) {
    if (routePoints.isEmpty) return 0;

    int bestIndex = startIndex.clamp(0, routePoints.length - 1);
    double bestDistance = double.infinity;

    for (int i = bestIndex; i < routePoints.length; i++) {
      final d = GeoUtils.calculateDistanceInMeters(routePoints[i], target);
      if (d < bestDistance) {
        bestDistance = d;
        bestIndex = i;
      }

      // Early-stop once distance starts growing after a very close match.
      if (bestDistance < 5.0 && d > bestDistance * 1.5) {
        break;
      }
    }

    return bestIndex;
  }
}
