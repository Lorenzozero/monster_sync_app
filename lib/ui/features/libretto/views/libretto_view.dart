import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme.dart';
import '../../../../data/services/notification_service.dart';
import '../../../../data/database/db_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modello voce manutenzione con doppio trigger (tempo + km)
// ─────────────────────────────────────────────────────────────────────────────
class _ManutItem {
  final String key;
  final String label;
  final String icon;
  final int? intervalDays;     // null = solo km
  final int? intervalKm;      // null = solo giorni
  final String note;
  final int notifId;

  const _ManutItem({
    required this.key,
    required this.label,
    required this.icon,
    this.intervalDays,
    this.intervalKm,
    required this.note,
    required this.notifId,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Controlli CORRETTI per Ducati Monster 695 (motore L-twin 695cc, ARIA+OLIO,
// NO radiatore/liquido refrigerante, NO filtro aria tradizionale a viscosa —
// ha filtro a carta nell'airbox sotto il serbatoio)
// ─────────────────────────────────────────────────────────────────────────────
const List<_ManutItem> _maintenanceItems = [
  _ManutItem(
    key: 'olio_motore',
    label: 'Olio Motore',
    icon: '🛢️',
    intervalDays: 365,
    intervalKm: 7500,
    note: '10W-40 o 15W-50 – certificazione JASO MA2 obbligatoria. '
        'Quantità: 2,7 L con filtro. Cambia il prima tra 12 mesi e 7.500 km.',
    notifId: 301,
  ),
  _ManutItem(
    key: 'filtro_olio',
    label: 'Filtro Olio',
    icon: '🔩',
    intervalDays: 730,
    intervalKm: 15000,
    note: 'Ducati p/n 44440056A. Sostituisci ogni 2 cambi olio (15.000 km). '
        'Coppia di serraggio: 12 Nm.',
    notifId: 302,
  ),
  _ManutItem(
    key: 'filtro_aria',
    label: 'Filtro Aria (Carta)',
    icon: '💨',
    intervalDays: 730,
    intervalKm: 15000,
    note: 'La Monster 695 ha un filtro a carta nell\'airbox sotto il serbatoio. '
        'NON è a bagno d\'olio. Pulisci con aria compressa ogni 7.500 km, '
        'sostituisci ogni 15.000 km o 2 anni. p/n Ducati 42620141A.',
    notifId: 303,
  ),
  _ManutItem(
    key: 'candele',
    label: 'Candele Accensione',
    icon: '⚡',
    intervalDays: 548,
    intervalKm: 15000,
    note: 'NGK DCPR8E (originale) o DCPR9E per guida sportiva intensa. '
        'Verifica gap a 0.7 mm ogni 7.500 km – sostituzione a 15.000 km.',
    notifId: 304,
  ),
  _ManutItem(
    key: 'catena',
    label: 'Lubrifica Catena',
    icon: '⛓️',
    intervalDays: 30,
    intervalKm: 1000,
    note: 'Catena O-ring 525. Lubrifica ogni 1.000 km o dopo ogni pioggia. '
        'Tensione: 25-35 mm di gioco a metà tra pignone e corona. '
        'Ispeziona allungamento ogni 3.000 km.',
    notifId: 305,
  ),
  _ManutItem(
    key: 'catena_sostituzione',
    label: 'Sostituzione Catena+Pignoni',
    icon: '⛓️',
    intervalDays: null,
    intervalKm: 25000,
    note: 'Sostituisci sempre catena + pignone anteriore (15T) + corona (42T) '
        'insieme. Non mescolare componenti usati con nuovi.',
    notifId: 306,
  ),
  _ManutItem(
    key: 'freni_ant',
    label: 'Pastiglie Freno Ant.',
    icon: '🔴',
    intervalDays: null,
    intervalKm: 12000,
    note: 'Brembo serie originale o Ferodo DS2500 per uso sportivo. '
        'Controlla spessore ogni 6.000 km — minimo 2 mm residui. '
        'Pinza Brembo radiale 4 pistoncini.',
    notifId: 307,
  ),
  _ManutItem(
    key: 'freni_post',
    label: 'Pastiglie Freno Post.',
    icon: '🔴',
    intervalDays: null,
    intervalKm: 20000,
    note: 'Piston singolo. Le posteriori durano quasi il doppio delle anteriori. '
        'Controlla ogni 10.000 km – minimo 2 mm.',
    notifId: 308,
  ),
  _ManutItem(
    key: 'liquido_freni',
    label: 'Liquido Freni DOT 4',
    icon: '🧪',
    intervalDays: 730,
    intervalKm: null,
    note: 'Il DOT 4 è igroscopico: assorbe umidità e abbassa il punto di ebollizione. '
        'Sostituisci ogni 2 anni indipendentemente dai km. '
        'Usa solo DOT 4 – mai DOT 5 silicone.',
    notifId: 309,
  ),
  _ManutItem(
    key: 'pneumatico_ant',
    label: 'Pneumatico Anteriore',
    icon: '⚪',
    intervalDays: 365,
    intervalKm: 15000,
    note: '120/60 ZR17 M/C (55W). Pressione: 2.20 bar a freddo. '
        'Battistrada min: 1.6 mm (legge) – sostituisci prima a 2.0 mm. '
        'Controlla pressione ogni 2 settimane.',
    notifId: 310,
  ),
  _ManutItem(
    key: 'pneumatico_post',
    label: 'Pneumatico Posteriore',
    icon: '⚫',
    intervalDays: 365,
    intervalKm: 10000,
    note: '160/60 ZR17 M/C (69W). Pressione: 2.50 bar a freddo (2.20 con passeggero). '
        'Il posteriore si consuma più velocemente. Min: 1.6 mm.',
    notifId: 311,
  ),
  _ManutItem(
    key: 'valvole',
    label: 'Gioco Valvole',
    icon: '🔧',
    intervalDays: 730,
    intervalKm: 15000,
    note: 'Gioco aspirazione: 0.10–0.15 mm  •  Scarico: 0.15–0.20 mm. '
        'Operazione da officina specializzata. La Monster 695 ha 2 valvole/cilindro '
        '(no Desmo — quella è la famiglia L-twin con distribuzione desmodromica).',
    notifId: 312,
  ),
  _ManutItem(
    key: 'batteria',
    label: 'Batteria',
    icon: '🔋',
    intervalDays: 1460,
    intervalKm: null,
    note: 'YTX12-BS (12V 10Ah) o equivalente AGM/GEL. '
        'Controlla tensione: >12.6V a riposo. Se non usi la moto d\'inverno '
        'metti in carica con mantenitore ogni 2 mesi.',
    notifId: 313,
  ),
  _ManutItem(
    key: 'revisione_legale',
    label: 'Revisione Legale (CdS)',
    icon: '📋',
    intervalDays: 730,
    intervalKm: null,
    note: 'Art. 80 CdS – veicoli >10 anni: revisione ogni 2 anni. '
        'Ultimo esito: 26.09.2024 REGOLARE. '
        'La prossima è entro il 26.09.2026.',
    notifId: 314,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
class LibrettoView extends StatefulWidget {
  const LibrettoView({super.key});
  @override
  State<LibrettoView> createState() => _LibrettoViewState();
}

class _LibrettoViewState extends State<LibrettoView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SharedPreferences? _prefs;
  bool _notificationsEnabled = true;

  // km totali dallo storico giri
  double _totalKm = 0.0;
  // km al momento dell'ultimo intervento (salvato in prefs)
  // chiave: 'maint_km_<key>'

  // ── Scadenze legali editabili ──────────────────────────────────────────────
  String _revisioneUltimo = '26.09.2024';
  String _revisioneEsito = 'REGOLARE';
  String _revisioneProssima = '26.09.2026';
  String _bolloScadenza = '31.01.2027';
  String _rcaScadenza = '10.08.2027';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _totalKm = await DbHelper().getTotalKm();
    
    // Verifica lo stato reale dei permessi nel sistema operativo usando il plugin direttamente
    final enabled = await NotificationService.instance.areNotificationsEnabled();
    _notificationsEnabled = enabled;

    // Carica scadenze salvate
    _revisioneUltimo = _prefs?.getString('scad_revisione_ultimo') ?? '26.09.2024';
    _revisioneEsito = _prefs?.getString('scad_revisione_esito') ?? 'REGOLARE';
    _revisioneProssima = _prefs?.getString('scad_revisione_prossima') ?? '26.09.2026';
    _bolloScadenza = _prefs?.getString('scad_bollo') ?? '31.01.2027';
    _rcaScadenza = _prefs?.getString('scad_rca') ?? '10.08.2027';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  DateTime? _lastDate(String key) {
    final s = _prefs?.getString('maint_date_$key');
    return s == null ? null : DateTime.tryParse(s);
  }

  double _lastKm(String key) =>
      _prefs?.getDouble('maint_km_$key') ?? -1.0;

  int _daysLeft(_ManutItem item) {
    if (item.intervalDays == null) return 9999;
    final last = _lastDate(item.key);
    if (last == null) return -999;
    final next = last.add(Duration(days: item.intervalDays!));
    return next.difference(DateTime.now()).inDays;
  }

  double _kmLeft(_ManutItem item) {
    if (item.intervalKm == null) return 9999;
    final lastKm = _lastKm(item.key);
    if (lastKm < 0) return -1; // mai registrato
    final kmSince = _totalKm - lastKm;
    return item.intervalKm! - kmSince;
  }

  // Urgenza combinata: scatta sul trigger PIÙ critico (giorni o km)
  ({Color color, String label}) _status(_ManutItem item) {
    final dl = _daysLeft(item);
    final kl = _kmLeft(item);

    // Mai registrato
    if (dl == -999 && kl == -1) {
      return (color: Colors.white38, label: 'Mai registrato');
    }

    // Scaduto per giorni
    if (dl < 0 && dl != -999) {
      return (color: AppTheme.alertRed, label: 'SCADUTO ${-dl}gg fa');
    }
    // Scaduto per km
    if (kl < 0 && kl != -1) {
      return (
        color: AppTheme.alertRed,
        label: 'SCADUTO ${(-kl).toStringAsFixed(0)} km fa'
      );
    }
    // Urgente (< 30gg o < 200km)
    if ((dl < 30 && dl != 9999) || (kl < 200 && kl != 9999)) {
      final msg = (kl < dl / 365 * (item.intervalKm ?? 9999))
          ? '🔴 Fra ${kl.toStringAsFixed(0)} km'
          : '🔴 Fra ${dl}gg';
      return (color: const Color(0xFFFF4400), label: msg);
    }
    // Attenzione (< 90gg o < 1000km)
    if ((dl < 90 && dl != 9999) || (kl < 1000 && kl != 9999)) {
      final msg = (dl != 9999 && kl != 9999)
          ? '🟡 ${dl}gg / ${kl.toStringAsFixed(0)}km'
          : dl != 9999
              ? '🟡 Fra ${dl}gg'
              : '🟡 Fra ${kl.toStringAsFixed(0)} km';
      return (color: const Color(0xFFFFCC00), label: msg);
    }
    // Ok
    final msg = (dl != 9999 && kl != 9999)
        ? '✅ ${dl}gg / ${kl.toStringAsFixed(0)}km'
        : dl != 9999
            ? '✅ Fra ${dl}gg'
            : '✅ Fra ${kl.toStringAsFixed(0)} km';
    return (color: AppTheme.activeCyan, label: msg);
  }

  Future<void> _markDoneToday(_ManutItem item) async {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    await _prefs?.setString('maint_date_${item.key}', now.toIso8601String());
    await _prefs?.setDouble('maint_km_${item.key}', _totalKm);
    // Ricarica km aggiornati
    _totalKm = await DbHelper().getTotalKm();
    if (mounted) setState(() {});

    final s = _status(item);
    await NotificationService.instance.sendManutenzioneNotification(
      id: item.notifId,
      title: '${item.label.toUpperCase()} REGISTRATO $dateStr',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${item.label} registrato! ${s.label}'),
          backgroundColor: AppTheme.activeCyan,
        ),
      );
    }
  }

  Future<void> _checkAndSendNotification(Future<void> Function() send) async {
    // 1. Richiedi o verifica il permesso a runtime
    var status = await Permission.notification.status;
    if (status.isDenied) {
      status = await Permission.notification.request();
    }

    // 2. Verifica se le notifiche sono abilitate a livello globale nel sistema operativo
    final systemEnabled = await NotificationService.instance.areNotificationsEnabled();

    if (!status.isGranted || !systemEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ Notifiche disattivate nel sistema. Attivale nelle impostazioni!'),
            backgroundColor: AppTheme.alertRed,
            action: SnackBarAction(
              label: 'IMPOSTAZIONI',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      setState(() => _notificationsEnabled = false);
      return;
    }
    setState(() => _notificationsEnabled = true);
    try {
      await send();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Errore notifica: $e'),
            backgroundColor: AppTheme.alertRed,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _testNotification(_ManutItem item) async {
    await _checkAndSendNotification(() async {
      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      await NotificationService.instance.sendManutenzioneNotification(
        id: item.notifId + 100,
        title: '${item.label.toUpperCase()} $dateStr',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔧 Notifica manutenzione inviata!'),
            backgroundColor: AppTheme.activeCyan,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ Notifiche disattivate nel sistema. Attivale nelle impostazioni!'),
              backgroundColor: AppTheme.alertRed,
              action: SnackBarAction(
                label: 'IMPOSTAZIONI',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        setState(() => _notificationsEnabled = false);
        return;
      }
    }
    setState(() => _notificationsEnabled = value);
  }

  Future<void> _testLegaleNotification(String type) async {
    await _checkAndSendNotification(() async {
      final isBollo = type == 'BOLLO';
      final scadenzaDot = isBollo ? _bolloScadenza : _rcaScadenza;
      final scadenza = scadenzaDot.replaceAll('.', '/');
      await NotificationService.instance.sendScadenzaNotification(
        id: isBollo ? 201 : 202,
        title: isBollo ? 'SCADENZA BOLLO MOTO $scadenza' : 'SCADENZA ASSICURAZIONE RCA $scadenza',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📲 Notifica inviata — controlla la tendina!'),
            backgroundColor: AppTheme.activeCyan,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  // ── Date Picker Helper ────────────────────────────────────────────────────
  Future<String?> _pickDate({String? initial}) async {
    DateTime initialDate = DateTime.now();
    if (initial != null) {
      final parts = initial.split('.');
      if (parts.length == 3) {
        initialDate = DateTime(
          int.tryParse(parts[2]) ?? DateTime.now().year,
          int.tryParse(parts[1]) ?? 1,
          int.tryParse(parts[0]) ?? 1,
        );
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2040),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.activeCyan,
              surface: Color(0xFF1A0000),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return null;
    return '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
  }

  Future<void> _editRevisione() async {
    final ultimo = await _pickDate(initial: _revisioneUltimo);
    if (ultimo == null || !mounted) return;
    final prossima = await _pickDate(initial: _revisioneProssima);
    if (prossima == null || !mounted) return;
    setState(() {
      _revisioneUltimo = ultimo;
      _revisioneProssima = prossima;
    });
    await _prefs?.setString('scad_revisione_ultimo', ultimo);
    await _prefs?.setString('scad_revisione_prossima', prossima);
  }

  Future<void> _editBollo() async {
    final date = await _pickDate(initial: _bolloScadenza);
    if (date == null || !mounted) return;
    setState(() => _bolloScadenza = date);
    await _prefs?.setString('scad_bollo', date);
  }

  Future<void> _editRca() async {
    final date = await _pickDate(initial: _rcaScadenza);
    if (date == null || !mounted) return;
    setState(() => _rcaScadenza = date);
    await _prefs?.setString('scad_rca', date);
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(gradient: AppTheme.metallicDarkRed),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 48),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text('LIBRETTO & SCADENZE',
                      style: AppTheme.orbitronTitle
                          .copyWith(fontSize: 20, letterSpacing: 1.0)),
                ),
                Switch.adaptive(
                  value: _notificationsEnabled,
                  onChanged: _toggleNotifications,
                  activeColor: AppTheme.activeCyan,
                ),
                const Icon(Icons.notifications_active,
                    color: AppTheme.activeCyan, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tab bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12), // Reduced from 20 to prevent overflow
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4), // Prevents label truncation
                indicator: BoxDecoration(
                  color: AppTheme.activeCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppTheme.activeCyan.withValues(alpha: 0.5)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: AppTheme.orbitronLabel
                    .copyWith(fontSize: 9, color: AppTheme.activeCyan),
                unselectedLabelStyle:
                    AppTheme.orbitronLabel.copyWith(fontSize: 9),
                unselectedLabelColor: Colors.white38,
                tabs: const [
                  Tab(text: 'LIBRETTO'),
                  Tab(text: 'SCADENZE'),
                  Tab(text: 'TAGLIANDO'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLibrettoTab(),
                _buildScadenzeTab(),
                _buildTagliandoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 1: LIBRETTO ──────────────────────────────────────────────────────────
  Widget _buildLibrettoTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 95),
        children: [
          _sectionHeader('IDENTIFICAZIONE VEICOLO'),
          _card([
            _row('Targa:', 'TARGA_RIMOSSA', cyan: true),
            _row('Telaio:', 'TELAIO_RIMOSSO'),
            _row('Modello:', 'DUCATI MONSTER 695'),
            _row('Versione:', 'M4 VAR.20 VERS.AA'),
            _row('Intestatario:', 'INTESTATARIO_RIMOSSO'),
            _row('Immatric.:', '06.11.2007'),
          ]),
          const SizedBox(height: 14),
          _sectionHeader('SPECIFICHE TECNICHE'),
          _card([
            _row('Motore:', 'L-twin 695cc, ARIA+OLIO (NO radiatore)', cyan: true),
            _row('Potenza:', '22.00 kW  (A2)'),
            _row('Trasmissione:', 'Catena O-ring 525 · 15T / 42T'),
            _row('Emissioni:', 'Euro 3 – Dir. 2003/77/CE'),
            _row('Pneu. Ant.:', '120/60 ZR17 M/C (55W) – 2.20 bar'),
            _row('Pneu. Post.:', '160/60 ZR17 M/C (69W) – 2.50 bar'),
          ]),

        ],
      );

  // ── TAB 2: SCADENZE LEGALI ───────────────────────────────────────────────────
  Widget _buildScadenzeTab() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 95),
        children: [
          _sectionHeaderWithEdit('REVISIONE LEGALE', _editRevisione),
          _card([
            _row('Ultimo esito:', '$_revisioneUltimo – $_revisioneEsito', cyan: true),
            _row('Prossima:', '$_revisioneProssima (ogni 2 anni per veicoli >10 anni)'),
          ]),
          const SizedBox(height: 14),
          _sectionHeaderWithEdit('BOLLO MOTO', _editBollo),
          _card([_expiryRow(label: 'Bollo Regione Piemonte', date: _bolloScadenza, type: 'BOLLO')]),
          const SizedBox(height: 14),
          _sectionHeaderWithEdit('ASSICURAZIONE RCA', _editRca),
          _card([_expiryRow(label: 'Polizza RCA Ducati', date: _rcaScadenza, type: 'ASSICURAZIONE')]),
        ],
      );

  // ── TAB 3: TAGLIANDO ─────────────────────────────────────────────────────────
  Widget _buildTagliandoTab() {
    if (_prefs == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.activeCyan));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 95),
      children: [
        // Banner km totali dallo storico
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.activeCyan.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
            border: Border.all(color: AppTheme.activeCyan.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.route, color: AppTheme.activeCyan, size: 20),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('KM REGISTRATI NELL\'APP',
                    style: AppTheme.orbitronLabel
                        .copyWith(fontSize: 9, color: AppTheme.activeCyan)),
                const SizedBox(height: 2),
                Text(
                  '${_totalKm.toStringAsFixed(1)} km',
                  style: AppTheme.orbitronTitle.copyWith(fontSize: 22),
                ),
              ]),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  _totalKm = await DbHelper().getTotalKm();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.activeCyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.activeCyan.withValues(alpha: 0.3)),
                  ),
                  child: Text('AGGIORNA',
                      style: AppTheme.orbitronLabel
                          .copyWith(fontSize: 8, color: AppTheme.activeCyan)),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'I km vengono calcolati dallo storico giri registrati. '
            'Ogni voce mostra i giorni e/o i km rimanenti all\'intervento. '
            'Premi ✅ FATTO OGGI dopo ogni intervento — l\'app salva data e km attuali.',
            style: AppTheme.interLabel.copyWith(color: Colors.white38, fontSize: 9),
          ),
        ),
        _sectionHeader('CONTROLLI PERIODICI – DUCATI MONSTER 695'),
        ..._maintenanceItems.map((item) => _manutCard(item)),
      ],
    );
  }

  // ── Card singola manutenzione ────────────────────────────────────────────────
  Widget _manutCard(_ManutItem item) {
    final s = _status(item);
    final lastDate = _lastDate(item.key);
    final lastKmVal = _lastKm(item.key);
    final kmSince = lastKmVal >= 0 ? _totalKm - lastKmVal : null;
    final kl = _kmLeft(item);
    final dl = _daysLeft(item);

    final isExpired = (dl < 0 && dl != -999 && dl != 9999) ||
        (kl < 0 && kl != -1 && kl != 9999);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        border: Border.all(
          color: isExpired
              ? AppTheme.alertRed.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.05),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Riga titolo + badge
        Row(children: [
          Text(item.icon, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.label,
                style: AppTheme.interBody
                    .copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: s.color.withValues(alpha: 0.4)),
            ),
            child: Text(s.label,
                style: AppTheme.orbitronLabel
                    .copyWith(fontSize: 7.5, color: s.color)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(item.note,
            style: AppTheme.interLabel
                .copyWith(color: Colors.white38, fontSize: 9.5)),
        // Dettagli km/giorni
        if (lastDate != null || lastKmVal >= 0) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (lastDate != null)
              _chip(
                  '📅 Ultimo: ${lastDate.day.toString().padLeft(2, '0')}/${lastDate.month.toString().padLeft(2, '0')}/${lastDate.year}'),
            if (lastKmVal >= 0)
              _chip(
                  '📍 Al km: ${lastKmVal.toStringAsFixed(0)}'),
            if (kmSince != null)
              _chip(
                  '🛣️ Percorsi da allora: ${kmSince.toStringAsFixed(0)} km'),
            if (item.intervalKm != null && kl != -1 && kl != 9999)
              _chip(kl > 0
                  ? '⏩ Rimanenti: ${kl.toStringAsFixed(0)} km'
                  : '🚨 Sforati: ${(-kl).toStringAsFixed(0)} km'),
            if (item.intervalDays != null && dl != -999 && dl != 9999)
              _chip(dl > 0
                  ? '📆 Rimanenti: ${dl}gg'
                  : '🚨 Scaduto: ${-dl}gg fa'),
          ]),
        ],
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white38,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.notifications_none, size: 13),
            label: Text('TEST',
                style: AppTheme.orbitronLabel
                    .copyWith(fontSize: 8, color: Colors.white38)),
            onPressed: () => _testNotification(item),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.activeCyan.withValues(alpha: 0.12),
              foregroundColor: AppTheme.activeCyan,
              side: const BorderSide(color: AppTheme.activeCyan, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.check, size: 13),
            label: Text('FATTO OGGI',
                style: AppTheme.orbitronLabel
                    .copyWith(fontSize: 8, color: AppTheme.activeCyan)),
            onPressed: () => _markDoneToday(item),
          ),
        ]),
      ]),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(text,
            style: AppTheme.interLabel
                .copyWith(fontSize: 9, color: Colors.white54)),
      );

  // ── Helper widgets ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(t,
            style: AppTheme.orbitronLabel
                .copyWith(fontSize: 10, color: AppTheme.activeCyan)),
      );

  Widget _sectionHeaderWithEdit(String t, VoidCallback onEdit) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Row(
          children: [
            Text(t,
                style: AppTheme.orbitronLabel
                    .copyWith(fontSize: 10, color: AppTheme.activeCyan)),
            const Spacer(),
            GestureDetector(
              onTap: onEdit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 12, color: AppTheme.activeCyan.withValues(alpha: 0.7)),
                  const SizedBox(width: 3),
                  Text('MODIFICA',
                      style: AppTheme.orbitronLabel.copyWith(
                          fontSize: 7, color: AppTheme.activeCyan.withValues(alpha: 0.7))),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panelBg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _row(String label, String value, {bool cyan = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 95,
            child: Text(label,
                style: AppTheme.interBody
                    .copyWith(color: AppTheme.textMuted, fontSize: 10.5)),
          ),
          Expanded(
            child: Text(value,
                style: AppTheme.interBody.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                  color: cyan ? AppTheme.activeCyan : Colors.white,
                )),
          ),
        ]),
      );

  Widget _expiryRow({
    required String label,
    required String date,
    required String type,
  }) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: AppTheme.interBody
                  .copyWith(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text('Scade il $date',
              style: AppTheme.interBody
                  .copyWith(fontWeight: FontWeight.bold, fontSize: 12.5)),
        ]),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.activeCyan.withValues(alpha: 0.08),
            foregroundColor: AppTheme.activeCyan,
            side: const BorderSide(color: AppTheme.activeCyan, width: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(56, 28),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _testLegaleNotification(type),
          child: Text('TEST',
              style: AppTheme.orbitronLabel
                  .copyWith(fontSize: 9, color: AppTheme.activeCyan)),
        ),
      ]);
}
