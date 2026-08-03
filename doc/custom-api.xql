xquery version "3.1";

(:module namespace custom = "http://teipublisher.com/api/custom";
:)
module namespace api = "http://teipublisher.com/api/custom";

declare namespace custom = "http://teipublisher.com/api/custom";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://www.tei-c.org/tei-simple/config" at "config.xqm";
import module namespace util = "http://exist-db.org/xquery/util";

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
   Renvoie l'URL du manifeste IIIF officiel (e-rara, mdz, etc.)
   déjà référencée dans le teiHeader du document, sous :
   sourceDesc/msDesc/additional/surrogates/bibl/ptr/@target
   ========================================================== :)
declare function api:manifest-url($request as map(*)) {
    let $id := $request?parameters?id
    let $doc := config:get-document($id)
    let $manifest :=
        $doc//tei:sourceDesc/tei:msDesc/tei:additional/tei:surrogates
            /tei:bibl/tei:ptr[ends-with(@target, 'manifest')][1]/@target/string()
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
   ========================================================== :)
declare function api:page-for-section($request as map(*)) {
    let $id := $request?parameters?id
    let $section := $request?parameters?section
    let $doc := config:get-document($id)
    let $target := $doc//*[@xml:id = $section][1]

    return
        if (empty($doc))
        then <error status="404">Document introuvable: {$id}</error>
        else if (empty($target))
        then <error status="404">Section introuvable: {$section}</error>
        else
            let $pb := ($target/preceding::tei:pb)[last()]
            let $pb := if (exists($pb)) then $pb else ($doc//tei:pb)[1]
            let $corresp := $pb/@corresp/string()
            let $surfaceId :=
                if (starts-with($corresp, '#'))
                then substring-after($corresp, '#')
                else $corresp
            return
                map { "pageId": $surfaceId }
};

