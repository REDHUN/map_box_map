import 'dart:math' as math;

/// A simple representation of a geographic coordinate.
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

/// A wrapper for snapping results.
class SnapResult {
  final LatLng snappedLocation;
  final int segmentIndex;

  SnapResult({required this.snappedLocation, required this.segmentIndex});
}

class GeoUtils {
  static const double earthRadiusKm = 6371.0;

  /// Approximates the distance between two coordinates in meters.
  /// Uses Haversine Formula.
  static double calculateDistanceInMeters(LatLng point1, LatLng point2) {
    if (point1.latitude == point2.latitude &&
        point1.longitude == point2.longitude) {
      return 0;
    }

    var lat1Rad = _degreesToRadians(point1.latitude);
    var lon1Rad = _degreesToRadians(point1.longitude);
    var lat2Rad = _degreesToRadians(point2.latitude);
    var lon2Rad = _degreesToRadians(point2.longitude);

    var dLat = lat2Rad - lat1Rad;
    var dLon = lon2Rad - lon1Rad;

    var a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    var c = 2 * math.asin(math.sqrt(a));
    return earthRadiusKm * c * 1000.0;
  }

  /// Calculates the bearing from [start] to [end] in degrees (0..360)
  static double calculateBearing(LatLng start, LatLng end) {
    var lat1 = _degreesToRadians(start.latitude);
    var lon1 = _degreesToRadians(start.longitude);
    var lat2 = _degreesToRadians(end.latitude);
    var lon2 = _degreesToRadians(end.longitude);

    var dLon = lon2 - lon1;

    var y = math.sin(dLon) * math.cos(lat2);
    var x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    var bearing = math.atan2(y, x);
    return (_radiansToDegrees(bearing) + 360) % 360;
  }

  /// Map matching logic to snap a noisy GPS point to the nearest
  /// route polyline segment and returns the snapped point and the
  /// index of the starting point of the segment.
  static SnapResult snapToRoute(LatLng gpsLocation, List<LatLng> routePoints) {
    if (routePoints.isEmpty) {
      return SnapResult(snappedLocation: gpsLocation, segmentIndex: 0);
    }
    if (routePoints.length == 1) {
      return SnapResult(snappedLocation: routePoints.first, segmentIndex: 0);
    }

    double minDistance = double.infinity;
    LatLng closestPoint = routePoints.first;
    int closestIndex = 0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      LatLng start = routePoints[i];
      LatLng end = routePoints[i + 1];

      LatLng projected = _projectPointOnSegment(gpsLocation, start, end);
      double dist = calculateDistanceInMeters(gpsLocation, projected);

      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = projected;
        closestIndex = i;
      }
    }

    return SnapResult(
      snappedLocation: closestPoint,
      segmentIndex: closestIndex,
    );
  }

  static LatLng _projectPointOnSegment(LatLng point, LatLng start, LatLng end) {
    var latP = point.latitude;
    var lonP = point.longitude;
    var latA = start.latitude;
    var lonA = start.longitude;
    var latB = end.latitude;
    var lonB = end.longitude;

    var dx = lonB - lonA;
    var dy = latB - latA;
    var lenSq = dx * dx + dy * dy;

    if (lenSq == 0) return start; // A and B are the same point

    // Compute dot product to find projection length parameter t
    var t = ((lonP - lonA) * dx + (latP - latA) * dy) / lenSq;

    if (t < 0) return start; // Projects beyond A
    if (t > 1) return end; // Projects beyond B

    return LatLng(latA + t * dy, lonA + t * dx);
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  static double _radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }
}
