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

    // As we process steps, Mapbox paths correlate. The Mapbox APIs
    // step `geometry` also has arrays. To simplify, we keep track using standard offsets
    // if `geometry_index` is missing. Mapbox API usually provides step geometry.
    int currentIndex = 0;

    for (var leg in legs) {
      final legSteps = leg['steps'] as List<dynamic>? ?? [];
      for (var stepJson in legSteps) {
        // Decoding step geometry temporarily just to count the points
        // so we can set the geometry index for the next step.
        final stepGeometryStr = stepJson['geometry'] as String? ?? '';
        final stepPts = PolylineDecoder.decodePolyline(
          stepGeometryStr,
          precision: 6,
        );

        stepsList.add(NavigationStep.fromJson(stepJson, currentIndex));

        // Advance current index (Mapbox step segments share the end-start point,
        // so we often do math.max(0, stepPts.length - 1))
        currentIndex += (stepPts.isNotEmpty ? stepPts.length - 1 : 0);
      }
    }

    return NavigationRoute(
      distance: distance,
      duration: duration,
      routePoints: points,
      steps: stepsList,
    );
  }
}
