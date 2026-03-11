import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/location_service.dart';
import '../core/navigation_engine.dart';
import '../models/navigation_route_model.dart';
import '../models/navigation_step_model.dart';
import '../services/mapbox_repository.dart';
import '../utils/geo_utils.dart';

class NavigationViewModel extends ChangeNotifier {
  final MapboxRepository _mapboxRepository;
  final LocationService _locationService;
  final NavigationEngine _navigationEngine;

  bool _isNavigating = false;
  bool get isNavigating => _isNavigating;

  bool _isLoadingRoute = false;
  bool get isLoadingRoute => _isLoadingRoute;

  NavigationRoute? _currentRoute;
  NavigationRoute? get currentRoute => _currentRoute;

  NavigationStep? _currentInstruction;
  NavigationStep? get currentInstruction => _currentInstruction;

  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;

  LatLng? _snappedLocation;
  LatLng? get snappedLocation => _snappedLocation;

  double _currentHeading = 0.0;
  double get currentHeading => _currentHeading;

  double _currentSpeed = 0.0; // m/s
  double get currentSpeed => _currentSpeed;

  double _distanceRemaining = 0.0;
  double get distanceRemaining => _distanceRemaining;

  double _durationRemaining = 0.0;
  double get durationRemaining => _durationRemaining;

  StreamSubscription? _locationSubscription;
  StreamSubscription? _engineInstructionSub;
  StreamSubscription? _engineSnappedSub;
  StreamSubscription? _engineRerouteSub;
  StreamSubscription? _engineProgressSub;

  LatLng? _destination;
  LatLng? _previousLocation;
  DateTime? _lastRerouteAt;

  NavigationViewModel({
    required MapboxRepository mapboxRepository,
    required LocationService locationService,
    required NavigationEngine navigationEngine,
  }) : _mapboxRepository = mapboxRepository,
       _locationService = locationService,
       _navigationEngine = navigationEngine;

  Future<void> initNavigation(
    LatLng destination, {
    LatLng? customOrigin,
  }) async {
    _destination = destination;
    _isLoadingRoute = true;
    notifyListeners();

    LatLng originToUse;
    if (customOrigin != null) {
      originToUse = customOrigin;
      _currentLocation = customOrigin; // simulate being there initially
    } else {
      final position = await _locationService.getCurrentLocation();
      if (position == null) {
        print(
          "Error: Could not get current location (permissions denied or service disabled).",
        );
        _isLoadingRoute = false;
        notifyListeners();
        return;
      }
      _currentLocation = LatLng(position.latitude, position.longitude);
      originToUse = _currentLocation!;
    }

    await _fetchAndStartRoute(originToUse, destination);
  }

  Future<void> _fetchAndStartRoute(LatLng origin, LatLng destination) async {
    _isLoadingRoute = true;
    notifyListeners();

    final route = await _mapboxRepository.getRoute(
      origin: origin,
      destination: destination,
    );

    if (route != null) {
      _currentRoute = route;
      _distanceRemaining = route.distance;
      _durationRemaining = route.duration;
      _isNavigating = true;

      _setupStreams();
      _navigationEngine.startNavigation(route);
      _locationService.startLocationStream();
    }

    _isLoadingRoute = false;
    notifyListeners();
  }

  void _setupStreams() {
    _clearStreams();

    // 1. Listen to raw location from Geolocator
    _locationSubscription = _locationService.locationStream.listen((
      Position position,
    ) {
      final newLocation = LatLng(position.latitude, position.longitude);

      // Calculate heading manually if raw heading is unreliable, but position.heading is usually OK
      if (_currentLocation != null && position.speed > 1.0) {
        if (position.heading.isFinite && position.heading >= 0) {
          _currentHeading = position.heading;
        } else if (_previousLocation != null) {
          final movedDistance = GeoUtils.calculateDistanceInMeters(
            _previousLocation!,
            newLocation,
          );
          // Avoid heading jitter when device barely moved.
          if (movedDistance > 3.0) {
            _currentHeading = GeoUtils.calculateBearing(
              _previousLocation!,
              newLocation,
            );
          }
        }
      }

      _previousLocation = _currentLocation;
      _currentLocation = newLocation;
      _currentSpeed = position.speed >= 0 ? position.speed : 0.0; // meters/s

      // Feed location into engine
      _navigationEngine.updateLocation(_currentLocation!, _currentSpeed);

      notifyListeners();
    });

    // 2. Listen to snapped location from Engine
    _engineSnappedSub = _navigationEngine.snappedLocationStream.listen((
      LatLng snapped,
    ) {
      _snappedLocation = snapped;

      notifyListeners();
    });

    // 3. Listen to instruction updates
    _engineInstructionSub = _navigationEngine.instructionStream.listen((
      NavigationStep step,
    ) {
      _currentInstruction = step;
      notifyListeners();
    });

    // 4. Listen to Reroute events (Deviation > 40m)
    _engineRerouteSub = _navigationEngine.rerouteEventStream.listen((
      LatLng deviationPoint,
    ) {
      if (_destination != null && !_isLoadingRoute) {
        final now = DateTime.now();
        if (_lastRerouteAt != null &&
            now.difference(_lastRerouteAt!) < const Duration(seconds: 4)) {
          return;
        }
        _lastRerouteAt = now;

        // Stop current engine temporarily while fetching new route
        _navigationEngine.stopNavigation();
        unawaited(_fetchAndStartRoute(deviationPoint, _destination!));
      }
    });

    // 5. Listen to Progress updates
    _engineProgressSub = _navigationEngine.progressStream.listen((
      NavigationProgress progress,
    ) {
      _distanceRemaining = progress.distanceRemainingMeters;
      _durationRemaining = progress.durationRemainingSeconds;
      notifyListeners();
    });
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentRoute = null;
    _currentInstruction = null;
    _distanceRemaining = 0.0;
    _durationRemaining = 0.0;
    _previousLocation = null;
    _lastRerouteAt = null;

    _clearStreams();
    _locationService.stopLocationStream();
    _navigationEngine.stopNavigation();

    notifyListeners();
  }

  void _clearStreams() {
    _locationSubscription?.cancel();
    _engineInstructionSub?.cancel();
    _engineSnappedSub?.cancel();
    _engineRerouteSub?.cancel();
    _engineProgressSub?.cancel();
  }

  @override
  void dispose() {
    _clearStreams();
    _locationService.dispose();
    _navigationEngine.dispose();
    super.dispose();
  }
}
