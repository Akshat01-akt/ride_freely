import 'package:geolocator/geolocator.dart';

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude, this.accuracy, this.heading, this.speed});

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? heading;
  final double? speed;
}

enum LocationProblem { servicesOff, denied, deniedForever, unavailable }

class LocationException implements Exception {
  const LocationException(this.problem);

  final LocationProblem problem;

  String get message => switch (problem) {
        LocationProblem.servicesOff => 'Location is turned off. Turn it on in your phone settings.',
        LocationProblem.denied => 'Location permission is needed. Allow it and try again.',
        LocationProblem.deniedForever => 'Location permission is blocked. Allow it in your phone settings.',
        LocationProblem.unavailable => 'Could not get your location. Move to an open area and try again.',
      };

  @override
  String toString() => message;
}

/// Where the phone is right now. Behind an interface so screens can be tested without a GPS.
abstract class LocationService {
  Future<GeoPoint> current();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<GeoPoint> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw const LocationException(LocationProblem.servicesOff);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) throw const LocationException(LocationProblem.denied);
    if (permission == LocationPermission.deniedForever) throw const LocationException(LocationProblem.deniedForever);
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      return GeoPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        heading: p.heading >= 0 ? p.heading : null,
        speed: p.speed >= 0 ? p.speed : null,
      );
    } catch (_) {
      throw const LocationException(LocationProblem.unavailable);
    }
  }
}
