import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../utils/geo_utils.dart' as geo;
import '../viewmodels/navigation_view_model.dart';

class NavigationScreen extends StatefulWidget {
  final geo.LatLng destination;
  final geo.LatLng? customOrigin;

  const NavigationScreen({
    Key? key,
    required this.destination,
    this.customOrigin,
  }) : super(key: key);

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with SingleTickerProviderStateMixin {
  MapboxMap? mapboxMap;
  PointAnnotationManager? pointAnnotationManager;
  PolylineAnnotationManager? polylineAnnotationManager;
  PointAnnotation? locationPuck;
  int? _lastRenderedRouteHash;

  // Continuous smoothing for perfectly fluid puck and camera movement
  late Ticker _ticker;
  double? _drawnLat;
  double? _drawnLng;
  double? _drawnHeading;

  geo.LatLng? _targetLocation;
  double _targetHeading = 0.0;

  @override
  void initState() {
    super.initState();

    // Start a continuous ticker for exponential smoothing (fluid engine)
    _ticker = createTicker(_onTick);
    _ticker.start();

    // Start navigation after frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NavigationViewModel>().initNavigation(
        widget.destination,
        customOrigin: widget.customOrigin,
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_targetLocation == null) return;

    // If it's the very first frame, jump instantly to target
    if (_drawnLat == null || _drawnLng == null || _drawnHeading == null) {
      _drawnLat = _targetLocation!.latitude;
      _drawnLng = _targetLocation!.longitude;
      _drawnHeading = _targetHeading;
      _applyCameraAndPuck(geo.LatLng(_drawnLat!, _drawnLng!), _drawnHeading!);
      return;
    }

    // Exponential smoothing factor (0.0 to 1.0).
    // 0.08 at 60fps = very smooth gliding without drifting too far behind
    const double factor = 0.08;

    // 1. Smooth Location
    _drawnLat = _drawnLat! + (_targetLocation!.latitude - _drawnLat!) * factor;
    _drawnLng = _drawnLng! + (_targetLocation!.longitude - _drawnLng!) * factor;

    // 2. Smooth Heading (Shortest Path)
    double diff = _targetHeading - _drawnHeading!;
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }
    _drawnHeading = _drawnHeading! + (diff * factor);

    // 3. Apply changes
    _applyCameraAndPuck(geo.LatLng(_drawnLat!, _drawnLng!), _drawnHeading!);
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
    // Load 3D terrain/puck if needed via mapboxMap.style

    // Initialize annotation managers
    pointAnnotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();
    polylineAnnotationManager = await mapboxMap.annotations
        .createPolylineAnnotationManager();

    // Disable the native location puck since it reads OS GPS and deviates from the road
    await mapboxMap.location.updateSettings(
      LocationComponentSettings(enabled: false),
    );

    // Generate custom Google Maps-style arrow and add to style
    final arrowBytes = await _createCustomArrowImage();
    // Using MbxImage for Mapbox V10
    final mbxImage = MbxImage(width: 80, height: 80, data: arrowBytes);
    await mapboxMap.style.addStyleImage(
      "custom-arrow",
      1.0,
      mbxImage,
      false,
      [],
      [],
      null,
    );

    if (mounted) {
      setState(() {}); // Trigger build to draw the route
    }
  }

  Future<Uint8List> _createCustomArrowImage() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 80.0;

    // Draw Google Maps chevron (arrowhead)
    final path = Path();
    path.moveTo(size / 2, 5); // top tip
    path.lineTo(size - 10, size - 10); // bottom right
    path.lineTo(size / 2, size - 25); // bottom inner
    path.lineTo(10, size - 10); // bottom left
    path.close();

    // Shadow
    canvas.drawShadow(path, Colors.black, 8.0, false);

    // White outline
    final strokePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Blue interior
    final fillPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);

    final img = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<NavigationViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoadingRoute) {
            return const Center(child: CircularProgressIndicator());
          }

          if (viewModel.currentLocation == null) {
            return const Center(child: Text("Fetching location..."));
          }

          _updateMapboxCamera(viewModel);
          _drawRouteIfNeeded(viewModel);

          return Stack(
            children: [
              MapWidget(
                key: const ValueKey("mapWidget"),
                onMapCreated: _onMapCreated,
                cameraOptions: CameraOptions(
                  center: Point(
                    coordinates: Position(
                      viewModel.currentLocation!.longitude,
                      viewModel.currentLocation!.latitude,
                    ),
                  ),
                  zoom: 17.0,
                  bearing: viewModel.currentHeading,
                  pitch: 45.0, // 3D Driving view
                ),
              ),

              // UI Overlay
              if (viewModel.isNavigating) ...[
                // Top Card
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  child: _buildTopInstructionCard(viewModel),
                ),

                // Speed Indicator
                Positioned(
                  left: 16,
                  bottom: 220,
                  child: _buildSpeedWidget(viewModel),
                ),

                // Bottom Stats Card
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomStatsCard(context, viewModel),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _updateMapboxCamera(NavigationViewModel viewModel) {
    if (mapboxMap == null || !viewModel.isNavigating) return;

    final location = viewModel.snappedLocation ?? viewModel.currentLocation!;
    final heading = viewModel.currentHeading;

    // Update the true target location that the Ticker will smoothly pursue
    _targetLocation = location;
    _targetHeading = heading;
  }

  void _applyCameraAndPuck(geo.LatLng location, double heading) {
    // Update Camera
    final cameraOptions = CameraOptions(
      center: Point(
        coordinates: Position(location.longitude, location.latitude),
      ),
      zoom: 18.0,
      bearing: heading,
      pitch: 45.0,
    );
    mapboxMap?.setCamera(cameraOptions);

    // Update custom Location Puck
    _updateLocationPuck(location, heading);
  }

  void _updateLocationPuck(geo.LatLng location, double heading) async {
    if (pointAnnotationManager == null) return;

    if (locationPuck == null) {
      final options = PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(location.longitude, location.latitude),
        ),
        iconImage: 'custom-arrow',
        iconSize: 0.5, // Reduced from 1.0 to make the arrow smaller
        iconRotate: heading,
      );
      locationPuck = await pointAnnotationManager!.create(options);
    } else {
      // Update existing puck
      locationPuck?.geometry = Point(
        coordinates: Position(location.longitude, location.latitude),
      );
      locationPuck?.iconRotate = heading;
      await pointAnnotationManager!.update(locationPuck!);
    }
  }

  void _drawRouteIfNeeded(NavigationViewModel viewModel) async {
    if (polylineAnnotationManager == null || viewModel.currentRoute == null)
      return;

    final route = viewModel.currentRoute!;
    final currentRouteHash = Object.hash(route.distance, route.duration);
    if (_lastRenderedRouteHash == currentRouteHash) return;

    await polylineAnnotationManager!.deleteAll();

    final lineCoordinates = route.routePoints
        .map((p) => Position(p.longitude, p.latitude))
        .toList();

    // Background Polyline (Casing)
    var casingOptions = PolylineAnnotationOptions(
      geometry: LineString(coordinates: lineCoordinates),
      lineColor: const Color(0xFF2E65E2).value, // Darker blue outline
      lineWidth: 10.0,
      lineOpacity: 1.0,
      lineJoin: LineJoin.ROUND,
    );

    // Foreground Polyline (Inner Line)
    var innerOptions = PolylineAnnotationOptions(
      geometry: LineString(coordinates: lineCoordinates),
      lineColor: const Color(0xFF4C8CFF).value, // Google Maps style light blue
      lineWidth: 6.0,
      lineOpacity: 1.0,
      lineJoin: LineJoin.ROUND,
    );

    // Create casing first so it's behind the inner line
    await polylineAnnotationManager!.create(casingOptions);
    await polylineAnnotationManager!.create(innerOptions);
    _lastRenderedRouteHash = currentRouteHash;
  }

  Widget _buildTopInstructionCard(NavigationViewModel viewModel) {
    if (viewModel.currentInstruction == null) return const SizedBox.shrink();

    String distanceString = "--";
    String distanceUnit = "meters";
    if (viewModel.distanceRemaining < 1000) {
      distanceString = viewModel.distanceRemaining.toStringAsFixed(0);
      distanceUnit = "meters";
    } else {
      distanceString = (viewModel.distanceRemaining / 1000).toStringAsFixed(1);
      distanceUnit = "km";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1D5CFF), // Mapbox blue style
              borderRadius: BorderRadius.circular(12),
            ),
            child: _getManeuverIcon(viewModel.currentInstruction!.modifier),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      distanceString,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      distanceUnit,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
                Text(
                  viewModel.currentInstruction!.instruction,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedWidget(NavigationViewModel viewModel) {
    final speedKmh = (viewModel.currentSpeed * 3.6).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            speedKmh,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Colors.black87,
            ),
          ),
          const Text(
            "KM/H",
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatsCard(
    BuildContext context,
    NavigationViewModel viewModel,
  ) {
    // Current route distance string calculation (example showing km)
    final distanceLeft = viewModel.currentRoute?.distance ?? 0.0;
    final totalDistance =
        viewModel.currentRoute?.distance ?? 1.0; // avoid div/0
    // Real progress needs a 'total route distance' from initial route. Assuming distanceLeft here.
    // For simplicity just using distanceLeft to drive the progress bar backwards, or just a dummy fill.
    final progress =
        1.0 - (distanceLeft / (totalDistance > 0 ? totalDistance : 1));

    String distanceTotalStr = _formatDistance(distanceLeft);
    String timeEst =
        "00:00"; // Can compute from DateTime.now() + durationRemaining
    final now = DateTime.now();
    final arrival = now.add(
      Duration(seconds: viewModel.durationRemaining.round()),
    );
    timeEst =
        "${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}";

    int minutes = (viewModel.durationRemaining / 60).round();

    return Container(
      padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 5),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatCol("ETA", timeEst, isPrimary: false),
              _buildStatCol("TIME", "$minutes min", isPrimary: true),
              _buildStatCol("DISTANCE", distanceTotalStr, isPrimary: false),
            ],
          ),
          const SizedBox(height: 16),
          // Progress bar
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade200,
            color: const Color(0xFF1D5CFF),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "ORIGIN",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "DESTINATION",
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: Colors.black87,
                  ),
                  label: const Text(
                    "Add Stop",
                    style: TextStyle(color: Colors.black87),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    context.read<NavigationViewModel>().stopNavigation();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 20,
                    color: Colors.red,
                  ),
                  label: const Text(
                    "End Trip",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCol(String title, String value, {bool isPrimary = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 24,
            color: isPrimary ? const Color(0xFF1D5CFF) : Colors.black87,
          ),
        ),
      ],
    );
  }

  Icon _getManeuverIcon(String modifier) {
    IconData iconData = Icons.turn_sharp_right;
    if (modifier.contains('left')) {
      iconData = Icons.turn_left;
    } else if (modifier.contains('right')) {
      iconData = Icons.turn_right;
    } else if (modifier.contains('straight')) {
      iconData = Icons.straight;
    } else if (modifier.contains('u-turn')) {
      iconData = Icons.u_turn_right;
    }
    return Icon(iconData, size: 48, color: Colors.white);
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return "${meters.toStringAsFixed(0)} m";
    } else {
      return "${(meters / 1000).toStringAsFixed(1)} km";
    }
  }
}
