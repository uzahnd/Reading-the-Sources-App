xquery version "3.1";

(:module namespace custom = "http://teipublisher.com/api/custom";
:)
module namespace api = "http://teipublisher.com/api/custom";

declare namespace custom = "http://teipublisher.com/api/custom";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace util = "http://exist-db.org/xquery/util";
import module namespace idx="http://teipublisher.com/index" at "../index.xql";

(:~
 : Point d'entrée appelé par api.xql pour CHAQUE operationId.
 : On essaie de résoudre le nom dans le scope de ce module
 : (donc toute fonction custom:xxx déclarée ici est automatiquement
 : visible). Si rien ne correspond -> séquence vide, et api.xql
 : se rabat sur les modules par défaut de TEI Publisher.
 :)
declare function api:lookup($name as xs:string, $arity as xs:integer) as function(*)? {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
};

(: table of content :) 
(: ==========================================================
   Point d'entrée de l'API : /api/document/{id}/contents
   Paramètres attendus (déclarés dans custom-api.json) :
     - id      : chemin du document (path)
     - view    : mode d'affichage transmis à pb-link (query)
     - target  : cible pb-link "emit" (query)
     - text    : booléen, si vrai affiche le texte complet du verset (query)
   ========================================================== :)
declare function api:table-of-contents($request as map(*)) {
    let $id := $request?parameters?id
    let $view := $request?parameters?view
    let $target := $request?parameters?target
    let $showText := boolean($request?parameters?text)
    let $doc := config:get-document($id)

    return
        if (exists($doc))
        then
            <ul class="toc">
            {
                for $div in $doc//tei:body/tei:div[@type = ('book-introduction', 'chapter-title')]
                return api:toc-entry($div, $view, $target, $showText)
            }
            </ul>
        else
            <error status="404">Document introuvable: {$id}</error>
};

(: ==========================================================
   Une entrée de niveau "chapitre" (ou introduction), avec
   sous-liste des versets qu'elle contient.
   Les versets sont recherchés à n'importe quelle profondeur
   sous le chapitre (via //), car un niveau intermédiaire
   (wrapper) sépare parfois le chapitre de verse+commentary-text.
   ========================================================== :)
declare function api:toc-entry($div as element(tei:div), $view, $target, $showText as xs:boolean) {
    let $title := ($div//tei:ab[@type = 'MainZone-Head'])[1]/tei:title[1]
    let $label :=
        if ($title)
        then api:extract-label($title)
        else
            switch ($div/@type/string())
                case "book-introduction" return "Introduction"
                default return $div/@xml:id/string()
    let $anchor := $div/@xml:id/string()
    let $verses := $div//tei:div[@type = 'verse+commentary-text']/tei:div[@type = 'verse']
    let $link :=
        <pb-link xml-id="{$anchor}" node-id="{util:node-id($div)}" emit="{$target}" subscribe="{$target}">
            {$label}
        </pb-link>

    return
        if (exists($verses))
        then
            (: niveau avec enfants -> details/summary, comme attendu par toc.css :)
            <li class="{$div/@type/string()}">
                <details>
                    <summary>{$link}</summary>
                    <ul class="verses">
                    {
                        for $verse in $verses
                        return api:verse-entry($verse, $view, $target, $showText)
                    }
                    </ul>
                </details>
            </li>
        else
            (: niveau sans enfants -> li simple :)
            <li class="{$div/@type/string()}">
                {$link}
            </li>
};

(: ==========================================================
   Une entrée de niveau "verset", avec titre (ex. "Cap. I v.1")
   en sous-section distincte, suivi en option du texte complet
   du verset (forme reg) dans un bloc séparé.
   ========================================================== :)
declare function api:verse-entry($verse as element(tei:div), $view, $target, $showText as xs:boolean) {
    let $vid := $verse/@xml:id/string()
    let $ab := $verse/tei:ab[@type = 'MainZone-Head'][1]
    let $title := $ab/tei:title[1]

    let $label :=
        if ($title)
        then normalize-space(replace(api:extract-label($title), '^\[|\]$', ''))
        else
            let $num := replace($vid, '.*_sec_(\d+)$', '$1')
            return if ($num != $vid) then "Verset " || $num else $vid

    (: Cible du lien : le wrapper "verse+commentary-text" qui contient à la
       fois le verset ET son commentaire (xml:id = {vid}_full), pour que le
       clic affiche l'ensemble. Si ce wrapper n'existe pas (structure
       inattendue), on retombe sur le verset seul. :)
    let $target-node := ($verse/parent::tei:div[@type = 'verse+commentary-text'], $verse)[1]
    let $target-id := $target-node/@xml:id/string()

    let $link :=
        <pb-link xml-id="{$target-id}" node-id="{util:node-id($target-node)}" emit="{$target}" subscribe="{$target}">
            {$label}
        </pb-link>

    return
        if ($showText and exists($ab))
        then
            (: niveau avec contenu repliable -> details/summary, comme les chapitres :)
            <li class="verse">
                <details>
                    <summary>{$link}</summary>
                    <p class="verse-text">{api:verse-text($ab)}</p>
                </details>
            </li>
        else
            (: pas de texte à replier -> li simple :)
            <li class="verse">
                {$link}
            </li>
};

(: ==========================================================
   UTILITAIRES
   ========================================================== :)

(: Traite un seul nœud (élément ou texte) et retourne son texte
   lisible. Ignore <lb>, résout <choice> en préférant <reg>
   à <orig>, descend récursivement dans les autres éléments. :)
declare function api:node-text($n as node()) as xs:string {
    typeswitch ($n)
        case element(tei:lb) return ''
        case element(tei:choice) return
            if ($n/tei:reg)
            then api:extract-label($n/tei:reg[1])
            else api:extract-label($n/tei:orig[1])
        case element() return api:extract-label($n)
        case text() return $n/string()
        default return ''
};

(: Parcourt les enfants d'un nœud et fusionne leur texte lisible
   en résolvant les césures de fin de ligne (ex: "sal-" + "uatoris"
   -> "saluatoris"), y compris quand la césure se produit à
   l'intérieur d'un même bloc <hi> (deux <lb>+<choice> successifs).
   Utilisé pour les titres de chapitre/verset ET pour le corps
   du texte via node-text. :)
declare function api:extract-label($node as node()) as xs:string {
    let $chunks :=
        for $n in $node/node()
        let $t := api:node-text($n)
        where normalize-space($t) != ''
        return $t
    return api:join-verse-lines($chunks)
};

(: Récupère tout le texte qui suit <title> dans un <ab
   type="MainZone-Head"> — c'est-à-dire le corps du verset
   (lettrine + lignes), en forme normalisée (reg), avec :
     - la lettrine (DropCapitalLine) collée au mot suivant
       (pas d'espace, cas spécifique traité ici),
     - toutes les autres césures résolues via join-verse-lines. :)
     
declare function api:verse-text($ab as element(tei:ab)) as xs:string {
    let $title := $ab/tei:title[1]
    let $hasDropCap := exists($title/following-sibling::tei:lb[1][@type = 'DropCapitalLine'])
    let $chunks :=
        for $n in $title/following-sibling::node()
        let $t := api:node-text($n)
        where normalize-space($t) != ''
        return $t

    return
        if ($hasDropCap and count($chunks) >= 2)
        then
            let $glued := $chunks[1] || $chunks[2]
            let $restChunks := ($glued, subsequence($chunks, 3))
            return api:join-verse-lines($restChunks)
        else
            api:join-verse-lines($chunks)
};

(: Fusionne une séquence de chaînes en respectant :
     - pas d'espace après un élément se terminant par "-"
       (césure), et suppression de ce "-",
     - un espace simple dans tous les autres cas.
   Fonction générique, réutilisable partout (titres, texte
   du verset, texte imbriqué dans un <hi>). :)
   
declare function api:join-verse-lines($chunks as xs:string*) as xs:string {
    normalize-space(
        fold-left($chunks, '', function($acc as xs:string, $chunk as xs:string) as xs:string {
            if ($acc = '')
            then $chunk
            else if (ends-with($acc, '-'))
            then substring($acc, 1, string-length($acc) - 1) || $chunk
            else $acc || ' ' || $chunk
        })
    )
};

(: ==========================================================
   Point d'entrée de l'API : /api/document/{id}/manifest-url
   Renvoie l'URL du manifeste IIIF officiel (e-rara, mdz, onb, etc.)
   déjà référencée dans le teiHeader du document, sous :
   sourceDesc/msDesc/additional/surrogates/bibl/ptr/@target

   Le motif "manifest" n'est pas toujours en fin de chemin (ex. ONB :
   ".../presentation/v3/manifest/{id}", "manifest" au milieu) : on
   accepte donc aussi les URL qui le contiennent en tant que segment.
   ========================================================== :)
declare function api:manifest-url($request as map(*)) {
    let $id := $request?parameters?id
    let $doc := config:get-document($id)
    let $manifest :=
        $doc//tei:sourceDesc/tei:msDesc/tei:additional/tei:surrogates
            /tei:bibl/tei:ptr[ends-with(@target, 'manifest') or contains(@target, '/manifest/')][1]/@target/string()
    return
        if (exists($doc) and exists($manifest))
        then
            map { "manifest": $manifest }
        else if (exists($doc))
        then
            <error status="404">Aucun manifeste IIIF référencé pour ce document</error>
        else
            <error status="404">Document introuvable: {$id}</error>
};

(: ==========================================================
   Point d'entrée de l'API : /api/document/{id}/page-for-section?section={xml:id}
   Étant donné une section (chapitre ou verset, ex. "Dan_1-Tim_C_I_sec_1_full"),
   renvoie l'identifiant de page e-rara (@corresp du <pb> le plus proche
   AVANT cette section dans le document) — c'est-à-dire la première page
   du fac-similé où débute cette section.

   Si aucune section n'est précisée (ou introuvable) — par exemple quand
   le lecteur ouvre le document sur sa page web par défaut, sans cibler
   un chapitre/verset précis — on retombe sur la toute PREMIÈRE page du
   document, pour que le fac-similé s'affiche quand même correctement
   dès l'ouverture.
   ========================================================== :)
declare function api:page-for-section($request as map(*)) {
    let $id := $request?parameters?id
    let $section := $request?parameters?section
    let $doc := config:get-document($id)

    return
        if (empty($doc))
        then <error status="404">Document introuvable: {$id}</error>
        else
            let $firstPb := ($doc//tei:pb)[1]
            let $pb :=
                if (exists($section) and normalize-space($section) != '')
                then
                    let $target := $doc//*[@xml:id = $section][1]
                    return
                        if (empty($target))
                        then $firstPb
                        else
                            let $precedingPb := ($target/preceding::tei:pb)[last()]
                            return if (exists($precedingPb)) then $precedingPb else $firstPb
                else
                    $firstPb
            let $corresp := $pb/@corresp/string()
            let $surfaceId :=
                if (starts-with($corresp, '#'))
                then substring-after($corresp, '#')
                else $corresp
            return
                map { "pageId": $surfaceId }
};

(: ==========================================================
   /api/document/{id}/metadata
   Displays bibliographic metadata for the commentary (author, printer,
   place, date, holding institution, digitisation provider...), with
   clickable links wherever the teiHeader already provides one
   (biographical notes, DOI, IIIF manifest, GND, RRP database).
   ========================================================== :)

declare function api:is-hls-link($link as xs:string?) as xs:boolean {
    exists($link) and contains($link, 'hls-dhs-dss.ch')
};

declare function api:epistle-full-name($abbrev as xs:string?) as xs:string? {
    if (empty($abbrev) or normalize-space($abbrev) = '') then
        ()
    else
        switch (normalize-space($abbrev))
            case "Rom" return "Romans"
            case "1-Cor" return "1 Corinthians"
            case "2-Cor" return "2 Corinthians"
            case "Gal" return "Galatians"
            case "Eph" return "Ephesians"
            case "Phil" return "Philippians"
            case "Col" return "Colossians"
            case "1-Thess" return "1 Thessalonians"
            case "2-Thess" return "2 Thessalonians"
            case "1-Tim" return "1 Timothy"
            case "2-Tim" return "2 Timothy"
            case "Tit" return "Titus"
            case "Phlm" return "Philemon"
            case "Hebr" return "Hebrews"
            default return normalize-space($abbrev)
};

(:~
 : Code à 3 lettres utilisé par die-bibel.de pour chaque épître
 : paulinienne (ex. "ROM", "1CO"...), pour construire un lien direct
 : vers le texte de la Vulgate.
 :)
declare function api:epistle-die-bibel-code($abbrev as xs:string?) as xs:string? {
    if (empty($abbrev) or normalize-space($abbrev) = '') then
        ()
    else
        switch (normalize-space($abbrev))
            case "Rom" return "ROM"
            case "1-Cor" return "1CO"
            case "2-Cor" return "2CO"
            case "Gal" return "GAL"
            case "Eph" return "EPH"
            case "Phil" return "PHP"
            case "Col" return "COL"
            case "1-Thess" return "1TH"
            case "2-Thess" return "2TH"
            case "1-Tim" return "1TI"
            case "2-Tim" return "2TI"
            case "Tit" return "TIT"
            case "Phlm" return "PHM"
            case "Hebr" return "HEB"
            default return ()
};

declare function api:document-metadata($request as map(*)) {
    let $id := $request?parameters?id
    let $doc := config:get-document($id)
    return
        if (empty($doc)) then
            <error status="404">Document not found: {$id}</error>
        else
            let $header := $doc/tei:TEI/tei:teiHeader
            let $monogr := $header//tei:sourceDesc/tei:msDesc/tei:msContents//tei:biblStruct/tei:monogr
            let $msIdent := $header//tei:sourceDesc/tei:msDesc/tei:msIdentifier

            let $commentaryTitle := normalize-space($monogr/tei:title[@type = 'commentary_title'][1])
            let $bookTitle := normalize-space($monogr/tei:title[@type = 'book_title'][1])

            let $authorName := normalize-space($monogr/tei:author/tei:persName[1]/(tei:forename || " " || tei:surname))
            let $authorLink := $monogr/tei:author/tei:note/tei:ref[1]/@target/string()

            let $printerName := normalize-space($monogr/tei:imprint/tei:respStmt[tei:resp = 'Imprimeur']/tei:persName[1]/(tei:forename || " " || tei:surname))
            let $printerLink := $monogr/tei:imprint/tei:respStmt[tei:resp = 'Imprimeur']/tei:note/tei:ref[1]/@target/string()

            let $place := normalize-space($monogr/tei:imprint/tei:pubPlace[1])
            let $placeRef := $monogr/tei:imprint/tei:pubPlace[1]/@ref/string()
            let $placeLink := if (starts-with($placeRef, 'geonames:')) then "https://www.geonames.org/" || substring-after($placeRef, 'geonames:') else ()

            let $date := normalize-space($monogr/tei:imprint/tei:date[1])

            let $institution := normalize-space($msIdent/tei:institution[1])
            let $settlement := normalize-space($msIdent/tei:settlement[1])
            let $shelfmark := normalize-space($msIdent/tei:idno[@type = 'shelfmark'][1])

            let $provider := normalize-space($header//tei:additional/tei:surrogates/tei:bibl/tei:relatedItem[@type = 'original']/tei:ref[1])
            let $doiLink := $header//tei:additional/tei:surrogates/tei:bibl/tei:ref[starts-with(@target, 'https://doi.org')][1]/@target/string()
            (: SBB fournit un lien resolver dédié (pas un DOI) :
               <ref target="http://resolver.staatsbibliothek-berlin.de/..."/> :)
            let $sbbResolverLink := $header//tei:additional/tei:surrogates/tei:bibl/tei:ref[contains(@target, 'resolver.staatsbibliothek-berlin.de')][1]/@target/string()
            let $manifestLink := $header//tei:additional/tei:surrogates/tei:bibl/tei:ptr[ends-with(@target, 'manifest') or contains(@target, '/manifest/')][1]/@target/string()

            (: MDZ n'a généralement pas de DOI dans le teiHeader : on
               construit plutôt un lien resolver à partir de
               l'identifiant d'objet déjà présent dans l'URL du
               manifeste (ex. ".../presentation/v2/bsb10313792/manifest"
               -> "bsb10313792"), format attendu par mdz-nbn-resolving.de :
               urn:nbn:de:bvb:12-{id}-0 :)
            let $mdzObjectId :=
                if (matches($manifestLink, '/presentation/v\d+/[^/]+/manifest$')) then
                    replace($manifestLink, '^.*/presentation/v\d+/([^/]+)/manifest$', '$1')
                else
                    ()
            let $mdzResolverLink := if ($mdzObjectId) then "https://mdz-nbn-resolving.de/urn:nbn:de:bvb:12-" || $mdzObjectId || "-0" else ()

            (: ONB : lien permanent construit à partir de l'identifiant
               d'objet déjà présent dans l'URL du manifeste
               (".../presentation/v3/manifest/{id}" -> "{id}"), format
               confirmé : https://viewer.onb.ac.at/{id} :)
            let $onbObjectId :=
                if (matches($manifestLink, '/presentation/v\d+/manifest/[^/]+$')) then
                    replace($manifestLink, '^.*/presentation/v\d+/manifest/([^/]+)$', '$1')
                else
                    ()
            let $onbResolverLink := if ($onbObjectId) then "https://viewer.onb.ac.at/" || $onbObjectId else ()

            let $gndLink := $header//tei:additional/tei:listBibl/tei:bibl[tei:ref/tei:orgName = 'GND']/tei:ref[1]/@target/string()
            let $rrpLink := $header//tei:additional/tei:listBibl/tei:bibl[tei:ref/tei:orgName = 'RRP']/tei:ref[1]/@target/string()

            let $epistleAbbrev := $header//tei:profileDesc/tei:textClass/tei:keywords/tei:term[@type = 'commentary-topic'][1]
            let $epistle := api:epistle-full-name($epistleAbbrev)
            let $epistleCode := api:epistle-die-bibel-code($epistleAbbrev)
            let $epistleLink := if ($epistleCode) then "https://www.die-bibel.de/bibel/VUL/" || $epistleCode || ".1" else ()

            let $totalImages := $header//tei:extent/tei:measure[@unit = 'total_images_commentary'][1]/@n/string()
            let $processedImages := $header//tei:extent/tei:measure[@unit = 'processed_images_commentary'][1]/@n/string()

            let $links := (
                 if ($rrpLink) then
                    <li>
                        <a href="{$rrpLink}" target="_blank" rel="noopener">
                            <img src="{$config:context-path}/resources/images/logos/rrp_database.svg" alt="RRP" class="source-logo rrp-logo"/>
                            Database
                        </a>
                    </li>
                else (),

                if ($gndLink) then
                    <li>
                        <a href="{$gndLink}" target="_blank" rel="noopener">
                            <img src="{$config:context-path}/resources/images/logos/gnd.gif" alt="GND" class="source-logo"/>
                            Authority record
                        </a>
                    </li>
                else (),

                  if ($manifestLink) then
                    <li>
                        <a href="{$manifestLink}" target="_blank" rel="noopener">
                            <img src="{$config:context-path}/resources/images/logos/iiif.svg" alt="IIIF" class="source-logo"/>
                            Manifest
                        </a>
                    </li>
                else ()

            )

            let $licenceItems :=
                for $lic in $header//tei:fileDesc/tei:publicationStmt/tei:availability/tei:licence
                let $target := $lic/@target/string()
                let $desc := normalize-space($lic/following-sibling::tei:p[1])
                return
                    <li><a href="{$target}" target="_blank" rel="noopener">{ if ($desc != '') then $desc else $target }</a></li>

            return
                <div class="document-metadata">
                    { if ($commentaryTitle != '') then <h4>{$commentaryTitle}</h4> else () }
                    { if ($bookTitle != '' and $bookTitle != $commentaryTitle) then <p class="book-title">{$bookTitle}</p> else () }
                    { if ($epistle) then
                        <p class="epistle-line">
                            Epistle: { if ($epistleLink) then <a href="{$epistleLink}" target="_blank" rel="noopener">{$epistle}</a> else $epistle }
                        </p>
                      else () }

                    <div class="metadata-tabs">
                        <input type="radio" name="metadata-tab-{$id}" id="tab-work-{$id}" class="tab-input" checked="checked"/>
                        <input type="radio" name="metadata-tab-{$id}" id="tab-license-{$id}" class="tab-input"/>

                        <div class="tab-labels">
                            <label for="tab-work-{$id}">Work information</label>
                            <label for="tab-license-{$id}">License</label>
                        </div>

                        <div class="tab-panel" id="panel-work-{$id}">
                            <dl>
                                {
                                    if ($authorName != '') then (
                                        <dt>Author</dt>,
                                        <dd>
                                            { if ($authorLink) then <a href="{$authorLink}" target="_blank" rel="noopener">{$authorName}</a> else $authorName }
                                            { if (api:is-hls-link($authorLink)) then <img src="{$config:context-path}/resources/images/logos/hls.png" alt="HLS" class="source-logo"/> else () }
                                        </dd>
                                    ) else (),

                                    if ($printerName != '') then (
                                        <dt>Printer</dt>,
                                        <dd>
                                            { if ($printerLink) then <a href="{$printerLink}" target="_blank" rel="noopener">{$printerName}</a> else $printerName }
                                            { if (api:is-hls-link($printerLink)) then <img src="{$config:context-path}/resources/images/logos/hls.png" alt="HLS" class="source-logo"/> else () }
                                        </dd>
                                    ) else (),

                                    if ($place != '') then (
                                        <dt>Place</dt>,
                                        <dd>{ if ($placeLink) then <a href="{$placeLink}" target="_blank" rel="noopener">{$place}</a> else $place }</dd>
                                    ) else (),

                                    if ($date != '') then (
                                        <dt>Date</dt>,
                                        <dd>{$date}</dd>
                                    ) else (),

                                    if ($institution != '' or $provider != '') then (
                                        <dt>Holding institution</dt>,
                                        <dd>
                                            { $institution }{ if ($settlement != '') then ", " || $settlement else () }{ if ($shelfmark != '') then " (" || $shelfmark || ")" else () }
                                            { if ($provider != '') then (
                                                " | ",
                                                let $providerLogo :=
                                                    if ($provider = 'e-rara') then
                                                        <img src="{$config:context-path}/resources/images/logos/e-rara.svg" alt="e-rara" class="source-logo provider-logo"/>
                                                    else if (contains(lower-case($provider), 'mdz')) then
                                                        <img src="{$config:context-path}/resources/images/logos/mdz.png" alt="MDZ" class="source-logo provider-logo"/>
                                                    else if (contains(lower-case($provider), 'onb')) then
                                                        <img src="{$config:context-path}/resources/images/logos/onb.png" alt="ONB" class="source-logo provider-logo"/>
                                                    else if (contains(lower-case($provider), 'sbb')) then
                                                        <img src="{$config:context-path}/resources/images/logos/sbb.svg" alt="SBB" class="source-logo provider-logo"/>
                                                    else
                                                        ()
                                                let $providerLink :=
                                                    if (contains(lower-case($provider), 'mdz')) then
                                                        head(($mdzResolverLink, $doiLink))
                                                    else if (contains(lower-case($provider), 'sbb')) then
                                                        head(($sbbResolverLink, $doiLink))
                                                    else if (contains(lower-case($provider), 'onb')) then
                                                        head(($onbResolverLink, $doiLink, $manifestLink))
                                                    else
                                                        $doiLink
                                                let $isClickable := exists($providerLink)
                                                return
                                                    if ($isClickable) then
                                                        <a href="{$providerLink}" target="_blank" rel="noopener" class="provider-link">
                                                            <span class="clickable-hint" aria-hidden="true">&#8594;</span>
                                                            { if ($providerLogo) then $providerLogo else $provider }
                                                        </a>
                                                    else
                                                        ($providerLogo, if ($providerLogo) then () else $provider)
                                            ) else () }
                                        </dd>
                                    ) else (),

                                    if ($totalImages != '') then (
                                        <dt>Images processed</dt>,
                                        <dd>{$processedImages} / {$totalImages}</dd>
                                    ) else ()
                                }
                            </dl>

                            {
                                if (count($links) > 0) then
                                    <div class="metadata-links">
                                        <h5>External links</h5>
                                        <ul>{$links}</ul>
                                    </div>
                                else ()
                            }

                            <p class="ocr-disclaimer">
                                The texts have been processed using automatic OCR and Python scripts. They may still contain errors — please keep this in mind.
                            </p>
                        </div>

                        <div class="tab-panel" id="panel-license-{$id}">
                            {
                                if (count($licenceItems) > 0) then
                                    <ul>{$licenceItems}</ul>
                                else
                                    <p class="tab-empty">No license information available.</p>
                            }
                        </div>
                    </div>
                </div>
};
