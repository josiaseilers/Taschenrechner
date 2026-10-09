-- Knotenverschiebung aus dem Rand-LGS (Knotenmenue Seite 4, Zeile 1) und Systeme speichern/oeffnen
-- (Obermenue Seite 4, Zeilen 5 und 6).
-- Verschiebungen global: x nach rechts, y nach unten, phi gegen den Uhrzeigersinn.
-- Aufruf: luajit Emulator/tests/verschiebung.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned = T.node, T.fixed, T.pinned
local fall = T.fall

-- TI-Variablen fuer var.store/var.recall
local speicher = {}
var.store = function(name, wert) speicher[name] = wert end
var.recall = function(name) return speicher[name] end

-- Zeichen-Attrappe wie in oberflaeche.lua: alle Texte sammeln
local texte = {}
local gc = setmetatable({}, { __index = function(_, k)
    if k == 'drawString' then return function(_, text, x, y) texte[#texte + 1] = { t = tostring(text), x = x, y = y } end end
    if k == 'getStringWidth' then return function(_, text) return #tostring(text) * 6 end end
    if k == 'getStringHeight' then return function() return 12 end end
    return function() end
end })
local function zeichne()
    texte = {}
    local ok, err = pcall(on.paint, gc)
    if not ok then T.pruef(false, 'on.paint Absturz: ' .. tostring(err):gsub('\n.*', '')) end
    return texte
end
local function textBei(muster)
    for _, e in ipairs(zeichne()) do if e.t:find(muster, 1, true) then return e end end
    return nil
end

local function wert(name) return T.ev(name) end
local function anzahl(muster)
    local n = 0
    for _, m in ipairs(T.msgs) do if m:find(muster, 1, true) then n = n + 1 end end
    return n
end
local function export(kidx)
    local ok, res = pcall(exportKnotenVerschiebungToTI, kidx)
    T.pruef(ok and res == true, 'Export Knoten ' .. kidx .. (ok and '' or (': ' .. tostring(res))))
    return ok and res
end
local function knotenWerte(kidx, ux, uy, phi, tol)
    tol = tol or 1e-6
    T.zahl('ux_k' .. kidx, wert('ux_k' .. kidx), ux, tol)
    T.zahl('uy_k' .. kidx, wert('uy_k' .. kidx), uy, tol)
    if phi then T.zahl('phi_k' .. kidx, wert('phi_k' .. kidx), phi, tol) end
end

fall('1 Kragarm waagerecht, F nach unten', function()
    T.abschnitt('Kragarm L=2, F=10 nach unten, EI=1: w = FL^3/3, phi = -FL^2/2')
    local K = { fixed(node(0, 0)), node(2, 0) }
    K[2].last_y = 10
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    if export(2) then knotenWerte(2, 0, 80 / 3, -20) end
    if export(1) then knotenWerte(1, 0, 0, 0) end
end)

fall('2 Stiel: H nach rechts, V nach unten', function()
    T.abschnitt('Stiel L=2 nach oben, H=5, V=3, EI=1, EA=100')
    local K = { fixed(node(0, 0)), node(0, -2) }
    K[2].last_x, K[2].last_y = 5, 3
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    -- H: ux = HL^3/3, Kopf dreht im Uhrzeigersinn; V: Stauchung VL/EA, Kopf geht nach unten
    if export(2) then knotenWerte(2, 40 / 3, 0.06, -10) end
end)

fall('3 schraeger Kragarm', function()
    T.abschnitt('Kragarm nach (3,-4), L=5, F=1 nach unten: Laengs- und Queranteil')
    local K = { fixed(node(0, 0)), node(3, -4) }
    K[2].last_y = 1
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    -- t = (0.6, -0.8), n = (0.8, 0.6); u(L) = -0.8*5/100, w(L) = 0.6*125/3
    local u, w = -0.04, 25
    if export(2) then knotenWerte(2, 0.6 * u + 0.8 * w, -0.8 * u + 0.6 * w, -7.5) end
end)

fall('4 Querkraftgelenke: Knoten-Unbekannte ux(K), uy(K)', function()
    T.abschnitt('Knoten 2 nur ueber Stabenden mit Q-Gelenk: Verschiebung aus den Knoten-Unbekannten')
    local K = { fixed(node(0, 0)), node(2, 0), fixed(node(2, 2)) }
    K[2].last_x, K[2].last_y = 5, 3
    local S = { T.bar(1, 2, { q_gelenk_B = true }), T.bar(2, 3, { q_gelenk_A = true }) }
    if not T.rechne(K, S) then return end
    -- H ueber die Normalkraft von Stab 1, V ueber die von Stab 2
    if export(2) then knotenWerte(2, 0.1, 0.06, 0) end
end)

fall('5 starrer Stab auf Feder (direkt und Grenzwert)', function()
    for _, direkt in ipairs({ true, false }) do
        T.abschnitt('biege- und dehnsteifer Stab, Festlager links, Feder cy=10 rechts, F=4 (' .. (direkt and 'direkt' or 'Grenzwert') .. ')')
        local K = { pinned(node(0, 0)), node(2, 0) }
        K[2].cy, K[2].last_y = 10, 4
        if T.rechne(K, { T.bar(1, 2, { biegesteif = true, dehnsteif = true }) }, { starrDirekt = direkt }) then
            if export(2) then knotenWerte(2, 0, 0.4, -0.2) end
            if export(1) then knotenWerte(1, 0, 0, -0.2) end
        end
    end
end)

fall('6 Gelenkknoten ohne Verdrehung', function()
    T.abschnitt('Zweifeldtraeger mit Gelenk ueber dem Mittelknoten: kein phi_k2')
    local K = { fixed(node(0, 0)), node(1, 0), fixed(node(2, 0)) }
    K[2].gelenk, K[2].last_y = true, 2
    if not T.rechne(K, { T.bar(1, 2), T.bar(2, 3) }) then return end
    -- zwei Kragarme L=1 teilen sich F: je F/2, w = (F/2)/3
    if export(2) then
        knotenWerte(2, 0, 1 / 3)
        T.wahr('phi_k2 nicht gesetzt', T.evs('phi_k2') == 'phi_k2', T.evs('phi_k2'))
    end
end)

fall('7 symbolisch', function()
    T.abschnitt('Kragarm L=l, F an der Spitze, EI und EA symbolisch')
    local K = { fixed(node(0)), node(1) }
    K[2].last_y, K[2].last_y_str = 1, 'F'
    local S = { T.bar(1, 2, nil, { EI = 1, EA = 1, EI_str = 'EI', EA_str = 'EA' }) }
    if not T.rechne(K, S) then return end
    if export(2) then
        local function gleich(name, soll)
            local d = T.ev('expand((' .. name .. ')-(' .. soll .. '))')
            T.pruef(type(d) == 'number' and math.abs(d) < 1e-9, name .. ' = ' .. tostring(T.evs(name)) .. '  soll ' .. soll)
        end
        gleich('ux_k2', '0')
        gleich('uy_k2', 'F*l^3/(3*EI)')
        gleich('phi_k2', '-F*l^2/(2*EI)')
    end
end)

fall('8 Speicher: Rand-LGS nur bei Aenderung neu', function()
    T.abschnitt('zweiter Knoten aus dem Speicher; nur ein anderes System erzwingt einen Neuaufbau')
    local K = { fixed(node(0, 0)), node(2, 0) }
    K[2].last_y = 10
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    export(2)
    T.zahl('1 Rand-LGS nach erstem Export', anzahl('Rand-LGS gestartet'), 1, 0)
    export(1)
    export(2)
    T.zahl('weiter 1 Rand-LGS (System unveraendert)', anzahl('Rand-LGS gestartet'), 1, 0)
    T.wahr('Meldung "aus dem Speicher"', anzahl('aus dem Speicher') == 2, anzahl('aus dem Speicher'))
    -- Neuberechnung (Taste B) ohne Aenderung: Speicher bleibt gueltig
    starteBerechnung()
    export(2)
    T.zahl('Neuberechnung ohne Aenderung: kein neues Rand-LGS', anzahl('Rand-LGS gestartet'), 1, 0)
    -- Last aendern
    getKnoten()[2].last_y = 20
    export(2)
    T.zahl('Laständerung: Rand-LGS neu', anzahl('Rand-LGS gestartet'), 2, 0)
    knotenWerte(2, 0, 160 / 3, -40)
    -- Knoten 2 loeschen (Stab 1 geht mit) und identisch wieder einbauen: gleicher Fingerabdruck
    local vorher = systemFingerabdruck()
    local k2, s1 = {}, {}
    for f, v in pairs(getKnoten()[2]) do k2[f] = v end
    for f, v in pairs(getStaebe()[1]) do s1[f] = v end
    setHover('knoten', 2)
    on.backspaceKey()
    T.zahl('Knoten und Stab geloescht', #getKnoten() + #getStaebe(), 1, 0)
    local KK, SS = getKnoten(), getStaebe()
    KK[2] = k2; SS[1] = s1
    T.wahr('Fingerabdruck wie vorher', systemFingerabdruck() == vorher)
    export(2)
    T.zahl('Loeschen und identischer Neubau: gleiches System, kein neues Rand-LGS', anzahl('Rand-LGS gestartet'), 2, 0)
    knotenWerte(2, 0, 160 / 3, -40)
    -- anders nummeriert (Stab umgedreht): anderer Fingerabdruck, Rand-LGS neu
    getStaebe()[1].k1, getStaebe()[1].k2 = 2, 1
    export(2)
    T.zahl('anders nummeriert: Rand-LGS neu', anzahl('Rand-LGS gestartet'), 3, 0)
    knotenWerte(2, 0, 160 / 3, -40)
    getStaebe()[1].k1, getStaebe()[1].k2 = 1, 2
    -- Aenderung: alte Knotenverschiebungen werden beim naechsten Rand-LGS geloescht
    getKnoten()[2].last_y = 10
    exportBiegelinienNeuToTI()
    T.wahr('ux_k2 des alten Systems geloescht', T.evs('ux_k2') == 'ux_k2', T.evs('ux_k2'))
    -- gleiches System, Rand-LGS explizit neu: Knotenverschiebungen bleiben stehen
    export(2)
    exportBiegelinienNeuToTI()
    T.zahl('uy_k2 bleibt bei gleichem System', T.ev('uy_k2'), 80 / 3, 1e-6)
end)

fall('9 Knotenmenue Seite 4', function()
    T.abschnitt('Zeile 1 "Verschiebung", Zeile 9 "In TI speichern", Menuehoehe')
    local K = { fixed(node(0, 0)), node(2, 0) }
    K[2].last_y = 10
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    local e = textBei('Verschiebung:')
    T.wahr('ohne Menue kein Eintrag', e == nil)
    menuOffen, menuTyp, menuIndex, menuSeite, menuZeile, eingabeModus = true, 'knoten', 2, 4, 1, false
    e = textBei('Verschiebung:')
    T.wahr('Zeile 1: "Verschiebung:"', e and e.y == 40, e and e.y)
    e = textBei('In TI speichern:')
    T.wahr('Zeile 9: "In TI speichern:"', e and e.y == 200, e and e.y)
    e = textBei('phi (WGV):')
    T.wahr('phi (WGV) in Zeile 8', e and e.y == 180, e and e.y)
    -- Menuebreite: Text der ersten Spalte endet vor der Wertespalte (6 px je Zeichen)
    local breit = 0
    for _, t in ipairs(zeichne()) do if t.x == 15 and t.y > 30 then breit = math.max(breit, #t.t * 6) end end
    T.wahr('Beschriftungen passen vor die Wertespalte', breit <= 100, breit)
    menuZeile = 9
    T.wahr('Zeile 9 ist die letzte', (function() on.arrowKey('down'); return menuZeile == 9 end)())
    menuZeile = 1
    on.enterKey()
    T.wahr('Enter in Zeile 1 exportiert', T.ev('uy_k2') and math.abs(T.ev('uy_k2') - 80 / 3) < 1e-6, T.evs('uy_k2'))
    T.wahr('Menue geschlossen', not menuOffen)
    T.wahr('Meldung zeigt uy_k2 in eigener Zeile', textBei('uy_k2 = ') ~= nil)
    meldungText = nil
end)

-- Beispielsystem mit allen Arten von Eingaben
local function beispiel()
    T.reset()
    defEA, defEI, defEA_str, defEI_str = 1e10, 1e8, '1e8', nil
    rasterMass, rasterMass_str, fachwerkModus = 0.5, '1/2', false
    local K = { fixed(node(0, 0)), node(2, 0, '2', '0'), pinned(node(4, 1)) }
    K[2].last_x, K[2].last_x_str = 1, 'a,b;c=d:e"f%g'
    K[2].last_w, K[2].last_w_str = 30, '30'
    K[3].winkel, K[3].cx, K[3].cx_str = 15, 1000, 'c'
    local S = { erstelleStab(1, 2), erstelleStab(2, 3) }
    S[1].q, S[1].q_str, S[1].q_A, S[1].q_B = 2, 'q*x/l', 1, 3
    S[1].EA_str, S[1].EI, S[1].gelenk_B = nil, 0.1, true
    S[2].gx, S[2].gx_str, S[2].gx_proj, S[2].To, S[2].Tu = 1, 'p', true, 10, -5
    S[2].biegesteif, S[2].n_gelenk_A = true, true
    setKnoten(K); setStaebe(S)
end

fall('10 System speichern und oeffnen', function()
    T.abschnitt('Obermenue Seite 4: speichern als system7, alles loeschen, system7 oeffnen')
    beispiel()
    local vorher = systemFingerabdruck()
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 5, false
    on.enterKey()
    T.wahr('Zeile 5 startet die Eingabe', eingabeModus)
    eingabeText = '7'
    on.enterKey()
    local text = speicher.system7
    T.wahr('system7 ist ein String', type(text) == 'string', type(text))
    if type(text) ~= 'string' then return end
    T.info('   system7 = ' .. text)
    T.wahr('Kopf TWS1', text:sub(1, 8) == 'TWS1;G:r', text:sub(1, 12))
    T.wahr('Sonderzeichen kodiert', text:find('a%2Cb%3Bc%3Dd%3Ae%22f%25g', 1, true) ~= nil)
    T.wahr('nur Abweichungen vom Standard', not text:find('lager_x=F', 1, true))
    T.wahr('letzte Nummer 7', letzteSystemNr == 7, letzteSystemNr)
    -- alles anders machen
    loescheAlles()
    rasterMass, rasterMass_str, defEA, defEI, defEA_str, defEI_str = 1, nil, 5, 6, 'x', 'y'
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 6, false
    on.enterKey(); eingabeText = '7'; on.enterKey()
    T.zahl('3 Knoten', #getKnoten(), 3, 0)
    T.zahl('2 Staebe', #getStaebe(), 2, 0)
    T.wahr('Fingerabdruck wie vor dem Speichern', systemFingerabdruck() == vorher)
    T.wahr('Einstellungen zurueck', rasterMass == 0.5 and rasterMass_str == '1/2' and defEA == 1e10 and defEI == 1e8
        and defEA_str == '1e8' and defEI_str == nil, tostring(rasterMass) .. ' ' .. tostring(defEA_str) .. ' ' .. tostring(defEI_str))
    local S = getStaebe()
    T.wahr('EA_str nil bleibt nil (Standard waere 1e8)', S[1].EA_str == nil and S[2].EA_str == '1e8', tostring(S[1].EA_str))
    T.wahr('Sonderzeichen zurueck', getKnoten()[2].last_x_str == 'a,b;c=d:e"f%g', getKnoten()[2].last_x_str)
    T.wahr('berechnete Felder neu angelegt', type(S[1].s_local) == 'table' and S[1].k1 == 1 and S[2].k2 == 3)
    T.wahr('neu rechnen', not systemBerechnet)
    meldungText = nil

    T.abschnitt('Kragarm speichern, oeffnen, rechnen: gleiche Knotenverschiebung')
    defEA_str, defEI_str = nil, nil
    local K = { fixed(node(0, 0)), node(2, 0) }
    K[2].last_y = 10
    if not T.rechne(K, { T.bar(1, 2) }) then return end
    T.wahr('speichern', speichereSystem(8))
    loescheAlles()
    T.wahr('oeffnen', oeffneSystem(8))
    local ok, err = pcall(starteBerechnung)
    T.wahr('geoeffnetes System rechnet', ok, err)
    if export(2) then knotenWerte(2, 0, 80 / 3, -20) end
    meldungText = nil
end)

fall('11 Fehlerfaelle und Anzeige', function()
    T.abschnitt('nicht vorhandene Nummer, keine Zahl, fremder Inhalt, Zeichnung Seite 4')
    beispiel()
    local vorher = systemFingerabdruck()
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 6, false
    on.enterKey(); eingabeText = '99'; on.enterKey()
    T.wahr('system99 nicht vorhanden', meldungText and meldungText:find('system99 ist nicht vorhanden', 1, true), meldungText)
    T.wahr('System unveraendert', systemFingerabdruck() == vorher)
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 5, false
    on.enterKey(); eingabeText = 'abc'; on.enterKey()
    T.wahr('keine Zahl: Hinweis', meldungText and meldungText:find('ganze Zahl', 1, true), meldungText)
    speicher.system5 = 'irgendwas'
    oeffneSystem(5)
    T.wahr('fremder Inhalt: Hinweis', meldungText and meldungText:find('keine gespeicherte', 1, true), meldungText)
    T.wahr('System unveraendert', systemFingerabdruck() == vorher)
    loescheAlles()
    speichereSystem(4)
    T.wahr('leeres System wird nicht gespeichert', speicher.system4 == nil and meldungText:find('Kein System', 1, true), meldungText)
    meldungText = nil
    beispiel()
    menuOffen, menuTyp, menuSeite, menuZeile, eingabeModus = true, 'obermenue', 4, 5, false
    letzteSystemNr = 12
    local e = textBei('System speichern als:')
    T.wahr('Zeile 5 "System speichern als:"', e and e.y == 120, e and e.y)
    e = textBei('System öffnen:')
    T.wahr('Zeile 6 "System öffnen:"', e and e.y == 140, e and e.y)
    e = textBei('system12')
    T.wahr('letzte Nummer angezeigt', e ~= nil)
    menuZeile = 6
    on.arrowKey('down')
    T.wahr('darunter Zeile 7 (Variablen loeschen)', menuZeile == 7, menuZeile)
    on.arrowKey('down')
    T.wahr('Zeile 7 ist die letzte', menuZeile == 7, menuZeile)
    menuOffen = false
end)

T.ende('Knotenverschiebung und Systeme')
