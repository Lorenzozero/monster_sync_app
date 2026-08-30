# 🏍️ MonsterSync – Il Cruscotto Cyberpunk per Ducati Monster 695 (2007)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](https://github.com/Lorenzozero/monster_sync_app)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-v3.22.x-blue.svg)](https://flutter.dev)
[![Landing Page](https://img.shields.io/badge/Landing--Page-Live%20on%20Vercel-red?style=flat&logo=vercel)](https://monster-sync-app.vercel.app)

> **"Perché comprare una Panigale V4 da 30.000€ per avere i grafici delle pieghe quando puoi rischiare un cortocircuito sulla batteria di un Monster del 2007 con 22€ di schede comprate su AliExpress?"**

Benvenuto in **MonsterSync**, il progetto open-source nato per dare un cervello digitale a una moto che originariamente comunicava con il mondo solo tramite vibrazioni bullonarie, perdite d'olio regolamentari e fumo desmodromico.

Questa repository contiene l'applicazione mobile **Flutter** (collegata via Bluetooth a un ESP32) e il codice della landing page dinamica 3D (situata in `/docs`) hostabile su **Vercel** o **GitHub Pages**.

🔗 **Landing Page Live**: [monster-sync-app.vercel.app](https://monster-sync-app.vercel.app) (Hostata su Vercel)

---

## 🚀 Funzionalità (Reali & Software-Powered)

*   📐 **Angoli di Piega Reali (MPU-6050 + ESP32)**: Misura in tempo reale rollio, beccheggio e imbardata. Smentisci definitivamente i tuoi amici al bar: se hai piegato a 12° pensando di strisciare la saponetta, l'app registrerà spietatamente i tuoi 12° di pura prudenza stradale.
*   🚦 **Marce Live (1ª - 6ª)**: Rilevamento in tempo reale della marcia inserita. Dato che il Monster 695 non ha un sensore fisico nel cambio, la marcia viene calcolata istantaneamente via software confrontando i giri del motore (RPM) e la velocità reale (GPS).
*   ⛽ **Controllo Carburante & Stima Autonomia**: Il serbatoio del Monster ha solo un sensore per la spia di riserva a 12V. Il circuito legge questo segnale isolandolo con un fotoaccoppiatore. Il software dell'app fa il resto, stimando un indicatore a 8 tacche e calcolando i chilometri residui di autonomia in base allo storico dei consumi e della distanza percorsa.
*   📍 **Smart Vehicle Finder (Dove ho parcheggiato?)**: Se vai a un raduno affollato o parcheggi al Passo del Muraglione in mezzo a centinaia di moto e non ricordi dove sia la tua, l'app memorizza in automatico l'ultima coordinata GPS ricevuta dall'ESP32 prima che il quadro venisse spento, guidandoti a piedi fino alla moto.
*   🗺️ **Mappe Termiche Pieghe Offline**: Tracciamento della traiettoria GPS a 10Hz visualizzato su una mappa termica reale tramite OpenStreetMap (funzionante offline). Colora in ciano le curve lente o prudenti e in rosso neon quelle ad alta piega (>30°).
*   🌡️ **Allarme Olio Bollente (L-Twin Aria & Olio)**: Il motore 695cc non ha radiatore né liquido refrigerante. Quando superi i 115°C al semaforo estivo mentre ti si cuociono le cosce, l'app passa al colore rosso allarme per ricordarti che sei su una griglia semovente.
*   🔋 **Monitoraggio Tensione Batteria**: Un voltmetro in tempo reale. Chi possiede una Ducati sa che l'alternatore è un generatore di ansia e di guasti regolatori di tensione. Tieni d'occhio i volt prima di dover spingere la moto in salita.
*   📋 **Scadenziario Burocratico & Manutenzioni**: Gestisci scadenze fiscali (Bollo, RCA, Revisione) e meccaniche (cinghie di distribuzione del Desmodue, tagliando, gioco valvole, olio) tramite database locale. Include notifiche native del sistema operativo Android/iOS per non dimenticare nulla.

---

## 🛠️ L'Hardware "Fai da Te" (BOM AliExpress ~22.30€)

Per far funzionare la telemetria sulla moto, devi assemblare la centralina custom *MonsterSync-Brain* (da inserire sotto la sella o nel codone) utilizzando i seguenti componenti economici:

1.  **ESP32 NodeMCU (WROOM-32D)** (~€4.50):
    *   *Scopo*: Riceve i dati dal GPS e dall'IMU, esegue il filtro di Kalman/Complementare per l'angolo di piega e trasmette tutto via Bluetooth Classic/BLE all'applicazione mobile.
2.  **Sensore IMU MPU-6050 (GY-521)** (~€1.20):
    *   *Scopo*: Misura l'accelerazione lineare e la velocità angolare. Va fissato solidamente e in bolla sul telaio della moto.
3.  **Modulo GPS Beitian BN-180** (~€9.50):
    *   *Scopo*: Rileva velocità reale, traiettoria ed altitudine a **10Hz** (10 aggiornamenti al secondo tramite protocollo UART/NMEA a 115200 baud).
4.  **Fotoaccoppiatore PC817 (Isolamento I/O 12V)** (~€1.80):
    *   *Scopo*: Isola elettricamente i segnali a 12V della moto (impulsi bobina iniettore per calcolare gli RPM, e cavo sensore riserva serbatoio) riducendoli a 3.3V sicuri per l'ESP32.
5.  **Convertitore Step-Down DC-DC LM2596** (~€1.50):
    *   *Scopo*: Abbassa la tensione instabile dell'impianto elettrico della moto (12V-14.4V) ai 5V stabili necessari per alimentare l'ESP32 tramite pin Vin.
6.  **Scatola Waterproof IP65 + Fusibile 1A** (~€3.80):
    *   *Scopo*: Alloggiamento impermeabile e protezione contro i cortocircuiti dovuti alle forti vibrazioni del bicilindrico.

---

## ⚡ Il Firmware: Compilazione e Flash dell'ESP32

Il codice della centralina sta in [`firmware/`](firmware/). È un progetto **Arduino + FreeRTOS**
diviso in quattro moduli: `imu_kinematic` (angolo di piega), `gps_parser` (NMEA), `ble_server`
(server GATT) e `sensors_io` (ingressi optoisolati).

> ⚠️ **Stato reale**: BLE, GPS e ingressi digitali funzionano. Il **driver dell'IMU non è ancora
> scritto** (`IMU_Init()` è un TODO): la fusione cinematica c'è, ma non legge ancora il sensore.
> Il firmware compila e trasmette, non è ancora una telemetria completa.

### 🛠️ Ambiente

1.  **Arduino IDE 2.x** (o PlatformIO).
2.  Aggiungi il supporto ESP32: *Preferenze → URL Gestore schede aggiuntive* →
    `https://espressif.github.io/arduino-esp32/package_esp32_index.json`, poi installa
    **esp32 by Espressif Systems** dal Gestore schede.
3.  Installa dal Gestore librerie: **TinyGPSPlus** (di Mikal Hart).
    `WiFi`, `HTTPClient` e lo stack `BLEDevice` sono già inclusi nel core ESP32.

### 📌 Scheda e pin

I commenti nel codice sono tarati su un **ESP32-S3-WROOM-1** (GPIO 22–26 sono riservati alla
Flash Octal-SPI e alla PSRAM, per questo i sensori stanno su GPIO 4 e 5).

> **Nota**: la BOM qui sopra elenca un ESP32 classico (WROOM-32D). Su quel chip **GPIO 5 è un pin
> di strapping** e deve stare alto all'avvio: se usi il WROOM-32D, sposta l'ingresso riserva su
> GPIO 25/26/27/32/33 in `firmware/sensors_io.cpp`.

| Segnale | Pin | Note |
| --- | --- | --- |
| Iniettore (RPM + consumo) | `GPIO 4` | interrupt su fronte di discesa, via PC817 |
| Riserva carburante | `GPIO 5` | interrupt su cambio di stato, via PC817 |
| GPS RX / TX | `GPIO 16` / `GPIO 17` | `Serial1`, 115200 baud |
| IMU | I²C/SPI | da collegare quando il driver sarà scritto |

> 🔌 **Prima di collegarlo alla moto**, leggi le note di sicurezza elettrica più sotto: il PC817
> sull'iniettore vuole un **diodo 1N4148 in antiparallelo** al LED, e l'alimentazione va presa
> **sotto chiave**, fusibilata.

### 🚀 Flash

1.  Apri `firmware/MonsterSync.ino` nell'IDE (gli altri file si aprono da soli come tab).
2.  Seleziona la scheda (*ESP32S3 Dev Module* oppure *ESP32 Dev Module*) e la porta COM.
3.  Se usi l'S3 con PSRAM: *Tools → PSRAM → OPI PSRAM*.
4.  **Upload**. Apri il monitor seriale a **115200** per vedere l'inizializzazione dei task.

### 📡 Wi-Fi opzionale (upload verso il backend)

In cima a `MonsterSync.ino`:

```cpp
const char* ssid      = "IlTuoHotspot";     // lascia così per tenere il Wi-Fi spento
const char* password  = "LaTuaPassword";
const char* serverUrl = "http://192.168.1.100:8000/telemetry";
```

Finché l'SSID resta il segnaposto, il firmware **non tenta la connessione**. È voluto: una
scansione Wi-Fi che fallisce in loop occupa al 100% l'antenna condivisa a 2.4 GHz e **l'advertising
BLE non va mai in onda** — il dispositivo sparisce dall'app pur essendo acceso.

### 🔌 Sicurezza elettrica prima di montarlo sulla moto

Sette regole. Le prime due proteggono il motore, le altre l'elettronica.

1.  **Il pressostato olio originale non si rimuove mai.** Se in futuro aggiungi un trasduttore di
    pressione analogico, va su un **raccordo a T**, in parallelo: la spia rossa è l'unica
    protezione reale del motore.
2.  **Non toccare il circuito di accensione né l'antenna dell'immobilizer.**
3.  **Diodo 1N4148 in antiparallelo** al LED di ogni PC817 collegato all'iniettore. Il PC817 regge
    **6 V inversi**; il flyback induttivo dell'iniettore ne produce 60–100. Senza il diodo il LED
    muore, magari dopo qualche ora di funzionamento.
4.  **Protezione dell'alimentazione.** L'**LM2596** della BOM accetta **40 V massimi e non ha
    protezione da load dump**: sui Monster il regolatore/raddrizzatore è un punto debole noto, e
    quando cede può superarli — con il rischio che il buck si guasti in corto e mandi i 12 V
    all'ESP32. Aggiungi almeno **TVS (SMAJ33A) + fusibile + MOSFET anti-inversione**, oppure usa un
    buck automotive tipo **LM5164** (65 V di ingresso).
5.  **Alimentazione sotto chiave**, con fusibile da 1 A a monte. La batteria da 10 Ah non regge un
    assorbimento permanente a moto ferma.
6.  **IMU su supporto smorzante** (silicone/sorbothane). Un Desmodue vibra: montata rigida falsa i
    dati e rompe le saldature. Niente breadboard, niente dupont, connettori con ritenuta.
7.  **Tutto reversibile.** L'impianto dev'essere riportabile all'originale in un'ora: derivazioni
    con connettori, mai tagli o rubacorrente sul cablaggio motore.

---

## 📱 L'Applicazione Flutter: Compilazione APK ed IPA

L'app è sviluppata in **Flutter** con un design cyberpunk metallico nero e ciano neon, ottimizzato per l'uso in moto (pulsanti giganti, testi ad alta leggibilità, allarmi cromatici).

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
*Troverai l'APK installabile sul telefono in `build/app/outputs/flutter-apk/app-release.apk` (copiato in automatico sul Desktop nel nostro script di build).*

### 🍎 Compilazione per iOS (File .IPA)
Per compilare ed esportare l'applicazione per iPhone (richiede un **Mac con Xcode** installato):
1.  Prepara la build folder:
    ```bash
    flutter build ios --release --no-codesign
    ```
2.  Genera il pacchetto distributivo `.ipa` per il caricamento su telefono:
    ```bash
    flutter build ipa --export-method development
    ```
    *Il file `.ipa` generato sarà disponibile in `build/ios/ipa/monster_sync_app.ipa`.*

---

## 🌐 Landing Page

La landing page del progetto con scrollytelling interattivo 3D del Monster 695 e sintesi sonora del motore è hostata qui:
👉 **[https://monster-sync-app.vercel.app/](https://monster-sync-app.vercel.app/)**

---

## 📄 Licenza

Questo progetto è rilasciato sotto la licenza **MIT**. Sentiti libero di fare fork, aggiungere sensori (tipo un sensore di livello olio per contare le gocce che cadono a terra) o modificare il codice.

*Disclaimer: L'uso di questa applicazione non previene lo svitamento spontaneo delle viti dovuto alle vibrazioni del bicilindrico a L né le tipiche perdite d'olio. Tenere sempre a portata di mano una chiave da 10 e una brugola da 5.*

Fatto con 🛠️ e 🔴 desmodromico da [Lorenzo Garoffolo](https://github.com/Lorenzozero).
