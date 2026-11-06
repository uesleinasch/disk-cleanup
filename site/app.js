(function () {
  var repo = 'uesleinasch/disk-cleanup';
  var list = document.getElementById('releases');
  var download = document.getElementById('download');
  var meta = document.getElementById('latest-meta');

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }

  function fallback() {
    list.textContent = '';
    var li = el('li', 'note');
    var a = el('a', null, 'Ver versões no GitHub');
    a.href = 'https://github.com/' + repo + '/releases';
    li.appendChild(a);
    list.appendChild(li);
  }

  function sizeMB(bytes) {
    return (bytes / 1e6).toFixed(1).replace('.', ',') + ' MB';
  }

  fetch('https://api.github.com/repos/' + repo + '/releases', {
    headers: { Accept: 'application/vnd.github+json' }
  })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (releases) {
      releases = releases.filter(function (r) { return !r.draft; });
      if (!releases.length) {
        list.textContent = '';
        list.appendChild(el('li', 'note', 'Nenhuma versão publicada ainda.'));
        return;
      }
      list.textContent = '';
      releases.forEach(function (r, i) {
        var asset = (r.assets || []).find(function (a) { return /\.AppImage$/.test(a.name); });
        var li = el('li');
        li.appendChild(el('span', 'name', r.name || r.tag_name));
        li.appendChild(el('span', 'date', new Date(r.published_at).toLocaleDateString('pt-BR')));
        var a = el('a', null, asset ? 'Baixar AppImage (' + sizeMB(asset.size) + ')' : 'Ver release');
        a.href = asset ? asset.browser_download_url : r.html_url;
        li.appendChild(a);
        list.appendChild(li);
        if (i === 0 && asset) {
          download.href = asset.browser_download_url;
          meta.textContent = (r.tag_name) + ' · AppImage para Linux x86_64 · ' + sizeMB(asset.size);
        }
      });
    })
    .catch(fallback);
})();
