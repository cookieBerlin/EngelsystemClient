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

// Pages with a contents list (layout: page.toc): a link to every chapter (h2/h3) in the side column on large screens and in
// a folded "Contents" block on small ones, a "#" link at every heading, and a "Top" button once the page is scrolled.
(function () {
  var side = document.getElementById('toc-side');
  var mobile = document.getElementById('toc-mobile');
  if (!side || !mobile) return;
  var headings = document.querySelectorAll('main h2, main h3, main h4');

  var used = {};
  headings.forEach(function (heading) {
    if (!heading.id) {
      heading.id = heading.textContent.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'section';
    }
    if (used[heading.id]) heading.id += '-' + (used[heading.id] += 1); else used[heading.id] = 1;
    heading.dataset.label = heading.textContent.trim();
    var anchor = document.createElement('a');
    anchor.className = 'anchor-link';
    anchor.href = '#' + heading.id;
    anchor.setAttribute('aria-label', 'Link to this section');
    anchor.textContent = '#';
    heading.appendChild(anchor);
  });

  function build(target) {
    var list = document.createElement('ul');
    var sub = null;
    document.querySelectorAll('main h2, main h3').forEach(function (heading) {
      var item = document.createElement('li');
      var link = document.createElement('a');
      link.href = '#' + heading.id;
      link.textContent = heading.dataset.label;
      item.appendChild(link);
      if (heading.tagName === 'H2' || !sub) {
        list.appendChild(item);
        sub = null;
        if (heading.tagName === 'H2') { sub = document.createElement('ul'); item.appendChild(sub); }
      } else {
        sub.appendChild(item);
      }
    });
    list.querySelectorAll('ul:empty').forEach(function (empty) { empty.remove(); });
    target.appendChild(list);
  }
  build(side);
  build(mobile.querySelector('nav'));
  // Choosing a chapter on a small screen folds the list away again.
  mobile.addEventListener('click', function (event) {
    if (event.target.closest('a')) mobile.removeAttribute('open');
  });

  var top = document.getElementById('to-top');
  if (top) {
    window.addEventListener('scroll', function () { top.hidden = window.scrollY < 600; }, { passive: true });
  }
})();
