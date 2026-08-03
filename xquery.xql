xquery version "3.1";
declare namespace tei="http://www.tei-c.org/ns/1.0";
count(collection("/db/apps/PaulCom/data/corpus")//tei:text[ft:query(., "ſuperſtitioſo")])