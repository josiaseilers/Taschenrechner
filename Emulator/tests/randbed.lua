-- Lesbarkeit der exportierten Randbedingungen:
--   * bereits bekannte Groessen (meist 0) stehen als Wert in der Bedingung, nicht als fremder Name
--   * randbed wird nach Biegelinie (w) und Laengslinie (u) gruppiert, wenn das moeglich ist
--   * die Ergebnisse muessen dabei unveraendert richtig bleiben (Vergleich mit der FEM)
-- Aufruf: luajit Emulator/tests/randbed.lua [Filter]
local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
local node, fixed, pinned, roller, ev = T.node, T.fixed, T.pinned, T.roller, T.ev

-- randbed als Liste von Strings
local function bedingungen()
    local rb = tostring(T.evs('randbed'))
    local liste = {}
    for t in rb:gmatch('"([^"]*)"') do liste[#liste + 1] = t end
    return liste
end

local function enthaelt(liste, muster)
    for _, t in ipairs(liste) do if t:find(muster, 1, true) then return true end end
    return false
end

local function zeige(liste)
    for i, t in ipairs(liste) do T.info(string.format('   %2d  %s', i, t)) end
end

-- Stabenden gegen die FEM: der lesbare Export muss dieselbe Loesung liefern
local function pruefeGegenFEM(tol)
    for i, s in ipairs(getStaebe()) do
        local k1, k2 = getKnoten()[s.k1], getKnoten()[s.k2]
        local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
        T.zahl('Stab ' .. i .. ' w(0)', ev('wv' .. i .. '(0)'), s.v_local[2] or 0, tol or 1e-8)
        T.zahl('Stab ' .. i .. ' w(L)', ev('wv' .. i .. '(' .. L .. ')'), s.v_local[5] or 0, tol or 1e-8)
        T.zahl('Stab ' .. i .. ' u(0)', ev('uv' .. i .. '(0)'), s.v_local[1] or 0, tol or 1e-8)
        T.zahl('Stab ' .. i .. ' u(L)', ev('uv' .. i .. '(' .. L .. ')'), s.v_local[4] or 0, tol or 1e-8)
    end
end

local fall = T.fall

fall('1 Bekannte Groessen eingesetzt', function()
    T.abschnitt('Rahmenecke: Stab 2 dehnstarr und gehalten, also u2 = 0 -> "w1(x1=2)=0" statt "=u2(...)"')
    local K = { node(0, 0), node(2, 0), fixed(node(2, 2)) }
    K[1].last_y = 1
    local S = { T.bar(1, 2, { EI = 10, EA = 100 }), T.bar(2, 3, { EI = 10, EA = 100, dehnsteif = true }) }
    if not T.rechne(K, S, { starrDirekt = true }) then return end
    if not T.randLGS() then return end
    local rb = bedingungen()
    zeige(rb)
    T.wahr('w1 am Knoten 2 steht mit Wert 0 da', enthaelt(rb, 'w1(x1=2)=0'), table.concat(rb, ' | '))
    T.wahr('kein Verweis auf u2 in dieser Bedingung', not enthaelt(rb, 'w1(x1=2)=u2'), table.concat(rb, ' | '))
    T.wahr('Biegelinie allein loesbar gemeldet',
        tostring(T.evs('randinfo')):find('Biegelinie w ohne Laengslinie', 1, true) ~= nil, tostring(T.evs('randinfo')))
    T.wahr('Gruppenueberschrift vorhanden', enthaelt(rb, 'Biegelinie w: diese genuegen'), table.concat(rb, ' | '))
    -- Handrechnung: phi(Ecke) = F*L*L/EI = 2*2/10 = 0.4; w(Spitze) = F*L^3/(3EI) + phi*L
    T.zahl('w1(0) = F L^3/(3EI) + phi L', ev('wv1(0)'), 8 / 30 + 0.4 * 2, 1e-9)
    pruefeGegenFEM()
end)

fall('2 Biege- und Laengslinie unabhaengig', function()
    T.abschnitt('gerader Balken mit q und n: w und u haengen nicht zusammen')
    local K = { fixed(node(0, 0)), node(2, 0), roller(node(4, 0)) }
    local S = { T.bar(1, 2, { q = 1, q_str = '1', n = 1, n_str = '1' }), T.bar(2, 3, { q = 1, q_str = '1' }) }
    if not T.rechne(K, S) then return end
    if not T.randLGS() then return end
    local rb = bedingungen()
    zeige(rb)
    T.wahr('Gruppe Biegelinie', enthaelt(rb, 'nur Biegelinie w'), table.concat(rb, ' | '))
    T.wahr('Gruppe Laengslinie', enthaelt(rb, 'nur Laengslinie u'), table.concat(rb, ' | '))
    T.wahr('randinfo meldet die Unabhaengigkeit',
        tostring(T.evs('randinfo')):find('unabhaengig', 1, true) ~= nil, tostring(T.evs('randinfo')))
    -- in der w-Gruppe darf keine u-Groesse mit Namen stehen und umgekehrt
    local gruppe = nil
    for _, t in ipairs(rb) do
        if t:find('nur Biegelinie', 1, true) then gruppe = 'w'
        elseif t:find('nur Laengslinie', 1, true) then gruppe = 'u'
        elseif gruppe == 'w' then
            T.wahr('w-Gruppe ohne u-Groesse: ' .. t, not t:find('u%d'), t)
        elseif gruppe == 'u' then
            T.wahr('u-Gruppe ohne w-Ableitung: ' .. t, not t:find("EIw"), t)
        end
    end
    pruefeGegenFEM()
end)

fall('3 Gekoppeltes System bleibt ungeteilt', function()
    T.abschnitt('Zweigelenkrahmen ohne starre Staebe: Normalkraft und Biegung haengen zusammen')
    local K = { pinned(node(0, 2)), node(0, 0), node(2, 0), pinned(node(2, 2)) }
    K[2].last_x = 1
    local S = {}
    for i = 1, 3 do S[i] = T.bar(i, i + 1, { EI = 10, EA = 100 }) end
    if not T.rechne(K, S) then return end
    if not T.randLGS() then return end
    local rb = bedingungen()
    T.wahr('keine Gruppenueberschrift', not enthaelt(rb, '---'), table.concat(rb, ' | '))
    T.wahr('randinfo ohne Trennungshinweis',
        tostring(T.evs('randinfo')):find('Laengslinie u', 1, true) == nil, tostring(T.evs('randinfo')))
    pruefeGegenFEM()
end)

fall('4 Klausursystem mit starrem Balken', function()
    T.abschnitt('starrer Balken auf Pendelstaeben: Bedingungen bleiben richtig, Werte eingesetzt')
    local K = { node(0, 0), node(2, 0), pinned(node(4, 0)), node(6, 0), pinned(node(6, -1)), pinned(node(6, 4)), node(10, 0) }
    K[1].cm = 3
    K[2].last_y = 1
    K[7].last_y = -1
    K[5].gelenk, K[6].gelenk = true, true
    local function starr() return { biegesteif = true, dehnsteif = true, EI = 1e8, EA = 1e10 } end
    local S = { T.bar(1, 2, starr()), T.bar(2, 3, starr()), T.bar(3, 4, starr()), T.bar(4, 7, starr()),
        T.bar(5, 4, { EA = 1, EI = 1e8, gelenk_A = true, gelenk_B = true }),
        T.bar(4, 6, { EA = 2, EI = 1e8, gelenk_A = true, gelenk_B = true }) }
    if not T.rechne(K, S, { starrDirekt = true }) then return end
    if not T.randLGS() then return end
    local rb = bedingungen()
    zeige(rb)
    T.wahr('Laengsverschiebung des starren Balkens steht als 0 da', enthaelt(rb, 'u1(x1=2)=0'), table.concat(rb, ' | '))
    pruefeGegenFEM(1e-6)
end)

-- Zweigelenkrahmen wie in der Klausur: alle Staebe dehnsteif, F in Riegelmitte
local function portal(auf, symb, stielEA)
    local d = { EI = 1, EA = 1, dehnsteif = true }
    if symb then d.EI_str, d.EA_str = 'EI', 'EA' end
    local function bar(a, b, f)
        local s = T.bar(a, b, f, d)
        return s
    end
    local K = { pinned(node(0, 0)), node(0, -1), node(1, -1), node(2, -1), pinned(node(2, 0)) }
    K[3].last_y = 1
    if symb then K[3].last_y_str = 'F' end
    local st = stielEA and { dehnsteif = false, EA = stielEA } or nil
    local S = { bar(1, 2, st), bar(2, 3), bar(3, 4), auf and bar(5, 4, st) or bar(4, 5, st) }
    if not T.rechne(K, S, { starrDirekt = true }) then return nil end
    if not T.randLGS() then return nil end
    return bedingungen()
end
-- Bedingungen in den beiden Gruppen
local function gruppen(rb)
    local g, w, u = nil, {}, {}
    for _, t in ipairs(rb) do
        if t:find('Biegelinie w: diese genuegen', 1, true) then g = w
        elseif t:find('zusaetzlich fuer Laengslinie u', 1, true) then g = u
        elseif g then g[#g + 1] = t end
    end
    return w, u
end

fall('5 Rahmen mit dehnsteifen Staeben: u und N durchgereicht', function()
    for _, auf in ipairs({ false, true }) do
        T.abschnitt('Zweigelenkrahmen, alle Staebe dehnsteif, rechter Stiel ' .. (auf and 'nach oben' or 'nach unten'))
        local rb = portal(auf)
        if not rb then return end
        zeige(rb)
        local w, u = gruppen(rb)
        T.zahl('16 Bedingungen fuer w (4 je Stab)', #w, 16, 0)
        T.zahl('8 Bedingungen zusaetzlich fuer u und N', #u, 8, 0)
        for _, t in ipairs(w) do
            T.wahr('w-Gruppe ohne Laengsgroesse: ' .. t, not t:find('u%d') and not t:find('EAu', 1, true), t)
        end
        local sway = auf and 'w4(x4=1)=w1(x1=1)' or 'w4(x4=0)=-w1(x1=1)'
        T.wahr('Seitenverschiebung durchgereicht: ' .. sway, enthaelt(w, sway), table.concat(w, ' | '))
        T.wahr('Querkraefte der Stiele verbunden', enthaelt(w, "EIw1'''(x1=1)=-EIw4'''"), table.concat(w, ' | '))
        T.wahr('u-Gruppe wie von Hand: u2(x2=0)=w1(x1=1)', enthaelt(u, 'u2(x2=0)=w1(x1=1)'), table.concat(u, ' | '))
        T.wahr('randinfo nennt das Einsetzen',
            tostring(T.evs('randinfo')):find('dehnsteifen Staebe eingesetzt', 1, true) ~= nil, tostring(T.evs('randinfo')))
        -- die zusammengefasste Bedingung gilt fuer die Loesung
        if auf then T.zahl('w4(1) = w1(1)', ev('wv4(1)'), ev('wv1(1)'), 1e-12)
        else T.zahl('w4(0) = -w1(1)', ev('wv4(0)'), -ev('wv1(1)'), 1e-12) end
        pruefeGegenFEM()
    end
end)

fall('6 Rahmen symbolisch wie auf dem Rechner', function()
    T.abschnitt('Zweigelenkrahmen symbolisch (F, EI), alle Staebe dehnsteif')
    local rb = portal(false, true)
    if not rb then return end
    zeige(rb)
    local w = gruppen(rb)
    T.zahl('16 Bedingungen fuer w', #w, 16, 0)
    T.wahr('w4(x4=0)=-w1(x1=l)', enthaelt(w, 'w4(x4=0)=-w1(x1=l)'), table.concat(w, ' | '))
end)

fall('7 Elastische Stiele bleiben gekoppelt', function()
    T.abschnitt('Riegel dehnsteif, Stiele mit EA: Stielstauchung steckt in der Biegelinie des Riegels')
    local rb = portal(false, false, 100)
    if not rb then return end
    T.wahr('keine Gruppenueberschrift', not enthaelt(rb, '---'), table.concat(rb, ' | '))
    pruefeGegenFEM()
end)

fall('8 Rahmen mit Horizontalkraft am Riegel', function()
    for _, symb in ipairs({ false, true }) do
        T.abschnitt('Zweigelenkrahmen, dehnsteif, F in Riegelmitte und H an der linken Ecke' .. (symb and ' (symbolisch)' or ''))
        local d = { EI = 1, EA = 1, dehnsteif = true }
        if symb then d.EI_str, d.EA_str = 'EI', 'EA' end
        local K = { pinned(node(0, 0)), node(0, -1), node(1, -1), node(2, -1), pinned(node(2, 0)) }
        K[3].last_y, K[2].last_x = 1, 2
        if symb then K[3].last_y_str, K[2].last_x_str = 'F', 'H' end
        local S = { T.bar(1, 2, nil, d), T.bar(2, 3, nil, d), T.bar(3, 4, nil, d), T.bar(4, 5, nil, d) }
        if not T.rechne(K, S, { starrDirekt = true }) then return end
        if not T.randLGS() then return end
        local rb = bedingungen()
        zeige(rb)
        local w = gruppen(rb)
        T.zahl('16 Bedingungen fuer w', #w, 16, 0)
        -- Summe der Stielquerkraefte = -H (Gleichgewicht am ganzen Riegel)
        local soll = symb and "EIw1'''(x1=l)+EIw4'''(x4=0)+H=0" or "EIw1'''(x1=1)+EIw4'''(x4=0)+2=0"
        T.wahr('H in der zusammengefassten Bedingung: ' .. soll, enthaelt(w, soll), table.concat(w, ' | '))
        if not symb then pruefeGegenFEM() end
    end
end)

T.ende('Randbedingungen lesbar')
