// Registrazione ScrollTrigger
gsap.registerPlugin(ScrollTrigger);

const viewer = document.getElementById('ducati-viewer');

// Definiamo un oggetto che animeremo per aggiornare le proprietà del viewer 3D
const viewerParams = {
  orbitTheta: 165,
  orbitPhi: 75,
  orbitRadius: 70
};

// Funzione helper per aggiornare l'inquadratura del modello 3D
function updateCamera() {
  if (viewer) {
    viewer.cameraOrbit = `${viewerParams.orbitTheta}deg ${viewerParams.orbitPhi}deg ${viewerParams.orbitRadius}%`;
  }
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
    { orbitTheta: 360, orbitRadius: 100 },
    { orbitTheta: 165, orbitRadius: 70, duration: 2.5, ease: "power3.out", onUpdate: updateCamera }
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

// Definiamo le tappe della telecamera in base allo scroll delle varie sezioni
// Stage 1: Hero -> Concept (Nessun hotspot)
tl.to(viewerParams, {
  orbitTheta: 270, // Vista laterale sinistra
  orbitPhi: 75,
  orbitRadius: 68,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 2: Concept -> IMU/Piega (Evidenzia IMU)
.to(viewerParams, {
  orbitTheta: 180, // Inquadratura frontale/manubrio per ESP32
  orbitPhi: 60,
  orbitRadius: 55,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['imu']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 3: IMU/Piega -> Motore (Evidenzia Motore)
.to(viewerParams, {
  orbitTheta: 90, // Inquadratura laterale motore L-twin (destra)
  orbitPhi: 80,
  orbitRadius: 60,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['engine']),
  onReverseComplete: () => setHotspotsVisibility(['imu']),
  duration: 1
})
// Stage 4: Motore -> Burocrazia/Codone (Nessun hotspot, coda)
.to(viewerParams, {
  orbitTheta: 0, // Inquadratura posteriore/targa per scadenze
  orbitPhi: 75,
  orbitRadius: 65,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility([]),
  onReverseComplete: () => setHotspotsVisibility(['engine']),
  duration: 1
})
// Stage 5: Burocrazia -> Hardware Completo (Mostra tutti gli hotspot per panoramica)
.to(viewerParams, {
  orbitTheta: -90, // Vista dall'alto/laterale per mostrare la disposizione generale
  orbitPhi: 45,
  orbitRadius: 75,
  onUpdate: updateCamera,
  onStart: () => setHotspotsVisibility(['imu', 'engine', 'gps']),
  onReverseComplete: () => setHotspotsVisibility([]),
  duration: 1
})
// Stage 6: Hardware -> Download finale (Rotazione completa desmo-cinema)
.to(viewerParams, {
  orbitTheta: -195, // Rotazione cinema-style
  orbitPhi: 75,
  orbitRadius: 70,
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
