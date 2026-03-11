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
  int _routeProgressIndex = 0;

  // Track the current step index we are trying to reach.
  int _currentStepIndex = 0;

  // Prevent duplicate voice instructions for a given step.
  final Set<int> _spokenStepIndices = {};

  // Precomputed cumulative distance left from each route point index.
  // remainingDistanceFromIndex[i] = distance from point i to destination.
  List<double> _remainingDistanceFromIndex = const [];

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
    await _flutterTts.setLanguage('en-US');
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
    _remainingDistanceFromIndex = _buildRemainingDistanceTable(route.routePoints);

    if (route.steps.isNotEmpty) {
      _instructionController.add(route.steps[_currentStepIndex]);
    }
  }

  void stopNavigation() {
    _isNavigating = false;
    _currentRoute = null;
    _remainingDistanceFromIndex = const [];
    _flutterTts.stop();
  }

  void updateLocation(LatLng gpsLocation, double speedInMetersPerSecond) {
    if (!_isNavigating || _currentRoute == null) return;

    final route = _currentRoute!;
    if (route.routePoints.isEmpty) return;

    // 1. Map Matching (Snap GPS to Route), searching only a forward window.
    final searchWindowStart = _routeProgressIndex;
    final dynamicWindow = speedInMetersPerSecond > 20
        ? 140
        : speedInMetersPerSecond > 10
        ? 90
        : 60;

    final searchWindowEnd =
        (searchWindowStart + dynamicWindow).clamp(0, route.routePoints.length);

    final searchPoints = route.routePoints.sublist(
      searchWindowStart,
      searchWindowEnd,
    );

    final snapResult = GeoUtils.snapToRoute(gpsLocation, searchPoints);
    final snappedLocation = snapResult.snappedLocation;

    // Nearest index relative to the full route.
    final nearestIndex = searchWindowStart + snapResult.segmentIndex;

    // 2. Route Deviation Detection.
    final deviationDistance = GeoUtils.calculateDistanceInMeters(
      gpsLocation,
      snappedLocation,
    );

    if (deviationDistance > 40) {
      _rerouteEventController.add(gpsLocation);
      return;
    }

    // 3. Update Route Progress Index monotonically.
    if (nearestIndex > _routeProgressIndex) {
      _routeProgressIndex = nearestIndex;
    }

    _snappedLocationController.add(snappedLocation);

    // 4. Progress calculation.
    final progressFraction = _calculateProgressFraction(route, _routeProgressIndex);
    final remainingDistance = _calculateRemainingDistance(_routeProgressIndex);
    final remainingDuration = route.duration * (1.0 - progressFraction);

    _progressController.add(
      NavigationProgress(
        progressFraction: progressFraction,
        distanceRemainingMeters: remainingDistance,
        durationRemainingSeconds: remainingDuration.clamp(0.0, route.duration),
      ),
    );

    // 5. Step Detection & Instruction Timing.
    _checkStepProgress(snappedLocation, speedInMetersPerSecond);
  }

  double _calculateProgressFraction(NavigationRoute route, int index) {
    if (route.routePoints.length <= 1) return 1.0;
    final progress = index / (route.routePoints.length - 1);
    return progress.clamp(0.0, 1.0);
  }

  List<double> _buildRemainingDistanceTable(List<LatLng> points) {
    if (points.isEmpty) return const [];

    final remaining = List<double>.filled(points.length, 0.0);
    double sum = 0.0;

    for (int i = points.length - 2; i >= 0; i--) {
      sum += GeoUtils.calculateDistanceInMeters(points[i], points[i + 1]);
      remaining[i] = sum;
    }

    return remaining;
  }

  double _calculateRemainingDistance(int fromIndex) {
    if (_remainingDistanceFromIndex.isEmpty) return 0.0;

    final clampedIndex = fromIndex.clamp(0, _remainingDistanceFromIndex.length - 1);
    return _remainingDistanceFromIndex[clampedIndex];
  }

  void _checkStepProgress(LatLng currentLocation, double speed) {
    if (_currentRoute == null || _currentStepIndex >= _currentRoute!.steps.length) {
      return;
    }

    final currentStep = _currentRoute!.steps[_currentStepIndex];
    final distanceToStep = GeoUtils.calculateDistanceInMeters(
      currentLocation,
      currentStep.location,
    );

    double instructionThreshold = 50.0;
    if (speed <= 2.5) {
      instructionThreshold = 25.0;
    } else if (speed > 15.0) {
      instructionThreshold = 120.0;
    }

    if (distanceToStep <= instructionThreshold &&
        !_spokenStepIndices.contains(_currentStepIndex)) {
      _speakInstruction(currentStep.instruction);
      _spokenStepIndices.add(_currentStepIndex);
    }

    if (_routeProgressIndex >= currentStep.geometryIndex) {
      if (distanceToStep < 20.0 || _routeProgressIndex > currentStep.geometryIndex + 2) {
        _currentStepIndex++;
        if (_currentStepIndex < _currentRoute!.steps.length) {
          _instructionController.add(_currentRoute!.steps[_currentStepIndex]);

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
          _speakInstruction('You have arrived at your destination.');
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
