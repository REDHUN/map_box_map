import '../utils/geo_utils.dart';

class PolylineDecoder {
  /// Decodes a polyline string typically returned by Mapbox/Google APIs
  /// into a List of [LatLng].
  /// Uses a precision of 5 decimals (factor = 1e5) by default,
  /// Mapbox uses precision 5 for normal routes, and 6 for Mapbox Directions API
  /// depending on parameters (polyLine precision is param configurable, default 5 or 6).
  /// Typically it is 5 or 6. We provide 5 as default, 6 for OSRM mapbox.
  static List<LatLng> decodePolyline(String encoded, {int precision = 5}) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    double factor = precision == 6 ? 1e6 : 1e5;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      LatLng p = LatLng((lat / factor), (lng / factor));
      poly.add(p);
    }
    return poly;
  }
}
