// Registrazione ScrollTrigger
gsap.registerPlugin(ScrollTrigger);

const viewer = document.getElementById('ducati-viewer');

// Definiamo un oggetto che animeremo per aggiornare le proprietà del viewer 3D
const viewerParams = {
  orbitTheta: 165,
  orbitPhi: 75,
  orbitRadius: 85, // Rimpicciolito per inquadratura iniziale spaziosa
  x: 18,           // Spostato a destra per non coprire il testo "MONSTERSYNC"
  roll: 0,
  pitch: 0,
  yaw: 0
};

// Parsing del parametro query 'no-item'
const urlParams = new URLSearchParams(window.location.search);
const noItem = urlParams.get('no-item') === 'true';

// Funzione helper per aggiornare l'inquadratura e l'orientamento 3D del modello (responsiva)
function updateCamera() {
  if (viewer) {
    if (!noItem) {
      viewer.cameraOrbit = `${viewerParams.orbitTheta}deg ${viewerParams.orbitPhi}deg ${viewerParams.orbitRadius}%`;
      viewer.orientation = `${viewerParams.roll}deg ${viewerParams.pitch}deg ${viewerParams.yaw}deg`;
      const isMobile = window.innerWidth < 1024;
      viewer.style.transform = `translateX(${isMobile ? 0 : viewerParams.x}vw)`;
    }
  }
}

// Se no-item è attivo, nascondi del tutto il modello 3D e rivela sempre la tabella costi
if (noItem && viewer) {
  viewer.style.display = 'none';
  const table = document.getElementById('hardware-table-container');
  if (table) {
    table.classList.remove('opacity-0', 'pointer-events-none', 'translate-y-10');
    table.classList.add('opacity-100', 'pointer-events-auto', 'translate-y-0');
  }
}

// Aggiorna l'inquadratura se l'utente ruota lo schermo o ridimensiona la finestra
window.addEventListener('resize', updateCamera);

// NAVBAR SCOMPARE IN BASSO / APPARE IN ALTO (GSAP ScrollTrigger)
const header = document.querySelector('header');
if (header) {
  ScrollTrigger.create({
    start: "top -80",
    end: 99999,
    onUpdate: (self) => {
      // self.direction: 1 = scorrimento verso il basso, -1 = verso l'alto
      if (self.direction === 1) {
        gsap.to(header, { yPercent: -100, duration: 0.3, ease: "power2.out" });
      } else {
        gsap.to(header, { yPercent: 0, duration: 0.3, ease: "power2.out" });
      }
    }
  });
}

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
    { orbitTheta: 360, orbitRadius: 125, x: 30, roll: 0, pitch: 0, yaw: 0 },
    { orbitTheta: 165, orbitRadius: 98, x: 18, roll: 0, pitch: 0, yaw: 0, duration: 2.5, ease: "power3.out", onUpdate: updateCamera }
  );
});

// Target animazione della tabella (viene ignorato se no-item è attivo nell'URL)
const tableAnimTarget = noItem ? [] : "#hardware-table-container";

// Imposta lo stato iniziale 3D per la tabella hardware centrata
gsap.set(tableAnimTarget, {
  opacity: 0,
  y: 80,
  rotationX: 18,
  scale: 0.85,
  pointerEvents: "none"
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

// Definiamo le tappe della telecamera, inclinazione (roll), impennata (pitch) e spostamenti
// Stage 1: Hero -> Concept/Progetto (Moto a destra, in piedi)
tl.to(viewerParams, {
  orbitTheta: 270, // Vista laterale sinistra
  orbitPhi: 75,
  orbitRadius: 95,
  x: 18,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 2: Concept -> IMU & PIEGA (MOTO PIEGATA A SINISTRA!)
.to(viewerParams, {
  orbitTheta: 180, // Inquadratura frontale per evidenziare la piega
  orbitPhi: 60,
  orbitRadius: 75,
  x: -18,
  roll: -28,       // PIEGA DI 28 GRADI A SINISTRA!
  pitch: -5,
  yaw: 15,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['imu']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 3: IMU & Piega -> Parametri Acquisiti (Raddrizza per panoramica logger)
.to(viewerParams, {
  orbitTheta: 220,
  orbitPhi: 70,
  orbitRadius: 90,
  x: 18,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility(['imu']),
  duration: 1
})
// Stage 4: Parametri -> Motore (MOTO IN IMPENNATA / WHEELIE!)
.to(viewerParams, {
  orbitTheta: 90, // Vista laterale destra per vedere l'impennata del motore
  orbitPhi: 80,
  orbitRadius: 80,
  x: -18,
  roll: 0,
  pitch: 18,      // SOLLEVA LA RUOTA ANTERIORE DI 18 GRADI!
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['engine']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 5: Motore -> Burocrazia/Scadenze (Raddrizza e inquadra il codone/targa)
.to(viewerParams, {
  orbitTheta: 0, // Inquadratura posteriore
  orbitPhi: 75,
  orbitRadius: 82,
  x: 18,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility(['engine']),
  duration: 1
})
// Stage 6: Burocrazia -> Hardware / AliExpress (Dissolvenza Modello, Rivelazione & Animazione Tabella)
.to(viewerParams, {
  orbitTheta: -90,
  orbitPhi: 45,
  orbitRadius: 90,
  x: 8,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => {
    setHotspotsVisibility([]);
    if (!noItem) {
      gsap.to(viewer, { opacity: 0, duration: 0.4 });
    }
  },
  onReverseComplete: () => {
    setHotspotsVisibility([]);
    if (!noItem) {
      gsap.to(viewer, { opacity: 1, duration: 0.4 });
    }
  },
  duration: 1
})
// La tabella fa un ingresso 3D inclinato che segue lo scorrimento
.to(tableAnimTarget, {
  opacity: 1,
  y: 0,
  rotationX: 0,
  scale: 1,
  pointerEvents: "auto",
  display: "flex",
  duration: 1
}, "<")
// La tabella scivola verso l'alto e scompare ruotando in avanti, venendo poi nascosta completamente (display: none)
.to(tableAnimTarget, {
  opacity: 0,
  y: -80,
  rotationX: -18,
  scale: 0.85,
  pointerEvents: "none",
  display: "none",
  duration: 0.8
})
// Pausa di scorrimento vuota (la tabella è sparita, il mockup non è ancora iniziato)
.to({}, { duration: 0.5 })
// Stage 7: Hardware -> Mockup Mobile (Moto riappare su desktop, scompare su mobile)
.to(viewerParams, {
  orbitTheta: -90,
  orbitPhi: 55,
  orbitRadius: 90,
  x: -18,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => {
    setHotspotsVisibility([]);
    if (!noItem) {
      const isMobile = window.innerWidth < 1024;
      gsap.to(viewer, { opacity: isMobile ? 0 : 1, duration: 0.4 });
    }
  },
  onReverseComplete: () => {
    if (!noItem) {
      gsap.to(viewer, { opacity: 0, duration: 0.4 });
    }
  },
  duration: 1
})
// Stage 8: Mockup -> Download finale (Rotazione finale cinematografica su desktop, nascosta su mobile)
.to(viewerParams, {
  orbitTheta: -195,
  orbitPhi: 75,
  orbitRadius: 95,
  x: 18,
  roll: 0,
  pitch: 0,
  yaw: 0,
  onUpdate: updateCamera,
  onStart: () => {
    setHotspotsVisibility([]);
    if (!noItem) {
      const isMobile = window.innerWidth < 1024;
      gsap.to(viewer, { opacity: isMobile ? 0 : 1, duration: 0.4 });
    }
  },
  onReverseComplete: () => {
    if (!noItem) {
      const isMobile = window.innerWidth < 1024;
      gsap.to(viewer, { opacity: isMobile ? 0 : 1, duration: 0.4 });
    }
  },
  duration: 1
});

// Animazione di rotazione del telefono mockup a landscape sullo scroll
ScrollTrigger.create({
  trigger: "#mockup",
  start: "top 45%",
  end: "top 10%",
  scrub: true,
  onUpdate: (self) => {
    const progress = self.progress; // 0 a 1
    const angle = progress * 90; // da 0 a 90 gradi
    const phone = document.getElementById('phone-mockup');
    const portraitView = document.getElementById('mock-portrait-view');
    const landscapeView = document.getElementById('mock-landscape-view');
    
    if (phone) {
      phone.style.transform = `rotate(${angle}deg)`;
    }
    
    // Dissolvenza incrociata delle viste
    if (portraitView && landscapeView) {
      if (progress > 0.5) {
        portraitView.style.opacity = '0';
        portraitView.style.pointerEvents = 'none';
        landscapeView.style.opacity = '1';
        landscapeView.style.pointerEvents = 'auto';
      } else {
        portraitView.style.opacity = '1';
        portraitView.style.pointerEvents = 'auto';
        landscapeView.style.opacity = '0';
        landscapeView.style.pointerEvents = 'none';
      }
    }
  }
});

// Dissolvenza e comparsa a scorrimento delle card informative (Fade-in / Parallax)
const sections = ["#progetto", "#telemetria", "#valori", "#motore", "#scadenze", "#copilota", "#mockup", "#download"];
sections.forEach((sec) => {
  let startVal = "top 55%";
  let endVal = "top 30%";

  // Per il mockup e il download ritardiamo la comparsa per evitare overlap su mobile
  if (sec === "#mockup") {
    startVal = "top 10%";
    endVal = "top -15%";
  } else if (sec === "#download") {
    startVal = "top 20%";
    endVal = "top 0%";
  }

  // Entrata (fade-in)
  gsap.fromTo(sec + " .max-w-2xl", 
    { opacity: 0.05, y: 40 },
    {
      scrollTrigger: {
        trigger: sec,
        start: startVal,
        end: endVal,
        scrub: true
      },
      opacity: 1,
      y: 0,
      overwrite: "auto"
    }
  );

  // Uscita (fade-out)
  gsap.to(sec + " .max-w-2xl", {
    scrollTrigger: {
      trigger: sec,
      start: "bottom 60%", // Inizia a svanire quando il fondo sale oltre il 60% del viewport
      end: "bottom 20%",   // Diventa invisibile prima di uscire del tutto
      scrub: true
    },
    opacity: 0.05,
    y: -40,
    overwrite: "auto"
  });
});

let engineRoarPlayed = false;

// Funzione di sintesi del motore L-Twin Ducati (Web Audio API)
function playDesmoEngineRoar() {
  if (engineRoarPlayed) return;

  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();

    const startSynthesis = () => {
      engineRoarPlayed = true; // Segna come avviato con successo
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
    };

    // Proviamo ad attivare il contesto (necessario su molti browser anche all'interno di un click)
    if (ctx.state === 'suspended') {
      ctx.resume().then(() => {
        if (ctx.state === 'running') {
          startSynthesis();
        }
      }).catch((e) => {
        console.warn("Impossibile sbloccare l'AudioContext:", e);
      });
    } else {
      startSynthesis();
    }

  } catch (error) {
    console.error("Errore durante la sintesi audio:", error);
  }
}

// Simulatore barra di caricamento (stile giochi di auto)
document.addEventListener("DOMContentLoaded", () => {
  const loaderBar = document.getElementById("loader-bar");
  const loaderPercentage = document.getElementById("loader-percentage");
  const loaderStatus = document.getElementById("loader-status");
  const progressContainer = document.getElementById("progress-container");
  const progressInfo = document.getElementById("progress-info");
  const loaderScreen = document.getElementById("loader-screen");
  const audioPrompt = document.getElementById("audio-prompt");

  // Sblocco preventivo dell'AudioContext al primo tocco, click o scorrimento
  const unlockAudio = () => {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      const tempCtx = new AudioContextClass();
      tempCtx.resume().then(() => {
        tempCtx.close();
        if (!engineRoarPlayed) {
          playDesmoEngineRoar();
        }
      });
    }

    if (audioPrompt) {
      audioPrompt.innerText = "AUDIO ABILITATO";
      audioPrompt.classList.remove("text-cyan-400", "animate-pulse");
      audioPrompt.classList.add("text-green-400", "border-green-500/30");
      setTimeout(() => {
        audioPrompt.style.opacity = "0";
      }, 600);
    }

    document.removeEventListener('click', unlockAudio);
    document.removeEventListener('touchstart', unlockAudio);
    document.removeEventListener('scroll', unlockAudio);
    document.removeEventListener('wheel', unlockAudio);
  };

  document.addEventListener('click', unlockAudio);
  document.addEventListener('touchstart', unlockAudio);
  document.addEventListener('scroll', unlockAudio);
  document.addEventListener('wheel', unlockAudio);

  let progress = 0;
  // Prova ad avviare la sintesi immediatamente all'avvio (se sbloccato precedentemente o consentito)
  playDesmoEngineRoar();
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
        // Esegui la sgassata del bicilindrico desmodromico immediata
        playDesmoEngineRoar();

        // Effetto dissolvenza e transizione GSAP per rivelare la pagina (più rapida)
        gsap.to(loaderScreen, {
          y: "-100vh",
          opacity: 0,
          duration: 1.0,
          ease: "power3.inOut",
          onComplete: () => {
            loaderScreen.style.display = "none";
          }
        });
      }, 150); // Avvio quasi istantaneo al 100% di progresso
    }
  }, 100);
});

// Registrazione ascoltatori interazione utente per avvio audio ritardato in caso di blocco autoplay
function initAudioInteractionListeners() {
  const triggerRoar = () => {
    if (!engineRoarPlayed) {
      playDesmoEngineRoar();
    }
    // Rimuove gli ascoltatori solo se il suono è effettivamente partito
    if (engineRoarPlayed) {
      document.removeEventListener('click', triggerRoar);
      document.removeEventListener('touchstart', triggerRoar);
      document.removeEventListener('keydown', triggerRoar);
      document.removeEventListener('scroll', triggerRoar);
      document.removeEventListener('wheel', triggerRoar);
    }
  };

  document.addEventListener('click', triggerRoar, { passive: true });
  document.addEventListener('touchstart', triggerRoar, { passive: true });
  document.addEventListener('keydown', triggerRoar, { passive: true });
  document.addEventListener('scroll', triggerRoar, { passive: true });
  document.addEventListener('wheel', triggerRoar, { passive: true });
}

initAudioInteractionListeners();
