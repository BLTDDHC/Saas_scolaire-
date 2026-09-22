{{flutter_js}}
{{flutter_build_config}}

// Les anciennes versions PWA peuvent continuer à servir un main.dart.js
// obsolète après une mise à jour. Le SaaS est actuellement distribué comme
// application Web connectée : nettoyer ces caches avant de charger Flutter
// garantit que l'interface et les contrats API appartiennent à la même version.
globalThis.godfirstStartup = (async () => {
  try {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations.map((registration) => registration.unregister()),
      );
    }
    if ('caches' in globalThis) {
      const cacheNames = await caches.keys();
      await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
    }
  } catch (error) {
    // Un navigateur privé ou une politique restrictive peut interdire l'accès
    // au cache. Cela ne doit jamais empêcher l'application de démarrer.
    console.warn('Nettoyage du cache Web impossible :', error);
  }

  await _flutter.loader.load();
})();
