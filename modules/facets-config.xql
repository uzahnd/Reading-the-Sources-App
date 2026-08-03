module namespace facets-config="http://teipublisher.com/api/facets-config";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare function facets-config:get-name($id as xs:string, $type as xs:string) as xs:string {
    let $entity := collection($config:register-root)/id($id)
    return head((
            switch ($type)
                case 'place' return head(($entity//tei:placeName[@type = "main"], $entity//tei:placeName))
                case 'actor' return head(($entity//(tei:persName | tei:orgName)[@type = "main"], $entity//tei:placeName))
                default return "ERR",
             "Unresolvable entity " || $id || " of type " || $type)
        )
};
(:
 : Display configuration for facets to be shown in the sidebar. The facets themselves
 : are configured in the index configuration, collection.xconf.
 
 delete variable from default config 
 
 map {
        "dimension": "genre",
        "heading": "facets.genre",
        "max": 5,
        "hierarchical": true()
    },
    
       map {
        "dimension": "language",
        "heading": "Language",
        "max": 5,
        "hierarchical": false(),
        "output": function($label) {
            switch($label)
                case "de" return "German"
                case "es" return "Spanish"
                case "la" return "Latin"
                case "fr" return "French"
                case "en" return "English"
                default return $label
        }
    },
     map {
        "dimension": "provider",
        "heading": "Provider",
        "max": 20,
        "hierarchical": false()
    },
 
 :)
declare variable $facets-config:facets := [
    


    (: --------------------------------------------------------------
       Facettes propres au corpus PaulCom (16th Century Exegesis of Paul)
       -------------------------------------------------------------- :)
    map {
        "dimension": "author",
        "heading": "Author",
        "max": 20,
        "hierarchical": false()
    },
    map {
        "dimension": "printer",
        "heading": "Printer",
        "max": 20,
        "hierarchical": false()
    },
    map {
        "dimension": "place",
        "heading": "Publication's Places",
        "max": 20,
        "hierarchical": false()
    },
    map {
        "dimension": "date",
        "heading": "Date of Publication",
        "max": 20,
        "hierarchical": false()
    },
     map {
        "dimension": "epistle",
        "heading": "Epistle",
        "max": 20,
        "hierarchical": false(),
        (: Ordre canonique de la Vulgate (pas alphabétique) — utilisé par
           facets:sort dans facets.xql. Ajustez/retirez les livres que
           votre corpus ne couvre pas. :)
        "order": ["Rom", "1-Cor", "2-Cor", "Gal", "Eph", "Phil", "Col",
                   "1-Thess", "2-Thess", "1-Tim", "2-Tim", "Tit", "Phlm", "Hebr"]
    },
    
    map {
        "dimension": "institution",
        "heading": "Library",
        "max": 20,
        "hierarchical": false()
    },
   
    map {
        "dimension": "transcription-quality",
        "heading": "Transcription-Quality",
        "max": 20,
        "hierarchical": false()
    }
];
