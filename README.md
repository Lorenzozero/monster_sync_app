# 🏍️ MonsterSync – Il Cruscotto Cyberpunk per Ducati Monster 695 (2007)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](https://github.com/Lorenzozero/monster_sync_app)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-v3.22.x-blue.svg)](https://flutter.dev)
[![Landing Page](https://img.shields.io/badge/Landing--Page-Live%20on%20Vercel-red?style=flat&logo=vercel)](https://monster-sync-app.vercel.app)

> **"Perché comprare una Panigale V4 da 30.000€ per avere i grafici delle pieghe quando puoi rischiare un cortocircuito sulla batteria di un Monster del 2007 con 75€ di schede comprate su AliExpress?"**

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
*   🌡️ **Allarme Temperatura Testa (L-Twin Aria & Olio)**: Il motore 695cc non ha radiatore né liquido refrigerante, quindi l'unico modo che ha di smaltire calore è l'aria che gli passa sopra — e al semaforo non ne passa. La termocoppia sotto candela misura la testa verticale, quella che scalda di più, e l'app va in rosso quando superi la tua soglia. **La soglia è la tua**: si ricava registrando qualche giro normale, non copiandola da un forum.
*   🔋 **Monitoraggio Tensione Batteria**: Un voltmetro in tempo reale. Chi possiede una Ducati sa che l'alternatore è un generatore di ansia e di guasti regolatori di tensione. Tieni d'occhio i volt prima di dover spingere la moto in salita.
*   📋 **Scadenziario Burocratico & Manutenzioni**: Gestisci scadenze fiscali (Bollo, RCA, Revisione) e meccaniche (cinghie di distribuzione del Desmodue, tagliando, gioco valvole, olio) tramite database locale. Include notifiche native del sistema operativo Android/iOS per non dimenticare nulla.

---

## 🛠️ L'Hardware "Fai da Te" (BOM ~75€)

Per far funzionare la telemetria sulla moto, devi assemblare la centralina custom *MonsterSync-Brain* (da inserire sotto la sella o nel codone) utilizzando i seguenti componenti economici:

1.  **Scheda ESP32-S3** — dev board con PSRAM, es. ESP32-S3-DevKitC-1 (~€9):
    *   *Scopo*: Riceve i dati dal GPS e dall'IMU, calcola l'angolo di piega e trasmette via BLE all'app.
    *   ⚠️ **Deve essere un S3**, non un WROOM-32D: il firmware e la mappa dei pin sono tarati sull'S3.
2.  **Sensore IMU MPU-6050 (GY-521)** (~€1.20):
    *   *Scopo*: Accelerazione lineare e velocità angolare. Va fissato **in bolla** e allineato con l'asse longitudinale della moto.
    *   ℹ️ È il compromesso economico: non ha filtro anti-alias e il giroscopio deriva. Il firmware compensa (DLPF a 21 Hz + calibrazione del bias), ma per una telemetria seria il salto è un **ICM-42688-P** (~€15).
3.  **Modulo GPS Beitian BN-220** (~€9.50):
    *   *Scopo*: Velocità reale, traiettoria e quota. La velocità è ciò che alimenta il riferimento cinematico dell'angolo di piega: senza GPS, niente piega.
    *   ⚠️ **Va configurato prima dell'uso**: i BN-180/BN-220 escono di fabbrica a **9600 baud e 1 Hz**, mentre il firmware apre la seriale a **115200** e si aspetta **10 Hz**. Si imposta una volta con **u-center** (u-blox), riducendo anche le frasi NMEA attive perché a 10 Hz non ci starebbero tutte.
4.  **Fotoaccoppiatore PC817** (~€1.80) **+ diodi 1N4148** (~€1):
    *   *Scopo*: Isola i segnali a 12V della moto (impulsi iniettore per RPM e consumo, sensore riserva) portandoli a 3.3V sicuri.
    *   ⚠️ **Un 1N4148 in antiparallelo al LED di ogni opto collegato all'iniettore**: il PC817 regge 6V inversi, il flyback induttivo dell'iniettore ne produce 60–100. Senza diodo il LED muore.
5.  **Convertitore Step-Down automotive — LM5164** (~€12) **oppure LM2596 + protezioni** (~€5):
    *   *Scopo*: Porta la tensione dell'impianto (12–14,4V) ai 5V dell'ESP32.
    *   ⚠️ **L'LM2596 da solo non basta**: accetta 40V massimi e non ha protezione da *load dump*. Sui Monster il regolatore/raddrizzatore Shindengen è il punto debole noto, e quando cede può superarli — con il rischio che il buck si guasti in corto e mandi i 12V all'ESP32. Se scegli l'LM2596, aggiungi **TVS SMAJ33A + MOSFET P-channel anti-inversione** (~€2). L'LM5164 regge 65V ed è nato per l'automotive.
6.  **Scatola Waterproof IP65 + Fusibile 1A + portafusibile volante** (~€3.80):
    *   *Scopo*: Alloggiamento impermeabile e protezione dai cortocircuiti.
7.  **Temperatura testa: termocoppia tipo K con anello sotto candela + MAX31855** (~€18):
    *   *Scopo*: su un motore raffreddato ad aria la temperatura della testa è **il** parametro che
        anticipa i guai, e risponde in secondi — l'olio ci mette minuti. Va sulla **testa
        verticale**, quella dietro, che prende meno aria ed è la più calda.
    *   *Perché così e non altrimenti*: l'anello si infila sotto la candela che c'è già, quindi
        **nessuna modifica meccanica** e si torna indietro in dieci minuti (ricordandosi di
        riserrare la candela a coppia). E soprattutto **non tocca la centralina**: il sensore di
        temperatura testa della moto alimenta la Marelli 5AM e determina la carburazione — meglio
        non metterci le mani.
    *   ⚠️ **MAX31855, non MAX6675**: il 6675 è obsoleto e parte da 0 °C. In moto d'inverno serve
        leggere anche sotto zero.
    *   ⚠️ **La soglia di allarme non si copia da internet**: registra tre o quattro giri normali,
        guarda dove si assesta la *tua* moto in autostrada e nel traffico, e metti l'allarme a
        quella linea di base più una ventina di gradi.
8.  **Lettura tensione batteria: due resistenze** (~€0.20):
    *   *Scopo*: partitore **100 kΩ + 18 kΩ** verso un ingresso ADC — a 20 V d'ingresso escono
        ~3,05 V, dentro il range dell'ESP32 con margine. Aggiungi un condensatore da 100 nF verso
        massa per il rumore.
    *   *Perché conta*: su queste Ducati il regolatore/raddrizzatore è il pezzo che cede. Vedere la
        tensione a riposo e in carica ti fa scoprire il guasto **prima** di restare a piedi. È il
        miglior rapporto valore/prezzo di tutto l'ordine.
    *   *Nota*: l'ADC dell'ESP32 non è lineare agli estremi — tara la lettura una volta con un
        multimetro e salva l'offset.
9.  **Cablaggio e minuteria** (~€15) — la voce che tutti dimenticano:
    *   Cavo automotive, guaina, **connettori con ritenuta** (niente dupont sulla moto), fuse tap per la derivazione sotto chiave, resistenze 1kΩ e 10kΩ, millefori.
    *   **Supporto smorzante per l'IMU** (silicone o sorbothane): montata rigida su un bicilindrico, l'IMU falsa i dati e si spacca alle saldature.
    *   Un **cavo USB dati** (non solo ricarica) per flashare.

---

## ⚡ Il Firmware: Compilazione e Flash dell'ESP32

Il codice della centralina sta in [`firmware/`](firmware/). È un progetto **Arduino + FreeRTOS**
diviso in quattro moduli: `imu_kinematic` (angolo di piega), `gps_parser` (NMEA), `ble_server`
(server GATT) e `sensors_io` (ingressi optoisolati).

📦 **[Scarica lo ZIP pronto da flashare](docs/monstersync-firmware-esp32s3.zip)** — cartella
`MonsterSync/` già impaginata per l'IDE, con un `LEGGIMI.txt` che ripete librerie, pin e procedura.
Lo stesso pulsante è nella sezione Download della landing page.

### 🧭 Come viene calcolato l'angolo di piega

Non con Madgwick, e non è un dettaglio: **in curva stabilizzata la risultante fra gravità e
accelerazione centripeta è allineata con l'asse verticale della moto**, quindi l'accelerometro
legge `(0, 0, −g)` esattamente come da fermo in verticale. Qualunque filtro AHRS che usa
l'accelerometro come riferimento di gravità **converge a 0° mentre sei a 40° di piega**.

Il firmware usa invece:

| Componente | Sorgente |
| --- | --- |
| Alta frequenza | integrazione del rateo di rollio del giroscopio, con `dt` misurato (non costante) |
| Bassa frequenza | riferimento **cinematico** `θ = atan(v · ψ̇ / g)`, con `ψ̇ ≈ ω_y·sinθ + ω_z·cosθ` e `v` dal GPS |
| Fusione | complementare, α = 0,98 a 100 Hz |
| Accelerometro | **solo da fermo** (v < 1 m/s), per l'allineamento statico e la G-force |

Il bias del giroscopio viene misurato all'avvio su 500 campioni: **non muovere la moto** mentre sul
monitor seriale compare *"calibrazione giroscopio"*. Il DLPF del sensore è impostato a **21 Hz**
perché il bicilindrico vibra e la dinamica della moto sta sotto i 10 Hz.

> ⚠️ **Da validare su strada**: l'algoritmo è quello giusto, ma l'angolo va confrontato con un video
> girato dalla forcella prima di fidarsene. Finché non lo fai, consideralo indicativo.

### 🛠️ Ambiente

1.  **Arduino IDE 2.x** (o PlatformIO).
2.  Aggiungi il supporto ESP32: *Preferenze → URL Gestore schede aggiuntive* →
    `https://espressif.github.io/arduino-esp32/package_esp32_index.json`, poi installa
    **esp32 by Espressif Systems** dal Gestore schede.
3.  Installa dal Gestore librerie: **TinyGPSPlus** (di Mikal Hart).
    `WiFi`, `HTTPClient` e lo stack `BLEDevice` sono già inclusi nel core ESP32.

### 📌 Scheda e pin

La scheda di riferimento è l'**ESP32-S3** (su S3 i GPIO 22–26 sono riservati alla Flash Octal-SPI
e alla PSRAM: per questo i sensori stanno su GPIO 4 e 5).

| Segnale | Pin | Note |
| --- | --- | --- |
| IMU MPU-6050 | `GPIO 8` SDA · `GPIO 9` SCL | I²C a 400 kHz, alimentazione 3V3 |
| GPS RX / TX | `GPIO 16` / `GPIO 17` | `Serial1`, 115200 baud |
| Iniettore (RPM + consumo) | `GPIO 4` | interrupt su fronte di discesa, via PC817 |
| Riserva carburante | `GPIO 5` | interrupt su cambio di stato, via PC817 |

I pin I²C si cambiano in `firmware/imu_kinematic.cpp` (`IMU_SDA_PIN` / `IMU_SCL_PIN`).

> **Se usi un ESP32 classico (WROOM-32D)** invece dell'S3: lì **GPIO 5 è un pin di strapping** e
> deve stare alto all'avvio, quindi sposta l'ingresso riserva su GPIO 25/26/27/32/33 in
> `firmware/sensors_io.cpp`, e usa i pin I²C di default della tua scheda (di solito 21/22).

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
