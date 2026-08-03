/* ==========================================================
   mirador-sync.js
   Synchronise l'affichage Mirador (fac-similé IIIF) avec la section
   du document actuellement affichée dans pb-view.
   Attend que window.__rrpDocId et window.__rrpContextPath soient
   définis au préalable (voir basic.html, petit script inline).

   Gère deux fournisseurs IIIF :
   - e-rara.ch
   - MDZ / digitale-sammlungen.de (Bayerische Staatsbibliothek)
   ========================================================== */
(function () {
    var docId = window.__rrpDocId;
    var contextPath = window.__rrpContextPath;
    var lastSectionId = null;
    var firstRun = true;

    // Construit l'URL de canevas IIIF adaptée au fournisseur du manifeste.
    // On détecte le fournisseur via l'URL du manifeste, et on retire
    // uniquement le préfixe "f" du pageId (pas toutes les lettres, car
    // des identifiants comme "bsb10313792_00016" chez MDZ contiennent
    // des lettres à conserver après le "f" initial).
    function buildCanvasId(manifestUrl, pageId) {
        var cleanPageId = pageId.replace(/^f/, '');

        // e-rara.ch : .../i3f/v20/{workId}/manifest -> .../i3f/v20/{workId}/canvas/{numéro}
        var eraraMatch = manifestUrl.match(/\/i3f\/v(\d+)\/(\d+)\/manifest/);
        if (eraraMatch) {
            var iiifVersion = eraraMatch[1];
            var workId = eraraMatch[2];
            return "https://www.e-rara.ch/i3f/v" + iiifVersion + "/" + workId + "/canvas/" + cleanPageId;
        }

        // MDZ / digitale-sammlungen.de : .../presentation/v2/{objectId}/manifest
        // -> .../presentation/v2/{objectId}/canvas/{numéro}
        // Le numéro de canevas est la partie numérique finale de l'identifiant
        // de page (ex: "bsb10313792_00051" -> 51, sans les zéros de tête).
        var mdzMatch = manifestUrl.match(/^(https?:\/\/[^/]+\/iiif\/presentation\/v\d+\/[^/]+)\/manifest/);
        if (mdzMatch) {
            var mdzBase = mdzMatch[1];
            var pageNumMatch = cleanPageId.match(/_(\d+)$/);
            if (pageNumMatch) {
                var pageNum = parseInt(pageNumMatch[1], 10);
                return mdzBase + "/canvas/" + pageNum;
            }
        }

        // ONB (Österreichische Nationalbibliothek) : .../presentation/v3/manifest/{id}
        // -> .../presentation/v3/manifest/{id}/canvas/{numéro}
        // Confirmé directement sur un vrai manifeste : on garde l'URL du
        // manifeste telle quelle et on ajoute juste "/canvas/{numéro}".
        var onbMatch = manifestUrl.match(/\/presentation\/v\d+\/manifest\/[^/]+$/);
        if (onbMatch) {
            var onbPageNumMatch = cleanPageId.match(/(\d+)$/);
            if (onbPageNumMatch) {
                var onbPageNum = parseInt(onbPageNumMatch[1], 10);
                return manifestUrl + "/canvas/" + onbPageNum;
            }
        }

        // SBB (Staatsbibliothek zu Berlin) : .../dc/{ppn}/manifest
        // -> .../dc/{ppn}-{numéro sur 4 chiffres}/canvas
        // Structure confirmée via un exemple réel (documentation SBB) :
        // ".../dc/757246826-0018/canvas". ESTIMATION pour le format du
        // pageId (numéro extrait puis mis sur 4 chiffres) — à vérifier
        // sur un vrai document SBB, comme on l'a fait pour MDZ/ONB.
        var sbbMatch = manifestUrl.match(/^(https?:\/\/[^/]+\/dc\/)([^/]+)\/manifest$/);
        if (sbbMatch) {
            var sbbBase = sbbMatch[1];
            var sbbPpn = sbbMatch[2];
            var sbbPageNumMatch = cleanPageId.match(/(\d+)$/);
            if (sbbPageNumMatch) {
                var sbbPageNum = sbbPageNumMatch[1].padStart(4, "0");
                return sbbBase + sbbPpn + "-" + sbbPageNum + "/canvas";
            }
        }

        console.warn("[mirador-sync] Fournisseur IIIF non reconnu, canevas non calculé:", manifestUrl);
        return null;
    }

    function syncMirador() {
        var urlParams = new URLSearchParams(window.location.search);
        var sectionId = urlParams.get('id');

        // On relance à chaque changement de section, ET au tout premier
        // appel même si sectionId est absent (page par défaut du document).
        if (!firstRun && sectionId === lastSectionId) {
            return;
        }
        firstRun = false;
        lastSectionId = sectionId;

        var manifestEndpoint = contextPath + "/api/document/" + encodeURIComponent(docId) + "/manifest-url";
        // Toujours appelé, avec ou sans section : l'API retombe sur la
        // première page du document si aucune section n'est précisée.
        var pageEndpoint = contextPath + "/api/document/" + encodeURIComponent(docId) + "/page-for-section"
            + (sectionId ? "?section=" + encodeURIComponent(sectionId) : "");

        Promise.all([
            fetch(manifestEndpoint).then(function (r) { return r.json(); }),
            fetch(pageEndpoint).then(function (r) { return r.json(); })
        ]).then(function (results) {
            var manifestData = results[0];
            var pageData = results[1];

            if (!manifestData || !manifestData.manifest) {
                console.warn("Aucun manifeste IIIF trouvé pour ce document.");
                return;
            }

            var windowConfig = {
                "manifestId": manifestData.manifest,
                "view": "single"
            };

            if (pageData && pageData.pageId) {
                try {
                    var canvasId = buildCanvasId(manifestData.manifest, pageData.pageId);
                    if (canvasId) {
                        windowConfig.canvasId = canvasId;
                    }
                } catch (e) {
                    console.warn("[mirador-sync] Erreur de calcul du canevas:", e);
                }
            }

            var container = document.getElementById('mirador-facsimile');
            if (container) {
                container.innerHTML = '';
            }
            window.__mirador_instance = Mirador.viewer({
                "id": "mirador-facsimile",
                "language": "fr",
                "selectedTheme": "light",
                "window": {
                    "defaultView": "single",
                    "panels": { "annotations": false }
                },
                "workspace": {
                    "isWorkspaceAddVisible": false,
                    "showZoomControls": true
                },
                "windows": [windowConfig]
            });
        }).catch(function (err) {
            console.error("Erreur de chargement IIIF:", err);
        });
    }

    syncMirador();

    (function (history) {
        var origPushState = history.pushState;
        var origReplaceState = history.replaceState;

        function fireLocationChange() {
            window.dispatchEvent(new Event('pb-location-change'));
        }

        history.pushState = function () {
            var result = origPushState.apply(history, arguments);
            fireLocationChange();
            return result;
        };
        history.replaceState = function () {
            var result = origReplaceState.apply(history, arguments);
            fireLocationChange();
            return result;
        };
        window.addEventListener('popstate', fireLocationChange);
    })(window.history);

    window.addEventListener('pb-location-change', syncMirador);
})();