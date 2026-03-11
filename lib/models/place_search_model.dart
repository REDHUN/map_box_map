import '../utils/geo_utils.dart';

class PlaceSearchPrediction {
  final String mapboxId;
  final String name;
  final String fullAddress;
  final LatLng? coordinate;

  PlaceSearchPrediction({
    required this.mapboxId,
    required this.name,
    required this.fullAddress,
    this.coordinate,
  });

  factory PlaceSearchPrediction.fromJson(Map<String, dynamic> json) {
    LatLng? coord;
    if (json['center'] != null &&
        json['center'] is List &&
        json['center'].length == 2) {
      coord = LatLng(
        json['center'][1],
        json['center'][0],
      ); // Mapbox returns [lon, lat]
    }

    return PlaceSearchPrediction(
      mapboxId: json['id'] ?? '',
      name: json['text'] ?? '',
      fullAddress: json['place_name'] ?? '',
      coordinate: coord,
    );
  }
}

class PlaceDetails {
  final String mapboxId;
  final LatLng location;

  PlaceDetails({required this.mapboxId, required this.location});
}
