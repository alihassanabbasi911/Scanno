/* pptx kabuğunun mantığı.
 *
 * PPTXjs bu kopyada beş yama taşıyor (madde imi buFont mirası, Wingdings
 * dingbat dönüşümü, XML karakter referansı, eksik docProps/app.xml'de çökme,
 * numCol/vert) — ayrıntı vendor/pptxjs/PATCHES.md.
 *
 * PPTXjs bir dosya girdisine bağlanmayı bekliyor; byte'lar köprüden geldiği
 * için gizli bir input'a DataTransfer ile yazıp change olayını tetikliyoruz.
 * Tamamlanma, async FileReader beklemesini hesaba katmak için motordan gelir;
 * DOM sessizliğine göre süre tahmin edilmez.
 */
(function () {
  'use strict';

  const stage = document.getElementById('stage');
  let startedAt = 0;

  function fail(error) {
    if (!startedAt) {
      return;
    }
    startedAt = 0;
    Bridge.send('error', {
      code: 'render_failed',
      detail: String(error && (error.stack || error.message) || error)
    });
  }

  function reportRendered() {
    if (!startedAt) {
      return;
    }
    const slides = stage.querySelectorAll('.slide');
    if (!slides.length) {
      return fail('PPTXjs did not render any slides');
    }
    fitToWidth(slides);
    const outline = [];
    slides.forEach(function (slide, index) {
      slide.setAttribute('data-slide', String(index));
      const text = (slide.textContent || '').trim().split('\n')[0];
      outline.push(text ? text.slice(0, 60) : 'Slayt ' + (index + 1));
    });
    Bridge.send('rendered', {
      ms: Math.round(performance.now() - startedAt),
      units: slides.length,
      styled: true,
      outline: outline
    });
    startedAt = 0;
  }

  /* PPTXjs slaytlara sabit piksel genişlik veriyor (ör. 960 px); telefonda
     taşıyor. Her slaytı ölçekleyip kapsayıcı yüksekliğini düzeltiyoruz. */
  function fitToWidth(slides) {
    const available = document.documentElement.clientWidth;
    slides.forEach(function (slide) {
      const width = slide.offsetWidth;
      const height = slide.offsetHeight;
      if (!width || width <= available) {
        return;
      }
      const scale = available / width;
      slide.style.transformOrigin = 'top left';
      slide.style.transform = 'scale(' + scale + ')';
      // Ölçek düzen kutusunu küçültmüyor; kalan boşluğu negatif kenar
      // boşluğuyla geri alıyoruz, yoksa slaytlar arası dev boşluk kalıyor.
      slide.style.marginLeft = '0';
      slide.style.marginRight = (available - width) + 'px';
      slide.style.marginBottom = (16 - height * (1 - scale)) + 'px';
    });
  }

  function render(bytes) {
    startedAt = performance.now();

    const input = document.createElement('input');
    input.type = 'file';
    input.id = 'pptx-source';
    input.style.display = 'none';
    document.body.appendChild(input);

    // PPTXjs MIME'ı tam eşleşme ile kontrol ediyor.
    const file = new File([bytes], 'doc.pptx', {
      type: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    });
    const transfer = new DataTransfer();
    transfer.items.add(file);
    input.files = transfer.files;

    try {
      window.jQuery('#stage').pptxToHtml({
        fileInputId: 'pptx-source',
        slideMode: false,
        keyBoardShortCut: false,
        mediaProcess: true,
        themeProcess: true,
        onReady: reportRendered,
        onError: fail
      });
      input.dispatchEvent(new Event('change', { bubbles: true }));
    } catch (error) {
      fail(error);
    }
  }

  Bridge.on('goto', function (payload) {
    const target = stage.querySelector('[data-slide="' + payload.index + '"]');
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });

  Bridge.on('search', function (payload) {
    const query = (payload.query || '').toLocaleLowerCase('tr');
    let hits = 0;
    stage.querySelectorAll('.slide').forEach(function (slide) {
      const match =
        query && (slide.textContent || '').toLocaleLowerCase('tr').indexOf(query) >= 0;
      slide.classList.toggle('hit', Boolean(match));
      if (match) {
        hits++;
      }
    });
    const first = stage.querySelector('.slide.hit');
    if (first) {
      first.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    Bridge.send('searchResult', { hits: hits });
  });

  Bridge.start(render);
})();
