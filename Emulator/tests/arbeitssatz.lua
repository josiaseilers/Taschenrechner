-- Arbeitssatz (PvV-Export w_eq1/w_eq2) gegen FEM und Handrechnung.
-- Fuer jede freigesetzte Bindung wird w_eq2 nach der Unbekannten aufgeloest und mit der
-- Auflagerreaktion bzw. Schnittgroesse der FEM-Rechnung verglichen:
--   H, V   = Lagerkraft in Lagerrichtung xi = (cos w, -sin w) bzw. eta = (sin w, cos w) (y nach unten)
--   M_A    = Einspannmoment gegen den Uhrzeigersinn (= k.R_m)
--   M, N, Q = positive Schnittgroesse am Stabende (Anfang: -s_local[1..3], Ende: s_local[4..6])
-- Aufruf: luajit Emulator/tests/arbeitssatz.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller
local zahl, wahr, fall = T.zahl, T.wahr, T.fall

-- linke Seiten und Tabellen holen (ohne CAS-Speichern)
local function terme()
    local ok, e1, e2, kin, pol = pcall(exportArbeitssatzToTI, true)
    if not ok then T.pruef(false, 'Export abgestuerzt: ' .. tostring(e1)); return '0', '0', {}, {} end
    return e1 or '0', e2 or '0', kin or {}, pol or {}
end

-- Namen aus einer Tabelle (Spalte 1) durch Spalte `spalte` ersetzen. Die Namen beginnen mit φ bzw.
-- δ (kein %w), deshalb nur eine Wortgrenze dahinter.
local function einsetzen(s, zeilen, spalte)
    for _, z in ipairs(zeilen) do
        s = s:gsub(z[1]:gsub('%p', '%%%0') .. '%f[^%w_]', '(' .. z[spalte] .. ')')
    end
    return s
end

local function ersetze(s, name, wert)
    return (s:gsub('%f[%w_]' .. name .. '%f[^%w_]', '(' .. wert .. ')'))
end

-- Symbole mit Zahlen belegen, Ausdruck auswerten, wieder loeschen
local function mitWerten(expr, werte)
    local namen = {}
    for k, v in pairs(werte or {}) do math.eval(k .. ':=' .. tostring(v)); namen[#namen + 1] = k end
    local v = T.ev(expr)
    if #namen > 0 then math.eval('DelVar ' .. table.concat(namen, ',')) end
    return v
end

-- w_eq2 = 0 (linear in x) nach x aufloesen; phi_0 bzw. delta_0 kuerzt sich heraus
local function loese(e2, x, werte)
    local basis = e2:gsub('φ_0', '1'):gsub('δ_0', '1')
    local a0 = mitWerten(ersetze(basis, x, 0), werte)
    local a1 = mitWerten(ersetze(basis, x, 1), werte)
    if type(a0) ~= 'number' or type(a1) ~= 'number' or math.abs(a1 - a0) < 1e-12 then
        return nil
    end
    return -a0 / (a1 - a0)
end

-- zwei Ausdruecke (phi_0 bzw. delta_0 = 1) gleich?
local function gleich(label, a, b, werte)
    local va = mitWerten(a:gsub('φ_0', '1'):gsub('δ_0', '1'), werte)
    local vb = mitWerten(b:gsub('φ_0', '1'):gsub('δ_0', '1'), werte)
    -- 1e-7: bei schiefen Geometrien stehen Dezimalzahlen mit etwa neun Stellen im Text
    zahl(label, va, type(vb) == 'number' and vb or 0 / 0, 1e-7)
end

-- Zeichnung und Export passen 1:1: Jede Zeile von pvv_kin steht als "Name = Wert" in der PvV-Ansicht,
-- der Zahlenwert der Ansicht ist Spalte 3 (phi_0 bzw. delta_0 = 1, Laengensymbol = sein Zahlenwert),
-- und die Ansicht beschriftet keinen Weg und keine Scheibe, die der Export nicht kennt.
local function anzeigePasst(name, kin, werte)
    local D = pvvAnzeige()
    if not D then T.pruef(false, name .. ': keine Anzeigedaten'); return end
    local texte = {}
    local gc = setmetatable({ drawString = function(_, t) texte[#texte + 1] = tostring(t) end },
        { __index = function() return function() return 10 end end })
    local ok, err = pcall(on.paint, gc)
    wahr(name .. ': PvV-Ansicht zeichnet', ok, err)
    local gezeigt, namen = {}, {}
    for _, t in ipairs(texte) do gezeigt[t] = true end
    local w = {}
    for k, v in pairs(werte or {}) do w[k] = v end
    if symbolischer_modus then w[symbLSym] = symbLDummy end
    for _, z in ipairs(kin) do
        namen[z[1]] = true
        local e = D.wege[z[1]]
        if not e then for _, sc in pairs(D.scheiben) do if sc.var == z[1] then e = sc end end end
        if e then
            gleich(name .. ': Ansicht ' .. z[1] .. ' = Spalte 3', z[3], tostring(e.num), w)
            local lbl = z[1] .. ' = ' .. e.text
            wahr(name .. ': Ansicht zeigt ' .. lbl, gezeigt[lbl] == true, lbl)
        else
            T.pruef(false, name .. ': Ansicht kennt ' .. z[1] .. ' nicht')
        end
    end
    for _, t in ipairs(texte) do
        local n = t:match('^([δφ][^ ]*) = ')
        if n then wahr(name .. ': Ansicht ' .. n .. ' steht im Export', namen[n] == true, t) end
    end
    -- Menues: jeder Weg steht bei seinem Knoten bzw. Stab, und alle PvV-Menues zeichnen
    for _, wg in ipairs(D.reihe) do
        local typ, idx = wg.knoten and 'knoten' or 'stab', wg.knoten or wg.stab
        local da = false
        for _, z in ipairs(pvvMenueZeilen(typ, idx)) do if z[1] == wg.name .. ' = ' .. wg.text then da = true end end
        wahr(name .. ': Menue ' .. typ .. ' ' .. tostring(idx) .. ' zeigt ' .. wg.name, da)
    end
    local fehler = nil
    for _, m in ipairs({ { 'knoten', #getKnoten() }, { 'stab', #getStaebe() } }) do
        for idx = 1, m[2] do
            menuOffen, menuTyp, menuIndex, menuSeite, menuZeile = true, m[1], idx, 1, 1
            local ok2, err2 = pcall(on.paint, gc)
            if not ok2 then fehler = m[1] .. ' ' .. idx .. ': ' .. tostring(err2) end
        end
    end
    menuOffen = false
    wahr(name .. ': alle PvV-Menues zeichnen', fehler == nil, fehler)
end

-- Bindung loesen, Arbeitssatz bilden, Unbekannte gegen soll pruefen. Dazu die Tabellen:
--   w_eq1 mit pvv_kin (Spalte 3) eingesetzt liefert dieselbe Unbekannte,
--   in pvv_kin passt Spalte 2 (ueber die eigene Scheibe) zu Spalte 3 (ueber phi_0),
--   in pvv_pol liefern beide Scheiben am Nebenpol dieselbe Bewegung.
local function pruefe(name, x, soll, freigabe, werte)
    freigabe()
    local e1, e2, kin, pol = terme()
    local ist = loese(e2, x, werte)
    zahl(name .. ': ' .. x, ist, soll, 1e-6)
    local ist1 = loese(einsetzen(e1, kin, 3), x, werte)
    zahl(name .. ': ' .. x .. ' aus w_eq1 und pvv_kin', ist1, soll, 1e-6)
    local scheiben = {}
    for _, z in ipairs(kin) do if z[1] == z[2] then scheiben[#scheiben + 1] = z end end
    for _, z in ipairs(kin) do
        if z[1] ~= z[2] then gleich(name .. ': pvv_kin ' .. z[1] .. ' Spalte 2 = Spalte 3', einsetzen(z[2], scheiben, 3), z[3], werte) end
    end
    for _, z in ipairs(pol) do
        gleich(name .. ': pvv_pol ' .. z[1] .. ' ueber beide Scheiben gleich', einsetzen(z[2], scheiben, 3), einsetzen(z[3], scheiben, 3), werte)
    end
    anzeigePasst(name, kin, werte)
    if T.verbose or not ist or math.abs(ist - soll) > 1e-6 * math.max(1, math.abs(soll)) then
        T.write('      w_eq1: ' .. e1 .. '\n      w_eq2: ' .. e2 .. '\n')
        for _, z in ipairs(kin) do T.write('      kin: ' .. table.concat(z, ' | ') .. '\n') end
        for _, z in ipairs(pol) do T.write('      pol: ' .. table.concat(z, ' | ') .. '\n') end
    end
    pvvEnde()
    return e1, e2, kin, pol
end

local function anfang(s) return -s.s_local[1], -s.s_local[2], -s.s_local[3] end
local function ende(s) return s.s_local[4], s.s_local[5], s.s_local[6] end

fall('1 Gelenkkette aus der Klausur (symbolisch)', function()
    T.abschnitt('Gelenkkette: F1 ins Lager, F2 nach links, F3 schraeg in Stabrichtung, Einspannung geloest')
    -- N1 (0|1) waagerecht gehalten, N2 (1|0) Rollenlager, N3 (2|1), N4 (3|0) eingespannt; Gelenke in N1..N3
    local K = { node(0, -1), node(1, 0), node(2, -1), node(3, 0) }
    K[1].lager_x = true; K[1].gelenk = true
    K[2].lager_y = true; K[2].gelenk = true
    K[3].gelenk = true
    fixed(K[4])
    K[1].last_x, K[1].last_x_str = 1, 'F1'
    K[2].last_x, K[2].last_x_str = -1, '-F2'
    K[3].last_x, K[3].last_x_str, K[3].last_w = 1, 'F3', 45
    local S = { T.bar(1, 2), T.bar(2, 3), T.bar(3, 4) }
    for _, s in ipairs(S) do s.EI_str, s.EA_str = 'EI', 'EA' end
    if not T.rechne(K, S) then return end
    wahr('symbolischer Modus', symbolischer_modus)
    local Rm_fem = getKnoten()[4].R_m
    pvvFreigabe(4, 3)
    local e1, e2, kin1 = terme()
    anzeigePasst('Gelenkkette', kin1)
    wahr('w_eq1 enthaelt den Namen F2', e1:find('F2', 1, true) ~= nil, e1)
    wahr('w_eq1 enthaelt den Namen F3', e1:find('F3', 1, true) ~= nil, e1)
    wahr('F1 leistet keine Arbeit (N1 bewegt sich senkrecht)', e1:find('F1', 1, true) == nil, e1)
    wahr('kein Winkel im CAS-Text (Winkelmodus egal)', e1:find('cos', 1, true) == nil and e1:find('sin', 1, true) == nil, e1)
    -- Handrechnung: M_A * phi_0 + 2 F2 l phi_0 - sqrt(2) F3 l phi_0 = 0
    local werte = { f2 = 1.3, f3 = 0.7, l = 1.9 }
    zahl('M_A = (sqrt(2) F3 - 2 F2) l', loese(e2, 'M_A', werte), (math.sqrt(2) * 0.7 - 2 * 1.3) * 1.9, 1e-9)
    zahl('gegen FEM (Platzhalter F = 1, l = 1)', loese(e2, 'M_A', { f2 = 1, f3 = 1, l = 1 }), Rm_fem, 1e-6)
    T.info('      w_eq1: ' .. e1 .. '\n      w_eq2: ' .. e2)
    -- echter Export ins CAS: Gleichungen, Tabellen und Legende sind angelegt
    exportArbeitssatzToTI()
    local kinTxt, infoTxt = tostring(T.evs('pvv_kin')), tostring(T.evs('pvvinfo'))
    T.info('      pvv_kin: ' .. kinTxt .. '\n      pvvinfo: ' .. infoTxt)
    wahr('pvv_kin als Matrix im CAS', kinTxt:sub(1, 1) == '[' and kinTxt:find('φ_0', 1, true) ~= nil, kinTxt)
    wahr('pvvinfo erklaert die Namen', infoTxt:find('δ_k2x', 1, true) ~= nil, infoTxt)
    wahr('pvv_pol mit den Nebenpolen', tostring(T.evs('pvv_pol')):find('φ_1', 1, true) ~= nil, T.evs('pvv_pol'))
    -- w_eq1/w_eq2 selbst ("name := ... = 0") kann der Emulator nicht zuweisen, der Rechner schon
    pvvEnde()
end)

fall('2 Kragrahmen: Einspannung und Stabgelenke', function()
    T.abschnitt('Kragrahmen (Zahlen): jede Bindung einzeln geloest, Vergleich mit FEM')
    -- N1 eingespannt, Stuetze nach oben, Riegel nach rechts; Lasten mit Winkel, Moment, Streckenlasten
    local K = { node(0, 0), node(0, -2), node(2, -2) }
    fixed(K[1])
    K[3].last_x, K[3].last_y, K[3].last_m = 3, 5, 2
    K[2].last_x, K[2].last_w = 4, 30
    local S = { T.bar(1, 2, { n = 0.5 }), T.bar(2, 3, { q = 1, q_B = 1 }) }
    if not T.rechne(K, S) then return end
    local k1 = getKnoten()[1]
    local s1, s2 = getStaebe()[1], getStaebe()[2]
    local N1a, Q1a, M1a = anfang(s1); local N1e, Q1e, M1e = ende(s1)
    local N2a, Q2a, M2a = anfang(s2)
    pruefe('Einspannung H (Verschiebung)', 'H', k1.R_xi, function() pvvFreigabe(1, 1) end)
    pruefe('Einspannung V (Verschiebung)', 'V', -k1.R_eta, function() pvvFreigabe(1, 2) end)
    pruefe('Einspannung M', 'M_A', k1.R_m, function() pvvFreigabe(1, 3) end)
    pruefe('Knotengelenk N2', 'M', M1e, function() pvvFreigabe(2, 4) end)
    pruefe('M-Gelenk Riegel Anfang', 'M', M2a, function() pvvFreigabeStab(2, 1) end)
    pruefe('M-Gelenk Stuetze Ende', 'M', M1e, function() pvvFreigabeStab(1, 2) end)
    pruefe('N-Gelenk Riegel Anfang', 'N', N2a, function() pvvFreigabeStab(2, 3) end)
    pruefe('N-Gelenk Stuetze Ende', 'N', N1e, function() pvvFreigabeStab(1, 4) end)
    pruefe('Q-Gelenk Riegel Anfang', 'Q', Q2a, function() pvvFreigabeStab(2, 5) end)
    pruefe('Q-Gelenk Stuetze Ende', 'Q', Q1e, function() pvvFreigabeStab(1, 6) end)
    pruefe('M-Gelenk Stuetze Anfang', 'M', M1a, function() pvvFreigabeStab(1, 1) end)
    pruefe('Q-Gelenk Stuetze Anfang', 'Q', Q1a, function() pvvFreigabeStab(1, 5) end)
end)

fall('3 Dreigelenkrahmen mit gedrehtem Lager', function()
    T.abschnitt('Dreigelenkrahmen (Zahlen): drehende Scheiben, gedrehtes Lager, alle Lastarten')
    -- N1 (0|0) und N4 (3|0) gelenkig, Riegel in N5 (1.5|2) mit Gelenk; Lager N4 um 30 Grad gedreht
    local K = { node(0, 0), node(0, -2), node(3, -2), node(3, 0), node(1.5, -2) }
    pinned(K[1]); pinned(K[4]); K[4].winkel = 30
    K[5].gelenk = true
    K[2].last_x, K[2].last_y, K[2].last_w = 2, 1, -25
    K[3].last_y, K[3].last_m = 3, 1.5
    local S = { T.bar(1, 2, { n = 0.4, gx = 0.3 }), T.bar(2, 5, { q = 1, q_A = 0.5 }), T.bar(5, 3, { gy = 0.8, m = 0.2 }), T.bar(3, 4, { q = -0.6 }) }
    if not T.rechne(K, S) then return end
    local kn = getKnoten()
    local st = getStaebe()
    local _, _, M1e = ende(st[1])
    local N2a, Q2a, M2a = anfang(st[2])
    local N4e, Q4e = ende(st[4])
    local N3a, Q3a = anfang(st[3])
    pruefe('Lager N4 H (gedreht)', 'H', kn[4].R_xi, function() pvvFreigabe(4, 1) end)
    pruefe('Lager N4 V (gedreht)', 'V', -kn[4].R_eta, function() pvvFreigabe(4, 2) end)
    pruefe('Lager N1 H', 'H', kn[1].R_xi, function() pvvFreigabe(1, 1) end)
    pruefe('Lager N1 V', 'V', -kn[1].R_eta, function() pvvFreigabe(1, 2) end)
    pruefe('Knotengelenk N2', 'M', M1e, function() pvvFreigabe(2, 4) end)
    pruefe('M-Gelenk Stuetze 1 Ende', 'M', M1e, function() pvvFreigabeStab(1, 2) end)
    pruefe('M-Gelenk Riegel Anfang', 'M', M2a, function() pvvFreigabeStab(2, 1) end)
    pruefe('Q-Gelenk Riegel Anfang', 'Q', Q2a, function() pvvFreigabeStab(2, 5) end)
    pruefe('N-Gelenk Riegel Anfang', 'N', N2a, function() pvvFreigabeStab(2, 3) end)
    pruefe('Q-Gelenk Riegel rechts Anfang (am Gelenk)', 'Q', Q3a, function() pvvFreigabeStab(3, 5) end)
    pruefe('N-Gelenk Riegel rechts Anfang (am Gelenk)', 'N', N3a, function() pvvFreigabeStab(3, 3) end)
    pruefe('Q-Gelenk Stuetze 4 Ende', 'Q', Q4e, function() pvvFreigabeStab(4, 6) end)
    pruefe('N-Gelenk Stuetze 4 Ende', 'N', N4e, function() pvvFreigabeStab(4, 4) end)
end)

fall('4 symbolisch mit Rastermass und Laengensymbol', function()
    T.abschnitt('Symbolisch: Rastermass 0.5 (l = Raster) und Geometriesymbol a')
    -- Kragarm, Raster 0.5: Knoten bei 0 und 1.5 m = 3 l; Last F am Ende, Streckenlast q
    local K = { fixed(node(0, 0)), node(1.5, 0) }
    K[2].last_y, K[2].last_y_str = 1, 'F'
    local S = { T.bar(1, 2, { q = 1, q_str = 'q', EI_str = 'EI', EA_str = 'EA' }) }
    if not T.rechne(K, S, { raster = 0.5 }) then return end
    local Rm = getKnoten()[1].R_m
    pvvFreigabe(1, 3)
    local e1, e2 = terme()
    wahr('Laengensymbol l im Arbeitssatz', e2:find('l', 1, true) ~= nil, e2)
    -- Handrechnung (M gegen den Uhrzeigersinn): M_A = F * 3l + q * (3l)^2 / 2
    zahl('M_A = 3 F l + 9/2 q l^2', loese(e2, 'M_A', { f = 1.7, q = 0.9, l = 1.3 }), 3 * 1.7 * 1.3 + 4.5 * 0.9 * 1.3 ^ 2, 1e-9)
    zahl('gegen FEM (F = q = 1, l = 0.5)', loese(e2, 'M_A', { f = 1, q = 1, l = 0.5 }), Rm, 1e-6)
    pvvEnde()

    -- Geometrie mit Symbol a: Kragarm der Laenge 2a
    K = { fixed(node(0, 0)), node(2, 0, '2*a') }
    K[2].last_y, K[2].last_y_str = 1, 'F'
    S = { T.bar(1, 2, { EI_str = 'EI', EA_str = 'EA' }) }
    if not T.rechne(K, S) then return end
    pvvFreigabe(1, 3)
    e1, e2 = terme()
    wahr('Laengensymbol a statt l', e2:find('a', 1, true) ~= nil and e2:find('%f[%w]l%f[^%w]') == nil, e2)
    zahl('M_A = 2 F a', loese(e2, 'M_A', { f = 1.7, a = 1.3 }), 2 * 1.7 * 1.3, 1e-9)
    pvvEnde()
end)

fall('5 Zeichnen im PvV-Modus', function()
    T.abschnitt('PvV-Ansicht mit gedrehtem Lager und geloestem H zeichnet ohne Fehler')
    local K = { node(0, 0), node(0, -2), node(3, -2), node(3, 0), node(1.5, -2) }
    pinned(K[1]); pinned(K[4]); K[4].winkel = 30
    K[5].gelenk = true
    K[3].last_y = 3
    local S = { T.bar(1, 2), T.bar(2, 5), T.bar(5, 3), T.bar(3, 4) }
    if not T.rechne(K, S) then return end
    local gc = setmetatable({}, { __index = function() return function() return 10 end end })
    for zeile = 1, 2 do
        pvvFreigabe(4, zeile)
        local ok, err = pcall(on.paint, gc)
        wahr('on.paint mit geloestem ' .. (zeile == 1 and 'H' or 'V'), ok, err)
        pvvEnde()
    end
end)

fall('6 Dreigelenkbogen mit Bogenlasten', function()
    T.abschnitt('Dreigelenkbogen aus zwei Viertelkreisen R = 2: Lasten auf den Boegen')
    -- Auf der starren Scheibe leistet die Bogenlast dieselbe Arbeit wie ihre Resultierende (Kraft auf der
    -- Wirkungslinie, Wege δ_s<i>x, δ_s<i>y); ohne Kraft bleibt ein Moment auf phi_i
    local K = { pinned(node(0, 0)), node(2, -2), pinned(node(4, 0)) }
    K[2].gelenk = true
    local S = { T.bar(1, 2, { bogen_r = 2, gy = 1.5, gy_str = '1.5', q = 1, q_str = '1' }),
                T.bar(2, 3, { bogen_r = 2, gx_str = 'x', m = 0.5, m_str = '0.5' }) }
    if not T.rechne(K, S) then return end
    local kn = getKnoten()
    pruefe('Bogenlasten: Lager N3 H', 'H', kn[3].R_xi, function() pvvFreigabe(3, 1) end)
    pruefe('Bogenlasten: Lager N1 V', 'V', -kn[1].R_eta, function() pvvFreigabe(1, 2) end)
    pruefe('Bogenlasten: Lager N1 H', 'H', kn[1].R_xi, function() pvvFreigabe(1, 1) end)
    -- nur Streckenmoment auf Bogen 2: Resultierende ist ein reines Moment
    S = { T.bar(1, 2, { bogen_r = 2, gy = 1.5, gy_str = '1.5' }), T.bar(2, 3, { bogen_r = 2, m = 0.5, m_str = '0.5' }) }
    K = { pinned(node(0, 0)), node(2, -2), pinned(node(4, 0)) }
    K[2].gelenk = true
    if not T.rechne(K, S) then return end
    kn = getKnoten()
    pruefe('Bogen mit reinem Moment: Lager N3 H', 'H', kn[3].R_xi, function() pvvFreigabe(3, 1) end)
    -- Handrechnung nur mit Eigengewicht g auf beiden Boegen: H = (pi - 2) g (siehe bogenlast.lua Fall 5)
    S = { T.bar(1, 2, { bogen_r = 2, gy = 1.5, gy_str = '1.5' }), T.bar(2, 3, { bogen_r = 2, gy = 1.5, gy_str = '1.5' }) }
    K = { pinned(node(0, 0)), node(2, -2), pinned(node(4, 0)) }
    K[2].gelenk = true
    if not T.rechne(K, S) then return end
    pruefe('Eigengewicht: Lager N1 H (FEM, Polygon)', 'H', getKnoten()[1].R_xi, function() pvvFreigabe(1, 1) end)
    pvvFreigabe(1, 1)
    local _, e2 = terme()
    zahl('Eigengewicht: H = (pi - 2) g (Handrechnung, 20 Teilstuecke)', loese(e2, 'H'), (math.pi - 2) * 1.5, 2e-3)
    pvvEnde()
end)

T.ende('Arbeitssatz')
