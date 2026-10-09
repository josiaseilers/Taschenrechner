-- Lasten auf Boegen gegen Handrechnung: q (radial), n (tangential), Trapez, globale Linienlasten
-- p_X/p_Y (auch projiziert), Momentenlast m, Temperatur, Lastfunktionen mit x = Winkel ab Stabanfang.
-- Der Bogen wird fuer die Rechnung in Teilstaebe zerlegt (bogenSegmente); Werte, die vom Polygon
-- abhaengen, werden mit einer Toleranz passend zur Teilung geprueft, die exakten Faelle eng.
-- Frueher bekamen die Teilstaebe keine Lasten: der Elternstab trug sie als Sehnenlast, wovon die
-- Haelfte am eingespannten Knoten verloren ging (q = 1 auf dem Viertelkreis gab R_m = 4 mit R = (-1, 1)).
-- Aufruf: luajit Emulator/tests/bogenlast.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned = T.node, T.fixed, T.pinned
local zahl, wahr, fall = T.zahl, T.wahr, T.fall

local pi = math.pi
local R, ALPHA = 2, pi / 2     -- Viertelkreis um (2|0) von (0|0) nach (2|-2), Tangente am Anfang nach oben

-- eingespannter Viertelkreis, Spitze frei
local function kragbogen(felder, n)
    bogenSegmente = n or 20
    local f = { bogen_r = R }
    for k, v in pairs(felder) do f[k] = v end
    if not T.rechne({ fixed(node(0, 0)), node(2, -2) }, { T.bar(1, 2, f) }) then return nil end
    return getKnoten()[1], getStaebe()[1]
end

local function reaktion(titel, k, xi, eta, m, tol)
    if not k then T.pruef(false, titel .. ': keine Rechnung'); return end
    zahl(titel .. ': R_xi', k.R_xi, xi, tol)
    zahl(titel .. ': R_eta', k.R_eta, eta, tol)
    zahl(titel .. ': R_m', k.R_m, m, tol)
end

-- Schnittgroessen der FEM an einem Teilungspunkt (Ende des linken, Anfang des rechten Teilstuecks,
-- gemittelt wie in der Zeichnung; die Teilstuecke liegen um den halben Teilungswinkel gedreht)
local function femPunkt(s, j)
    local l, r = s.arc_plot_data[j - 1], s.arc_plot_data[j]
    return (l.N2 + r.N) / 2, (l.Q2 + r.Q) / 2, r.M1, r.phi1
end

-- Export M_bogen1/N_bogen1/q_bogen1 gegen eine Handformel f(p) -> N, Q, M
local function exportGegen(titel, f, tol)
    meldungText = nil
    local winkel = exportBogenSchnittkraefteToTI(1)
    zahl(titel .. ': Oeffnungswinkel 90 Grad', winkel, 90, 1e-9)
    for _, p in ipairs({ 0, pi / 8, pi / 4, 3 * pi / 8, pi / 2 }) do
        local N, Q, M = f(p)
        zahl(string.format('%s: N_bogen1(%.4f)', titel, p), T.ev('N_bogen1(' .. p .. ')'), N, tol)
        zahl(string.format('%s: q_bogen1(%.4f)', titel, p), T.ev('q_bogen1(' .. p .. ')'), Q, tol)
        zahl(string.format('%s: M_bogen1(%.4f)', titel, p), T.ev('M_bogen1(' .. p .. ')'), M, tol)
    end
end

-- Export gegen FEM an den Teilungspunkten auf dem Bogen. Punkt 1 und n-1 liegen tangential neben dem
-- Bogen: M ab Punkt 2, N und Q erst ab Punkt 3 (das Teilstueck von Punkt 1 nach 2 liegt schief).
-- femPunkt(s, j) ist Punkt j-1.
local function exportGegenFEM(titel, s, tolN, tolM)
    local n = #s.arc_plot_data
    local maxN, maxM = 0, 0
    for j = 3, n - 1 do
        local N, Q, M, p = femPunkt(s, j)
        local eN, eQ, eM = T.ev('N_bogen1(' .. p .. ')'), T.ev('q_bogen1(' .. p .. ')'), T.ev('M_bogen1(' .. p .. ')')
        if type(eN) ~= 'number' or type(eQ) ~= 'number' or type(eM) ~= 'number' then
            T.pruef(false, titel .. ': Export nicht auswertbar bei p = ' .. p); return
        end
        if j >= 4 and j <= n - 2 then maxN = math.max(maxN, math.abs(eN - N), math.abs(eQ - Q)) end
        maxM = math.max(maxM, math.abs(eM - M))
    end
    T.pruef(maxN <= tolN, string.format('%s: Export = FEM an den Teilungspunkten, N und Q (max. %.2g)', titel, maxN))
    T.pruef(maxM <= tolM, string.format('%s: Export = FEM an den Teilungspunkten, M (max. %.2g)', titel, maxM))
end

fall('1 radiale Gleichlast', function()
    T.abschnitt('Eingespannter Viertelkreis R = 2 mit radialer Gleichlast q = 1,5 (zum Mittelpunkt)')
    -- Handrechnung: die Last auf dem Bogenstueck P..B hat die Resultierende q*(B-P) um 90 Grad gedreht
    -- und um P das Moment q|B-P|^2/2. Mit beta = alpha - phi: |B-P| = 2R sin(beta/2)
    --   N = -qR(1-cos beta), Q = qR sin beta, M = -qR^2(1-cos beta); Lager R = (-2q, 2q, 4q)
    -- Das gilt auch fuer das Polygon der Teilstaebe exakt (Druck auf einen Linienzug haengt nur von
    -- den Endpunkten ab), deshalb enge Toleranzen an den Teilungspunkten auf dem Bogen.
    local q = 1.5
    local k, s = kragbogen({ q = q, q_str = '1.5' })
    reaktion('Lager', k, -2 * q, 2 * q, 4 * q, 1e-9)
    if not s then return end
    local n = #s.arc_plot_data
    wahr('20 Teilstuecke', n == 20, n)
    local maxM = 0
    for j = 3, n - 2 do
        local _, _, M, p = femPunkt(s, j)
        maxM = math.max(maxM, math.abs(M + q * R^2 * (1 - math.cos(ALPHA - p))))
    end
    T.pruef(maxM < 1e-9, string.format('M an den Teilungspunkten = -qR^2(1-cos(alpha-phi)) (max. %.2g)', maxM))
    -- freies Ende: N, Q, M = 0 (Endwerte N2/Q2 des letzten Teilstuecks, nicht seine Anfangswerte)
    local pd = s.arc_plot_data[n]
    wahr('freies Ende: N2 = Q2 = M2 = 0', math.abs(pd.N2) < 1e-9 and math.abs(pd.Q2) < 1e-9 and math.abs(pd.M2) < 1e-9,
        string.format('%.3g %.3g %.3g', pd.N2, pd.Q2, pd.M2))
    -- radiale Last steht quer zum letzten (tangentialen) Teilstueck: dort aendert sich Q, nicht N
    wahr('letztes Teilstueck traegt Last: Anfangswert Q ~= 0', math.abs(pd.Q) > 1e-4, pd.Q)
    exportGegen('Export', function(p)
        local b = ALPHA - p
        return -q * R * (1 - math.cos(b)), q * R * math.sin(b), -q * R^2 * (1 - math.cos(b))
    end, 1e-6)
    exportGegenFEM('Export', s, 2e-3 * q * R, 1e-9 + 1e-6)
    -- feinere Teilung aendert die exakten Werte nicht
    k = kragbogen({ q = q, q_str = '1.5' }, 50)
    reaktion('50 Teilstuecke', k, -2 * q, 2 * q, 4 * q, 1e-9)
    wahr('50 Teilstuecke in arc_plot_data', #getStaebe()[1].arc_plot_data == 50)
    bogenSegmente = 20
end)

fall('2 Eigengewicht', function()
    T.abschnitt('Eingespannter Viertelkreis unter Eigengewicht p_Y = g = 2 je Bogenlaenge')
    -- Handrechnung (P(psi) = (2 - 2cos psi, -2 sin psi), ds = R dpsi):
    --   Gesamtlast g R alpha = g pi nach unten, Hebel um A: int (2 - 2cos psi) g R dpsi = 2g(pi - 2)
    --   N = -gR(alpha-phi) cos phi, Q = gR(alpha-phi) sin phi, M = -2gR((alpha-phi) cos phi - 1 + sin phi)
    -- Die Last je Teilstab ist auf die Bogenlaenge skaliert: Summe exakt, Hebel O(Teilwinkel^2).
    local g = 2
    local k = kragbogen({ gy = g, gy_str = '2' })
    if not k then return end
    zahl('Lager: R_xi = 0', k.R_xi, 0, 1e-9)
    zahl('Lager: R_eta = g pi (Summe exakt)', k.R_eta, g * pi, 1e-9)
    zahl('Lager: R_m = 2g(pi-2), 20 Teilstuecke', k.R_m, 2 * g * (pi - 2), 1e-3)
    local function hand(p)
        local b = ALPHA - p
        return -g * R * b * math.cos(p), g * R * b * math.sin(p), -2 * g * R * (b * math.cos(p) - 1 + math.sin(p))
    end
    -- mit 100 Teilstuecken: Polygonfehler unter 1e-4. Der Export rechnet die Last exakt auf dem Kreisbogen,
    -- uebernimmt aber die Werte am Bogenanfang aus der FEM (Fehler dort etwa 1,5e-4)
    local s
    k, s = kragbogen({ gy = g, gy_str = '2' }, 100)
    zahl('Lager: R_m = 2g(pi-2), 100 Teilstuecke', k.R_m, 2 * g * (pi - 2), 5e-5)
    exportGegen('Export', hand, 5e-4)
    exportGegenFEM('Export', s, 2e-3, 2e-4)
    bogenSegmente = 20
end)

fall('3 weitere Lastarten', function()
    T.abschnitt('Eingespannter Viertelkreis: p_Y projiziert, p_X, p_X projiziert, n, m, Trapez')
    -- p_Y je Grundrisslaenge: 2g nach unten bei x = 1 -> (0, 2g, 2g), auf dem Polygon exakt
    reaktion('p_Y = 1,5 projiziert', kragbogen({ gy = 1.5, gy_str = '1.5', gy_proj = true }), 0, 3, 3, 1e-9)
    -- p_X je Hoehenlaenge: 2g nach rechts, Hebel 1 nach oben -> (-2g, 0, 2g)
    reaktion('p_X = 1,5 projiziert', kragbogen({ gx = 1.5, gx_str = '1.5', gx_proj = true }), -3, 0, 3, 1e-9)
    -- p_X je Bogenlaenge: g pi nach rechts, Hebel int 2 sin psi * R dpsi / (R alpha) -> R_m = 4g
    reaktion('p_X = 1,5', kragbogen({ gx = 1.5, gx_str = '1.5' }), -1.5 * pi, 0, 6, 1e-3)
    -- tangentiale Gleichlast: Resultierende n*(B-A) = (2n, -2n), Moment n R^2 (alpha - sin alpha)
    reaktion('n = 1', kragbogen({ n = 1, n_str = '1' }), -2, -2, 4 * (pi / 2 - 1), 2e-3)
    -- Streckenmoment: m R alpha gegen den Uhrzeigersinn
    reaktion('m = 1', kragbogen({ m = 1, m_str = '1' }), 0, 0, -pi, 1e-9)
    -- Trapez linear ueber die Bogenlaenge = Lastfunktion linear im Winkel
    local k1 = kragbogen({ q_A = 0, q_B = pi / 2 })
    local a = k1 and { k1.R_xi, k1.R_eta, k1.R_m }
    local k2 = kragbogen({ q_str = 'x' })
    if a and k2 then
        zahl('q = x gleich Trapez 0..pi/2: R_xi', k2.R_xi, a[1], 1e-9)
        zahl('q = x gleich Trapez 0..pi/2: R_eta', k2.R_eta, a[2], 1e-9)
        zahl('q = x gleich Trapez 0..pi/2: R_m', k2.R_m, a[3], 1e-9)
    end
    -- Handrechnung q = phi radial: F = R int phi (cos phi, sin phi) dphi = (pi - 2, 2), M_A = R^2 int phi sin phi = 4
    reaktion('q = x (Winkel in rad)', k2, -(pi - 2), 2, 4, 1e-3)
    -- Export mit Lastfunktion und Trapez: gegen FEM an den Teilungspunkten
    local _, s = kragbogen({ q_str = 'x', q_A = 1, q_B = 2, n_str = 'sin(x)', gy = 1, gy_str = '1', m = 0.5, m_str = '0.5' })
    if s then
        exportBogenSchnittkraefteToTI(1)
        exportGegenFEM('alle Lasten zusammen', s, 2e-2, 3e-3)
    end
end)

fall('4 Winkelmodus Grad', function()
    T.abschnitt('Lastfunktion im Gradmodus: x laeuft von 0 bis 90 (Winkel im Winkelmodus des Rechners)')
    -- Der Emulator rechnet im Bogenmass; Gradmodus vortaeuschen (cos(180) = -1), x/90 = Trapez 0..1
    local a = kragbogen({ q_A = 0, q_B = 1 })
    a = a and { a.R_xi, a.R_eta, a.R_m }
    local orig = math.eval
    math.eval = function(e) if e == 'approx(cos(180))' then return -1 end return orig(e) end
    local ok, f = pcall(bogenWinkelFaktor)
    wahr('bogenWinkelFaktor erkennt Grad', ok and math.abs(f - 180 / pi) < 1e-12, f)
    local k = kragbogen({ q_str = 'x/90' })
    math.eval = orig
    if a and k then
        zahl('q = x/90 (Grad) gleich Trapez 0..1: R_xi', k.R_xi, a[1], 1e-9)
        zahl('q = x/90 (Grad) gleich Trapez 0..1: R_m', k.R_m, a[3], 1e-9)
    end
    local f2 = bogenWinkelFaktor()
    wahr('Bogenmass: Faktor 1', f2 == 1, f2)
end)

fall('5 Dreigelenkbogen', function()
    T.abschnitt('Dreigelenkbogen aus zwei Viertelkreisen R = 2 (Kaempfer 0|0 und 4|0, Scheitel 2|-2), Eigengewicht g')
    -- Handrechnung: A_v = B_v = g R pi / 2 * 2 / 2 = g pi; Scheitelmoment links = 0:
    --   2 A_v - 2 H - g R int 2 cos psi dpsi = 0  ->  H = (pi - 2) g
    --   M(psi) = A_v (2 - 2cos psi) - H 2 sin psi - g R int_0^psi 2 (cos t - cos psi) dt
    local g = 1.5
    bogenSegmente = 100
    local K = { pinned(node(0, 0)), node(2, -2), pinned(node(4, 0)) }
    K[2].gelenk = true
    local ok = T.rechne(K, { T.bar(1, 2, { bogen_r = R, gy = g, gy_str = '1.5' }), T.bar(2, 3, { bogen_r = R, gy = g, gy_str = '1.5' }) })
    bogenSegmente = 20
    if not ok then return end
    local A, B = getKnoten()[1], getKnoten()[3]
    zahl('A_v = g pi', A.R_eta, g * pi, 1e-9)
    zahl('B_v = g pi', B.R_eta, g * pi, 1e-9)
    zahl('A_h = (pi - 2) g (nach rechts)', A.R_xi, (pi - 2) * g, 1e-4)
    zahl('B_h = -(pi - 2) g', B.R_xi, -(pi - 2) * g, 1e-4)
    local s = getStaebe()[1]
    zahl('Scheitelgelenk: M = 0', s.arc_plot_data[#s.arc_plot_data].M2, 0, 1e-9)
    local H = (pi - 2) * g
    exportGegen('Bogen 1', function(p)
        local Mh = g * pi * (2 - 2 * math.cos(p)) - 2 * H * math.sin(p) - 2 * g * R * (math.sin(p) - p * math.cos(p))
        -- Kraefte am Schnitt aus dem linken Teil: Lager (H nach rechts, g pi nach oben) und Last g R p
        local Fx, Fy = -H, g * pi - g * R * p
        local tx, ty = math.sin(p), -math.cos(p)
        return Fx * tx + Fy * ty, -Fx * ty + Fy * tx, Mh
    end, 5e-4)   -- Werte am Bogenanfang aus der FEM mit 100 Teilstuecken
end)

fall('6 Temperatur', function()
    T.abschnitt('Eingespannter Viertelkreis: Temperatur')
    -- gleichmaessige Erwaermung: statisch bestimmt, keine Kraefte; die Spitze wandert um alpha_T dT (B - A)
    local k, s = kragbogen({ To = 20, Tu = 20, To_str = '20', Tu_str = '20', alpha = 1e-5 })
    reaktion('To = Tu = 20', k, 0, 0, 0, 1e-9)
    local B = getKnoten()[2]
    zahl('u_x Spitze = 2e-4 * 2', B.mat_pv[1][2], 4e-4, 1e-9)
    zahl('u_y Spitze = 2e-4 * (-2)', B.mat_pv[2][2], -4e-4, 1e-9)
    -- Temperaturgradient: Kruemmung alpha_T (Tu - To)/h; Drehung der Spitze = Kruemmung mal Bogenlaenge,
    -- also wie bei einem geraden Kragarm der Laenge R alpha. Die Kruemmung wirkt auf der Laenge des
    -- Polygons (wie die Steifigkeit), mit 20 Teilstuecken etwa 2e-4 laenger als der Bogen.
    kragbogen({ To = -5, Tu = 5, To_str = '-5', Tu_str = '5', alpha = 1e-5, h = 0.2 })
    local phiB = getKnoten()[2].mat_pv[3][2]
    T.rechne({ fixed(node(0, 0)), node(R * ALPHA, 0) }, { T.bar(1, 2, { To = -5, Tu = 5, To_str = '-5', Tu_str = '5', alpha = 1e-5, h = 0.2 }) })
    zahl('Drehung Spitze = gerader Kragarm gleicher Laenge', phiB, getKnoten()[2].mat_pv[3][2], 5e-4 * 1.6e-3)
    wahr('  Drehung nicht null', math.abs(phiB) > 1e-6, phiB)
end)

fall('7 Hinweis und Export', function()
    T.abschnitt('Nicht auswertbare Lastfunktion: Hinweis statt still 0; Exportmeldung')
    kragbogen({ q_str = '1/(x-x)' })
    local hinweis = nil
    for _, h in ipairs(hinweisListe) do if h:find('Bogen', 1, true) and h:find('nicht auswertbar', 1, true) then hinweis = h end end
    wahr('Hinweis: Lastfunktion auf dem Bogen nicht auswertbar', hinweis ~= nil, table.concat(hinweisListe, ' | '))
    wahr('Hinweisbox offen', hinweisOffen == true)
    kragbogen({ q = 1, q_str = '1' })
    wahr('ohne Fehler kein Bogen-Hinweis', #hinweisListe == 0, table.concat(hinweisListe, ' | '))
    meldungText = nil
    exportSchnittkraefteToTI()
    wahr('Meldung nennt den Bogen und den Winkelbereich', (meldungText or ''):find('Stab 1: p von 0 bis 90 Grad', 1, true) ~= nil, meldungText)
    zahl('M_bogen1(0) = -4 (aus dem Menue-Export)', T.ev('M_bogen1(0)'), -4, 1e-9)
end)

fall('8 Zeichnung', function()
    T.abschnitt('Zeichnen mit belasteten Boegen (alle Ansichten), Resultierende auf der E-Seite')
    local gc = setmetatable({}, { __index = function(_, k)
        if k == 'getStringWidth' then return function(_, t) return #tostring(t) * 6 end end
        if k == 'getStringHeight' then return function() return 12 end end
        return function() end
    end })
    local S = { q_str = 'x', n = 1, n_str = '1', m = 0.5, m_str = '0.5', gx_str = 'x', gy = 1, gy_str = '1', gy_proj = true, q_A = 1, q_B = 2 }
    kragbogen(S)
    local fehler = {}
    for _, modus in ipairs({ 'System', 'N', 'Q', 'M', 'W', 'U', 'E' }) do
        for seite = 1, (modus == 'E') and 2 or 1 do
            ansichtsModus, explosionPage = modus, seite
            local ok, err = pcall(on.paint, gc)
            if not ok then fehler[#fehler + 1] = modus .. seite .. ': ' .. tostring(err) end
        end
    end
    ansichtsModus, explosionPage = 'System', 1
    wahr('alle Ansichten zeichnen', #fehler == 0, table.concat(fehler, ' | '))
    -- radiale Gleichlast: Resultierende durch Mittelpunkt und Sehnenmitte, Fusspunkt = Bogenmitte
    kragbogen({ q = 1, q_str = '1' })
    ansichtsModus, explosionPage = 'E', 1
    local ok = pcall(on.paint, gc)
    ansichtsModus = 'System'
    local treffer = false
    for _, p in ipairs(glob_resultant_pts or {}) do
        if math.abs(p.x - (2 - math.sqrt(2))) < 1e-9 and math.abs(p.y + math.sqrt(2)) < 1e-9 then treffer = true end
    end
    wahr('E-Seite: Resultierende der radialen Last auf der Bogenmitte', ok and treffer)
    local r = getStaebe()[1].bogen_res
    wahr('Resultierende q = (2, 2), Moment um A = -4', r and math.abs(r.q[1] - 2) < 1e-9 and math.abs(r.q[2] - 2) < 1e-9 and math.abs(r.q[3] + 4) < 1e-9)
    -- Halbkreis (Radius = halbe Sehne) rechnet ohne Division durch null
    T.rechne({ pinned(node(0, 0)), pinned(node(4, 0)) }, { T.bar(1, 2, { bogen_r = 2, q = 1, q_str = '1', dehnsteif = true }) })
    local A = getKnoten()[1]
    wahr('Halbkreis: Lagerkraefte endlich', A.R_eta == A.R_eta and math.abs(A.R_eta - 2) < 1e-9, A.R_eta)
    local s = getStaebe()[1]
    zahl('Halbkreis unter radialem Druck: N ~ -qR', s.arc_plot_data[10].N, -2, 1e-2)
end)

T.ende('Lasten auf Boegen')
