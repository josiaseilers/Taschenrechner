-- Gemeinsame Hilfen fuer die Querschnitt-Tests (reines Lua, kein CAS noetig).
-- Laedt Querschnitte/Querschnitt.lua (oder QUERSCHNITT=<pfad>) und macht interne
-- Funktionen ueber die Tabelle Q zugaenglich. Koordinaten in den Tests sind die
-- internen (u nach rechts, v nach oben); die Anzeige (y, z) haengt von rotation ab.
local M = {}
io.stdout:setvbuf('no')
M.dir = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or ".\\")
M.write = io.write
M.verbose = os.getenv('TEST_VERBOSE') ~= nil
M.filter = arg and arg[1]
M.total, M.fails, M.problems = 0, 0, {}

-- TI-Umgebung
on = {}
platform = { window = { width = function() return 318 end, height = function() return 212 end, invalidate = function() end } }
timer = { start = function() end, stop = function() end, getMilliSecCounter = function() return 0 end }
var = { store = function() end }

-- Zeichen-Attrappe: sammelt alle drawString-Texte (M.texte) mit Position (M.pos) und zaehlt
-- Linien und Polylinien (M.zaehler), um den Zeichenaufwand zu pruefen
M.texte = {}
M.pos = {}
M.zaehler = { linien = 0, polylinien = 0, polypunkte = 0 }
function M.zaehlerReset() M.zaehler = { linien = 0, polylinien = 0, polypunkte = 0 } end
-- Textbreite abhaengig von der eingestellten Schrift (etwas grosszuegiger als auf dem Rechner,
-- damit ein Layout, das hier passt, dort sicher passt)
M.schrift = { stil = 'r', groesse = 10 }
local function utf8len(s) local n = 0; for i = 1, #tostring(s) do local b = tostring(s):byte(i); if b < 128 or b > 191 then n = n + 1 end end; return n end
function M.breite(text) return utf8len(text) * M.schrift.groesse * ((M.schrift.stil == 'b') and 0.66 or 0.62) end
M.gc = setmetatable({}, { __index = function(_, k)
    if k == 'drawString' then return function(_, text, x, y)
        M.texte[#M.texte + 1] = tostring(text)
        M.pos[#M.pos + 1] = { t = tostring(text), x = x, y = y, w = M.breite(text) }
    end end
    if k == 'setFont' then return function(_, _, stil, groesse)
        M.schrift.stil, M.schrift.groesse = stil or 'r', groesse or 10
    end end
    if k == 'drawLine' then return function() M.zaehler.linien = M.zaehler.linien + 1 end end
    if k == 'drawPolyLine' then return function(_, pts)
        M.zaehler.polylinien = M.zaehler.polylinien + 1
        M.zaehler.polypunkte = M.zaehler.polypunkte + #pts / 2
    end end
    if k == 'getStringWidth' then return function(_, text) return M.breite(text) end end
    if k == 'getStringHeight' then return function() return 12 end end
    return function() end
end })

local pfad = os.getenv('QUERSCHNITT') or (M.dir .. '..\\..\\Querschnitte\\Querschnitt.lua')
local f = assert(io.open(pfad, 'rb'), 'Querschnitt.lua nicht gefunden: ' .. pfad)
local code = f:read('*a'); f:close()
if code:sub(1, 3) == string.char(239, 187, 191) then code = code:sub(4) end
local export = [[

_G.__Q = {
  berechneSystem = berechneSystem,
  M = function() return massiv_elemente end, D = function() return duenn_elemente end,
  K = function() return kraefte end,
  R = function() return system_results end,
  smp = function() return berechneSchubmittelpunkt() end,
  duennSchub = berechneDuenneSchubspannung,
  zellen = find_closed_cells,
  schub = function(a, b) return berechneSchubspannungsResultate(a, b) end,
  torsion = berechneTorsionsResultat,
  kraftTorsion = berechneKraftTorsion,
  cfd = coordinatesForDisplay,
  setRotation = function(r) rotation = r end,
  overlap = checkOverlapStatus,
  sigma = function(N, My, Mz) sigma_N, sigma_My = N, My; local ok = finishSigmaCalculation(Mz); return ok and sigma_results end,
  spreadsheet = function(gc) showResults = true; drawSpreadsheet(gc, 318, 2000) end,
  evalInput = evaluate_input,
  status = function() return status end,
  clear = function() on.clearKey(); if qsLoeschFrage then on.enterKey() end end,   -- Rueckfrage bestaetigen
  setShear = function(res) shear_results = res end,
  setTorsion = function(t) torsion_results = t end,
  setView = function(mode, sichtbar) shear_view_mode = mode; shear_profile_visible = sichtbar end,
  setFlags = function(center, tab, momtab) show_shear_center = center; showTable = tab; show_shear_moment_table = momtab; if momtab then shear_moment_table = berechneSchubMomentTabelle() end end,
  update = aktualisiereTorsionsverlauf,
  -- Schub wie auf dem Rechner eingeben: Q_y, Enter, Q_z, Enter (angezeigtes KOS)
  schubEingabe = function(qa, qb)
    openShearInput()
    inputText = tostring(qa); enterShearInput()
    inputText = tostring(qb); enterShearInput()
    return shear_results
  end,
  meldung = function() return qsMeldung end,
  meldungWeg = function() qsMeldung = nil end,
  ftmBezug = function(v) if v then ftm_bezug = v end; return ftm_bezug end,
  loeschFrage = function() return qsLoeschFrage end,
  menu = function(page, row) menuOpen, menuPage, menuRow = page ~= nil, page or 1, row or 1 end,
  menuTexte = function() return buildMenuItems() end,
  tabelle = function(gc) showTable = true; drawTable(gc, 318, 212); showTable = false end,
  kraft = function(k) table.insert(kraefte, k) end,
  auswahl = function(t, i) selected_type, selected_idx = t, i end,
  hover = function(t, i) hover_type, hover_idx = t, i end,
  menuStatus = function() return menuOpen, menuPage, menuRow, selected_type, selected_idx end,
  selektor = function(offen) shear_selector_open = offen end,
  paint = function(gc) showResults = false; on.paint(gc) end,
  toScreen = function(u, v) return toScreen(u, v) end,
  -- Verwoelbung
  verwoelbung = function(M_, G_) return woelb.berechne(M_, G_) end,
  woelb = function() return woelb end,
  woelbEingabe = function(M_, G_)
    woelb.oeffnen()
    if woelb.step == 0 then return nil end
    inputText = tostring(M_); woelb.eingabe()
    inputText = tostring(G_); woelb.eingabe()
    return woelb.results
  end,
  torsionResults = function() return torsion_results end,
  immerVertraeglich = function(f) schub_immer_vertraeglich = f and true or false end,
  inputText = function() return inputText end,
  fmt = function(v) return formatLabel(v) end,
  fange = function(u, v) return fange(u, v) end,
  pending = function() return pending end,
  modus = function() return mode end,
  ursprung = function() return ox, oy, scale end,
  sigmaFelder = function() return sigmaEingabe.felder end,
  sigmaStep = function() return sigma_input_step end,
  sigmaErgebnis = function() return sigma_results end,
  sigmaKennwerte = function() return sigmaEingabe.kennwerte(sigma_results) end,
  sigmaZusatz = function() return sigmaEingabe.zusatzzeilen(sigma_results) end,
  sigmaTabelleZeigen = function(an) showTable = an and true or false end,
  sigmaScroll = function() return sigma_scroll_y end,
  tippe = function(text) for i = 1, #text do on.charIn(text:sub(i, i)) end; on.enterKey() end,
  sigmaTabelle = function(gc) drawSigmaResultsTable(gc, 318, 2000) end,
  hoverZustand = function() return hover_type, hover_idx end,
  schubmittelpunkt = function() shear_center_cache = nil; return berechneSchubmittelpunkt() end,
  standardDicke = function(t) if t then default_t = t end; return default_t end,
  -- Kernflaeche: Modus setzen (1 Geraden, 2 Kernflaeche), Hover, Laengen wie angezeigt
  kern = function(modus) kernMode = modus; kern_build(); return kern_lines, kern_vertices end,
  kernHover = function(linie, punkt) kern_hover_line, kern_hover_pt = linie, punkt end,
  laenge = function(x) return display_length(x) end,
}
]]
assert(loadstring(code .. export, '=' .. pfad))()
M.Q = _G.__Q
M.pfad = pfad

function M.P(u, v) return { u = u, v = v } end
function M.reset() M.Q.clear(); M.Q.setRotation(180) end
function M.massiv(e) e.is_hole = e.is_hole or false; e.is_numeric = e.is_numeric or false; table.insert(M.Q.M(), e); return e end
function M.duenn(p1, p2, t) local e = { points = { p1, p2 }, t = t or 1 }; table.insert(M.Q.D(), e); return e end
-- Linienzug aus Punktliste {u1,v1, u2,v2, ...}
function M.zug(koords, t)
    for i = 1, #koords - 3, 2 do
        M.duenn(M.P(koords[i], koords[i + 1]), M.P(koords[i + 2], koords[i + 3]), t)
    end
end
function M.rechne() M.Q.berechneSystem(); return M.Q.R() end

-- Ergebnisfeld-Texte (so wie auf dem Bildschirm)
function M.ergebnisfeld()
    M.texte, M.pos = {}, {}
    M.Q.spreadsheet(M.gc)
    return M.texte
end
function M.zeileWert(texte, praefix)
    for _, t in ipairs(texte) do
        if t:sub(1, #praefix) == praefix then
            return tonumber(t:match('=%s*([%-%d%.eE%+]+)')), t
        end
    end
    return nil
end

function M.pruef(ok, text)
    M.total = M.total + 1
    if not ok then M.fails = M.fails + 1; M.problems[#M.problems + 1] = (M.titel and (M.titel .. ': ') or '') .. text end
    if not ok or M.verbose then M.write('   ' .. (ok and 'ok ' or 'XX ') .. text .. '\n') end
end
function M.zahl(label, ist, soll, tol)
    tol = tol or 1e-6
    local ok = type(ist) == 'number' and math.abs(ist - soll) <= tol * math.max(1, math.abs(soll))
    M.pruef(ok, string.format('%-52s soll %-14.8g ist %s', label, soll, type(ist) == 'number' and string.format('%.8g', ist) or tostring(ist)))
    return ok
end
function M.wahr(label, bedingung, info) M.pruef(bedingung and true or false, label .. (info and ('  [' .. tostring(info) .. ']') or '')) end
function M.abschnitt(titel) M.titel = titel; M.write('\n== ' .. titel .. '\n') end
function M.fall(name, fn)
    if M.filter and not name:find(M.filter, 1, true) then return end
    M.reset()
    local ok, err = pcall(fn)
    if not ok then M.pruef(false, 'Absturz in ' .. name .. ': ' .. tostring(err):gsub('\n.*', '')) end
end
function M.ende(name)
    M.write(string.format('\nErgebnis %s: %d Pruefungen, %d Fehler\n', name, M.total, M.fails))
    for _, p in ipairs(M.problems) do M.write('   XX ' .. p .. '\n') end
    os.exit(M.fails == 0 and 0 or 1)
end

return M
