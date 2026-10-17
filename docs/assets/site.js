// Light/dark toggle: remembers the visitor's choice in this browser only (localStorage, never sent anywhere).
(function () {
  var root = document.documentElement;
  var button = document.getElementById('theme-toggle');
  var label = document.getElementById('theme-toggle-label');
  if (!button) return;

  function render() {
    // The label names what a click switches to.
    label.textContent = root.getAttribute('data-bs-theme') === 'dark' ? 'Light' : 'Dark';
  }
  button.addEventListener('click', function () {
    var next = root.getAttribute('data-bs-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-bs-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) {}
    render();
  });
  render();
})();

// External links (another host) always open in a new window, also those inside the Markdown pages.
(function () {
  document.querySelectorAll('a[href]').forEach(function (a) {
    try {
      var url = new URL(a.href, window.location.href);
      if ((url.protocol === 'http:' || url.protocol === 'https:') && url.host !== window.location.host) {
        a.target = '_blank';
        a.rel = 'noopener noreferrer';
      }
    } catch (e) {}
  });
})();


// Guide screenshots follow the theme: in dark mode every guide image is replaced by its "-dark" counterpart
// (name.png -> name-dark.png); an image without one (the Watch screens are dark anyway) stays as it is.
(function () {
  var root = document.documentElement;
  var images = Array.prototype.filter.call(document.querySelectorAll('img[src*="/assets/guide/"]'), function (img) {
    return !/-dark\.png/.test(img.getAttribute('src')) && !/\/watch/.test(img.getAttribute('src'));
  });
  images.forEach(function (img) {
    img.dataset.light = img.getAttribute('src');
    img.addEventListener('error', function () {
      if (img.dataset.darkMissing !== '1') {
        img.dataset.darkMissing = '1';
        img.setAttribute('src', img.dataset.light);
      }
    });
  });
  function apply() {
    var dark = root.getAttribute('data-bs-theme') === 'dark';
    images.forEach(function (img) {
      if (dark && img.dataset.darkMissing !== '1') {
        img.setAttribute('src', img.dataset.light.replace(/\.png$/, '-dark.png'));
      } else {
        img.setAttribute('src', img.dataset.light);
      }
    });
  }
  new MutationObserver(apply).observe(root, { attributes: true, attributeFilter: ['data-bs-theme'] });
  apply();
})();
