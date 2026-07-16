// Custom Flutter bootstrap. Replaces the generated one so the app loads
// WITHOUT registering a service worker.
//
// Flutter's default offline-first worker serves the previously cached bundle
// on the first load after a deploy, so a freshly upgraded self-hosted server
// keeps handing visitors the old app until they reload a second time (or
// hard-refresh). For a server the household upgrades in place — and during
// development, where the bundle is rebuilt constantly — that staleness is a
// worse trade than the offline support it buys. Passing no
// `serviceWorkerSettings` to load() is the supported way to opt out.
// Not registering a worker does not remove one a PREVIOUS build installed:
// it stays registered and keeps serving its cache to that browser forever.
// Tear down any leftover so an upgraded server actually reaches its users.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker
    .getRegistrations()
    .then((registrations) => {
      for (const registration of registrations) {
        registration.unregister();
      }
    })
    .catch(() => {
      // Never let cache housekeeping keep the app from booting.
    });
}

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
