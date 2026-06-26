(function () {
  var productionHosts = {
    'healthmd.app': true,
    'www.healthmd.app': true
  };

  if (!productionHosts[window.location.hostname]) {
    return;
  }

  function loadCloudflareBeacon() {
    if (document.querySelector('script[src="https://static.cloudflareinsights.com/beacon.min.js"]')) {
      return;
    }

    var script = document.createElement('script');
    script.defer = true;
    script.src = 'https://static.cloudflareinsights.com/beacon.min.js';
    script.setAttribute('data-cf-beacon', '{"token":"090f363070334cddad5c5cc1509b8807"}');
    document.head.appendChild(script);
  }

  fetch('https://img-host.costream.workers.dev/analytics-gate', {
    cache: 'no-store',
    mode: 'cors',
    credentials: 'omit'
  })
    .then(function (response) {
      return response.ok ? response.json() : { track: false };
    })
    .then(function (gate) {
      if (gate && gate.track) {
        loadCloudflareBeacon();
      }
    })
    .catch(function () {
      // Fail closed so excluded IPs are not accidentally tracked.
    });
})();
