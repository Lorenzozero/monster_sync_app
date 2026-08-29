# 🏍️ MonsterSync – Il Cruscotto Cyberpunk per Ducati Monster 695 (2007)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](https://github.com/Lorenzozero/monster_sync_app)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-v3.22.x-blue.svg)](https://flutter.dev)

> **"Perché comprare una Panigale V4 da 30.000€ per avere i grafici delle pieghe quando puoi rischiare un cortocircuito sulla batteria di un Monster del 2007 con 15€ di schede comprate su Amazon?"**

Benvenuto in **MonsterSync**, il progetto open-source nato per dare un cervello digitale a una moto che originariamente comunicava con il mondo solo tramite vibrazioni bullonarie, perdite d'olio regolamentari e fumo desmodromico.

Questa repository contiene sia l'applicazione mobile **Flutter** (collegata via Bluetooth a un ESP32) sia il codice della landing page dinamica in `/docs` con rotazioni cinematiche 3D ed effetti GSAP.

---

## 🚀 Funzionalità (Reali & Satiriche)

*   📐 **Angoli di Piega Reali (MPU-6050 + ESP32)**: Misura in tempo reale rollio, beccheggio e imbardata. Smentisci definitivamente i tuoi amici al bar: se hai piegato a 12° pensando di strisciare la saponetta, l'app registrerà spietatamente i tuoi 12° di pura prudenza stradale.
*   📡 **GPS Beitian a 10Hz**: Tracciamento del percorso a 10 campionamenti al secondo. Perché registrare la tua strada verso il meccanico di fiducia con la precisione di un comune GPS a 1Hz sarebbe stato offensivo.
*   🌡️ **Allarme Olio Bollente (L-Twin Aria & Olio)**: Il motore 695cc non ha radiatore né liquido refrigerante. Quando superi i 115°C al semaforo estivo mentre ti si cuociono le cosce, l'app passa al colore rosso allarme per ricordarti che sei su una griglia semovente.
*   🔋 **Monitoraggio Tensione Batteria**: Un voltmetro in tempo reale. Chi possiede una Ducati sa che l'alternatore è un generatore di ansia e di guasti regolatori di tensione. Tieni d'occhio i volt prima di dover spingere la moto in salita.
*   📋 **Scadenziario Burocratico Editabile**: Gestisci Bollo, Assicurazione RCA e Revisione Legale con date salvate localmente in `SharedPreferences`. Include un comodo tasto "TEST" per inviare notifiche push istantanee sul telefono e verificare che l'app sia sveglia.

---

## 🛠️ L'Hardware "Fai da Te" (Costo stimato: ~15€)

Per far funzionare la telemetria sulla moto, devi assemblare il *MonsterSync-Brain* e metterlo sotto la sella:

1.  **ESP32 NodeMCU** (il cervello con Bluetooth Classic / BLE).
2.  **Sensore MPU-6050** (accelerometro e giroscopio a 3 assi), fissato dritto e parallelo al telaio a traliccio.
3.  **Modulo GPS Beitian BN-180** (o simile, configurato a 10Hz via comandi NMEA).
4.  **Convertitore Step-Down (12V a 5V)** per alimentare l'ESP32 direttamente dalla batteria della moto senza farlo esplodere.

*Lo schema di collegamento e il firmware per l'ESP32 sono inclusi nella cartella `/ApexTelemetryBox`.*

---

## 📱 L'Applicazione Flutter

L'app è sviluppata in **Flutter** con un design cyberpunk metallico nero e ciano neon, ottimizzato per l'uso in moto (pulsanti giganti, tooltip esplicativi su ogni metrica).

### Configurazione & Build

1.  Assicurati di avere Flutter installato (`flutter --version` >= 3.22).
2.  Clona la repository ed entra nella cartella:
    ```bash
    git clone https://github.com/Lorenzozero/monster_sync_app.git
    cd monster_sync_app
    ```
3.  Scarica le dipendenze:
    ```bash
    flutter pub get
    ```
4.  Avvia l'app in modalità debug:
    ```bash
    flutter run
    ```
5.  Per compilare l'APK finale pronto per l'installazione su Android:
    ```bash
    flutter build apk --release
    ```
    *(Troverai l'APK in `build/app/outputs/flutter-apk/app-release.apk`)*

---

## 🌐 La Landing Page (GSAP & 3D Model)

Abbiamo creato una landing page spettacolare dentro la cartella `/docs` che utilizza:
*   **Google `<model-viewer>`** per caricare il modello 3D interattivo (`.glb`) del Ducati Monster.
*   **GSAP + ScrollTrigger** per catturare lo scroll della pagina e ruotare/ingrandire cinematicamente la telecamera del modello 3D in corrispondenza delle varie sezioni esplicative (inquadratura del manubrio per l'IMU, del blocco motore e dello scarico).
*   **Tailwind CSS** per un layout responsive e futuristico.

### Come visualizzarla localmente:
Puoi lanciare un server locale velocissimo con Python:
```bash
cd docs
python -m http.server 8000
```
Poi apri `http://localhost:8000` nel browser per goderti l'effetto cinema.

---

## 📄 Licenza

Questo progetto è rilasciato sotto la licenza **MIT**. Sentiti libero di fare fork, aggiungere sensori (tipo un sensore di livello olio per contare le gocce che cadono a terra) o modificare il codice.

*Disclaimer: L'uso di questa applicazione non previene lo svitamento spontaneo delle viti dovuto alle vibrazioni del bicilindrico a L né le tipiche perdite d'olio. Tenere sempre a portata di mano una chiave da 10 e una brugola da 5.*

Fatto con 🛠️ e 🔴 desmodromico da [Lorenzo Garoffolo](https://github.com/Lorenzozero).
