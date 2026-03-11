import 'package:dio/dio.dart';

import '../models/navigation_route_model.dart';
import '../models/place_search_model.dart';
import '../utils/geo_utils.dart';

class MapboxRepository {
  final Dio _dio;
  final String _apiKey;

  MapboxRepository({required String apiKey, Dio? dio})
    : _apiKey = apiKey,
      _dio = dio ?? Dio();

  /// Fetches a driving route from Mapbox Directions API.
  Future<NavigationRoute?> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
  }) async {
    try {
      final originStr = '${origin.longitude},${origin.latitude}';
      final destStr = '${destination.longitude},${destination.latitude}';

      final url =
          'https://api.mapbox.com/directions/v5/mapbox/$profile/$originStr;$destStr';

      final response = await _dio.get(
        url,
        queryParameters: {
          'access_token': _apiKey,
          'alternatives': false,
          'geometries': 'polyline6', // requesting higher precision polyline
          'overview': 'full',
          'steps': true,
          'annotations': 'distance,duration',
          'language': 'en',
          'voice_instructions': true,
          'banner_instructions': true,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final routeJson = data['routes'][0];
          return NavigationRoute.fromJson(routeJson);
        }
      }
      return null;
    } on DioException catch (e) {
      print('Mapbox API Error: ${e.message}');
      return null;
    } catch (e) {
      print('Unknown error fetching route: $e');
      return null;
    }
  }

  /// Searches for places using Mapbox Geocoding API
  Future<List<PlaceSearchPrediction>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    try {
      final url =
          'https://api.mapbox.com/geocoding/v5/mapbox.places/$query.json';
      final response = await _dio.get(
        url,
        queryParameters: {
          'access_token': _apiKey,
          'autocomplete': true,
          'limit': 5,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final features = response.data['features'] as List?;
        if (features != null) {
          return features
              .map((f) => PlaceSearchPrediction.fromJson(f))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Mapbox Geocoding API Error: $e');
      return [];
    }
  }
}
