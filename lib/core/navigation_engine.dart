import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../models/navigation_route_model.dart';
import '../models/navigation_step_model.dart';
import '../utils/geo_utils.dart';


class NavigationProgress {
  final double progressFraction;
  final double distanceRemainingMeters;
  final double durationRemainingSeconds;

  const NavigationProgress({
    required this.progressFraction,
    required this.distanceRemainingMeters,
    required this.durationRemainingSeconds,
  });
}

class NavigationEngine {
  final FlutterTts _flutterTts = FlutterTts();

  NavigationRoute? _currentRoute;
  bool _isNavigating = false;

  // Track progress along the physical route points.
  // This helps us know exactly where we are on the route geometry.
  int _routeProgressIndex = 0;

  // Track the current step index we are trying to reach.
  int _currentStepIndex = 0;

  // Prevent duplicate voice instructions for a given step.
  Set<int> _spokenStepIndices = {};

  final _snappedLocationController = StreamController<LatLng>.broadcast();
  final _instructionController = StreamController<NavigationStep>.broadcast();
  final _rerouteEventController = StreamController<LatLng>.broadcast();
  final _progressController = StreamController<NavigationProgress>.broadcast();

  Stream<LatLng> get snappedLocationStream => _snappedLocationController.stream;
  Stream<NavigationStep> get instructionStream => _instructionController.stream;
  Stream<LatLng> get rerouteEventStream => _rerouteEventController.stream;
  Stream<NavigationProgress> get progressStream => _progressController.stream;

  NavigationEngine() {
    _initTts();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void startNavigation(NavigationRoute route) {
    _currentRoute = route;
    _routeProgressIndex = 0;
    _currentStepIndex = 0;
    _isNavigating = true;
    _spokenStepIndices.clear();

    if (route.steps.isNotEmpty) {
      _instructionController.add(route.steps[_currentStepIndex]);
    }
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentRoute = null;
    _flutterTts.stop();
  }

  void updateLocation(LatLng gpsLocation, double speedInMetersPerSecond) {
    if (!_isNavigating || _currentRoute == null) return;

    final route = _currentRoute!;

    // 1. Map Matching (Snap GPS to Route)
    // To optimize, we don't snap against the whole route every time,
    // only a window ahead of our current progress index.
    final searchWindowStart = _routeProgressIndex;
    final dynamicWindow = speedInMetersPerSecond > 20
        ? 140
        : speedInMetersPerSecond > 10
        ? 90
        : 60;
    final searchWindowEnd = (searchWindowStart + dynamicWindow).clamp(
      0,
      route.routePoints.length,
    );
    final searchPoints = route.routePoints.sublist(
      searchWindowStart,
      searchWindowEnd,
    );

    final snapResult = GeoUtils.snapToRoute(gpsLocation, searchPoints);
    final snappedLocation = snapResult.snappedLocation;

    // Nearest index relative to the full route
    final nearestIndex = searchWindowStart + snapResult.segmentIndex;

    // 2. Route Deviation Detection
    final deviationDistance = GeoUtils.calculateDistanceInMeters(
      gpsLocation,
      snappedLocation,
    );
    if (deviationDistance > 40) {
      _rerouteEventController.add(gpsLocation);
      return;
    }

    // 3. Update Route Progress Index
    if (nearestIndex > _routeProgressIndex) {
      _routeProgressIndex = nearestIndex;
    }

    _snappedLocationController.add(snappedLocation);

    // 4. Progress calculation (0.0 to 1.0)
    final progress = _routeProgressIndex / (route.routePoints.length - 1);
    final progressFraction = progress.clamp(0.0, 1.0);

    final remainingDistance = _calculateRemainingDistance(route, _routeProgressIndex);
    final remainingDuration = route.duration * (1.0 - progressFraction);

    _progressController.add(
      NavigationProgress(
        progressFraction: progressFraction,
        distanceRemainingMeters: remainingDistance,
        durationRemainingSeconds: remainingDuration.clamp(0.0, route.duration),
      ),
    );

    // 5. Step Detection & Instruction Timing
    _checkStepProgress(snappedLocation, speedInMetersPerSecond);
  }

  double _calculateRemainingDistance(NavigationRoute route, int fromIndex) {
    if (route.routePoints.length < 2) return 0.0;
    if (fromIndex >= route.routePoints.length - 1) return 0.0;

    double total = 0.0;
    for (int i = fromIndex; i < route.routePoints.length - 1; i++) {
      total += GeoUtils.calculateDistanceInMeters(
        route.routePoints[i],
        route.routePoints[i + 1],
      );
    }
    return total;
  }


  void _checkStepProgress(LatLng currentLocation, double speed) {
    if (_currentRoute == null ||
        _currentStepIndex >= _currentRoute!.steps.length)
      return;

    final currentStep = _currentRoute!.steps[_currentStepIndex];
    final distanceToStep = GeoUtils.calculateDistanceInMeters(
      currentLocation,
      currentStep.location,
    );

    // Speed-aware instruction timing
    // speed is in m/s.
    // walking (<= 2 m/s) -> 25m
    // city driving (<= 15 m/s) -> 50m
    // highway (> 15 m/s) -> 120m
    double instructionThreshold = 50.0;
    if (speed <= 2.5) {
      instructionThreshold = 25.0; // Walking / cycling very slow
    } else if (speed > 15.0) {
      instructionThreshold = 120.0; // Highway
    }

    // Trigger instruction if within threshold and haven't spoken yet
    if (distanceToStep <= instructionThreshold &&
        !_spokenStepIndices.contains(_currentStepIndex)) {
      _speakInstruction(currentStep.instruction);
      _spokenStepIndices.add(_currentStepIndex);
    }

    // Step completion: if we've passed the step's geometry index
    // Note: Mapbox may provide slightly imperfect coordinate matching,
    // relying strictly on geometry index progress is extremely robust algorithmically.
    if (_routeProgressIndex >= currentStep.geometryIndex) {
      // Step reached! Move to next step if distance is very low or if we are well past the geometry index
      if (distanceToStep < 20.0 ||
          _routeProgressIndex > currentStep.geometryIndex + 2) {
        _currentStepIndex++;
        if (_currentStepIndex < _currentRoute!.steps.length) {
          _instructionController.add(_currentRoute!.steps[_currentStepIndex]);

          // If the next step is very soon, we might speak it immediately
          final nextStep = _currentRoute!.steps[_currentStepIndex];
          final distanceToNextStep = GeoUtils.calculateDistanceInMeters(
            currentLocation,
            nextStep.location,
          );
          if (distanceToNextStep <= instructionThreshold) {
            _speakInstruction(nextStep.instruction);
            _spokenStepIndices.add(_currentStepIndex);
          }
        } else {
          _speakInstruction("You have arrived at your destination.");
          stopNavigation();
        }
      }
    }
  }

  void _speakInstruction(String instruction) async {
    await _flutterTts.speak(instruction);
  }

  void dispose() {
    _flutterTts.stop();
    _snappedLocationController.close();
    _instructionController.close();
    _rerouteEventController.close();
    _progressController.close();
  }
}
