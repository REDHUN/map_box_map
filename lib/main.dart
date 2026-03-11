import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

import 'core/location_service.dart';
import 'core/navigation_engine.dart';
import 'core/secrets.dart';
import 'services/mapbox_repository.dart';
import 'viewmodels/navigation_view_model.dart';
import 'viewmodels/search_view_model.dart';
import 'views/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  MapboxOptions.setAccessToken(Secrets.mapboxApiKey);

  runApp(
    MultiProvider(
      providers: [
        Provider<MapboxRepository>(
          create: (_) => MapboxRepository(apiKey: Secrets.mapboxApiKey),
        ),
        Provider<LocationService>(create: (_) => LocationService()),
        Provider<NavigationEngine>(create: (_) => NavigationEngine()),
        ChangeNotifierProvider<NavigationViewModel>(
          create: (context) => NavigationViewModel(
            mapboxRepository: context.read<MapboxRepository>(),
            locationService: context.read<LocationService>(),
            navigationEngine: context.read<NavigationEngine>(),
          ),
        ),
        ChangeNotifierProvider<SearchViewModel>(
          create: (context) => SearchViewModel(
            mapboxRepository: context.read<MapboxRepository>(),
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideNav',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
