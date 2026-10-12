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

