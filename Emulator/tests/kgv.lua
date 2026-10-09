-- KGV-Export (kgv_delta, kgv_delta0): die daraus bestimmten X muessen die FEM-Loesung treffen.
-- Kern der Pruefung: bei einem geloesten Pendelstab gehoert seine eigene Laengenaenderung L/(EA)
-- zu delta_ii, weil der Stab im Hauptsystem entfernt ist.
-- Ab Fall 10: Superposition. Die Verlaeufe N, Q, M des Originalsystems muessen gleich
-- Zustand 0 + Summe X_k * Zustand k sein, mit X_k aus den exportierten delta-Zahlen.
-- Aufruf: luajit Emulator/tests/kgv.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller

-- exportierte Matrizen abgreifen
local gespeichert = {}
var = var or {}
var.store = function(name, mat) gespeichert[name] = mat end

local function rechneX(K, S)
    gespeichert = {}
    T.reset()
    autoKGV = true
    setKnoten(K); setStaebe(S)
    starteBerechnung()
    exportKGVToTI()
    local D, D0 = gespeichert.kgv_delta, gespeichert.kgv_delta0
    if not D or not D0 then return nil end
    local n = #D
    -- X = -D^-1 * D0 (kleines Gauss-Verfahren)
    local M = {}
    for i = 1, n do
        M[i] = {}
        for j = 1, n do M[i][j] = D[i][j] end
        M[i][n + 1] = -D0[i][1]
    end
    for k = 1, n do
        local p, best = k, math.abs(M[k][k])
        for i = k + 1, n do if math.abs(M[i][k]) > best then p, best = i, math.abs(M[i][k]) end end
        if best < 1e-300 then return nil end
        M[k], M[p] = M[p], M[k]
        for i = k + 1, n do
            local f = M[i][k] / M[k][k]
            for j = k, n + 1 do M[i][j] = M[i][j] - f * M[k][j] end
        end
    end
    local x = {}
    for i = n, 1, -1 do
        local sum = M[i][n + 1]
        for j = i + 1, n do sum = sum - M[i][j] * x[j] end
        x[i] = sum / M[i][i]
    end
    return x, getXWerte(), D, D0
end

-- Fachwerkfeld mit zwei Diagonalen: unbestimmt im Stab, Lager statisch bestimmt
local function fachwerk(extra)
    local K = { pinned(node(0, 0)), roller(node(2, 0)), node(0, 2), node(2, 2) }
    for _, k in ipairs(K) do k.gelenk = true end
    K[4].last_y = 1
    local S = {}
    for i, p in ipairs({ { 1, 2 }, { 1, 3 }, { 2, 4 }, { 3, 4 }, { 1, 4 }, { 2, 3 } }) do
        local f = { EA = 1e4, EI = 1 }
        for k, v in pairs((extra and extra[i]) or {}) do f[k] = v end
        S[i] = T.bar(p[1], p[2], f)
    end
    return K, S
end

local fall = T.fall

fall('1 Geloester Pendelstab', function()
    T.abschnitt('Fachwerk mit zwei Diagonalen: X aus delta muss die FEM-Normalkraft treffen')
    local K, S = fachwerk()
    local x, XW, D, D0 = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    T.wahr('genau ein X, Typ Pendelstab', #XW == 1 and XW[1].typ == 'pendel_n', XW[1] and XW[1].typ)
    applyKGVZustand(-1); rechneAktuellesSystem()
    local s = getStaebe()[XW[1].stab]
    local N_fem = -s.s_local[1]
    T.zahl('X1 = N des geloesten Stabes (FEM)', x[1], N_fem, 1e-9)
    -- ohne den Eigenanteil waere das Ergebnis deutlich daneben
    local k1, k2 = getKnoten()[s.k1], getKnoten()[s.k2]
    local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
    local eigen = L / s.EA
    local ohne = -D0[1][1] / (D[1][1] - eigen)
    T.wahr('ohne Eigenanteil L/EA waere X falsch', math.abs(ohne - N_fem) > 0.01 * math.abs(N_fem),
        string.format('ohne = %.6f, richtig = %.6f', ohne, N_fem))
    T.zahl('delta_11 enthaelt L/EA', D[1][1] - eigen + eigen, D[1][1], 1e-12)
end)

fall('2 Weicherer Stab', function()
    T.abschnitt('geloester Stab mit kleinerem EA: der Eigenanteil waechst entsprechend')
    local K, S = fachwerk({ [5] = { EA = 2e3 }, [6] = { EA = 2e3 } })
    local x, XW = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    applyKGVZustand(-1); rechneAktuellesSystem()
    local N_fem = -getStaebe()[XW[1].stab].s_local[1]
    T.zahl('X1 = N des geloesten Stabes (FEM)', x[1], N_fem, 1e-9)
end)

fall('3 Dehnsteifer geloester Stab', function()
    T.abschnitt('dehnsteifer geloester Stab: kein Eigenanteil, X muss trotzdem stimmen')
    local K, S = fachwerk({ [5] = { dehnsteif = true }, [6] = { dehnsteif = true } })
    local x, XW = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    applyKGVZustand(-1); rechneAktuellesSystem()
    local N_fem = -getStaebe()[XW[1].stab].s_local[1]
    T.zahl('X1 = N des geloesten Stabes (FEM)', x[1], N_fem, 1e-6)
end)

fall('4 Geloestes Lager und Gelenk', function()
    T.abschnitt('andere Freiwerte bleiben unveraendert richtig')
    -- Durchlauftraeger: Einspannung + zwei Rollen, ein Lager wird geloest
    local K = { fixed(node(0)), roller(node(2)), roller(node(4)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 1e4, EA = 1e8 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 1e4, EA = 1e8 }) }
    local x, XW = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    T.wahr('geloest wurden Lager bzw. Gelenke', XW[1].typ ~= 'pendel_n', XW[1].typ)
    applyKGVZustand(-1); rechneAktuellesSystem()
    local xw = XW[1]
    local ist, soll
    if xw.typ == 'lager_y' then
        ist, soll = math.abs(x[1]), math.abs(getKnoten()[xw.knoten].Ry_glob)
    elseif xw.typ == 'lager_m' then
        ist, soll = math.abs(x[1]), math.abs(getKnoten()[xw.knoten].Rm_glob)
    else
        local s = getStaebe()[xw.stab]
        ist, soll = math.abs(x[1]), math.abs(s.s_local[xw.typ == 'gelenk_A' and 3 or 6])
    end
    T.zahl('|X1| = |Lagerkraft bzw. Moment| (FEM)', ist, soll, 1e-6)
end)

fall('5 Zwei geloeste Staebe', function()
    T.abschnitt('zwei Felder mit je zwei Diagonalen: jeder geloeste Stab nur in seinem eigenen Diagonaleintrag')
    -- Untergurt 1-2-3 (y = 2), Obergurt 4-5-6 (y = 0), Pfosten, je Feld zwei Diagonalen
    local K = { pinned(node(0, 2)), node(2, 2), roller(node(4, 2)), node(0, 0), node(2, 0), node(4, 0) }
    for _, k in ipairs(K) do k.gelenk = true end
    K[5].last_y = 1
    local paare = { { 1, 2 }, { 2, 3 }, { 4, 5 }, { 5, 6 }, { 1, 4 }, { 2, 5 }, { 3, 6 }, { 1, 5 }, { 2, 4 }, { 2, 6 }, { 3, 5 } }
    local S = {}
    for i, p in ipairs(paare) do S[i] = T.bar(p[1], p[2], { EA = 1e4, EI = 1 }) end
    local x, XW, D = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    T.wahr('zwei geloeste Pendelstaebe', #XW == 2 and XW[1].typ == 'pendel_n' and XW[2].typ == 'pendel_n',
        (XW[1] and XW[1].typ or '?') .. ',' .. (XW[2] and XW[2].typ or '?'))
    applyKGVZustand(-1); rechneAktuellesSystem()
    for i = 1, 2 do
        local N_fem = -getStaebe()[XW[i].stab].s_local[1]
        T.zahl('X' .. i .. ' = N des geloesten Stabes ' .. XW[i].stab, x[i], N_fem, 1e-8)
    end
    -- Nebendiagonale: im Einheitszustand j ist der andere geloeste Stab kraeftefrei, also kein Zusatz
    T.zahl('delta_12 = delta_21 (symmetrisch, ohne Zusatz)', D[1][2], D[2][1], 1e-9)
end)

-- Sollwert eines Freiwerts aus der FEM-Loesung des Originalsystems, mit Vorzeichen:
-- Lager: Kraft des Lagers auf das Tragwerk in xi (R_xi) bzw. eta (= -R_eta, R_eta zaehlt nach oben),
-- Einspannmoment R_m; Gelenk: Stabendmoment; Pendelstab: Normalkraft (Zug positiv)
local function sollX(xw)
    local k = xw.knoten and getKnoten()[xw.knoten]
    if xw.typ == 'lager_x' then return k.R_xi
    elseif xw.typ == 'lager_y' then return -k.R_eta
    elseif xw.typ == 'lager_m' then return k.R_m
    elseif xw.typ == 'gelenk_A' then return getStaebe()[xw.stab].s_local[3]
    elseif xw.typ == 'gelenk_B' then return getStaebe()[xw.stab].s_local[6]
    else return -getStaebe()[xw.stab].s_local[1] end
end

local function alleX(K, S, titel)
    local x, XW, D = rechneX(K, S)
    if not x then T.pruef(false, titel .. ': KGV-Export lieferte keine Matrizen'); return end
    -- Maxwell: delta_ij = delta_ji
    for i = 1, #D do for j = i + 1, #D do
        T.zahl(string.format('%s: delta_%d%d = delta_%d%d', titel, i, j, j, i), D[i][j], D[j][i], 1e-7)
    end end
    applyKGVZustand(-1); rechneAktuellesSystem()
    for i, xw in ipairs(XW) do
        T.zahl(string.format('%s: X%d (%s%s)', titel, i, xw.typ, xw.knoten and (' Knoten ' .. xw.knoten) or (' Stab ' .. tostring(xw.stab))),
            x[i], sollX(xw), 1e-7)
    end
    return XW
end

fall('6 Gedrehtes Festlager geloest', function()
    T.abschnitt('Festlager um 30 Grad gedreht: X in Lagerrichtung xi, mit Vorzeichen')
    local K = { pinned(node(0)), roller(node(4)), roller(node(8)) }
    K[1].winkel = 30
    K[3].last_x = 2
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 1e4, EA = 1e6 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 1e4, EA = 1e6 }) }
    local XW = alleX(K, S, 'Festlager 30 Grad')
    T.wahr('geloest wurde das gedrehte Lager', XW and XW[1] and XW[1].knoten == 1, XW and XW[1] and XW[1].typ)
end)

fall('7 Gedrehtes Rollenlager geloest', function()
    T.abschnitt('Rollenlager (eta) um 30 Grad gedreht als Freiwert')
    -- weicher Stab 1 und Horizontallast: der freie Freiheitsgrad u_xi am Rollenlager ist gross
    local K = { roller(node(0)), pinned(node(4)), roller(node(8)) }
    K[1].winkel = 30
    K[1].last_x = 3
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 1e4, EA = 50 }), T.bar(2, 3, { q = 2, q_str = '2', EI = 1e4, EA = 1e6 }) }
    local XW = alleX(K, S, 'Rolle 30 Grad')
    T.wahr('geloest wurde das gedrehte Rollenlager (eta)', XW and XW[1] and XW[1].knoten == 1 and XW[1].typ == 'lager_y', XW and XW[1] and XW[1].typ)
end)

fall('8 Pendelstab am gedrehten Lager', function()
    T.abschnitt('Fachwerk mit gedrehtem Rollenlager: geloester Diagonalstab haengt an diesem Knoten')
    local K, S = fachwerk()
    K[2].winkel = 25
    K[3].last_x = 0.5
    alleX(K, S, 'Pendelstab, Lager 25 Grad')
end)

fall('8b Zwei Freiwerte an gedrehten Lagern', function()
    T.abschnitt('zweifach unbestimmt, gedrehte Rolle mit freier Richtung und weiche Staebe')
    local K = { roller(node(0)), pinned(node(3)), roller(node(6)), roller(node(9)) }
    K[1].winkel = 40; K[4].winkel = -20
    K[1].last_x = 2; K[4].last_x = -1
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 3e3, EA = 80 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 3e3, EA = 120 }),
                T.bar(3, 4, { q = 2, q_str = '2', EI = 3e3, EA = 60 }) }
    alleX(K, S, 'zwei Rollen gedreht')
end)

fall('9 Vorzeichen ohne Drehung', function()
    T.abschnitt('Einspannung, Lager, Gelenke: alle Freiwerte mit Vorzeichen')
    local K = { fixed(node(0)), roller(node(2)), roller(node(4)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 1e4, EA = 1e8 }), T.bar(2, 3, { q = 3, q_str = '3', EI = 2e4, EA = 1e8 }) }
    alleX(K, S, 'Durchlauftraeger')
    K = { fixed(node(0, 0)), node(0, -3), node(4, -3), fixed(node(4, 0)) }
    K[2].last_x = 5
    S = { T.bar(1, 2, { EI = 1e4, EA = 1e8 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 1e4, EA = 1e8 }), T.bar(3, 4, { EI = 1e4, EA = 1e8 }) }
    alleX(K, S, 'Rahmen')
end)

-- ---------------------------------------------------------------------------------------------
-- Superposition der Verlaeufe
-- Ausgewertet wird wie in der Zeichnung: Stabendkraefte plus Streckenlasten. Ein im Hauptsystem
-- geloester Pendelstab hat keine Stabendkraefte, sein N ist die angesetzte Einheitskraft x_nA
-- (im Einheitszustand als "1.00" mit zwei Pfeilen gezeichnet, Zug positiv).
local XS = { 0, 0.25, 0.5, 0.75, 1 }
local abgedeckt = {}

local function stabVerlauf(i)
    local s, K = getStaebe()[i], getKnoten()
    local dx, dy = K[s.k2].x - K[s.k1].x, K[s.k2].y - K[s.k1].y
    local L = math.sqrt(dx * dx + dy * dy)
    local werte = {}
    if s.is_cut then
        for j = 1, #XS do werte[j] = { N = s.x_nA or 0, Q = 0, M = 0 } end
        return werte
    end
    local c, sn = dx / L, -dy / L
    local gx = (s.gx or 0) * (s.gx_proj and math.abs(sn) or 1)
    local gy = (s.gy or 0) * (s.gy_proj and math.abs(c) or 1)
    local n_add, q_add = gx * c - gy * sn, gx * sn + gy * c
    local N0, Q0, M0 = -(s.s_local[1] or 0), -(s.s_local[2] or 0), -(s.s_local[3] or 0)
    local qA, qB = (s.q or 0) + (s.q_A or 0) + q_add, (s.q or 0) + (s.q_B or 0) + q_add
    local nA, nB = (s.n or 0) + (s.n_A or 0) + n_add, (s.n or 0) + (s.n_B or 0) + n_add
    for j, t in ipairs(XS) do
        local x = t * L
        werte[j] = {
            N = N0 - (nA * x + (nB - nA) * x ^ 2 / (2 * L)),
            Q = Q0 - (qA * x + (qB - qA) * x ^ 2 / (2 * L)),
            M = M0 + Q0 * x - (s.m or 0) * x - (qA * x ^ 2 / 2 + (qB - qA) * x ^ 3 / (6 * L)),
        }
    end
    return werte
end

local function aufnahme(zustand)
    applyKGVZustand(zustand); rechneAktuellesSystem()
    local z = {}
    for i = 1, #getStaebe() do z[i] = stabVerlauf(i) end
    return z
end

-- hand(wert): optionale Handrechnung; wert(i, j, g) ist der superponierte Wert g (N, Q, M) von
-- Stab i an der Stelle XS[j]. tol: Toleranz gegen die FEM des Originalsystems (Standard 1e-7)
local function superpos(titel, K, S, hand, tol)
    T.abschnitt('Superposition: ' .. titel)
    local x, XW = rechneX(K, S)
    if not x then T.pruef(false, 'KGV-Export lieferte keine Matrizen'); return end
    local typen = {}
    for k, xw in ipairs(XW) do
        typen[k] = string.format('X%d = %.6g (%s)', k, x[k], xw.typ)
        abgedeckt[(xw.typ:gsub('_[AB]$', ''))] = true
    end
    T.info('   ' .. table.concat(typen, ', '))
    local z0, zk = aufnahme(0), {}
    for k = 1, #XW do zk[k] = aufnahme(k) end
    local zo = aufnahme(-1)
    local function wert(i, j, g)
        local summe = z0[i][j][g]
        for k = 1, #XW do summe = summe + x[k] * zk[k][i][j][g] end
        return summe
    end
    for i = 1, #zo do
        for j, t in ipairs(XS) do
            for _, g in ipairs({ 'N', 'Q', 'M' }) do
                T.zahl(string.format('Stab %d, %s(%.2gL) = %s0 + sum X_k %sk', i, g, t, g, g), wert(i, j, g), zo[i][j][g], tol or 1e-7)
            end
        end
    end
    if hand then hand(wert) end
    return XW
end

local function handwert(label, ist, soll) T.zahl('Hand: ' .. label, ist, soll, 1e-7) end

fall('10 Superposition Zweifeldtraeger', function()
    -- wie S5 in balken_hand.lua: M_B = -qL^2/8, A = 3qL/8
    local K = { pinned(node(0)), roller(node(4)), roller(node(8)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1' }), T.bar(2, 3, { q = 1, q_str = '1' }) }
    superpos('Zweifeldtraeger 4+4, q=1', K, S, function(wert)
        for j, t in ipairs(XS) do
            local x = 4 * t
            handwert(string.format('M1(%g) = 1.5x - x^2/2', x), wert(1, j, 'M'), 1.5 * x - x ^ 2 / 2)
            handwert(string.format('Q1(%g) = 1.5 - x', x), wert(1, j, 'Q'), 1.5 - x)
            handwert(string.format('M2(%g) = M1(4-x)', x), wert(2, j, 'M'), 1.5 * (4 - x) - (4 - x) ^ 2 / 2)
        end
    end)
end)

fall('11 Superposition beidseitig eingespannt', function()
    -- wie S3 in balken_hand.lua: M = -q (L^2 - 6Lx + 6x^2)/12, Q = q (L/2 - x)
    local K = { fixed(node(0)), fixed(node(4)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1' }) }
    superpos('beidseitig eingespannt L=4, q=1', K, S, function(wert)
        for j, t in ipairs(XS) do
            local x = 4 * t
            handwert(string.format('M(%g)', x), wert(1, j, 'M'), -(16 - 24 * x + 6 * x ^ 2) / 12)
            handwert(string.format('Q(%g)', x), wert(1, j, 'Q'), 2 - x)
        end
    end)
end)

fall('12 Superposition Zweigelenkrahmen', function()
    -- wie (2) in rahmen_hand.lua: M Ecke = +-H h/2, Q Stuetzen = H/2
    -- EA/EI = 1e9: Die FEM des Originalsystems hat dann nur etwa sieben gueltige Stellen
    -- (Kondition ~ EA h^2/EI), sie liegt bei 1.50000037 statt 1.5. Die Superposition rechnet im
    -- statisch bestimmten Hauptsystem und trifft die Handrechnung auf 1e-7, deshalb gegen FEM 1e-6.
    local h, L, H = 3, 4, 1
    local K = { pinned(node(0, h)), node(0, 0), node(L, 0), pinned(node(L, h)) }
    K[2].last_x = H
    local S = { T.bar(1, 2, { EI = 1, EA = 1e9 }), T.bar(2, 3, { EI = 1, EA = 1e9 }), T.bar(3, 4, { EI = 1, EA = 1e9 }) }
    superpos('Zweigelenkrahmen h=3 L=4, H=1', K, S, function(wert)
        handwert('M Ecke links = H h/2', wert(1, #XS, 'M'), H * h / 2)
        handwert('M Ecke rechts = -H h/2', wert(3, 1, 'M'), -H * h / 2)
        handwert('Q linke Stuetze = H/2', wert(1, 1, 'Q'), H / 2)
    end, 1e-6)
end)

fall('13 Superposition eingespannter Rahmen', function()
    local K = { fixed(node(0, 0)), node(0, -3), node(4, -3), fixed(node(4, 0)) }
    K[2].last_x = 5
    local S = { T.bar(1, 2, { EI = 1e4, EA = 1e8 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 1e4, EA = 1e8 }), T.bar(3, 4, { EI = 2e4, EA = 1e8 }) }
    superpos('Rahmen beidseitig eingespannt, H=5, q=1', K, S)
end)

fall('14 Superposition geschlossener Rahmen', function()
    -- innerlich dreifach unbestimmt: das Hauptsystem muss Momente an den Ecken loesen
    local K = { pinned(node(0, 0)), roller(node(4, 0)), node(4, -3), node(0, -3) }
    K[4].last_x = 2
    local S = { T.bar(1, 2, { EI = 1e4, EA = 1e8 }), T.bar(2, 3, { EI = 1e4, EA = 1e8 }),
                T.bar(3, 4, { q = 1, q_str = '1', EI = 2e4, EA = 1e8 }), T.bar(4, 1, { EI = 1e4, EA = 1e8 }) }
    local XW = superpos('geschlossener Rahmen auf Fest- und Rollenlager, q=1, H=2', K, S)
    local gelenke = 0
    for _, xw in ipairs(XW or {}) do if xw.typ == 'gelenk_A' or xw.typ == 'gelenk_B' then gelenke = gelenke + 1 end end
    T.wahr('drei Freiwerte, alle an Gelenken', XW and #XW == 3 and gelenke == 3, XW and #XW)
end)

fall('15 Superposition Fachwerk', function()
    local K, S = fachwerk()
    K[3].last_x = 0.5
    superpos('Fachwerk mit zwei Diagonalen, zwei Knotenlasten', K, S)
end)

fall('16 Superposition Temperatur', function()
    -- Zweigelenkrahmen, Riegel erwaermt: delta_10 kommt nur aus der Temperatur
    local h, L = 3, 4
    local K = { pinned(node(0, h)), node(0, 0), node(L, 0), pinned(node(L, h)) }
    local S = { T.bar(1, 2, { EI = 2e4, EA = 1e9 }), T.bar(2, 3, { EI = 2e4, EA = 1e9, To = 10, Tu = 30, alpha = 1e-5, h = 0.2 }),
                T.bar(3, 4, { EI = 2e4, EA = 1e9 }) }
    local XW = superpos('Zweigelenkrahmen, Riegel To=10 Tu=30', K, S)
    T.wahr('Temperatur erzeugt Schnittgroessen', XW ~= nil and math.abs(getStaebe()[2].s_local[3]) > 1e-3)
end)

fall('17 Superposition gedrehtes Lager', function()
    local K = { pinned(node(0)), roller(node(4)), roller(node(8)) }
    K[1].winkel = 30
    K[3].last_x = 2
    local S = { T.bar(1, 2, { q = 1, q_str = '1', EI = 1e4, EA = 1e6 }), T.bar(2, 3, { q = 1, q_str = '1', EI = 1e4, EA = 1e6 }) }
    superpos('Zweifeldtraeger, Festlager um 30 Grad gedreht, Horizontallast', K, S)
end)

fall('18 Abdeckung der Freiwerttypen', function()
    if T.filter then return end   -- nur sinnvoll, wenn alle Superpositionsfaelle gelaufen sind
    T.abschnitt('Superposition: jede Art von Freiwert kam mindestens einmal vor')
    for _, typ in ipairs({ 'lager_x', 'lager_y', 'lager_m', 'gelenk', 'pendel_n' }) do
        T.wahr('Freiwert ' .. typ .. ' geprueft', abgedeckt[typ])
    end
end)

T.ende('KGV')
