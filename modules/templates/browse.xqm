xquery version "3.1";

module namespace browse="http://teipublisher.com/ns/templates/browse";

import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "../lib/util.xql";
import module namespace nav="http://www.tei-c.org/tei-simple/navigation" at "../navigation.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "../../config.xqm";
import module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config" at "../pm-config.xql";
import module namespace query="http://www.tei-c.org/tei-simple/query" at "../query.xql";
import module namespace kwic="http://exist-db.org/xquery/kwic" at "resource:org/exist/xquery/lib/kwic.xql";
import module namespace idx="http://teipublisher.com/index" at "../../index.xql";

declare namespace tei="http://www.tei-c.org/ns/1.0";

declare function browse:parent-link($context as map(*)) {
    let $parts := 
        if (exists($context?doc)) then
            config:get-relpath($context?doc?content, $config:data-default) => tokenize("/")
        else
            head(($context?request?parameters?path, $context?request?parameters?docid)) => tokenize("/")
    return
        string-join(subsequence($parts, 1, count($parts) - 1), "/")
};

declare function browse:is-writable($context as map(*)) {
    let $path := $config:data-root || "/" || $context?request?parameters?path
    let $writable := sm:has-access(xs:anyURI($path), "rw-")
    return
        if ($writable) then "writable" else ""
};

declare function browse:document-options($doc as element()) {
    let $config := tpu:parse-pi(root($doc), ())
    return map:merge((
        $config,
        map {
            "relpath": config:get-identifier($doc),
            "odd": head(($config?odd, $config:default-odd))
        }
    ))
};

declare function browse:header($context as map(*), $doc as element()) {
    browse:header($context, $doc, browse:document-options($doc))
};

declare function browse:header($context as map(*), $doc as element(), $config as map(*)) {
    try {
        let $teiHeader := nav:get-header($config, root($doc)/*)
        let $header :=
            $pm-config:web-transform($teiHeader, map {
                "display": "browse",
                "doc": if ($config:address-by-id) then config:get-identifier($doc) else $config:context-path || "/" || $config?relpath,
                "language": $context?language
            }, $config?odd)
        return
            if ($header) then
                $header
            else
                <a href="{$config?relPath}">{$config?relPath}</a>
    } catch * {
        <a href="{$config?relPath}">{util:document-name($doc)}</a>,
        <p class="error">Failed to output document metadata: {$err:description}</p>
    }
};
(:
declare function browse:show-hits($context as map(*), $doc as element()) {
    if (exists($context?request?parameters?query) and $context?request?parameters?query != '') then
        let $fieldName := head(($context?request?parameters?field, "text"))
        for $field in ft:highlight-field-matches($doc, query:field-prefix($doc) || $fieldName)
        let $matches := $field//exist:match
        return
            if (count($matches)) then 
                <div class="matches">
                    <div class="count"><pb-i18n key="browse.items" options='{{"count": {count($matches)}}}'></pb-i18n></div>
                    {
                        for $match in subsequence($matches, 1, 5)
                        let $config := <config width="60" table="no"/>
                        return
                            kwic:get-summary($field, $match, $config)
                    }
                </div>
            else ()
    else
        ()
};:)

(:j'ajoute du contexte autour du mot recherche et je pointe vers le xml id:)
(:~
 : Construit l'extrait cliquable d'un seul résultat (mot trouvé + contexte),
 : pointant vers la section précise (xml:id) qui le contient.
  fonctionnel le 30 juillet:)
(:declare %private function browse:render-match($field as element(), $docId as xs:string, $match as element(exist:match)) {
    let $config := <config width="180" table="no"/>
    return
        kwic:get-summary($field, $match, $config)
};

declare function browse:show-hits($context as map(*), $doc as element()) {
    if (exists($context?request?parameters?query) and $context?request?parameters?query != '') then
        let $fieldName := head(($context?request?parameters?field, "text"))
        for $field in ft:highlight-field-matches($doc, query:field-prefix($doc) || $fieldName)
        let $matches := $field//exist:match
        let $total := count($matches)
        return
            if ($total > 0) then
                let $shown := subsequence($matches, 1, 5)
                let $rest := subsequence($matches, 6)
                return
                    <div class="matches">
                        <div class="count"><pb-i18n key="browse.items" options='{{"count": {$total}}}'></pb-i18n></div>
                        {
                            for $match in $shown
                            return browse:render-match($field, "", $match)
                        }
                        {
                            if (count($rest) > 0) then
                                <details class="more-matches">
                                    <summary>Show all {$total} results</summary>
                                    {
                                        for $match in $rest
                                        return browse:render-match($field, "", $match)
                                    }
                                </details>
                            else ()
                        }
                    </div>
            else ()
    else
        ()
};:)
(:~
 : Libellé de section (ex. "Cap. II, § 7"), comme pour la table des
 : matières.
 :)
(:~
 : Libellé de section (ex. "Cap. II, § 7"), comme pour la table des
 : matières.
 :)
declare %private function browse:section-label($div as element()) as xs:string {
    let $title := ($div//tei:ab[@type = 'MainZone-Head'])[1]/tei:title[1]
    return
        if ($title) then
            normalize-space(replace(idx:get-searchable-text($title), '^\[|\]$', ''))
        else
            $div/@xml:id/string()
};

(:~
 : Reconstruit, POUR UNE SECTION DONNÉE, un extrait par occurrence du
 : terme recherché — texte ET xml:id viennent du MÊME nœud, ce qui
 : garantit qu'ils correspondent toujours (contrairement à une
 : association par position entre deux listes séparées, qui s'est
 : révélée peu fiable).
 :)
declare %private function browse:extract-snippets(
    $div as element(),
    $searchRegex as xs:string,
    $docId as xs:string,
    $width as xs:integer
) as element()* {
    let $label := browse:section-label($div)
    let $sectionId := $div/@xml:id/string()
    let $href := $docId || "?id=" || $sectionId || "&amp;action=search#" || $sectionId
    let $fullText := normalize-space(idx:get-searchable-text($div))
    let $tokens := analyze-string($fullText, $searchRegex, 'i')/*
    for $i in 1 to count($tokens)
    where local-name($tokens[$i]) = 'match'
    let $beforeText := string-join(for $t in $tokens[position() lt $i] return string($t), '')
    let $afterText := string-join(for $t in $tokens[position() gt $i] return string($t), '')
    let $beforeTrimmed := substring($beforeText, max((string-length($beforeText) - $width, 1)))
    let $afterTrimmed := substring($afterText, 1, $width)
    return
        <p class="result-line">
            <a class="section-label" href="{$href}">[{$label}]</a>
            {" ...", $beforeTrimmed}
            <mark>{string($tokens[$i])}</mark>
            {$afterTrimmed, "..."}
        </p>
};

declare function browse:show-hits($context as map(*), $doc as element()) {
    if (exists($context?request?parameters?query) and $context?request?parameters?query != '') then
        let $docId := config:get-identifier($doc)
        let $rawQuery := $context?request?parameters?query
        (: Conversion très simple du joker "*" en équivalent regex, puis
           chaque "u"/"v" tapé devient [uv] : "victoria" et "uictoria"
           sont ainsi tous deux trouvés, quelle que soit la lettre tapée
           dans la recherche — sans toucher au texte du document ni à
           l'index, uniquement la requête est transformée ici. :)
        let $searchRegex := replace(replace($rawQuery, '\*', '\\w*'), '[uv]', '[uv]', 'i')
        let $sections := $doc//tei:div[@xml:id][
            (@type = 'verse+commentary-text') or
            (@type = ('chapter-title', 'book-introduction') and not(.//tei:div[@type = 'verse+commentary-text']))
        ]
        let $allSnippets :=
            for $div in $sections
            where matches(idx:get-searchable-text($div), $searchRegex, 'i')
            return browse:extract-snippets($div, $searchRegex, $docId, 90)
        let $total := count($allSnippets)
        return
            if ($total > 0) then
                let $shown := subsequence($allSnippets, 1, 5)
                let $rest := subsequence($allSnippets, 6)
                return
                    <div class="matches">
                        <div class="count"><pb-i18n key="browse.items" options='{{"count": {$total}}}'></pb-i18n></div>
                        {$shown}
                        {
                            if (count($rest) > 0) then
                                <details class="more-matches">
                                    <summary>Show all {$total} results</summary>
                                    {$rest}
                                </details>
                            else ()
                        }
                    </div>
            else ()
    else
        ()
};

