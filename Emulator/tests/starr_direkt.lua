-- Starre Staebe im Rand-LGS: direkte Methode (Starrkoerper + Gleichgewicht, randStarrDirekt = true)
-- gegen die Grenzwert-Methode (EA, EI -> unendlich). Beide muessen dieselben Verschiebungen wv/uv, bei
-- nicht starren Staeben dieselben wneu/uneu und dieselbe Bedingungsliste liefern. Bei starren Staeben
-- ist wneu/uneu in der direkten Methode immer die Verschiebung.
-- Aufruf: luajit Emulator/tests/starr_direkt.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller

local function str(e) return tostring(T.evs(e)) end
local function num(e) return T.ev(e) end
local function bar(a, b, f) return T.bar(a, b, f, { EI = 1e8, EA = 1e10 }) end
local function temp(f, To, Tu, al, h)
    f.To, f.To_str, f.Tu, f.Tu_str = 1, To, 1, Tu
    if al then f.alpha, f.alpha_str = 1, al end
    if h then f.h, f.h_str = 1, h end
    return f
end

-- System rechnen und exportieren; liefert die exportierten Funktionen als Texte
local function exportiere(K, S, opts, direkt)
    if not T.rechne(K, S, opts) then return nil end
    if symbolFehler then T.pruef(false, 'unerwarteter symbolFehler: ' .. symbolFehler); return nil end
    randStarrDirekt = direkt
    if not T.randLGS() then return nil end
    local r = { randbed = str('randbed'), randinfo = str('randinfo') }
    for i = 1, #S do
        for _, f in ipairs({ 'wv', 'uv', 'wneu', 'uneu' }) do r[f .. i] = str(f .. i .. '(x)') end
    end
    return r
end

-- Symbole belegen, Ausdruck auswerten, Symbole wieder loeschen
local function mit(werte, expr)
    local namen = {}
    for k, v in pairs(werte) do math.eval(k .. ':=' .. v); namen[#namen + 1] = k end
    local r = num(expr)
    if #namen > 0 then math.eval('DelVar ' .. table.concat(namen, ',')) end
    return r
end

local FUNKTIONEN = { sqrt = true, exp = true, ln = true, sin = true, cos = true, tan = true }
local function gleich(label, ausdruck, soll)
    local d = num('expand((' .. ausdruck .. ')-(' .. soll .. '))')
    local ok = type(d) == 'number' and math.abs(d) < 1e-12
    local ist = str(ausdruck)
    if not ok then
        -- gebrochen rationale Ausdruecke kuerzt expand nicht: an Zahlenwerten fuer alle Symbole vergleichen
        local werte, n = {}, 0
        for w in (ist .. ' ' .. soll):gmatch('%a[%w_]*') do
            if not werte[w] and not FUNKTIONEN[w] then n = n + 1; werte[w] = (n + 2) .. '/' .. (n + 5) end
        end
        local d2 = mit(werte, '(' .. ist .. ')-(' .. soll .. ')')
        ok = type(d2) == 'number' and math.abs(d2) < 1e-9
    end
    T.pruef(ok, string.format('%-34s direkt=%s  Grenzwert=%s', label, ist, soll))
end

-- bauen() liefert jeweils frische Knoten/Staebe (T.rechne veraendert sie)
local function vergleiche(titel, bauen, opts, erwarteRueckfall)
    T.abschnitt(titel)
    local K, S = bauen()
    local a = exportiere(K, S, opts, false)
    local K2, S2 = bauen()
    local b = exportiere(K2, S2, opts, true)
    if not a or not b then T.pruef(false, 'Export fehlgeschlagen'); return end
    T.info('   randinfo direkt: ' .. b.randinfo)
    if erwarteRueckfall then
        T.wahr('direkt singulaer -> Rueckfall auf Grenzwert', b.randinfo:find('direkt singulaer', 1, true) ~= nil, b.randinfo)
    else
        T.wahr('direkte Methode verwendet', b.randinfo:find('starre Staebe: direkt', 1, true) ~= nil, b.randinfo)
        -- die Exportmeldung nennt die Staebe, bei denen wneu bzw. uneu die Verschiebung selbst ist
        local biege, dehn, msg = {}, {}, tostring(meldungText)
        for i, s in ipairs(getStaebe()) do
            if stabBiegesteif(s) then biege[#biege + 1] = i end
            if stabDehnsteif(s) then dehn[#dehn + 1] = i end
        end
        if #biege > 0 then
            local soll = 'wneu=w bei Stab ' .. table.concat(biege, ',')
            T.wahr('Exportmeldung: ' .. soll, msg:find(soll, 1, true) ~= nil, msg)
        end
        if #dehn > 0 then
            local soll = 'uneu=u bei Stab ' .. table.concat(dehn, ',')
            T.wahr('Exportmeldung: ' .. soll, msg:find(soll, 1, true) ~= nil, msg)
        end
    end
    for i, s in ipairs(getStaebe()) do
        gleich('wv' .. i, 'wv' .. i .. '(x)', a['wv' .. i])
        gleich('uv' .. i, 'uv' .. i .. '(x)', a['uv' .. i])
        if not stabBiegesteif(s) or erwarteRueckfall then gleich('wneu' .. i, 'wneu' .. i .. '(x)', a['wneu' .. i])
        else gleich('wneu' .. i .. ' = wv' .. i .. ' (starr)', 'wneu' .. i .. '(x)', b['wv' .. i]) end
        if not stabDehnsteif(s) or erwarteRueckfall then gleich('uneu' .. i, 'uneu' .. i .. '(x)', a['uneu' .. i])
        else gleich('uneu' .. i .. ' = uv' .. i .. ' (starr)', 'uneu' .. i .. '(x)', b['uv' .. i]) end
    end
    -- Die Texte duerfen sich unterscheiden: bei der direkten Methode stehen mehr Groessen schon
    -- vorab fest und werden in der Anzeige eingesetzt. Die Zahl der Bedingungen muss gleich bleiben.
    local function anzahl(rb)
        local n = 0
        for t in rb:gmatch('"([^"]*)"') do if t:sub(1, 3) ~= '---' then n = n + 1 end end
        return n
    end
    T.wahr('gleich viele Bedingungen', anzahl(a.randbed) == anzahl(b.randbed),
        anzahl(a.randbed) .. ' (Grenzwert) / ' .. anzahl(b.randbed) .. ' (direkt)')
    if a.randbed ~= b.randbed then T.info('   randbed direkt: ' .. b.randbed) end
end

local fall = T.fall

fall('1 Kragarm', function()
    vergleiche('Kragarm biegesteif, F am Ende', function()
        local K = { fixed(node(0)), node(2) }; K[2].last_y = 1
        return K, { bar(1, 2, { biegesteif = true }) }
    end)
end)

fall('2 Federn', function()
    vergleiche('starrer Balken auf drei Federn', function()
        local K = { node(0), node(1), node(2) }
        for _, k in ipairs(K) do k.cy = 1 end
        K[1].lager_x = true
        return K, { bar(1, 2, { q = 1, q_str = '1', biegesteif = true }), bar(2, 3, { q = 1, q_str = '1', biegesteif = true }) }
    end)
end)

fall('3 Rahmenecke', function()
    vergleiche('Rahmenecke, Stuetze biege- und dehnsteif', function()
        return { fixed(node(0, 0)), node(0, -2), roller(node(2, -2)) },
            { bar(1, 2, { biegesteif = true, dehnsteif = true }), bar(2, 3, { q = 1, q_str = '1' }) }
    end)
end)

fall('4 Dehnsteif', function()
    vergleiche('Festlager-Festlager, Stab 1 dehnsteif', function()
        local K = { pinned(node(0)), node(1), pinned(node(2)) }; K[2].last_x = 1
        return K, { bar(1, 2, { dehnsteif = true }), bar(2, 3, { EA = 1 }) }
    end)
end)

fall('5 Symbolisch', function()
    vergleiche('Kragarm 2l, q, zweite Haelfte biegesteif', function()
        return { fixed(node(0)), node(1), node(2) },
            { T.bar(1, 2, { EI = 1, EI_str = 'EI', EA = 1e10, q = 1, q_str = 'q' }),
              T.bar(2, 3, { EI = 1e8, EA = 1e10, q = 1, q_str = 'q', biegesteif = true }) }
    end)
end)

fall('6 Temperatur', function()
    vergleiche('Einfeldtraeger dehnsteif, Erwaermung', function()
        return { pinned(node(0)), roller(node(2)) }, { bar(1, 2, { dehnsteif = true, To = 10, Tu = 10, alpha = 1e-5, h = 0.2 }) }
    end)
    vergleiche('Einfeldtraeger biegesteif, Gradient symbolisch', function()
        return { pinned(node(0)), roller(node(2)) }, { bar(1, 2, temp({ biegesteif = true }, 't1', 't2', 'a', 'h')) }
    end)
    vergleiche('starre Scheibe, Stab 1 erwaermt (symbolisch)', function()
        local K = { pinned(node(0, 0)), pinned(node(0, -2)), roller(node(1, 0)), node(1, -2), node(1, -1) }
        K[1].gelenk, K[2].gelenk = true, true
        K[5].last_x, K[5].last_x_str = 1, 'F'
        return K, {
            bar(1, 3, temp({ EA = 1, EA_str = 'EA', gelenk_B = true }, 'dt', 'dt', 'a')),
            bar(2, 4, { EA = 2, EA_str = '2*EA', gelenk_B = true }),
            bar(3, 5, { biegesteif = true, dehnsteif = true }),
            bar(5, 4, { biegesteif = true, dehnsteif = true }),
        }
    end)
end)

fall('7 Standard-EA dehnstarr', function()
    vergleiche('Zweigelenkrahmen, H und EI symbolisch, Standard-EA dehnstarr', function()
        local K = { pinned(node(0, 1)), node(0, 0), node(1, 0), pinned(node(1, 1)) }
        K[2].last_x, K[2].last_x_str = 1, 'H'
        local S = {}
        for i = 1, 3 do S[i] = T.bar(i, i + 1, { EI = 1, EI_str = 'EI', EA = 1e10 }) end
        return K, S
    end, { dehnstarr = true })
    vergleiche('Rahmenecke numerisch, Standard-EA dehnstarr', function()
        return { fixed(node(0, 0)), node(0, -2), roller(node(2, -2)) },
            { bar(1, 2), bar(2, 3, { q = 1, q_str = '1' }) }
    end, { dehnstarr = true })
end)

-- Klausur Aufgabe 4 (TM2): starrer Balken aus vier Teilstaeben, Drehfeder cm = 3EAl, Stab 1 (EA) nach oben,
-- Stab 2 (2EA) nach unten; gesucht N1 = -16F/9, N2 = 8F/9
local function klausur4(gelenke)
    return function()
        local K = { node(0, 0), node(2, 0), pinned(node(4, 0)), node(6, 0), pinned(node(6, -1)), pinned(node(6, 4)), node(10, 0) }
        K[1].cm, K[1].cm_str = 3, '3*EA*l'
        K[2].last_y, K[2].last_y_str = 1, 'F'
        K[7].last_y, K[7].last_y_str = -1, '-F'
        local function starr() return { biegesteif = true, dehnsteif = true } end
        if gelenke then K[5].gelenk, K[6].gelenk = true, true end
        return K, {
            bar(1, 2, starr()), bar(2, 3, starr()), bar(3, 4, starr()), bar(4, 7, starr()),
            bar(5, 4, { EA = 1, EA_str = 'EA', gelenk_A = gelenke, gelenk_B = gelenke }),
            bar(4, 6, { EA = 2, EA_str = '2*EA', gelenk_A = gelenke, gelenk_B = gelenke }),
        }
    end
end

fall('8 Klausur Aufgabe 4', function()
    vergleiche('Klausur Aufgabe 4, Pendelstaebe (Gelenke)', klausur4(true))
    gleich('N1 = uneu5\' = -16F/9', 'uneu5(1)-uneu5(0)', '-16*f/9')
    gleich('N2 = uneu6\' = 8F/9', 'uneu6(1)-uneu6(0)', '8*f/9')
    vergleiche('Klausur Aufgabe 4, Staebe biegesteif angeschlossen', klausur4(false))
end)

fall('9 Rueckfall', function()
    vergleiche('Festlager-Festlager, beide dehnstarr (starr gegen starr)', function()
        local K = { pinned(node(0)), node(1), pinned(node(2)) }; K[2].last_x = 1
        return K, { bar(1, 2), bar(2, 3) }
    end, { dehnstarr = true }, true)
end)

fall('10 FEM: starre Teile gegenseitig unbestimmt', function()
    T.abschnitt('Diagramme/Lagerkraefte: Aufteilung wie gleich steife starre Staebe, dazu Hinweis')
    local function hinweis()
        for _, h in ipairs(hinweisListe or {}) do if h:find('gegenseitig statisch unbestimmt', 1, true) then return true end end
        return false
    end
    -- zwei dehnstarre Staebe hintereinander zwischen Festlagern, F = 1 in der Mitte
    local K = { pinned(node(0)), node(1), pinned(node(4)) }; K[2].last_x = 1
    local S = { bar(1, 2, { dehnsteif = true }), bar(2, 3, { dehnsteif = true }) }
    if not T.rechne(K, S) then return end
    local st = getStaebe()
    -- gleich steif (EA gleich): Steifigkeit EA/L, Stab 1 (L = 1) ist dreimal so steif wie Stab 2 (L = 3)
    T.zahl('N1 = 3/4 (Zug)', -st[1].s_local[1], 0.75, 1e-9)
    T.zahl('N2 = -1/4 (Druck)', -st[2].s_local[1], -0.25, 1e-9)
    T.wahr('Hinweis: gegenseitig statisch unbestimmt', hinweis(), table.concat(hinweisListe or {}, ' | '))
    -- Reihenfolge der Staebe darf keine Rolle spielen
    K = { pinned(node(0)), node(1), pinned(node(4)) }; K[2].last_x = 1
    S = { bar(2, 3, { dehnsteif = true }), bar(1, 2, { dehnsteif = true }) }
    if not T.rechne(K, S) then return end
    st = getStaebe()
    T.zahl('umgekehrte Stabreihenfolge: N (L = 1) = 3/4', -st[2].s_local[1], 0.75, 1e-9)
    -- Zweifeldtraeger aus starren Staeben (EI, EA gleich): klassisches Ergebnis 3/8, 10/8, 3/8 qL
    K = { pinned(node(0)), roller(node(2)), roller(node(4)) }
    S = { bar(1, 2, { q = 1, q_str = '1', biegesteif = true, dehnsteif = true }),
          bar(2, 3, { q = 1, q_str = '1', biegesteif = true, dehnsteif = true }) }
    if not T.rechne(K, S) then return end
    local kn = getKnoten()
    T.zahl('Zweifeldtraeger starr: Mittellager 5/4 q l', kn[2].R_eta, 2.5, 1e-9)
    T.zahl('Zweifeldtraeger starr: Endlager 3/8 q l', kn[1].R_eta, 0.75, 1e-9)
    T.zahl('Stuetzmoment -q l^2/8', getStaebe()[1].s_local[6], -0.5, 1e-9)
    -- statisch bestimmtes starres System: kein Hinweis
    K = { fixed(node(0)), node(2) }; K[2].last_y = 1
    S = { bar(1, 2, { biegesteif = true, dehnsteif = true }) }
    if not T.rechne(K, S) then return end
    T.wahr('Kragarm starr: kein Hinweis', not hinweis(), table.concat(hinweisListe or {}, ' | '))
end)

T.ende('Starre Staebe direkt')
