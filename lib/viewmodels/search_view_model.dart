import 'package:flutter/foundation.dart';

import '../models/place_search_model.dart';
import '../services/mapbox_repository.dart';

class SearchViewModel extends ChangeNotifier {
  final MapboxRepository _mapboxRepository;

  SearchViewModel({required MapboxRepository mapboxRepository})
    : _mapboxRepository = mapboxRepository;

  List<PlaceSearchPrediction> _suggestions = [];
  List<PlaceSearchPrediction> get suggestions => _suggestions;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  PlaceSearchPrediction? _originPlace;
  PlaceSearchPrediction? get originPlace => _originPlace;

  PlaceSearchPrediction? _destinationPlace;
  PlaceSearchPrediction? get destinationPlace => _destinationPlace;

  String _activeSearchField = 'destination'; // 'origin' or 'destination'
  String get activeSearchField => _activeSearchField;

  void setActiveSearchField(String field) {
    _activeSearchField = field;
  }

  void setOriginPlaceholder() {
    _originPlace = PlaceSearchPrediction(
      mapboxId: 'current_location',
      name: 'Your Location',
      fullAddress: 'Current Device Location',
    );
    notifyListeners();
  }

  void setOrigin(PlaceSearchPrediction place) {
    _originPlace = place;
    notifyListeners();
  }

  void setDestination(PlaceSearchPrediction place) {
    _destinationPlace = place;
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      _suggestions = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _suggestions = await _mapboxRepository.searchPlaces(query);

    _isLoading = false;
    notifyListeners();
  }

  void setSelection(PlaceSearchPrediction place) {
    if (_activeSearchField == 'origin') {
      _originPlace = place;
    } else {
      _destinationPlace = place;
    }
    notifyListeners();
  }

  void clearSuggestions() {
    _suggestions = [];
    notifyListeners();
  }
}
