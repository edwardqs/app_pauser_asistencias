class GeoPosition {
  final double latitude;
  final double longitude;
  final double accuracy;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
  });
}

class LocationService {
  Future<GeoPosition?> getCurrentPosition() async => null;

  Future<bool> hasPermission() async => false;

  Future<bool> requestPermission() async => false;
}
