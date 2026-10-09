-- Globale Linienlasten p_X(x), p_Y(x), die von x abhaengen.
-- Laufvariable: projiziert entlang der globalen Achse ab dem Stabanfang (p_Y waagerecht, p_X
-- senkrecht), sonst entlang der Stabachse. Geprueft wird ueber gleichwertige Lasten: eine
-- projizierte Last p(X) mit X = f*x wirkt je Stablaenge wie die nicht projizierte Last f*p(f*x).
-- Aufruf: luajit Emulator/tests/globallast.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller = T.node, T.fixed, T.pinned, T.roller
local zahl, wahr, fall = T.zahl, T.wahr, T.fall

-- Auflagerkraefte und Stabendkraefte eines Systems
local function ergebnis(K, S)
    if not T.rechne(K, S) then return nil end
    local r = { knoten = {}, staebe = {} }
    for i, k in ipairs(getKnoten()) do r.knoten[i] = { k.R_xi or 0, k.R_eta or 0, k.R_m or 0 } end
    for i, s in ipairs(getStaebe()) do r.staebe[i] = { unpack(s.s_local) } end
    return r
end

local function vergleiche(titel, a, b)
    if not a or not b then T.pruef(false, titel .. ': keine Rechnung'); return end
    local maxd, skala = 0, 1e-9
    for i = 1, #a.knoten do for j = 1, 3 do
        maxd = math.max(maxd, math.abs(a.knoten[i][j] - b.knoten[i][j])); skala = math.max(skala, math.abs(b.knoten[i][j]))
    end end
    for i = 1, #a.staebe do for j = 1, 6 do
        maxd = math.max(maxd, math.abs(a.staebe[i][j] - b.staebe[i][j])); skala = math.max(skala, math.abs(b.staebe[i][j]))
    end end
    T.pruef(maxd <= 1e-6 * skala, string.format('%-60s max. Abweichung %.3g (Groesse %.3g)', titel, maxd, skala))
end

-- schraeger Stab 3-4-5: Knoten 1 unten links gelenkig, Knoten 2 oben rechts Rollenlager (senkrecht)
local function schraeg(felder)
    local K = { pinned(node(0, 0)), roller(node(3, -4)) }
    local S = { T.bar(1, 2, felder) }
    return K, S
end

fall('1 p_Y(x) auf waagerechtem Stab = q(x)', function()
    T.abschnitt('Waagerechter Einfeldtraeger: p_Y = x (nicht projiziert) wirkt wie q = x')
    local a = ergebnis({ pinned(node(0)), roller(node(4)) }, { T.bar(1, 2, { gy_str = 'x' }) })
    local b = ergebnis({ pinned(node(0)), roller(node(4)) }, { T.bar(1, 2, { q_str = 'x' }) })
    vergleiche('p_Y = x gegen q = x', a, b)
    -- Handrechnung: Dreieckslast 0..4, R = 8, Lagerkraefte L^2/6 und L^2/3 (nach oben)
    if a then
        zahl('A_v = L^2/6', a.knoten[1][2], 16 / 6)
        zahl('B_v = L^2/3', a.knoten[2][2], 16 / 3)
    end
    -- frueher fehlte die Last in der Rechnung ganz (s.gy = 0 bei einem Text mit x)
    wahr('Last kommt in der Rechnung an', a and math.abs(a.knoten[1][2]) > 1)
end)

fall('2 p_Y projiziert auf schraegem Stab', function()
    T.abschnitt('p_Y = x projiziert (x waagerecht 0..3) = nicht projiziert 9/25*x (x entlang Stab 0..5)')
    local a = ergebnis(schraeg({ gy_str = 'x', gy_proj = true }))
    local b = ergebnis(schraeg({ gy_str = '9/25*x' }))
    vergleiche('projiziert gegen gleichwertig', a, b)
    -- Handrechnung: senkrechte Gesamtlast int_0^3 X dX = 4.5 bei X = 2 -> B_v = 4.5*2/3 = 3, A_v = 1.5
    if a then
        zahl('A_v = 1.5', a.knoten[1][2], 1.5)
        zahl('B_v = 3', a.knoten[2][2], 3)
    end
    -- nicht projiziert: int_0^5 x dx = 12.5 bei s = 10/3, waagerecht 2 -> B_v = 25/3
    local c = ergebnis(schraeg({ gy_str = 'x' }))
    if c then zahl('nicht projiziert: B_v = 12.5*2/3', c.knoten[2][2], 25 / 3) end
end)

fall('3 p_X projiziert auf schraegem Stab', function()
    T.abschnitt('p_X = x^2 projiziert (x senkrecht 0..4) = nicht projiziert 4/5*(4/5*x)^2')
    local a = ergebnis(schraeg({ gx_str = 'x^2', gx_proj = true }))
    local b = ergebnis(schraeg({ gx_str = '4/5*(4/5*x)^2' }))
    vergleiche('projiziert gegen gleichwertig', a, b)
    -- Gesamtlast int_0^4 X^2 dX = 64/3 nach rechts: das Festlager haelt sie, R_xi = -64/3
    if a then zahl('A_h = -64/3', a.knoten[1][1], -64 / 3) end
end)

fall('4 gemischt mit konstantem Anteil und q', function()
    T.abschnitt('konstantes q und p_X, dazu p_Y(x) projiziert: alles zusammen im CAS-Pfad')
    local a = ergebnis(schraeg({ q = 1, q_str = '1', gx = 2, gx_str = '2', gy_str = '1+x', gy_proj = true }))
    local b = ergebnis(schraeg({ q = 1, q_str = '1', gx = 2, gx_str = '2', gy_str = '3/5*(1+3/5*x)' }))
    vergleiche('gemischt: projiziert gegen gleichwertig', a, b)
end)

fall('5 Arbeitssatz und Rand-LGS', function()
    T.abschnitt('PvV-Arbeitssatz und Rand-LGS mit projizierter p_Y(x)')
    local K, S = schraeg({ gy_str = 'x', gy_proj = true })
    if not T.rechne(K, S) then return end
    local Bv = getKnoten()[2].R_eta
    -- Rollenlager loesen: V in eta-Richtung (nach unten) = -R_eta
    pvvFreigabe(2, 2)
    local _, e2 = exportArbeitssatzToTI(true)
    pvvEnde()
    local basis = e2:gsub('φ_0', '1'):gsub('δ_0', '1')
    local a0 = T.ev((basis:gsub('%f[%w_]V%f[^%w_]', '(0)')))
    local a1 = T.ev((basis:gsub('%f[%w_]V%f[^%w_]', '(1)')))
    local V = (type(a0) == 'number' and type(a1) == 'number' and a1 ~= a0) and -a0 / (a1 - a0) or nil
    zahl('Arbeitssatz: V = -B_v (FEM)', V, -Bv, 1e-6)
    -- Rand-LGS: gleichwertige nicht projizierte Last muss dieselbe Biegelinie geben
    if not T.randLGS() then return end
    local w1 = T.ev('wv1(2.5)')
    T.rechne(schraeg({ gy_str = '9/25*x' }))
    if not T.randLGS() then return end
    local w2 = T.ev('wv1(2.5)')
    zahl('Rand-LGS: w(2.5) projiziert = gleichwertig', w1, w2, 1e-9)
    wahr('  Biegelinie nicht null', type(w1) == 'number' and math.abs(w1) > 1e-9, w1)
end)

T.ende('Globale Linienlasten')
