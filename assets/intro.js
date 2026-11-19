/* Intro de marca: video a pantalla completa, sin controles; al terminar se desvanece y revela la página. */
(function () {
  'use strict';
  var ov = document.getElementById('introOverlay');
  var v = document.getElementById('introVideo');
  var btn = document.getElementById('introSound');
  if (!ov || !v) return;

  var done = false;
  var started = false;
  var stallTimer = null;

  function finish() {
    if (done) return;
    done = true;
    clearTimeout(stallTimer);
    ov.classList.add('is-leaving');
    document.body.classList.remove('intro-lock');
    document.documentElement.classList.remove('intro-lock');
    window.removeEventListener('keydown', blockKeys);
    window.dispatchEvent(new Event('intro:done'));
    setTimeout(function () {
      try { v.pause(); v.removeAttribute('src'); v.load(); } catch (e) { /* noop */ }
      if (ov.parentNode) ov.parentNode.removeChild(ov);
    }, 1400);
  }

  // Quien prefiere menos movimiento no ve la intro.
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    ov.parentNode.removeChild(ov);
    return;
  }

  document.documentElement.classList.add('intro-lock');
  document.body.classList.add('intro-lock');
  ov.addEventListener('contextmenu', function (e) { e.preventDefault(); });
  // Bloquea el desplazamiento de la página mientras dura la intro (rueda, táctil y teclado).
  ['wheel', 'touchmove'].forEach(function (ev) {
    ov.addEventListener(ev, function (e) { e.preventDefault(); }, { passive: false });
  });
  var scrollKeys = { 32: 1, 33: 1, 34: 1, 35: 1, 36: 1, 38: 1, 40: 1 };
  function blockKeys(e) { if (!done && scrollKeys[e.keyCode]) e.preventDefault(); }
  window.addEventListener('keydown', blockKeys);

  // Encuadre: si la proporción del video difiere mucho de la pantalla, se muestra completo
  // sobre el color de fondo del propio video (sin recortar el logo).
  function fit() {
    var vw = v.videoWidth, vh = v.videoHeight;
    if (!vw || !vh) return;
    var va = vw / vh;
    var sa = window.innerWidth / window.innerHeight;
    var ratio = va > sa ? va / sa : sa / va;
    ov.classList.toggle('fit-contain', ratio > 1.35);
  }
  v.addEventListener('loadedmetadata', fit);
  window.addEventListener('resize', fit);

  // Color de fondo = esquina del primer fotograma (si el navegador lo permite).
  v.addEventListener('loadeddata', function () {
    try {
      var c = document.createElement('canvas');
      c.width = 1; c.height = 1;
      var x = c.getContext('2d');
      x.drawImage(v, 2, 2, 4, 4, 0, 0, 1, 1);
      var d = x.getImageData(0, 0, 1, 1).data;
      ov.style.background = 'rgb(' + d[0] + ',' + d[1] + ',' + d[2] + ')';
    } catch (e) { /* canvas bloqueado (file://): se usa el azul de marca */ }
  });

  function unmute() {
    if (done) return;
    v.muted = false;
    v.volume = 1;
    if (btn) btn.classList.add('hidden');
  }

  function offerSound() {
    if (!btn) return;
    btn.classList.remove('hidden');
    btn.addEventListener('click', unmute);
    ['pointerdown', 'keydown', 'touchstart', 'wheel'].forEach(function (ev) {
      window.addEventListener(ev, unmute, { once: true, passive: true });
    });
  }

  v.addEventListener('playing', function () { started = true; clearTimeout(stallTimer); });
  v.addEventListener('ended', finish);
  v.addEventListener('error', finish);

  // Si el video no arranca en 20 s (conexión lenta o bloqueo), no se retiene la página.
  stallTimer = setTimeout(function () { if (!started) finish(); }, 20000);

  // 1) Intento con sonido. 2) Si el navegador lo bloquea (política de autoplay), arranca en silencio
  // y el sonido se activa con el primer toque/clic/tecla o con el botón.
  var p = v.play();
  if (p && typeof p.catch === 'function') {
    p.catch(function () {
      v.muted = true;
      var q = v.play();
      if (q && typeof q.then === 'function') {
        q.then(offerSound).catch(finish);
      } else {
        offerSound();
      }
    });
  }
})();
