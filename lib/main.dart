import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() => runApp(const NavArApp());

class NavArApp extends StatelessWidget {
  const NavArApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'NavAR',
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MapController map = MapController();
  final TextEditingController search = TextEditingController();
  StreamSubscription<Position>? locationSub;
  Position? position;
  LatLng? destination;
  String destinationName = '';
  List<LatLng> route = const [];
  bool dark = true;
  bool busy = false;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  @override
  void dispose() {
    locationSub?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;
    final p = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => position = p);
    map.move(LatLng(p.latitude, p.longitude), 15);
    locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((p) {
      if (mounted) setState(() => position = p);
    });
  }

  Future<void> _searchPlace(String value) async {
    final q = value.trim();
    if (q.isEmpty) return;
    setState(() => busy = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'limit': '1',
      });
      final r = await http.get(uri, headers: const {
        'User-Agent': 'NavAR/0.2 open-source navigation app',
      });
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = jsonDecode(r.body) as List<dynamic>;
      if (list.isEmpty) throw Exception('место не найдено');
      final item = list.first as Map<String, dynamic>;
      final point = LatLng(
        double.parse(item['lat'] as String),
        double.parse(item['lon'] as String),
      );
      setState(() {
        destination = point;
        destinationName = item['display_name'] as String? ?? q;
        route = const [];
      });
      map.move(point, 16);
      await _buildRoute();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Поиск: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _buildRoute() async {
    final p = position;
    final d = destination;
    if (p == null || d == null) return;
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${p.longitude},${p.latitude};${d.longitude},${d.latitude}'
        '?overview=full&geometries=geojson',
      );
      final r = await http.get(uri, headers: const {
        'User-Agent': 'NavAR/0.2 open-source navigation app',
      });
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') throw Exception('маршрут не найден');
      final geometry = ((body['routes'] as List).first
          as Map<String, dynamic>)['geometry'] as Map<String, dynamic>;
      final points = (geometry['coordinates'] as List).map((v) {
        final c = v as List;
        return LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble());
      }).toList();
      if (mounted) setState(() => route = points);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Маршрут: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (tab == 2) {
      return ArCameraPage(
        position: position,
        destination: destination,
        destinationName: destinationName,
        onClose: () => setState(() => tab = 0),
      );
    }
    if (tab == 1) {
      return Scaffold(
        appBar: AppBar(title: const Text('Транспорт')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Реальная карта и автомобильная маршрутизация подключены.\n\n'
              'Фиктивные данные общественного транспорта не показываем.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        bottomNavigationBar: _nav(),
      );
    }
    final center = position == null
        ? const LatLng(25.2048, 55.2708)
        : LatLng(position!.latitude, position!.longitude);
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: map,
            options: MapOptions(initialCenter: center, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: dark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.navar.app',
              ),
              if (route.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 6,
                    color: const Color(0xFFFF4B4B),
                  ),
                ]),
              MarkerLayer(markers: [
                if (position != null)
                  Marker(
                    point: LatLng(position!.latitude, position!.longitude),
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.my_location,
                        color: Colors.blue, size: 34),
                  ),
                if (destination != null)
                  Marker(
                    point: destination!,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_pin,
                        color: Color(0xFFFF4B4B), size: 44),
                  ),
              ]),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ]),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Material(
                color: const Color(0xFF242436),
                borderRadius: BorderRadius.circular(16),
                child: TextField(
                  controller: search,
                  onSubmitted: _searchPlace,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Поиск реального адреса или места…',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    suffixIcon: busy
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'locate',
                  onPressed: _startLocation,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'theme',
                  onPressed: () => setState(() => dark = !dark),
                  child: Icon(dark ? Icons.light_mode : Icons.dark_mode),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'ar',
                  onPressed: destination == null
                      ? null
                      : () => setState(() => tab = 2),
                  child: const Icon(Icons.navigation),
                ),
              ],
            ),
          ),
          if (destination != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Card(
                color: const Color(0xFF242436),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.route, color: Color(0xFFFF4B4B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          destinationName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      FilledButton(
                        onPressed: _buildRoute,
                        child: const Text('Маршрут'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _nav(),
    );
  }

  Widget _nav() => NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          if (index == 2 && destination == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Сначала найдите место.')),
            );
            return;
          }
          setState(() => tab = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Карта'),
          NavigationDestination(
              icon: Icon(Icons.directions_transit), label: 'Транспорт'),
          NavigationDestination(icon: Icon(Icons.navigation), label: 'AR'),
        ],
      );
}

class ArCameraPage extends StatefulWidget {
  const ArCameraPage({
    super.key,
    required this.position,
    required this.destination,
    required this.destinationName,
    required this.onClose,
  });
  final Position? position;
  final LatLng? destination;
  final String destinationName;
  final VoidCallback onClose;
  @override
  State<ArCameraPage> createState() => _ArCameraPageState();
}

class _ArCameraPageState extends State<ArCameraPage> {
  CameraController? camera;
  StreamSubscription<CompassEvent>? compassSub;
  double heading = 0;
  String error = '';

  @override
  void initState() {
    super.initState();
    _openCamera();
    compassSub = FlutterCompass.events?.listen((event) {
      if (mounted && event.heading != null) {
        setState(() => heading = event.heading!);
      }
    });
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('камера не найдена');
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => camera = controller);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    compassSub?.cancel();
    camera?.dispose();
    super.dispose();
  }

  double _bearing() {
    final p = widget.position;
    final d = widget.destination;
    if (p == null || d == null) return heading;
    final lat1 = p.latitude * math.pi / 180;
    final lat2 = d.latitude * math.pi / 180;
    final dl = (d.longitude - p.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _distance() {
    final p = widget.position;
    final d = widget.destination;
    if (p == null || d == null) return 0;
    return Geolocator.distanceBetween(
        p.latitude, p.longitude, d.latitude, d.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final bearing = _bearing();
    final delta = ((bearing - heading + 540) % 360) - 180;
    final distance = _distance();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera?.value.isInitialized == true)
            CameraPreview(camera!)
          else
            const Center(child: CircularProgressIndicator()),
          Container(color: Colors.black.withOpacity(.08)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      IconButton.filled(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.72),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(widget.destinationName,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Transform.rotate(
                  angle: delta * math.pi / 180,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.58),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFFFF4B4B), width: 3),
                    ),
                    child: const Icon(Icons.navigation,
                        color: Color(0xFFFF4B4B), size: 92),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.76),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      Text(
                        distance < 1000
                            ? '${distance.toStringAsFixed(0)} м'
                            : '${(distance / 1000).toStringAsFixed(1)} км',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.bold),
                      ),
                      Text(
                          'Цель ${bearing.toStringAsFixed(0)}° · компас ${heading.toStringAsFixed(0)}°'),
                      if (error.isNotEmpty)
                        Text(error,
                            style: const TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
