document.addEventListener('DOMContentLoaded', () => {
    const customForms = document.querySelectorAll('.facets');
    customForms.forEach((facets) => {
        facets.addEventListener('pb-custom-form-loaded', function(ev) {
            const container = ev.detail;

            // Cases à cocher : cumulables (plusieurs valeurs, plusieurs
            // dimensions à la fois). On ne soumet plus automatiquement à
            // chaque clic — seule l'exclusion mutuelle des sous-facettes
            // imbriquées reste immédiate (comportement hiérarchique).
            const elems = container.querySelectorAll('.facet');
            elems.forEach(facet => {
                facet.addEventListener('change', () => {
                    const table = facet.closest('table');
                    if (table) {
                        table.querySelectorAll('.nested .facet').forEach(nested => {
                            if (nested != facet) {
                                nested.checked = false;
                            }
                        });
                    }
                    // Pas de facets.submit() ici : on attend le bouton "Soumettre".
                });
            });

            container.querySelectorAll('pb-combo-box').forEach((select) => {
                select.renderFunction = (data, escape) => {
                    if (data) {
                        return `<div>${escape(data.text)} <span class="freq">${escape(data.freq || '')}</span></div>`;
                    }
                    return '';
                }
            });

            // Ajoute les boutons Soumettre/Effacer une seule fois, à la
            // fin de la liste des facettes.
            if (!container.querySelector('.facets-actions')) {
                const actions = document.createElement('div');
                actions.className = 'facets-actions';

                const submitBtn = document.createElement('button');
                submitBtn.type = 'button';
                submitBtn.className = 'facets-submit';
                submitBtn.textContent = 'Submit';
                submitBtn.addEventListener('click', () => facets.submit());

                const clearBtn = document.createElement('button');
                clearBtn.type = 'button';
                clearBtn.className = 'facets-clear';
                clearBtn.textContent = 'Clear';
                clearBtn.addEventListener('click', () => {
                    container.querySelectorAll('input[type=checkbox]').forEach((cb) => {
                        cb.checked = false;
                    });
                    facets.submit();
                });

                actions.appendChild(submitBtn);
                actions.appendChild(clearBtn);
                container.appendChild(actions);
            }
        });

        // Le combo-box (liste déroulante de recherche) reste en
        // soumission immédiate : usage différent (sélection ponctuelle
        // dans une longue liste), pas concerné par la demande de
        // cases cumulables avant validation.
        pbEvents.subscribe('pb-combo-box-change', null, function(ev) {
            const parent = ev.target.parentNode;
            const values = ev.detail.value;
            parent.querySelectorAll('.facet').forEach((cb) => {
                const idx = values.indexOf(cb.value);
                cb.checked = idx > -1;
                if (cb.checked) {
                    values.splice(idx, 1);
                }
            });
            values.forEach((value) => {
                const hidden = document.createElement('input');
                hidden.type = 'hidden';
                hidden.name = parent.dataset.dimension;
                hidden.value = value;
                parent.appendChild(hidden);
            });
            facets.submit();
        });
    });
});
