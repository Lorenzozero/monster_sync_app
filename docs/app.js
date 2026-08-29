// Registrazione ScrollTrigger
gsap.registerPlugin(ScrollTrigger);

const viewer = document.getElementById('ducati-viewer');

// Definiamo un oggetto che animeremo per aggiornare le proprietà del viewer 3D
const viewerParams = {
  orbitTheta: 165,
  orbitPhi: 75,
  orbitRadius: 85, // Rimpicciolito per inquadratura iniziale spaziosa
  x: 18            // Spostato a destra per non coprire il testo "MONSTERSYNC"
};

// Funzione helper per aggiornare l'inquadratura del modello 3D (responsiva)
function updateCamera() {
  if (viewer) {
    viewer.cameraOrbit = `${viewerParams.orbitTheta}deg ${viewerParams.orbitPhi}deg ${viewerParams.orbitRadius}%`;
    const isMobile = window.innerWidth < 1024;
    viewer.style.transform = `translateX(${isMobile ? 0 : viewerParams.x}vw)`;
  }
}

// Aggiorna l'inquadratura se l'utente ruota lo schermo o ridimensiona la finestra
window.addEventListener('resize', updateCamera);

// Gestione visibilità Hotspots
const imuHotspot = document.querySelector('[slot="hotspot-imu"]');
const engineHotspot = document.querySelector('[slot="hotspot-engine"]');
const gpsHotspot = document.querySelector('[slot="hotspot-gps"]');

function setHotspotsVisibility(activeList) {
  if (imuHotspot) {
    imuHotspot.style.opacity = activeList.includes('imu') ? '1' : '0';
    imuHotspot.style.pointerEvents = activeList.includes('imu') ? 'auto' : 'none';
  }
  if (engineHotspot) {
    engineHotspot.style.opacity = activeList.includes('engine') ? '1' : '0';
    engineHotspot.style.pointerEvents = activeList.includes('engine') ? 'auto' : 'none';
  }
  if (gpsHotspot) {
    gpsHotspot.style.opacity = activeList.includes('gps') ? '1' : '0';
    gpsHotspot.style.pointerEvents = activeList.includes('gps') ? 'auto' : 'none';
  }
}

// Inizialmente nascondi tutti gli hotspot
setHotspotsVisibility([]);

// Inizializzazione camera al caricamento
viewer.addEventListener('load', () => {
  updateCamera();
  // Animazione iniziale d'ingresso
  gsap.fromTo(viewerParams, 
    { orbitTheta: 360, orbitRadius: 110, x: 30 },
    { orbitTheta: 165, orbitRadius: 85, x: 18, duration: 2.5, ease: "power3.out", onUpdate: updateCamera }
  );
});

// Creiamo una timeline agganciata allo scorrimento globale della pagina
const tl = gsap.timeline({
  scrollTrigger: {
    trigger: "body",
    start: "top top",
    end: "bottom bottom",
    scrub: 1, // effetto molla fluido di 1 secondo nello scroll
  }
});

// Definiamo le tappe della telecamera e degli spostamenti (x) per evitare sovrapposizioni
// Stage 1: Hero -> Concept/Progetto (Nessun hotspot, moto a destra)
tl.to(viewerParams, {
  orbitTheta: 270, // Vista laterale sinistra
  orbitPhi: 75,
  orbitRadius: 80,
  x: 15,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 2: Concept -> IMU/Piega (Evidenzia IMU, sposta un po' più al centro per focalizzare)
.to(viewerParams, {
  orbitTheta: 180, // Inquadratura frontale/manubrio per ESP32
  orbitPhi: 60,
  orbitRadius: 65,
  x: 10,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['imu']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 3: IMU/Piega -> Motore (Evidenzia Motore)
.to(viewerParams, {
  orbitTheta: 90, // Inquadratura laterale motore L-twin (destra)
  orbitPhi: 80,
  orbitRadius: 65,
  x: 12,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['engine']),
  onReverseComplete: () => setHotspotsVisibility(['imu']),
  duration: 1
})
// Stage 4: Motore -> Burocrazia/Codone (Nessun hotspot, coda)
.to(viewerParams, {
  orbitTheta: 0, // Inquadratura posteriore/targa per scadenze
  orbitPhi: 75,
  orbitRadius: 68,
  x: 14,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility(['engine']),
  duration: 1
})
// Stage 5: Burocrazia -> Hardware Completo (Mostra tutti gli hotspot per panoramica)
.to(viewerParams, {
  orbitTheta: -90, // Vista dall'alto/laterale
  orbitPhi: 45,
  orbitRadius: 75,
  x: 8,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['imu', 'engine', 'gps']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 6: Hardware -> Download finale (Rotazione completa desmo-cinema)
.to(viewerParams, {
  orbitTheta: -195, // Rotazione cinema-style
  orbitPhi: 75,
  orbitRadius: 80,
  x: 12,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility(['imu', 'engine', 'gps']),
  duration: 1
});

// Dissolvenza e comparsa a scorrimento delle card informative (Fade-in / Parallax)
const sections = ["#progetto", "#telemetria", "#motore", "#scadenze", "#hardware", "#download"];
sections.forEach((sec) => {
  gsap.from(sec + " .max-w-lg", {
    scrollTrigger: {
      trigger: sec,
      start: "top 80%",
      end: "top 40%",
      scrub: true
    },
    opacity: 0.05,
    y: 50,
    duration: 1
  });
});

// ── SISTEMA DI CARICAMENTO INIZIALE & SINTESI AUDIO ─────────────────────────

// Funzione di sintesi del motore L-Twin Ducati (Web Audio API)
function playDesmoEngineRoar() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    const now = ctx.currentTime;

    // Oscillatore principale (sawtooth per il rombo meccanico)
    const osc1 = ctx.createOscillator();
    osc1.type = 'sawtooth';
    osc1.frequency.setValueAtTime(45, now); // frequenza di base (minimo profondo)

    // Secondo oscillatore (triangle per aggiungere armoniche e corpo)
    const osc2 = ctx.createOscillator();
    osc2.type = 'triangle';
    osc2.frequency.setValueAtTime(90, now);

    // Filtro passa-basso per incupire il rombo
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(180, now);
    filter.Q.setValueAtTime(4, now);

    // LFO per simulare i singoli scoppi dei pistoni (circa 7Hz a minimo)
    const lfo = ctx.createOscillator();
    lfo.type = 'sawtooth';
    lfo.frequency.setValueAtTime(7, now);

    const lfoGain = ctx.createGain();
    lfoGain.gain.setValueAtTime(12, now); // deviazione in Hz

    // Noise Generator per il soffio dello scarico
    const bufferSize = ctx.sampleRate * 2;
    const noiseBuffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1;
    }
    const whiteNoise = ctx.createBufferSource();
    whiteNoise.buffer = noiseBuffer;
    whiteNoise.loop = true;

    const noiseFilter = ctx.createBiquadFilter();
    noiseFilter.type = 'bandpass';
    noiseFilter.frequency.setValueAtTime(220, now);
    noiseFilter.Q.setValueAtTime(2, now);

    const noiseGain = ctx.createGain();
    noiseGain.gain.setValueAtTime(0.02, now);

    // Nodo distorsione per simulare il carattere ruvido del motore desmo
    const dist = ctx.createWaveShaper();
    function makeDistortionCurve(amount) {
      const k = typeof amount === 'number' ? amount : 50;
      const n_samples = 44100;
      const curve = new Float32Array(n_samples);
      const deg = Math.PI / 180;
      for (let i = 0; i < n_samples; ++i) {
        const x = (i * 2) / n_samples - 1;
        curve[i] = ((3 + k) * x * 20 * deg) / (Math.PI + k * Math.abs(x));
      }
      return curve;
    }
    dist.curve = makeDistortionCurve(10);
    dist.oversample = '4x';

    // Regolazione guadagni
    const mainGain = ctx.createGain();
    mainGain.gain.setValueAtTime(0.001, now);

    // Connessioni LFO per la modulazione di frequenza (piston stroke)
    lfo.connect(lfoGain);
    lfoGain.connect(osc1.frequency);
    lfoGain.connect(osc2.frequency);

    // Connessioni catena di sintesi
    osc1.connect(filter);
    osc2.connect(filter);
    filter.connect(dist);
    
    // Connessioni rumore scarico
    whiteNoise.connect(noiseFilter);
    noiseFilter.connect(noiseGain);
    
    // Mix finale
    dist.connect(mainGain);
    noiseGain.connect(mainGain);
    mainGain.connect(ctx.destination);

    // Avvio oscillatori
    osc1.start(now);
    osc2.start(now);
    lfo.start(now);
    whiteNoise.start(now);

    // SIMULAZIONE RUGGITO / ACCELERATA (VROOOOM!)
    // 1. Minimo per 0.3 secondi
    mainGain.gain.exponentialRampToValueAtTime(0.7, now + 0.2);

    // 2. Colpo di gas (Sgassata desmo) a 0.8s (da 45Hz a 130Hz, LFO da 7Hz a 26Hz)
    osc1.frequency.exponentialRampToValueAtTime(130, now + 0.7);
    osc2.frequency.exponentialRampToValueAtTime(260, now + 0.7);
    lfo.frequency.linearRampToValueAtTime(24, now + 0.7);
    filter.frequency.exponentialRampToValueAtTime(800, now + 0.7);
    noiseGain.gain.linearRampToValueAtTime(0.08, now + 0.7);

    // 3. Rilascio gas e ritorno al minimo a 1.6s
    osc1.frequency.exponentialRampToValueAtTime(45, now + 1.5);
    osc2.frequency.exponentialRampToValueAtTime(90, now + 1.5);
    lfo.frequency.linearRampToValueAtTime(7, now + 1.5);
    filter.frequency.exponentialRampToValueAtTime(180, now + 1.5);
    noiseGain.gain.linearRampToValueAtTime(0.02, now + 1.5);

    // 4. Spegnimento graduale (Fade-out)
    mainGain.gain.setValueAtTime(0.7, now + 1.8);
    mainGain.gain.exponentialRampToValueAtTime(0.001, now + 2.5);

    // Stop dei nodi
    setTimeout(() => {
      osc1.stop();
      osc2.stop();
      lfo.stop();
      whiteNoise.stop();
      ctx.close();
    }, 2800);

  } catch (error) {
    console.error("Errore durante la sintesi audio:", error);
  }
}

// Simulatore barra di caricamento (stile giochi di auto)
document.addEventListener("DOMContentLoaded", () => {
  const loaderBar = document.getElementById("loader-bar");
  const loaderPercentage = document.getElementById("loader-percentage");
  const loaderStatus = document.getElementById("loader-status");
  const startBtn = document.getElementById("start-btn");
  const progressContainer = document.getElementById("progress-container");
  const progressInfo = document.getElementById("progress-info");
  const loaderScreen = document.getElementById("loader-screen");

  let progress = 0;
  const statusTexts = [
    "DIAGNOSTICA MPU-6050...",
    "SINCRONIZZAZIONE REGOLATORE TENSIONE...",
    "AVVIO SERVO DIALOGO BLUETOOTH...",
    "ACQUISIZIONE SATELLITI GPS 10Hz...",
    "VERIFICA PERDITE OLIO (OK, SONO REGOLAMENTARI)...",
    "SISTEMI PRONTI A CURVARE!"
  ];

  const interval = setInterval(() => {
    progress += Math.floor(Math.random() * 8) + 4;
    if (progress > 100) progress = 100;

    loaderBar.style.width = `${progress}%`;
    loaderPercentage.innerText = `${progress}%`;

    // Cambia il testo dello stato a seconda del progresso
    const textIdx = Math.min(
      Math.floor((progress / 100) * statusTexts.length),
      statusTexts.length - 1
    );
    loaderStatus.innerText = statusTexts[textIdx];

    if (progress === 100) {
      clearInterval(interval);
      setTimeout(() => {
        // Esegui la sgassata del bicilindrico desmodromico
        playDesmoEngineRoar();

        // Effetto dissolvenza e transizione GSAP per rivelare la pagina
        gsap.to(loaderScreen, {
          y: "-100vh",
          opacity: 0,
          duration: 1.2,
          ease: "power4.inOut",
          onComplete: () => {
            loaderScreen.style.display = "none";
          }
        });
      }, 500);
    }
  }, 100);
});
