-- Gemeinsame Hilfen fuer die Testreihen in Emulator/tests/.
-- Jede Testreihe beginnt mit
--   local T = dofile((debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\") .. 'common.lua')
-- und endet mit T.ende('Name').
--
-- Aufruf einzeln:   luajit Emulator/tests/balken_hand.lua [Filter]
-- Umgebung:         TEST_VERBOSE=1  -> jede Pruefung und alle Zwischenausgaben anzeigen
--                   BIEGELINIE=...  -> anderes Skript testen (siehe cas_bridge.lua)

local M = {}
io.stdout:setvbuf('no')

M.dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\")
M.cas = dofile(M.dir .. '..\\cas_bridge.lua')
M.cas.start()
M.pfad = M.cas.loadBiegelinie(nil, [==[
_G.neuCasText = neuCasText; _G.neuZahl = neuZahl
_G.exportArbeitssatzToTI = exportArbeitssatzToTI
_G.exportSchnittkraefteToTI = exportSchnittkraefteToTI; _G.exportStabToTI = exportStabToTI
_G.exportBiegelinienToTI = exportBiegelinienToTI; _G.exportULinienToTI = exportULinienToTI
-- PvV: eine Bindung am Knoten loesen wie im Menue "pvv_knoten" (Zeile 1 H, 2 V, 3 M, 4 Gelenk)
_G.pvvFreigabe = function(nr, zeile)
    local k = knoten[nr]
    pvvBackupSystem()
    if zeile == 1 then k.lager_x = false; pvv_released_binding = { type = "lager_x", node = nr }
    elseif zeile == 2 then k.lager_y = false; pvv_released_binding = { type = "lager_y", node = nr }
    elseif zeile == 3 then k.lager_m = false; pvv_released_binding = { type = "lager_m", node = nr }
    else k.gelenk = true; pvv_released_binding = { type = "knoten_gelenk", node = nr } end
    pvvModus = false; in_pvv_release = true
    buildPolplan(); calcKinematicStates(); ansichtsModus = "V"; pvvPrepareCAS()
end
-- PvV: Gelenk am Stab einbauen wie im Menue "pvv_stab" (Zeile 1/2 M-Gelenk A/B, 3/4 N-, 5/6 Q-Gelenk)
_G.pvvFreigabeStab = function(nr, zeile)
    local s = staebe[nr]
    local felder = { "gelenk_A", "gelenk_B", "n_gelenk_A", "n_gelenk_B", "q_gelenk_A", "q_gelenk_B" }
    local typen = { "m_gelenk", "m_gelenk", "n_gelenk", "n_gelenk", "q_gelenk", "q_gelenk" }
    pvvBackupSystem()
    s[felder[zeile]] = true
    pvv_released_binding = { type = typen[zeile], stab = nr, endA = (zeile % 2 == 1) }
    pvvModus = false; in_pvv_release = true
    buildPolplan(); calcKinematicStates(); ansichtsModus = "V"; pvvPrepareCAS()
end
_G.pvvEnde = function() pvvRestoreSystem(); in_pvv_release = false; pvv_released_binding = nil; ansichtsModus = "System" end
_G.getKinematik = function() return kinematic_disk_states, kinematic_seed_info end
_G.systemFingerabdruck = systemFingerabdruck
-- Hover setzen wie mit dem Cursor (fuer on.backspaceKey)
_G.setHover = function(typ, obj) hoverTyp, hoverObj = typ, obj end
-- Mausposition in Pixeln (fuer Hover-Anzeigen wie den Tooltip oben rechts)
_G.setMaus = function(x, y) mouseX, mouseY = x, y end
]==])

M.write = io.write
M.verbose = os.getenv('TEST_VERBOSE') ~= nil
M.filter = arg and arg[1]
M.total, M.fails, M.problems = 0, 0, {}
M.msgs = {}

-- Statusausgaben des Skripts sammeln (nur bei TEST_VERBOSE anzeigen)
print = function(...)
    local t = {}
    for i = 1, select('#', ...) do t[i] = tostring(select(i, ...)) end
    local line = table.concat(t, ' ')
    M.msgs[#M.msgs + 1] = line
    if M.verbose then io.write('   [skript] ' .. line .. '\n') end
end

-- Ausgabe nur im Verbose-Modus
function M.info(text) if M.verbose then M.write(text .. '\n') end end

-- Eine Pruefung verbuchen; Fehlschlaege werden immer angezeigt
function M.pruef(ok, text)
    M.total = M.total + 1
    if not ok then
        M.fails = M.fails + 1
        M.problems[#M.problems + 1] = (M.titel and (M.titel .. ': ') or '') .. text
    end
    if not ok or M.verbose then M.write('   ' .. (ok and 'ok ' or 'XX ') .. text .. '\n') end
end

-- Zahlenvergleich mit relativer Toleranz
function M.zahl(label, ist, soll, tol)
    tol = tol or 1e-6
    local ok = type(ist) == 'number' and math.abs(ist - soll) <= tol * math.max(1, math.abs(soll))
    M.pruef(ok, string.format('%-48s soll %-16.10g ist %s', label, soll,
        type(ist) == 'number' and string.format('%.10g', ist) or tostring(ist)))
    return ok
end

-- Wahrheitspruefung mit optionaler Zusatzinfo
function M.wahr(label, bedingung, info) M.pruef(bedingung and true or false, label .. (info ~= nil and ('  [' .. tostring(info) .. ']') or '')) end

-- Abschnitt (Titel wird immer angezeigt)
function M.abschnitt(titel)
    M.titel = titel
    M.write('\n== ' .. titel .. '\n')
end

-- Testfall nur ausfuehren, wenn er zum Filter passt; Abstuerze zaehlen als Fehler
function M.fall(name, fn)
    if M.filter and not name:find(M.filter, 1, true) then return end
    local ok, err = pcall(fn)
    if not ok then M.pruef(false, 'Absturz in ' .. name .. ': ' .. tostring(err):gsub('\n.*', '')) end
end

-- CAS-Auswertung
function M.ev(e) local ok, v = pcall(math.eval, 'approx(' .. e .. ')'); return ok and v or ('ERR ' .. tostring(v):sub(1, 80)) end
function M.evs(e) local ok, v = pcall(math.eval, 'string(' .. e .. ')'); return ok and v or ('ERR ' .. tostring(v):sub(1, 80)) end

-- Modellbausteine (Weltkoordinaten: x nach rechts, y nach UNTEN)
function M.node(x, y, xs, ys)
    local k = erstelleKnoten(x, y or 0)
    k.x_str, k.y_str = xs or tostring(x), ys or tostring(y or 0)
    return k
end
function M.bar(a, b, f, defaults)
    local s = erstelleStab(a, b)
    s.EI, s.EA = 1, 100
    for k, v in pairs(defaults or {}) do s[k] = v end
    for k, v in pairs(f or {}) do s[k] = v end
    return s
end
function M.fixed(k) k.lager_x, k.lager_y, k.lager_m = true, true, true; return k end
function M.pinned(k) k.lager_x, k.lager_y = true, true; return k end
function M.roller(k) k.lager_y = true; return k end

-- Ausgangszustand vor jedem System
function M.reset(opts)
    opts = opts or {}
    M.cas.reset()
    autoKGV, zeigeN, sym_vars, symbolischer_modus = false, false, {}, false
    randDehnstarr = opts.dehnstarr or false   -- Vergleich mit FEM: EA endlich
    randStarrDirekt = opts.starrDirekt or false   -- starre Staebe: Grenzwert-Methode (direkt: starr_direkt.lua)
    symbolFehler = nil
    rasterMass, rasterMass_str = opts.raster or 1, nil
    casToleranz = opts.casToleranz or 9     -- Referenzexport v_EI_stab rundet sonst auf 5 Stellen
    zahlenFormat = opts.zahlenFormat or 1
    M.msgs = {}
end

-- System rechnen und das Rand-LGS exportieren; liefert true bei Erfolg
function M.rechne(K, S, opts)
    M.reset(opts)
    setKnoten(K); setStaebe(S)
    local ok, err = pcall(starteBerechnung)
    if not ok then M.pruef(false, 'starteBerechnung: ' .. tostring(err)); return false end
    if symbolFehler then M.info('   symbolFehler: ' .. symbolFehler) end
    return true
end
function M.randLGS()
    local ok, res = pcall(exportBiegelinienNeuToTI)
    if not ok then M.pruef(false, 'Rand-LGS Absturz: ' .. tostring(res)); return false end
    if not res then
        local rb = M.evs('randbed')
        M.pruef(false, 'Rand-LGS fehlgeschlagen: ' .. tostring(rb))
        return false
    end
    M.info('   randbed = ' .. tostring(M.evs('randbed')))
    return true
end

-- Abschluss: Zusammenfassung, CAS-Server beenden, Exitcode
function M.ende(name)
    M.cas.stop()
    M.write(string.format('\nErgebnis %s: %d Pruefungen, %d Fehler\n', name, M.total, M.fails))
    for _, p in ipairs(M.problems) do M.write('   XX ' .. p .. '\n') end
    os.exit(M.fails == 0 and 0 or 1)
end

return M
