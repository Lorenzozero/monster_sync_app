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

## 🛠️ L'Hardware "Fai da Te" (Componenti Dettagliati)

Per far funzionare la telemetria sulla moto, devi assemblare il *MonsterSync-Brain* (sotto la sella o nel vano portaoggetti) utilizzando i seguenti componenti:

1.  **ESP32 NodeMCU (WROOM-32)**:
    *   *Scopo*: Riceve i dati dal GPS e dall'IMU, esegue il filtro di Kalman/Complementare per l'angolo di piega e trasmette tutto via Bluetooth Classic (SPP) o BLE all'applicazione mobile.
    *   *Specifiche*: Frequenza 240MHz dual-core, Bluetooth integrato.
2.  **Sensore IMU MPU-6050 (Giroscopio + Accelerometro a 3 assi)**:
    *   *Scopo*: Misura l'accelerazione lineare e la velocità angolare.
    *   *Specifiche*: Collegamento via bus I2C (SDA/SCL) all'ESP32. Fissalo perfettamente allineato all'asse longitudinale del telaio a traliccio.
3.  **Modulo GPS Beitian BN-180 (o BN-220/BN-880)**:
    *   *Scopo*: Rileva velocità reale, latitudine, longitudine e altitudine.
    *   *Specifiche*: Configurato per comunicare a **10Hz** (10 aggiornamenti al secondo tramite protocollo UART/NMEA a 115200 baud). Collegato ai pin RX/TX dell'ESP32.
4.  **Convertitore Step-Down DC-DC (LM2596 o Mini-360)**:
    *   *Scopo*: Abbassa la tensione instabile della batteria della moto (12V-14.4V con alternatore acceso) ai 5V stabili necessari per alimentare l'ESP32 tramite pin Vin, senza bruciare tutto.
5.  **Fusibile in linea da 1A (Consigliatissimo)**:
    *   *Scopo*: Protezione contro i cortocircuiti. Le vibrazioni del bicilindrico Ducati tendono a spellare i cavi; il fusibile evita di dare fuoco al serbatoio della benzina.

*Lo schema di collegamento e il firmware per l'ESP32 sono inclusi nella cartella `/ApexTelemetryBox`.*

---

## 📱 L'Applicazione Flutter & Come compilare l'APK e l'IPA

L'app è sviluppata in **Flutter** con un design cyberpunk metallico nero e ciano neon, ottimizzato per l'uso in moto (pulsanti giganti, tooltip esplicativi su ogni metrica).

### 🛠️ Configurazione Ambiente

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

### 🤖 Compilazione per Android (APK)

Per generare l'APK finale pronto per l'installazione su Android:
```bash
flutter build apk --release
```
*Troverai l'APK installabile sul telefono in `build/app/outputs/flutter-apk/app-release.apk`.*

### 🍎 Compilazione per iOS (File .IPA)

Per compilare ed esportare l'applicazione per iPhone (richiede un **Mac con Xcode** installato):

1.  Prepara il build folder e apri la cartella `ios` in Xcode per configurare il Signing & Capabilities (seleziona il tuo account Apple Developer):
    ```bash
    flutter build ios --release --no-codesign
    ```
2.  Per creare l'archivio e generare il pacchetto distributivo `.ipa`:
    ```bash
    flutter build ipa --export-method development
    ```
    *Nota: Se disponi di un account Apple Developer a pagamento e vuoi testare l'app tramite TestFlight o distribuirla ad-hoc, sostituisci `development` con `app-store` o `ad-hoc`.*
3.  Il file `.ipa` generato sarà disponibile all'interno della cartella:
    `build/ios/ipa/monster_sync_app.ipa`
    *Puoi installarlo sull'iPhone utilizzando Xcode, Apple Configurator o caricarlo direttamente su TestFlight.*

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
