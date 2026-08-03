(: ==========================================================
   Point d'entrée de l'API : /api/document/{id}/metadata
   Affiche les métadonnées bibliographiques du commentaire (auteur,
   imprimeur, lieu, date, institution, fournisseur du fac-similé...)
   sous forme de HTML prêt à afficher, pour la colonne "after" de la
   page d'édition.
   ========================================================== :)
declare function api:document-metadata($request as map(*)) {
    let $id := $request?parameters?id
    let $doc := config:get-document($id)
    return
        if (empty($doc))
        then <error status="404">Document introuvable: {$id}</error>
        else
            let $root := $doc/tei:TEI
            let $title := idx:get-metadata($root, "title")
            let $author := idx:get-metadata($root, "author")
            let $printer := idx:get-metadata($root, "printer")
            let $place := idx:get-metadata($root, "place")
            let $date := idx:get-metadata($root, "date")
            let $institution := idx:get-metadata($root, "institution")
            let $provider := idx:get-metadata($root, "provider")
            let $epistle := idx:get-metadata($root, "epistle")
            let $quality := idx:get-metadata($root, "transcription-quality")

            let $rows := (
                if ($author != '') then <tr><th>Auteur</th><td>{$author}</td></tr> else (),
                if ($epistle != '') then <tr><th>Épître</th><td>{$epistle}</td></tr> else (),
                if ($printer != '') then <tr><th>Imprimeur</th><td>{$printer}</td></tr> else (),
                if ($place != '') then <tr><th>Lieu</th><td>{$place}</td></tr> else (),
                if ($date != '') then <tr><th>Date</th><td>{$date}</td></tr> else (),
                if ($institution != '') then <tr><th>Institution</th><td>{$institution}</td></tr> else (),
                if ($provider != '') then <tr><th>Fournisseur</th><td>{$provider}</td></tr> else (),
                if ($quality != '') then <tr><th>Qualité de transcription</th><td>{$quality}</td></tr> else ()
            )
            return
                <div class="document-metadata">
                    { if ($title != '') then <h4>{$title}</h4> else () }
                    <table>
                        { $rows }
                    </table>
                </div>
};
