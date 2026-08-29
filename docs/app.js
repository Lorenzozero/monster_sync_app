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
// 1. Passaggio all'IMU/Piega (Sezione 2)
tl.to(viewerParams, {
  orbitTheta: 180, // Inquadratura frontale/manubrio per ESP32
  orbitPhi: 60,
  orbitRadius: 55,
  onUpdate: updateCamera,
  duration: 1
})
// 2. Passaggio al Motore (Sezione 3)
.to(viewerParams, {
  orbitTheta: 90, // Inquadratura laterale motore L-twin (destra)
  orbitPhi: 80,
  orbitRadius: 60,
  onUpdate: updateCamera,
  duration: 1
})
// 3. Passaggio alla Burocrazia/Codone (Sezione 4)
.to(viewerParams, {
  orbitTheta: 0, // Inquadratura posteriore/targa per scadenze
  orbitPhi: 75,
  orbitRadius: 65,
  onUpdate: updateCamera,
  duration: 1
})
// 4. Passaggio all'Hardware Dettagliato (Sezione 4.5)
.to(viewerParams, {
  orbitTheta: -90, // Vista dall'alto/laterale per mostrare la disposizione generale
  orbitPhi: 45,
  orbitRadius: 75,
  onUpdate: updateCamera,
  duration: 1
})
// 5. Passaggio al Download finale (Sezione 5)
.to(viewerParams, {
  orbitTheta: -195, // Rotazione completa cinema-style
  orbitPhi: 75,
  orbitRadius: 70,
  onUpdate: updateCamera,
  duration: 1
});

// Dissolvenza e comparsa a scorrimento delle card informative (Fade-in)
const sections = ["#progetto", "#telemetria", "#motore", "#scadenze", "#hardware", "#download"];
sections.forEach((sec) => {
  gsap.from(sec + " .max-w-lg", {
    scrollTrigger: {
      trigger: sec,
      start: "top 70%",
      end: "top 30%",
      scrub: true
    },
    opacity: 0.1,
    y: 40,
    duration: 1
  });
});
