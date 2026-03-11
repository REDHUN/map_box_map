import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../utils/geo_utils.dart' as geo;
import '../viewmodels/search_view_model.dart';
import 'navigation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start with current location as origin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<SearchViewModel>();
      viewModel.setOriginPlaceholder();
      _originController.text = 'Your location';
    });
  }

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  void _onMapCreated(MapboxMap mapboxMap) {}

  void _startNavigation() {
    final viewModel = context.read<SearchViewModel>();
    if (viewModel.destinationPlace?.coordinate != null &&
        viewModel.originPlace?.coordinate != null) {
      geo.LatLng? customOrigin;
      if (viewModel.originPlace?.mapboxId != 'current_location') {
        customOrigin = viewModel.originPlace?.coordinate;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => NavigationScreen(
            destination: viewModel.destinationPlace!.coordinate!,
            customOrigin: customOrigin,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a valid destination and origin"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey("homeMapWidget"),
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(0.0, 0.0)),
              zoom: 2.0,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildSearchCard(),
                Expanded(child: _buildSuggestionsList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _originController,
            decoration: InputDecoration(
              icon: const Icon(Icons.my_location, color: Colors.blue),
              hintText: "Choose starting point",
              border: InputBorder.none,
            ),
            onTap: () {
              context.read<SearchViewModel>().setActiveSearchField('origin');
            },
            onChanged: (val) {
              context.read<SearchViewModel>().setActiveSearchField('origin');
              context.read<SearchViewModel>().search(val);
            },
          ),
          const Divider(),
          TextField(
            controller: _destController,
            decoration: InputDecoration(
              icon: const Icon(Icons.location_on_outlined, color: Colors.red),
              hintText: "Choose destination",
              border: InputBorder.none,
            ),
            onTap: () {
              context.read<SearchViewModel>().setActiveSearchField(
                'destination',
              );
            },
            onChanged: (val) {
              context.read<SearchViewModel>().setActiveSearchField(
                'destination',
              );
              context.read<SearchViewModel>().search(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Consumer<SearchViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.isLoading) {
          return const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          );
        }

        if (viewModel.suggestions.isEmpty &&
            viewModel.destinationPlace != null) {
          // Ready to navigate
          return Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.directions_car),
                label: const Text(
                  "Start Navigation",
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const ui.Size(double.infinity, 56),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                onPressed: _startNavigation,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: viewModel.suggestions.length,
          itemBuilder: (context, index) {
            final place = viewModel.suggestions[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.location_on, color: Colors.grey),
                title: Text(place.name),
                subtitle: Text(place.fullAddress),
                onTap: () {
                  if (viewModel.activeSearchField == 'origin') {
                    _originController.text = place.name;
                  } else {
                    _destController.text = place.name;
                  }

                  viewModel.setSelection(place);
                  viewModel.clearSuggestions();
                  FocusScope.of(context).unfocus(); // hide keyboard
                },
              ),
            );
          },
        );
      },
    );
  }
}
