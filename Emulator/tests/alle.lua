-- Alle Tests (Biegelinieneu.lua und Querschnitt.lua) in einem Durchlauf.
-- Aufruf:  luajit Emulator/tests/alle.lua        (nur Fehler und Zusammenfassung)
--          luajit Emulator/tests/alle.lua -v     (alle Ausgaben)
-- Jede Testreihe laeuft als eigener Prozess mit eigenem CAS-Server (sauberer Zustand).
io.stdout:setvbuf('no')

local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\")
local lua = arg[-1] or 'luajit'
local verbose = arg[1] == '-v'

local REIHEN = {
    { name = 'Regression (alte Fehler, symbolischer Modus)', datei = dir .. '..\\test_regression.lua' },
    { name = 'Test-Runner (Originaltestfaelle)', datei = dir .. '..\\test_runner.lua', runner = true },
    { name = 'Balken gegen Handrechnung', datei = dir .. 'balken_hand.lua' },
    { name = 'Rahmen gegen Handrechnung', datei = dir .. 'rahmen_hand.lua' },
    { name = 'Symbolischer Modus', datei = dir .. 'symbolisch.lua' },
    { name = 'Rand-LGS gegen FEM', datei = dir .. 'randlgs_fem.lua' },
    { name = 'Rand-LGS dehnstarr (EA -> unendlich)', datei = dir .. 'dehnstarr.lua' },
    { name = 'Starre Staebe (biegesteif, dehnsteif)', datei = dir .. 'starr.lua' },
    { name = 'Starre Staebe: direkt gegen Grenzwert', datei = dir .. 'starr_direkt.lua' },
    { name = 'Randbedingungen lesbar (eingesetzte Werte, Gruppen)', datei = dir .. 'randbed.lua' },
    { name = 'Temperatur (auch symbolisch)', datei = dir .. 'temperatur.lua' },
    { name = 'LGS-Export gegen FEM (Gelenke, Auflager)', datei = dir .. 'lgs.lua' },
    { name = 'LGS-Export passend zu E-Seite 2', datei = dir .. 'lgs_seite2.lua' },
    { name = 'KGV: Matrizen und Superposition', datei = dir .. 'kgv.lua' },
    { name = 'Arbeitssatz (PvV) gegen FEM', datei = dir .. 'arbeitssatz.lua' },
    { name = 'Globale Linienlasten p(x), projiziert', datei = dir .. 'globallast.lua' },
    { name = 'Lasten auf Boegen (Handrechnung, Export)', datei = dir .. 'bogenlast.lua' },
    { name = 'Knotenverschiebung (Rand-LGS), Systeme speichern', datei = dir .. 'verschiebung.lua' },
    { name = 'Oberflaeche Tragwerk (ESC, Obermenue)', datei = dir .. 'oberflaeche.lua' },
    { name = 'Querschnitt (Handrechnung, Oberflaeche)', datei = dir .. 'querschnitt.lua' },
    { name = 'Spannungskreis (Schnitte, Ansichten)', datei = dir .. 'spannung.lua' },
}

-- Zeilen, die auch ohne -v angezeigt werden
local function wichtig(line)
    return line:find('^%s*XX') or line:find('FEHLER') or line:find('Absturz') or line:find('traceback')
        or line:find('luajit') or line:find('Zeitueberschreitung') or line:find('^Ergebnis')
end

local gesamt_ok, zeilen = true, {}
local start = os.time()
for _, r in ipairs(REIHEN) do
    io.write('\n### ' .. r.name .. '\n')
    local t0 = os.time()
    -- cmd.exe: gesamten Befehl nochmals in Anfuehrungszeichen, damit Pfade mit Leerzeichen gehen
    local p = io.popen('""' .. lua .. '" "' .. r.datei .. '" 2>&1"')
    local ergebnis, bestanden, absturz = nil, false, false
    for line in p:lines() do
        line = line:gsub('\r$', '')
        if verbose or wichtig(line) then io.write(line .. '\n') end
        if line:find('^Ergebnis') then ergebnis = line end
        if line:find('bestanden') then bestanden = true end
        if line:find('traceback') or line:find('^[^%s]*luajit[^:]*: ') then absturz = true end
    end
    p:close()
    local ok
    if r.runner then
        ok = bestanden and not absturz
        ergebnis = ok and 'Ergebnis: Pruefung uneu3 bestanden' or 'Ergebnis: Test-Runner fehlgeschlagen'
    else
        ok = ergebnis ~= nil and not absturz and (ergebnis:find(' 0 Fehler') or ergebnis:find(' 0 FEHLER')) ~= nil
        ergebnis = ergebnis or 'Ergebnis: keine Zusammenfassung (Absturz?)'
    end
    if not ok then gesamt_ok = false end
    zeilen[#zeilen + 1] = string.format('%s %-46s %4d s  %s', ok and 'OK    ' or 'FEHLER', r.name, os.time() - t0, ergebnis)
end

io.write('\n================ Zusammenfassung ================\n')
for _, z in ipairs(zeilen) do io.write(z .. '\n') end
io.write(string.format('Gesamt: %s (%d s)\n', gesamt_ok and 'alles bestanden' or 'FEHLER vorhanden', os.time() - start))
os.exit(gesamt_ok and 0 or 1)
