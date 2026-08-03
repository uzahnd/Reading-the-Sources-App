
xquery version "3.1";

module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config";

import module namespace pm-PaulCom-web="http://www.tei-c.org/pm/models/PaulCom/web/module" at "../transform/PaulCom-web-module.xql";
import module namespace pm-PaulCom-print="http://www.tei-c.org/pm/models/PaulCom/print/module" at "../transform/PaulCom-print-module.xql";
import module namespace pm-PaulCom-epub="http://www.tei-c.org/pm/models/PaulCom/epub/module" at "../transform/PaulCom-epub-module.xql";
import module namespace pm-teipublisher-web="http://www.tei-c.org/pm/models/teipublisher/web/module" at "../transform/teipublisher-web-module.xql";
import module namespace pm-teipublisher-print="http://www.tei-c.org/pm/models/teipublisher/print/module" at "../transform/teipublisher-print-module.xql";
import module namespace pm-teipublisher-epub="http://www.tei-c.org/pm/models/teipublisher/epub/module" at "../transform/teipublisher-epub-module.xql";

declare variable $pm-config:web-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "PaulCom.odd" return pm-PaulCom-web:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-web:transform($xml, $parameters)
    default return pm-PaulCom-web:transform($xml, $parameters)
            

};
            


declare variable $pm-config:print-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "PaulCom.odd" return pm-PaulCom-print:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-print:transform($xml, $parameters)
    default return pm-PaulCom-print:transform($xml, $parameters)
            

};
            


declare variable $pm-config:epub-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "PaulCom.odd" return pm-PaulCom-epub:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-epub:transform($xml, $parameters)
    default return pm-PaulCom-epub:transform($xml, $parameters)
            

};
            


declare variable $pm-config:tei-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode tei")

};
            
    