-- Oberflaeche des Tragwerksskripts: Warnhinweise mit ESC schliessen, Obermenue-Werte fuer neue Staebe.
-- on.paint wird mit einer Zeichen-Attrappe aufgerufen, die alle Texte sammelt.
-- Aufruf: luajit Emulator/tests/oberflaeche.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller
local STANDARD_DEHNSTARR = randDehnstarr   -- Wert ab Werk (vor jedem T.reset)
local STANDARD_DIREKT = randStarrDirekt

-- Zeichen-Attrappe: Texte und gefuellte Polygone sammeln, Textbreite 6 px je Zeichen
local texte, polygone = {}, {}
local gc = setmetatable({}, { __index = function(_, k)
    if k == 'drawString' then return function(_, text, x, y) texte[#texte + 1] = { t = tostring(text), x = x, y = y } end end
    if k == 'fillPolygon' then return function(_, pts)
        local p = {}
        for i, v in ipairs(pts) do p[i] = v end
        polygone[#polygone + 1] = p
    end end
    if k == 'getStringWidth' then return function(_, text) return #tostring(text) * 6 end end
    if k == 'getStringHeight' then return function() return 12 end end
    return function() end
end })
local function zeichne()
    texte, polygone = {}, {}
    local ok, err = pcall(on.paint, gc)
    if not ok then T.pruef(false, 'on.paint Absturz: ' .. tostring(err):gsub('\n.*', '')) end
    return texte
end
local function sichtbar(muster)
    for _, e in ipairs(zeichne()) do if e.t:find(muster, 1, true) then return true end end
    return false
end
local function sichtbarGenau(text)
    for _, e in ipairs(zeichne()) do if e.t == text then return true end end
    return false
end

-- Obermenue Seite 1 wie auf dem Rechner: Zeile waehlen, Enter, Text, Enter
local function obermenue(zeile, text)
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 1, zeile, false
    on.enterKey(); eingabeText = text; on.enterKey()
    menuOffen = false
end
local function stabZeichnen(a, b, q)
    local S = getStaebe(); S[#S + 1] = erstelleStab(a, b)
    if q then S[#S].q, S[#S].q_str = 1, q end
    setStaebe(S)
end
local function leer(K)
    T.reset()
    defEA, defEI, defEA_str, defEI_str = 1e10, 1e8, nil, nil
    menuOffen, eingabeModus = false, false
    uiZustand({ auswahl = false, warnungKinematisch = false, warnungStarrBestimmt = false, pvvPrompt = false, pvvModus = false, in_pvv_release = false })
    ansichtsModus = 'System'
    hinweisQuittiert = nil
    setKnoten(K); setStaebe({})
end
local function hinweisMit(muster)
    for _, h in ipairs(hinweisListe) do if h:find(muster, 1, true) then return true end end
    return false
end

local fall = T.fall

fall('1 Obermenue vor dem Zeichnen', function()
    T.abschnitt('EA/EI im Obermenue setzen, danach Staebe zeichnen')
    leer({ pinned(node(0)), node(2), roller(node(4)) })
    obermenue(2, 'EA'); obermenue(3, 'EI')
    stabZeichnen(1, 2, 'q'); stabZeichnen(2, 3, 'q')
    local S = getStaebe()
    for i = 1, 2 do
        T.wahr('Stab ' .. i .. ': EA_str = EA', S[i].EA_str == 'EA', S[i].EA_str)
        T.wahr('Stab ' .. i .. ': EI_str = EI', S[i].EI_str == 'EI', S[i].EI_str)
    end
    pcall(starteBerechnung)
    T.wahr('kein symbolFehler', symbolFehler == nil, symbolFehler)
end)

fall('2 Obermenue zwischendurch', function()
    T.abschnitt('Stab zeichnen, EA setzen, weiteren Stab zeichnen (fuehrte zur Warnung)')
    leer({ pinned(node(0)), node(2), roller(node(4)) })
    stabZeichnen(1, 2, 'q'); obermenue(2, 'EA'); stabZeichnen(2, 3, 'q')
    pcall(starteBerechnung)
    T.wahr('Stab 2 uebernimmt EA', getStaebe()[2].EA_str == 'EA', getStaebe()[2].EA_str)
    T.wahr('kein symbolFehler', symbolFehler == nil, symbolFehler)
end)

fall('3 Fehlerbox symbolischer Modus', function()
    T.abschnitt('Fehlerbox: umbrechen, mit ESC schliessen, Sperre bleibt')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2, 'q*x')
    pcall(starteBerechnung)
    T.wahr('symbolFehler gesetzt', symbolFehler ~= nil, symbolFehler)
    T.wahr('Box offen', symbolFehlerOffen == true)
    T.wahr('Box gezeichnet', sichtbar('Symbolischer Modus nicht moeglich'))
    on.escapeKey()
    T.wahr('ESC: Box geschlossen', symbolFehlerOffen == false and not sichtbar('Symbolischer Modus nicht moeglich'))
    T.wahr('ESC: Fehler bleibt gespeichert', symbolFehler ~= nil)
    local ok, res = pcall(exportBiegelinienNeuToTI)
    T.wahr('Rand-LGS bleibt gesperrt', ok and res == false)
    pcall(starteBerechnung)
    T.wahr('neue Berechnung zeigt die Box wieder', sichtbar('Symbolischer Modus nicht moeglich'))
    -- lange Meldung wird umgebrochen und bleibt in der Box
    symbolFehler = 'Symbol EA kommt vor, aber Stab 12 hat EA als Zahl. EA fuer alle Staebe symbolisch setzen.'
    symbolFehlerOffen = true
    local b = platform.window:width()
    local boxW = math.min(b - 20, 300); local boxX = math.floor((b - boxW) / 2)
    local zeilen, drin = 0, true
    for _, e in ipairs(zeichne()) do
        if e.t ~= '[Esc]' and e.x == boxX + 8 and e.t ~= 'Symbolischer Modus nicht moeglich:' then
            zeilen = zeilen + 1
            if e.x + #e.t * 6 > boxX + boxW then drin = false end
        end
    end
    T.wahr('lange Meldung auf mehrere Zeilen umgebrochen', zeilen >= 2, zeilen)
    T.wahr('alle Zeilen innerhalb der Box', drin)
    on.escapeKey()
end)

fall('4 Kinematisch und Starrmodus', function()
    T.abschnitt('Warnungen kinematisch / Starrmodus: ESC schliesst, Auswahl bleibt')
    leer({ roller(node(0)), roller(node(2)) })
    stabZeichnen(1, 2)
    getKnoten()[2].last_x = 1
    pcall(starteBerechnung)
    T.wahr('System als kinematisch erkannt', uiZustand().warnungKinematisch == true)
    T.wahr('Warnung gezeichnet', sichtbar('System ist kinematisch!'))
    uiZustand({ auswahl = 1 })
    on.escapeKey()
    T.wahr('ESC: Warnung weg', uiZustand().warnungKinematisch == false and not sichtbar('System ist kinematisch!'))
    T.wahr('ESC schliesst nur die Warnung (Auswahl bleibt)', uiZustand().auswahl == 1)
    on.escapeKey()
    T.wahr('zweites ESC hebt die Auswahl auf', uiZustand().auswahl == nil)
    uiZustand({ warnungStarrBestimmt = true })
    T.wahr('Starrmodus-Warnung gezeichnet', sichtbar('Starrmodus & statisch unbestimmt!'))
    on.escapeKey()
    T.wahr('ESC: Starrmodus-Warnung weg', uiZustand().warnungStarrBestimmt == false and not sichtbar('Starrmodus'))
end)

fall('5 Menue ueber Warnung', function()
    T.abschnitt('Menue offen und Warnung: erst Menue, dann Warnung')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2)
    uiZustand({ warnungKinematisch = true }); menuOffen, menuTyp, menuSeite, menuZeile = true, 'obermenue', 1, 1
    on.escapeKey()
    T.wahr('1. ESC schliesst das Menue', menuOffen == false and uiZustand().warnungKinematisch == true)
    on.escapeKey()
    T.wahr('2. ESC schliesst die Warnung', uiZustand().warnungKinematisch == false)
end)

fall('6 Stabmenue starr', function()
    T.abschnitt('Stabmenue: biegesteif/dehnsteif schalten, EI/EA gesperrt, eigenes EA')
    T.wahr('Standard-EA dehnstarr ist ab Werk aus', STANDARD_DEHNSTARR == false)
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2)
    local s = getStaebe()[1]
    local function stabmenue(zeile) menuOffen, menuTyp, menuIndex, menuSeite, menuZeile, eingabeModus = true, 'stab', 1, 1, zeile, false end
    stabmenue(2); on.enterKey()
    T.wahr('Zeile 2 schaltet biegesteif ein', s.biegesteif == true and eingabeModus == false)
    T.wahr('Menue: EI zeigt "starr"', sichtbarGenau('starr'))
    stabmenue(1); on.enterKey()
    T.wahr('EI-Eingabe gesperrt', eingabeModus == false)
    stabmenue(4); on.enterKey()
    T.wahr('Zeile 4 schaltet dehnsteif ein', s.dehnsteif == true)
    stabmenue(3); on.enterKey()
    T.wahr('EA-Eingabe gesperrt', eingabeModus == false)
    stabmenue(4); on.enterKey(); stabmenue(2); on.enterKey()
    T.wahr('beide wieder aus', not s.biegesteif and not s.dehnsteif)
    T.wahr('Menue: EI wieder als Wert', not sichtbarGenau('starr'))
    stabmenue(3); on.enterKey(); eingabeText = '5e9'; on.enterKey()
    T.wahr('eigenes EA gesetzt und als manuell markiert', s.EA == 5e9 and s.EA_manuell == true, tostring(s.EA))
    stabmenue(5); on.enterKey(); eingabeText = '2'; on.enterKey()
    T.wahr('Zeile 5 = Last q', s.q_str == '2', s.q_str)
    stabmenue(6); on.enterKey(); eingabeText = '3'; on.enterKey()
    T.wahr('Zeile 6 = Last n', s.n_str == '3', s.n_str)
    stabmenue(7); on.enterKey(); eingabeText = '4'; on.enterKey()
    T.wahr('Zeile 7 = Momentenlast m', s.m_str == '4', s.m_str)
    -- Standard-EA dehnstarr: eigener Wert ausgenommen; "Alle EA setzen" macht ihn wieder zum Standard
    randDehnstarr = true
    T.wahr('Stab mit eigenem EA nicht dehnsteif', stabDehnsteif(s) == false)
    stabmenue(4)
    T.wahr('Menue: dehnsteif "Nein"', sichtbarGenau('Nein'))
    obermenue(2, '1e10')
    T.wahr('Alle EA setzen: wieder Standard und dehnsteif', s.EA_manuell == nil and stabDehnsteif(s) == true)
    stabmenue(4)
    T.wahr('Menue: dehnsteif "Ja (Std.)"', sichtbarGenau('Ja (Std.)'))
    randDehnstarr = false
    menuOffen = false
end)

fall('7 Temperatur im Stabmenue', function()
    T.abschnitt('Stabmenue Seite 3: Temperatur als Text eingeben und anzeigen')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2)
    local s = getStaebe()[1]
    local function eingabe(zeile, text)
        menuOffen, menuTyp, menuIndex, menuSeite, menuZeile, eingabeModus = true, 'stab', 1, 3, zeile, false
        on.enterKey(); eingabeText = text; on.enterKey()
    end
    eingabe(5, 'dt'); eingabe(6, 'dt'); eingabe(7, 'a'); eingabe(8, 'h')
    T.wahr('Texte gespeichert', s.To_str == 'dt' and s.Tu_str == 'dt' and s.alpha_str == 'a' and s.h_str == 'h',
        tostring(s.To_str) .. ',' .. tostring(s.Tu_str) .. ',' .. tostring(s.alpha_str) .. ',' .. tostring(s.h_str))
    menuOffen, menuSeite = true, 3
    T.wahr('Menue zeigt "dt" statt 1', sichtbarGenau('dt'))
    T.wahr('Menue zeigt "a" und "h"', sichtbarGenau('a') and sichtbarGenau('h'))
    menuOffen = false
    pcall(starteBerechnung)
    T.wahr('symbolischer Modus ohne Fehler', symbolischer_modus == true and symbolFehler == nil, symbolFehler)
    T.wahr('Temperatur-Hinweis gezeichnet', sichtbar('Temperatur symbolisch'))
    on.escapeKey()
    T.wahr('ESC schliesst den Temperatur-Hinweis', not sichtbar('Temperatur symbolisch'))
end)

fall('8 Hinweise', function()
    T.abschnitt('Hinweisbox: Zahl-EI/EA neben symbolischen Steifigkeiten, h = 0, ESC')
    -- Klausur Aufgabe 4 ohne Gelenke: EI der senkrechten Staebe ist eine Zahl
    local function klausur4(gelenke)
        leer({ node(0, 0), node(2, 0), pinned(node(4, 0)), node(6, 0), pinned(node(6, -1)), pinned(node(6, 4)), node(10, 0) })
        local K = getKnoten()
        K[1].cm, K[1].cm_str = 3, '3*EA*l'
        K[2].last_y, K[2].last_y_str = 1, 'F'
        K[7].last_y, K[7].last_y_str = -1, '-F'
        if gelenke then K[5].gelenk, K[6].gelenk = true, true end
        local S = {}
        for i, p in ipairs({ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 7 } }) do
            S[i] = erstelleStab(p[1], p[2]); S[i].biegesteif, S[i].dehnsteif = true, true
        end
        S[5] = erstelleStab(5, 4); S[5].EA, S[5].EA_str = 1, 'EA'
        S[6] = erstelleStab(4, 6); S[6].EA, S[6].EA_str = 2, '2*EA'
        if gelenke then S[5].gelenk_A, S[5].gelenk_B, S[6].gelenk_A, S[6].gelenk_B = true, true, true, true end
        setStaebe(S)
        pcall(starteBerechnung)
    end
    klausur4(false)
    T.wahr('ohne Gelenke: Hinweis EI Zahl fuer Stab 5, 6', hinweisMit('Stab 5, 6 wird auf Biegung belastet'), table.concat(hinweisListe, ' | '))
    T.wahr('Hinweisbox gezeichnet', sichtbarGenau('Hinweis:'))
    on.escapeKey()
    T.wahr('ESC schliesst die Hinweisbox', hinweisOffen == false and not sichtbarGenau('Hinweis:'))
    zeichne()   -- Zeichnen darf den Fingerabdruck nicht veraendern
    pcall(starteBerechnung)
    T.wahr('gleiches System neu gerechnet: Box bleibt zu', hinweisOffen == false)
    getStaebe()[5].EA_str = '3*EA'   -- andere Dehnsteifigkeit, aber weiter keine Gelenke
    pcall(starteBerechnung)
    T.wahr('System geaendert (EA Stab 5): Hinweis wieder offen', hinweisOffen == true and hinweisMit('Stab 5, 6 wird auf Biegung belastet'))
    on.escapeKey()
    getKnoten()[2].last_y_str = '2*F'   -- auch eine Laststaenderung zaehlt als Aenderung
    pcall(starteBerechnung)
    T.wahr('Last geaendert: Hinweis wieder offen', hinweisOffen == true)
    klausur4(true)
    T.wahr('mit Gelenken: kein EI-Hinweis', not hinweisMit('EI ist dort eine Zahl'), table.concat(hinweisListe, ' | '))
    -- Aufgabe 4 wie in der Klausur eingegeben: Platte starr, Staebe 5 und 6 an der Platte gelenkig,
    -- unten bzw. oben eingespannt, EA als Zahl. Die Staebe werden nicht gebogen, ein symbolisches EI
    -- (Obermenue fuer alle Staebe oder nur Stab 5) wirkt also nicht mit: kein Hinweis.
    local function klausur4eingespannt(eiStab5, eiStab6)
        leer({ pinned(node(0, 0)), node(2.5, 0), node(5, 0), node(7.5, 0), node(10, 0), fixed(node(5, 2)), fixed(node(10, -5)) })
        local K = getKnoten()
        K[2].last_y, K[2].last_y_str = 1, 'F'
        K[4].last_y, K[4].last_y_str = 1, 'F'
        local S = {}
        for i = 1, 4 do S[i] = erstelleStab(i, i + 1); S[i].biegesteif, S[i].dehnsteif = true, true end
        S[5] = erstelleStab(6, 3); S[5].EA, S[5].EA_str, S[5].gelenk_B = 4e6, '4000000', true
        S[5].To, S[5].Tu, S[5].To_str, S[5].Tu_str, S[5].alpha, S[5].alpha_str = 1, 1, 'dt', 'dt', 1.2e-5, '0.000012'
        S[6] = erstelleStab(5, 7); S[6].EA, S[6].EA_str, S[6].gelenk_A = 8e5, '800000', true
        if eiStab5 then S[5].EI, S[5].EI_str = 1, eiStab5 end
        if eiStab6 then S[6].EI, S[6].EI_str = 1, eiStab6 end
        setStaebe(S)
        pcall(starteBerechnung)
    end
    klausur4eingespannt('EI', 'EI')
    T.wahr('Aufgabe 4, EI symbolisch, Staebe ungebogen: kein Steifigkeits-Hinweis',
        not hinweisMit('ist dort eine Zahl'), table.concat(hinweisListe, ' | '))
    klausur4eingespannt('EI', nil)
    T.wahr('Aufgabe 4, nur Stab 5 mit EI symbolisch: kein Steifigkeits-Hinweis',
        not hinweisMit('ist dort eine Zahl'), table.concat(hinweisListe, ' | '))
    -- Zweigelenkrahmen mit EI symbolisch, EA Zahl: Hinweis EA, mit Standard-EA dehnstarr keiner
    local function portal(dehnstarr)
        leer({ pinned(node(0, 1)), node(0, 0), node(1, 0), pinned(node(1, 1)) })
        randDehnstarr = dehnstarr or false
        local K = getKnoten(); K[2].last_x, K[2].last_x_str = 1, 'H'
        local S = {}
        for i = 1, 3 do S[i] = erstelleStab(i, i + 1); S[i].EI, S[i].EI_str = 1, 'EI' end
        setStaebe(S)
        pcall(starteBerechnung)
    end
    portal()
    T.wahr('Rahmen: Hinweis EA Zahl', hinweisMit('EA ist dort eine Zahl'), table.concat(hinweisListe, ' | '))
    portal(true)
    T.wahr('Rahmen mit Standard-EA dehnstarr: kein Hinweis', #hinweisListe == 0, table.concat(hinweisListe, ' | '))
    randDehnstarr = false
    -- Einfeldtraeger mit q und EI symbolisch: N = 0, EA spielt keine Rolle -> kein Hinweis
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2, 'q'); getStaebe()[1].EI_str = 'EI'
    pcall(starteBerechnung)
    T.wahr('Einfeldtraeger: kein Hinweis', #hinweisListe == 0 and not hinweisOffen, table.concat(hinweisListe, ' | '))
    -- Temperatur oben 10, unten 0, h = 0: nur mittlere Erwaermung
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2)
    local s = getStaebe()[1]; s.To, s.Tu, s.h = 10, 0, 0
    pcall(starteBerechnung)
    T.wahr('h = 0 und To ~= Tu: Hinweis', hinweisMit('aber h = 0'), table.concat(hinweisListe, ' | '))
    s.Tu = 10
    pcall(starteBerechnung)
    T.wahr('To = Tu: kein Hinweis', not hinweisMit('aber h = 0'))
end)

fall('9 Schalter Methode', function()
    T.abschnitt('Obermenue Seite 4: Methode fuer starre Staebe')
    T.wahr('ab Werk: direkt', STANDARD_DIREKT == true)
    leer({ pinned(node(0)), roller(node(2)) })
    randStarrDirekt = true
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 4, false
    T.wahr('Menue zeigt "direkt"', sichtbarGenau('direkt'))
    on.enterKey()
    T.wahr('Enter schaltet auf Grenzwert', randStarrDirekt == false and sichtbarGenau('Grenzwert'))
    on.enterKey()
    T.wahr('nochmal Enter: wieder direkt', randStarrDirekt == true)
    menuOffen = false
end)

fall('10 Exportmeldungen', function()
    T.abschnitt('Exporte melden sich sichtbar (frueher nur Konsole bzw. Disp)')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2, '1')
    -- Export ohne Berechnung
    exportVerschiebungenToTI()
    T.wahr('Meldung "zuerst berechnen"', meldungText ~= nil and meldungText:find('berechnen', 1, true) ~= nil, meldungText)
    T.wahr('Box gezeichnet', sichtbarGenau('Export fehlgeschlagen:'))
    on.escapeKey()
    T.wahr('ESC schliesst die Meldung', meldungText == nil and not sichtbarGenau('Export fehlgeschlagen:'))
    -- erfolgreicher Rand-LGS-Export
    pcall(starteBerechnung)
    T.wahr('Berechnung raeumt die Meldung weg', meldungText == nil)
    exportBiegelinienNeuToTI()
    T.wahr('Rand-LGS meldet den Export', meldungText ~= nil and meldungText:find('Rand-LGS:', 1, true) ~= nil, meldungText)
    T.wahr('Box mit Titel Export', sichtbarGenau('Export:'))
    on.escapeKey()
    -- fehlgeschlagener Rand-LGS-Export (keine Staebe)
    leer({ pinned(node(0)), roller(node(2)) })
    exportBiegelinienNeuToTI()
    T.wahr('Rand-LGS meldet den Fehlschlag', meldungText ~= nil and meldungText:find('Keine Staebe', 1, true) ~= nil, meldungText)
    on.escapeKey()
end)

fall('11 Loeschabfrage', function()
    T.abschnitt('Alles loeschen fragt nach: Esc bricht ab, Enter loescht')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2, 'q')
    on.clearKey()
    T.wahr('Frage steht', loeschFrage == true)
    T.wahr('Frage wird gezeichnet', sichtbar('Wirklich alles loeschen?'))
    T.wahr('Enter/Esc stehen dabei', sichtbar('[Enter] loeschen'))
    on.escapeKey()
    T.wahr('Esc bricht ab', loeschFrage == false)
    T.wahr('System ist noch da', #getKnoten() == 2 and #getStaebe() == 1)
    T.wahr('Frage verschwindet', not sichtbar('Wirklich alles loeschen?'))
    on.clearKey()
    on.enterKey()
    T.wahr('Enter loescht alles', #getKnoten() == 0 and #getStaebe() == 0)
    T.wahr('keine Frage mehr offen', loeschFrage == false)
    -- leeres System: keine Rueckfrage noetig
    on.clearKey()
    T.wahr('leeres System fragt nicht', loeschFrage == false)
end)

fall('12 Menues links', function()
    T.abschnitt('Obermenue, Knoten- und Stabmenue stehen am linken Rand')
    leer({ pinned(node(0)), roller(node(2)) })
    stabZeichnen(1, 2, 'q')
    local breite = platform.window:width()
    local function menuX(muster)
        local x
        for _, e in ipairs(zeichne()) do
            if e.t:find(muster, 1, true) and (x == nil or e.x < x) then x = e.x end
        end
        return x
    end
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 1, 1, false
    local x1 = menuX('Raster')
    T.wahr('Obermenue links', x1 ~= nil and x1 < breite / 2, tostring(x1))
    menuOffen, menuTyp, menuIndex, menuSeite, menuZeile = true, 'knoten', 1, 1, 1
    local x2 = menuX('Knoten 1')
    T.wahr('Knotenmenue links', x2 ~= nil and x2 < breite / 2, tostring(x2))
    menuOffen, menuTyp, menuIndex, menuSeite, menuZeile = true, 'stab', 1, 1, 1
    local x3 = menuX('Stab 1')
    T.wahr('Stabmenue links', x3 ~= nil and x3 < breite / 2, tostring(x3))
    menuOffen = false
end)

fall('13 Resultierende im E-Modus', function()
    T.abschnitt('E-Seite: Streckenlasten treten als Resultierende R auf, Lage in der Bemassung')

    -- alle gezeichneten Texte einsammeln
    local function texteJetzt() return zeichne() end
    local function rWert()
        for _, e in ipairs(texteJetzt()) do
            local v = e.t:match('^R = (.*)$')
            if v then return v end
        end
    end
    -- Beschriftungen koennen exakte Brueche sein (z. B. 64/3)
    local function zahlAus(t)
        if not t then return nil end
        local a, b = t:match('^(-?%d+)/(%d+)$')
        if a then return tonumber(a) / tonumber(b) end
        return tonumber(t)
    end
    local function textDa(t)
        for _, e in ipairs(texteJetzt()) do if e.t == t then return true end end
        return false
    end

    -- Balken 0..4 m mit Gleichlast q = 2
    leer({ pinned(node(0)), roller(node(4)) })
    setStaebe({ T.bar(1, 2, { q = 2, q_str = '2' }) })
    pcall(starteBerechnung)

    ansichtsModus = 'System'
    T.wahr('Systemansicht zeigt die Streckenlast selbst', rWert() == nil, rWert())

    ansichtsModus = 'E'; explosionPage = 1
    local r = rWert()
    T.wahr('E-Seite beschriftet die Resultierende mit R', r ~= nil, r)
    T.wahr('R = q*L = 8', r ~= nil and zahlAus(r) ~= nil and math.abs(zahlAus(r) - 8) < 1e-6, r)
    T.wahr('Lage 2 m steht in der Bemassung', textDa('2'))

    explosionPage = 2
    T.wahr('auch auf Seite 2 der E-Ansicht', rWert() ~= nil, rWert())

    -- Dreieckslast: Resultierende liegt bei 2/3 der Laenge
    explosionPage = 1
    setStaebe({ T.bar(1, 2, { q = 0, q_str = '0', q_A = 0, q_B = 3 }) })
    pcall(starteBerechnung)
    ansichtsModus = 'E'
    local r2 = rWert()
    T.wahr('Dreieckslast: R = 6', r2 ~= nil and zahlAus(r2) ~= nil and math.abs(zahlAus(r2) - 6) < 1e-6, r2)
    T.wahr('Schwerpunkt 2.67 m bemasst', textDa('2.67'), '')
    T.wahr('Restmass 1.33 m bemasst', textDa('1.33'), '')

    -- globale Linienlast gy
    setStaebe({ T.bar(1, 2, { gy = 2, gy_str = '2' }) })
    pcall(starteBerechnung)
    ansichtsModus = 'E'
    local r3 = rWert()
    T.wahr('globale Linienlast: R = 8', r3 ~= nil and zahlAus(r3) ~= nil and math.abs(zahlAus(r3) - 8) < 1e-6, r3)

    -- CAS-Last q = x ueber 4 m: R = 8, Schwerpunkt bei 2.67 m
    setStaebe({ T.bar(1, 2, { q_str = 'x' }) })
    pcall(starteBerechnung)
    ansichtsModus = 'E'
    local r4 = rWert()
    T.wahr('CAS-Last: R = 8', r4 ~= nil and zahlAus(r4) ~= nil and math.abs(zahlAus(r4) - 8) < 1e-4, r4)
    T.wahr('CAS-Last: Schwerpunkt 2.67 m', textDa('2.67'), '')

    -- quadratische CAS-Last q = x^2 ueber 4 m: R = 64/3, Schwerpunkt bei 3 m (Simpson ist exakt)
    setStaebe({ T.bar(1, 2, { q_str = 'x^2' }) })
    pcall(starteBerechnung)
    ansichtsModus = 'E'
    local r5 = rWert()
    T.wahr('quadratische Last: R = 21.33', r5 ~= nil and zahlAus(r5) ~= nil and math.abs(zahlAus(r5) - 64/3) < 1e-3, r5)
    T.wahr('quadratische Last: Schwerpunkt 3 m', textDa('3'), '')

    -- Streckenmoment: eine Resultierende M statt vieler Momentsymbole
    setStaebe({ T.bar(1, 2, { m = 1.5, m_str = '1.5' }) })
    pcall(starteBerechnung)
    ansichtsModus = 'E'
    local mm
    for _, e in ipairs(texteJetzt()) do
        local v = e.t:match('^M = (.*)$')
        if v and zahlAus(v) then mm = zahlAus(v) end
    end
    T.wahr('Streckenmoment: M = m*L = 6', mm ~= nil and math.abs(mm - 6) < 1e-6, mm)

    ansichtsModus = 'System'; explosionPage = 1
end)

fall('14 Pfeilspitzen der Streckenlasten', function()
    T.abschnitt('Lastflaechen bekommen groessere Spitzen, andere Pfeile bleiben wie sie sind')
    local k2 = roller(node(4)); k2.last_y, k2.last_y_str = 5, '5'
    leer({ pinned(node(0)), k2 })
    setStaebe({ T.bar(1, 2, { q = 2, q_str = '2' }) })
    pcall(starteBerechnung)
    ansichtsModus = 'System'
    zeichne()

    -- Spitzenlaenge eines Dreiecks: Abstand der Spitze zur Mitte der Grundseite
    local gross, normal = 0, 0
    for _, p in ipairs(polygone) do
        if #p == 6 then
            local mx, my = (p[3] + p[5]) / 2, (p[4] + p[6]) / 2
            local hl = math.sqrt((p[1] - mx) ^ 2 + (p[2] - my) ^ 2)
            if math.abs(hl - 6 * 1.4) < 0.5 then gross = gross + 1
            elseif math.abs(hl - 6) < 0.5 then normal = normal + 1 end
        end
    end
    T.wahr('Streckenlast zeichnet groessere Spitzen', gross >= 8, gross)
    T.wahr('Einzellast behaelt die normale Spitze', normal >= 1, normal)
end)

fall('15 Lagerwinkel ueber das Knotenmenue', function()
    T.abschnitt('Knotenmenue Seite 2, Zeile 5 (Lager-Winkel) mit den Pfeiltasten erreichbar')
    leer({ pinned(node(0)), roller(node(4)) })
    setStaebe({ T.bar(1, 2) })
    menuOffen, menuTyp, menuIndex, menuSeite, menuZeile, eingabeModus = true, 'knoten', 2, 2, 1, false
    for _ = 1, 6 do on.arrowKey('down') end
    T.zahl('unterste Zeile ist 5', menuZeile, 5, 0)
    on.enterKey(); eingabeText = '30'; on.enterKey()
    T.zahl('Lagerwinkel gesetzt', getKnoten()[2].winkel, 30, 0)
    menuOffen = false
end)

fall('16 Nur Laengslinien exportiert nur die Laengslinien', function()
    T.abschnitt('Obermenue Seite 2, Zeile 3: u_EA_stab, keine v_EI_stab')
    local k2 = roller(node(4)); k2.last_y = 5
    leer({ pinned(node(0)), k2 })
    setStaebe({ T.bar(1, 2, { n = 1, n_str = '1' }) })
    pcall(starteBerechnung)
    pcall(math.eval, 'DelVar v_EI_stab1,u_EA_stab1')
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 2, 3, false
    on.enterKey()
    menuOffen = false
    T.wahr('u_EA_stab1 exportiert', T.evs('u_EA_stab1(1)') ~= 'u_ea_stab1(1)', T.evs('u_EA_stab1(1)'))
    local v = tostring(T.evs('v_EI_stab1(1)'))
    T.wahr('v_EI_stab1 nicht exportiert (bleibt Symbol)', v:lower():find('v_ei_stab1', 1, true) ~= nil, v)
    meldungText = nil
end)

fall('17 Taste f tauscht nur Start- und Endknoten', function()
    T.abschnitt('f: k1 und k2 tauschen, alle anderen Stabwerte bleiben; System muss neu gerechnet werden')
    leer({ pinned(node(0)), roller(node(4)) })
    setStaebe({ T.bar(1, 2, { q_A = 1, q_B = 3, n_A = 2, n_B = 4, gelenk_A = true, To = 5, q_str = 'x' }) })
    pcall(starteBerechnung)
    T.wahr('vorher berechnet', systemBerechnet)
    uiZustand({ auswahl = false })
    setHover('stab', 1)
    on.charIn('f')
    local s = getStaebe()[1]
    T.wahr('Knoten getauscht', s.k1 == 2 and s.k2 == 1, s.k1 .. ',' .. s.k2)
    T.wahr('Trapezwerte unveraendert', s.q_A == 1 and s.q_B == 3 and s.n_A == 2 and s.n_B == 4)
    T.wahr('Gelenk, Temperatur, Lastfunktion unveraendert', s.gelenk_A and not s.gelenk_B and s.To == 5 and s.q_str == 'x')
    T.wahr('System als geaendert markiert', not systemBerechnet)
end)

fall('18 Fachwerk: Abzaehlformel beim Hovern ueber n', function()
    T.abschnitt('Fachwerkmodus: n = s + r - 2k statt n = r + z - 3p')
    -- Dreieck aus drei Staeben auf Fest- und Loslager: s = 3, r = 3, k = 3 -> n = 0
    local K = { pinned(node(0)), roller(node(4)), node(2, -2) }
    for _, k in ipairs(K) do k.gelenk = true end
    leer(K)
    setStaebe({ T.bar(1, 2), T.bar(2, 3), T.bar(3, 1) })
    fachwerkModus = true
    pcall(starteBerechnung)
    setMaus(310, 8)
    local texte = zeichne()
    local hat = false
    for _, e in ipairs(texte) do if e.t:find('n=s+r-2k: 3+3-6=0', 1, true) then hat = true end end
    T.wahr('Tooltip zeigt n=s+r-2k', hat)
    fachwerkModus = false
    setMaus(0, 0)
end)

fall('19 Lange Hinweisbox scrollt mit hoch/runter', function()
    T.abschnitt('gelbe Box laenger als der Bildschirm: Ausschnitt, Zeilenzaehler, Pfeiltasten')
    leer({ pinned(node(0)), roller(node(4)) })
    local lang = {}
    for i = 1, 12 do lang[i] = 'Hinweis' .. i .. ' ' .. string.rep('Wort ', 15) .. 'Ende' .. i end
    meldungText, hinweisListe, hinweisOffen = nil, lang, true
    zeichne()
    T.wahr('Box ist scrollbar', hinweisBoxScrollbar and hinweisScrollMax > 0, hinweisScrollMax)
    T.wahr('oben: erster Hinweis sichtbar, letzter nicht', sichtbar('Hinweis1 ') and not sichtbar('Ende12'))
    local zaehler = false
    for _, e in ipairs(zeichne()) do if e.t:match('^1%-%d+/%d+$') then zaehler = true end end
    T.wahr('Zeilenzaehler 1-x/n neben [Esc]', zaehler)
    T.wahr('nur der Pfeil nach unten', #polygone == 1 and polygone[1][6] > polygone[1][2], #polygone)
    on.arrowKey('down')
    T.zahl('Pfeil runter: eine Zeile weiter', hinweisScroll, 1)
    on.arrowKey('up'); on.arrowKey('up')
    T.zahl('Pfeil hoch: nicht ueber den Anfang hinaus', hinweisScroll, 0)
    for _ = 1, 200 do on.arrowKey('down') end
    zeichne()
    T.zahl('Pfeil runter: nicht ueber das Ende hinaus', hinweisScroll, hinweisScrollMax)
    T.wahr('unten: letzter Hinweis sichtbar, erster nicht', sichtbar('Ende12') and not sichtbar('Hinweis1 '))
    T.wahr('nur der Pfeil nach oben', #polygone == 1 and polygone[1][6] < polygone[1][2], #polygone)
    -- neuer Inhalt beginnt wieder oben
    hinweisListe = { 'kurz' }
    zeichne()
    T.wahr('kurzer Hinweis: nicht scrollbar, wieder oben', not hinweisBoxScrollbar and hinweisScroll == 0)
    on.arrowKey('down')
    T.zahl('kurzer Hinweis: Pfeil aendert nichts', hinweisScroll, 0)
    on.escapeKey()
    zeichne()
    T.wahr('nach ESC keine scrollbare Box mehr', not hinweisBoxScrollbar and not hinweisOffen)
end)

fall('20 Rasterpunkte: keine, normal, dick', function()
    T.abschnitt('Obermenue Seite 3, Zeile 9 schaltet die Rasterpunkte Normal -> Dick -> Keine -> Normal')
    leer({ pinned(node(0)), roller(node(4)) })
    -- Rasterpunkte zaehlen: kleine graue Quadrate (1x1 bzw. 2x2)
    local function punkte()
        local n1, n2, grau = 0, 0, false
        local g = setmetatable({}, { __index = function(_, k)
            if k == 'setColorRGB' then return function(_, r, gg, b) grau = (r == 180 and gg == 180 and b == 180) end end
            if k == 'fillRect' then return function(_, _, _, w, h)
                if grau and w == 1 and h == 1 then n1 = n1 + 1 elseif grau and w == 2 and h == 2 then n2 = n2 + 1 end
            end end
            if k == 'getStringWidth' then return function(_, t) return #tostring(t) * 6 end end
            if k == 'getStringHeight' then return function() return 12 end end
            return function() end
        end })
        local ok, err = pcall(on.paint, g)
        if not ok then T.pruef(false, 'on.paint Absturz: ' .. tostring(err)) end
        return n1, n2
    end
    T.zahl('ab Werk: Normal', rasterPunkte, 1)
    local n1, n2 = punkte()
    T.wahr('Normal: 1-px-Punkte, keine dicken', n1 > 50 and n2 == 0, n1 .. '/' .. n2)
    -- per Pfeiltaste bis Zeile 9 und Enter, wie auf dem Rechner
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 3, 8, false
    on.arrowKey('down')
    T.zahl('Zeile 9 erreichbar', menuZeile, 9)
    T.wahr('Menue zeigt "Rasterpunkte:" und "Normal"', sichtbarGenau('Rasterpunkte:') and sichtbarGenau('Normal'))
    on.enterKey()
    T.zahl('Enter: Dick', rasterPunkte, 2)
    T.wahr('Menue zeigt "Dick"', sichtbarGenau('Dick'))
    menuOffen = false
    local d1, d2 = punkte()
    T.wahr('Dick: gleich viele Punkte, alle 2 px', d1 == 0 and d2 == n1, d1 .. '/' .. d2)
    menuOffen = true; on.enterKey(); menuOffen = false
    T.zahl('Enter: Keine', rasterPunkte, 0)
    local k1, k2 = punkte()
    T.wahr('Keine: keine Rasterpunkte', k1 == 0 and k2 == 0, k1 .. '/' .. k2)
    menuOffen = true; on.enterKey(); menuOffen = false
    T.zahl('Enter: wieder Normal', rasterPunkte, 1)
end)

fall('21 Biegelinie bei sehr kleinen Verformungen', function()
    T.abschnitt('Kragarm mit w_max = 0,02 mm: Linie ohne flaches Stueck am Anfang (frueher Schwelle 0,01 mm)')
    local K = { fixed(node(0)), node(4) }
    K[2].last_y = 1
    leer(K)
    setStaebe({ T.bar(1, 2, { EI = 1e6, EA = 1e10 }) })
    pcall(starteBerechnung)
    ansichtsModus = 'W'
    local linien = {}
    local g = setmetatable({}, { __index = function(_, k)
        if k == 'drawPolyLine' then return function(_, pts) linien[#linien + 1] = pts end end
        if k == 'getStringWidth' then return function(_, t) return #tostring(t) * 6 end end
        if k == 'getStringHeight' then return function() return 12 end end
        return function() end
    end })
    local ok, err = pcall(on.paint, g)
    T.wahr('on.paint ohne Absturz', ok, err)
    -- die Biegelinie ist der Linienzug mit ptsBiegelinie + 1 Punkten
    local linie
    for _, l in ipairs(linien) do if #l == 2 * (ptsBiegelinie + 1) then linie = l end end
    T.wahr('Biegelinie gezeichnet', linie ~= nil)
    if linie then
        local steigt = true
        for j = 2, ptsBiegelinie + 1 do
            if not (linie[2 * j] > linie[2 * (j - 1)]) then steigt = false end
        end
        T.wahr('jeder Punkt liegt tiefer als der vorige (kein flaches Stueck)', steigt)
        T.wahr('Ende deutlich ausgelenkt', linie[#linie] - linie[2] > 5, linie[#linie] - linie[2])
    end
    ansichtsModus = 'System'
end)

fall('22 Variablen des Skripts loeschen', function()
    T.abschnitt('Obermenue Seite 4, Zeile 7: Exporte weg, system<Nr> und eigene Variablen bleiben')
    local K = { fixed(node(0)), node(4) }
    K[2].last_y = 1
    leer(K)
    setStaebe({ T.bar(1, 2) })
    pcall(starteBerechnung)
    T.randLGS()
    math.eval('system3:=7')                   -- gespeichertes System (hier nur ein Platzhalterwert)
    -- undefinierte Funktion: der Emulator zeigt sie als name*x bzw. name(x)
    local function weg(name) local v = T.evs(name .. '(x)'); return v == name .. '*x' or v == name .. '(x)' end
    math.eval('meinevar:=5')                  -- eigene Variable
    math.eval('wneu45(x):=x')                 -- Rest eines groesseren Systems, nur ueber var.list zu finden
    local altList = var.list
    var.list = function() return { 'wneu1', 'wneu45', 'system3', 'meinevar' } end
    T.wahr('vorher: wneu1 und randbed definiert', not weg('wneu1') and T.evs('randbed'):find('w1', 1, true) ~= nil)
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 6, false
    on.arrowKey('down')
    T.zahl('Zeile 7 erreichbar', menuZeile, 7)
    T.wahr('Menue zeigt "Variablen loeschen:" und "Loeschen"', sichtbarGenau('Variablen loeschen:') and sichtbarGenau('Loeschen'))
    on.enterKey()
    T.wahr('erstes Enter fragt nur nach', varLoeschFrage and menuOffen and sichtbarGenau('Sicher? Enter'))
    T.wahr('nach dem ersten Enter ist noch nichts geloescht', not weg('wneu1'))
    on.arrowKey('up'); on.arrowKey('down')
    T.wahr('Pfeiltaste: Nachfrage verfaellt', not varLoeschFrage)
    on.enterKey(); on.enterKey()
    T.wahr('zweites Enter: Menue zu, Meldung', not menuOffen and meldungText ~= nil and meldungText:find('system<Nr>', 1, true) ~= nil, meldungText)
    T.wahr('wneu1 geloescht', weg('wneu1'), T.evs('wneu1(x)'))
    T.wahr('randbed geloescht', T.evs('randbed') == 'randbed', T.evs('randbed'))
    T.wahr('wneu45 (ueber var.list) geloescht', weg('wneu45'), T.evs('wneu45(x)'))
    T.wahr('system3 bleibt', T.evs('system3') == '7', T.evs('system3'))
    T.wahr('eigene Variable bleibt', T.evs('meinevar') == '5', T.evs('meinevar'))
    T.wahr('Rand-LGS-Speicher geleert', randErgebnis == nil)
    T.wahr('Namenspruefung: system12 nie, ux_k3 und stab2_k schon',
        not istSkriptVariable('system12') and istSkriptVariable('UX_K3') and istSkriptVariable('stab2_k') and not istSkriptVariable('wneu'))
    var.list = altList
    pcall(math.eval, 'DelVar system3, meinevar')
    on.escapeKey()
end)

fall('23 Starre Platte: Hinweis nur, wenn die Annahme das Ergebnis aendert', function()
    T.abschnitt('Verbundstab mit starrer Platte (senkrechte Stabkette), Lager oben und unten an der Platte')
    local function platte(lager)
        local K = { node(2, 0), node(2, 1), node(2, 2), node(2, 3), node(2, 4), fixed(node(0, 2)), fixed(node(3, 1)), fixed(node(3, 2)), fixed(node(3, 3)) }
        lager(K[1]); lager(K[5])
        leer(K)
        local starr = { biegesteif = true, dehnsteif = true }
        setStaebe({ T.bar(1, 2, starr), T.bar(2, 3, starr), T.bar(3, 4, starr), T.bar(4, 5, starr),
            T.bar(6, 3, { EA = 1.2e9, EI = 1e6, To = 10, Tu = 10, alpha = 1.2e-5, h = 0.2 }),
            T.bar(3, 8, { EA = 8e8, EI = 1e6 }), T.bar(2, 7, { EA = 1e9, EI = 1e6 }), T.bar(4, 9, { EA = 1e9, EI = 1e6 }) })
        pcall(starteBerechnung)
        return getStaebe()
    end
    -- zwei Loslager: die senkrechte Kraft in der Platte ist unbestimmt, aber fuer jede Annahme null
    local st = platte(roller)
    T.wahr('zwei Loslager: kein Hinweis "gegenseitig statisch unbestimmt"', not hinweisMit('gegenseitig statisch unbestimmt'), table.concat(hinweisListe, ' | '))
    T.zahl('zwei Loslager: u Platte = 9/212500 m', st[5].v_local[4], 9 / 212500, 1e-9)
    T.zahl('sigma1 = -168/85 N/mm^2', -st[5].s_local[1] / 60000, -168 / 85, 1e-9)
    T.zahl('sigma3 = -144/17 N/mm^2', -st[7].s_local[1] / 5000, -144 / 17, 1e-9)
    -- zwei Einspannungen: die Momente zwischen oben und unten haengen von der Annahme ab
    platte(fixed)
    T.wahr('zwei Einspannungen: Hinweis bleibt', hinweisMit('gegenseitig statisch unbestimmt'), table.concat(hinweisListe, ' | '))
end)

fall('24 Boegen: Schnittgroessen-Export, auch wenn Stab 1 ein Bogen ist', function()
    T.abschnitt('Viertelkreis R = 2 um (2|0) mit Kragende, Stab mit Laengslast angelenkt, F = 1 an der Spitze')
    -- Handrechnung: Stab 3 (angelenkt, nur Laengslast) gibt an den Bogen nur eine Kraft in seiner
    -- Richtung; Momente um N1 -> Lager N1 rein waagerecht F. Von N1 aus (Tangente senkrecht):
    -- M = -2F sin p, N = -F sin p, Q = -F cos p. Bogen 2 ab N2 (Kraft F an der Spitze):
    -- M = -2F cos(45 Grad + p) = sqrt(2) (sin p - cos p)
    local a = 2 - math.sqrt(2)
    local K = { node(0, 0), node(a, -math.sqrt(2)), node(2, -2), node(2, 0) }
    pinned(K[1]); pinned(K[4])
    K[3].last_y = 1
    if not T.rechne(K, { T.bar(1, 2, { bogen_r = 2 }), T.bar(2, 3, { bogen_r = 2 }), T.bar(2, 4, { n = 1, gelenk_A = true }) }) then return end
    meldungText = nil
    exportSchnittkraefteToTI()
    T.wahr('Meldung nennt die Boegen und den Winkelbereich', (meldungText or ''):find('M_bogen', 1, true) ~= nil
        and meldungText:find('Stab 1: p von 0 bis 45 Grad', 1, true) ~= nil, meldungText)
    for _, p in ipairs({ 0, math.pi / 8, math.pi / 4 }) do
        T.zahl('M_bogen1(' .. p .. ') = -2 sin p', T.ev('M_bogen1(' .. p .. ')'), -2 * math.sin(p), 1e-6)
        T.zahl('N_bogen1(' .. p .. ') = -sin p', T.ev('N_bogen1(' .. p .. ')'), -math.sin(p), 1e-6)
        T.zahl('q_bogen1(' .. p .. ') = -cos p', T.ev('q_bogen1(' .. p .. ')'), -math.cos(p), 1e-6)
        T.zahl('M_bogen2(' .. p .. ') = sqrt(2)(sin p - cos p)', T.ev('M_bogen2(' .. p .. ')'), math.sqrt(2) * (math.sin(p) - math.cos(p)), 1e-6)
    end
    -- der gerade Stab 3 wird trotz Bogen als Stab 1 exportiert: Druckkraft sqrt(2) F am Gelenk
    T.zahl('N_stab3(0) = -sqrt(2)', T.ev('N_stab3(0)'), -math.sqrt(2), 1e-6)
    -- die anderen Exporte melden nicht mehr faelschlich "zuerst berechnen"
    for _, f in ipairs({ exportBiegelinienToTI, exportULinienToTI }) do
        meldungText = nil
        f()
        T.wahr('Export laeuft trotz Bogen als Stab 1', (meldungText or ''):find('zuerst', 1, true) == nil, meldungText)
    end
end)

T.ende('Oberflaeche Tragwerk')
