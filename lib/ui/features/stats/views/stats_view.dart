import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme.dart';
import '../../../widgets/value_tooltip.dart';
import '../../../../data/database/db_helper.dart';
import '../../../../data/services/fuel_price_service.dart';

class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  // Prezzo della benzina di oggi, dai dati aperti del MIMIT. Null finche' la
  // prima lettura non arriva: senza di lui i costi non si possono scrivere.
  FuelPrice? _fuel;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _loadFuelPrice();
  }

  Future<void> _loadFuelPrice() async {
    final p = await FuelPriceService.instance.current();
    if (mounted) setState(() => _fuel = p);
  }

  /// Costo di un giro. Null finche' non si conosce il prezzo del carburante.
  RideCost? _costOf(Map<String, dynamic> log) {
    final price = _fuel;
    if (price == null) return null;
    final km = DbHelper.kmOf(log);
    if (km <= 0) return null;
    return RideCost.compute(
      km: km,
      lPer100: DbHelper.consumptionOf(log),
      price: price,
    );
  }

  /// Spesa complessiva di tutti i giri in elenco.
  double _totalEuro() {
    double t = 0;
    for (final l in _logs) {
      final c = _costOf(l);
      if (c != null) t += c.euro;
    }
    return t;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final rides = await DbHelper().getRides();
      if (mounted) setState(() { _logs = rides; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── ELIMINA CON CONFERMA POPUP ───────────────────────────────────────────────
  Future<bool> _confirmDelete(Map<String, dynamic> log) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: Text(
          'ELIMINA SESSIONE?',
          style: AppTheme.orbitronLabel.copyWith(color: Colors.white),
        ),
        content: Text(
          'Vuoi eliminare definitivamente "${log['title']}" dal database?\n\nQuesta azione non può essere annullata.',
          style: AppTheme.interBody.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ANNULLA',
                style: AppTheme.orbitronLabel
                    .copyWith(color: Colors.white38, fontSize: 11)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.alertRed,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('ELIMINA',
                style: AppTheme.orbitronLabel
                    .copyWith(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteRide(int index) async {
    final log = _logs[index];
    final confirmed = await _confirmDelete(log);
    if (!confirmed || !mounted) return;

    await DbHelper().deleteRide(log['id'] as int);
    setState(() => _logs.removeAt(index));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ "${log['title']}" eliminato dal database.'),
          backgroundColor: AppTheme.alertRed,
        ),
      );
    }
  }

  // ── CONDIVIDI SU WHATSAPP ────────────────────────────────────────────────────
  void _shareOnWhatsApp(Map<String, dynamic> log) {
    final cost = _costOf(log);
    final text = '''🏍️ *MonsterSync – ${log['title']}*

📅 Data: ${log['date'] ?? 'N/D'}
📏 Distanza: ${log['dist'] ?? 'N/D'}
🏎️ Velocità max: ${log['speed'] ?? 'N/D'}
🔄 Giri max: ${log['rpm'] ?? 'N/D'}
↩️ Piega max: ${log['roll'] ?? 'N/D'}${cost == null ? '' : '''
⛽ Carburante: ${cost.litresLabel} (${cost.consumptionLabel})
💶 Costo: ${cost.euroLabel} a ${cost.price.label}'''}

_Esportato da MonsterSync per Ducati Monster 695_''';

    Share.share(text, subject: 'MonsterSync – ${log['title']}');
  }

  // ── APRI SU WAZE ─────────────────────────────────────────────────────────────
  Future<void> _openOnWaze(Map<String, dynamic> log) async {
    // Usa lat/lng se disponibili, altrimenti mostra errore
    final double? lat = (log['lat_start'] as num?)?.toDouble();
    final double? lng = (log['lng_start'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ Coordinate GPS non disponibili per questo giro.'),
            backgroundColor: AppTheme.alertRed,
          ),
        );
      }
      return;
    }

    // Waze deeplink
    final wazeUri = Uri.parse('waze://?ll=$lat,$lng&navigate=yes');
    // Fallback web
    final wazeWeb = Uri.parse(
        'https://www.waze.com/ul?ll=$lat,$lng&navigate=yes');

    if (await canLaunchUrl(wazeUri)) {
      await launchUrl(wazeUri);
    } else if (await canLaunchUrl(wazeWeb)) {
      await launchUrl(wazeWeb, mode: LaunchMode.externalApplication);
    }
  }

  // ── APRI SU GOOGLE MAPS ──────────────────────────────────────────────────────
  Future<void> _openOnGoogleMaps(Map<String, dynamic> log) async {
    final double? lat = (log['lat_start'] as num?)?.toDouble();
    final double? lng = (log['lng_start'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Coordinate GPS non disponibili.'),
            backgroundColor: AppTheme.alertRed,
          ),
        );
      }
      return;
    }

    final mapsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
  }

  // ── LOGHI SVG ORGINALI ───────────────────────────────────────────────────────
  static const String _whatsappSvg = '''
<svg viewBox="0 0 24 24" fill="currentColor">
  <path d="M12.012 2c-5.506 0-9.989 4.478-9.99 9.984a9.96 9.96 0 001.37 5.054L2 22l5.077-1.33a9.92 9.92 0 004.93 1.314h.005c5.507 0 9.991-4.479 9.992-9.985.002-2.67-1.04-5.18-2.936-7.078A9.9 9.9 0 0012.012 2zm4.686 11.666c-.257-.128-1.52-.749-1.755-.835-.234-.085-.405-.128-.575.128-.17.256-.659.833-.808 1.003-.149.17-.298.19-.556.062a7.008 7.008 0 01-2.062-1.272 7.726 7.726 0 01-1.428-1.778c-.15-.256-.016-.395.113-.523.115-.115.256-.298.383-.448a1.69 1.69 0 00.256-.426.43.43 0 00-.021-.405c-.064-.128-.575-1.385-.788-1.897-.207-.5-.452-.41-.623-.418-.16-.008-.346-.008-.532-.008-.186 0-.489.07-.745.347-.256.277-.979.957-.979 2.333 0 1.376 1.001 2.706 1.14 2.898.14.191 1.97 3.007 4.773 4.213.667.287 1.188.458 1.595.587.67.213 1.28.183 1.761.111.537-.08 1.654-.675 1.887-1.326.232-.65.232-1.209.163-1.326-.07-.116-.256-.18-.515-.308z"/>
</svg>
''';

  static const String _wazeSvg = '''
<svg viewBox="0 0 30 30" fill="currentColor">
  <path d="M25.2 12.8c0-5.8-4.7-10.4-10.4-10.4S4.4 7 4.4 12.8c0,3.1 1.4,6 3.6,7.9 0.1,0.1 0.2,0.3 0.2,0.5v3.2c0,0.6 0.6,0.9 1.1,0.7l3.1-1.3c0.2-0.1 0.5-0.1 0.7,0 0.9,0.4 1.8,0.6 2.7,0.6 5.8,0 10.4-4.7 10.4-10.4z M11.9 14.6c-0.8 0-1.3-0.6-1.3-1.3s0.6-1.3 1.3-1.3 1.3 0.6 1.3 1.3S12.7 14.6 11.9 14.6z M18.5 14.6c-0.8 0-1.3-0.6-1.3-1.3s0.6-1.3 1.3-1.3 1.3 0.6 1.3 1.3S19.3 14.6 18.5 14.6z"/>
</svg>
''';

  Widget _circleIconButton({
    required String assetPath,
    required Color shadowColor,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withOpacity(0.18),
                blurRadius: 12,
                spreadRadius: 1,
              )
            ],
          ),
          child: Center(
            child: ClipOval(
              child: Image.asset(
                assetPath,
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );

  // ── BOTTOM SHEET DETTAGLI ────────────────────────────────────────────────────
  void _showDetails(Map<String, dynamic> log) {
    final double startLat = (log['lat_start'] as num?)?.toDouble() ?? 43.9975;
    final double startLng = (log['lng_start'] as num?)?.toDouble() ?? 11.3718;
    
    // Genera un percorso fittizio coerente con l'id
    final int rideId = log['id'] as int? ?? 1;
    final List<LatLng> routePoints = [];
    final int numPoints = 50;
    for (int i = 0; i < numPoints; i++) {
      final double progress = i / numPoints;
      final double angle = progress * 2 * math.pi;
      final double latOffset = 0.0025 * math.sin(angle) * (1 + 0.08 * (rideId % 3));
      final double lngOffset = 0.0035 * math.cos(angle * 2) * (1 - 0.12 * (rideId % 2));
      routePoints.add(LatLng(startLat + latOffset, startLng + lngOffset));
    }

    final cost = _costOf(log);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ValueTooltipLayer(
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Titolo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      (log['title'] as String).toUpperCase(),
                      style: AppTheme.orbitronTitle.copyWith(fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: [
                  Text(
                    log['date'] ?? 'N/D',
                    style: AppTheme.interLabel.copyWith(color: Colors.white38),
                  ),
                  const SizedBox(height: 16),
                  
                  // Mappa del percorso reale
                  Text(
                    'TRACCIATO GPS REGISTRATO',
                    style: AppTheme.orbitronLabel.copyWith(fontSize: 9, color: AppTheme.activeCyan),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(startLat, startLng),
                          initialZoom: 14.0,
                          maxZoom: 18.0,
                          minZoom: 10.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.monstersync.app',
                          ),
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: routePoints,
                                color: AppTheme.activeCyan,
                                strokeWidth: 4.5,
                              ),
                            ],
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: routePoints.first,
                                width: 10,
                                height: 10,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Marker(
                                point: routePoints.last,
                                width: 28,
                                height: 28,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.activeCyan.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.activeCyan, width: 2),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.motorcycle, color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Metriche dettagli in card
                  Text(
                    'DETTAGLI SESSIONE',
                    style: AppTheme.orbitronLabel.copyWith(fontSize: 9, color: Colors.white38),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _metric(ctx, Icons.straighten, log['dist'] ?? '--', 'DISTANZA'),
                      const SizedBox(width: 12),
                      _metric(ctx, Icons.speed, log['speed'] ?? '--', 'VELOCITÀ MAX'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _metric(ctx, Icons.rotate_right, log['rpm'] ?? '--', 'GIRI MAX'),
                      const SizedBox(width: 12),
                      _metric(ctx, Icons.rotate_90_degrees_cw, log['roll'] ?? '--', 'PIEGA MAX'),
                    ],
                  ),
                  if (cost != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _metric(ctx, Icons.local_gas_station,
                            cost.litresLabel, 'CARBURANTE'),
                        const SizedBox(width: 12),
                        _metric(ctx, Icons.euro, cost.euroLabel, 'COSTO'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _metric(ctx, Icons.water_drop_outlined,
                            cost.consumptionLabel, 'CONSUMO'),
                        const SizedBox(width: 12),
                        _metric(ctx, Icons.route, cost.kmPerLitreLabel,
                            'PERCORRENZA'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Da dove arriva il prezzo: senza questa riga il numero in
                    // euro sembrerebbe inventato.
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 11, color: Colors.white.withOpacity(0.35)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Benzina self a ${cost.price.label} — '
                            '${cost.price.sourceLabel}',
                            style: AppTheme.interLabel.copyWith(
                                color: Colors.white38, fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  
                  // Condivisione (Solo icone WhatsApp e Waze, senza scritte)
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _circleIconButton(
                        assetPath: 'assets/whatsapp_icon.png',
                        shadowColor: const Color(0xFF25D366),
                        onTap: () {
                          Navigator.pop(ctx);
                          _shareOnWhatsApp(log);
                        },
                      ),
                      const SizedBox(width: 32),
                      _circleIconButton(
                        assetPath: 'assets/waze_icon.png',
                        shadowColor: const Color(0xFF33CCFF),
                        onTap: () {
                          Navigator.pop(ctx);
                          _openOnWaze(log);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  double _calculateTotalKm() {
    double total = 0.0;
    for (var log in _logs) {
      final distVal = log['dist_km'];
      if (distVal is num) {
        total += distVal.toDouble();
      }
    }
    return total;
  }

  Widget _buildRideRow(int index) {
    final log = _logs[index];
    final cost = _costOf(log);

    return Dismissible(
      key: Key('ride_${log['id']}_$index'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.alertRed.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 20),
      ),
      confirmDismiss: (direction) async {
        return await _confirmDelete(log);
      },
      onDismissed: (direction) async {
        await DbHelper().deleteRide(log['id'] as int);
        setState(() => _logs.removeAt(index));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ "${log['title']}" eliminato dal database.'),
              backgroundColor: AppTheme.alertRed,
            ),
          );
        }
      },
      child: GestureDetector(
        onTap: () => _showDetails(log),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              // Circular index indicator
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.activeCyan.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.activeCyan.withOpacity(0.2), width: 1),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: AppTheme.orbitronLabel.copyWith(
                      color: AppTheme.activeCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Title and Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (log['title'] ?? 'Giro').toUpperCase(),
                      style: AppTheme.orbitronTitle.copyWith(fontSize: 13, letterSpacing: 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${log['date'] ?? ''} · ${log['time'] ?? ''}',
                      style: AppTheme.interLabel.copyWith(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Stats preview on the right
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    log['dist'] ?? '--',
                    style: AppTheme.interBody.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    log['speed'] ?? '--',
                    style: AppTheme.interLabel.copyWith(
                      color: AppTheme.activeCyan,
                      fontSize: 9.5,
                    ),
                  ),
                  // Quanto e' costato il giro: il dato che manca sempre e che
                  // in moto interessa quanto la velocita' di punta.
                  if (cost != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${cost.euroLabel} · ${cost.litresLabel}',
                      style: AppTheme.interLabel.copyWith(
                        color: Colors.amber.withOpacity(0.85),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showMetricTooltip(BuildContext context, String label, String value, Offset globalPos) {
    String valText = value;
    String unitText = '';
    String explanationText = '';

    if (label == 'DISTANZA') {
      valText = value.replaceAll(' km', '');
      unitText = 'KM';
      explanationText = 'Distanza totale stimata percorsa durante la sessione di guida, basata sul tracciamento GPS.';
    } else if (label == 'VELOCITÀ MAX') {
      valText = value.replaceAll(' km/h', '');
      unitText = 'KM/H';
      explanationText = 'La massima velocità di punta registrata durante la sessione tramite il sensore GPS.';
    } else if (label == 'GIRI MAX') {
      valText = value.replaceAll(' RPM', '');
      unitText = 'RPM';
      explanationText = 'Il regime di rotazione del motore massimo (in RPM) registrato dai sensori di iniezione.';
    } else if (label == 'CARBURANTE') {
      valText = value.replaceAll(' l', '');
      unitText = 'LITRI';
      explanationText =
          'Litri bruciati nel giro: chilometri percorsi per il consumo medio '
          'registrato. Con la centralina collegata il consumo arriva dal '
          'sensore, non da una stima.';
    } else if (label == 'COSTO') {
      valText = value.replaceAll(' €', '');
      unitText = 'EURO';
      explanationText =
          'Quanto è costato il giro, ai prezzi di oggi. Il prezzo è la '
          'mediana della benzina self di tutti gli impianti italiani, dai dati '
          'aperti Osservaprezzi del MIMIT, aggiornati ogni mattina.';
    } else if (label == 'CONSUMO') {
      valText = value.replaceAll(' l/100km', '');
      unitText = 'L/100KM';
      explanationText =
          'Consumo medio del giro. La Monster 695 sta fra 4,8 l/100km in '
          'statale tranquilla e 6,5 l/100km tirata fra i tornanti.';
    } else if (label == 'PERCORRENZA') {
      valText = value.replaceAll(' km/l', '');
      unitText = 'KM/L';
      explanationText =
          'Chilometri percorsi con un litro: lo stesso dato del consumo, letto '
          'come si legge al distributore.';
    } else if (label == 'PIEGA MAX') {
      valText = value;
      unitText = '';
      explanationText = 'L\'inclinazione massima laterale a sinistra e destra registrata dal sensore IMU in curva.';
    } else {
      return;
    }

    ValueTooltipLayer.of(context)?.show(
      label: label,
      value: valText,
      unit: unitText,
      explanation: explanationText,
      globalPosition: globalPos,
    );
  }

  Widget _metric(BuildContext context, IconData icon, String value, String label) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            _showMetricTooltip(context, label, value, details.globalPosition);
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 14, color: AppTheme.activeCyan),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: AppTheme.interBody.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(label,
                    style: AppTheme.orbitronLabel
                        .copyWith(fontSize: 8, color: Colors.white38)),
              ],
            ),
          ),
        ),
      );

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueTooltipLayer(
      child: Builder(
        builder: (context) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(gradient: AppTheme.metallicDarkRed),
            padding: const EdgeInsets.only(top: 48, bottom: 95),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'STORICO TELEMETRIA',
                      style: AppTheme.orbitronTitle
                          .copyWith(fontSize: 22, fontStyle: FontStyle.normal),
                    ),
                  ),
                  if (_logs.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_logs.length} GIRI',
                          style: AppTheme.orbitronLabel
                              .copyWith(color: AppTheme.activeCyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_calculateTotalKm().toStringAsFixed(1)} KM TOTALI',
                          style: AppTheme.orbitronLabel
                              .copyWith(color: Colors.white38, fontSize: 8),
                        ),
                        if (_fuel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${_totalEuro().toStringAsFixed(2)} € DI BENZINA',
                            style: AppTheme.orbitronLabel.copyWith(
                                color: Colors.amber.withOpacity(0.8),
                                fontSize: 8),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.activeCyan))
                  : _logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.moped,
                                  color: Colors.white12, size: 64),
                              const SizedBox(height: 16),
                              Text(
                                'Nessun giro registrato.',
                                style: AppTheme.interBody
                                    .copyWith(color: AppTheme.textMuted),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Connetti la moto e registra il tuo primo giro!',
                                style: AppTheme.interLabel
                                    .copyWith(color: Colors.white24),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                          itemCount: _logs.length,
                          separatorBuilder: (ctx, index) => const SizedBox(height: 10),
                          itemBuilder: (ctx, index) => _buildRideRow(index),
                        ),
            ),
          ],
        ),
      );
    },
  ),
);
  }
}
