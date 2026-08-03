xquery version "3.1";

module namespace idx="http://teipublisher.com/index";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace dbk="http://docbook.org/ns/docbook";

declare variable $idx:app-root :=
    let $rawPath := system:get-module-load-path()
    return
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else
                substring($rawPath, 15)
        else
            $rawPath
    ;

(: --------------------------------------------------------------
   PaulCom : mise en forme des valeurs avec gestion du degré de
   certitude (@cert), pour les champs propres à ce corpus.
   -------------------------------------------------------------- :)

declare function idx:parse-person($person as element()?) {
    if (empty($person)) then
        ()
    else
        let $name :=
            if ($person/tei:forename or $person/tei:surname) then
                normalize-space($person/tei:forename || " " || $person/tei:surname)
            else
                normalize-space($person)
        return
            if ($person/@cert = ("low", "medium")) then
                "[" || $name || " ?]"
            else
                $name
};

declare function idx:parse-place-cert($place as element()?) {
    if (empty($place)) then
        ()
    else if ($place/@cert = ("low", "medium")) then
        "[" || normalize-space($place) || "?]"
    else
        normalize-space($place)
};

declare function idx:parse-date-cert($date as element()?) {
    if (empty($date)) then
        ()
    else if ($date/@cert = "low") then
        "[" || normalize-space($date) || " ?]"
    else if ($date/@cert = "medium") then
        "[" || normalize-space($date) || "]"
    else
        normalize-space($date)
};

(:~
 : Helper function called from collection.xconf to create index fields and facets.
 : This module needs to be loaded before collection.xconf starts indexing documents
 : and therefore should reside in the root of the app.
 :)
(:~
 : Reconstitue le texte "propre" d'un nœud pour l'indexation Lucene :
 : à l'intérieur de chaque <choice>, seule la forme normalisée <reg>
 : est retenue (la graphie d'origine <orig> est ignorée), pour que la
 : recherche plein texte ne porte que sur l'orthographe modernisée.
 : Plus fiable que <ignore qname="tei:orig"/> seul, qui ne semble pas
 : s'appliquer à un champ défini via expression="." explicite.
 :)
declare function idx:get-searchable-text($node as node()) as xs:string {
    string-join(
        for $child in $node/node()
        return
            typeswitch ($child)
                case element(tei:choice) return
                    if ($child/tei:reg) then
                        idx:get-searchable-text($child/tei:reg[1])
                    else
                        idx:get-searchable-text($child)
                case element(tei:orig) return ''
                case element(tei:lb) return ' '
                case element() return idx:get-searchable-text($child)
                case text() return $child/string()
                default return ''
    , '')
};

declare function idx:get-metadata($root as element(), $field as xs:string) {
    let $header := $root/tei:teiHeader
    (: PaulCom : raccourci vers le bloc bibliographique principal du
       manuscrit/imprimé, utilisé par plusieurs champs ci-dessous. :)
    let $paulcomMonogr := $header//tei:sourceDesc/tei:msDesc/tei:msContents//tei:biblStruct/tei:monogr
    return
        switch ($field)
            case "title" return
                string-join((
                    $header//tei:msDesc/tei:head, $header//tei:titleStmt/tei:title[@type = 'main'],
                    $header//tei:titleStmt/tei:title,
                    $root/dbk:info/dbk:title,
                    root($root)//article-meta/title-group/article-title,
                    root($root)//article-meta/title-group/subtitle
                ), " - ")
            case "author" return (
                $header//tei:correspDesc/tei:correspAction/tei:persName,
                $header//tei:titleStmt/tei:author,
                $root/dbk:info/dbk:author,
                root($root)//article-meta/contrib-group/contrib/name,
                (: PaulCom : auteur du commentaire :)
                idx:parse-person($paulcomMonogr/tei:author/tei:persName[1])
            )
            case "language" return
                head((
                    $header//tei:langUsage/tei:language/@ident,
                    $root/@xml:lang,
                    $header/@xml:lang,
                    root($root)/*/@xml:lang
                ))
            case "date" return head((
                (: PaulCom : date d'impression — priorité sur les chemins
                   génériques ci-dessous, qui peuvent accidentellement
                   correspondre à une date d'encodage du fichier plutôt
                   qu'à la date de l'imprimé. :)
                idx:parse-date-cert($paulcomMonogr/tei:imprint/tei:date[1]),
                $header//tei:correspDesc/tei:correspAction/tei:date/@when,
                $header//tei:sourceDesc/(tei:bibl|tei:biblFull)/tei:publicationStmt/tei:date,
                $header//tei:sourceDesc/(tei:bibl|tei:biblFull)/tei:date/@when,
                $header//tei:fileDesc/tei:editionStmt/tei:edition/tei:date,
                $header//tei:publicationStmt/tei:date
            ))
            case "genre" return (
                idx:get-genre($header),
                root($root)//dbk:info/dbk:keywordset[@role="genre"]/dbk:keyword,
                root($root)//article-meta/kwd-group[@kwd-group-type="genre"]/kwd
            )
            case "category" return
                (root($root)/tei:TEI/@n, "ZZZ")[1]
            case "feature" return (
                idx:get-classification($header, 'feature'),
                $root/dbk:info/dbk:keywordset[@role="feature"]/dbk:keyword
            )
            case "form" return (
                idx:get-classification($header, 'form'),
                $root/dbk:info/dbk:keywordset[@role="form"]/dbk:keyword,
                (: PaulCom : genre/forme déclaré directement en mot-clé,
                   sans passer par une taxonomie externe. :)
                $header//tei:profileDesc/tei:textClass/tei:keywords/tei:term[@type = "form"]
            )
            case "period" return (
                idx:get-classification($header, 'period'),
                $root/dbk:info/dbk:keywordset[@role="period"]/dbk:keyword
            )
            case "content" return (
                root($root)//body,
                $root/dbk:section
            )
            case "place" return (
                for $id in ($root//tei:placeName, $root//tei:name[@type="place"], $root//tei:rs[@type='place'])
                return
                    (if ($id/@ref) then $id/@ref/string() else (), if ($id/@key) then $id/@key/string() else $id),
                (: PaulCom : lieu d'impression :)
                idx:parse-place-cert($paulcomMonogr/tei:imprint/tei:pubPlace[1])
            )
            case "person" return
                for $id in ($root//tei:persName, $root//tei:name[@type="person"], $root//tei:rs[@type='person'])
                return
                    (if ($id/@ref) then $id/@ref/string() else (), if ($id/@key) then $id/@key/string() else $id)

            (: --------------------------------------------------------------
               Champs propres au corpus PaulCom (16th Century Exegesis of Paul)
               -------------------------------------------------------------- :)
            case "printer" return (
                idx:parse-person($paulcomMonogr/tei:imprint/tei:respStmt[tei:resp = "Imprimeur"]/tei:persName[1])
            )
            case "institution" return (
                $header//tei:sourceDesc/tei:msDesc/tei:msIdentifier/tei:institution[1]
            )
            case "provider" return (
                $header//tei:sourceDesc/tei:msDesc/tei:additional/tei:surrogates
                    /tei:bibl/tei:relatedItem[@type = "original"]/tei:ref[1]
            )
            case "transcription-quality" return (
                $header//tei:profileDesc/tei:textClass/tei:keywords/tei:term[@type = "transcription_quality"][1]
            )
            case "epistle" return (
                (: Lu directement depuis le teiHeader :
                   profileDesc/textClass/keywords/term[@type='commentary-topic'] :)
                normalize-space($header//tei:profileDesc/tei:textClass/tei:keywords/tei:term[@type = 'commentary-topic'][1])
            )

            default return
                ()
};

declare function idx:get-genre($header as element()?) {
    for $target in $header//tei:textClass/tei:catRef[@scheme="#genre"]/@target
    let $category := id(substring($target, 2), doc($idx:app-root || "/data/taxonomy.xml"))
    return
        $category/ancestor-or-self::tei:category[parent::tei:category]/tei:catDesc
};

declare function idx:get-classification($header as element()?, $scheme as xs:string) {
    for $target in $header//tei:textClass/tei:catRef[@scheme="#" || $scheme]/@target
    let $category := id(substring($target, 2), doc($idx:app-root || "/data/taxonomy.xml"))
    return
        $category/ancestor-or-self::tei:category[parent::tei:category]/tei:catDesc
};
