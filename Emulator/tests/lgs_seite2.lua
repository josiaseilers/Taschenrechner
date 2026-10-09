-- LGS-Export (ggw_a, ggw_b, ggw_x) passend zur Explosionszeichnung, Seite 2.
-- 1. Jede Unbekannte des LGS steht auf Seite 2 mit demselben Namen und derselben positiven
--    Richtung (bzw. demselben Drehsinn), und jeder Name auf Seite 2 ist eine Unbekannte des LGS.
-- 2. Die Loesung des LGS trifft die Werte der FEM-Rechnung (Seite 1): Lagerkraefte R_xi, R_eta, R_m,
--    Gelenkkraefte = Stabendkraft minus der am Stab angetragenen Knotenlasten und Lager.
-- Aufruf: luajit Emulator/tests/lgs_seite2.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller
local zahl, wahr, fall = T.zahl, T.wahr, T.fall

local gc = setmetatable({}, { __index = function(_, k)
    if k == 'getStringWidth' then return function(_, t) return #tostring(t) * 6 end end
    if k == 'getStringHeight' then return function() return 12 end end
    return function() end
end })

-- Seite 2 zeichnen und protokollieren
local function seite2()
    E2_PROTOKOLL = {}
    ansichtsModus = 'E'; explosionPage = 2
    local ok, err = pcall(on.paint, gc)
    if not ok then T.pruef(false, 'on.paint Absturz: ' .. tostring(err):gsub('\n.*', '')) end
    local p = E2_PROTOKOLL
    E2_PROTOKOLL = nil; ansichtsModus = 'System'; explosionPage = 1
    return p or {}
end

-- Text aus dem LGS als Zahl (Brueche, Wurzeln; Symbole mit ihren Platzhalterwerten)
local function zahlVon(t)
    local v = tonumber(t)
    if v then return v end
    local r = T.ev(t)
    return type(r) == 'number' and r or nil
end

local function loeseLGS()
    local M = lgs_modell
    local n, m = #M.x, #M.A
    if n ~= m then return nil, 'nicht quadratisch: ' .. m .. ' Gleichungen, ' .. n .. ' Unbekannte' end
    local A = {}
    for r = 1, n do
        A[r] = {}
        for c = 1, n do
            A[r][c] = zahlVon(M.A[r][c]); if not A[r][c] then return nil, 'Eintrag ' .. tostring(M.A[r][c]) end
        end
        A[r][n + 1] = zahlVon(M.b[r][1]); if not A[r][n + 1] then return nil, 'rechte Seite ' .. tostring(M.b[r][1]) end
    end
    for k = 1, n do
        local p, best = k, math.abs(A[k][k])
        for i = k + 1, n do if math.abs(A[i][k]) > best then p, best = i, math.abs(A[i][k]) end end
        if best < 1e-12 then return nil, 'singulaer' end
        A[k], A[p] = A[p], A[k]
        for i = k + 1, n do
            local f = A[i][k] / A[k][k]
            for j = k, n + 1 do A[i][j] = A[i][j] - f * A[k][j] end
        end
    end
    local x = {}
    for i = n, 1, -1 do
        local s = A[i][n + 1]
        for j = i + 1, n do s = s - A[i][j] * x[j] end
        x[i] = s / A[i][i]
    end
    return x
end

-- Sollwert einer Unbekannten aus der FEM-Rechnung
local function soll(q)
    local K, S = getKnoten(), getStaebe()
    if q.komp == 'S' then return -S[q.stab].s_local[1] end
    local k = K[q.knoten]
    if not q.stab then
        if q.komp == 'h' then return k.R_xi elseif q.komp == 'v' then return k.R_eta else return k.R_m end
    end
    local s = S[q.stab]
    local k1, k2 = K[s.k1], K[s.k2]
    local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
    local ux, uy = (k2.x - k1.x) / L, (k2.y - k1.y) / L
    -- Bogen: s_local liegt in Richtung der Tangente am jeweiligen Stabende (erstes bzw. letztes Teilstueck)
    local g = bogenGeometrie(s, 2)
    if g then ux, uy = select(3, bogenPunkt(g, (s.k1 == q.knoten) and 0 or g.alpha)) end
    local N, V, M
    if s.k1 == q.knoten then N, V, M = s.s_local[1], s.s_local[2], s.s_local[3]
    else N, V, M = s.s_local[4], s.s_local[5], s.s_local[6] end
    local Fx, Fy = N * ux - V * uy, N * uy + V * ux
    if lastStabKnoten(q.knoten) == q.stab then
        local r = math.rad(-(k.last_w or 0))
        local fx = (k.last_x or 0) * math.cos(r) - (k.last_y or 0) * math.sin(r)
        local fy = (k.last_x or 0) * math.sin(r) + (k.last_y or 0) * math.cos(r)
        local lager = k.lager_x or k.lager_y or k.lager_m or k.cx > 0 or k.cy > 0 or k.cm > 0
        Fx = Fx - fx - (lager and k.Rx_glob or 0)
        Fy = Fy - fy - (lager and k.Ry_glob or 0)
        M = M - (k.last_m or 0) - (lager and k.Rm_glob or 0)
    end
    local d = gelenkRichtung(q.knoten, q.stab)
    if q.komp == 'x' then return Fx * d elseif q.komp == 'y' then return Fy * d
    elseif q.komp == 'n' then return (Fx * ux + Fy * uy) * d
    elseif q.komp == 'q' then return (-Fx * uy + Fy * ux) * d
    else return M * d end
end

local function istUnbekannteName(n)
    return n:match('^[A-Z]_[hv]$') or n:match('^M_[A-Z]$') or n:match('^G[xynqm]_') or n:match('^S_%d')
end

-- System rechnen, LGS bauen, mit Seite 2 und der FEM vergleichen
local function pruefe(titel, K, S, opts, werte)
    T.abschnitt(titel)
    if not T.rechne(K, S, opts) then return end
    local ok, err = pcall(exportLGSMatrixToTI, true)
    if not ok then T.pruef(false, 'LGS-Export Absturz: ' .. tostring(err)); return end
    local M = lgs_modell
    -- Seite 2
    local prot = seite2()
    local namen = {}
    for _, u in ipairs(M.unbekannte) do
        namen[u.name] = true
        for _, e in ipairs(u.eintraege) do
            if not e.koerper.bolzen then
                local da = false
                for _, p in ipairs(prot) do
                    if p.name == u.name then
                        if e.m ~= 0 and p.m == (e.m > 0 and 1 or -1) then da = true end
                        if e.m == 0 and p.dx and math.abs(p.dx - e.fx) < 1e-6 and math.abs(p.dy - e.fy) < 1e-6 then da = true end
                    end
                end
                wahr(string.format('Seite 2 zeigt %s in LGS-Richtung (%.2f, %.2f, %d)', u.name, e.fx, e.fy, e.m), da)
            end
        end
    end
    local fremd = {}
    for _, p in ipairs(prot) do if istUnbekannteName(p.name) and not namen[p.name] then fremd[#fremd + 1] = p.name end end
    wahr('keine Namen auf Seite 2, die im LGS fehlen', #fremd == 0, table.concat(fremd, ', '))
    -- Loesung gegen FEM
    local namenListe = {}
    for _, xl in ipairs(M.x) do namenListe[#namenListe + 1] = xl[1] end
    T.info('   Unbekannte: ' .. table.concat(namenListe, ', '))
    local zugewiesen = {}
    if werte then for k, v in pairs(werte) do math.eval(k .. ':=' .. v); zugewiesen[#zugewiesen + 1] = k end end
    local x, grund = loeseLGS()
    if #zugewiesen > 0 then math.eval('DelVar ' .. table.concat(zugewiesen, ',')) end
    wahr('LGS quadratisch und loesbar', x ~= nil, grund)
    if not x then
        for _, zeile in ipairs(lgs_equations or {}) do T.write('      ' .. zeile .. '\n') end
        return
    end
    for i, u in ipairs(M.unbekannte) do
        zahl(u.name .. ' = FEM', x[i], soll(u.quelle), 1e-6)
    end
    return M
end

fall('1 Dreigelenkrahmen', function()
    -- N1 (0|0) gelenkig, N4 (4|0) gelenkig und um 30 Grad gedreht, Gelenk N5 im Riegel
    local K = { pinned(node(0, 0)), node(0, -3), node(4, -3), pinned(node(4, 0)), node(2, -3) }
    K[4].winkel = 30
    K[5].gelenk = true
    K[2].last_x, K[2].last_y, K[2].last_w = 2, 1, 40
    K[3].last_m = 1.5
    K[5].last_y = 3
    local S = { T.bar(1, 2, { gx = 0.5, gx_str = '0.5' }), T.bar(2, 5, { q = 1, q_str = '1', q_B = 0.5, q_B_str = '0.5' }),
                T.bar(5, 3, { gy = 0.8, gy_str = '0.8', gy_proj = true, m = 0.3, m_str = '0.3' }), T.bar(3, 4, { n = 0.2, n_str = '0.2' }) }
    pruefe('Dreigelenkrahmen: gedrehtes Lager, schraege Last, Moment, alle Streckenlasten', K, S)
end)

fall('2 Gerbertraeger mit Angelenk', function()
    -- Einspannung links, Gelenk am Ende von Stab 1 (Angelenk), Stab 2 biegesteif am Knoten 2, Rolle rechts
    local K = { fixed(node(0)), node(3), roller(node(5)) }
    K[2].last_x, K[2].last_w = 2, -60     -- schraege Last genau am Gelenkknoten
    local S = { T.bar(1, 2, { q = 1, q_str = '1', gelenk_B = true }), T.bar(2, 3, { q = 2, q_str = '2' }) }
    pruefe('Gerbertraeger: Angelenk, Last am Gelenkknoten', K, S)
    -- Lager nicht an Knoten 1: Buchstaben nach getSuppLetter
    K = { node(-1), fixed(node(0)), node(3), roller(node(5)) }
    K[1].last_y = 1
    S = { T.bar(1, 2), T.bar(2, 3, { q = 1, q_str = '1', gelenk_B = true }), T.bar(3, 4, { q = 2, q_str = '2' }) }
    local M = pruefe('Kragarm vorn: Lager an Knoten 2 und 4 heissen A und B', K, S)
    if M then
        local n = {}
        for _, u in ipairs(M.unbekannte) do n[u.name] = true end
        wahr('Lager heissen A und B', n.A_h and n.A_v and n.M_A and n.B_v)
    end
end)

fall('3 Q- und N-Gelenk', function()
    local K = { fixed(node(0)), node(3), roller(node(6)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1' }), T.bar(2, 3, { q = 2, q_str = '2', q_gelenk_A = true }) }
    pruefe('Querkraftgelenk am Anfang von Stab 2', K, S)
    K = { fixed(node(0)), node(3), node(6) }
    K[3].lager_x = true
    K[3].last_x = 1
    S = { T.bar(1, 2, { q = 1, q_str = '1' }), T.bar(2, 3, { q = 2, q_str = '2', n_gelenk_A = true }) }
    pruefe('Normalkraftgelenk am Anfang von Stab 2, Lager in Stabrichtung', K, S)
end)

fall('4 Vollgelenk, beide Staebe beginnen dort', function()
    -- Dreigelenkbogen: beide Staebe laufen vom Scheitel weg (Stabanfang am Gelenk)
    local K = { node(2, -2), pinned(node(0, 0)), pinned(node(4, 0)) }
    K[1].gelenk = true
    K[1].last_x, K[1].last_y = 1, 2
    local S = { T.bar(1, 2, { q = 1, q_str = '1' }), T.bar(1, 3, { gy = 1, gy_str = '1' }) }
    pruefe('Dreigelenkbogen, Actio = Reactio am Scheitel', K, S)
end)

fall('5 Gelenk mit drei Staeben', function()
    -- Vollgelenk mit drei Staeben: je Stab eigene Gelenkkraefte plus Gelenkbolzen
    -- Stab 3 senkrecht nach oben, oben waagerecht gehalten (Lager quer zum Stab)
    local K = { node(0, -2), pinned(node(-2, 0)), pinned(node(2, 0)), node(0, -4) }
    K[4].lager_x = true
    K[1].gelenk = true
    K[1].last_x = 1
    local S = { T.bar(1, 2, { q = 1, q_str = '1' }), T.bar(1, 3, { q = 1, q_str = '1' }), T.bar(1, 4, { gx = 0.5, gx_str = '0.5' }) }
    pruefe('Vollgelenk mit drei Staeben (Gelenkbolzen)', K, S)
    -- zwei Gelenkstaebe und ein biegesteifer Rest (Stuetze eingespannt)
    K = { fixed(node(0, 0)), node(0, -3), roller(node(-3, -3)), roller(node(3, -3)) }
    K[2].last_x = 2
    S = { T.bar(1, 2), T.bar(3, 2, { q = 1, q_str = '1', gelenk_B = true }), T.bar(2, 4, { q = 2, q_str = '2', gelenk_A = true }) }
    pruefe('Zwei Angelenke an einer eingespannten Stuetze', K, S)
end)

fall('6 Fachwerk', function()
    local K = { pinned(node(0, 0)), roller(node(4, 0)), node(2, -2), node(2, 0) }
    for _, k in ipairs(K) do k.gelenk = true end
    K[2].winkel = 20
    K[3].last_x, K[3].last_w = 2, 30
    K[4].last_y = 3
    local S = { T.bar(1, 4), T.bar(4, 2), T.bar(1, 3), T.bar(3, 2), T.bar(3, 4) }
    fachwerkModus = true
    pruefe('Fachwerk: gedrehtes Lager, schraege Knotenlast', K, S)
    fachwerkModus = false
end)

fall('7 Symbolisch', function()
    local K = { pinned(node(0, 0)), node(0, -2), node(4, -2), pinned(node(4, 0)), node(2, -2) }
    K[5].gelenk = true
    K[2].last_x, K[2].last_x_str = 1, 'F'
    local S = { T.bar(1, 2), T.bar(2, 5, { q = 1, q_str = 'q' }), T.bar(5, 3), T.bar(3, 4) }
    for _, s in ipairs(S) do s.EI_str, s.EA_str = 'EI', 'EA' end
    local M = pruefe('Dreigelenkrahmen symbolisch (F, q, l)', K, S, nil, { f = 1, q = 1, l = 1 })
    if M then
        local alles = ''
        for r = 1, #M.A do alles = alles .. table.concat(M.A[r], ' ') .. ' ' .. M.b[r][1] .. ' ' end
        wahr('LGS enthaelt F, q und l', alles:find('f') ~= nil and alles:find('q') ~= nil and alles:find('l') ~= nil, alles:sub(1, 200))
    end
end)

fall('8 Dreigelenkbogen mit Bogenlasten', function()
    -- zwei Viertelkreise R = 2, Scheitelgelenk; Lasten auf den Boegen gehen als Resultierende (Kraft am
    -- Stabanfang plus Moment, verteilt wie in der FEM) in das LGS
    local K = { pinned(node(0, 0)), node(2, -2), pinned(node(4, 0)) }
    K[2].gelenk = true
    K[2].last_x = 1
    local S = { T.bar(1, 2, { bogen_r = 2, gy = 1.5, gy_str = '1.5', q = 1, q_str = '1', m = 0.5, m_str = '0.5' }),
                T.bar(2, 3, { bogen_r = 2, gx_str = 'x', gy = 2, gy_str = '2', gy_proj = true, n_A = 1, n_B = -1 }) }
    pruefe('Dreigelenkbogen: q, n-Trapez, p_X(x), p_Y (auch projiziert), m auf den Boegen', K, S)
end)

T.ende('LGS zu Seite 2')
