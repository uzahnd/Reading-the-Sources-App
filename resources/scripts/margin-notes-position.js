/* ==========================================================
   margin-notes-position.js
   Positionne chaque note marginale (.margin-note) juste en dessous du
   .pb qui ouvre sa page (pas à côté du .pb suivant, où elle apparaît
   naturellement dans le texte source).

   Utilise un MutationObserver sur le Shadow DOM de <pb-view> (le
   contenu se construit après le chargement de la page), ET
   document.fonts.ready pour recalculer une fois que la police de
   contenu (JunicodeVF) a fini de charger — un chargement tardif de
   police peut décaler le texte après notre premier calcul, ce qui
   explique les déplacements observés.
   ========================================================== */
(function () {

    // Position verticale de la note, en proportion de la hauteur de sa
    // page : 0 = juste sous le pb d'ouverture, 1 = tout en bas.
    var PAGE_POSITION_RATIO = 0.03;

    // Espace vertical (en pixels) entre deux notes empilées sur la
    // même page.
    var GAP_BETWEEN_NOTES = 5;

    var debounceTimer = null;

    function positionMarginNotes() {
        var pbView = document.querySelector('pb-view');
        if (!pbView || !pbView.shadowRoot) {
            return;
        }
        var root = pbView.shadowRoot;
        var container = root.querySelector('#view');
        if (!container) {
            return;
        }

        var containerRect = container.getBoundingClientRect();
        var items = root.querySelectorAll('.pb, .margin-note');
        if (items.length === 0) {
            return;
        }

        var pbTops = [];
        items.forEach(function (el) {
            if (el.classList.contains('pb')) {
                var rect = el.getBoundingClientRect();
                pbTops.push(rect.top - containerRect.top);
            }
        });

        var pbIndex = -1;
        var currentTop = 0;
        var stackOffset = 0;

        items.forEach(function (el) {
            if (el.classList.contains('pb')) {
                pbIndex++;
                var thisTop = pbTops[pbIndex];
                var nextTop = (pbIndex + 1 < pbTops.length)
                    ? pbTops[pbIndex + 1]
                    : containerRect.height;
                var pageHeight = nextTop - thisTop;
                currentTop = thisTop + pageHeight * PAGE_POSITION_RATIO;
                stackOffset = 0;
            } else {
                el.style.position = 'absolute';
                el.style.top = (currentTop + stackOffset) + 'px';
                stackOffset += el.offsetHeight + GAP_BETWEEN_NOTES;
            }
        });
    }

    function scheduleReposition() {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(positionMarginNotes, 150);
    }

    function attachObserver(pbView) {
        if (!pbView.shadowRoot) {
            setTimeout(function () { attachObserver(pbView); }, 100);
            return;
        }
        var observer = new MutationObserver(scheduleReposition);
        observer.observe(pbView.shadowRoot, { childList: true, subtree: true });
        scheduleReposition();

        // Recalcule une fois que les polices web ont fini de charger
        // (une police variable comme JunicodeVF peut arriver après
        // notre premier calcul et décaler le texte).
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(scheduleReposition);
        }
    }

    function init() {
        var pbView = document.querySelector('pb-view');
        if (pbView) {
            attachObserver(pbView);
        } else {
            setTimeout(init, 100);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    window.addEventListener('resize', scheduleReposition);
})();
