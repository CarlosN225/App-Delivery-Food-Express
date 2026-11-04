// Carga la API de Google Maps (JavaScript) con la llave del NAVEGADOR.
// La llave NO va aquí: se define en web/maps_key.js, que no se sube a GitHub.
// Ver web/maps_key.example.js.
(function () {
  var llave = window.FOOD_EXPRESS_MAPS_KEY;
  if (!llave) {
    console.warn(
      'Falta web/maps_key.js con FOOD_EXPRESS_MAPS_KEY: el mapa de Google no se mostrara.'
    );
    return;
  }
  document.write(
    '<script src="https://maps.googleapis.com/maps/api/js?key=' +
      encodeURIComponent(llave) +
      '&language=es&region=MX"><\/script>'
  );
})();
