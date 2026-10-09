-- Querschnitt.lua: eigenstaendiger Querschnittseditor fuer TI-Nspire CX II CAS
-- Version 2: Massiv-Querschnitte (alle Standardformen) und Duennwandige Profile
-- Mit automatischer Loch-Erkennung, Steiner-Satz, und Hauptachsen-Darstellung.

local massiv_elemente = {}
local duenn_elemente = {}
local kraefte = {}
local pending = {}
local mode = "idle" -- Easteregg1
local selected_idx = nil
local selected_type = nil -- "massiv" oder "duenn"
local hover_type, hover_idx = nil, nil

local scale, ox, oy, raster = 24, 160, 106, 1
local kos_size = 48
local kos_pixel_length = kos_size
local plane, swapped, rotation = 2, false, 180
local menuOpen, menuRow, menuPage = false, 1, 1

local default_t = 1 -- Standarddicke fuer duennwandige Profile
torsion_xi = 1 -- Profilbeiwert fuer offene Duennwandprofile
rasterPunkte = 1 -- Rasterpunkte: 0 keine, 1 normal (1 px), 2 dick (2 px); Weitere Optionen, Zeile 5
local zahlenFormat = 3 -- 1: Brueche/Wurzelbrueche, 2: Brueche, 3: Dezimal
-- Bezug der angezeigten Flaechentraegheitsmomente: "schwerpunkt" (Standard) oder "kos"
-- (Ursprung des gezeichneten Koordinatensystems). Gilt fuer Ergebnisliste und Einzelwerte-Tabelle.
local ftm_bezug = "schwerpunkt"
local qsLoeschFrage = false   -- Sicherheitsfrage vor "alles loeschen"
local casToleranz = 5

local function evaluate_input(expr)
    -- Wertet zuerst den TI-Nspire-Ausdruck und danach eine einfache Lua-Formel aus.
    expr = (tostring(expr or ""):gsub(",", "."))   -- Dezimalkomma zulassen
    if math.eval then
        local ok, val = pcall(function() return tonumber(math.eval("approx(" .. expr .. ")")) end)
        if ok and type(val) == "number" then return val end
    end
    -- Ersatz ohne CAS: Lua-Ausdruck, nur mit den math-Funktionen (sqrt, pi, sin, ...)
    local chunk = (loadstring or load)("return " .. expr)
    if not chunk then return nil end
    if setfenv then setfenv(chunk, setmetatable({math = math}, {__index = math})) end
    local ok, val = pcall(chunk)
    if ok and type(val) == "number" and val == val then return val end
    return nil
end

local function floatToFrac_lua(value, tolerance, max_denominator)
    if math.abs(value) < 1e-10 then return "0" end
    local sign = value < 0 and "-" or ""
    value = math.abs(value)
    max_denominator = max_denominator or 10000
    local h1, h2, k1, k2 = 1, 0, 0, 1
    local rest = value
    for _ = 1, 30 do
        local a = math.floor(rest)
        local h, k = a * h1 + h2, a * k1 + k2
        h2, h1, k2, k1 = h1, h, k1, k
        if k > max_denominator then break end
        if math.abs(value - h / k) <= tolerance + 1e-10 then
            if k == 1 then return sign .. tostring(h) end
            return sign .. tostring(h) .. "/" .. tostring(k)
        end
        if math.abs(rest - a) < 1e-10 then break end
        rest = 1 / (rest - a)
    end
    return nil
end

local function smartToFracStr(value, tolerance)
    if math.abs(value) < 1e-10 then return "0" end
    if math.abs(value - 1) < 1e-10 then return "1" end
    if math.abs(value + 1) < 1e-10 then return "-1" end
    if zahlenFormat ~= 3 then
        local strict = floatToFrac_lua(value, 1e-5, 50)
        if strict then return strict end
        if zahlenFormat == 1 and value * value <= 10000 then
            local square_fraction = floatToFrac_lua(value * value, 1e-4, 2000)
            if square_fraction then
                local numerator, denominator = square_fraction:match("^(%d+)/(%d+)$")
                local num, den = tonumber(numerator) or tonumber(square_fraction), tonumber(denominator) or 1
                local function extract_square(number)
                    for factor = math.floor(math.sqrt(number)), 2, -1 do
                        if number % (factor * factor) == 0 then return factor, number / (factor * factor) end
                    end
                    return 1, number
                end
                local coeff_num, rest_num = extract_square(num)
                local coeff_den, rest_den = extract_square(den)
                local final_coeff, final_rest = extract_square(rest_num * rest_den)
                local total_coeff = coeff_num * final_coeff
                local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end
                local divisor = gcd(total_coeff, coeff_den * rest_den)
                total_coeff = total_coeff / divisor
                local final_den = coeff_den * rest_den / divisor
                local prefix = value < 0 and "-" or ""
                if final_rest == 1 then return prefix .. (final_den == 1 and tostring(total_coeff) or string.format("%d/%d", total_coeff, final_den)) end
                local root = "sqrt(" .. final_rest .. ")"
                if total_coeff == 1 and final_den == 1 then return prefix .. root end
                if final_den == 1 then return prefix .. total_coeff .. "*" .. root end
                if total_coeff == 1 then return prefix .. root .. "/" .. final_den end
                return prefix .. total_coeff .. "*" .. root .. "/" .. final_den
            end
        end
        local loose = floatToFrac_lua(value, tolerance, 10000)
        if loose then return loose end
    end
    return string.format("%.4f", value)
end

local function formatLabel(value)
    if type(value) ~= "number" then return "0" end
    return smartToFracStr(value, 10^(-casToleranz))
end

local function point_to_line_dist(px, py, x1, y1, x2, y2)
    local l2 = (x1-x2)^2 + (y1-y2)^2
    if l2 == 0 then return math.sqrt((px-x1)^2 + (py-y1)^2) end
    local t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2
    t = math.max(0, math.min(1, t))
    local proj_x, proj_y = x1 + t * (x2 - x1), y1 + t * (y2 - y1)
    return math.sqrt((px - proj_x)^2 + (py - proj_y)^2)
end
local showResults = false
local showTable = false
local table_scroll_x = 0
local table_scroll_y = 0
local results_scroll_y = 0
local overlap_pending_elem = nil
local is_numeric_system = false
local inputMode, inputText = false, ""
local status = "Massiv | Duennwand | Ergebnisse"
-- Meldungen, die der Nutzer sehen muss (Fehlergruende, Hinweise), als Box; ESC schliesst sie.
-- Global, weil on.paint und on.escapeKey kaum freie Upvalues haben.
qsMeldung = nil   -- { titel = ..., text = ..., fehler = true/false }
local function meldung(text, titel, fehler)
    status = text
    qsMeldung = { text = text, titel = titel or "Hinweis", fehler = fehler and true or false, scroll = 0, scrollMax = 0 }
end
-- Meldungsbox: rot bei Fehlergruenden, gelb bei Hinweisen; Text auf Boxbreite umbrechen. Passt er
-- nicht auf den Bildschirm, zeigt die Box einen Ausschnitt, den hoch/runter verschiebt (on.arrowKey),
-- dazu einen Zeilenzaehler und rechts Pfeile, solange oben bzw. unten noch etwas steht.
function zeichneQsMeldung(gc, w, h)
    local m = qsMeldung
    local boxW = math.min(w - 20, 300)
    gc:setFont("sansserif", "r", 9)
    local zeilen, zeile = {}, ""
    for wort in tostring(m.text):gmatch("%S+") do
        local probe = (zeile == "") and wort or (zeile .. " " .. wort)
        if zeile ~= "" and gc:getStringWidth(probe) > boxW - 24 then zeilen[#zeilen + 1] = zeile; zeile = wort else zeile = probe end
    end
    if zeile ~= "" then zeilen[#zeilen + 1] = zeile end
    local boxH = math.min(28 + 13 * #zeilen, h - 10)
    local sichtbar = math.max(1, math.floor((boxH - 28) / 13))
    m.scrollMax = math.max(0, #zeilen - sichtbar)
    m.scroll = math.max(0, math.min(m.scroll or 0, m.scrollMax))
    local boxX, boxY = math.floor((w - boxW) / 2), math.floor((h - boxH) / 2)
    if m.fehler then gc:setColorRGB(255, 205, 200) else gc:setColorRGB(255, 235, 150) end
    gc:fillRect(boxX, boxY, boxW, boxH)
    gc:setColorRGB(0, 0, 0); gc:setPen("thin", "smooth"); gc:drawRect(boxX, boxY, boxW, boxH)
    gc:setFont("sansserif", "b", 10); gc:drawString(m.titel .. ":", boxX + 8, boxY + 6)
    gc:setFont("sansserif", "r", 9)
    for k = 1, math.min(sichtbar, #zeilen - m.scroll) do
        gc:drawString(zeilen[m.scroll + k], boxX + 8, boxY + 12 + 13 * k)
    end
    gc:drawString("[Esc]", boxX + boxW - 34, boxY + 6)
    if m.scrollMax > 0 then
        local zaehler = string.format("%d-%d/%d", m.scroll + 1, m.scroll + sichtbar, #zeilen)
        gc:drawString(zaehler, boxX + boxW - 40 - gc:getStringWidth(zaehler), boxY + 6)
        local ax = boxX + boxW - 10
        if m.scroll > 0 then gc:fillPolygon({ ax - 4, boxY + 30, ax + 4, boxY + 30, ax, boxY + 24 }) end
        if m.scroll < m.scrollMax then gc:fillPolygon({ ax - 4, boxY + boxH - 10, ax + 4, boxY + boxH - 10, ax, boxY + boxH - 4 }) end
    end
end
-- Hinweise, die der Nutzer nicht uebersehen soll (Funktionen weiter unten, nach den Anzeigehilfen)
local qsHinweis = { dicke_gezeigt = false }
-- Manuell ueberschriebene Querschnittswerte (Schwerpunktwerte im internen KOS, nil = berechnet).
-- sig ist die Geometrie-Signatur, zu der sie gehoeren; aendert sich der Querschnitt, fallen sie weg.
-- ys, zs: manueller Schwerpunkt relativ zum ersten Punkt der Geometrie (bleibt beim KOS-Verschieben gueltig)
local qsWerte = { A = nil, Iy = nil, Iz = nil, Iyz = nil, ys = nil, zs = nil, sig = nil }
local escape_clear_pending = false
local sigma_input_step = 0
local sigma_N, sigma_My, sigma_Mz = nil, nil, nil
-- Felder der sigma-Eingabe ("N", "Ma", "Mb", "x") und Versatz der Kraftebene entlang der Stabachse
local sigmaEingabe = { felder = { "N", "Ma" }, versatz = 0 }
local sigma_oblique = false
local sigma_results = nil
local sigma_scroll_y, sigma_table_scroll_y = 0, 0
local shear_results = nil
local shear_input_step = 0
local shear_Qa, shear_Qb = nil, nil
local shear_M = 0
local shear_profile_visible = false
local shear_hover_index = nil
local shear_view_mode = 0
local shear_selector_open = false
local shear_external_input = false
local show_shear_center = false
local show_shear_moment_table = false
local shear_moment_table = nil
local force_unit, length_unit, moment_unit = "N", "mm", "Nm"
local force_units = {N = 1, kN = 1000}
local length_units = {m = 1000, dm = 100, cm = 10, mm = 1}
local moment_units = {Nm = 1000, Ncm = 10, Nmm = 1, kNm = 1000000, kNcm = 10000, kNmm = 1000}

local function unit_factor(unit)
    return force_units[unit] or length_units[unit] or moment_units[unit] or 1
end

local function input_to_internal(value, unit)
    return value * unit_factor(unit)
end

local function cycle_unit(current, units)
    for index, unit in ipairs(units) do
        if unit == current then return units[index % #units + 1] end
    end
    return units[1]
end

local function unit_label(power)
    if power == 1 then return length_unit end
    return length_unit .. "^" .. power
end

local function display_length(value) return value / unit_factor(length_unit) end
local function display_area(value) return value / unit_factor(length_unit)^2 end
local function display_volume(value) return value / unit_factor(length_unit)^3 end
local function display_inertia(value) return value / unit_factor(length_unit)^4 end
local function display_moment(value) return value / unit_factor(moment_unit) end
local function display_force(value) return value / unit_factor(force_unit) end
local torsion_input_step, torsion_M, torsion_results = 0, nil, nil
-- Verwoelbung: eigener Modus unter [b] -> 7. Das dort eingegebene MT gilt nur in dieser Ansicht
-- (bis Esc) und wird nicht an die Torsion der Schubspannungsrechnung uebergeben.
local woelb = { step = 0, M = nil, G = 81000, results = nil, visible = false }
local berechneSchubspannungsResultate
local system_results = nil
kernMode = 0
local kern_lines, kern_pts, kern_vertices = {}, {}, {}
local kern_hover_line, kern_hover_pt = nil, nil
local kern_build = nil
local kern_collect_points
local find_closed_cells
local berechneSchubmittelpunkt
-- Duennwandige Kreise und Boegen (Mittellinie mit Dicke t): Abstand fuer Hover, Punkte zum Zeichnen,
-- Kreisrohr-Erkennung (Bredt) und Pruefung, ob Boegen an andere Elemente anschliessen
local duennKurve = {}
local shear_center_cache = nil   -- Schubmittelpunkt haengt nur von der Geometrie ab
schub_immer_vertraeglich = false -- nur fuer Tests: q0 immer aus der Vertraeglichkeit (Gegenprobe zur Symmetrie)
local schub_grund = nil          -- Begruendung, wenn Schub nicht berechnet wird
local coordinatesForDisplay

local function current_axes()
    local p = {{"x", "y"}, {"y", "z"}, {"x", "z"}}
    local a, b = p[plane][1], p[plane][2]
    if swapped then return b, a end
    return a, b
end

-- Haben eingezeichnete Kraefte eine Komponente in der Querschnittsebene (Querkraft)?
function sigmaEingabe.hatQuerkraefte()
    for _, kraft in ipairs(kraefte) do
        if math.abs(tonumber(kraft.fa) or 0) > 1e-12 or math.abs(tonumber(kraft.fb) or 0) > 1e-12 then return true end
    end
    return false
end

-- Name der Stabachse (die Achse, die nicht in der Querschnittsebene liegt)
function sigmaEingabe.stabachse()
    local a, b = current_axes()
    for _, n in ipairs({ "x", "y", "z" }) do
        if n ~= a and n ~= b then return n end
    end
    return "x"
end

function sigmaEingabe.aufforderung()
    local feld = sigmaEingabe.felder[sigma_input_step]
    local a, b = current_axes()
    if feld == "N" then return "N in " .. force_unit .. " eingeben, dann Enter." end
    if feld == "Ma" then return "M" .. a .. " in " .. moment_unit .. " eingeben, dann Enter." end
    if feld == "Mb" then return "M" .. b .. " in " .. moment_unit .. " eingeben, dann Enter." end
    return "Abstand Δ" .. sigmaEingabe.stabachse() .. " zwischen Schnitt und Kraftebene in " .. length_unit .. " eingeben."
end

local function openSigmaInput(oblique)
    qsMeldung = nil
    sigma_oblique = oblique == true
    sigma_input_step, inputText = 1, ""
    sigma_results, sigma_scroll_y, sigma_table_scroll_y = nil, 0, 0
    showResults, showTable, menuOpen = true, false, false
    -- Der Versatz wird nur gefragt, wenn eingezeichnete Kraefte eine Querkomponente haben:
    -- sonst gaebe es kein Moment aus Querkraft und das Feld waere ohne Wirkung.
    sigmaEingabe.felder = sigma_oblique and { "N", "Ma", "Mb" } or { "N", "Ma" }
    if sigmaEingabe.hatQuerkraefte() then table.insert(sigmaEingabe.felder, "x") end
    sigmaEingabe.versatz = 0
    status = sigmaEingabe.aufforderung()
end

local function openShearInput()
    qsMeldung = nil
    shear_input_step, inputText = 1, ""
    shear_M = 0
    shear_results = nil
    shear_view_mode, shear_selector_open = 0, false
    showResults, showTable, menuOpen = false, false, false
    local a, b = current_axes()
        status = "Q" .. a .. " und Q" .. b .. " eingeben, dann Enter." 
end

local function openShearFromForces()
    qsMeldung = nil
    shear_input_step, shear_Qa, shear_Qb = 0, 0, 0
    shear_results = berechneSchubspannungsResultate(0, 0)
    shear_view_mode, shear_selector_open = 0, false
    showResults, showTable, menuOpen = false, false, false
    if shear_results then
        shear_selector_open = true
        status = "Eingetragene Kräfte ausgewertet. V: Verlauf wählen."
    else
        meldung(schub_grund or "Schubspannung nicht berechenbar.", "Schub nicht berechnet", true)
    end
    platform.window:invalidate()
end

local function openTorsionInput()
    qsMeldung = nil
    torsion_input_step, inputText = 1, ""
    torsion_results = nil
    showResults, showTable, menuOpen = true, false, false
    status = "Torsionsmoment MT in Nm eingeben."
end

-- Torsion nach TM2 (keine Prandtl-Loesung fuer massive Querschnitte):
--  * offene duennwandige Profile: I_T = sum xi/3 h t^3, tau_max = MT/I_T * t_max
--  * genau eine geschlossene Zelle (Bredt): I_T = 4 A_m^2 / Int ds/t, tau_max = MT/(2 A_m t_min)
--  * mehrzellig, massiv oder gemischt massiv/duennwandig: nicht berechnet (Meldung)
local function berechneTorsionsResultat(moment)
    local r = system_results
    if not r then return nil end
    if #duenn_elemente == 0 or #massiv_elemente > 0 then
        meldung("Torsion nur fuer rein duennwandige Profile (offen oder einzellig geschlossen); fuer massive Querschnitte keine TM2-Formel.", "Torsion nicht berechnet", true)
        return nil
    end
    if not duennKurve.rohr() then
        for _, elem in ipairs(duenn_elemente) do
            if elem.type == "duenn_kreis" or (duennKurve.gekruemmt(elem) and duennKurve.verbunden()) then
                meldung("Torsion mit Kreisen/Boegen nur fuer ein einzelnes Kreisrohr oder freie (offene) Boegen; angeschlossene Boegen koennen eine Zelle schliessen.", "Torsion nicht berechnet", true)
                return nil
            end
        end
    end
    local It_closed, Am, cells, info = find_closed_cells()
    if cells >= 2 then
        meldung("Mehrzelliges Profil: Torsion statisch unbestimmt, nicht berechnet.", "Torsion nicht berechnet", true)
        return nil
    end
    if cells == 1 then
        return {M = moment, It = It_closed, Am = Am, tau = math.abs(moment) / math.max(2 * Am * info.t_min, 1e-12),
                closed = true, t_min = info.t_min}
    end
    local t_max = 0
    for _, elem in ipairs(duenn_elemente) do t_max = math.max(t_max, elem.t or default_t) end
    local It = r.It or 0
    if It <= 1e-12 then
        meldung("I_T = 0: Torsion nicht berechenbar.", "Torsion nicht berechnet", true)
        return nil
    end
    return {M = moment, It = It, Am = 0, tau = math.abs(moment) / It * t_max, closed = false, t_max = t_max}
end

-- Torsionsschubspannung an einer Stuetzstelle: in der Zelle Bredt (q_T = MT/(2 A_m), im
-- Umlaufsinn), in offenen Teilen tau = MT/I_T * t (Maximalwert am Rand)
local function torsionsTau(result, sample)
    local thickness = math.max(sample.thickness or default_t, 1e-12)
    if result.closed and sample.in_cell then
        return (sample.cell_sign or 1) * result.M / math.max(2 * result.Am, 1e-12) / thickness
    end
    return (sample.direction or 1) * result.M / math.max(result.It, 1e-12) * thickness
end

local function aktualisiereTorsionsverlauf(result)
    if not result or not shear_results or not shear_results.samples then return end
    local max_total = 0
    for _, sample in ipairs(shear_results.samples) do
        sample.tau_t = torsionsTau(result, sample)
        if result.closed and sample.in_cell then
            sample.tau_total = (sample.tau or 0) + sample.tau_t
        else
            sample.tau_total = math.abs(sample.tau or 0) + math.abs(sample.tau_t)
        end
        max_total = math.max(max_total, math.abs(sample.tau_total))
    end
    shear_results.max_tau_total = max_total
end

local function torsionTauAtSample(sample)
    if not torsion_results then return sample.tau_t or 0 end
    return torsionsTau(torsion_results, sample)
end

local function combinedTauAtSample(sample)
    local shear_tau = sample.tau or 0
    local torsion_tau = torsionTauAtSample(sample)
    if sample.in_cell then return shear_tau + torsion_tau end
    return math.abs(shear_tau) + math.abs(torsion_tau)
end

local function displayedMomentDensity(sample)
    local r = qsWerte.geoSicht(system_results)
    if not r then return 0, 0 end
    local display_u, display_v = coordinatesForDisplay(sample.u - r.ys, sample.v - r.zs)
    local thickness = sample.thickness or default_t
    return display_u * thickness, display_v * thickness
end

local function displayedVector(u, v)
    return coordinatesForDisplay(u, v)
end

local function enterTorsionInput()
    local value = evaluate_input(inputText)
    if not value then meldung("Ungueltige Torsionseingabe.", "Eingabe", true); inputText = ""; return true end
    value = input_to_internal(value, moment_unit)
    torsion_M, torsion_input_step, inputText = value, 0, ""
    torsion_results = berechneTorsionsResultat(value)
    aktualisiereTorsionsverlauf(torsion_results)
    if torsion_results then status = "Torsionsspannung berechnet." end
    if qsHinweis.xiNoetig(torsion_results) then qsHinweis.melde(qsHinweis.xiText()) end
    showResults = true
    return true
end

local function berechneKraftTorsion()
    if not system_results or #duenn_elemente == 0 then return nil end
    local in_ebene = false
    for _, kraft in ipairs(kraefte) do
        if math.abs(tonumber(kraft.fa) or 0) > 1e-12 or math.abs(tonumber(kraft.fb) or 0) > 1e-12 then in_ebene = true end
    end
    if not in_ebene then return nil end
    -- Bezugspunkt fuer das Torsionsmoment ist der Schubmittelpunkt M (nicht der Schwerpunkt)
    local center = berechneSchubmittelpunkt()
    if not center then return nil end
    local moment = 0
    for _, kraft in ipairs(kraefte) do
        local fa, fb = tonumber(kraft.fa) or 0, tonumber(kraft.fb) or 0
        if (math.abs(fb) > 1e-12 and not center.known_u) or (math.abs(fa) > 1e-12 and not center.known_v) then
            meldung("Torsion aus Kraeften: Schubmittelpunkt statisch unbestimmt, Torsionsmoment nicht bestimmbar.", "Torsion nicht berechnet", true)
            return nil
        end
        -- M_x = du * F_v - dv * F_u (intern rechtshaendig, x aus der Bildebene)
        moment = moment + (kraft.u - center.u) * fb - (kraft.v - center.v) * fa
    end
    if math.abs(moment) < 1e-9 then return nil end
    return berechneTorsionsResultat(moment)
end

local function enterShearInput()
    local val = evaluate_input(inputText)
    if not val then
        meldung("Ungueltige Schubkraft-Eingabe.", "Eingabe", true)
        inputText = ""
        platform.window:invalidate()
        return true
    end
    if shear_input_step == 1 then
        shear_Qa, shear_input_step, inputText = input_to_internal(val, force_unit), 2, ""
        local _, b = current_axes()
            status = "Q" .. b .. " in " .. force_unit .. " eingeben, dann Enter." 
    elseif shear_input_step == 2 then
        shear_Qb, inputText = input_to_internal(val, force_unit), ""
        if shear_external_input then
            shear_input_step = 4
            status = "MT in " .. moment_unit .. " eingeben, dann Enter."
        else
            shear_input_step = 0
            shear_results = berechneSchubspannungsResultate(shear_Qa, shear_Qb)
            shear_selector_open = shear_results ~= nil
            if shear_results then status = "Schubkräfte ausgewertet. V: Verlauf waehlen."
            else meldung(schub_grund or "Schubspannung nicht berechenbar.", "Schub nicht berechnet", true) end
        end
    else
        shear_M, shear_input_step, inputText = input_to_internal(val, moment_unit), 0, ""
        shear_results = berechneSchubspannungsResultate(shear_Qa or 0, shear_Qb or 0)
        torsion_M = shear_M
        torsion_results = berechneTorsionsResultat(shear_M)
        aktualisiereTorsionsverlauf(torsion_results)
        if qsHinweis.xiNoetig(torsion_results) then qsHinweis.melde(qsHinweis.xiText()) end
        shear_external_input = false
        shear_selector_open = shear_results ~= nil
        showResults = true
        if shear_results then status = "Belastungen ausgewertet. V: Verlauf waehlen."
        elseif schub_grund then meldung(schub_grund, "Schub nicht berechnet", true) end
    end
    platform.window:invalidate()
    return true
end

local function toggleCalculationMenu()
    if sigma_input_step ~= 0 or inputMode then return end
    if shear_results and shear_input_step == 0 then
        if menuOpen and menuPage == 8 then
            menuOpen = false
            return
        end
        menuOpen, menuPage, menuRow = true, 8, 1
        showResults, showTable = false, false
        return
    end
    if menuOpen and menuPage == 5 then
        menuOpen = false
        return
    end
    if not system_results then meldung("Kein Querschnitt vorhanden.", "Hinweis", true) end
    menuOpen, menuPage, menuRow = true, 5, 1
    showResults, showTable = false, false
end

local function axes()
    return current_axes()
end

local function toScreen(u, v) return ox + u * scale, oy - v * scale end
local function toScreenKOS(u, v)
    local x, y
    if rotation == 0 then x, y = u, -v
    elseif rotation == 90 then x, y = -v, -u
    elseif rotation == 180 then x, y = -u, v
    else x, y = v, u end
    return ox + x * scale, oy + y * scale
end
local function fromScreen(x, y) return (x - ox) / scale, (oy - y) / scale end
local function snap(x)
    local q = x / raster
    if q >= 0 then return math.floor(q + .5) * raster end
    return math.ceil(q - .5) * raster
end

-- Fangpunkte: die Punkte, die Flaechen und Elemente definieren (bei Rechtecken auch die beiden
-- gegenueberliegenden Ecken), und die schon geklickten Punkte des Elements, das gerade entsteht.
-- Sie wirken wie zusaetzliche Rasterpunkte: ein Klick landet auf dem naechsten Kandidaten, egal
-- ob Rasterpunkt oder Fangpunkt. So lassen sich auch Punkte treffen, die nach exakter
-- Koordinateneingabe oder KOS-Verschiebung nicht mehr auf dem Raster liegen.
local function fange(u, v)
    local liste = {}
    local function dazu(pt) if pt and pt.u and pt.v then liste[#liste + 1] = pt end end
    for _, elem in ipairs(massiv_elemente) do
        for _, pt in ipairs(elem.points or {}) do dazu(pt) end
        if elem.type == "rect" and elem.points[1] and elem.points[2] then
            local p1, p2 = elem.points[1], elem.points[2]
            dazu({ u = p1.u, v = p2.v }); dazu({ u = p2.u, v = p1.v })
        end
    end
    for _, elem in ipairs(duenn_elemente) do
        for _, pt in ipairs(elem.points or {}) do dazu(pt) end
    end
    for _, pt in ipairs(pending) do dazu(pt) end
    local bu, bv = snap(u), snap(v)
    local best = (bu - u) ^ 2 + (bv - v) ^ 2
    for _, pt in ipairs(liste) do
        local d = (pt.u - u) ^ 2 + (pt.v - v) ^ 2
        if d < best then best, bu, bv = d, pt.u, pt.v end
    end
    return bu, bv
end

-- Intern: u nach rechts, v nach oben. Angezeigtes KOS (y, z) wie von toScreenKOS gezeichnet:
-- 0: y rechts, z oben | 90: y oben, z links | 180: y links, z unten | 270: y unten, z rechts
coordinatesForDisplay = function(u, v)
    if rotation == 90 then return v, -u end
    if rotation == 180 then return -u, -v end
    if rotation == 270 then return -v, u end
    return u, v
end

local function coordinatesFromDisplay(a, b)
    if rotation == 90 then return -b, a end
    if rotation == 180 then return -a, -b end
    if rotation == 270 then return b, -a end
    return a, b
end

-- Traegheitsmomente (intern Iy = Int v^2, Iz = Int u^2, Iyz = -Int u v) im angezeigten KOS
local function inertiaForDisplay(Iy, Iz, Iyz)
    if rotation == 90 or rotation == 270 then return Iz, Iy, -Iyz end
    return Iy, Iz, Iyz
end

-- Hauptachsenwinkel im angezeigten KOS (gemessen von der angezeigten y-Achse)
local function alphaForDisplay(alpha)
    if rotation == 90 or rotation == 270 then
        alpha = alpha - math.pi / 2
        if alpha <= -math.pi / 2 then alpha = alpha + math.pi end
    end
    return alpha
end

-- Hauptachsensystem (HAS) wie in der σx-Tabelle: Ursprung im Schwerpunkt, η (Hauptachse 1) unter
-- φ* zur angezeigten y-Achse, ζ (Hauptachse 2) um 90° weiter. Gebraucht fuer die gezeichneten
-- Hauptachsen und die Beschriftung der Kernflaeche, damit Pfeile und Vorzeichen zusammenpassen.
kernHAS = {}
function kernHAS.richtungen()   -- Einheitsvektoren von η und ζ in internen Koordinaten (u, v)
    local phi = alphaForDisplay(system_results.alpha or 0)
    local c, sn = math.cos(phi), math.sin(phi)
    local e1u, e1v = coordinatesFromDisplay(c, sn)
    local e2u, e2v = coordinatesFromDisplay(-sn, c)
    return e1u, e1v, e2u, e2v
end
function kernHAS.koordinaten(u, v)   -- interner Punkt -> (η, ζ) vom Schwerpunkt aus
    local r = system_results
    local e1u, e1v, e2u, e2v = kernHAS.richtungen()
    local du, dv = u - r.ys, v - r.zs
    return du * e1u + dv * e1v, du * e2u + dv * e2v
end

local function forceComponentsForDisplay(fu, fv)
    return coordinatesForDisplay(fu, fv)
end

local function forceComponentsFromDisplay(fu, fv)
    return coordinatesFromDisplay(fu, fv)
end

local function setDisplayedPointCoordinate(point, coordinate, value)
    local display_u, display_v = coordinatesForDisplay(point.u, point.v)
    if coordinate == "u" then display_u = value else display_v = value end
    point.u, point.v = coordinatesFromDisplay(display_u, display_v)
end

local function poly_props(pts)
    local A, sy, sz, Iy, Iz, Iyz = 0, 0, 0, 0, 0, 0
    for i = 1, #pts do
        local p1, p2 = pts[i], pts[i % #pts + 1]
        local c = p1.u * p2.v - p2.u * p1.v
        A = A + c
        sy = sy + (p1.u + p2.u) * c
        sz = sz + (p1.v + p2.v) * c
        Iy = Iy + (p1.v^2 + p1.v*p2.v + p2.v^2) * c
        Iz = Iz + (p1.u^2 + p1.u*p2.u + p2.u^2) * c
        Iyz = Iyz + (p1.u*p2.v + 2*p1.u*p1.v + 2*p2.u*p2.v + p2.u*p1.v) * c
    end
    A = A / 2
    if math.abs(A) < 1e-9 then return 0, 0, 0, 0, 0, 0 end
    if A < 0 then A, sy, sz, Iy, Iz, Iyz = -A, -sy, -sz, -Iy, -Iz, -Iyz end
    local ys, zs = sy / (6 * A), sz / (6 * A)
    return A, ys, zs, Iy / 12 - A * zs^2, Iz / 12 - A * ys^2, -(Iyz / 24 - A * ys * zs)
end

local function sector_props(p1, p2, p3, is_segment)
    local R = math.sqrt((p2.u-p1.u)^2 + (p2.v-p1.v)^2)
    if R < 1e-5 then return 0, 0, 0, 0, 0, 0 end
    local a1 = math.atan2(p2.v-p1.v, p2.u-p1.u)
    local diff = math.atan2(p3.v-p1.v, p3.u-p1.u) - a1
    if diff <= 0 then diff = diff + 2 * math.pi end
    local alpha = diff / 2
    local A, d
    if is_segment then
        A = R^2 / 2 * (2 * alpha - math.sin(2 * alpha))
        d = 4 * R * math.sin(alpha)^3 / (3 * (2 * alpha - math.sin(2 * alpha)))
    else
        A, d = alpha * R^2, 2 * R * math.sin(alpha) / (3 * alpha)
    end
    local phi = a1 + alpha
    local ys, zs = p1.u + d * math.cos(phi), p1.v + d * math.sin(phi)
    local sa, ca = math.sin(alpha), math.cos(alpha)
    local Iu = R^4 / 4 * (alpha - sa * ca)          -- um die Symmetrieachse des Sektors
    local Iv0 = R^4 / 4 * (alpha + sa * ca)         -- senkrecht dazu, um den Kreismittelpunkt
    if is_segment then
        -- Kreisabschnitt = Sektor minus Dreieck (Mittelpunkt, P2, P3) mit Basis 2 R sa und Hoehe R ca
        -- (fuer alpha > 90 Grad ist ca < 0, dann wird das Dreieck addiert)
        Iu = Iu - R^4 * sa^3 * ca / 6
        Iv0 = Iv0 - R^4 * sa * ca^3 / 2
    end
    local Iv = Iv0 - A * d^2
    local c, s = math.cos(phi), math.sin(phi)
    return A, ys, zs, Iu*c^2 + Iv*s^2, Iu*s^2 + Iv*c^2, (Iu-Iv)*s*c
end

local function thin_line_props(p1, p2, t)
    local du, dv = p2.u-p1.u, p2.v-p1.v
    local L = math.sqrt(du^2 + dv^2)
    local A, ys, zs = L*t, (p1.u+p2.u)/2, (p1.v+p2.v)/2
    if L < 1e-9 then return 0, ys, zs, 0, 0, 0, 0 end
    local Iy = t*L/12*dv^2
    local Iz = t*L/12*du^2
    local Iyz = -(t*L/12)*du*dv
    return A, ys, zs, Iy, Iz, Iyz, L
end

local function berechneLokaleWerte(elem)
    local A, ys, zs, Iy, Iz, Iyz = 0,0,0,0,0,0
    local p = elem.points
    if elem.type == "massiv_linie" then
        local p1, p2 = elem.points[1], elem.points[2]
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local L = math.sqrt(du^2 + dv^2)
        local nx, ny = 0, 0
        if L > 1e-9 then nx, ny = (-dv/L) * (elem.t/2), (du/L) * (elem.t/2) end
        local pts = {
            {u = p1.u + nx, v = p1.v + ny},
            {u = p2.u + nx, v = p2.v + ny},
            {u = p2.u - nx, v = p2.v - ny},
            {u = p1.u - nx, v = p1.v - ny}
        }
        A, ys, zs, Iy, Iz, Iyz = poly_props(pts)
    end
    
    if elem.type == "rect" then
        local pts = {
            {u=p[1].u, v=p[1].v}, {u=p[2].u, v=p[1].v},
            {u=p[2].u, v=p[2].v}, {u=p[1].u, v=p[2].v}
        }
        A, ys, zs, Iy, Iz, Iyz = poly_props(pts)
    elseif elem.type == "circle" or elem.type == "duenn_kreis" then
        local R = math.sqrt((p[2].u-p[1].u)^2 + (p[2].v-p[1].v)^2)
        A = math.pi * R^2
        ys, zs = p[1].u, p[1].v
        Iy, Iz = math.pi * R^4 / 4, math.pi * R^4 / 4
        Iyz = 0
    elseif elem.type == "triangle" or elem.type == "trapezoid" then
        A, ys, zs, Iy, Iz, Iyz = poly_props(p)
    elseif elem.type == "sector" then
        A, ys, zs, Iy, Iz, Iyz = sector_props(p[1], p[2], p[3], false)
    elseif elem.type == "segment" then
        A, ys, zs, Iy, Iz, Iyz = sector_props(p[1], p[2], p[3], true)
    end
    
    if elem.is_hole then A, Iy, Iz, Iyz = -A, -Iy, -Iz, -Iyz end
    return A, ys, zs, Iy, Iz, Iyz
end

-- === GRAPH & TORSION ===
-- Mittelliniengraph der duennwandigen Elemente. Gerade Elemente werden an Schnitt- und
-- Beruehrpunkten (T-Knoten) sowie optional an den Achsen u = achse_u und v = achse_v geteilt.
-- Doppelt gezeichnete Kanten werden zu einer Kante (Dicken addiert) zusammengelegt.
-- Rueckgabe: nodes {u, v, edges, arrivals}, edges {i, index, p1, p2, n1, n2, t}, nicht_gerade
local function duennGraph(achse_u, achse_v)
    local tol = 1e-6
    local nodes, edges = {}, {}
    local nicht_gerade = false
    local function node_for(u, v)
        for index, node in ipairs(nodes) do
            if math.abs(node.u - u) <= tol and math.abs(node.v - v) <= tol then return index end
        end
        table.insert(nodes, {u = u, v = v, edges = {}, arrivals = {}})
        return #nodes
    end
    local function cross(au, av, bu, bv) return au * bv - av * bu end
    local function add_parameter(list, value)
        if value < -tol or value > 1 + tol then return end
        value = math.max(0, math.min(1, value))
        for _, existing in ipairs(list) do
            if math.abs(existing - value) <= tol then return end
        end
        table.insert(list, value)
    end
    local params = {}
    for index, elem in ipairs(duenn_elemente) do
        if not elem.type or elem.type == "duenn_linie" then params[index] = {0, 1} else nicht_gerade = true end
    end
    for first = 1, #duenn_elemente do
        if params[first] then
            local p, p2 = duenn_elemente[first].points[1], duenn_elemente[first].points[2]
            local rx, rv = p2.u - p.u, p2.v - p.v
            for second = first + 1, #duenn_elemente do
                if params[second] then
                    local q, q2 = duenn_elemente[second].points[1], duenn_elemente[second].points[2]
                    local sx, sv = q2.u - q.u, q2.v - q.v
                    local qpx, qpv = q.u - p.u, q.v - p.v
                    local denominator = cross(rx, rv, sx, sv)
                    if math.abs(denominator) > tol then
                        add_parameter(params[first], cross(qpx, qpv, sx, sv) / denominator)
                        add_parameter(params[second], cross(qpx, qpv, rx, rv) / denominator)
                    elseif math.abs(cross(qpx, qpv, rx, rv)) <= tol then
                        -- kollinear: Endpunktberuehrungen und ueberlappende Teilstrecken
                        local first_length, second_length = rx^2 + rv^2, sx^2 + sv^2
                        if first_length > tol then
                            add_parameter(params[first], ((q.u - p.u) * rx + (q.v - p.v) * rv) / first_length)
                            add_parameter(params[first], ((q2.u - p.u) * rx + (q2.v - p.v) * rv) / first_length)
                        end
                        if second_length > tol then
                            add_parameter(params[second], ((p.u - q.u) * sx + (p.v - q.v) * sv) / second_length)
                            add_parameter(params[second], ((p2.u - q.u) * sx + (p2.v - q.v) * sv) / second_length)
                        end
                    end
                end
            end
            if achse_u and math.abs(rx) > tol then add_parameter(params[first], (achse_u - p.u) / rx) end
            if achse_v and math.abs(rv) > tol then add_parameter(params[first], (achse_v - p.v) / rv) end
        end
    end
    for index, elem in ipairs(duenn_elemente) do
        local list = params[index]
        if list then
            table.sort(list)
            local p1, p2 = elem.points[1], elem.points[2]
            for part = 1, #list - 1 do
                local a, b = list[part], list[part + 1]
                local q1 = {u = p1.u + a * (p2.u - p1.u), v = p1.v + a * (p2.v - p1.v)}
                local q2 = {u = p1.u + b * (p2.u - p1.u), v = p1.v + b * (p2.v - p1.v)}
                local n1, n2 = node_for(q1.u, q1.v), node_for(q2.u, q2.v)
                if n1 ~= n2 then
                    local doppelt = nil
                    for _, k in ipairs(nodes[n1].edges) do
                        local e = edges[k]
                        if (e.n1 == n1 and e.n2 == n2) or (e.n1 == n2 and e.n2 == n1) then doppelt = e end
                    end
                    if doppelt then
                        doppelt.t = doppelt.t + (elem.t or default_t)
                    else
                        table.insert(edges, {index = index, p1 = q1, p2 = q2, n1 = n1, n2 = n2, t = elem.t or default_t, used = false})
                        edges[#edges].i = #edges
                        table.insert(nodes[n1].edges, #edges)
                        table.insert(nodes[n2].edges, #edges)
                    end
                end
            end
        end
    end
    return nodes, edges, nicht_gerade
end

-- Zellenanalyse: freie Aeste abschneiden, Zellenzahl = Kanten - Knoten + Komponenten des Restes.
-- Bei genau einer Zelle: Umlauf mit A_m, Integral ds/t, t_min und Umlaufsinn je Kante.
local function duennZellen(nodes, edges)
    local aktiv = {}
    for i = 1, #edges do aktiv[i] = true end
    local changed = true
    while changed do
        changed = false
        for _, node in ipairs(nodes) do
            local deg, last = 0, nil
            for _, k in ipairs(node.edges) do if aktiv[k] then deg, last = deg + 1, k end end
            if deg == 1 then aktiv[last] = false; changed = true end
        end
    end
    local parent, rest_e, rest_n, comp = {}, 0, 0, 0
    local function find(x) while parent[x] ~= x do x = parent[x] end return x end
    for i, e in ipairs(edges) do
        if aktiv[i] then
            rest_e = rest_e + 1
            for _, n in ipairs({e.n1, e.n2}) do
                if not parent[n] then parent[n] = n; rest_n = rest_n + 1 end
            end
        end
    end
    for i, e in ipairs(edges) do
        if aktiv[i] then
            local a, b = find(e.n1), find(e.n2)
            if a ~= b then parent[a] = b end
        end
    end
    for n in pairs(parent) do if find(n) == n then comp = comp + 1 end end
    local info = {cells = rest_e - rest_n + comp, in_loop = aktiv, Am = 0, It = 0}
    if info.cells ~= 1 then return info end
    -- Umlauf ablaufen
    local start_edge
    for i = 1, #edges do if aktiv[i] then start_edge = i; break end end
    local start_node = edges[start_edge].n1
    local current, edge_i = start_node, start_edge
    local dirs, area2, sum_ds_t, t_min, schritte = {}, 0, 0, math.huge, 0
    repeat
        local e = edges[edge_i]
        local forward = e.n1 == current
        local nxt = forward and e.n2 or e.n1
        local a, b = nodes[current], nodes[nxt]
        area2 = area2 + (a.u * b.v - b.u * a.v)
        sum_ds_t = sum_ds_t + math.sqrt((b.u - a.u)^2 + (b.v - a.v)^2) / e.t
        t_min = math.min(t_min, e.t)
        dirs[edge_i] = forward and 1 or -1
        current = nxt
        local next_edge = nil
        for _, k in ipairs(nodes[current].edges) do
            if aktiv[k] and not dirs[k] then next_edge = k; break end
        end
        edge_i = next_edge
        schritte = schritte + 1
    until current == start_node or not edge_i or schritte > #edges
    if area2 < 0 then for k, d in pairs(dirs) do dirs[k] = -d end end   -- +1 = gegen den Uhrzeigersinn
    info.Am = math.abs(area2) / 2
    info.sum_ds_t = sum_ds_t
    info.t_min = t_min
    info.ccw_dir = dirs
    info.It = (sum_ds_t > 1e-12) and 4 * info.Am^2 / sum_ds_t or 0
    return info
end

-- Spiegelsymmetrie des Mittelliniengraphen (inkl. Dicken) zur senkrechten Achse u = ys
-- (sym_v) und zur waagerechten Achse v = zs (sym_h). Geprueft wird durch Abtasten: jeder Punkt
-- jeder Kante muss gespiegelt wieder auf einer Kante gleicher Dicke liegen. So wird die
-- Symmetrie auch erkannt, wenn beide Haelften unterschiedlich in Segmente geteilt sind.
local function duennSymmetrie(nodes, edges, ys, zs)
    if #edges == 0 then return false, false end
    local ext = 0
    for _, n in ipairs(nodes) do ext = math.max(ext, math.abs(n.u - ys), math.abs(n.v - zs)) end
    local tol = 1e-6 * math.max(ext, 1)
    local function liegtAuf(u, v, t)
        for _, f in ipairs(edges) do
            if math.abs(f.t - t) <= 1e-9 * math.max(t, 1) then
                local a, b = nodes[f.n1], nodes[f.n2]
                local du, dv = b.u - a.u, b.v - a.v
                local L2 = du * du + dv * dv
                if L2 > 1e-18 then
                    local lambda = ((u - a.u) * du + (v - a.v) * dv) / L2
                    if lambda >= -1e-9 and lambda <= 1 + 1e-9 then
                        local pu, pv = a.u + lambda * du, a.v + lambda * dv
                        if (pu - u) ^ 2 + (pv - v) ^ 2 <= tol * tol then return true end
                    end
                end
            end
        end
        return false
    end
    local function symmetrisch(spiegel)
        for _, e in ipairs(edges) do
            local a, b = nodes[e.n1], nodes[e.n2]
            for k = 0, 12 do
                local lambda = k / 12
                local u, v = a.u + lambda * (b.u - a.u), a.v + lambda * (b.v - a.v)
                local mu, mv = spiegel(u, v)
                if not liegtAuf(mu, mv, e.t) then return false end
            end
        end
        return true
    end
    local sym_v = symmetrisch(function(u, v) return 2 * ys - u, v end)
    local sym_h = symmetrisch(function(u, v) return u, 2 * zs - v end)
    return sym_v, sym_h
end

function duennKurve.gekruemmt(elem)
    return elem.type == "duenn_kreis" or elem.type == "duenn_kreis_bogen"
end

-- Mittelpunkt, Radius, Startwinkel und Oeffnungswinkel (Bogen gegen den Uhrzeigersinn von P2 nach P3)
function duennKurve.kreis(elem)
    local C, P = elem.points[1], elem.points[2]
    local R = math.sqrt((P.u - C.u)^2 + (P.v - C.v)^2)
    if elem.type == "duenn_kreis" then return C, R, 0, 2 * math.pi end
    local a1 = math.atan2(P.v - C.v, P.u - C.u)
    local diff = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u) - a1
    if diff <= 0 then diff = diff + 2 * math.pi end
    return C, R, a1, diff
end

-- Abstand eines Punktes von der Mittellinie (Hover, Anschlusspruefung)
function duennKurve.abstand(elem, u, v)
    local p = elem.points
    if not duennKurve.gekruemmt(elem) then return point_to_line_dist(u, v, p[1].u, p[1].v, p[2].u, p[2].v) end
    local C, R, a1, diff = duennKurve.kreis(elem)
    local du, dv = u - C.u, v - C.v
    local d = math.sqrt(du^2 + dv^2)
    if elem.type == "duenn_kreis" or (math.atan2(dv, du) - a1) % (2 * math.pi) <= diff then return math.abs(d - R) end
    local best = math.huge
    for _, a in ipairs({a1, a1 + diff}) do
        best = math.min(best, math.sqrt((u - C.u - R * math.cos(a))^2 + (v - C.v - R * math.sin(a))^2))
    end
    return best
end

-- Punkte entlang der Mittellinie (Gerade: beide Enden, Kreis/Bogen: alle 5 Grad)
function duennKurve.punkte(elem)
    if not duennKurve.gekruemmt(elem) then return {elem.points[1], elem.points[2]} end
    local C, R, a1, diff = duennKurve.kreis(elem)
    local steps = math.max(8, math.ceil(math.deg(diff) / 5))
    local out = {}
    for i = 0, steps do
        local a = a1 + diff * i / steps
        out[#out + 1] = {u = C.u + R * math.cos(a), v = C.v + R * math.sin(a)}
    end
    return out
end

-- Kreisrohr: genau ein duennwandiger Vollkreis und sonst kein duennwandiges Element
function duennKurve.rohr()
    if #duenn_elemente ~= 1 or duenn_elemente[1].type ~= "duenn_kreis" then return nil end
    local C, R = duennKurve.kreis(duenn_elemente[1])
    return C, R, duenn_elemente[1].t or default_t
end

-- true, wenn Kreise/Boegen mit anderen duennwandigen Elementen zusammenhaengen (koennte eine Zelle
-- schliessen, die der Profilgraph -- nur gerade Elemente -- nicht sieht)
function duennKurve.verbunden()
    local skala = 1
    for _, e in ipairs(duenn_elemente) do
        for _, pt in ipairs(e.points) do skala = math.max(skala, math.abs(pt.u), math.abs(pt.v)) end
    end
    local tol = 1e-6 * skala
    local function enden(e)
        if not duennKurve.gekruemmt(e) then return {e.points[1], e.points[2]} end
        if e.type == "duenn_kreis" then return {} end
        local pts = duennKurve.punkte(e)
        return {pts[1], pts[#pts]}
    end
    for i, e in ipairs(duenn_elemente) do
        if duennKurve.gekruemmt(e) then
            for j, f in ipairs(duenn_elemente) do
                if i ~= j then
                    for _, pt in ipairs(enden(e)) do if duennKurve.abstand(f, pt.u, pt.v) <= tol then return true end end
                    for _, pt in ipairs(enden(f)) do if duennKurve.abstand(e, pt.u, pt.v) <= tol then return true end end
                    if e.type == "duenn_kreis" then return true end   -- Vollkreis neben weiteren Elementen
                end
            end
        end
    end
    return false
end

-- Bredt fuer genau eine geschlossene Zelle. Rueckgabe: I_T, A_m, Zellenzahl, Info (t_min, ...)
-- Mehrzellige Profile sind statisch unbestimmt und werden nicht berechnet (I_T = 0, A_m = 0).
-- Ein duennwandiges Kreisrohr ist die Zelle mit A_m = pi R^2 und Int ds/t = 2 pi R / t.
find_closed_cells = function()
    local C, R, t = duennKurve.rohr()
    if C then
        local Am, sum_ds_t = math.pi * R^2, 2 * math.pi * R / t
        local info = {cells = 1, Am = Am, It = 4 * Am^2 / sum_ds_t, sum_ds_t = sum_ds_t, t_min = t,
                      ccw_dir = {}, in_loop = {}, rohr = true}
        return info.It, Am, 1, info
    end
    local nodes, edges = duennGraph()
    local info = duennZellen(nodes, edges)
    if info.cells == 1 then return info.It, info.Am, 1, info end
    return 0, 0, info.cells, info
end

-- === SYSTEM BERECHNUNG ===
-- === KOLLISION UND LOECHER ===
local function is_point_inside(elem, u, v)
    if elem.type == "massiv_linie" then
        local p1, p2 = elem.points[1], elem.points[2]
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local L2 = du^2 + dv^2
        if L2 < 1e-9 then return false end
        local dot = (u - p1.u)*du + (v - p1.v)*dv
        local proj = dot / L2
        if proj < 0 or proj > 1 then return false end
        local px = p1.u + proj * du
        local py = p1.v + proj * dv
        local dist2 = (u - px)^2 + (v - py)^2
        return dist2 <= (elem.t/2)^2
    end
    
    if elem.type == "rect" then
        local p = elem.points
        local min_u, max_u = math.min(p[1].u, p[2].u), math.max(p[1].u, p[2].u)
        local min_v, max_v = math.min(p[1].v, p[2].v), math.max(p[1].v, p[2].v)
        return u >= min_u and u <= max_u and v >= min_v and v <= max_v
    elseif elem.type == "circle" or elem.type == "duenn_kreis" then
        local R = math.sqrt((elem.points[2].u - elem.points[1].u)^2 + (elem.points[2].v - elem.points[1].v)^2)
        return (u - elem.points[1].u)^2 + (v - elem.points[1].v)^2 <= R^2
    elseif elem.type == "triangle" or elem.type == "trapezoid" then
        -- Ray casting for polygon
        local pts = elem.points
        local inside = false
        local j = #pts
        for i=1,#pts do
            if ((pts[i].v > v) ~= (pts[j].v > v)) and (u < (pts[j].u - pts[i].u) * (v - pts[i].v) / (pts[j].v - pts[i].v) + pts[i].u) then
                inside = not inside
            end
            j = i
        end
        return inside
    elseif elem.type == "sector" or elem.type == "segment" or elem.type == "duenn_kreis_bogen" then
        local C = elem.points[1]
        local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
        local dist2 = (u - C.u)^2 + (v - C.v)^2
        if dist2 > R^2 then return false end
        -- Check angle
        local a1 = math.atan2(elem.points[2].v - C.v, elem.points[2].u - C.u)
        local a2 = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u)
        local aP = math.atan2(v - C.v, u - C.u)
        
        local function norm(a) if a < 0 then return a + 2*math.pi end return a end
        local a2_n = norm(a2 - a1)
        local aP_n = norm(aP - a1)
        
        if elem.type == "sector" then
            return aP_n <= a2_n
        else
            -- For segment, must also be on the correct side of the chord
            if aP_n > a2_n then return false end
            local line_a = (elem.points[2].v - elem.points[3].v)
            local line_b = (elem.points[3].u - elem.points[2].u)
            local line_c = elem.points[2].u * elem.points[3].v - elem.points[3].u * elem.points[2].v
            -- Check if center and point are on opposite sides
            local valC = line_a * C.u + line_b * C.v + line_c
            local valP = line_a * u + line_b * v + line_c
            return (valC * valP) <= 0
        end
    end
    return false
end

local function getBoundingBox(elem)
    local min_u, max_u, min_v, max_v
    
    if elem.type == "rect" then
        min_u = math.min(elem.points[1].u, elem.points[2].u)
        max_u = math.max(elem.points[1].u, elem.points[2].u)
        min_v = math.min(elem.points[1].v, elem.points[2].v)
        max_v = math.max(elem.points[1].v, elem.points[2].v)
    elseif elem.type == "circle" or elem.type == "duenn_kreis" then
        local C = elem.points[1]
        local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
        min_u, max_u = C.u - R, C.u + R
        min_v, max_v = C.v - R, C.v + R
    elseif elem.type == "massiv_linie" then
        local p1, p2 = elem.points[1], elem.points[2]
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local L = math.sqrt(du^2 + dv^2)
        local nx, ny = 0, 0
        if L > 1e-9 then nx, ny = (-dv/L) * (elem.t/2), (du/L) * (elem.t/2) end
        local pts = {
            {u = p1.u + nx, v = p1.v + ny},
            {u = p2.u + nx, v = p2.v + ny},
            {u = p2.u - nx, v = p2.v - ny},
            {u = p1.u - nx, v = p1.v - ny}
        }
        min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
        for _, p in ipairs(pts) do
            min_u = math.min(min_u, p.u)
            max_u = math.max(max_u, p.u)
            min_v = math.min(min_v, p.v)
            max_v = math.max(max_v, p.v)
        end
    else
        if elem.type == "sector" or elem.type == "segment" or elem.type == "duenn_kreis_bogen" then
            -- Box aus Bogenendpunkten, Kreispunkten bei 0/90/180/270 Grad im Winkelbereich
            -- und (nur Sektor) dem Mittelpunkt
            local C = elem.points[1]
            local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
            local a1 = math.atan2(elem.points[2].v - C.v, elem.points[2].u - C.u)
            local sweep = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u) - a1
            if sweep <= 0 then sweep = sweep + 2 * math.pi end
            local pts = {elem.points[2], elem.points[3]}
            if elem.type == "sector" then table.insert(pts, C) end
            for k = 0, 3 do
                local a = k * math.pi / 2
                if (a - a1) % (2 * math.pi) <= sweep + 1e-12 then
                    table.insert(pts, {u = C.u + R * math.cos(a), v = C.v + R * math.sin(a)})
                end
            end
            min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
            for _, pt in ipairs(pts) do
                min_u, max_u = math.min(min_u, pt.u), math.max(max_u, pt.u)
                min_v, max_v = math.min(min_v, pt.v), math.max(max_v, pt.v)
            end
        else
            min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
            for _, p in ipairs(elem.points) do
                min_u = math.min(min_u, p.u)
                max_u = math.max(max_u, p.u)
                min_v = math.min(min_v, p.v)
                max_v = math.max(max_v, p.v)
            end
        end
    end
    return min_u, max_u, min_v, max_v
end

local function berechneNumerisch(elem, index_of_elem)
    -- Naehert die Kennwerte rasterbasiert an, wenn keine geschlossene Formel genutzt wird.
    local min_u, max_u, min_v, max_v = getBoundingBox(elem)
    local A, sum_yu, sum_zu, sum_y2, sum_z2, sum_yz = 0,0,0,0,0,0
    
    local steps = 40
    local du = (max_u - min_u) / steps
    local dv = (max_v - min_v) / steps
    local dA = du * dv
    
    for i=0, steps-1 do
        for j=0, steps-1 do
            local u = min_u + (i + 0.5)*du
            local v = min_v + (j + 0.5)*dv
            
            if is_point_inside(elem, u, v) then
                if elem.is_hole then
                    local is_positive = false
                    for k=1, index_of_elem-1 do
                        local other = massiv_elemente[k]
                        if not other.is_hole and is_point_inside(other, u, v) then
                            is_positive = true
                            break
                        end
                    end
                    if is_positive then
                        A = A - dA
                        sum_yu = sum_yu - u * dA
                        sum_zu = sum_zu - v * dA
                        sum_y2 = sum_y2 - (v^2) * dA
                        sum_z2 = sum_z2 - (u^2) * dA
                        sum_yz = sum_yz - (u * v) * dA
                    end
                else
                    local overlap = false
                    for k=1, index_of_elem-1 do
                        if is_point_inside(massiv_elemente[k], u, v) then overlap = true break end
                    end
                    if not overlap then
                        A = A + dA
                        sum_yu = sum_yu + u * dA
                        sum_zu = sum_zu + v * dA
                        sum_y2 = sum_y2 + (v^2) * dA
                        sum_z2 = sum_z2 + (u^2) * dA
                        sum_yz = sum_yz + (u * v) * dA
                    end
                end
            end
        end
    end
    
    if math.abs(A) < 1e-9 then return 0,0,0,0,0,0 end
    
    local ys = sum_yu / A
    local zs = sum_zu / A
    
    -- sum_y2 = Integral v^2 dA (gehoert zu I_y), sum_z2 = Integral u^2 dA (gehoert zu I_z)
    local Iys = sum_y2 - A * zs^2
    local Izs = sum_z2 - A * ys^2
    local Iyzs = -(sum_yz - A * ys * zs)
    
    return A, ys, zs, Iys, Izs, Iyzs
end

local function checkOverlapStatus(new_elem)
    -- Testpunkte in Zellmitten eines Rasters ueber der neuen Form. Ein Punkt zaehlt nur, wenn er
    -- samt kleiner Umgebung in einer Form liegt: gemeinsame Kanten sind keine Ueberlappung.
    local min_u, max_u, min_v, max_v = getBoundingBox(new_elem)
    local N = 20
    local eps = 1e-6 * math.max(max_u - min_u, max_v - min_v, 1e-9)
    local function strikt_innen(elem, u, v)
        return is_point_inside(elem, u, v) and is_point_inside(elem, u + eps, v) and is_point_inside(elem, u - eps, v)
            and is_point_inside(elem, u, v + eps) and is_point_inside(elem, u, v - eps)
    end
    local test_pts = {}
    for i = 0, N - 1 do
        for j = 0, N - 1 do
            local u = min_u + (max_u - min_u) * (i + 0.5) / N
            local v = min_v + (max_v - min_v) * (j + 0.5) / N
            if strikt_innen(new_elem, u, v) then table.insert(test_pts, {u = u, v = v}) end
        end
    end
    if #test_pts == 0 then return "none" end

    local is_partial, completely_inside = false, false
    for _, other in ipairs(massiv_elemente) do
        if not other.is_hole and other ~= new_elem then
            local count_in = 0
            for _, pt in ipairs(test_pts) do
                if strikt_innen(other, pt.u, pt.v) then count_in = count_in + 1 end
            end
            local anteil = count_in / #test_pts
            if anteil >= 0.995 then
                completely_inside = true
            elseif count_in > 0 then
                is_partial = true
            end
        end
    end
    if is_partial then return "partial" end
    if completely_inside then return "inside" end
    return "none"
end

-- === GUI & ZEICHNEN ===


local function get_thin_props(elem)
    if elem.type == "duenn_kreis" or elem.type == "duenn_kreis_bogen" then
        local C = elem.points[1]
        local P2 = elem.points[2]
        local is_full = (elem.type == "duenn_kreis")
        local R = math.sqrt((P2.u - C.u)^2 + (P2.v - C.v)^2)
        local a1, diff = 0, 2*math.pi
        if not is_full then
            a1 = math.atan2(P2.v - C.v, P2.u - C.u)
            local P3 = elem.points[3]
            local a2 = math.atan2(P3.v - C.v, P3.u - C.u)
            diff = a2 - a1
            if diff <= 0 then diff = diff + 2*math.pi end
        end
        local t = elem.t
        local L = R * diff
        local A = L * t
        local ys, zs = C.u, C.v
        if not is_full then
            local chord = 2 * R * math.sin(diff / 2)
            local cg_dist = (R * chord) / L
            local bisector = a1 + diff / 2
            ys = C.u + cg_dist * math.cos(bisector)
            zs = C.v + cg_dist * math.sin(bisector)
        end
        local i_sin2 = (a1+diff)/2 - math.sin(2*(a1+diff))/4 - (a1/2 - math.sin(2*a1)/4)
        local i_cos2 = (a1+diff)/2 + math.sin(2*(a1+diff))/4 - (a1/2 + math.sin(2*a1)/4)
        local i_sincos = -math.cos(2*(a1+diff))/4 - (-math.cos(2*a1)/4)
        local Iu_c = R^3 * t * i_sin2
        local Iv_c = R^3 * t * i_cos2
        local Iuv_c = -(R^3 * t * i_sincos)
        local dy = ys - C.u
        local dz = zs - C.v
        return A, ys, zs, Iu_c - A * dz^2, Iv_c - A * dy^2, Iuv_c + A * dy * dz, L
    else
        return thin_line_props(elem.points[1], elem.points[2], elem.t)
    end
end

local function autoZoom()
    -- Waehlt einen Massstab, der alle vorhandenen Elemente im Zeichenbereich zeigt.
    if not system_results then return end
    local r = system_results
    if r.A == nil or r.A == 0 then return end
    
    local min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
    for _, elem in ipairs(massiv_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    for _, elem in ipairs(duenn_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    
    if min_u == math.huge then return end
    
    local w = max_u - min_u
    local h = max_v - min_v
    if w < 1e-9 then w = 1 end
    if h < 1e-9 then h = 1 end
    
    local sw = platform.window:width()
    local sh = platform.window:height()
    scale = math.min((sw - 60) / w, (sh - 60) / h)
    
    local cx = (max_u + min_u) / 2
    local cy = (max_v + min_v) / 2
    
    ox = sw/2 - cx * scale
    oy = sh/2 + cy * scale
    platform.window:invalidate()
end

-- Alles loeschen; on.clearKey fragt vorher nach (qsLoeschFrage)
-- Hinweis an eine schon offene Box anhaengen (sonst wuerde er sie ueberschreiben), doppelt nie
function qsHinweis.melde(text)
    if qsMeldung then
        if not tostring(qsMeldung.text):find(text, 1, true) then qsMeldung.text = qsMeldung.text .. "  " .. text end
    else
        meldung(text, "Hinweis")
    end
end

-- Offenes Profil mit Profilbeiwert 1: nachfragen, ob das gewollt ist (Formelsammlung Kap. 6.2)
function qsHinweis.xiNoetig(ergebnis)
    return ergebnis ~= nil and not ergebnis.closed and math.abs((torsion_xi or 1) - 1) < 1e-12
end
function qsHinweis.xiText()
    return "Offenes Profil: der Profilbeiwert steht auf ξ = 1 (Optionen o, Punkt 10). Laut Formelsammlung "
        .. "z. B. L 0,99 / C 1,12 / T 1,12 / I 1,31 / IPB 1,29 -- ist ξ = 1 so gewollt?"
end

-- Alle duennwandigen Elemente in der Standarddicke: einmal darauf hinweisen. Der Hinweis kommt erst
-- wieder, wenn das ganze Profil geloescht wurde (loescheAllesQS oder alles einzeln entfernt).
function qsHinweis.pruefeDicke()
    if #massiv_elemente + #duenn_elemente == 0 then qsHinweis.dicke_gezeigt = false; return end
    if qsHinweis.dicke_gezeigt or #duenn_elemente == 0 then return end
    for _, elem in ipairs(duenn_elemente) do
        if math.abs((elem.t or default_t) - default_t) > 1e-9 * math.max(1, default_t) then return end
    end
    qsHinweis.dicke_gezeigt = true
    qsHinweis.melde(string.format("Alle duennwandigen Elemente haben dieselbe Dicke, die Standarddicke "
        .. "t = %.4g %s (Optionen o, Punkt 2). Ist das so gewollt? Einzelne Waende aendert ihr mit dem "
        .. "Zeiger auf dem Element und Enter.", display_length(default_t), length_unit))
end

function qsWerte.aktiv()
    return qsWerte.A ~= nil or qsWerte.Iy ~= nil or qsWerte.Iz ~= nil or qsWerte.Iyz ~= nil or qsWerte.ys ~= nil
end

-- Bezugspunkt fuer den manuellen Schwerpunkt: erster Punkt der Geometrie (wie in der Signatur)
function qsWerte.bezugspunkt()
    for _, liste in ipairs({ massiv_elemente, duenn_elemente }) do
        for _, e in ipairs(liste) do
            if e.points and e.points[1] then return e.points[1].u, e.points[1].v end
        end
    end
    return 0, 0
end

-- Sicht auf system_results mit dem Schwerpunkt der Geometrie. Schub, Schubmittelpunkt, Verwoelbung
-- und die Einzelwerte-Tabelle rechnen mit den gezeichneten Waenden und brauchen deren eigenen
-- Schwerpunkt (sonst ist das statische Moment der ganzen Flaeche nicht null).
function qsWerte.geoSicht(r)
    if not r or not r.geo or r.geo.ys == nil then return r end
    return setmetatable({ ys = r.geo.ys, zs = r.geo.zs }, { __index = r })
end

local function loescheManuelleWerte()
    qsWerte.A, qsWerte.Iy, qsWerte.Iz, qsWerte.Iyz, qsWerte.ys, qsWerte.zs = nil, nil, nil, nil, nil, nil
end

-- Signatur des Querschnitts: Elementtypen, Dicken, Loch-/Numerikmarken und alle Punkte relativ zum
-- ersten Punkt. KOS verschieben (alle Punkte gleich), KOS drehen, Kraefte setzen oder Optionen
-- aendern lassen sie unveraendert -- nur eine echte Aenderung am Querschnitt nicht.
function qsWerte.signatur()
    local teile, u0, v0 = {}, nil, nil
    local function pkt(pt)
        if not u0 then u0, v0 = pt.u, pt.v end
        teile[#teile + 1] = string.format("%.9g,%.9g", pt.u - u0, pt.v - v0)
    end
    for _, e in ipairs(massiv_elemente) do
        teile[#teile + 1] = "M" .. tostring(e.type) .. (e.is_hole and "L" or "") .. (e.is_numeric and "N" or "") .. tostring(e.t or "")
        for _, pt in ipairs(e.points or {}) do pkt(pt) end
    end
    for _, e in ipairs(duenn_elemente) do
        teile[#teile + 1] = "D" .. tostring(e.type) .. tostring(e.t or default_t)
        for _, pt in ipairs(e.points or {}) do pkt(pt) end
    end
    return table.concat(teile, ";")
end

-- Zu Beginn jeder Neuberechnung: hat sich der Querschnitt geaendert, gelten wieder die berechneten Werte
function qsWerte.pruefe()
    local sig = qsWerte.signatur()
    if qsWerte.aktiv() and qsWerte.sig ~= sig then
        loescheManuelleWerte()
        qsWerte.verworfen = true
    end
    qsWerte.sig = sig
end

-- Am Ende der Neuberechnung: manuelle Werte einsetzen und alles daraus Abgeleitete neu bilden
function qsWerte.anwenden()
    local r = system_results
    if not r then return end
    r.geo = { A = r.A, Iy = r.Iy, Iz = r.Iz, Iyz = r.Iyz, ys = r.ys, zs = r.zs }
    if qsWerte.aktiv() then
        if qsWerte.ys then
            -- manueller Schwerpunkt: Randabstaende fuer die Widerstandsmomente neu
            local u0, v0 = qsWerte.bezugspunkt()
            r.ys, r.zs = u0 + qsWerte.ys, v0 + qsWerte.zs
            local bb = r.bbox
            if bb then
                r.e_u = math.max(math.abs(bb.max_u - r.ys), math.abs(bb.min_u - r.ys))
                r.e_v = math.max(math.abs(bb.max_v - r.zs), math.abs(bb.min_v - r.zs))
            end
        end
        r.A = qsWerte.A or r.A
        r.Iy = qsWerte.Iy or r.Iy
        r.Iz = qsWerte.Iz or r.Iz
        r.Iyz = qsWerte.Iyz or r.Iyz
        r.IyS, r.IzS, r.IyzS = r.Iy, r.Iz, r.Iyz
        local m = (r.Iy + r.Iz) / 2
        local d = math.sqrt(((r.Iy - r.Iz) / 2) ^ 2 + r.Iyz ^ 2)
        r.I1, r.I2 = m + d, m - d
        r.alpha = (d > 1e-12 * (math.abs(m) + 1)) and 0.5 * math.atan2(2 * r.Iyz, r.Iy - r.Iz) or 0
        r.Wu = ((r.e_v or 0) > 1e-9) and (r.Iy / r.e_v) or 0
        r.Wv = ((r.e_u or 0) > 1e-9) and (r.Iz / r.e_u) or 0
        r.manuell = true
    end
    if qsWerte.verworfen then
        qsWerte.verworfen = false
        meldung("Querschnitt geaendert: die manuell eingegebenen Querschnittswerte gelten nicht mehr, "
            .. "gerechnet wird wieder mit den berechneten Werten.", "Hinweis")
    end
end

-- Welche angezeigten Groessen sind manuell? (bei KOS-Drehung 90/270 tauschen I_y und I_z)
function qsWerte.anzeige()
    -- ausdruecklich mit if: "tausch and qsWerte.Iz or qsWerte.Iy" liefert Iy, wenn Iz nil ist
    local fa, fb
    if rotation == 90 or rotation == 270 then fa, fb = qsWerte.Iz, qsWerte.Iy else fa, fb = qsWerte.Iy, qsWerte.Iz end
    return qsWerte.A ~= nil, fa ~= nil, fb ~= nil, qsWerte.Iyz ~= nil, qsWerte.ys ~= nil
end

-- Liste der manuellen Groessen fuer Hinweise, z. B. "A, I_y"
function qsWerte.namen()
    local a, b = axes()
    local fA, fa, fb, fab, fS = qsWerte.anzeige()
    local l = {}
    if fS then l[#l + 1] = a .. "_S, " .. b .. "_S" end
    if fA then l[#l + 1] = "A" end
    if fa then l[#l + 1] = "I_" .. a end
    if fb then l[#l + 1] = "I_" .. b end
    if fab then l[#l + 1] = "I_" .. a .. b end
    return table.concat(l, ", ")
end

function loescheAllesQS()
    qsLoeschFrage = false
    qsHinweis.dicke_gezeigt = false
    loescheManuelleWerte(); qsWerte.verworfen = false
    escape_clear_pending = false
    massiv_elemente, duenn_elemente, kraefte, pending = {}, {}, {}, {}
    overlap_pending_elem = nil
    system_results = nil
    showResults, showTable = false, false
    table_scroll_x, table_scroll_y = 0, 0
    results_scroll_y = 0
    sigma_input_step, sigma_N, sigma_My, sigma_Mz, sigma_results = 0, nil, nil, nil, nil
    sigmaEingabe.versatz, sigmaEingabe.felder = 0, { "N", "Ma" }
    shear_input_step, shear_Qa, shear_Qb, shear_results = 0, nil, nil, nil
    torsion_input_step, torsion_M, torsion_results = 0, nil, nil
    woelb.step, woelb.M, woelb.results, woelb.visible = 0, nil, nil, false
    shear_profile_visible, shear_hover_index, shear_view_mode, shear_selector_open = false, nil, 0, false
    shear_external_input = false
    show_shear_center, show_shear_moment_table, shear_moment_table = false, false, nil
    shear_profile_visible = false
    shear_hover_index = nil
    sigma_scroll_y = 0
    sigma_table_scroll_y = 0
    sigma_oblique = false
    kernMode = 0
    kern_lines, kern_pts, kern_vertices = {}, {}, {}
    kern_hover_line, kern_hover_pt = nil, nil
    selected_idx, selected_type = nil, nil
    hover_type, hover_idx = nil, nil
    menuOpen, inputMode = false, false
    mode = "idle"
    kos_size, kos_pixel_length = 48, 48
    plane, swapped, rotation = 2, false, 180
    status = "Massiv | Duennwand | Ergebnisse"
    platform.window:invalidate()
end

function on.clearKey()
    if #massiv_elemente == 0 and #duenn_elemente == 0 and #kraefte == 0 then loescheAllesQS(); return end
    qsLoeschFrage = true
    platform.window:invalidate()
end

function on.backspaceKey()
    on.clearKey()
end

local function berechneSystem()
    qsMeldung = nil   -- Querschnitt geaendert: alte Meldung gilt nicht mehr
    qsWerte.pruefe()
    if #massiv_elemente + #duenn_elemente == 0 then qsHinweis.dicke_gezeigt = false end
    sigma_results = nil
    shear_center_cache = nil
    woelb.results, woelb.visible = nil, false   -- Geometrie geaendert: Verwoelbung neu rechnen
    local sumA, sumSyu, sumSzu = 0, 0, 0
    is_numeric_system = false
    
    for i, elem in ipairs(massiv_elemente) do
        local A, ys, zs = 0,0,0
        if elem.is_numeric then
            is_numeric_system = true
            A, ys, zs = berechneNumerisch(elem, i)
        else
            A, ys, zs = berechneLokaleWerte(elem)
        end
        elem.ys = ys
        elem.zs = zs
        sumA = sumA + A
        sumSyu = sumSyu + A * ys
        sumSzu = sumSzu + A * zs
    end
    
    local It_open = 0
    for _, elem in ipairs(duenn_elemente) do
        local A, ys, zs, Iy, Iz, Iyz, L = get_thin_props(elem)
        elem.ys = ys
        elem.zs = zs
        sumA = sumA + A
        sumSyu = sumSyu + A * ys
        sumSzu = sumSzu + A * zs
        It_open = It_open + (torsion_xi / 3) * L * (elem.t^3)
    end
    
    if math.abs(sumA) < 1e-9 then system_results = nil; return end
    
    local global_ys = sumSyu / sumA
    local global_zs = sumSzu / sumA
    
    local sys_Iy, sys_Iz, sys_Iyz = 0, 0, 0
    
    for i, elem in ipairs(massiv_elemente) do
        local A, ys, zs, Iy, Iz, Iyz = 0,0,0,0,0,0
        if elem.is_numeric then
            A, ys, zs, Iy, Iz, Iyz = berechneNumerisch(elem, i)
        else
            A, ys, zs, Iy, Iz, Iyz = berechneLokaleWerte(elem)
        end
        elem.A, elem.Iy, elem.Iz, elem.Iyz = A, Iy, Iz, Iyz
        local I_avg = (Iy + Iz) / 2
        local R = math.sqrt(((Iy - Iz)/2)^2 + Iyz^2)
        elem.I_eta = I_avg + R
        elem.I_zeta = I_avg - R
        elem.I_etazeta = 0
        elem.display_name = "M" .. i
        elem.alpha = 0
        if R > 1e-9 then
            elem.alpha = math.atan2(2 * Iyz, Iy - Iz) / 2
        end
        local dy = ys - global_ys
        local dz = zs - global_zs
        sys_Iy = sys_Iy + Iy + A * dz^2
        sys_Iz = sys_Iz + Iz + A * dy^2
        sys_Iyz = sys_Iyz + Iyz - A * dy * dz
    end
    
    for _, elem in ipairs(duenn_elemente) do
        local A, ys, zs, Iy, Iz, Iyz = get_thin_props(elem)
        elem.A, elem.Iy, elem.Iz, elem.Iyz = A, Iy, Iz, Iyz
        local I_avg = (Iy + Iz) / 2
        local R = math.sqrt(((Iy - Iz)/2)^2 + Iyz^2)
        elem.I_eta = I_avg + R
        elem.I_zeta = I_avg - R
        elem.I_etazeta = 0
        elem.display_name = "D" .. _
        elem.alpha = 0
        if R > 1e-9 then
            elem.alpha = math.atan2(2 * Iyz, Iy - Iz) / 2
        end
        local dy = ys - global_ys
        local dz = zs - global_zs
        sys_Iy = sys_Iy + Iy + A * dz^2
        sys_Iz = sys_Iz + Iz + A * dy^2
        sys_Iyz = sys_Iyz + Iyz - A * dy * dz
    end
    
    -- Haupttraegheitsmomente & Drehwinkel
    local IyS, IzS, IyzS = sys_Iy, sys_Iz, sys_Iyz
    local m = (IyS + IzS) / 2
    local d = math.sqrt(((IyS - IzS)/2)^2 + IyzS^2)
    local I1 = m + d
    local I2 = m - d
    -- Vorsicht: Der Winkel im Mohrschen Kreis tan(2a) = 2 Iyz / (Iy - Iz)
    -- Da y,z hier als Koordinaten sind (y horizontal, z vertikal):
    -- atan2 liefert auch bei I_y = I_z den richtigen Winkel (+-45 Grad je nach Vorzeichen von I_yz)
    local alpha_star = 0
    if d > 1e-12 * (math.abs(m) + 1) then
        alpha_star = 0.5 * math.atan2(2 * sys_Iyz, sys_Iy - sys_Iz)
    end
    
    local It_closed, Am = find_closed_cells()
    
    local sys_min_u, sys_max_u = 1e9, -1e9
    local sys_min_v, sys_max_v = 1e9, -1e9
    local function update_sys_bounds(elem)
        if elem.is_hole then return end
        local min_u, max_u, min_v, max_v = getBoundingBox(elem)
        if min_u < sys_min_u then sys_min_u = min_u end
        if max_u > sys_max_u then sys_max_u = max_u end
        if min_v < sys_min_v then sys_min_v = min_v end
        if max_v > sys_max_v then sys_max_v = max_v end
    end
    for _, elem in ipairs(massiv_elemente) do update_sys_bounds(elem) end
    for _, elem in ipairs(duenn_elemente) do update_sys_bounds(elem) end
    
    local e_u = math.max(math.abs(sys_max_u - global_ys), math.abs(sys_min_u - global_ys))
    local e_v = math.max(math.abs(sys_max_v - global_zs), math.abs(sys_min_v - global_zs))
    local Wu = (e_v > 1e-9) and (sys_Iy / e_v) or 0
    local Wv = (e_u > 1e-9) and (sys_Iz / e_u) or 0
    
    system_results = {
        A = sumA, ys = global_ys, zs = global_zs,
        Iy = IyS, Iz = IzS, Iyz = IyzS,
        IyS = IyS, IzS = IzS, IyzS = IyzS,
        Wu = Wu, Wv = Wv,
        I1 = I1, I2 = I2, alpha = alpha_star,
        It = It_open, It_closed = It_closed, Am = Am,
        e_u = e_u, e_v = e_v,
        bbox = { min_u = sys_min_u, max_u = sys_max_u, min_v = sys_min_v, max_v = sys_max_v }
    }
    qsWerte.anwenden()
    -- Spiegelsymmetrie der Mittellinien (entscheidet, ob der Schubfluss einer geschlossenen
    -- Zelle statisch bestimmt ist); wird im Ergebnisfeld angezeigt.
    if #duenn_elemente > 0 and It_closed > 1e-9 then   -- nur bei geschlossener Zelle noetig
        local sym_nodes, sym_edges = duennGraph(global_ys, global_zs)
        system_results.sym_v, system_results.sym_h = duennSymmetrie(sym_nodes, sym_edges, global_ys, global_zs)
    end
    local force_torsion = berechneKraftTorsion()
    if force_torsion then
        torsion_results = force_torsion
    elseif torsion_M == nil then
        torsion_results = nil
    end
    if kernMode > 0 and kern_build then kern_build() end
end

-- KOS-Ursprung um (du, dv) im internen KOS verschieben: alle Koordinaten aendern sich um
-- -(du, dv). Die Ansicht wird mitgefuehrt, damit der Querschnitt auf dem Bildschirm stehen bleibt
-- und sichtbar das KOS wandert (mit ihm das Raster).
local function verschiebeKOS(du, dv)
    if #massiv_elemente + #duenn_elemente + #kraefte == 0 then
        meldung("Kein Querschnitt vorhanden.", "Hinweis", true)
        return false
    end
    local verschoben = {}
    local function schiebe(pt)
        if pt and not verschoben[pt] then
            pt.u, pt.v = pt.u - du, pt.v - dv
            verschoben[pt] = true
        end
    end
    for _, elem in ipairs(massiv_elemente) do for _, pt in ipairs(elem.points) do schiebe(pt) end end
    for _, elem in ipairs(duenn_elemente) do for _, pt in ipairs(elem.points) do schiebe(pt) end end
    for _, pt in ipairs(pending) do schiebe(pt) end
    for _, kraft in ipairs(kraefte) do kraft.u, kraft.v = kraft.u - du, kraft.v - dv end
    ox, oy = ox + du * scale, oy - dv * scale
    berechneSystem()
    return true
end

local function verschiebeKOSZumSchwerpunkt()
    if not system_results then
        meldung("Kein Querschnitt vorhanden.", "Hinweis", true)
        return
    end
    local shift_u, shift_v = system_results.ys, system_results.zs
    local shifted_points = {}
    for _, elem in ipairs(massiv_elemente) do
        for _, point in ipairs(elem.points) do
            if not shifted_points[point] then
                point.u, point.v = point.u - shift_u, point.v - shift_v
                shifted_points[point] = true
            end
        end
    end
    for _, elem in ipairs(duenn_elemente) do
        for _, point in ipairs(elem.points) do
            if not shifted_points[point] then
                point.u, point.v = point.u - shift_u, point.v - shift_v
                shifted_points[point] = true
            end
        end
    end
    for _, kraft in ipairs(kraefte) do
        kraft.u, kraft.v = kraft.u - shift_u, kraft.v - shift_v
    end
    berechneSystem()
    status = "KOS in den Schwerpunkt verschoben."
end


-- Schubfluss in duennwandigen Profilen (TM2, nur statisch bestimmte Faelle):
--  * offene Profile: q(s) aus dem statischen Moment ab den freien Enden, mit I_yz-Kopplung
--  * genau eine geschlossene Zelle, symmetrisch zur Achse parallel zur Querkraft:
--    der konstante Zellschubfluss q0 folgt aus der Symmetrie (q ist antisymmetrisch)
--  * fehlt die Symmetrieachse parallel zur Querkraft (unsymmetrische Zelle, Querkraft quer zur
--    einzigen Achse, Symmetrie nicht erkannt), folgt q0 aus der Vertraeglichkeit: die Zelle
--    verdrillt sich unter einer Querkraft im Schubmittelpunkt nicht, ∮ q/(G t) ds = 0
--  * mehrzellige Profile bleiben statisch unbestimmt und werden mit Begruendung abgelehnt.
-- Qa, Qb: Querkraefte im internen KOS (u, v). Rueckgabe: maximum, samples, paths, fehler, info
local function berechneDuenneSchubspannung(Qa, Qb)
    if not system_results or #duenn_elemente == 0 then return nil end
    local r = qsWerte.geoSicht(system_results)   -- Schub: Schwerpunkt der gezeichneten Waende
    local samples, paths = {}, {}
    local nodes, edges, nicht_gerade = duennGraph(r.ys, r.zs)
    if nicht_gerade then return nil, nil, nil, "Schub nur fuer gerade duennwandige Elemente." end
    local zellen = duennZellen(nodes, edges)
    local sym_v, sym_h = duennSymmetrie(nodes, edges, r.ys, r.zs)
    local info = {cells = zellen.cells, sym_v = sym_v, sym_h = sym_h}
    if zellen.cells >= 2 then
        return nil, nil, nil, "Mehrzelliges Profil: Schubfluss statisch unbestimmt.", info
    end
    if zellen.cells == 1 then
        -- Fehlt die Symmetrieachse parallel zur Querkraft, kommt q0 nicht aus der Symmetrie,
        -- sondern aus der Vertraeglichkeit (Schritt 4b). Fuer die Warnung wird gemerkt, was erkannt wurde.
        info.erkannt = (sym_v and sym_h) and "senkrecht und waagerecht"
            or (sym_v and "nur senkrecht") or (sym_h and "nur waagerecht") or "keine"
    end
    local det = r.Iy * r.Iz - r.Iyz^2
    if det <= 1e-12 then return nil, nil, nil, "Traegheitsmomente singulaer.", info end

    local function other_node(edge, node_index)
        return edge.n1 == node_index and edge.n2 or edge.n1
    end

    local function unused_edges(node_index)
        local result = {}
        for _, edge_index in ipairs(nodes[node_index].edges) do
            if not edges[edge_index].used then table.insert(result, edge_index) end
        end
        return result
    end

    local function integrate_edge(path, item, first_moment_a, first_moment_b, path_s)
        local edge, reverse = item.edge, item.reverse
        local segment_index, elem = edge.index, duenn_elemente[edge.index]
        local p1, p2 = edge.p1, edge.p2
        if reverse then p1, p2 = p2, p1 end
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local length = math.sqrt(du^2 + dv^2)
        if length <= 1e-9 then return first_moment_a, first_moment_b, path_s end
        local t = edge.t
        local original_p1, original_p2 = elem.points[1], elem.points[2]
        if original_p2.u < original_p1.u or (math.abs(original_p2.u - original_p1.u) <= 1e-9 and original_p2.v < original_p1.v) then
            original_p1, original_p2 = original_p2, original_p1
        end
        local original_du = original_p2.u - original_p1.u
        local original_dv = original_p2.v - original_p1.v
        local original_length = math.sqrt(original_du^2 + original_dv^2)
        local display_normal_u = original_length > 1e-9 and -original_dv / original_length or 0
        local display_normal_v = original_length > 1e-9 and original_du / original_length or 0
        -- Mindestens 64 Teilintervalle pro Kante, unabhaengig von der Zoomstufe
        local integration_step = math.max(raster / 8, 0.025)
        local sample_count = math.max(64, math.ceil(length / integration_step))
        if sample_count % 2 == 1 then sample_count = sample_count + 1 end   -- gerade: Simpson je Kante exakt
        for sample = 0, sample_count do
            local f = sample / sample_count
            local u = p1.u + f * du
            local v = p1.v + f * dv
            local ds = length / sample_count
            local area = t * ds
            -- Schubfluss mit I_yz-Kopplung (fuer I_yz = 0: tau = -Q S / (I t))
            local tau_a = -Qa * (r.Iy * first_moment_a + r.Iyz * first_moment_b) / (det * t)
            local tau_b = -Qb * (r.Iz * first_moment_b + r.Iyz * first_moment_a) / (det * t)
            table.insert(samples, {u = u, v = v, tau_a = tau_a, tau_b = tau_b, tau = tau_a + tau_b, Sy = first_moment_b, Sz = first_moment_a,
                moment_y_density = (v - r.zs) * t, moment_z_density = (u - r.ys) * t, thickness = t, ds = ds,
                tangent_u = du / length, tangent_v = dv / length, display_normal_u = display_normal_u, display_normal_v = display_normal_v,
                segment = segment_index, edge_i = edge.i, fwd = reverse and -1 or 1, path_id = path.id, parameter = f,
                s = path_s + f * length, direction = reverse and -1 or 1})
            if sample < sample_count then
                local midpoint = (sample + 0.5) / sample_count
                first_moment_a = first_moment_a + (p1.u + midpoint * du - r.ys) * area
                first_moment_b = first_moment_b + (p1.v + midpoint * dv - r.zs) * area
            end
        end
        item.p1, item.p2 = p1, p2
        return first_moment_a, first_moment_b, path_s + length
    end

    local function make_path(start_node, first_edge, initial_moment_a, initial_moment_b, start_kind)
        local path = {id = #paths + 1, items = {}, start_kind = start_kind, start_moment_a = initial_moment_a or 0, start_moment_b = initial_moment_b or 0}
        local current_node, edge_index = start_node, first_edge
        local first_moment_a, first_moment_b = initial_moment_a or 0, initial_moment_b or 0
        local path_s = 0
        while edge_index do
            local edge = edges[edge_index]
            if edge.used then break end
            edge.used = true
            local reverse = edge.n2 == current_node
            local next_node = other_node(edge, current_node)
            local item = {edge = edge, reverse = reverse}
            table.insert(path.items, item)
            first_moment_a, first_moment_b, path_s = integrate_edge(path, item, first_moment_a, first_moment_b, path_s)
            current_node = next_node
            table.insert(nodes[current_node].arrivals, {a = first_moment_a, b = first_moment_b})
            local candidates = unused_edges(current_node)
            -- nur bei genau zwei Kanten direkt weiter; Verzweigungen warten auf die Summe
            if #nodes[current_node].edges ~= 2 then break end
            edge_index = candidates[1]
        end
        if #path.items > 0 then table.insert(paths, path) end
    end

    -- 1) von jedem freien Ende aus (dort ist q = 0)
    for node_index, node in ipairs(nodes) do
        if #node.edges == 1 and not edges[node.edges[1]].used then
            make_path(node_index, node.edges[1], nil, nil, "free")
        end
    end

    -- 2) An einer Verzweigung mit nur noch einem unbekannten Ast startet dieser mit der Summe
    --    der angekommenen statischen Momente (Knotengleichgewicht der Schubfluesse).
    local function resolve_branch_nodes()
        local changed = true
        while changed do
            changed = false
            for node_index, node in ipairs(nodes) do
                local candidates = unused_edges(node_index)
                if #node.edges >= 3 and #candidates == 1 and #node.arrivals > 0 then
                    local start_a, start_b = 0, 0
                    for _, arrival in ipairs(node.arrivals) do
                        start_a, start_b = start_a + arrival.a, start_b + arrival.b
                    end
                    make_path(node_index, candidates[1], start_a, start_b)
                    changed = true
                end
            end
        end
    end
    resolve_branch_nodes()

    -- 3) Die geschlossene Zelle aufschneiden, moeglichst auf der Symmetrieachse: dort ist der
    --    Schubfluss null, die Laufvariable beginnt also wie in der Handrechnung bei S = 0.
    --    duennGraph teilt die Kanten bereits an den Schwerpunktachsen, der Knoten existiert also,
    --    sofern die Achse die Zelle ueberhaupt schneidet.
    local achs_tol = 0
    for _, n in ipairs(nodes) do
        achs_tol = math.max(achs_tol, math.abs(n.u - r.ys), math.abs(n.v - r.zs))
    end
    achs_tol = 1e-6 * math.max(achs_tol, 1)
    local function schnittAufAchse()
        if zellen.cells ~= 1 then return nil end
        -- Achse parallel zur (groesseren) Querkraft zuerst; ohne Querkraft die vorhandene
        local reihenfolge = (math.abs(Qb) >= math.abs(Qa)) and { "v", "h" } or { "h", "v" }
        for _, achse in ipairs(reihenfolge) do
            if (achse == "v" and sym_v) or (achse == "h" and sym_h) then
                for edge_index, edge in ipairs(edges) do
                    if not edge.used and zellen.in_loop[edge.i] then
                        for _, node_index in ipairs({ edge.n1, edge.n2 }) do
                            local nd = nodes[node_index]
                            local auf
                            if achse == "v" then auf = math.abs(nd.u - r.ys) <= achs_tol
                            else auf = math.abs(nd.v - r.zs) <= achs_tol end
                            if auf then return edge_index, node_index end
                        end
                    end
                end
            end
        end
        return nil
    end
    local sicherheit = #edges + 1
    local erster_schnitt = true
    while sicherheit > 0 do
        sicherheit = sicherheit - 1
        local offen_idx, start_node, art = nil, nil, "cut"
        if erster_schnitt then
            offen_idx, start_node = schnittAufAchse()
            if offen_idx then art = "cut_sym"; info.schnitt_auf_achse = true end
        end
        if not offen_idx then
            for edge_index, edge in ipairs(edges) do
                if not edge.used then offen_idx = edge_index; start_node = edge.n1; break end
            end
        end
        if not offen_idx then break end
        if erster_schnitt and zellen.cells == 1 and not info.schnitt_auf_achse then
            info.schnitt_auf_achse = false
        end
        erster_schnitt = false
        make_path(start_node, offen_idx, nil, nil, art)
        resolve_branch_nodes()
    end

    -- 4) Zelle: konstanten Umlaufschubfluss q0 aus der Symmetrie bestimmen. Fuer eine Querkraft
    --    parallel zur Symmetrieachse ist q (im Umlaufsinn) antisymmetrisch: q(P) + q(P') = 0.
    if zellen.cells == 1 then
        local loop = {}
        for _, sample in ipairs(samples) do
            if zellen.in_loop[sample.edge_i] then
                sample.in_cell = true
                sample.cell_sign = (zellen.ccw_dir[sample.edge_i] or 1) * sample.fwd
                table.insert(loop, sample)
            end
        end
        local ext = 0
        for _, n in ipairs(nodes) do ext = math.max(ext, math.abs(n.u - r.ys), math.abs(n.v - r.zs)) end
        local tol = 1e-6 * math.max(ext, 1)
        local function innen(sample) return sample.parameter > 1e-9 and sample.parameter < 1 - 1e-9 end
        -- Korrektur des statischen Moments in der Zelle: der Schnitt liegt beliebig, das statische
        -- Moment darf um eine Konstante verschoben werden. Aus der Symmetrie folgt S(P) + S(P') = 0
        -- (im Umlaufsinn), das entspricht einem Schnitt auf der Symmetrieachse, wo q = 0 ist.
        -- Damit stimmen auch die angezeigten S-Verlaeufe, nicht nur tau.
        local function korrigiere(key, spiegel)
            for _, sample in ipairs(loop) do
                if innen(sample) then
                    local mu, mv = spiegel(sample.u, sample.v)
                    if (mu - sample.u)^2 + (mv - sample.v)^2 > (10 * tol)^2 then
                        local partner, best = nil, (100 * tol)^2
                        for _, other in ipairs(loop) do
                            if innen(other) then
                                local d = (other.u - mu)^2 + (other.v - mv)^2
                                if d <= best then partner, best = other, d end
                            end
                        end
                        if partner then
                            local s0 = -(sample[key] * sample.cell_sign + partner[key] * partner.cell_sign) / 2
                            for _, other in ipairs(loop) do
                                other[key] = other[key] + other.cell_sign * s0
                            end
                            return true
                        end
                    end
                end
            end
            return false
        end
        -- Umlaufintegral ∮ S/t ds ueber die Zelle (im Umlaufsinn) samt ∮ 1/t ds. Simpson je Kante:
        -- S ist auf einer geraden Kante quadratisch, das Integral damit exakt. Die Stuetzstellen
        -- einer Kante liegen in loop hintereinander (parameter 0 .. 1).
        local function umlaufintegrale(key)
            local zaehler, nenner = 0, 0
            local i = 1
            while i <= #loop do
                local j = i
                while j < #loop and loop[j + 1].edge_i == loop[i].edge_i and loop[j + 1].path_id == loop[i].path_id do
                    j = j + 1
                end
                local m, h = j - i, loop[i].ds
                if m >= 2 and m % 2 == 0 then
                    local za, ne = 0, 0
                    for k = 0, m do
                        local g = (k == 0 or k == m) and 1 or ((k % 2 == 1) and 4 or 2)
                        local sm = loop[i + k]
                        za = za + g * sm[key] * sm.cell_sign / sm.thickness
                        ne = ne + g / sm.thickness
                    end
                    zaehler, nenner = zaehler + za * h / 3, nenner + ne * h / 3
                else
                    for k = 0, m do
                        local w = (k == 0 or k == m) and 0.5 or 1
                        local sm = loop[i + k]
                        zaehler = zaehler + w * sm[key] * sm.cell_sign / sm.thickness * h
                        nenner = nenner + w / sm.thickness * h
                    end
                end
                i = j + 1
            end
            return zaehler, nenner
        end
        -- 4b) Konstante aus der Vertraeglichkeit: unter einer Querkraft im Schubmittelpunkt
        --     verdrillt sich die Zelle nicht, also ∮ q/(G t) ds = 0. Mit q = -Q (I S + I_yz S')/det
        --     und regulaerer Matrix [[I_y, I_yz], [I_yz, I_z]] zerfaellt das in ∮ Sz/t ds = 0 und
        --     ∮ Sy/t ds = 0: je eine Konstante fuer Sz und Sy, unabhaengig von Q und von der
        --     I_yz-Kopplung. Damit stimmen auch die angezeigten S-Verlaeufe. Beim symmetrischen
        --     Profil ergibt das dieselbe (antisymmetrische) Loesung wie die Spiegelung.
        local function korrigiereVertraeglich(key)
            local zaehler, nenner = umlaufintegrale(key)
            if nenner <= 1e-12 then return false end
            local s0 = -zaehler / nenner
            for _, other in ipairs(loop) do other[key] = other[key] + other.cell_sign * s0 end
            return true
        end
        -- Sz gehoert zur Querkraft in a-Richtung (Symmetrieachse waagerecht), Sy zur b-Richtung.
        -- Symmetrie hat Vorrang; ohne Achse (oder ohne Spiegelpartner) die Vertraeglichkeit.
        local ok_a = sym_h and korrigiere("Sz", function(u, v) return u, 2 * r.zs - v end)
        local ok_b = sym_v and korrigiere("Sy", function(u, v) return 2 * r.ys - u, v end)
        if schub_immer_vertraeglich then ok_a, ok_b = false, false end
        local vert_a = (not ok_a) and korrigiereVertraeglich("Sz")
        local vert_b = (not ok_b) and korrigiereVertraeglich("Sy")
        if not (ok_a or vert_a) or not (ok_b or vert_b) then
            return nil, nil, nil, "Umlaufintegral der Zelle nicht auswertbar.", info
        end
        -- Schubspannungen aus den korrigierten statischen Momenten neu bilden
        for _, sample in ipairs(samples) do
            if sample.in_cell then
                sample.tau_a = -Qa * (r.Iy * sample.Sz + r.Iyz * sample.Sy) / (det * sample.thickness)
                sample.tau_b = -Qb * (r.Iz * sample.Sy + r.Iyz * sample.Sz) / (det * sample.thickness)
            end
            sample.tau = sample.tau_a + sample.tau_b
        end
        info.zelle_s_korrigiert = { a = true, b = true,
            vertraeglich = { a = vert_a and true or false, b = vert_b and true or false } }
    end

    local maximum = {tau = 0, abs_tau = 0, u = r.ys, v = r.zs}
    for _, sample in ipairs(samples) do
        if math.abs(sample.tau) > maximum.abs_tau then
            maximum = {tau = sample.tau, abs_tau = math.abs(sample.tau), u = sample.u, v = sample.v}
        end
    end
    return maximum, samples, paths, nil, info
end

-- Schubmittelpunkt aus dem Moment der Schubfluesse fuer Einheitsquerkraefte.
-- Offen: immer bestimmt. Eine Zelle: nur die Koordinate(n), fuer die eine Symmetrieachse
-- parallel zur Querkraft existiert (known_u / known_v); sonst statisch unbestimmt.
berechneSchubmittelpunkt = function()
    if shear_center_cache then return shear_center_cache end
    if not system_results or #duenn_elemente == 0 then return nil end
    local r = qsWerte.geoSicht(system_results)
    local rohr_mitte = duennKurve.rohr()
    if rohr_mitte then
        shear_center_cache = {u = rohr_mitte.u, v = rohr_mitte.v, known_u = true, known_v = true, known = true,
                              closed = true, moment_a = 0, moment_b = 0}
        return shear_center_cache
    end
    local function shear_torque(Qa, Qb)
        local maximum, samples = berechneDuenneSchubspannung(Qa, Qb)
        if not maximum then return nil end
        -- Simpson je Kante: der Hebelarm ist auf einer geraden Kante linear, q quadratisch, das
        -- Produkt kubisch -- damit ist das Moment exakt (Trapez liess den Schubmittelpunkt um ~1e-5 wandern)
        local moment = 0
        local i = 1
        while i <= #samples do
            local j = i
            while j < #samples and samples[j + 1].path_id == samples[i].path_id
                and samples[j + 1].edge_i == samples[i].edge_i and (samples[j + 1].parameter or 0) > (samples[j].parameter or 0) do
                j = j + 1
            end
            local m, h = j - i, samples[i].ds
            for k = 0, m do
                local sample = samples[i + k]
                local w
                if m >= 2 and m % 2 == 0 then w = ((k == 0 or k == m) and 1 or ((k % 2 == 1) and 4 or 2)) * h / 3
                else w = ((k == 0 or k == m) and 0.5 or 1) * h end
                local force = sample.tau * sample.thickness * w
                moment = moment - ((sample.u - r.ys) * sample.tangent_v - (sample.v - r.zs) * sample.tangent_u) * force
            end
            i = j + 1
        end
        return moment
    end
    local moment_a = shear_torque(1, 0)
    local moment_b = shear_torque(0, 1)
    local cells = select(3, find_closed_cells())
    local result = {
        u = moment_b and (r.ys - moment_b) or r.ys,
        v = moment_a and (r.zs + moment_a) or r.zs,
        known_u = moment_b ~= nil,
        known_v = moment_a ~= nil,
        closed = cells >= 1,
        moment_a = moment_a, moment_b = moment_b,
    }
    result.known = result.known_u and result.known_v
    shear_center_cache = result
    return result
end

local function berechneSchubMomentTabelle()
    if not system_results or #duenn_elemente == 0 then return nil end
    local function contributions(Qa, Qb)
        local _, samples = berechneDuenneSchubspannung(Qa, Qb)
        local result = {}
        local moments = {}
        for index = 1, #duenn_elemente do result[index] = 0 end
        for index = 1, #duenn_elemente do moments[index] = 0 end
        for _, sample in ipairs(samples or {}) do
            local endpoint_weight = (sample.parameter and (sample.parameter <= 1e-9 or sample.parameter >= 1 - 1e-9)) and 0.5 or 1
            local force = (Qa ~= 0 and sample.tau_a or sample.tau_b)
                * (sample.thickness or 0) * (sample.ds or 0) * endpoint_weight
            if sample.segment then
                result[sample.segment] = result[sample.segment] + math.abs(force)
                local signed_force = result[sample.segment .. "_signed"] or 0
                result[sample.segment .. "_signed"] = signed_force + force
                local sample_u, sample_v = displayedVector(sample.u, sample.v)
                local center_u, center_v = displayedVector(qsWerte.geoSicht(system_results).ys, qsWerte.geoSicht(system_results).zs)
                local tangent_u, tangent_v = displayedVector(sample.tangent_u, sample.tangent_v)
                moments[sample.segment] = moments[sample.segment]
                    - ((sample_u - center_u) * tangent_v - (sample_v - center_v) * tangent_u) * force
            end
        end
        return result, moments
    end
    local first, first_moment = contributions(1, 0)
    local second, second_moment = contributions(0, 1)
    local rows = {}
    local total_first, total_second = 0, 0
    for index = 1, #duenn_elemente do
        total_first, total_second = total_first + first_moment[index], total_second + second_moment[index]
        local first_force = first[index .. "_signed"] or 0
        local second_force = second[index .. "_signed"] or 0
        rows[index] = {
            name = "D" .. index,
            first = first_force, second = second_force,
            moment_first = first_moment[index], moment_second = second_moment[index],
            arm_first = math.abs(first_force) > 1e-12 and first_moment[index] / first_force or nil,
            arm_second = math.abs(second_force) > 1e-12 and second_moment[index] / second_force or nil
        }
    end
    return {rows = rows, total_first = total_first, total_second = total_second}
end

local function polygon_width_at_v(points, v)
    local intersections = {}
    for i = 1, #points do
        local p1, p2 = points[i], points[i % #points + 1]
        if (p1.v <= v and p2.v > v) or (p2.v <= v and p1.v > v) then
            local f = (v - p1.v) / (p2.v - p1.v)
            table.insert(intersections, p1.u + f * (p2.u - p1.u))
        end
    end
    table.sort(intersections)
    local width = 0
    for i = 1, #intersections - 1, 2 do
        width = width + math.max(0, intersections[i + 1] - intersections[i])
    end
    return width
end

local function polygon_height_at_u(points, u)
    local intersections = {}
    for i = 1, #points do
        local p1, p2 = points[i], points[i % #points + 1]
        if (p1.u <= u and p2.u > u) or (p2.u <= u and p1.u > u) then
            local f = (u - p1.u) / (p2.u - p1.u)
            table.insert(intersections, p1.v + f * (p2.v - p1.v))
        end
    end
    table.sort(intersections)
    local height = 0
    for i = 1, #intersections - 1, 2 do
        height = height + math.max(0, intersections[i + 1] - intersections[i])
    end
    return height
end

-- Umriss eines Massivelements als Polygon (dicke Linie: Rechteck; Sektor/Segment: 96-Eck)
local function massiv_outline_polygon(elem)
    if elem.type == "massiv_linie" then
        local p1, p2 = elem.points[1], elem.points[2]
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local L = math.sqrt(du^2 + dv^2)
        local nx, ny = 0, 0
        if L > 1e-9 then nx, ny = (-dv / L) * (elem.t / 2), (du / L) * (elem.t / 2) end
        return {{u = p1.u + nx, v = p1.v + ny}, {u = p2.u + nx, v = p2.v + ny},
                {u = p2.u - nx, v = p2.v - ny}, {u = p1.u - nx, v = p1.v - ny}}
    end
    local C = elem.points[1]
    local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
    local a1 = math.atan2(elem.points[2].v - C.v, elem.points[2].u - C.u)
    local sweep = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u) - a1
    if sweep <= 0 then sweep = sweep + 2 * math.pi end
    local pts = {}
    if elem.type == "sector" then table.insert(pts, {u = C.u, v = C.v}) end
    local n = 96
    for i = 0, n do
        local a = a1 + sweep * i / n
        table.insert(pts, {u = C.u + R * math.cos(a), v = C.v + R * math.sin(a)})
    end
    return pts
end

local function massiv_width_at_v(v)
    local width = 0
    for _, elem in ipairs(massiv_elemente) do
        local sign = elem.is_hole and -1 or 1
        if elem.type == "rect" then
            local p = elem.points
            local min_v, max_v = math.min(p[1].v, p[2].v), math.max(p[1].v, p[2].v)
            if v >= min_v and v <= max_v then width = width + sign * math.abs(p[2].u - p[1].u) end
        elseif elem.type == "circle" then
            local c, p = elem.points[1], elem.points[2]
            local radius = math.sqrt((p.u-c.u)^2 + (p.v-c.v)^2)
            local dv = v - c.v
            if math.abs(dv) < radius then width = width + sign * 2 * math.sqrt(radius^2 - dv^2) end
        elseif elem.type == "triangle" or elem.type == "trapezoid" then
            width = width + sign * polygon_width_at_v(elem.points, v)
        elseif elem.type == "sector" or elem.type == "segment" or elem.type == "massiv_linie" then
            width = width + sign * polygon_width_at_v(massiv_outline_polygon(elem), v)
        end
    end
    return math.max(0, width)
end

local function massiv_height_at_u(u)
    local height = 0
    for _, elem in ipairs(massiv_elemente) do
        local sign = elem.is_hole and -1 or 1
        if elem.type == "rect" then
            local p = elem.points
            local min_u, max_u = math.min(p[1].u, p[2].u), math.max(p[1].u, p[2].u)
            if u >= min_u and u <= max_u then height = height + sign * math.abs(p[2].v - p[1].v) end
        elseif elem.type == "circle" then
            local c, p = elem.points[1], elem.points[2]
            local radius = math.sqrt((p.u-c.u)^2 + (p.v-c.v)^2)
            local du = u - c.u
            if math.abs(du) < radius then height = height + sign * 2 * math.sqrt(radius^2 - du^2) end
        elseif elem.type == "triangle" or elem.type == "trapezoid" then
            height = height + sign * polygon_height_at_u(elem.points, u)
        elseif elem.type == "sector" or elem.type == "segment" or elem.type == "massiv_linie" then
            height = height + sign * polygon_height_at_u(massiv_outline_polygon(elem), u)
        end
    end
    return math.max(0, height)
end

-- Schubspannungen aus Querkraft. input_Qa/input_Qb sind im angezeigten KOS (Q_y, Q_z) eingegeben,
-- eingetragene Kraefte liegen intern vor. Massiv: tau = Q S / (I b) (nur I_yz = 0),
-- duennwandig: siehe berechneDuenneSchubspannung. Gemischt massiv/duennwandig: nicht berechnet.
-- ===== Verwoelbung duennwandiger Profile (Formelsammlung Kap. 6) =====
-- u_x(s) = Int [ MT/(2 G A_m h(s)) - r_perp * theta ] ds + c,   theta = MT/(G I_T)
--  * Pol ist der Schubmittelpunkt (Drillruhepunkt). r_perp = (u-u_M) t_v - (v-v_M) t_u ist der
--    vorzeichenbehaftete Abstand des Pols von der Kantentangente: positiv, wenn der Fahrstrahl
--    vom Pol zum Laufpunkt in Laufrichtung im Sinn des positiven Torsionsmoments dreht -- also
--    im selben Umlaufsinn, in dem der Bredt-Schubfluss fuer MT > 0 laeuft (ccw_dir = +1).
--  * c aus Int u_x h ds = 0 ueber das ganze Profil (keine mittlere Laengsverschiebung, N = 0).
--    Bei symmetrischen Profilen ist die Verwoelbung antisymmetrisch, u_x auf der Achse also
--    automatisch null -- genau der Startpunkt der Handrechnung.
--  * offene Profile: kein umlaufender Schubfluss, der Bredt-Term entfaellt, u_x = -theta Int r ds + c.
--    Das ist Standardtheorie, steht aber nicht in der Formelsammlung -> Warnung beim Aufruf.
--  * r_perp ist auf einer geraden Kante linear, u_x also quadratisch: beides wird geschlossen
--    integriert, die Stuetzstellen dienen nur der Darstellung.
function woelb.berechne(M, G)
    if not system_results then return nil, "Kein Querschnitt vorhanden." end
    if #duenn_elemente == 0 or #massiv_elemente > 0 then
        return nil, "Verwoelbung nur fuer rein duennwandige Profile (offen oder einzellig geschlossen)."
    end
    if not G or G <= 0 then return nil, "Der Schubmodul G muss positiv sein." end
    local r = qsWerte.geoSicht(system_results)
    local nodes, edges, nicht_gerade = duennGraph(r.ys, r.zs)
    if nicht_gerade then return nil, "Verwoelbung nur fuer gerade duennwandige Elemente." end
    if #edges == 0 then return nil, "Kein Profilgraph vorhanden." end
    local zellen = duennZellen(nodes, edges)
    if zellen.cells >= 2 then return nil, "Mehrzelliges Profil: Torsion statisch unbestimmt, keine Verwoelbung." end
    local geschlossen = zellen.cells == 1
    local It = geschlossen and zellen.It or (r.It or 0)
    if It <= 1e-12 then return nil, "I_T = 0: keine Verwoelbung berechenbar." end
    local pol = berechneSchubmittelpunkt()
    if not (pol and pol.known) then return nil, "Schubmittelpunkt nicht bestimmbar." end
    local theta = M / (G * It)
    local qT = geschlossen and M / (2 * zellen.Am) or 0

    -- Startknoten moeglichst auf einer Symmetrieachse (wie der Zellschnitt), sonst Knoten 1.
    -- Die Konstante c macht das Ergebnis ohnehin unabhaengig vom Start.
    local sym_v, sym_h = duennSymmetrie(nodes, edges, r.ys, r.zs)
    local ext = 0
    for _, n in ipairs(nodes) do ext = math.max(ext, math.abs(n.u - r.ys), math.abs(n.v - r.zs)) end
    local tol = 1e-6 * math.max(ext, 1)
    local start = 1
    for i, n in ipairs(nodes) do
        if (sym_v and math.abs(n.u - r.ys) <= tol) or (sym_h and math.abs(n.v - r.zs) <= tol) then start = i; break end
    end

    local u_knoten, besucht = {}, {}
    local samples, paths = {}, {}
    local schluss = 0        -- Probe: in der Zelle muss der Umlauf wieder schliessen
    local step = math.max(raster / 8, 0.025)
    local function ablaufen(startknoten)
        u_knoten[startknoten] = u_knoten[startknoten] or 0
        local schlange = { startknoten }
        while #schlange > 0 do
            local n = table.remove(schlange, 1)
            for _, ei in ipairs(nodes[n].edges) do
                local e = edges[ei]
                if not besucht[ei] then
                    besucht[ei] = true
                    local vorwaerts = (e.n1 == n)
                    local ziel = vorwaerts and e.n2 or e.n1
                    local p1 = vorwaerts and e.p1 or e.p2
                    local p2 = vorwaerts and e.p2 or e.p1
                    local du, dv = p2.u - p1.u, p2.v - p1.v
                    local L = math.sqrt(du^2 + dv^2)
                    if L > 1e-9 then
                        local tu, tv = du / L, dv / L
                        local h = e.t
                        local sign = 0
                        if geschlossen and zellen.in_loop[ei] then sign = (zellen.ccw_dir[ei] or 1) * (vorwaerts and 1 or -1) end
                        local bredt = sign * qT / (G * h)                      -- du/ds aus dem Bredt-Schubfluss
                        local r1 = (p1.u - pol.u) * tv - (p1.v - pol.v) * tu   -- r_perp am Kantenanfang
                        local r2 = (p2.u - pol.u) * tv - (p2.v - pol.v) * tu   -- r_perp am Kantenende (linear)
                        local u0 = u_knoten[n]
                        local function u_bei(sx) return u0 + bredt * sx - theta * (r1 * sx + (r2 - r1) * sx * sx / (2 * L)) end
                        local u_ende = u_bei(L)
                        if u_knoten[ziel] == nil then
                            u_knoten[ziel] = u_ende
                            table.insert(schlange, ziel)
                        else
                            schluss = math.max(schluss, math.abs(u_knoten[ziel] - u_ende))
                        end
                        -- Anzeige-Normale wie beim Schub aus der urspruenglichen Elementrichtung
                        local elem = duenn_elemente[e.index]
                        local o1, o2 = elem.points[1], elem.points[2]
                        if o2.u < o1.u or (math.abs(o2.u - o1.u) <= 1e-9 and o2.v < o1.v) then o1, o2 = o2, o1 end
                        local odu, odv = o2.u - o1.u, o2.v - o1.v
                        local oL = math.sqrt(odu^2 + odv^2)
                        local nu_, nv_ = (oL > 1e-9) and -odv / oL or 0, (oL > 1e-9) and odu / oL or 0
                        local m = math.max(64, math.ceil(L / step))
                        if m % 2 == 1 then m = m + 1 end
                        local path = { id = #paths + 1, items = { { p1 = p1, p2 = p2, edge = e } } }
                        table.insert(paths, path)
                        for k = 0, m do
                            local f = k / m
                            table.insert(samples, { u = p1.u + f * du, v = p1.v + f * dv, ux = u_bei(f * L), s = f * L,
                                parameter = f, ds = L / m, thickness = h, tangent_u = tu, tangent_v = tv,
                                display_normal_u = nu_, display_normal_v = nv_, segment = e.index, edge_i = ei,
                                path_id = path.id, r_perp = r1 + (r2 - r1) * f })
                        end
                    end
                end
            end
        end
    end
    ablaufen(start)
    for ei, e in ipairs(edges) do       -- nicht zusammenhaengende Teile: eigener Start
        if not besucht[ei] then ablaufen(e.n1) end
    end
    -- Konstante c: mittlere Verwoelbung null. Simpson je Kante (u_x ist dort quadratisch: exakt).
    local zaehler, nenner = 0, 0
    local i = 1
    while i <= #samples do
        local j = i
        while j < #samples and samples[j + 1].path_id == samples[i].path_id do j = j + 1 end
        local m, hs, h = j - i, samples[i].ds, samples[i].thickness
        for k = 0, m do
            local g = (k == 0 or k == m) and 1 or ((k % 2 == 1) and 4 or 2)
            zaehler = zaehler + g * samples[i + k].ux * h * hs / 3
            nenner = nenner + g * h * hs / 3
        end
        i = j + 1
    end
    local c = (nenner > 1e-12) and (-zaehler / nenner) or 0
    local maximum = { abs = 0, u = r.ys, v = r.zs, wert = 0 }
    for _, sm in ipairs(samples) do
        sm.ux = sm.ux + c
        if math.abs(sm.ux) > maximum.abs then maximum = { abs = math.abs(sm.ux), u = sm.u, v = sm.v, wert = sm.ux } end
    end
    return { M = M, G = G, theta = theta, It = It, Am = zellen.Am or 0, closed = geschlossen, pol = pol,
             samples = samples, paths = paths, max_abs = maximum.abs, max_u = maximum.u, max_v = maximum.v,
             max_wert = maximum.wert, schluss = schluss, c = c, sym_v = sym_v, sym_h = sym_h }
end

function woelb.oeffnen()
    qsMeldung = nil
    if not system_results then meldung("Kein Querschnitt vorhanden.", "Hinweis", true); return end
    if #duenn_elemente == 0 or #massiv_elemente > 0 then
        meldung("Verwoelbung nur fuer rein duennwandige Profile (offen oder einzellig geschlossen); fuer massive Querschnitte gibt es keine TM2-Formel.", "Verwoelbung nicht berechnet", true)
        return
    end
    local _, _, cells = find_closed_cells()
    if cells >= 2 then
        meldung("Mehrzelliges Profil: Torsion statisch unbestimmt, keine Verwoelbung.", "Verwoelbung nicht berechnet", true)
        return
    end
    woelb.step, woelb.results, woelb.visible = 1, nil, false
    menuOpen, showResults, showTable = false, false, false
    -- Vorbelegung: Torsionsmoment der eingetragenen Kraefte um den Schubmittelpunkt, sonst leer
    local ft = berechneKraftTorsion()
    inputText = ft and string.format("%.6g", display_moment(ft.M)) or ""
    qsMeldung = nil
    status = "Verwoelbung: Torsionsmoment MT in " .. moment_unit .. " eingeben, dann Enter."
end

function woelb.eingabe()
    local val = evaluate_input(inputText)
    if not val then
        meldung("Ungueltige Eingabe fuer die Verwoelbung.", "Eingabe", true)
        inputText = ""
        platform.window:invalidate()
        return true
    end
    if woelb.step == 1 then
        woelb.M = input_to_internal(val, moment_unit)
        woelb.step, inputText = 2, string.format("%.6g", woelb.G or 81000)
        status = "Schubmodul G in N/mm^2 eingeben, dann Enter."
    else
        woelb.G = val
        woelb.step, inputText = 0, ""
        local res, fehler = woelb.berechne(woelb.M, woelb.G)
        if res then
            woelb.results, woelb.visible = res, true
            shear_profile_visible, shear_selector_open, showResults = false, false, false
            status = "Verwoelbung berechnet. E: Werte, Esc schliesst die Ansicht."
            if not res.closed then
                meldung("Offenes Profil: die Verwoelbung folgt aus u_x = -theta * Int(r ds) + c um den Schubmittelpunkt "
                    .. "(der Bredt-Anteil entfaellt, es gibt keinen umlaufenden Schubfluss). Diese Formel steht nicht in "
                    .. "der Formelsammlung, dort ist nur der geschlossene Fall angegeben.", "Warnung", true)
                -- I_T und damit theta haengen am Profilbeiwert
                if qsHinweis.xiNoetig(res) then qsHinweis.melde(qsHinweis.xiText()) end
            end
        else
            meldung(fehler or "Verwoelbung nicht berechenbar.", "Verwoelbung nicht berechnet", true)
        end
    end
    platform.window:invalidate()
    return true
end

berechneSchubspannungsResultate = function(input_Qa, input_Qb)
    schub_grund = nil
    if not system_results then return nil end
    local r = qsWerte.geoSicht(system_results)
    local a, b = axes()
    local function ablehnen(text)
        schub_grund, status = text, text
        return nil
    end
    local in_a, in_b = coordinatesFromDisplay(input_Qa or 0, input_Qb or 0)
    local force_Qa, force_Qb = 0, 0
    for _, kraft in ipairs(kraefte) do
        force_Qa = force_Qa + (tonumber(kraft.fa) or 0)
        force_Qb = force_Qb + (tonumber(kraft.fb) or 0)
    end
    local Qa, Qb = in_a + force_Qa, in_b + force_Qb
    local Qa_d, Qb_d = coordinatesForDisplay(Qa, Qb)
    local force_Qa_d, force_Qb_d = coordinatesForDisplay(force_Qa, force_Qb)
    if #massiv_elemente > 0 and #duenn_elemente > 0 then
        return ablehnen("Schub fuer kombinierte massive und duennwandige Querschnitte nicht unterstuetzt.")
    end
    local force_torsion = berechneKraftTorsion()
    if force_torsion then
        torsion_results = force_torsion
    end
    local torsion_constant, enclosed_area, cells = find_closed_cells()
    local thin_closed = #duenn_elemente > 0 and cells == 1
    if #duenn_elemente > 0 then
        local maximum, samples, paths, fehler, info = berechneDuenneSchubspannung(Qa, Qb)
        if not maximum then return ablehnen(fehler or "Schubspannung nicht berechenbar.") end
        local result = {
            Qa = Qa_d, Qb = Qb_d, force_Qa = force_Qa_d, force_Qb = force_Qb_d,
            max_tau = maximum.abs_tau, max_u = maximum.u, max_v = maximum.v,
            samples = samples, paths = paths, thin_walled = true, axis_a = a, axis_b = b,
            thin_closed = thin_closed, torsion_constant = torsion_constant, enclosed_area = enclosed_area,
            sym_v = info and info.sym_v, sym_h = info and info.sym_h,
            zelle_korrigiert = info and info.zelle_s_korrigiert,
            schnitt_auf_achse = info and info.schnitt_auf_achse,
            shear_center = berechneSchubmittelpunkt(), torsion_open = r.It, torsion_closed = r.It_closed
        }
        shear_results = result
        if force_torsion then aktualisiereTorsionsverlauf(torsion_results) end
        -- Hinweise sammeln und in einer Box zeigen (sonst ueberschreibt der letzte die vorherigen)
        local hinweise, ist_warnung = {}, false
        if force_torsion and qsHinweis.xiNoetig(force_torsion) then hinweise[#hinweise + 1] = qsHinweis.xiText() end
        -- Geschlossene Zelle: q0 (konstanter Umlaufanteil) folgt nur aus der Symmetrie. Ohne erkannte
        -- Symmetrie bzw. ohne Querkraft bleibt er offen, die Verlaeufe gelten dann nur bis auf q0.
        if thin_closed then
            if (result.sym_v or result.sym_h) and result.schnitt_auf_achse == false then
                ist_warnung = true
                hinweise[#hinweise + 1] = "Geschlossene Zelle: die Laufvariable konnte nicht auf der "
                    .. "Symmetrieachse beginnen, weil dort kein Knoten der Zelle liegt (die Achse schneidet "
                    .. "die Zelle nicht). Der Schnitt liegt an beliebiger Stelle; die Werte sind zwar ueber "
                    .. "die Symmetrie korrigiert, S beginnt aber nicht bei null."
            end
            local vert = result.zelle_korrigiert and result.zelle_korrigiert.vertraeglich
            if not (result.sym_v or result.sym_h) then
                ist_warnung = true
                hinweise[#hinweise + 1] = "Geschlossene Zelle ohne erkannte Symmetrie: ueber die Symmetrie ist der "
                    .. "Umlaufschubfluss q0 hier nicht bestimmbar (statisch unbestimmt). Das Programm hat q0 deshalb "
                    .. "aus der Vertraeglichkeit bestimmt (Umlaufintegral q/t ds = 0, Querkraft im Schubmittelpunkt) "
                    .. "-- S und tau sind trotzdem richtig. Bei einem symmetrischen Profil muessen beide Haelften "
                    .. "gleich dick und spiegelbildlich zum Schwerpunkt liegen."
            elseif vert and ((vert.a and math.abs(Qa) > 1e-12) or (vert.b and math.abs(Qb) > 1e-12)) then
                ist_warnung = true
                local u_ist_a = (rotation == 0 or rotation == 180)
                local achse = (vert.a and math.abs(Qa) > 1e-12) and (u_ist_a and a or b) or (u_ist_a and b or a)
                hinweise[#hinweise + 1] = "Geschlossene Zelle: fuer die Querkraft parallel zur " .. achse
                    .. "-Achse fehlt die Symmetrieachse (erkannt: " .. tostring(info and info.erkannt or "keine")
                    .. "). q0 folgt fuer diese Richtung nicht aus der Symmetrie, sondern aus der Vertraeglichkeit "
                    .. "(Umlaufintegral q/t ds = 0, Querkraft im Schubmittelpunkt) -- S und tau sind trotzdem richtig."
            end
        end
        -- Hauptachsen nicht parallel zu y/z (Winkel kein Vielfaches von 90 Grad): Hinweis auf schiefe Biegung
        if math.abs(r.Iyz) > 1e-6 * math.sqrt(math.abs(r.Iy * r.Iz)) then
            result.iyz_kopplung = true
            hinweise[#hinweise + 1] = string.format("Hauptachsen nicht parallel zu %s/%s (I_%s%s ~= 0, Hauptachse bei %.2f Grad). Der Schubfluss wurde mit I_%s%s-Kopplung berechnet (schiefe Biegung), nicht mit tau = Q S/(I t).",
                a, b, a, b, math.deg(alphaForDisplay(r.alpha)), a, b)
        end
        if #hinweise > 0 then meldung(table.concat(hinweise, "  "), ist_warnung and "Warnung" or "Hinweis") end
        return result
    end
    -- Massiv: TM2-Schubformel nur fuer Hauptachsen parallel zu y/z
    if math.abs(r.IyzS) > 1e-6 * math.sqrt(math.abs(r.IyS * r.IzS)) then
        return ablehnen(string.format("Hauptachsen nicht parallel zu %s/%s (I_%s%s ~= 0, Hauptachse bei %.2f Grad). Fuer massive Querschnitte gilt tau = Q S/(I b) nur bei Hauptachsen parallel zu %s/%s.",
            a, b, a, b, math.deg(alphaForDisplay(r.alpha)), a, b))
    end
    local min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
    for _, elem in ipairs(massiv_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    if min_u == math.huge then return nil end

    -- eindimensionale Schnittintegration: S(v) ueber waagerechte, S(u) ueber senkrechte Schnitte
    local slices = 160
    local dv = math.max((max_v - min_v) / slices, 1e-9)
    local du = math.max((max_u - min_u) / slices, 1e-9)
    local tau_b, tau_a = {}, {}
    local moment_b, moment_a = 0, 0
    for row = slices, 1, -1 do
        local v = min_v + (row - 0.5) * dv
        local width = massiv_width_at_v(v)
        moment_b = moment_b + (v - r.zs) * width * dv
        tau_b[row] = (width > 1e-9 and math.abs(r.Iy) > 1e-12) and math.abs(Qb * moment_b / (r.Iy * width)) or 0
    end
    for column = slices, 1, -1 do
        local u = min_u + (column - 0.5) * du
        local height = massiv_height_at_u(u)
        moment_a = moment_a + (u - r.ys) * height * du
        tau_a[column] = (height > 1e-9 and math.abs(r.Iz) > 1e-12) and math.abs(Qa * moment_a / (r.Iz * height)) or 0
    end
    -- Maximum: groesste Werte beider Richtungen (Vektorsumme wie bisher)
    local max_tau_a, max_tau_b, best_u, best_v = 0, 0, r.ys, r.zs
    for column = 1, slices do if tau_a[column] > max_tau_a then max_tau_a, best_u = tau_a[column], min_u + (column - 0.5) * du end end
    for row = 1, slices do if tau_b[row] > max_tau_b then max_tau_b, best_v = tau_b[row], min_v + (row - 0.5) * dv end end
    local max_tau = math.sqrt(max_tau_a^2 + max_tau_b^2)
    local profile_samples = {}
    for row = 1, slices do
        local v = min_v + (row - 0.5) * dv
        local width = massiv_width_at_v(v)
        if width > 1e-12 then
            table.insert(profile_samples, {u = r.ys, v = v, tau_a = 0, tau_b = tau_b[row] or 0, tau = tau_b[row] or 0, moment_y_density = (v - r.zs) * width, moment_z_density = 0, parameter = row / slices, profile = "massiv_b"})
        end
    end
    for column = 1, slices do
        local u = min_u + (column - 0.5) * du
        local height = massiv_height_at_u(u)
        if height > 1e-12 then
            table.insert(profile_samples, {u = u, v = r.zs, tau_a = tau_a[column] or 0, tau_b = 0, tau = tau_a[column] or 0, moment_y_density = 0, moment_z_density = (u - r.ys) * height, parameter = column / slices, profile = "massiv_a"})
        end
    end
    return {
        Qa = Qa_d, Qb = Qb_d, force_Qa = force_Qa_d, force_Qb = force_Qb_d,
        max_tau = max_tau, max_u = (max_tau_a > 0) and best_u or r.ys, max_v = (max_tau_b > 0) and best_v or r.zs,
        samples = profile_samples, axis_a = a, axis_b = b,
        thin_closed = false, torsion_constant = 0, enclosed_area = 0,
        shear_center = nil, torsion_open = r.It, torsion_closed = r.It_closed
    }
end

local function finish_shape(type_name)
    if type_name == "force" then
        local pt = pending[1]
        table.insert(kraefte, {u = pt.u, v = pt.v, fa = 0, fb = 0, fc = 0})
        pending = {}
        mode = "idle"
        status = "Kraft platziert. Hover + Enter zum Bearbeiten."
        platform.window:invalidate()
        return
    end
    if type_name == "duenn_kreis" or type_name == "duenn_kreis_bogen" then
        -- duennwandig: Mittellinie mit Standarddicke, wie beim Linienzug (keine Loch-/Ueberlappungspruefung)
        table.insert(duenn_elemente, {type = type_name, points = pending, t = default_t})
        pending = {}
        mode = "idle"
        status = "Duennwandiges Element erstellt."
        berechneSystem()
        platform.window:invalidate()
        return
    end
    local elem = {type = type_name, points = pending, is_hole = false, is_numeric = false}
    if type_name == "massiv_linie" then
        elem.t = default_t
    end
    local status_overlap = checkOverlapStatus(elem)
    
    if status_overlap == "inside" then
        elem.is_hole = true
        table.insert(massiv_elemente, elem)
        pending = {}
        mode = "idle"
        status = "Element als Loch abgezogen."
        berechneSystem()
        platform.window:invalidate()
    elseif status_overlap == "partial" then
        overlap_pending_elem = elem
        mode = "overlap_prompt"
        status = "Ueberlappung! 1: Abziehen 2: Addieren (Numerisch) 3: Verwerfen"
        platform.window:invalidate()
    else
        table.insert(massiv_elemente, elem)
        pending = {}
        mode = "idle"
        status = "Element erstellt."
        berechneSystem()
        platform.window:invalidate()
    end
end

local function finish_thin_line()
    if #pending >= 2 then
        for i=1, #pending-1 do
            table.insert(duenn_elemente, {points = {pending[i], pending[i+1]}, t = default_t})
        end
    end
    pending = {}
    mode = "idle"
    status = "Duennwandiges Profil erstellt."
    berechneSystem()
    platform.window:invalidate()
end

local function drawAxes(gc)
    local a, b = axes()
    local x, y = toScreenKOS(0,0)
    local hx, hy = toScreenKOS(1,0)
    local vx, vy = toScreenKOS(0,1)
    
    local dx1, dy1 = hx - x, hy - y
    local mag1 = math.sqrt(dx1^2 + dy1^2)
    local X, Y = x, y
    if mag1 > 1e-5 then X, Y = x + dx1/mag1 * kos_pixel_length, y + dy1/mag1 * kos_pixel_length end
    
    local dx2, dy2 = vx - x, vy - y
    local mag2 = math.sqrt(dx2^2 + dy2^2)
    local Z, W = x, y
    if mag2 > 1e-5 then Z, W = x + dx2/mag2 * kos_pixel_length, y + dy2/mag2 * kos_pixel_length end
    
    gc:setColorRGB(35, 150, 70)
    gc:setPen("thin", "smooth")
    gc:drawLine(x, y, X, Y)
    gc:drawLine(x, y, Z, W)
    gc:setFont("sansserif", "r", 9)
    gc:drawString(a, X+4, Y-9)
    gc:drawString(b, Z+4, W-9)
    gc:setFont("sansserif", "r", 7)
    gc:drawString("0", x+3, y+2)
    
    if system_results then
        local sx, sy = toScreen(system_results.ys, system_results.zs)
        gc:setColorRGB(255, 0, 0)
        gc:drawLine(sx-5, sy, sx+5, sy)
        gc:drawLine(sx, sy-5, sx, sy+5)
        
        -- Hauptachsen 1 (η) und 2 (ζ) in den Richtungen des HAS (σx-Tabelle, Kernflaeche)
        local HA_len = 1.0 * scale
        local e1u, e1v, e2u, e2v = kernHAS.richtungen()
        local hx1, hy1 = sx + HA_len * e1u, sy - HA_len * e1v   -- Bildschirm-y nach unten
        local hx2, hy2 = sx + HA_len * e2u, sy - HA_len * e2v
        
        gc:setColorRGB(200, 50, 255)
        gc:setPen("thin", "dashed")
        gc:drawLine(sx, sy, hx1, hy1)
        gc:drawLine(sx, sy, hx2, hy2)
        gc:setFont("sansserif", "r", 8)
        gc:drawString("1", hx1+2, hy1-8)
        gc:drawString("2", hx2+2, hy2-8)
    end
end

local function drawGrid(gc, w, h)
    if rasterPunkte == 0 then return end
    local d = (rasterPunkte == 2) and 2 or 1
    gc:setColorRGB(180, 180, 180)
    for i = -30, 30 do
        for j = -24, 24 do
            local x, y = toScreen(i * raster, j * raster)
            if x >= 0 and x <= w and y >= 0 and y <= h then
                gc:fillRect(x, y, d, d)
            end
        end
    end
end

local function drawShapePath(gc, elem)
    
    if elem.type == "rect" then
        local p = elem.points
        local min_u, max_u = math.min(p[1].u, p[2].u), math.max(p[1].u, p[2].u)
        local min_v, max_v = math.min(p[1].v, p[2].v), math.max(p[1].v, p[2].v)
        local a, b = toScreen(min_u, min_v)
        local c, d = toScreen(max_u, max_v)
        local l, t = math.min(a, c), math.min(b, d)
        local w, h = math.abs(c - a), math.abs(d - b)
        gc:fillRect(l, t, w, h)
        gc:drawRect(l, t, w, h)
    elseif elem.type == "circle" or elem.type == "duenn_kreis" then
        local C = elem.points[1]
        local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
        local a, b = toScreen(C.u - R, C.v - R)
        local c, d = toScreen(C.u + R, C.v + R)
        local l, t = math.min(a, c), math.min(b, d)
        local w, h = math.abs(c - a), math.abs(d - b)
        gc:fillArc(l, t, w, h, 0, 360)
        gc:drawArc(l, t, w, h, 0, 360)
    elseif elem.type == "triangle" or elem.type == "trapezoid" then
        local q = {}
        for _, p in ipairs(elem.points) do
            local x, y = toScreen(p.u, p.v)
            table.insert(q, x)
            table.insert(q, y)
        end
        gc:fillPolygon(q)
        table.insert(q, q[1])
        table.insert(q, q[2])
        gc:drawPolyLine(q)
    elseif elem.type == "massiv_linie" then
        local p1, p2 = elem.points[1], elem.points[2]
        local du, dv = p2.u - p1.u, p2.v - p1.v
        local L = math.sqrt(du^2 + dv^2)
        local nx, ny = 0, 0
        if L > 1e-9 then nx, ny = (-dv/L) * (elem.t/2), (du/L) * (elem.t/2) end
        local pts = {
            {u = p1.u + nx, v = p1.v + ny},
            {u = p2.u + nx, v = p2.v + ny},
            {u = p2.u - nx, v = p2.v - ny},
            {u = p1.u - nx, v = p1.v - ny}
        }
        local q = {}
        for _, p in ipairs(pts) do
            local x, y = toScreen(p.u, p.v)
            table.insert(q, x)
            table.insert(q, y)
        end
        gc:fillPolygon(q)
        table.insert(q, q[1])
        table.insert(q, q[2])
        gc:drawPolyLine(q)
    elseif elem.type == "sector" or elem.type == "segment" or elem.type == "duenn_kreis_bogen" then
        local C = elem.points[1]
        local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
        local a1 = math.atan2(elem.points[2].v - C.v, elem.points[2].u - C.u)
        local a2 = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u)
        local diff = a2 - a1
        if diff <= 0 then diff = diff + 2*math.pi end
        
        local start_angle = math.deg(a1)
        local arc_angle = math.deg(diff)
        
        local a, b = toScreen(C.u - R, C.v - R)
        local c, d = toScreen(C.u + R, C.v + R)
        local l, t = math.min(a, c), math.min(b, d)
        local w, h = math.abs(c - a), math.abs(d - b)
        
        -- on screen, angles might be flipped if rotation/swapped
        -- Simplification: draw an approximated polygon
        local q = {}
        if elem.type == "sector" then
            local cx, cy = toScreen(C.u, C.v)
            table.insert(q, cx)
            table.insert(q, cy)
        end
        local steps = math.max(10, math.floor(arc_angle / 5))
        for i=0, steps do
            local ang = a1 + (i/steps)*diff
            local pu = C.u + R * math.cos(ang)
            local pv = C.v + R * math.sin(ang)
            local sx, sy = toScreen(pu, pv)
            table.insert(q, sx)
            table.insert(q, sy)
        end
        gc:fillPolygon(q)
        table.insert(q, q[1])
        table.insert(q, q[2])
        gc:drawPolyLine(q)
    end
end
local function drawLocalAxes(gc, elem)
    if not elem.ys or not elem.zs or not elem.alpha then return end
    local sx, sy = toScreen(elem.ys, elem.zs)
    local len = 30
    local a_rad = elem.alpha
    
    local hx1, hy1 = toScreen(elem.ys + math.cos(a_rad), elem.zs + math.sin(a_rad))
    local dx1, dy1 = hx1 - sx, hy1 - sy
    local mag1 = math.sqrt(dx1^2 + dy1^2)
    if mag1 > 1e-5 then dx1, dy1 = dx1/mag1 * len, dy1/mag1 * len end
    
    local hx2, hy2 = toScreen(elem.ys + math.cos(a_rad + math.pi/2), elem.zs + math.sin(a_rad + math.pi/2))
    local dx2, dy2 = hx2 - sx, hy2 - sy
    local mag2 = math.sqrt(dx2^2 + dy2^2)
    if mag2 > 1e-5 then dx2, dy2 = dx2/mag2 * len, dy2/mag2 * len end
    
    gc:setColorRGB(0, 100, 200)
    gc:setPen("medium", "smooth")
    gc:drawLine(sx, sy, sx + dx1, sy + dy1)
    gc:drawLine(sx, sy, sx + dx2, sy + dy2)
    gc:setFont("sansserif", "i", 9)
    gc:drawString("eta", sx + dx1 + 2, sy + dy1 - 8)
    gc:drawString("zeta", sx + dx2 + 2, sy + dy2 - 8)
end

local function drawSpreadsheet(gc, w, h)
    if not showResults then return end
    local width = 210
    local left = w - width
    local top = -results_scroll_y
    gc:setColorRGB(248, 248, 248)
    gc:fillRect(left, 0, width, h)
    gc:setColorRGB(0, 0, 0)
    gc:drawLine(left, 0, left, h)
    gc:clipRect("set", left, 0, width, h)

    gc:setFont("sansserif", "b", 9)
    gc:drawString("Ergebnisse", left + 5, top + 5)
    gc:setFont("sansserif", "r", 9)

    if system_results then
        local r = system_results
        local a, b = axes()
        local display_ys, display_zs = coordinatesForDisplay(r.ys, r.zs)
        local IyS_d, IzS_d, IyzS_d = inertiaForDisplay(r.IyS, r.IzS, r.IyzS)
        -- Bezug der Traegheitsmomente: Schwerpunkt oder Ursprung des gezeichneten KOS
        local bezug_kos = (ftm_bezug == "kos")
        local iy_anz = bezug_kos and (IyS_d + r.A * display_zs^2) or IyS_d
        local iz_anz = bezug_kos and (IzS_d + r.A * display_ys^2) or IzS_d
        local iyz_anz = bezug_kos and (IyzS_d - r.A * display_ys * display_zs) or IyzS_d
        local bezug_kurz = bezug_kos and " (KOS)" or ",S"
        local W_a, W_b = r.Wu, r.Wv
        if rotation == 90 or rotation == 270 then W_a, W_b = r.Wv, r.Wu end
        local mA, ma, mb, mab, mS = qsWerte.anzeige()
        local function mk(f) return f and "  (manuell)" or "" end
        local lines = {
            string.format("A = %.4g [%s]", display_area(r.A), unit_label(2)) .. mk(mA),
            string.format("%s_s = %.4g [%s]", a, display_length(display_ys), unit_label(1)) .. mk(mS),
            string.format("%s_s = %.4g [%s]", b, display_length(display_zs), unit_label(1)) .. mk(mS),
            string.format("I_%s%s = %.4g [%s]", a, bezug_kurz, display_inertia(iy_anz), unit_label(4)) .. mk(ma),
            string.format("I_%s%s = %.4g [%s]", b, bezug_kurz, display_inertia(iz_anz), unit_label(4)) .. mk(mb),
            string.format("I_%s%s%s = %.4g [%s]", a, b, bezug_kurz, display_inertia(iyz_anz), unit_label(4)) .. mk(mab),
            string.format("i_%s = %.4g [%s]", a, display_length(math.sqrt(math.abs(IyS_d / r.A))), unit_label(1)),
            string.format("i_%s = %.4g [%s]", b, display_length(math.sqrt(math.abs(IzS_d / r.A))), unit_label(1)),
            string.format("W_%s = %.4g [%s]", a, display_volume(W_a), unit_label(3)),
            string.format("W_%s = %.4g [%s]", b, display_volume(W_b), unit_label(3)),
            string.format("I_1,S = %.4g [%s]", display_inertia(r.I1), unit_label(4)),
            string.format("I_2,S = %.4g [%s]", display_inertia(r.I2), unit_label(4)),
            string.format("alpha = %.2f [deg]", math.deg(alphaForDisplay(r.alpha))),
        }
        if #duenn_elemente > 0 then
            table.insert(lines, string.format("I_T(offen) = %.4g [%s]", display_inertia(r.It), unit_label(4)))
            if r.It_closed > 1e-9 then
                table.insert(lines, string.format("I_T(geschlossen) = %.4g [%s]", display_inertia(r.It_closed), unit_label(4)))
                table.insert(lines, string.format("A_m = %.4g [%s]", display_area(r.Am), unit_label(2)))
                -- Zellsymmetrie: davon haengt ab, ob der Schubfluss q0 bestimmbar ist
                local u_ist_a = (rotation == 0 or rotation == 180)
                local namen = {}
                if r.sym_v then namen[#namen + 1] = u_ist_a and b or a end
                if r.sym_h then namen[#namen + 1] = u_ist_a and a or b end
                table.insert(lines, #namen > 0 and ("Zellsymmetrie: " .. table.concat(namen, ", ") .. "-Achse")
                    or "Zellsymmetrie: keine erkannt (q0 offen)")
            end
        end
        if shear_results then
            table.insert(lines, "--- Schubspannung ---")
            table.insert(lines, string.format("Q_%s = %.4g [%s]", shear_results.axis_a, display_force(shear_results.Qa), force_unit))
            table.insert(lines, string.format("Q_%s = %.4g [%s]", shear_results.axis_b, display_force(shear_results.Qb), force_unit))
            table.insert(lines, string.format("Q_%s aus Kraeften = %.4g [%s]", shear_results.axis_a, display_force(shear_results.force_Qa), force_unit))
            table.insert(lines, string.format("Q_%s aus Kraeften = %.4g [%s]", shear_results.axis_b, display_force(shear_results.force_Qb), force_unit))
            table.insert(lines, string.format("tau_max = %.4g [MPa]", shear_results.max_tau))
            if shear_results.max_tau_total then
                table.insert(lines, string.format("tau_gesamt,max = %.4g [MPa]", shear_results.max_tau_total))
            end
            local max_a, max_b = coordinatesForDisplay(shear_results.max_u, shear_results.max_v)
            table.insert(lines, string.format("bei (%s,%s) = (%.4g,%.4g)", shear_results.axis_a, shear_results.axis_b, display_length(max_a), display_length(max_b)))
            if shear_results.thin_walled then
                table.insert(lines, shear_results.thin_closed and "duennwandig geschlossen" or "duennwandig offen")
                if shear_results.thin_closed then
                    table.insert(lines, string.format("A_m = %.4g [%s]", display_area(shear_results.enclosed_area or 0), unit_label(2)))
                end
                if shear_results.shear_center then
                    if shear_results.shear_center.known then
                        table.insert(lines, "Schubmittelpunkt = (" .. formatLabel(display_length(coordinatesForDisplay(shear_results.shear_center.u, shear_results.shear_center.v))) .. ", " .. formatLabel(display_length(select(2, coordinatesForDisplay(shear_results.shear_center.u, shear_results.shear_center.v)))) .. ") [" .. length_unit .. "]")
                        if shear_results.shear_center.moment_a then
                            table.insert(lines, string.format("Probe-Ma = %.4g [%s]", display_moment(shear_results.shear_center.moment_a), moment_unit))
                            table.insert(lines, string.format("Probe-Mb = %.4g [%s]", display_moment(shear_results.shear_center.moment_b), moment_unit))
                        end
                    elseif shear_results.shear_center.known_u or shear_results.shear_center.known_v then
                        -- nur die Lage auf der Symmetrieachse ist bekannt
                        local c = shear_results.shear_center
                        local du_, dv_ = coordinatesForDisplay(c.u, c.v)
                        local u_ist_a = (rotation == 0 or rotation == 180)
                        local bekannt_a = (c.known_u and u_ist_a) or (c.known_v and not u_ist_a)
                        local label = bekannt_a and (shear_results.axis_a .. "_M = " .. formatLabel(display_length(du_)))
                            or (shear_results.axis_b .. "_M = " .. formatLabel(display_length(dv_)))
                        table.insert(lines, "Schubmittelpunkt: " .. label .. " [" .. length_unit .. "]")
                        table.insert(lines, "  zweite Koordinate statisch unbestimmt")
                    else
                        table.insert(lines, "Schubmittelpunkt: statisch unbestimmt")
                    end
                    table.insert(lines, string.format("I_T offen = %.4g [%s]", display_inertia(shear_results.torsion_open or 0), unit_label(4)))
                    if shear_results.thin_closed then
                        table.insert(lines, string.format("I_T geschlossen = %.4g [%s]", display_inertia(shear_results.torsion_closed or 0), unit_label(4)))
                    end
                end
            end
        end
        if woelb.results then
            local wr = woelb.results
            table.insert(lines, "--- Verwoelbung ---")
            table.insert(lines, string.format("MT = %.4g [%s]", display_moment(wr.M), moment_unit))
            table.insert(lines, string.format("G = %.4g [N/mm^2]", wr.G))
            table.insert(lines, string.format("I_T = %.4g [%s]", display_inertia(wr.It), unit_label(4)))
            if wr.closed then table.insert(lines, string.format("A_m = %.4g [%s]", display_area(wr.Am), unit_label(2))) end
            table.insert(lines, string.format("theta = %.4g [1/%s]", wr.theta * unit_factor(length_unit), length_unit))
            local mu, mv = coordinatesForDisplay(wr.max_u, wr.max_v)
            table.insert(lines, string.format("u_x,max = %.4g [%s]", display_length(wr.max_abs), length_unit))
            table.insert(lines, string.format("bei (%s,%s) = (%.4g,%.4g)", a, b, display_length(mu), display_length(mv)))
            local pu, pv = coordinatesForDisplay(wr.pol.u, wr.pol.v)
            table.insert(lines, string.format("Pol M = (%.4g, %.4g) [%s]", display_length(pu), display_length(pv), length_unit))
            table.insert(lines, wr.closed and "geschlossen (Formelsammlung Kap. 6)" or "offen (Warnung: nicht in der Formelsammlung)")
        end
        if torsion_results then
            table.insert(lines, "--- Torsion ---")
            table.insert(lines, string.format("MT = %.4g [%s]", display_moment(torsion_results.M), moment_unit))
            table.insert(lines, string.format("I_T = %.4g [%s]", display_inertia(torsion_results.It), unit_label(4)))
            table.insert(lines, string.format("tau_T,max = %.4g [MPa]", torsion_results.tau))
            table.insert(lines, torsion_results.closed and "geschlossen" or "offen")
        end

        for i, text in ipairs(lines) do
            gc:drawString(text, left + 5, top + 20 + i * 16)
        end

        if math.abs(r.A) > 1e-9 then
            gc:setFont("sansserif", "b", 9)
            if math.abs(r.Iyz) <= 1e-6 * math.sqrt(math.abs(r.Iy * r.Iz)) then
                gc:setColorRGB(35, 150, 70)
                gc:drawString("Hauptachsen parallel zu den Achsen (I_yz = 0)", left + 5, top + 20 + (#lines + 2) * 16)
            else
                gc:setColorRGB(220, 110, 0)
                gc:drawString("Hauptachsen nicht parallel zu den Achsen (I_yz ~= 0)", left + 5, top + 20 + (#lines + 2) * 16)
            end
        end
        if is_numeric_system then
            gc:setColorRGB(255, 100, 0)
            gc:setFont("sansserif", "b", 9)
            gc:drawString("Warnung: Numerisch berechnet!", left + 5, top + 20 + (#lines + 4) * 16)
        end
    else
        gc:drawString("Keine Flaechen gezeichnet.", left + 5, top + 25)
    end
    gc:clipRect("reset")
end

local function drawSigmaInput(gc, w, h)
    if sigma_input_step == 0 then return end
    local felder = sigmaEingabe.felder
    local moment_a, moment_b = axes()
    local achse = sigmaEingabe.stabachse()
    -- Hoehe aus der Feldzahl: vier Felder, Hinweiszeile und Fusszeile passen in 212 px
    local left, top, width = 12, 16, math.min(290, w - 24)
    local field_left = left + 78
    local field_width = width - 90
    local abstand = 28
    local hat_x = false
    for _, f in ipairs(felder) do if f == "x" then hat_x = true end end
    local unten = top + 26 + #felder * abstand
    local height = unten - top + (hat_x and 26 or 14)

    local function wert(feld)
        if feld == "N" then return sigma_N == nil and "" or string.format("%.6g", display_force(sigma_N)) end
        if feld == "Ma" then return sigma_My == nil and "" or string.format("%.6g", display_moment(sigma_My)) end
        if feld == "Mb" then return sigma_Mz == nil and "" or string.format("%.6g", display_moment(sigma_Mz)) end
        return string.format("%.6g", display_length(sigmaEingabe.versatz or 0))
    end
    local function name(feld)
        if feld == "N" then return "N [" .. force_unit .. "]" end
        if feld == "Ma" then return "M" .. moment_a .. " [" .. moment_unit .. "]" end
        if feld == "Mb" then return "M" .. moment_b .. " [" .. moment_unit .. "]" end
        return "Δ" .. achse .. " [" .. length_unit .. "]"
    end

    gc:setColorRGB(248, 248, 248)
    gc:fillRect(left, top, width, height)
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(left, top, width, height)
    gc:setFont("sansserif", "b", 10)
    gc:drawString("σx Eingabe", left + 8, top + 6)
    gc:setFont("sansserif", "r", 9)
    for i, feld in ipairs(felder) do
        local y = top + 26 + (i - 1) * abstand
        gc:drawString(name(feld), left + 8, y + 4)
        gc:drawRect(field_left, y, field_width, 20)
        local bereits = i < sigma_input_step
        local t = (i == sigma_input_step) and (inputText .. "_") or (bereits and wert(feld) or "")
        gc:drawString(t, field_left + 5, y + 4)
    end
    gc:setFont("sansserif", "r", 8)
    if hat_x then
        gc:setColorRGB(60, 60, 60)
        gc:drawString("Δ" .. achse .. " = Abstand Schnitt - Kraftebene (Betrag)", left + 8, unten)
        gc:setColorRGB(0, 0, 0)
    end
    gc:drawString("Enter bestaetigen, Esc abbrechen", left + 8, top + height - 14)
end

local function drawShearInput(gc, w, h)
    if shear_input_step == 0 then return end
    local left, top, width = 12, 28, math.min(280, w - 24)
    local a, b = axes()
    local field_left, field_width = left + 72, width - 84
    gc:setColorRGB(248, 248, 248)
    local input_height = shear_external_input and 146 or 112
    gc:fillRect(left, top, width, input_height)
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(left, top, width, input_height)
    gc:setFont("sansserif", "b", 10)
    gc:drawString("Schubkraft-Eingabe", left + 8, top + 8)
    gc:setFont("sansserif", "r", 9)
    gc:drawString("Q" .. a .. " [" .. force_unit .. "]", left + 8, top + 36)
    gc:drawString("Q" .. b .. " [" .. force_unit .. "]", left + 8, top + 70)
    gc:drawRect(field_left, top + 28, field_width, 20)
    gc:drawRect(field_left, top + 62, field_width, 20)
    gc:drawString(shear_input_step == 1 and inputText .. "_" or string.format("%.6g", shear_Qa or 0), field_left + 5, top + 33)
    gc:drawString(shear_input_step == 2 and inputText .. "_" or string.format("%.6g", shear_Qb or 0), field_left + 5, top + 67)
    if shear_external_input then
        gc:drawString("MT [" .. moment_unit .. "]", left + 8, top + 104)
        gc:drawRect(field_left, top + 96, field_width, 20)
        gc:drawString(shear_input_step == 4 and inputText .. "_" or string.format("%.6g", shear_M or 0), field_left + 5, top + 101)
    end
    gc:setFont("sansserif", "r", 8)
    gc:drawString("Enter bestaetigen, Esc abbrechen", left + 8, top + (shear_external_input and 128 or 94))
end

local function drawTorsionInput(gc, w, h)
    if torsion_input_step == 0 then return end
    local left, top, width = 12, 28, 250
    gc:setColorRGB(248, 248, 248); gc:fillRect(left, top, width, 88)
    gc:setColorRGB(0, 0, 0); gc:drawRect(left, top, width, 88)
    gc:setFont("sansserif", "b", 10); gc:drawString("Torsion", left + 8, top + 8)
    gc:setFont("sansserif", "r", 9); gc:drawString("MT [" .. moment_unit .. "]", left + 8, top + 36)
    gc:drawRect(left + 72, top + 28, width - 84, 20)
    gc:drawString(inputText .. "_", left + 77, top + 33)
    gc:setFont("sansserif", "r", 8); gc:drawString("Enter bestaetigen, Esc abbrechen", left + 8, top + 68)
end

-- ===== Verlaufsdarstellung (Schub, spaeter auch Verwoelbung) =====
-- Der Engpass war das Zeichnen, nicht die Rechnung: pro Frame wurden alle Stuetzstellen neu in
-- Abschnitte einsortiert, jeder Abschnitt sortiert, der Wert dreimal je Punkt ausgewertet und
-- jeder Punkt einzeln mit drawLine gezeichnet. Jetzt werden die Abschnitte (sortierte
-- Stuetzstellen, Werte, Pixelversatz normal zur Wand) einmal aufgebaut und je Frame nur noch in
-- Bildschirmpunkte umgerechnet, auf etwa einen Punkt je 1,5 px ausgeduennt und als eine
-- Polylinie je Abschnitt gezeichnet. Min/Max und Endwerte kommen weiterhin aus allen
-- Stuetzstellen; die Rechendichte ist unveraendert.
local verlauf = { cache = nil, breite = 36 }   -- Cache der Abschnitte; Pixel fuer den groessten Wert

local function verlaufAbschnitte(quelle)
    local schluessel = table.concat({ tostring(quelle.id), tostring(quelle.key), tostring(rotation),
        tostring(quelle.hovered or "-") }, "|")
    if verlauf.cache and verlauf.cache.schluessel == schluessel then return verlauf.cache end
    local abschnitte, aktuell, aktuell_key = {}, nil, nil
    for index, sample in ipairs(quelle.samples) do
        if not quelle.hovered or sample.segment == quelle.hovered then
            local k = tostring(sample.path_id or 1) .. ":" .. tostring(sample.segment or sample.profile or 1)
            if not aktuell or aktuell_key ~= k then
                aktuell, aktuell_key = {}, k
                abschnitte[#abschnitte + 1] = aktuell
            end
            aktuell[#aktuell + 1] = { index = index, sample = sample, wert = quelle.wert(sample) }
        end
    end
    local gesamt_max = 1e-9
    for _, ab in ipairs(abschnitte) do
        for _, e in ipairs(ab) do gesamt_max = math.max(gesamt_max, math.abs(e.wert)) end
    end
    local massiv_max = math.max(quelle.maximum or 0, 1e-9)
    local hover_max, hover_max_eintrag = -math.huge, nil
    for _, ab in ipairs(abschnitte) do
        table.sort(ab, function(l, r)
            return (l.sample.s or l.sample.parameter or l.index) < (r.sample.s or r.sample.parameter or r.index)
        end)
        ab.min, ab.max = nil, nil
        for _, e in ipairs(ab) do
            local sm = e.sample
            -- Pixelversatz des Verlaufspunkts gegenueber der Wand (Bildschirm: x rechts, y unten)
            if sm.profile == "massiv_b" then
                e.fx, e.fy = (e.wert / massiv_max) * verlauf.breite, 0
            elseif sm.profile == "massiv_a" then
                e.fx, e.fy = 0, -(e.wert / massiv_max) * verlauf.breite
            elseif sm.display_normal_u and sm.display_normal_v then
                local f = e.wert / gesamt_max * verlauf.breite
                e.fx, e.fy = sm.display_normal_u * f, -sm.display_normal_v * f
            else
                e.fx, e.fy = 0, 0
            end
            if not ab.min or e.wert < ab.min.wert then ab.min = e end
            if not ab.max or e.wert > ab.max.wert then ab.max = e end
            if quelle.hovered and e.wert > hover_max then hover_max, hover_max_eintrag = e.wert, e end
        end
    end
    verlauf.cache = { schluessel = schluessel, abschnitte = abschnitte, hover_max = hover_max_eintrag }
    return verlauf.cache
end

local function drawVerlauf(gc, quelle)
    local cache = verlaufAbschnitte(quelle)
    local farbe = quelle.farbe or { 45, 95, 175 }
    gc:setColorRGB(20, 70, 150)
    gc:setFont("sansserif", "b", 10)
    gc:drawString(quelle.titel, 6, 5)
    local function punkt(e) return ox + e.sample.u * scale + e.fx, oy - e.sample.v * scale + e.fy end
    local function verbinder(e)
        if not e or not (e.sample.display_normal_u and e.sample.display_normal_v) then return end
        local x, y = punkt(e)
        gc:setColorRGB(150, 150, 150); gc:setPen("thin", "smooth")
        gc:drawLine(ox + e.sample.u * scale, oy - e.sample.v * scale, x, y)
    end
    local function wert(e, label, color)
        if not e then return end
        local x, y = punkt(e)
        gc:setColorRGB(color[1], color[2], color[3])
        gc:fillArc(x - 2, y - 2, 4, 4, 0, 360)
        gc:setFont("sansserif", "r", 8)
        gc:drawString((label ~= "" and (label .. " ") or "") .. formatLabel(quelle.anzeige(e.wert)), x + 4, y - 10)
    end
    for _, ab in ipairs(cache.abschnitte) do
        local n = #ab
        local pts, lx, ly = {}, nil, nil
        for i, e in ipairs(ab) do
            local x, y = punkt(e)
            if i == 1 or i == n or (x - lx) ^ 2 + (y - ly) ^ 2 >= 2.25 then
                pts[#pts + 1] = x; pts[#pts + 1] = y
                lx, ly = x, y
            end
        end
        gc:setColorRGB(farbe[1], farbe[2], farbe[3])
        gc:setPen("thin", "smooth")
        if #pts >= 4 then gc:drawPolyLine(pts) end
        local erster, letzter = ab[1], ab[n]
        verbinder(erster); verbinder(letzter)
        wert(erster, "", { 40, 80, 150 })
        if letzter ~= erster then wert(letzter, "", { 40, 80, 150 }) end
        if quelle.hovered then
            if ab.max == cache.hover_max and ab.max ~= erster and ab.max ~= letzter then wert(ab.max, "max", { 190, 60, 60 }) end
        else
            if ab.min and ab.min ~= erster and ab.min ~= letzter then wert(ab.min, "min", { 190, 60, 60 }) end
            if ab.max and ab.max ~= erster and ab.max ~= letzter then wert(ab.max, "max", { 190, 60, 60 }) end
        end
    end
end

-- Laufrichtung der Integration (Pfeile) und Startmarken je Pfad. Die Pfeile zeigen die
-- Orientierung der Laufvariablen, nicht die Richtung der Spannungskomponente.
local function drawLaufrichtung(gc, paths, hovered_segment, korrigiert)
    if not paths then return end
    gc:setColorRGB(145, 55, 180)
    gc:setPen("thin", "smooth")
    for _, path in ipairs(paths) do
        if path.start_kind and path.items[1] and path.items[1].p1 then
            local start_point = path.items[1].p1
            local start_x, start_y = toScreen(start_point.u, start_point.v)
            gc:fillArc(start_x - 3, start_y - 3, 6, 6, 0, 360)
            gc:setFont("sansserif", "b", 9)
            -- "Start" heisst: hier beginnt die Laufvariable und S ist null (freies Ende).
            -- In der geschlossenen Zelle wird nur aufgeschnitten; S = 0 liegt nach der
            -- Symmetriekorrektur auf der Symmetrieachse. Ohne Symmetrie kommt q0 aus der
            -- Vertraeglichkeit, S ist am Schnitt dann im Allgemeinen nicht null.
            local text = "Start"
            if path.start_kind == "cut_sym" then
                text = "Start (Symmetrieachse)"
            elseif path.start_kind == "cut" then
                local k = korrigiert
                if k and k.vertraeglich and (k.vertraeglich.a or k.vertraeglich.b) then
                    text = "Schnitt (q0 aus Verträglichkeit)"
                elseif k and (k.a or k.b) then
                    text = "Schnitt"
                else
                    text = "Schnitt (q0 offen)"
                end
            end
            gc:drawString(text, start_x + 5, start_y - 10)
        end
        for _, item in ipairs(path.items) do
            if item.p1 and item.p2 and (not hovered_segment or item.edge.index == hovered_segment) then
                local mx = (item.p1.u + item.p2.u) / 2
                local mv = (item.p1.v + item.p2.v) / 2
                local dx, dv = item.p2.u - item.p1.u, item.p2.v - item.p1.v
                local length = math.sqrt(dx^2 + dv^2)
                if length > 1e-9 then
                    local ux, uv = dx / length, dv / length
                    local tx, ty = toScreen(mx - ux * 0.35, mv - uv * 0.35)
                    local px, py = toScreen(mx + ux * 0.35, mv + uv * 0.35)
                    gc:drawLine(tx, ty, px, py)
                    local screen_dx, screen_dy = px - tx, py - ty
                    local screen_length = math.sqrt(screen_dx^2 + screen_dy^2)
                    if screen_length > 1e-9 then
                        local ax, ay = screen_dx / screen_length, screen_dy / screen_length
                        local nx, ny = -ay, ax
                        gc:drawLine(px, py, px - ax * 5 + nx * 3, py - ay * 5 + ny * 3)
                        gc:drawLine(px, py, px - ax * 5 - nx * 3, py - ay * 5 - ny * 3)
                    end
                end
            end
        end
    end
end

local function drawShearProfileLegacy(gc)
    if not shear_profile_visible or not shear_results or not shear_results.samples then return end
    local hovered_segment = hover_type == "duenn" and hover_idx or nil
    local axis_a, axis_b = axes()
    -- Reihenfolge: 1/2 Momentendichten, 3/4 statische Momente, 5/6 Schubspannungsanteile,
    -- 7 Resultierend aus Querkraft, 8 Torsion, 9 Gesamt aus allem, 10 Laufvariable s.
    local profile_name = shear_view_mode == 1 and axis_a .. "*h(" .. axis_a .. ") [" .. unit_label(2) .. "]"
        or shear_view_mode == 2 and axis_b .. "*h(" .. axis_b .. ") [" .. unit_label(2) .. "]"
        or shear_view_mode == 3 and "S" .. axis_a .. " [" .. unit_label(3) .. "]"
        or shear_view_mode == 4 and "S" .. axis_b .. " [" .. unit_label(3) .. "]"
        or shear_view_mode == 5 and "τ_" .. axis_a .. "-Anteil [MPa]"
        or shear_view_mode == 6 and "τ_" .. axis_b .. "-Anteil [MPa]"
        or shear_view_mode == 7 and "Resultierend aus Querkraft: τ_" .. axis_a .. " + τ_" .. axis_b .. " [MPa]"
        or shear_view_mode == 8 and "Torsionsanteil [MPa]"
        or shear_view_mode == 9 and "Gesamtschubspannung [MPa]"
        or shear_view_mode == 10 and "Laufvariable s [" .. unit_label(1) .. "]"
        or "Schubspannungsverlauf"
    local function profile_value(sample)
        local display_sz, display_sy = coordinatesForDisplay(sample.Sz or 0, sample.Sy or 0)
        return shear_view_mode == 1 and displayedMomentDensity(sample)
            or shear_view_mode == 2 and select(2, displayedMomentDensity(sample))
            or shear_view_mode == 3 and display_sy
            or shear_view_mode == 4 and display_sz
            or shear_view_mode == 5 and sample.tau_a
            or shear_view_mode == 6 and sample.tau_b
            or shear_view_mode == 8 and torsionTauAtSample(sample)
            or shear_view_mode == 9 and combinedTauAtSample(sample)
            or shear_view_mode == 10 and (sample.s or 0)
            or sample.tau
    end
    local function profile_display_value(value)
        if shear_view_mode == 1 or shear_view_mode == 2 then return display_area(value) end
        if shear_view_mode == 3 or shear_view_mode == 4 then return display_volume(value) end
        if shear_view_mode == 10 then return display_length(value) end
        return value
    end
    drawVerlauf(gc, {
        id = shear_results,
        key = tostring(shear_view_mode) .. "|" .. tostring(torsion_results) .. "|" .. tostring(shear_results.max_tau_total),
        samples = shear_results.samples, hovered = hovered_segment, maximum = shear_results.max_tau,
        wert = profile_value, anzeige = profile_display_value, titel = profile_name,
    })
    drawLaufrichtung(gc, shear_results.paths, hovered_segment, shear_results.zelle_korrigiert)
end

local function drawShearProfile(gc)
    if not shear_profile_visible or not shear_results or not shear_results.samples then return end
    drawShearProfileLegacy(gc)
end

function woelb.zeichneDialog(gc, w, h)
    if woelb.step == 0 then return end
    local left, top, width = 12, 28, math.min(280, w - 24)
    local field_left, field_width = left + 96, width - 108
    gc:setColorRGB(248, 248, 248); gc:fillRect(left, top, width, 118)
    gc:setColorRGB(0, 0, 0); gc:drawRect(left, top, width, 118)
    gc:setFont("sansserif", "b", 10); gc:drawString("Verwölbung", left + 8, top + 8)
    gc:setFont("sansserif", "r", 9)
    gc:drawString("MT [" .. moment_unit .. "]", left + 8, top + 36)
    gc:drawString("G [N/mm^2]", left + 8, top + 70)
    gc:drawRect(field_left, top + 28, field_width, 20)
    gc:drawRect(field_left, top + 62, field_width, 20)
    gc:drawString(woelb.step == 1 and (inputText .. "_") or string.format("%.6g", display_moment(woelb.M or 0)), field_left + 5, top + 33)
    gc:drawString(woelb.step == 2 and (inputText .. "_") or string.format("%.6g", woelb.G or 81000), field_left + 5, top + 67)
    gc:setFont("sansserif", "r", 8)
    gc:drawString("Pol: Schubmittelpunkt. Enter bestaetigen, Esc abbrechen", left + 8, top + 98)
end

-- Verwoelbungsverlauf wie die Schubverlaeufe (normal zur Wand), dazu MT als Drehpfeil um den
-- Pol -- das Moment wird nur in dieser Ansicht gezeichnet.
function woelb.zeichne(gc)
    if not woelb.visible or not woelb.results then return end
    local wr = woelb.results
    local hovered_segment = hover_type == "duenn" and hover_idx or nil
    drawVerlauf(gc, {
        id = wr, key = "woelb", samples = wr.samples, hovered = hovered_segment,
        wert = function(sm) return sm.ux end, anzeige = function(v) return display_length(v) end,
        titel = "Verwölbung u_x [" .. length_unit .. "]   MT = " .. formatLabel(display_moment(wr.M)) .. " " .. moment_unit
            .. "   G = " .. formatLabel(wr.G) .. " N/mm^2",
        farbe = { 30, 130, 90 },
    })
    local cx, cy = toScreen(wr.pol.u, wr.pol.v)
    gc:setColorRGB(200, 60, 20); gc:setPen("medium", "smooth")
    gc:fillArc(cx - 3, cy - 3, 6, 6, 0, 360)
    local rad = 16
    local sgn = (wr.M >= 0) and 1 or -1          -- positiv: gegen den Uhrzeigersinn, wie der Bredt-Schubfluss
    local pts = {}
    local a0, a1 = math.rad(-60), math.rad(240)
    for k = 0, 20 do
        local a = a0 + (a1 - a0) * k / 20
        pts[#pts + 1] = cx + rad * math.cos(a)
        pts[#pts + 1] = cy - sgn * rad * math.sin(a)
    end
    gc:drawPolyLine(pts)
    local ex, ey, qx, qy = pts[#pts - 1], pts[#pts], pts[#pts - 3], pts[#pts - 2]
    local dx, dy = ex - qx, ey - qy
    local L = math.sqrt(dx * dx + dy * dy)
    if L > 1e-9 then
        dx, dy = dx / L, dy / L
        gc:fillPolygon({ ex, ey, ex - 7 * dx + 3 * dy, ey - 7 * dy - 3 * dx, ex - 7 * dx - 3 * dy, ey - 7 * dy + 3 * dx })
    end
    gc:setPen("thin", "smooth")
    gc:setFont("sansserif", "b", 9)
    gc:drawString("MT = " .. formatLabel(display_moment(wr.M)) .. " " .. moment_unit, cx + rad + 4, cy - 6)
    gc:setFont("sansserif", "r", 8); gc:setColorRGB(60, 60, 60)
    gc:drawString(wr.closed and "geschlossen: Bredt-Anteil - r*theta (Formelsammlung Kap. 6), Pol = Schubmittelpunkt"
        or "offen: u = -theta*Int(r ds) + c um den Schubmittelpunkt (nicht in der Formelsammlung)", 6, platform.window:height() - 12)
end

local function drawShearSelector(gc, w, h)
    if not shear_selector_open then return end
    local a, b = axes()
    local items = {
        "1: " .. a .. "*h(" .. a .. ")",
        "2: " .. b .. "*h(" .. b .. ")",
        "3: S" .. a,
        "4: S" .. b,
        "5: τ_" .. a .. "-Anteil",
        "6: τ_" .. b .. "-Anteil",
        "7: Gesamt aus Querkraft",
        "8: Torsion",
        "9: Gesamt aus allem",
        "0: Laufvariable s"
    }
    local row_height = 18
    local width, height = 260, 34 + #items * row_height
    local left, top = 8, (h - height) / 2   -- Auswahlmenue links
    gc:setColorRGB(245, 250, 255)
    gc:fillRect(left, top, width, height)
    gc:setColorRGB(30, 80, 150)
    gc:drawRect(left, top, width, height)
    gc:setFont("sansserif", "b", 10)
    gc:drawString("Schubspannungsverlauf", left + 8, top + 8)
    gc:setFont("sansserif", "r", 9)
    for i, text in ipairs(items) do
        gc:drawString(text, left + 8, top + 22 + (i - 1) * row_height)
    end
end

-- Spannungsebene im angezeigten KOS und im Hauptachsensystem. Grundlage ist dieselbe Ebene, die
-- auch Nulllinie und Extremwerte liefert (intern sigma = N/A + s_u (u - u_S) + s_v (v - v_S)):
-- der Gradient dreht sich wie ein Vektor, so dass keine zweite Vorzeichenherleitung noetig ist.
-- HAS nach Formelsammlung: eta = y' cos(phi) + z' sin(phi), zeta = -y' sin(phi) + z' cos(phi)
-- (y', z' vom Schwerpunkt aus), I_eta = I_1, I_zeta = I_2; Momente drehen sich genauso.
function sigmaEingabe.kennwerte(sr)
    local den = sr.Iy * sr.Iz - sr.Iyz ^ 2
    local su = -((sr.Mz_Nmm * sr.Iy - sr.My_Nmm * sr.Iyz) / den)
    local sv = (sr.My_Nmm * sr.Iz - sr.Mz_Nmm * sr.Iyz) / den
    local cy, cz = coordinatesForDisplay(su, sv)
    local ys, zs = coordinatesForDisplay(sr.ys, sr.zs)
    local Iy, Iz, Iyz = inertiaForDisplay(sr.Iy, sr.Iz, sr.Iyz)
    local My, Mz = coordinatesForDisplay(sr.My_Nmm, sr.Mz_Nmm)
    local phi = alphaForDisplay(sr.alpha or 0)
    local c, sn = math.cos(phi), math.sin(phi)
    return {
        n0 = sr.normal, cy = cy, cz = cz, ys = ys, zs = zs,
        c0 = sr.normal - cy * ys - cz * zs,          -- Konstante im KOS (Ursprung des KOS)
        phi = phi,
        I_eta = 0.5 * (Iy + Iz) + 0.5 * (Iy - Iz) * math.cos(2 * phi) + Iyz * math.sin(2 * phi),
        I_zeta = 0.5 * (Iy + Iz) - 0.5 * (Iy - Iz) * math.cos(2 * phi) - Iyz * math.sin(2 * phi),
        M_eta = My * c + Mz * sn,
        M_zeta = -My * sn + Mz * c,
        c_eta = cy * c + cz * sn,
        c_zeta = -cy * sn + cz * c,
    }
end

-- "a + b*x1 - c*x2" mit vier gueltigen Stellen; Terme unterhalb der Toleranz entfallen
function sigmaEingabe.lineareForm(konst, terme, tol)
    local t = ""
    if math.abs(konst) > tol then t = string.format("%.4g", konst) end
    for _, tm in ipairs(terme) do
        local k = tm[1]
        if math.abs(k) > (tm[3] or tol) then
            local zahl = string.format("%.4g", math.abs(k))
            if t == "" then t = (k < 0 and "-" or "") .. zahl .. "·" .. tm[2]
            else t = t .. (k < 0 and " - " or " + ") .. zahl .. "·" .. tm[2] end
        end
    end
    return (t == "") and "0" or t
end

-- Nulllinie a + b*x1 + c*x2 = 0 als "x2 = m*x1 + n" (bzw. "x1 = n", wenn c = 0)
function sigmaEingabe.nulllinie(a, b, c, x1, x2, tol_k, tol_n)
    if math.abs(c) > tol_k then
        return x2 .. " = " .. sigmaEingabe.lineareForm(display_length(-a / c), { { -b / c, x1, 1e-12 } }, tol_n)
    elseif math.abs(b) > tol_k then
        return x1 .. " = " .. string.format("%.4g", display_length(-a / b))
    end
    return "keine (σx ist konstant)"
end

function sigmaEingabe.zusatzzeilen(sr)
    local k = sigmaEingabe.kennwerte(sr)
    local a, b = axes()
    local f = unit_factor(length_unit)                -- mm je Laengeneinheit der Anzeige
    local skala = math.max(math.abs(sr.sigma_max or 0), math.abs(sr.sigma_min or 0), math.abs(sr.normal or 0), 1e-9)
    local L = 1
    for _, pt in ipairs({ { sr.max_y, sr.max_z }, { sr.min_y, sr.min_z } }) do
        L = math.max(L, math.abs(pt[1] - sr.ys) + math.abs(pt[2] - sr.zs))
    end
    local tol_s = 1e-9 * skala                        -- MPa
    local tol_k = 1e-9 * skala / L                    -- MPa je mm
    local tol_n = 1e-9 * L / f                        -- Laenge in Anzeigeeinheit
    local eh = length_unit
    -- Werte, die nur numerisch von null abweichen, als 0 zeigen (sonst "-0" oder "1e-17")
    local mskala = math.max(math.abs(k.M_eta), math.abs(k.M_zeta), 1e-9)
    if math.abs(k.M_eta) <= 1e-12 * mskala then k.M_eta = 0 end
    if math.abs(k.M_zeta) <= 1e-12 * mskala then k.M_zeta = 0 end
    local zeilen = {
        { kopf = "Hauptachsensystem (HAS, Ursprung im Schwerpunkt)" },
        { "φ* (" .. a .. " → η) [°]", string.format("%.4g°", math.deg(k.phi)) },
        { "I_η = I_1 [" .. unit_label(4) .. "]", string.format("%.6g %s", display_inertia(k.I_eta), unit_label(4)) },
        { "I_ζ = I_2 [" .. unit_label(4) .. "]", string.format("%.6g %s", display_inertia(k.I_zeta), unit_label(4)) },
        { "M_η (um HA 1) [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(k.M_eta), moment_unit) },
        { "M_ζ (um HA 2) [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(k.M_zeta), moment_unit) },
        { kopf = "Biegenormalspannung σx [MPa], Längen in " .. eh },
        { voll = "KOS: σx = " .. sigmaEingabe.lineareForm(k.c0, { { k.cy * f, a, tol_k * f }, { k.cz * f, b, tol_k * f } }, tol_s) },
        { voll = "HAS: σx = " .. sigmaEingabe.lineareForm(k.n0, { { k.c_eta * f, "η", tol_k * f }, { k.c_zeta * f, "ζ", tol_k * f } }, tol_s) },
        { voll = "     = N/A + (M_η/I_η)·ζ - (M_ζ/I_ζ)·η" },
        { kopf = "Neutrale Faser (σx = 0)" },
        { voll = "KOS: " .. sigmaEingabe.nulllinie(k.c0, k.cy, k.cz, a, b, tol_k, tol_n) },
        { voll = "HAS: " .. sigmaEingabe.nulllinie(k.n0, k.c_eta, k.c_zeta, "η", "ζ", tol_k, tol_n) },
    }
    if math.abs(k.ys) > 1e-9 * L or math.abs(k.zs) > 1e-9 * L then
        table.insert(zeilen, 8, { voll = string.format("     (Schwerpunkt im KOS: %s_S = %.4g, %s_S = %.4g)",
            a, display_length(k.ys), b, display_length(k.zs)) })
    end
    return zeilen, k
end

local function drawSigmaResultsTable(gc, w, h)
    if not sigma_results then return end
    local left, top, width = 8, 8 - sigma_scroll_y, math.min(300, w - 16)
    local row_height = 17
    local moment_a, moment_b = axes()
    local max_display_y, max_display_z = coordinatesForDisplay(sigma_results.max_y, sigma_results.max_z)
    local min_display_y, min_display_z = coordinatesForDisplay(sigma_results.min_y, sigma_results.min_z)
    -- Momente und Traegheitsmomente im angezeigten KOS
    local My_d, Mz_d = coordinatesForDisplay(sigma_results.My_Nmm, sigma_results.Mz_Nmm)
    local fMy_d, fMz_d = coordinatesForDisplay(sigma_results.force_Ma_Nmm or 0, sigma_results.force_Mb_Nmm or 0)
    local qMy_d, qMz_d = coordinatesForDisplay(sigma_results.quer_Ma_Nmm or 0, sigma_results.quer_Mb_Nmm or 0)
    local Iy_d, Iz_d, Iyz_d = inertiaForDisplay(sigma_results.Iy, sigma_results.Iz, sigma_results.Iyz)
    local rows = {
        {"N [" .. force_unit .. "]", string.format("%.6g %s", display_force(sigma_results.N), force_unit)},
        {"N aus Kraeften [" .. force_unit .. "]", string.format("%.6g %s", display_force(sigma_results.force_N or 0), force_unit)},
        {"M" .. moment_a .. " [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(My_d), moment_unit)},
        {"M" .. moment_a .. " aus Normalkraeften [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(fMy_d), moment_unit)},
        {"M" .. moment_b .. " [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(Mz_d), moment_unit)},
        {"M" .. moment_b .. " aus Normalkraeften [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(fMz_d), moment_unit)},
        {"A [" .. unit_label(2) .. "]", string.format("%.6g %s", display_area(sigma_results.A), unit_label(2))},
        {"I" .. moment_a .. " [" .. unit_label(4) .. "]", string.format("%.6g %s", display_inertia(Iy_d), unit_label(4))},
        {"I" .. moment_b .. " [" .. unit_label(4) .. "]", string.format("%.6g %s", display_inertia(Iz_d), unit_label(4))},
        {"I" .. moment_a .. moment_b .. " [" .. unit_label(4) .. "]", string.format("%.6g %s", display_inertia(Iyz_d), unit_label(4))},
        {"N/A [MPa]", string.format("%.6g MPa", sigma_results.normal)},
        {"σx,max [MPa]", string.format("%.6g MPa", sigma_results.sigma_max)},
        {"bei (y,z) [" .. unit_label(1) .. "]", string.format("(%.6g, %.6g) %s", display_length(max_display_y), display_length(max_display_z), length_unit)},
        {"σx,min [MPa]", string.format("%.6g MPa", sigma_results.sigma_min)},
        {"bei (y,z) [" .. unit_label(1) .. "]", string.format("(%.6g, %.6g) %s", display_length(min_display_y), display_length(min_display_z), length_unit)}
    }
    if sigma_results.mit_querkraft or (sigma_results.versatz or 0) > 0 then
        -- Querkraftanteil: My = -Δx Fz, Mz = Δx Fy, nach den Normalkraftzeilen eingefuegt
        local achse = sigmaEingabe.stabachse()
        table.insert(rows, 7, {"Δ" .. achse .. " Kraftebene [" .. unit_label(1) .. "]", string.format("%.6g %s", display_length(sigma_results.versatz or 0), length_unit)})
        table.insert(rows, 8, {"M" .. moment_a .. " aus Querkraeften [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(qMy_d), moment_unit)})
        table.insert(rows, 9, {"M" .. moment_b .. " aus Querkraeften [" .. moment_unit .. "]", string.format("%.6g %s", display_moment(qMz_d), moment_unit)})
    end
    for _, zeile in ipairs(sigmaEingabe.zusatzzeilen(sigma_results)) do rows[#rows + 1] = zeile end
    if qsWerte.aktiv() then table.insert(rows, 1, { kopf = "Manuelle Werte: " .. qsWerte.namen() }) end
    local height = (2 + #rows) * row_height + 8
    -- Wertespalte hinter die breiteste Beschriftung setzen (Schrift 8); die breitesten Werte muessen
    -- aber noch daneben passen. Was dann immer noch zu breit ist, wird kleiner geschrieben.
    gc:setFont("sansserif", "r", 8)
    local label_max, value_max = 0, 0
    for _, row in ipairs(rows) do
        if not row.kopf and not row.voll then
            label_max = math.max(label_max, gc:getStringWidth(row[1]))
            value_max = math.max(value_max, gc:getStringWidth(row[2]))
        end
    end
    local split = left + math.max(60, math.min(label_max + 10, width - value_max - 10))
    -- Hoehe fuer das Scrollen mit den Pfeiltasten merken
    sigmaEingabe.tabellenHoehe = height
    sigmaEingabe.inhaltHoehe = height + 8
    -- Text in die verfuegbare Breite bringen: Schrift 8, notfalls 7 oder 6
    local function schreibe(text, x, y, platz)
        for _, g in ipairs({ 8, 7, 6 }) do
            gc:setFont("sansserif", "r", g)
            if gc:getStringWidth(text) <= platz then break end
        end
        gc:drawString(text, x, y)
        gc:setFont("sansserif", "r", 8)
    end

    local viewport_top, viewport_bottom = 0, math.max(0, h - 24)
    local visible_top = math.max(top, viewport_top)
    local visible_bottom = math.min(top + height, viewport_bottom)
    if visible_bottom <= visible_top then return end

    gc:clipRect("set", 0, viewport_top, w, viewport_bottom - viewport_top)
    gc:setColorRGB(248, 248, 248)
    gc:fillRect(left, visible_top, width, visible_bottom - visible_top)
    gc:setColorRGB(0, 0, 0)
    if top >= viewport_top and top + height <= viewport_bottom then
        gc:drawRect(left, top, width, height)
    end
    gc:setFont("sansserif", "b", 10)
    if top + 4 >= viewport_top and top + 4 <= viewport_bottom then
        gc:drawString("σx Ergebnis", left + 6, top + 4)
    end
    gc:setFont("sansserif", "r", 8)
    local header_bottom = top + row_height + 8
    if header_bottom >= viewport_top and header_bottom <= viewport_bottom then
        gc:drawLine(left, header_bottom, left + width, header_bottom)
    end
    for i, row in ipairs(rows) do
        local y = top + row_height + 8 + i * row_height
        if y >= viewport_top and y <= viewport_bottom then
            gc:drawLine(left, y, left + width, y)
        end
        if row.kopf then
            -- Abschnittsueberschrift ueber die ganze Breite
            gc:setColorRGB(232, 238, 248)
            gc:fillRect(left + 1, y - row_height + 1, width - 1, row_height - 1)
            gc:setColorRGB(20, 60, 130)
            gc:setFont("sansserif", "b", 8)
            if y - 12 >= viewport_top and y - 12 <= viewport_bottom then gc:drawString(row.kopf, left + 4, y - 12) end
            gc:setFont("sansserif", "r", 8)
            gc:setColorRGB(0, 0, 0)
        elseif row.voll then
            if y - 12 >= viewport_top and y - 12 <= viewport_bottom then schreibe(row.voll, left + 4, y - 12, width - 8) end
        else
            gc:drawLine(split, math.max(y - row_height, visible_top), split, math.min(y, visible_bottom))
            if y - 12 >= viewport_top and y - 12 <= viewport_bottom then
                schreibe(row[1], left + 4, y - 12, split - left - 7)
                schreibe(row[2], split + 4, y - 12, left + width - split - 7)
            end
        end
    end
    gc:clipRect("reset")
end

local function drawSigmaCrossSection(gc, w, h)
    if not sigma_results then return end

    local r = sigma_results
    local min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
    for _, elem in ipairs(massiv_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    for _, elem in ipairs(duenn_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    if min_u == math.huge then return end

    local left, top = 8, 8
    local width, height = math.max(120, w - 16), math.max(180, h - 28)
    local section_panel_width = math.max(120, math.floor(width * 0.56))
    local graph_left = left + section_panel_width + 6
    local graph_width = width - section_panel_width - 6
    local margin = 24
    local draw_left, draw_top = left + margin, top + 28
    local draw_width = section_panel_width - 2 * margin
    local draw_height = height - 48
    local span_u = math.max(max_u - min_u, 1e-9)
    local span_v = math.max(max_v - min_v, 1e-9)
    local factor = math.min(draw_width / span_u, draw_height / span_v)
    local section_width, section_height = span_u * factor, span_v * factor
    local section_left = draw_left + (draw_width - section_width) / 2
    local section_top = draw_top + (draw_height - section_height) / 2
    local columns, rows = 28, 22
    local cell_width, cell_height = section_width / columns, section_height / rows
    local denominator = r.Iy * r.Iz - r.Iyz^2

    local function screen(u, v)
        return section_left + (u - min_u) * factor, section_top + (max_v - v) * factor
    end
    local function stress(u, v)
        return r.normal
            + ((r.My_Nmm * r.Iz - r.Mz_Nmm * r.Iyz) / denominator) * (v - r.zs)
            - ((r.Mz_Nmm * r.Iy - r.My_Nmm * r.Iyz) / denominator) * (u - r.ys)
    end
    local stress_scale = math.max(math.abs(r.sigma_min), math.abs(r.sigma_max), 1e-9)
    local function color(value)
        local ratio = math.min(1, math.abs(value) / stress_scale)
        if value < -1e-9 then
            return 255 - math.floor(45 * ratio), 225 - math.floor(70 * ratio), 225 - math.floor(65 * ratio)
        elseif value > 1e-9 then
            return 220 - math.floor(70 * ratio), 235 - math.floor(55 * ratio), 255
        end
        return 248, 248, 248
    end

    gc:setColorRGB(248, 248, 248)
    gc:fillRect(left, top, width, height)
    gc:setColorRGB(0, 0, 0)
    gc:drawRect(left, top, width, height)
    gc:setFont("sansserif", "b", 10)
    gc:drawString("σx im Querschnitt", left + 8, top + 5)
    gc:setFont("sansserif", "r", 8)
    gc:drawString("Druck", left + 8, top + 19)
    gc:setColorRGB(235, 175, 175)
    gc:fillRect(left + 39, top + 13, 9, 8)
    gc:setColorRGB(0, 0, 0)
    gc:drawString("Zug", left + 56, top + 19)
    gc:setColorRGB(185, 210, 245)
    gc:fillRect(left + 76, top + 13, 9, 8)
    gc:setColorRGB(0, 0, 0)

    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local u = min_u + (column + 0.5) * span_u / columns
            local v = max_v - (row + 0.5) * span_v / rows
            local inside = false
            for _, elem in ipairs(massiv_elemente) do
                if is_point_inside(elem, u, v) then
                    inside = not elem.is_hole
                end
            end
            if inside then
                local sr, sg, sb = color(stress(u, v))
                gc:setColorRGB(sr, sg, sb)
                gc:fillRect(section_left + column * cell_width, section_top + row * cell_height, cell_width + 1, cell_height + 1)
            end
        end
    end

    local slope_u = -((r.Mz_Nmm * r.Iy - r.My_Nmm * r.Iyz) / denominator)
    local slope_v = (r.My_Nmm * r.Iz - r.Mz_Nmm * r.Iyz) / denominator
    local neutral_offset = r.normal
    local neutral_length = math.sqrt(draw_width^2 + draw_height^2) / math.max(factor, 1e-9)
    local neutral_norm = math.sqrt(slope_u^2 + slope_v^2)
    if neutral_norm > 1e-12 then
        local dir_u, dir_v = -slope_v / neutral_norm, slope_u / neutral_norm
        local base_u = r.ys - slope_u * neutral_offset / (neutral_norm^2)
        local base_v = r.zs - slope_v * neutral_offset / (neutral_norm^2)
        local nu1, nv1 = base_u - dir_u * neutral_length, base_v - dir_v * neutral_length
        local nu2, nv2 = base_u + dir_u * neutral_length, base_v + dir_v * neutral_length
        local sx1, sy1 = screen(nu1, nv1)
        local sx2, sy2 = screen(nu2, nv2)
        gc:setColorRGB(25, 25, 25)
        gc:setPen("medium", "dashed")
        gc:drawLine(sx1, sy1, sx2, sy2)
        gc:setFont("sansserif", "r", 8)
        gc:drawString("neutrale Faser", section_left + 4, section_top + 2)

        local function draw_parallel(point_u, point_v, red, green, blue)
            local line_length = neutral_length * 0.28
            local px1, py1 = screen(point_u - dir_u * line_length, point_v - dir_v * line_length)
            local px2, py2 = screen(point_u + dir_u * line_length, point_v + dir_v * line_length)
            gc:setColorRGB(red, green, blue)
            gc:setPen("thin", "smooth")
            gc:drawLine(px1, py1, px2, py2)
        end
        draw_parallel(r.max_y, r.max_z, 190, 60, 60)
        draw_parallel(r.min_y, r.min_z, 55, 105, 190)
    end

    local cx, cy = screen(r.ys, r.zs)
    local axis_length = math.min(draw_width, draw_height) * 0.42
    local function draw_axis(angle, label)
        local dx, dy = math.cos(angle), math.sin(angle)
        local ax1, ay1 = screen(r.ys - dx * axis_length / factor, r.zs - dy * axis_length / factor)
        local ax2, ay2 = screen(r.ys + dx * axis_length / factor, r.zs + dy * axis_length / factor)
        gc:setColorRGB(110, 80, 160)
        gc:setPen("thin", "dashed")
        gc:drawLine(ax1, ay1, ax2, ay2)
        gc:setFont("sansserif", "r", 8)
        gc:drawString(label, ax2 + 3, ay2 - 8)
    end
    draw_axis(r.alpha, "eta")
    draw_axis(r.alpha + math.pi / 2, "zeta")
    gc:setColorRGB(110, 80, 160)
    gc:fillArc(cx - 3, cy - 3, 6, 6, 0, 360)

    gc:setColorRGB(0, 0, 0)
    gc:setPen("thin", "smooth")
    for _, elem in ipairs(duenn_elemente) do
        local x1, y1 = screen(elem.points[1].u, elem.points[1].v)
        local x2, y2 = screen(elem.points[2].u, elem.points[2].v)
        gc:drawLine(x1, y1, x2, y2)
    end
    gc:setFont("sansserif", "r", 8)
    gc:drawString(string.format("min %.3g", r.sigma_min), left + 8, top + height - 18)

    local graph_top = top + 30
    local graph_bottom = top + height - 24
    if graph_width > 70 then
        local plot_left, plot_right = graph_left + 22, left + width - 8
        local plot_top, plot_bottom = graph_top + 22, graph_bottom - 18
        local sigma_low = math.min(0, r.sigma_min)
        local sigma_high = math.max(0, r.sigma_max)
        local sigma_span = math.max(sigma_high - sigma_low, 1e-9)
        local function graph_y(value)
            return plot_bottom - (value - sigma_low) / sigma_span * (plot_bottom - plot_top)
        end
        gc:setColorRGB(0, 0, 0)
        gc:setPen("thin", "smooth")
        gc:drawRect(graph_left, graph_top, graph_width, graph_bottom - graph_top)
        gc:setFont("sansserif", "b", 9)
        gc:drawString("Spannungsverlauf", graph_left + 4, graph_top + 4)
        gc:setFont("sansserif", "r", 7)
        gc:drawString("σ [MPa]", graph_left + 3, plot_top - 8)
        local zero_y = graph_y(0)
        gc:setColorRGB(130, 130, 130)
        gc:drawLine(plot_left, zero_y, plot_right, zero_y)
        gc:setColorRGB(205, 125, 125)
        gc:drawLine(plot_left, graph_y(r.sigma_min), plot_right, graph_y(r.sigma_max))
        gc:setColorRGB(40, 90, 170)
        gc:setPen("medium", "smooth")
        gc:drawLine(plot_left, graph_y(r.sigma_min), plot_right, graph_y(r.sigma_max))
        gc:setColorRGB(0, 0, 0)
        gc:setFont("sansserif", "r", 7)
        gc:drawString(string.format("min %.3g", r.sigma_min), plot_left, plot_bottom + 4)
        gc:drawString(string.format("max %.3g", r.sigma_max), plot_left, plot_top + 2)
        if r.sigma_min <= 0 and r.sigma_max >= 0 then
            gc:setColorRGB(40, 40, 40)
            gc:setPen("thin", "dashed")
            local neutral_x = plot_left + (0 - r.sigma_min) / sigma_span * (plot_right - plot_left)
            gc:drawLine(neutral_x, plot_top, neutral_x, plot_bottom)
        end
    end
end

local function drawSigmaOverlay(gc, w, h)
    if not sigma_results then return end
    local r = sigma_results
    local denominator = r.Iy * r.Iz - r.Iyz^2
    if math.abs(denominator) < 1e-12 then return end

    local min_u, max_u, min_v, max_v = math.huge, -math.huge, math.huge, -math.huge
    for _, elem in ipairs(massiv_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    for _, elem in ipairs(duenn_elemente) do
        local u1, u2, v1, v2 = getBoundingBox(elem)
        min_u, max_u = math.min(min_u, u1), math.max(max_u, u2)
        min_v, max_v = math.min(min_v, v1), math.max(max_v, v2)
    end
    if min_u == math.huge then return end

    local slope_u = -((r.Mz_Nmm * r.Iy - r.My_Nmm * r.Iyz) / denominator)
    local slope_v = (r.My_Nmm * r.Iz - r.Mz_Nmm * r.Iyz) / denominator
    local function stress(u, v)
        return r.normal + slope_u * (u - r.ys) + slope_v * (v - r.zs)
    end
    local stress_scale = math.max(math.abs(r.sigma_min), math.abs(r.sigma_max), 1e-9)
    local function stress_color(value)
        local ratio = math.min(1, math.abs(value) / stress_scale)
        if value < -1e-9 then
            return 255 - math.floor(45 * ratio), 225 - math.floor(70 * ratio), 225 - math.floor(65 * ratio)
        elseif value > 1e-9 then
            return 220 - math.floor(70 * ratio), 235 - math.floor(55 * ratio), 255
        end
        return 248, 248, 248
    end

    local span_u = math.max(max_u - min_u, 1e-9)
    local span_v = math.max(max_v - min_v, 1e-9)
    local columns = math.max(12, math.min(60, math.floor(span_u * scale / 8)))
    local rows = math.max(12, math.min(60, math.floor(span_v * scale / 8)))
    local du, dv = span_u / columns, span_v / rows

    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local u = min_u + (column + 0.5) * du
            local v = min_v + (row + 0.5) * dv
            local section_state = 0
            for _, elem in ipairs(massiv_elemente) do
                if is_point_inside(elem, u, v) then
                    section_state = elem.is_hole and -1 or 1
                end
            end
            if section_state ~= 0 then
                local x1, y1 = toScreen(min_u + column * du, min_v + row * dv)
                local x2, y2 = toScreen(min_u + (column + 1) * du, min_v + (row + 1) * dv)
                local sr, sg, sb = 255, 255, 255
                if section_state > 0 then sr, sg, sb = stress_color(stress(u, v)) end
                gc:setColorRGB(sr, sg, sb)
                gc:fillRect(math.min(x1, x2), math.min(y1, y2), math.abs(x2 - x1) + 1, math.abs(y2 - y1) + 1)
            end
        end
    end

    gc:setColorRGB(40, 40, 40)
    gc:setPen("thin", "smooth")
    local function point(u, v) return toScreen(u, v) end
    local function line(u1, v1, u2, v2)
        local x1, y1 = point(u1, v1)
        local x2, y2 = point(u2, v2)
        gc:drawLine(x1, y1, x2, y2)
    end
    for _, elem in ipairs(massiv_elemente) do
        local p = elem.points
        if elem.type == "rect" then
            line(p[1].u, p[1].v, p[2].u, p[1].v)
            line(p[2].u, p[1].v, p[2].u, p[2].v)
            line(p[2].u, p[2].v, p[1].u, p[2].v)
            line(p[1].u, p[2].v, p[1].u, p[1].v)
        elseif elem.type == "circle" then
            local cx, cy = point(p[1].u, p[1].v)
            local rpx = math.sqrt((p[2].u - p[1].u)^2 + (p[2].v - p[1].v)^2) * scale
            gc:drawArc(cx - rpx, cy - rpx, 2 * rpx, 2 * rpx, 0, 360)
        elseif elem.type == "triangle" or elem.type == "trapezoid" then
            local q = {}
            for _, pt in ipairs(p) do
                local x, y = point(pt.u, pt.v)
                table.insert(q, x); table.insert(q, y)
            end
            table.insert(q, q[1]); table.insert(q, q[2])
            gc:drawPolyLine(q)
        end
    end
    for _, elem in ipairs(duenn_elemente) do
        local pts = duennKurve.punkte(elem)
        for k = 1, #pts - 1 do line(pts[k].u, pts[k].v, pts[k + 1].u, pts[k + 1].v) end
    end

    local neutral_norm = math.sqrt(slope_u^2 + slope_v^2)
    if neutral_norm <= 1e-12 then return end
    local dir_u, dir_v = -slope_v / neutral_norm, slope_u / neutral_norm
    local stress_dir_u, stress_dir_v = slope_u / neutral_norm, slope_v / neutral_norm
    local line_length = math.sqrt(span_u^2 + span_v^2) * 1.15
    local base_u = r.ys - slope_u * r.normal / (neutral_norm^2)
    local base_v = r.zs - slope_v * r.normal / (neutral_norm^2)

    local profile_offset = line_length
    local zero_profile_u = base_u + dir_u * profile_offset
    local zero_profile_v = base_v + dir_v * profile_offset

    local function cross2(au, av, bu, bv) return au * bv - av * bu end
    local function intersect_lines(pu, pv, du, dv, qu, qv, eu, ev)
        local denominator_lines = cross2(du, dv, eu, ev)
        if math.abs(denominator_lines) < 1e-12 then return pu, pv end
        local delta_u, delta_v = qu - pu, qv - pv
        local t = cross2(delta_u, delta_v, eu, ev) / denominator_lines
        return pu + t * du, pv + t * dv
    end

    local graph_slope = 0.45
    local graph_dir_u = stress_dir_u + graph_slope * dir_u
    local graph_dir_v = stress_dir_v + graph_slope * dir_v
    local min_graph_u, min_graph_v = intersect_lines(
        r.min_y, r.min_z, dir_u, dir_v,
        zero_profile_u, zero_profile_v, graph_dir_u, graph_dir_v)
    local max_graph_u, max_graph_v = intersect_lines(
        r.max_y, r.max_z, dir_u, dir_v,
        zero_profile_u, zero_profile_v, graph_dir_u, graph_dir_v)
    local min_axis_u, min_axis_v = intersect_lines(
        r.min_y, r.min_z, dir_u, dir_v,
        zero_profile_u, zero_profile_v, stress_dir_u, stress_dir_v)
    local max_axis_u, max_axis_v = intersect_lines(
        r.max_y, r.max_z, dir_u, dir_v,
        zero_profile_u, zero_profile_v, stress_dir_u, stress_dir_v)

    gc:setColorRGB(40, 40, 40)
    gc:setPen("thin", "dashed")
    line(base_u - dir_u * line_length, base_v - dir_v * line_length,
        zero_profile_u, zero_profile_v)

    -- Abszisse und Verlauf enden exakt an den beiden aeusseren Geraden.
    gc:setColorRGB(90, 90, 90)
    gc:setPen("thin", "smooth")
    line(min_axis_u, min_axis_v, max_axis_u, max_axis_v)
    gc:setPen("thin", "dashed")
    line(r.min_y, r.min_z, min_graph_u, min_graph_v)
    line(r.max_y, r.max_z, max_graph_u, max_graph_v)

    gc:setColorRGB(30, 30, 30)
    gc:setPen("medium", "smooth")
    line(min_graph_u, min_graph_v, max_graph_u, max_graph_v)

    local max_x, max_y = point(max_graph_u, max_graph_v)
    local min_x, min_y = point(min_graph_u, min_graph_v)
    local min_red, min_green, min_blue = 55, 105, 190
    if r.sigma_min < 0 then min_red, min_green, min_blue = 190, 70, 70 end
    gc:setColorRGB(min_red, min_green, min_blue)
    gc:fillArc(min_x - 2, min_y - 2, 4, 4, 0, 360)
    local max_red, max_green, max_blue = 55, 105, 190
    if r.sigma_max < 0 then max_red, max_green, max_blue = 190, 70, 70 end
    gc:setColorRGB(max_red, max_green, max_blue)
    gc:fillArc(max_x - 2, max_y - 2, 4, 4, 0, 360)
    gc:setFont("sansserif", "r", 8)
    gc:drawString(string.format("σmin %.3g", r.sigma_min), min_x + 4, min_y + 4)
    gc:drawString(string.format("σmax %.3g", r.sigma_max), max_x + 4, max_y - 10)
end

local function drawSigmaExtrema(gc)
    if not sigma_results then return end
    local extrema = {
        {y = sigma_results.max_y, z = sigma_results.max_z, color = {55, 105, 190}},
        {y = sigma_results.min_y, z = sigma_results.min_z, color = {210, 0, 0}}
    }
    for _, point in ipairs(extrema) do
        local sx, sy = toScreen(point.y, point.z)
        gc:setColorRGB(point.color[1], point.color[2], point.color[3])
        gc:fillArc(sx - 2, sy - 2, 4, 4, 0, 360)
    end
end

local function buildMenuItems()
    if menuPage == 1 then
        return {"1. Rechteck (2 Klicks)", "2. Kreis (2 Klicks)", "3. Dreieck (3 Klicks)", "4. Viereck/Trapez (4 Klicks)", "5. Kreisausschnitt (3 Klicks)", "6. Kreisabschnitt (3 Klicks)", "7. Dicke Linie (2 Klicks)", "8. Kraft platzieren (1 Klick)", "9. Naechste Seite >"}
    elseif menuPage == 2 then
        return {"1. Linienzug (n Klicks)", "2. Kreis (2 Klicks)", "3. Kreisbogen (3 Klicks)", "4. Kraft platzieren (1 Klick)", "5. < Vorherige Seite"}
    elseif menuPage == 4 then
        local a, b = axes()
        local format_name = zahlenFormat == 1 and "Wurzel/Bruch" or zahlenFormat == 2 and "Bruch" or "Dezimal"
        return {"1. Raster aendern (Aktuell: "..string.format("%.4g %s", display_length(raster), length_unit)..")", "2. Standarddicke t (Aktuell: "..string.format("%.4g %s", display_length(default_t), length_unit)..")", "3. KOS Ebene ("..a..b..")", "4. KOS drehen", "5. KOS Groesse (Aktuell: "..kos_size..")", "6. Zahlenformat ("..format_name..")", "7. Kraft-Einheit ("..force_unit..")", "8. Laengen-Einheit ("..length_unit..")", "9. Moment-Einheit ("..moment_unit..")", "10. ξ Profilbeiwert (Aktuell: "..string.format("%.4g", torsion_xi)..")"}
    elseif menuPage == 10 then
        local a, b = axes()
        local r = system_results
        local fA, fa, fb, fab, fS = qsWerte.anzeige()
        local tA, ta, tb, tab, tys, tzs = "-", "-", "-", "-", "-", "-"
        if r then
            local ys_d, zs_d = coordinatesForDisplay(r.ys, r.zs)
            tys = string.format("%.6g %s", display_length(ys_d), length_unit)
            tzs = string.format("%.6g %s", display_length(zs_d), length_unit)
            local Ia, Ib, Iab = inertiaForDisplay(r.Iy, r.Iz, r.Iyz)
            tA = string.format("%.6g %s", display_area(r.A), unit_label(2))
            ta = string.format("%.6g %s", display_inertia(Ia), unit_label(4))
            tb = string.format("%.6g %s", display_inertia(Ib), unit_label(4))
            tab = string.format("%.6g %s", display_inertia(Iab), unit_label(4))
        end
        local function m(f) return f and ", manuell" or "" end
        return {"1. A setzen (Aktuell: " .. tA .. m(fA) .. ")",
                "2. I_" .. a .. ",S setzen (Aktuell: " .. ta .. m(fa) .. ")",
                "3. I_" .. b .. ",S setzen (Aktuell: " .. tb .. m(fb) .. ")",
                "4. I_" .. a .. b .. ",S setzen (Aktuell: " .. tab .. m(fab) .. ")",
                "5. " .. a .. "_S setzen (Aktuell: " .. tys .. m(fS) .. ")",
                "6. " .. b .. "_S setzen (Aktuell: " .. tzs .. m(fS) .. ")",
                "7. Berechnete Werte wiederherstellen",
                "8. < Zurueck"}
    elseif menuPage == 9 then
        local a, b = axes()
        return {"1. KOS in Schwerpunkt verschieben",
                "2. KOS entlang " .. a .. " verschieben (Δ" .. a .. " in " .. length_unit .. ": Eingabe)",
                "3. KOS entlang " .. b .. " verschieben (Δ" .. b .. " in " .. length_unit .. ": Eingabe)",
                "4. FTM-Bezug (" .. (ftm_bezug == "kos" and "KOS-Ursprung" or "Schwerpunkt") .. ")",
                "5. Rasterpunkte (" .. ((rasterPunkte == 0) and "Keine" or ((rasterPunkte == 2) and "Dick" or "Normal")) .. ")",
                "6. < Zurueck"}
    elseif menuPage == 5 then
        return {"1. Querschnittswerte", "2. Einzelwerte-Tabelle", "3. σx-Berechnung", "4. Kernflaeche", "5. Schubspannung", "6. Schubmittelpunkt", "7. Verwölbung", "8. Schliessen"}
    elseif menuPage == 8 then
        return {"1. Äussere Belastungen hinzufügen", "2. Schliessen"}
    elseif menuPage == 6 then
        return {"1. Umhuellende Geraden", "2. Kernflaeche", "3. Ausblenden", "4. Zurueck"}
    end

    local elem = selected_type == "massiv" and massiv_elemente[selected_idx] or selected_type == "duenn" and duenn_elemente[selected_idx] or kraefte[selected_idx]
    if not elem then return {} end
    local a_lbl, b_lbl = axes()
    local items = {}
    if selected_type == "kraft" then
        local c_lbl = (a_lbl == "x" and b_lbl == "y") and "z" or ((a_lbl == "y" and b_lbl == "z") and "x" or "y")
        local display_u, display_v = coordinatesForDisplay(elem.u, elem.v)
        local force_a, force_b = forceComponentsForDisplay(elem.fa, elem.fb)
        items = {"--- Bearbeite Kraft " .. selected_idx .. " ---", a_lbl .. " [" .. length_unit .. "]: " .. string.format("%.3f", display_length(display_u)), b_lbl .. " [" .. length_unit .. "]: " .. string.format("%.3f", display_length(display_v)), "F_" .. a_lbl .. " [" .. force_unit .. "]: " .. string.format("%.3f", display_force(force_a)), "F_" .. b_lbl .. " [" .. force_unit .. "]: " .. string.format("%.3f", display_force(force_b)), "F_" .. c_lbl .. " [" .. force_unit .. "]: " .. string.format("%.3f", display_force(elem.fc)), "Loeschen"}
        return items
    end
    items[1] = "--- Bearbeite " .. (selected_type == "massiv" and "M" or "D") .. selected_idx .. " ---"
    for i = 1, #elem.points do
        local display_u, display_v = coordinatesForDisplay(elem.points[i].u, elem.points[i].v)
        table.insert(items, "P" .. i .. " " .. a_lbl .. " [" .. length_unit .. "]: " .. string.format("%.3f", display_length(display_u)))
        table.insert(items, "P" .. i .. " " .. b_lbl .. " [" .. length_unit .. "]: " .. string.format("%.3f", display_length(display_v)))
    end
    if selected_type == "massiv" then
        table.insert(items, "Typ: " .. (elem.is_hole and "Loch" or "Positiv"))
        if elem.type == "massiv_linie" then table.insert(items, "Dicke t [" .. length_unit .. "]: " .. string.format("%.3f", display_length(elem.t))); elem.has_t = true end
    else
        table.insert(items, "Dicke t [" .. length_unit .. "]: " .. string.format("%.3f", display_length(elem.t)))
    end
    if elem.type == "sector" or elem.type == "segment" or elem.type == "duenn_kreis_bogen" then
        table.insert(items, "P2 und P3 tauschen"); elem.has_swap = true
    else
        elem.has_swap = false
    end
    table.insert(items, "Element Loeschen")
    table.insert(items, "Schliessen")
    return items
end

local function drawMenu(gc, w, h)
    if not menuOpen then return end
    local width, left = 220, 5   -- Menues stehen links
    gc:setColorRGB(248, 248, 248); gc:fillRect(left, 5, width, h - 10)
    gc:setColorRGB(0, 0, 0); gc:drawRect(left, 5, width, h - 10)
    gc:setFont("sansserif", "b", 9)
    local title = "Menue (" .. (menuPage == 1 and "Massiv" or menuPage == 2 and "Duennwand" or menuPage == 3 and "Editieren" or menuPage == 5 and "Berechnungen" or menuPage == 6 and "Kernflaeche" or menuPage == 8 and "Schubspannung" or menuPage == 9 and "Weitere Optionen" or menuPage == 10 and "Querschnittswerte" or "Optionen") .. ")"
    gc:drawString(title, left + 5, 10)
    gc:setFont("sansserif", "r", 9)
    for i, row in ipairs(buildMenuItems()) do
        gc:setColorRGB(i == menuRow and 200 or 0, 0, 0)
        local text = row
        if inputMode and i == menuRow then text = row:match("^(.-):") .. ": " .. inputText .. "_" end
        gc:drawString(text, left + 5, 15 + i * 16)
    end
end

local function drawOverlapPrompt(gc, w, h)
    if mode ~= "overlap_prompt" then return end
    local width, height = 270, 92
    local left, top = (w - width) / 2, (h - height) / 2
    gc:setColorRGB(255, 248, 220)
    gc:fillRect(left, top, width, height)
    gc:setColorRGB(180, 90, 0)
    gc:setPen("medium", "smooth")
    gc:drawRect(left, top, width, height)
    gc:setColorRGB(120, 50, 0)
    gc:setFont("sansserif", "b", 11)
    gc:drawString("Ueberlappung erkannt", left + 10, top + 8)
    gc:setFont("sansserif", "r", 9)
    gc:drawString("1: Abziehen   2: Addieren   3: Verwerfen", left + 10, top + 34)
    gc:drawString("Taste 1, 2 oder 3 druecken", left + 10, top + 57)
end

local function drawTable(gc, w, h)
    if not showTable then return end
    
    local a_lbl, b_lbl = axes()
    -- Steiner-Anteile und Gesamtwerte wahlweise auf den Schwerpunkt oder auf den KOS-Ursprung
    local bezug_kos = (ftm_bezug == "kos")
    local bezug_kurz = bezug_kos and "KOS" or "S"
    local rows = {
        "Flaecheninhalt A [" .. unit_label(2) .. "]",
        a_lbl .. " [" .. unit_label(1) .. "]",
        b_lbl .. " [" .. unit_label(1) .. "]",
        "I_eta (Lokal) [" .. unit_label(4) .. "]",
        "I_zeta (Lokal) [" .. unit_label(4) .. "]",
        "I_etazeta (Lokal) [" .. unit_label(4) .. "]",
        "I_" .. a_lbl .. " (Gedreht) [" .. unit_label(4) .. "]",
        "I_" .. b_lbl .. " (Gedreht) [" .. unit_label(4) .. "]",
        "I_" .. a_lbl .. b_lbl .. " (Gedreht) [" .. unit_label(4) .. "]",
        b_lbl .. "^2 * A (Steiner zu " .. bezug_kurz .. ") [" .. unit_label(4) .. "]",
        a_lbl .. "^2 * A (Steiner zu " .. bezug_kurz .. ") [" .. unit_label(4) .. "]",
        a_lbl .. "*" .. b_lbl .. "*A (Steiner zu " .. bezug_kurz .. ") [" .. unit_label(4) .. "]",
        "I_" .. a_lbl .. " (" .. bezug_kurz .. ") [" .. unit_label(4) .. "]",
        "I_" .. b_lbl .. " (" .. bezug_kurz .. ") [" .. unit_label(4) .. "]",
        "I_" .. a_lbl .. b_lbl .. " (" .. bezug_kurz .. ") [" .. unit_label(4) .. "]"
    }
    
    local all_elems = {}
    for _, e in ipairs(massiv_elemente) do table.insert(all_elems, e) end
    for _, e in ipairs(duenn_elemente) do table.insert(all_elems, e) end
    if #all_elems == 0 then return end
    
    local colW = 75
    local rowColW = 140
    local rowH = 20
    
    local totalW = rowColW + #all_elems * colW
    local totalH = (1 + #rows) * rowH
    
    local startX = 10 + table_scroll_x
    local startY = 30 + table_scroll_y
    
    gc:setColorRGB(240, 240, 240)
    gc:fillRect(0, 0, w, h)
    
    gc:setColorRGB(0, 0, 0)
    gc:setFont("sansserif", "b", 9)
    gc:drawString("Tabellarische uebersicht Einzelelemente (Bezug: "
        .. (bezug_kos and "KOS-Ursprung" or "Schwerpunkt") .. ")", 10, 5)
    if qsWerte.aktiv() then
        gc:setFont("sansserif", "r", 8); gc:setColorRGB(200, 90, 0)
        gc:drawString("Manuell: " .. qsWerte.namen() .. " -- die Tabelle zeigt die Werte aus der Geometrie", 10, 16)
        gc:setColorRGB(0, 0, 0); gc:setFont("sansserif", "b", 9)
    end
    
    gc:clipRect("set", 10, 25, w - 20, h - 35)
    
    gc:setColorRGB(0, 0, 0)
    for i = 0, #rows + 1 do
        local y = startY + i * rowH
        gc:drawLine(startX, y, startX + totalW, y)
    end
    for j = 0, #all_elems + 1 do
        local x = startX + (j == 0 and 0 or rowColW + (j-1)*colW)
        gc:drawLine(x, startY, x, startY + totalH)
    end
    
    gc:setFont("sansserif", "r", 8)
    for i, label in ipairs(rows) do
        gc:drawString(label, startX + 5, startY + i * rowH + 2)
    end
    
    for i, elem in ipairs(all_elems) do
        local cx = startX + rowColW + (i-1)*colW
        local title = elem.display_name or ("E" .. i)
        local numeric_color = elem.is_numeric and {210, 0, 0} or {0, 0, 0}
        gc:setColorRGB(numeric_color[1], numeric_color[2], numeric_color[3])
        gc:setFont("sansserif", "b", 9)
        if elem.is_numeric then
            gc:setFont("sansserif", "b", 8)
            gc:drawString("numerisch", cx + 2, startY + 1)
            gc:setFont("sansserif", "b", 9)
            gc:drawString(title, cx + 5, startY + 11)
        else
            gc:drawString(title, cx + 5, startY + 2)
        end
        
        gc:setFont("sansserif", "r", 8)
        local A = elem.A or 0
        local y, z = coordinatesForDisplay(elem.ys or 0, elem.zs or 0)
        local Iy, Iz, Iyz = inertiaForDisplay(elem.Iy or 0, elem.Iz or 0, elem.Iyz or 0)
        local centroid_y, centroid_z = 0, 0
        if system_results then
            local g = qsWerte.geoSicht(system_results)
            centroid_y, centroid_z = coordinatesForDisplay(g.ys, g.zs)
        end
        local delta_y, delta_z = y, z
        if not bezug_kos then delta_y, delta_z = y - centroid_y, z - centroid_z end
        
        local vals = {
            display_area(A), display_length(y), display_length(z),
            display_inertia(elem.I_eta or 0), display_inertia(elem.I_zeta or 0), display_inertia(elem.I_etazeta or 0),
            display_inertia(Iy), display_inertia(Iz), display_inertia(Iyz),
            display_inertia(delta_z^2 * A), display_inertia(delta_y^2 * A), display_inertia(-delta_y * delta_z * A),
            display_inertia(Iy + delta_z^2 * A), display_inertia(Iz + delta_y^2 * A), display_inertia(Iyz - delta_y * delta_z * A)
        }
        
        for i, val in ipairs(vals) do
            local str = string.format("%.2f", val)
            gc:drawString(str, cx + 5, startY + i * rowH + 2)
        end
        gc:setColorRGB(0, 0, 0)
    end
    
    gc:clipRect("reset")
end

local function drawShearMomentTable(gc, w, h)
    if not shear_moment_table then return end
    gc:setColorRGB(255, 255, 255)
    gc:fillRect(0, 0, w, h)
    gc:setColorRGB(0, 0, 0)
    gc:setFont("sansserif", "b", 10)
    gc:drawString("Schubmittelpunkt: Resultierende Schubkraefte", 8, 8)
    gc:setFont("sansserif", "r", 9)
    local axis_a, axis_b = axes()
    gc:drawString("Einheitslast " .. axis_a .. " / " .. axis_b .. ", F [" .. force_unit .. "]", 8, 28)
    gc:drawString(axis_a .. "-Last", 35, 44)
    gc:drawString("Hebel", 90, 44)
    gc:drawString(axis_b .. "-Last", 175, 44)
    gc:drawString("Hebel", 235, 44)
    local function formatSignedForce(value)
        local displayed = value / unit_factor(force_unit)
        if displayed ~= 0 and math.abs(displayed) < 0.01 then
            return string.format("%.3e", displayed)
        end
        return formatLabel(displayed)
    end
    local y = 62
    for _, row in ipairs(shear_moment_table.rows) do
        gc:drawString(row.name, 8, y)
        gc:drawString(formatSignedForce(row.first), 35, y)
        gc:drawString(row.arm_first and (formatLabel(display_length(row.arm_first)) .. " " .. length_unit) or "--", 90, y)
        gc:drawString(formatSignedForce(row.second), 175, y)
        gc:drawString(row.arm_second and (formatLabel(display_length(row.arm_second)) .. " " .. length_unit) or "--", 235, y)
        y = y + 18
    end
    gc:setFont("sansserif", "b", 9)
    gc:drawString("M_ges", 8, y + 4)
    gc:drawString(formatLabel(shear_moment_table.total_first / unit_factor(moment_unit)) .. " " .. moment_unit, 90, y + 4)
    gc:drawString(formatLabel(shear_moment_table.total_second / unit_factor(moment_unit)) .. " " .. moment_unit, 235, y + 4)
end

-- === KERNFLAECHE (K-Modus) ===
local function kern_dual(nu, nv, d)
    -- Dualitaet: neutrale Faser nu*(y-ys) + nv*(z-zs) = d  ->  Kernpunkt (globale Koordinaten)
    local r = system_results
    local A = r.A
    local Iyzp = -r.Iyz -- Integral (y-ys)*(z-zs) dA (Vorzeichenkonvention beachten)
    local al = -nu / (d * A)
    local be = -nv / (d * A)
    local ky = al * r.Iz + be * Iyzp
    local kz = al * Iyzp + be * r.Iy
    return r.ys + ky, r.zs + kz
end

kern_collect_points = function()
    local pts = {}
    local function add(u, v, src, is_arc)
        table.insert(pts, {u = u, v = v, src = src, arc = is_arc})
    end
    local function arc_samples(C, R, a1, a2, src, full)
        local sweep = a2 - a1
        if sweep <= 0 then sweep = sweep + 2 * math.pi end
        local steps = math.max(4, math.ceil(math.deg(sweep) / 10))
        for i = 0, steps do
            local ang = a1 + sweep * (i / steps)
            local is_end = (i == 0 or i == steps)
            add(C.u + R * math.cos(ang), C.v + R * math.sin(ang), src, full or not is_end)
        end
    end
    for _, elem in ipairs(massiv_elemente) do
        if not elem.is_hole then
            local p = elem.points
            if elem.type == "rect" then
                add(p[1].u, p[1].v); add(p[2].u, p[1].v)
                add(p[2].u, p[2].v); add(p[1].u, p[2].v)
            elseif elem.type == "circle" then
                local R = math.sqrt((p[2].u - p[1].u)^2 + (p[2].v - p[1].v)^2)
                arc_samples(p[1], R, 0, 2 * math.pi, elem, true)
            elseif elem.type == "triangle" or elem.type == "trapezoid" then
                for _, pt in ipairs(p) do add(pt.u, pt.v) end
            elseif elem.type == "massiv_linie" then
                local du, dv = p[2].u - p[1].u, p[2].v - p[1].v
                local L = math.sqrt(du^2 + dv^2)
                local nx, ny = 0, 0
                if L > 1e-9 then nx, ny = (-dv / L) * (elem.t / 2), (du / L) * (elem.t / 2) end
                add(p[1].u + nx, p[1].v + ny); add(p[2].u + nx, p[2].v + ny)
                add(p[2].u - nx, p[2].v - ny); add(p[1].u - nx, p[1].v - ny)
            elseif elem.type == "sector" or elem.type == "segment" then
                local C = p[1]
                local R = math.sqrt((p[2].u - C.u)^2 + (p[2].v - C.v)^2)
                local a1 = math.atan2(p[2].v - C.v, p[2].u - C.u)
                local a2 = math.atan2(p[3].v - C.v, p[3].u - C.u)
                if elem.type == "sector" then add(C.u, C.v) end
                arc_samples(C, R, a1, a2, elem, false)
            end
        end
    end
    for _, elem in ipairs(duenn_elemente) do
        local p = elem.points
        if elem.type == "duenn_kreis" then
            local R = math.sqrt((p[2].u - p[1].u)^2 + (p[2].v - p[1].v)^2)
            arc_samples(p[1], R, 0, 2 * math.pi, elem, true)
        elseif elem.type == "duenn_kreis_bogen" then
            local C = p[1]
            local R = math.sqrt((p[2].u - C.u)^2 + (p[2].v - C.v)^2)
            local a1 = math.atan2(p[2].v - C.v, p[2].u - C.u)
            local a2 = math.atan2(p[3].v - C.v, p[3].u - C.u)
            arc_samples(C, R, a1, a2, elem, false)
        else
            add(p[1].u, p[1].v)
            add(p[2].u, p[2].v)
        end
    end
    return pts
end

local function berechneSigmaExtrema(N, My_Nmm, Mz_Nmm)
    local r = system_results
    if not r then return nil end
    local points = kern_collect_points()
    local denominator = r.Iy * r.Iz - r.Iyz^2
    if math.abs(r.A) < 1e-9 or math.abs(denominator) < 1e-12 or #points == 0 then
        return nil
    end

    local My = My_Nmm
    local Mz = Mz_Nmm
    local normal = N / r.A
    local max_sigma, min_sigma = -math.huge, math.huge
    local max_point, min_point

    for _, point in ipairs(points) do
        local sigma = normal
            + ((My * r.Iz - Mz * r.Iyz) / denominator) * (point.v - r.zs)
            - ((Mz * r.Iy - My * r.Iyz) / denominator) * (point.u - r.ys)
        if sigma > max_sigma then
            max_sigma = sigma
            max_point = point
        end
        if sigma < min_sigma then
            min_sigma = sigma
            min_point = point
        end
    end

    return {
        N = N,
        My_Nmm = My,
        Mz_Nmm = Mz,
        A = r.A,
        ys = r.ys,
        zs = r.zs,
        Iy = r.Iy,
        Iz = r.Iz,
        Iyz = r.Iyz,
        alpha = r.alpha,
        normal = normal,
        sigma_max = max_sigma,
        max_y = max_point.u,
        max_z = max_point.v,
        sigma_min = min_sigma,
        min_y = min_point.u,
        min_z = min_point.v
    }
end

local function berechneKraftResultanten()
    if not system_results then return 0, 0, 0 end
    local force_N, moment_a, moment_b = 0, 0, 0
    local orientation = ({1, 1, -1})[plane]
    if swapped then orientation = -orientation end
    for _, kraft in ipairs(kraefte) do
        local normal_force = tonumber(kraft.fc) or 0
        local du = kraft.u - system_results.ys
        local dv = kraft.v - system_results.zs
        force_N = force_N + normal_force
        moment_a = moment_a + orientation * dv * normal_force
        moment_b = moment_b - orientation * du * normal_force
    end
    return force_N, moment_a, moment_b
end

-- Biegemoment der eingezeichneten Querkraefte, deren Ebene um e entlang der Stabachse vom Schnitt
-- entfernt ist: My = -e Fz, Mz = e Fy (im angezeigten KOS, (y, z, x) rechtshaendig). Intern
-- (u, v wie y, z; Stabachse aus der Bildebene): M_u = -e F_v, M_v = e F_u. Das Ergebnis haengt nur
-- vom Abstand ab, nicht davon, auf welcher Seite des Schnitts die Kraefte angreifen:
--   Kraft am positiven Teil (Normale +x, Abstand +a):  M =  r x F  mit r = ( a, ...)
--   Kraft am negativen Teil (Abstand -a):              M = -r x F  mit r = (-a, ...)
-- In beiden Faellen ist der Querkraftanteil My = -a Fz, Mz = a Fy. Deshalb zaehlt |e|; ein
-- vorzeichenbehaftetes x eingesetzt waere auf einer der beiden Seiten falsch.
function sigmaEingabe.querkraftMomente(e)
    local Mu, Mv = 0, 0
    e = math.abs(e or 0)
    for _, kraft in ipairs(kraefte) do
        Mu = Mu - e * (tonumber(kraft.fb) or 0)
        Mv = Mv + e * (tonumber(kraft.fa) or 0)
    end
    return Mu, Mv
end

local function finishSigmaCalculation(Mz_Nmm)
    local r = system_results
    local denominator = r.Iy * r.Iz - r.Iyz^2
    if math.abs(denominator) < 1e-12 then
        return false
    end
    local force_N, force_Ma, force_Mb = berechneKraftResultanten()
    local quer_Ma, quer_Mb = sigmaEingabe.querkraftMomente(sigmaEingabe.versatz)
    -- Eingegebene Momente beziehen sich auf das angezeigte KOS (y, z): ins interne (u, v) drehen.
    -- Momentenvektoren drehen sich wie Punkte (Drehung um die Stabachse).
    local Mu_in, Mv_in = coordinatesFromDisplay(sigma_My or 0, Mz_Nmm or 0)
    local total_N = (sigma_N or 0) + force_N
    local total_Ma_Nmm = Mu_in + force_Ma + quer_Ma
    local total_Mb_Nmm = Mv_in + force_Mb + quer_Mb
    sigma_results = berechneSigmaExtrema(total_N, total_Ma_Nmm, total_Mb_Nmm)
    if sigma_results then
        sigma_results.force_N = force_N
        sigma_results.force_Ma_Nmm = force_Ma
        sigma_results.force_Mb_Nmm = force_Mb
        sigma_results.quer_Ma_Nmm = quer_Ma
        sigma_results.quer_Mb_Nmm = quer_Mb
        sigma_results.versatz = math.abs(sigmaEingabe.versatz or 0)
        sigma_results.mit_querkraft = sigmaEingabe.hatQuerkraefte()
    end
    return sigma_results ~= nil
end

kern_build = function()
    kern_lines, kern_pts, kern_vertices = {}, {}, {}
    kern_hover_line, kern_hover_pt = nil, nil
    local r = system_results
    if not r then return end
    local pts = kern_collect_points()
    if #pts < 3 then return end

    -- Konvexe Huelle (Monotone Chain), Ergebnis gegen den Uhrzeigersinn
    table.sort(pts, function(a, b)
        if math.abs(a.u - b.u) > 1e-12 then return a.u < b.u end
        return a.v < b.v
    end)
    local function cross(o, a, b) return (a.u - o.u) * (b.v - o.v) - (a.v - o.v) * (b.u - o.u) end
    local lower, upper = {}, {}
    for _, p in ipairs(pts) do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 1e-9 do table.remove(lower) end
        table.insert(lower, p)
    end
    for i = #pts, 1, -1 do
        local p = pts[i]
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 1e-9 do table.remove(upper) end
        table.insert(upper, p)
    end
    table.remove(lower); table.remove(upper)
    local hull = {}
    for _, p in ipairs(lower) do table.insert(hull, p) end
    for _, p in ipairs(upper) do table.insert(hull, p) end
    local n = #hull
    if n < 3 then return end

    local function arc_edge(H, N, i)
        local p1, p2 = H[i], H[(i % N) + 1]
        return p1.arc and p2.arc and p1.src ~= nil and p1.src == p2.src
    end

    -- Sonderfall: Huelle besteht nur aus einem Vollkreis
    local all_arc = true
    for i = 1, n do
        if not arc_edge(hull, n, i) then all_arc = false break end
    end
    if all_arc then
        local C = hull[1].src.points[1]
        local P0 = hull[1].src.points[2]
        local R = math.sqrt((P0.u - C.u)^2 + (P0.v - C.v)^2)
        for k = 0, 35 do
            local ang = 2 * math.pi * k / 36
            local cu, cv = math.cos(ang), math.sin(ang)
            local d = cu * (C.u + R * cu - r.ys) + cv * (C.v + R * cv - r.zs)
            if d > 1e-9 then
                local ku, kv = kern_dual(cu, cv, d)
                table.insert(kern_pts, {u = ku, v = kv})
            end
        end
        return
    end

    -- Huelle rotieren, so dass die erste Kante keine Bogenkante ist
    local start = 1
    for i = 1, n do
        if not arc_edge(hull, n, i) then start = i break end
    end
    local H = {}
    for i = 0, n - 1 do table.insert(H, hull[((start + i - 1) % n) + 1]) end
    hull = H

    -- Segmente bilden: gerade Kanten einzeln, Bogenläufe als ein Segment
    local segs = {}
    local i = 1
    while i <= n do
        if arc_edge(hull, n, i) then
            local j = i
            while j < n and arc_edge(hull, n, j + 1) do j = j + 1 end
            table.insert(segs, {type = "arc", src = hull[i].src, p1 = hull[i], p2 = hull[(j % n) + 1]})
            i = j + 1
        else
            table.insert(segs, {type = "line", p1 = hull[i], p2 = hull[(i % n) + 1]})
            i = i + 1
        end
    end

    -- Kollineare gerade Kanten verschmelzen (minimale Geradenanzahl)
    local changed = true
    while changed and #segs > 1 do
        changed = false
        for k = 1, #segs do
            local s1, s2 = segs[k], segs[(k % #segs) + 1]
            if s1.type == "line" and s2.type == "line" then
                local d1u, d1v = s1.p2.u - s1.p1.u, s1.p2.v - s1.p1.v
                local d2u, d2v = s2.p2.u - s2.p1.u, s2.p2.v - s2.p1.v
                local cr = math.abs(d1u * d2v - d1v * d2u)
                if cr <= 1e-9 * math.sqrt((d1u^2 + d1v^2) * (d2u^2 + d2v^2)) then
                    s1.p2 = s2.p2
                    table.remove(segs, (k % #segs) + 1)
                    changed = true
                    break
                end
            end
        end
    end

    local function add_line(nu, nv, d)
        if d < 0 then nu, nv, d = -nu, -nv, -d end
        if d <= 1e-9 then return end
        table.insert(kern_lines, {nu = nu, nv = nv, d = d})
        local ku, kv = kern_dual(nu, nv, d)
        table.insert(kern_pts, {u = ku, v = kv})
        table.insert(kern_vertices, {u = ku, v = kv})
    end

    for _, sg in ipairs(segs) do
        if sg.type == "line" then
            local du, dv = sg.p2.u - sg.p1.u, sg.p2.v - sg.p1.v
            local L = math.sqrt(du^2 + dv^2)
            if L > 1e-9 then
                -- Huelle ist CCW, also ist (dv, -du) die Aussennormale
                local nu, nv = dv / L, -du / L
                add_line(nu, nv, nu * (sg.p1.u - r.ys) + nv * (sg.p1.v - r.zs))
            end
        else
            local C = sg.src.points[1]
            local P0 = sg.src.points[2]
            local R = math.sqrt((P0.u - C.u)^2 + (P0.v - C.v)^2)
            -- Tangente am Bogenanfang
            local nu = (sg.p1.u - C.u) / R
            local nv = (sg.p1.v - C.v) / R
            add_line(nu, nv, nu * (sg.p1.u - r.ys) + nv * (sg.p1.v - r.zs))
            -- Kernkurve entlang des Bogens (Stuetzpunkte)
            local a1 = math.atan2(sg.p1.v - C.v, sg.p1.u - C.u)
            local a2 = math.atan2(sg.p2.v - C.v, sg.p2.u - C.u)
            if a2 <= a1 then a2 = a2 + 2 * math.pi end
            local steps = math.max(2, math.ceil(math.deg(a2 - a1) / 5))
            for k = 1, steps - 1 do
                local ang = a1 + (a2 - a1) * (k / steps)
                local cu, cv = math.cos(ang), math.sin(ang)
                local d = cu * (C.u + R * cu - r.ys) + cv * (C.v + R * cv - r.zs)
                if d > 1e-9 then
                    local ku, kv = kern_dual(cu, cv, d)
                    table.insert(kern_pts, {u = ku, v = kv})
                end
            end
            -- Tangente am Bogenende
            nu = (sg.p2.u - C.u) / R
            nv = (sg.p2.v - C.v) / R
            add_line(nu, nv, nu * (sg.p2.u - r.ys) + nv * (sg.p2.v - r.zs))
        end
    end
end

local function drawInfArrow(gc, u0, v0, du, dv, label)
    local x1, y1 = toScreen(u0, v0)
    local x2, y2 = toScreen(u0 + du, v0 + dv)
    local dx, dy = x2 - x1, y2 - y1
    local m = math.sqrt(dx^2 + dy^2)
    if m < 1e-5 then return end
    dx, dy = dx / m * 30, dy / m * 30
    gc:drawLine(x1, y1, x1 + dx, y1 + dy)
    local px, py = -dy, dx
    gc:drawLine(x1 + dx, y1 + dy, x1 + dx * 0.8 + px * 0.15, y1 + dy * 0.8 + py * 0.15)
    gc:drawLine(x1 + dx, y1 + dy, x1 + dx * 0.8 - px * 0.15, y1 + dy * 0.8 - py * 0.15)
    gc:drawString(label, x1 + dx + 4, y1 + dy - 8)
end

local function drawKern(gc, w, h)
    local r = system_results
    if not r then return end
    local a_lbl, b_lbl = axes()
    if kernMode == 1 then
        local L = (w + h) / scale
        for i, ln in ipairs(kern_lines) do
            local bu, bv = r.ys + ln.nu * ln.d, r.zs + ln.nv * ln.d
            local du, dv = -ln.nv, ln.nu
            local x1, y1 = toScreen(bu - du * L, bv - dv * L)
            local x2, y2 = toScreen(bu + du * L, bv + dv * L)
            if kern_hover_line == i then
                gc:setColorRGB(0, 90, 220)
                gc:setPen("medium", "smooth")
            else
                gc:setColorRGB(140, 185, 240)
                gc:setPen("thin", "smooth")
            end
            gc:drawLine(x1, y1, x2, y2)
            local lx, ly = toScreen(bu, bv)
            gc:setFont("sansserif", "r", 8)
            gc:drawString("g" .. i, lx + 4, ly - 10)
        end
        local i = kern_hover_line
        if i then
            local ln = kern_lines[i]
            local bu, bv = r.ys + ln.nu * ln.d, r.zs + ln.nv * ln.d
            gc:setColorRGB(220, 40, 40)
            gc:setFont("sansserif", "r", 9)
            -- Achsenabschnitte auf den Hauptachsen, vom Schwerpunkt aus in Richtung der gezeichneten
            -- Achsen 1 (η) und 2 (ζ): damit gilt wie von Hand η_K = -i_ζ²/a_η, ζ_K = -i_η²/a_ζ
            local e1u, e1v, e2u, e2v = kernHAS.richtungen()
            for _, e in ipairs({ { e1u, e1v, "η" }, { e2u, e2v, "ζ" } }) do
                local proj = ln.nu * e[1] + ln.nv * e[2]
                if math.abs(proj) > 1e-9 then
                    local t = ln.d / proj
                    local sx, sy = toScreen(r.ys + t * e[1], r.zs + t * e[2])
                    gc:fillArc(sx - 3, sy - 3, 6, 6, 0, 360)
                    gc:drawString(e[3] .. "=" .. formatLabel(display_length(t)), sx + 6, sy - 12)
                else
                    drawInfArrow(gc, bu, bv, e[1], e[2], "inf")
                end
            end
        end
    elseif kernMode == 2 then
        if #kern_pts >= 2 then
            local q = {}
            for _, p in ipairs(kern_pts) do
                local sx, sy = toScreen(p.u, p.v)
                table.insert(q, sx)
                table.insert(q, sy)
            end
            gc:setColorRGB(250, 205, 205)
            gc:fillPolygon(q)
            table.insert(q, q[1])
            table.insert(q, q[2])
            gc:setColorRGB(200, 40, 40)
            gc:setPen("medium", "smooth")
            gc:drawPolyLine(q)
            for k, p in ipairs(kern_vertices) do
                local sx, sy = toScreen(p.u, p.v)
                if kern_hover_pt == k then
                    gc:setColorRGB(255, 0, 0)
                    gc:fillArc(sx - 4, sy - 4, 8, 8, 0, 360)
                    gc:setFont("sansserif", "b", 9)
                    -- Kernpunkt im gezeichneten KOS und im HAS (η, ζ vom Schwerpunkt aus)
                    local display_u, display_v = coordinatesForDisplay(p.u, p.v)
                    local eta, zeta = kernHAS.koordinaten(p.u, p.v)
                    local z1 = "KOS: " .. a_lbl .. "=" .. formatLabel(display_length(display_u)) .. ", " .. b_lbl .. "=" .. formatLabel(display_length(display_v))
                    local z2 = "HAS: η=" .. formatLabel(display_length(eta)) .. ", ζ=" .. formatLabel(display_length(zeta))
                    local breite = math.max(gc:getStringWidth(z1), gc:getStringWidth(z2))
                    local tx = math.max(2, math.min(sx + 8, w - breite - 2))
                    local ty = math.max(2, sy - 26)
                    gc:drawString(z1, tx, ty)
                    gc:drawString(z2, tx, ty + 12)
                else
                    gc:setColorRGB(150, 30, 30)
                    gc:fillArc(sx - 3, sy - 3, 6, 6, 0, 360)
                end
            end
        end
    end
end

function on.paint(gc)
    local w, h = platform.window:width(), platform.window:height()
    
    if showTable then
        if sigma_results then
            gc:setColorRGB(255, 255, 255)
            gc:fillRect(0, 0, w, h)
            drawSigmaResultsTable(gc, w, h)
        elseif show_shear_moment_table then
            drawShearMomentTable(gc, w, h)
        else
            drawTable(gc, w, h)
        end
        return
    end
    if sigma_input_step > 0 then
        gc:setColorRGB(255, 255, 255)
        gc:fillRect(0, 0, w, h)
        drawSigmaInput(gc, w, h)
        return
    end
    if shear_input_step > 0 then
        gc:setColorRGB(255, 255, 255)
        gc:fillRect(0, 0, w, h)
        drawShearInput(gc, w, h)
        return
    end
    if torsion_input_step > 0 then
        gc:setColorRGB(255, 255, 255); gc:fillRect(0, 0, w, h)
        drawTorsionInput(gc, w, h)
        return
    end
    if woelb.step > 0 then
        gc:setColorRGB(255, 255, 255); gc:fillRect(0, 0, w, h)
        woelb.zeichneDialog(gc, w, h)
        return
    end
    gc:setColorRGB(255, 255, 255)
    gc:fillRect(0, 0, w, h)
    
    drawGrid(gc, w, h)
    
    -- Draw Massiv
    for i, elem in ipairs(massiv_elemente) do
        local is_sel = (selected_type == "massiv" and selected_idx == i)
        local is_hov = (hover_type == "massiv" and hover_idx == i)
        
        if elem.is_hole then
            gc:setColorRGB(255, 255, 255)
            gc:setPen((is_sel or is_hov) and "medium" or "thin", "dashed")
            drawShapePath(gc, elem)
        else
            if is_hov and not is_sel then
                gc:setColorRGB(150, 190, 250)
            else
                gc:setColorRGB(180, 210, 250)
            end
            gc:setPen((is_sel or is_hov) and "medium" or "thin", "smooth")
            drawShapePath(gc, elem)
        end
        
        if is_sel or is_hov then
            if not shear_results then drawLocalAxes(gc, elem) end
            gc:setColorRGB(255, 0, 0)
            if not shear_results then for pi, pt in ipairs(elem.points) do
                local sx, sy = toScreen(pt.u, pt.v)
                gc:fillArc(sx-3, sy-3, 6, 6, 0, 360)
                gc:setFont("sansserif", "r", 8)
                gc:drawString("P"..pi, sx + 5, sy - 5)
            end end
        end
        
        if elem.ys and elem.zs and not shear_profile_visible then
            local sx, sy = toScreen(elem.ys, elem.zs)
            gc:setColorRGB(0,0,0)
            gc:setFont("sansserif", "b", 8)
            gc:drawString("M"..i, sx, sy - 10)
        end
    end
    
    -- Draw Duennwand
    gc:setColorRGB(50, 50, 50)
    for i, elem in ipairs(duenn_elemente) do
        local is_sel = (selected_type == "duenn" and selected_idx == i)
        local is_hov = (hover_type == "duenn" and hover_idx == i)
        if shear_profile_visible then
            gc:setPen("thin", "dashed")
        else
            gc:setPen((is_sel or is_hov) and "thick" or "medium", "smooth")
        end
        if is_hov and not is_sel then gc:setColorRGB(100, 100, 100) else gc:setColorRGB(50, 50, 50) end
        
        if elem.type == "duenn_kreis" then
            local C = elem.points[1]
            local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
            local a, b = toScreen(C.u - R, C.v - R)
            local c, d = toScreen(C.u + R, C.v + R)
            local l, t_box = math.min(a, c), math.min(b, d)
            local w_box, h_box = math.abs(c - a), math.abs(d - b)
            gc:drawArc(l, t_box, w_box, h_box, 0, 360)
        elseif elem.type == "duenn_kreis_bogen" then
            local C = elem.points[1]
            local R = math.sqrt((elem.points[2].u - C.u)^2 + (elem.points[2].v - C.v)^2)
            local a1 = math.atan2(elem.points[2].v - C.v, elem.points[2].u - C.u)
            local a2 = math.atan2(elem.points[3].v - C.v, elem.points[3].u - C.u)
            local diff = a2 - a1
            if diff <= 0 then diff = diff + 2*math.pi end
            local a, b = toScreen(C.u - R, C.v - R)
            local c, d = toScreen(C.u + R, C.v + R)
            local l, t_box = math.min(a, c), math.min(b, d)
            local w_box, h_box = math.abs(c - a), math.abs(d - b)
            
            -- We just draw the approximated polygon but without filling it, just lines
            local steps = math.max(10, math.floor(math.deg(diff) / 5))
            local q = {}
            for i=0, steps do
                local ang = a1 + (i/steps)*diff
                local sx, sy = toScreen(C.u + R*math.cos(ang), C.v + R*math.sin(ang))
                table.insert(q, sx)
                table.insert(q, sy)
            end
            gc:drawPolyLine(q)
        else
            local sx1, sy1 = toScreen(elem.points[1].u, elem.points[1].v)
            local sx2, sy2 = toScreen(elem.points[2].u, elem.points[2].v)
            gc:drawLine(sx1, sy1, sx2, sy2)
        end
        
        if is_sel or is_hov then
            if not shear_results then drawLocalAxes(gc, elem) end
            gc:setColorRGB(255, 0, 0)
            if not shear_results then for pi, pt in ipairs(elem.points) do
                local sx, sy = toScreen(pt.u, pt.v)
                gc:fillArc(sx-3, sy-3, 6, 6, 0, 360)
                gc:setFont("sansserif", "r", 8)
                gc:drawString("P"..pi, sx + 5, sy - 5)
            end end
        end
        
        if elem.ys and elem.zs and not shear_profile_visible then
            local sx, sy = toScreen(elem.ys, elem.zs)
            gc:setColorRGB(0,0,0)
            gc:setFont("sansserif", "b", 8)
            gc:drawString("D"..i, sx, sy - 10)
        end
    end

    drawShearProfile(gc)
    woelb.zeichne(gc)

    if show_shear_center and system_results and #duenn_elemente > 0 then
        local center = berechneSchubmittelpunkt()
        if center and center.known then
            local center_x, center_y = toScreen(center.u, center.v)
            gc:setColorRGB(220, 40, 40)
            gc:fillArc(center_x - 4, center_y - 4, 8, 8, 0, 360)
            gc:setFont("sansserif", "b", 9)
            local display_u, display_v = coordinatesForDisplay(center.u, center.v)
            gc:drawString("Schubmittelpunkt (" .. formatLabel(display_length(display_u)) .. ", " .. formatLabel(display_length(display_v)) .. ") [" .. length_unit .. "]", center_x + 6, center_y - 10)
        end
    end

    if sigma_results then drawSigmaOverlay(gc, w, h) end
    
    -- Draw Kraefte nur in der normalen Querschnittsansicht.
    if not shear_profile_visible and not woelb.visible then for i, kraft in ipairs(kraefte) do
        local is_sel = (selected_type == "kraft" and selected_idx == i)
        local is_hov = (hover_type == "kraft" and hover_idx == i)
        gc:setColorRGB(is_sel and 255 or (is_hov and 150 or 0), 0, is_sel and 0 or (is_hov and 250 or 255)) 
        local sx, sy = toScreen(kraft.u, kraft.v)
        
        if math.abs(kraft.fc) > 1e-9 then
            local r = 6
            gc:drawArc(sx - r, sy - r, 2*r, 2*r, 0, 360)
            if kraft.fc < 0 then
                -- into plane (Kreuz)
                local d = r * 0.707
                gc:drawLine(sx - d, sy - d, sx + d, sy + d)
                gc:drawLine(sx - d, sy + d, sx + d, sy - d)
            else
                -- out of plane (Punkt)
                gc:fillArc(sx - 2, sy - 2, 4, 4, 0, 360)
            end
        end
        if math.abs(kraft.fa) > 1e-9 or math.abs(kraft.fb) > 1e-9 then
            local mag = math.sqrt(kraft.fa^2 + kraft.fb^2)
            local dx = (kraft.fa / mag) * 20
            local dy = -(kraft.fb / mag) * 20
            -- Draw line from tail to tip (sx, sy)
            gc:drawLine(sx - dx, sy - dy, sx, sy)
            local head_size = 6
            local angle = math.atan2(dy, dx)
            -- Draw arrowhead at (sx, sy)
            gc:drawLine(sx, sy, sx - head_size * math.cos(angle - 0.4), sy - head_size * math.sin(angle - 0.4))
            gc:drawLine(sx, sy, sx - head_size * math.cos(angle + 0.4), sy - head_size * math.sin(angle + 0.4))
        end
        -- Always draw a small point at the application point so it's clickable and visible
        gc:fillArc(sx - 2, sy - 2, 4, 4, 0, 360)
        if is_sel or is_hov then
            gc:setFont("sansserif", "r", 8)
            gc:drawString("K" .. i, sx + 5, sy - 15)
        end
    end end
    
    -- Draw Pending
    gc:setColorRGB(255, 100, 0)
    for i, p in ipairs(pending) do
        local sx, sy = toScreen(p.u, p.v)
        gc:fillArc(sx-3, sy-3, 6, 6, 0, 360)
        if i > 1 and string.sub(mode, 1, 5) == "duenn" then
            local sx_prev, sy_prev = toScreen(pending[i-1].u, pending[i-1].v)
            gc:drawLine(sx_prev, sy_prev, sx, sy)
        end
    end
    
    if kernMode > 0 then drawKern(gc, w, h) end
    if not shear_results then
        drawAxes(gc)
        drawSigmaExtrema(gc)
    end
    if not sigma_results then drawSpreadsheet(gc, w, h) end
    drawOverlapPrompt(gc, w, h)
    drawShearSelector(gc, w, h)   -- zuletzt, damit Kraefte und Achsen nicht darueber liegen
    drawMenu(gc, w, h)
    if qsMeldung then zeichneQsMeldung(gc, w, h) end

    if qsLoeschFrage then
        local boxW, boxH = math.min(w - 20, 260), 44
        local boxX, boxY = math.floor((w - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 165, 0); gc:fillRect(boxX, boxY, boxW, boxH)
        gc:setColorRGB(0, 0, 0); gc:setPen("thin", "smooth"); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("Wirklich alles loeschen?", boxX + 8, boxY + 6)
        gc:setFont("sansserif", "r", 9); gc:drawString("[Enter] loeschen    [Esc] abbrechen", boxX + 8, boxY + 24)
    end
    
    if #massiv_elemente == 0 and #duenn_elemente == 0 and mode == "idle" and not menuOpen then
        gc:setColorRGB(0, 0, 0)
        gc:setFont("sansserif", "r", 9)
        gc:drawString("M o. D fuer Querschnitt", 5, h - 15)
    end
end

function on.mouseMove(x, y)
    if menuOpen or mode ~= "idle" then return end
    local u, v = fromScreen(x, y)

    -- Die fruehere Suche nach der naechsten Stuetzstelle bei jeder Mausbewegung entfaellt:
    -- shear_hover_index wurde nirgends gezeichnet, loeste aber pro Bewegung einen ganzen Frame aus.
    
    if kernMode > 0 and system_results then
        local r = system_results
        local thresh = 12 / scale
        if kernMode == 1 then
            local best, bd = nil, thresh
            for i, ln in ipairs(kern_lines) do
                local dist = math.abs(ln.nu * (u - r.ys) + ln.nv * (v - r.zs) - ln.d)
                if dist < bd then bd, best = dist, i end
            end
            if best ~= kern_hover_line then
                kern_hover_line = best
                platform.window:invalidate()
            end
        else
            local best, bd = nil, thresh
            for i, p in ipairs(kern_vertices) do
                local dist = math.sqrt((u - p.u)^2 + (v - p.v)^2)
                if dist < bd then bd, best = dist, i end
            end
            if best ~= kern_hover_pt then
                kern_hover_pt = best
                platform.window:invalidate()
            end
        end
        return
    end
    
    local found_type, found_idx = nil, nil
    local force_hover_radius = 14 / math.max(scale, 1e-9)
    local element_hover_radius = 10 / math.max(scale, 1e-9)
    local min_dist = element_hover_radius
    
    -- Check kraefte
    for i, kraft in ipairs(kraefte) do
        local dist = math.sqrt((u - kraft.u)^2 + (v - kraft.v)^2)
        if dist < force_hover_radius and (found_type ~= "kraft" or dist < min_dist) then
            min_dist = dist
            found_type = "kraft"
            found_idx = i
        end
    end
    
    -- Elemente werden nur geprueft, wenn kein Kraftpunkt getroffen wurde.
    if not found_type then
        -- Check duenn
        for i, elem in ipairs(duenn_elemente) do
            local dist = duennKurve.abstand(elem, u, v)
            if dist < min_dist then
                min_dist = dist
                found_type = "duenn"
                found_idx = i
            end
        end
        
        -- Check massiv
        -- von hinten nach vorne, um die obersten (zuletzt gezeichneten) zu treffen
        for i = #massiv_elemente, 1, -1 do
            if is_point_inside(massiv_elemente[i], u, v) then
                found_type = "massiv"
                found_idx = i
                break
            end
        end
    end
    
    if found_type ~= hover_type or found_idx ~= hover_idx then
        hover_type, hover_idx = found_type, found_idx
        platform.window:invalidate()
    end
end

function on.mouseUp(x, y)
    if menuOpen then return end
    local u, v = fromScreen(x, y)
    u, v = fange(u, v)   -- Raster plus Punkte der vorhandenen Elemente
    
    if mode == "idle" then
        if hover_type then
            selected_type = hover_type
            selected_idx = hover_idx
            status = "Element ausgewaehlt. Enter bearbeitet (auch ohne Klick, nur mit dem Zeiger darauf)."
        else
            selected_type, selected_idx = nil, nil
            status = "Menue oeffnen mit 'M' oder 'D'."
        end
        platform.window:invalidate()
        return
    end
    
    table.insert(pending, {u=u, v=v})
    
    if mode == "rect" and #pending == 2 then finish_shape("rect")
    elseif mode == "massiv_linie" and #pending == 2 then finish_shape("massiv_linie")
    elseif mode == "circle" and #pending == 2 then finish_shape("circle")
    elseif mode == "triangle" and #pending == 3 then finish_shape("triangle")
    elseif mode == "trapezoid" and #pending == 4 then finish_shape("trapezoid")
    elseif mode == "sector" and #pending == 3 then finish_shape("sector")
    elseif mode == "segment" and #pending == 3 then finish_shape("segment")
    elseif mode == "duenn_kreis" and #pending == 2 then finish_shape("duenn_kreis")
    elseif mode == "duenn_kreis_bogen" and #pending == 3 then finish_shape("duenn_kreis_bogen")
    elseif mode == "force" and #pending == 1 then finish_shape("force")
    elseif mode == "duenn_linie" then
        status = "Linienzug: Weiter klicken. Enter zum Abschliessen."
    end
    
    platform.window:invalidate()
end

local function zoomCenter(factor)
    local w, h = platform.window:width(), platform.window:height()
    local old_scale = scale
    local new_scale = math.max(1e-4, scale * factor)
    local real_f = new_scale / old_scale
    ox = w/2 - (w/2 - ox) * real_f
    oy = h/2 - (h/2 - oy) * real_f
    scale = new_scale
end

-- Verlauf einer Richtung, fuer die die geschlossene Zelle keine Symmetrieachse hat: q0 kam dort
-- aus der Vertraeglichkeit statt aus der Symmetrie. Die Warnung bleibt (der Nutzer soll wissen,
-- dass die Symmetrie fehlt), sagt aber, dass S und tau trotzdem stimmen.
--   Ansicht 3 (S_a) und 6 (tau_b) gehoeren zur Querkraft in b-Richtung  -> senkrechte Achse (sym_v)
--   Ansicht 4 (S_b) und 5 (tau_a) gehoeren zur Querkraft in a-Richtung  -> waagerechte Achse (sym_h)
local function pruefeVerlaufSymmetrie(mode)
    if not shear_results or not shear_results.thin_closed then return end
    local a, b = axes()
    local braucht_v = (mode == 3 or mode == 6)
    local braucht_h = (mode == 4 or mode == 5)
    if not (braucht_v or braucht_h) then return end
    if braucht_v and shear_results.sym_v then return end
    if braucht_h and shear_results.sym_h then return end
    local u_ist_a = (rotation == 0 or rotation == 180)
    local achse = braucht_v and (u_ist_a and b or a) or (u_ist_a and a or b)
    local groesse = (mode == 3 and ("S" .. a)) or (mode == 4 and ("S" .. b))
        or (mode == 5 and ("tau_" .. a)) or ("tau_" .. b)
    meldung(groesse .. " setzt bei einer geschlossenen Zelle die Symmetrie zur " .. achse
        .. "-Achse voraus; die ist hier nicht vorhanden. Der Umlaufschubfluss q0 wurde fuer diese "
        .. "Richtung deshalb aus der Vertraeglichkeit bestimmt (Umlaufintegral q/t ds = 0, Querkraft im "
        .. "Schubmittelpunkt) -- der gezeigte Verlauf von S und tau ist damit trotzdem richtig.", "Warnung", true)
end

function on.charIn(c)
    if c == "-" or c == "?" or c == string.char(226, 136, 146) or c == string.char(226, 129, 187) or c == string.char(173) or c == string.char(226, 128, 147) or c == "-" or c == "-" then c = "-" end
    c = string.lower(c)
    if sigma_input_step > 0 then
        if c:match("[%w%.,%-%+%*/%(%)]") then inputText = inputText .. c end
        platform.window:invalidate()
        return
    end
    if shear_input_step > 0 or torsion_input_step > 0 or woelb.step > 0 then
        if c:match("[%w%.,%-%+%*/%(%)]") then inputText = inputText .. c end
        platform.window:invalidate()
        return
    end
    if inputMode then
        if c:match("[%w%.,%-%+%*/%(%)]") then inputText = inputText .. c end
        platform.window:invalidate()
        return
    end
    
    if mode == "overlap_prompt" then
        if c == "1" then
            overlap_pending_elem.is_hole = true
            overlap_pending_elem.is_numeric = true
            table.insert(massiv_elemente, overlap_pending_elem)
            overlap_pending_elem = nil
            pending = {}
            mode = "idle"
            status = "Element als Loch abgezogen."
            berechneSystem()
        elseif c == "2" then
            overlap_pending_elem.is_numeric = true
            table.insert(massiv_elemente, overlap_pending_elem)
            overlap_pending_elem = nil
            pending = {}
            mode = "idle"
            status = "Numerisch addiert."
            berechneSystem()
        elseif c == "3" then
            overlap_pending_elem = nil
            pending = {}
            mode = "idle"
            status = "Zeichnen verworfen."
        end
        platform.window:invalidate()
        return
    end

    if menuOpen and menuPage ~= 3 then
        local menu_number = tonumber(c)
        local menu_count = menuPage == 1 and 9 or menuPage == 2 and 5 or menuPage == 5 and 8 or menuPage == 6 and 4 or menuPage == 8 and 2 or menuPage == 9 and 6 or menuPage == 10 and 8 or menuPage == 4 and 10 or 6
        if menu_number and menu_number >= 1 and menu_number <= menu_count then
            menuRow = menu_number
            on.enterKey()
            return
        end
    end
    
    if c == "m" then
        menuOpen = true; showResults = false; showTable = false; menuPage = 1; menuRow = 1
    elseif c == "d" then menuOpen = true; showResults = false; showTable = false; menuPage = 2; menuRow = 1
    elseif c == "b" then toggleCalculationMenu()
    elseif c == "e" then
        showResults = not showResults
        if showResults then results_scroll_y = 0; qsHinweis.pruefeDicke() end
        menuOpen = false
        showTable = false
    elseif c == "t" then
        if show_shear_center and system_results and #duenn_elemente > 0 then
            if show_shear_moment_table then
                show_shear_moment_table, showTable = false, false
            else
                shear_moment_table = berechneSchubMomentTabelle()
                show_shear_moment_table = shear_moment_table ~= nil
                showTable = show_shear_moment_table
            end
        else
            showTable = not showTable
        end
        menuOpen = false
        showResults = sigma_results ~= nil and not showTable
    elseif c == "v" then
        if woelb.visible then
            meldung("V gehoert zur Schubspannungsansicht. Esc schliesst die Verwoelbung.", "Hinweis")
        elseif shear_results then
            shear_selector_open = true
            status = "Schubverlauf waehlen: 0 bis 9. Esc schliesst."
        else
            meldung("V ist nur im Schubspannungsmodus verfuegbar.", "Hinweis")
        end
    elseif shear_selector_open and (c == "0" or c == "1" or c == "2" or c == "3" or c == "4" or c == "5" or c == "6" or c == "7" or c == "8" or c == "9") then
        local choice = c == "0" and 10 or tonumber(c)
        shear_selector_open = false
        shear_profile_visible, shear_view_mode = true, choice
        shear_hover_index = nil
        status = "Schubverlauf " .. (c == "0" and "10" or c) .. " angezeigt."
        pruefeVerlaufSymmetrie(choice)
    elseif c == "+" then zoomCenter(1.25)
    elseif c == "-" then zoomCenter(1/1.25)
    elseif c == "c" then on.clearKey()
    elseif c == "h" then autoZoom()
    elseif c == "k" then
        if not system_results then
            meldung("Kein Querschnitt vorhanden.", "Hinweis", true)
        else
            kernMode = (kernMode + 1) % 3
            hover_type, hover_idx = nil, nil
            if kernMode > 0 then
                if kern_build then kern_build() end
                status = kernMode == 1 and "Kern 1/2: Umhüllende Geraden (K: weiter)" or "Kern 2/2: Kernfläche (K: weiter)"
            else
                status = "Kern-Modus beendet."
            end
        end
    elseif c == "o" then
        menuOpen = true
        showResults = false
        menuPage = 4
        menuRow = 1
        inputMode = false
    end
    platform.window:invalidate()
end

function on.arrowKey(k)
    -- zu lange Meldungsbox: hoch/runter blaettert zeilenweise durch den Text
    if qsMeldung and (qsMeldung.scrollMax or 0) > 0 and (k == "up" or k == "down") then
        qsMeldung.scroll = math.max(0, math.min(qsMeldung.scrollMax, (qsMeldung.scroll or 0) + ((k == "down") and 1 or -1)))
        platform.window:invalidate()
        return
    end
    if showTable and sigma_results then
        -- σx-Tabelle und Verteilung: hoch/runter scrollt, begrenzt auf den Inhalt
        local h = platform.window:height()
        local max_y = math.max(0, (sigmaEingabe.inhaltHoehe or 0) - (h - 24) + 8)
        if k == "up" then sigma_scroll_y = math.max(0, sigma_scroll_y - 20)
        elseif k == "down" then sigma_scroll_y = math.min(max_y, sigma_scroll_y + 20)
        end
        platform.window:invalidate()
        return
    end
    if showTable then
        if k == "left" then table_scroll_x = table_scroll_x + 20
        elseif k == "right" then table_scroll_x = table_scroll_x - 20
        elseif k == "up" then table_scroll_y = table_scroll_y + 20
        elseif k == "down" then table_scroll_y = table_scroll_y - 20
        end
        platform.window:invalidate()
        return
    end
    if showResults and not sigma_results then
        local max_scroll = math.max(0, 20 + (15 + 4) * 16 - platform.window:height())
        if k == "up" then results_scroll_y = math.max(0, results_scroll_y - 20)
        elseif k == "down" then results_scroll_y = math.min(max_scroll, results_scroll_y + 20)
        end
        platform.window:invalidate()
        return
    end
    if menuOpen and not inputMode then
        if menuPage == 4 or menuPage == 9 or menuPage == 10 then
            if k == "left" or k == "right" then
                -- Optionen, Weitere Optionen, Querschnittswerte im Kreis
                local folge = { [4] = 9, [9] = 10, [10] = 4 }
                local zurueck = { [4] = 10, [9] = 4, [10] = 9 }
                menuPage = (k == "right") and folge[menuPage] or zurueck[menuPage]
                menuRow = 1
                platform.window:invalidate()
                return
            end
        end
        local n = 1
        if menuPage == 1 then n = 9
        elseif menuPage == 2 then n = 5
        elseif menuPage == 5 then n = 8
        elseif menuPage == 6 then n = 4
        elseif menuPage == 8 then n = 2
        elseif menuPage == 9 then n = 6
        elseif menuPage == 10 then n = 8
        elseif menuPage == 4 then n = 10
        elseif menuPage == 3 then
            local elem = (selected_type == "massiv") and massiv_elemente[selected_idx] or (selected_type == "duenn" and duenn_elemente[selected_idx] or kraefte[selected_idx])
            if selected_type == "kraft" then
                n = 7
            else
                n = elem and (#elem.points * 2 + (elem.has_swap and 5 or (elem.has_t and 5 or 4))) or 1
            end
        end
        if k == "up" then menuRow = math.max(1, menuRow - 1)
        elseif k == "down" then menuRow = math.min(n, menuRow + 1)
        end
        platform.window:invalidate()
        return
    end
    if k == "left" then ox = ox + 8
        elseif k == "right" then ox = ox - 8
        elseif k == "up" then oy = oy + 8
        elseif k == "down" then oy = oy - 8
        end
    platform.window:invalidate()
end

local function enterSigmaInput()
    local val = evaluate_input(inputText)
    if not val then
        meldung("Ungueltige σx-Eingabe.", "Eingabe", true)
        inputText = ""
        platform.window:invalidate()
        return true
    end
    local feld = sigmaEingabe.felder[sigma_input_step]
    if feld == "N" then sigma_N = input_to_internal(val, force_unit)
    elseif feld == "Ma" then sigma_My = input_to_internal(val, moment_unit)
    elseif feld == "Mb" then sigma_Mz = input_to_internal(val, moment_unit)
    else sigmaEingabe.versatz = math.abs(input_to_internal(val, length_unit)) end
    inputText = ""
    if sigma_input_step < #sigmaEingabe.felder then
        sigma_input_step = sigma_input_step + 1
        status = sigmaEingabe.aufforderung()
    else
        sigma_input_step = 0
        if finishSigmaCalculation(sigma_oblique and (sigma_Mz or 0) or 0) then
            status = sigma_oblique and "Schiefe σx-Minimum und -Maximum berechnet." or "Normale σx-Minimum und -Maximum berechnet."
        else
            meldung("σx nicht berechenbar: Nenner ist 0.", "Spannung nicht berechnet", true)
        end
    end
    platform.window:invalidate()
    return true
end

local function enterMenuInput()
    local val = evaluate_input(inputText)
    if val then
        if menuPage == 4 and menuRow == 1 then
            local old_raster = raster
            raster = math.max(1e-5, input_to_internal(val, length_unit))
            scale = scale * old_raster / raster
            status = "Raster gesetzt auf " .. raster
        elseif menuPage == 4 and menuRow == 2 then
            default_t = math.max(0.01, input_to_internal(val, length_unit))
            status = "Dicke t gesetzt auf " .. default_t
        elseif menuPage == 4 and menuRow == 5 then
            kos_size = math.max(1e-5, val)
            kos_pixel_length = kos_size
            status = "KOS Groesse gesetzt auf " .. kos_size
        elseif menuPage == 4 and menuRow == 10 then
            torsion_xi = math.max(0, val)
            berechneSystem()
            status = "ξ gesetzt auf " .. torsion_xi
        elseif menuPage == 10 and (menuRow == 5 or menuRow == 6) and system_results then
            -- Schwerpunkt im angezeigten KOS (Laengeneinheit der Anzeige); die andere Koordinate bleibt
            local r = system_results
            local ys_d, zs_d = coordinatesForDisplay(r.ys, r.zs)
            local wert = input_to_internal(val, length_unit)
            if menuRow == 5 then ys_d = wert else zs_d = wert end
            local u, v = coordinatesFromDisplay(ys_d, zs_d)
            local u0, v0 = qsWerte.bezugspunkt()
            qsWerte.ys, qsWerte.zs = u - u0, v - v0
            berechneSystem()
            shear_results, shear_profile_visible, shear_selector_open = nil, false, false
            status = "Manuelle Querschnittswerte: " .. qsWerte.namen()
        elseif menuPage == 10 and menuRow >= 1 and menuRow <= 4 and system_results then
            -- Eingaben im angezeigten KOS und in der Laengeneinheit der Anzeige, bezogen auf den Schwerpunkt
            local f = unit_factor(length_unit)
            local r = system_results
            local tausch = (rotation == 90 or rotation == 270)
            local neu = {}
            if menuRow == 1 then neu.A = val * f ^ 2
            elseif menuRow == 2 then neu[tausch and "Iz" or "Iy"] = val * f ^ 4
            elseif menuRow == 3 then neu[tausch and "Iy" or "Iz"] = val * f ^ 4
            else neu.Iyz = (tausch and -val or val) * f ^ 4 end
            local A_ = neu.A or r.A
            local Iy_, Iz_, Iyz_ = neu.Iy or r.Iy, neu.Iz or r.Iz, neu.Iyz or r.Iyz
            if A_ <= 0 or Iy_ <= 0 or Iz_ <= 0 then
                meldung("A, I_y und I_z muessen positiv sein.", "Eingabe", true)
            elseif Iy_ * Iz_ - Iyz_ ^ 2 <= 1e-12 * Iy_ * Iz_ then
                meldung("So nicht moeglich: I_y * I_z - I_yz^2 muss positiv sein (sonst ist der Querschnitt nicht biegesteif).", "Eingabe", true)
            else
                for k, v in pairs(neu) do qsWerte[k] = v end
                berechneSystem()
                shear_results, shear_profile_visible, shear_selector_open = nil, false, false
                status = "Manuelle Querschnittswerte: " .. qsWerte.namen()
            end
        elseif menuPage == 9 and (menuRow == 2 or menuRow == 3) then
            -- Verschiebung entlang der angezeigten Achse, intern umgerechnet (KOS-Drehung)
            local d = input_to_internal(val, length_unit)
            local da, db = (menuRow == 2) and d or 0, (menuRow == 3) and d or 0
            local a, b = axes()
            if verschiebeKOS(coordinatesFromDisplay(da, db)) then
                status = "KOS um " .. string.format("%.6g", val) .. " " .. length_unit .. " entlang "
                    .. ((menuRow == 2) and a or b) .. " verschoben."
            end
        elseif menuPage == 3 then
            local elem = selected_type == "massiv" and massiv_elemente[selected_idx] or selected_type == "duenn" and duenn_elemente[selected_idx] or kraefte[selected_idx]
            if selected_type == "kraft" then
                local display_u, display_v = coordinatesForDisplay(elem.u, elem.v)
                local force_a, force_b = forceComponentsForDisplay(elem.fa, elem.fb)
                if menuRow == 2 then display_u = input_to_internal(val, length_unit)
                elseif menuRow == 3 then display_v = input_to_internal(val, length_unit)
                elseif menuRow == 4 then force_a = input_to_internal(val, force_unit)
                elseif menuRow == 5 then force_b = input_to_internal(val, force_unit)
                elseif menuRow == 6 then elem.fc = input_to_internal(val, force_unit) end
                if menuRow == 2 or menuRow == 3 then elem.u, elem.v = coordinatesFromDisplay(display_u, display_v) end
                if menuRow == 4 or menuRow == 5 then elem.fa, elem.fb = forceComponentsFromDisplay(force_a, force_b) end
            elseif selected_type == "massiv" and elem.has_t and menuRow == #elem.points * 2 + 3 then
                elem.t = math.max(0.01, input_to_internal(val, length_unit))
            elseif selected_type == "duenn" and menuRow == #elem.points * 2 + 2 then
                elem.t = math.max(0.01, input_to_internal(val, length_unit))
            else
                local row_idx = menuRow - 1
                local pt_idx = math.floor((row_idx + 1) / 2)
                if row_idx % 2 == 0 then
                    setDisplayedPointCoordinate(elem.points[pt_idx], "v", input_to_internal(val, length_unit))
                else
                    setDisplayedPointCoordinate(elem.points[pt_idx], "u", input_to_internal(val, length_unit))
                end
            end
            berechneSystem()
        end
    else
        meldung("Ungueltige Eingabe.", "Eingabe", true)
    end
    inputMode, inputText = false, ""
    platform.window:invalidate()
    return true
end

local function enterMenuAction()
    if menuPage == 5 then
        if menuRow == 1 then showResults, showTable, menuOpen = true, false, false; qsHinweis.pruefeDicke()
        elseif menuRow == 2 then showTable, showResults, menuOpen = true, false, false
        elseif menuRow == 3 then openSigmaInput(true)   -- eine Maske: N, My, Mz (und Δx bei Querkraeften)
        elseif menuRow == 4 then menuPage, menuRow = 6, 1
        elseif menuRow == 5 then openShearFromForces()
        elseif menuRow == 6 then
            show_shear_center = not show_shear_center
            menuOpen = false
            status = show_shear_center and "Schubmittelpunkt angezeigt. T: Momententabelle." or "Schubmittelpunkt ausgeblendet."
        elseif menuRow == 7 then woelb.oeffnen()
        elseif menuRow == 8 then menuOpen = false end
    elseif menuPage == 8 then
        if menuRow == 1 then
            shear_external_input = true
            menuOpen = false
            openShearInput()
        elseif menuRow == 2 then menuOpen = false end
    elseif menuPage == 6 then
        if menuRow == 1 or menuRow == 2 then kernMode = menuRow; kern_build(); menuOpen = false
        elseif menuRow == 3 then kernMode, menuOpen = 0, false
        elseif menuRow == 4 then menuPage, menuRow = 5, 4 end
    elseif menuPage == 1 then
        local modes = {"rect", "circle", "triangle", "trapezoid", "sector", "segment", "massiv_linie", "force"}
        if modes[menuRow] then mode, pending, menuOpen = modes[menuRow], {}, false
        elseif menuRow == 9 then menuPage, menuRow = 2, 1 end
    elseif menuPage == 2 then
        local modes = {"duenn_linie", "duenn_kreis", "duenn_kreis_bogen", "force"}
        if modes[menuRow] then mode, pending, menuOpen = modes[menuRow], {}, false
        elseif menuRow == 5 then menuPage, menuRow = 1, 1 end
    elseif menuPage == 4 then
        if menuRow == 1 or menuRow == 2 or menuRow == 5 then inputMode, inputText = true, ""
        elseif menuRow == 3 then plane, swapped = plane % 3 + 1, false
        elseif menuRow == 4 then rotation = (rotation + 90) % 360
        elseif menuRow == 6 then zahlenFormat = (zahlenFormat % 3) + 1
        elseif menuRow == 7 then force_unit = cycle_unit(force_unit, {"N", "kN"})
        elseif menuRow == 8 then length_unit = cycle_unit(length_unit, {"m", "dm", "cm", "mm"})
        elseif menuRow == 9 then moment_unit = cycle_unit(moment_unit, {"Nm", "Ncm", "Nmm", "kNm", "kNcm", "kNmm"})
        elseif menuRow == 10 then inputMode, inputText = true, ""
        end
    elseif menuPage == 10 then
        if menuRow >= 1 and menuRow <= 6 then
            if not system_results then meldung("Kein Querschnitt vorhanden.", "Hinweis", true)
            else inputMode, inputText = true, "" end
        elseif menuRow == 7 then
            loescheManuelleWerte()
            berechneSystem()
            shear_results, shear_profile_visible, shear_selector_open = nil, false, false
            status = "Berechnete Querschnittswerte wiederhergestellt."
        elseif menuRow == 8 then menuPage, menuRow = 4, 1 end
    elseif menuPage == 9 then
        if menuRow == 1 then
            verschiebeKOSZumSchwerpunkt()
            menuOpen = false
        elseif menuRow == 2 or menuRow == 3 then
            inputMode, inputText = true, ""
        elseif menuRow == 4 then
            ftm_bezug = (ftm_bezug == "kos") and "schwerpunkt" or "kos"
            status = "Traegheitsmomente bezogen auf " .. (ftm_bezug == "kos" and "den KOS-Ursprung" or "den Schwerpunkt")
        elseif menuRow == 5 then rasterPunkte = ((rasterPunkte or 1) + 1) % 3
        elseif menuRow == 6 then menuPage, menuRow = 4, 1 end
    elseif menuPage == 3 then
        local elem = selected_type == "massiv" and massiv_elemente[selected_idx] or selected_type == "duenn" and duenn_elemente[selected_idx] or kraefte[selected_idx]
        if not elem then
            menuOpen, selected_type, selected_idx = false, nil, nil
            platform.window:invalidate()
            return
        end
        if selected_type == "kraft" then
            if menuRow >= 2 and menuRow <= 6 then inputMode, inputText = true, ""
            elseif menuRow == 7 then table.remove(kraefte, selected_idx); selected_type, selected_idx, menuOpen = nil, nil, false end
        elseif menuRow > 1 and menuRow <= #elem.points * 2 + 1 then inputMode, inputText = true, ""
        elseif selected_type == "massiv" and menuRow == #elem.points * 2 + 2 then elem.is_hole = not elem.is_hole; berechneSystem()
        elseif selected_type == "duenn" and menuRow == #elem.points * 2 + 2 then inputMode, inputText = true, ""
        elseif menuRow == #elem.points * 2 + (elem.has_swap and 3 or (elem.has_t and 3 or 2)) then
            if elem.has_swap then elem.points[2], elem.points[3] = elem.points[3], elem.points[2] else inputMode, inputText = true, "" end
        elseif menuRow >= #elem.points * 2 + 3 then
            if selected_type == "massiv" then table.remove(massiv_elemente, selected_idx) else table.remove(duenn_elemente, selected_idx) end
            selected_type, selected_idx, menuOpen = nil, nil, false
            berechneSystem()
        end
    end
    platform.window:invalidate()
end

function on.enterKey()
    if qsLoeschFrage then loescheAllesQS(); return end
    if mode == "duenn_linie" and not menuOpen then finish_thin_line(); return end
    if sigma_input_step > 0 then enterSigmaInput(); return end
    if shear_input_step > 0 then enterShearInput(); return end
    if torsion_input_step > 0 then enterTorsionInput(); platform.window:invalidate(); return end
    if woelb.step > 0 then woelb.eingabe(); return end
    -- Wie im Tragwerksskript: Hovern genuegt, vorher anklicken ist nicht noetig.
    -- Liegt der Zeiger auf einem Objekt, gilt dieses; sonst das zuletzt ausgewaehlte.
    if not menuOpen and mode == "idle" and (hover_idx or selected_idx) then
        if hover_idx then selected_type, selected_idx = hover_type, hover_idx end
        menuOpen, menuPage, menuRow, showResults = true, 3, 1, false
        platform.window:invalidate()
        return
    end
    if not menuOpen then return end
    if inputMode then enterMenuInput() else enterMenuAction() end
end

function on.menuKey()
    toggleCalculationMenu()
    platform.window:invalidate()
end

function on.contextMenu()
    toggleCalculationMenu()
    platform.window:invalidate()
end

function on.escapeKey()
    if qsLoeschFrage then qsLoeschFrage = false; platform.window:invalidate(); return end
    if qsMeldung then
        qsMeldung = nil
        platform.window:invalidate()
        return
    end
    if menuOpen or inputMode or shear_selector_open then
        menuOpen = false
        inputMode, inputText = false, ""
        shear_selector_open = false
        status = "Untermenue geschlossen. Modus bleibt aktiv."
        platform.window:invalidate()
        return
    end
    if woelb.step > 0 or woelb.visible then
        -- Verwoelbung schliessen: das dort eingegebene MT gilt nur in dieser Ansicht
        woelb.step, woelb.visible, woelb.results = 0, false, nil
        inputText = ""
        status = "Verwoelbung geschlossen."
        platform.window:invalidate()
        return
    end
    escape_clear_pending = true
    inputMode, inputText = false, ""
    sigma_input_step, sigma_N, sigma_My, sigma_Mz = 0, nil, nil, nil
    sigmaEingabe.versatz = 0
    shear_input_step, shear_Qa, shear_Qb, shear_results = 0, nil, nil, nil
    shear_external_input = false
    show_shear_center, show_shear_moment_table, shear_moment_table = false, false, nil
    torsion_input_step, torsion_M, torsion_results = 0, nil, nil
    woelb.step, woelb.M, woelb.results, woelb.visible = 0, nil, nil, false
    shear_profile_visible, shear_hover_index, shear_view_mode, shear_selector_open = false, nil, 0, false
    sigma_results = nil
    sigma_oblique = false
    sigma_scroll_y = 0
    kernMode = 0
    menuOpen = false
    showResults = false
    showTable = false
    overlap_pending_elem = nil
    pending = {}
    mode = "idle"
    status = "Abbruch. Modus ist idle."
    platform.window:invalidate()
end

function on.backspaceKey()
    if escape_clear_pending then
        escape_clear_pending = false
        on.clearKey()
        return
    end
    if shear_input_step > 0 or torsion_input_step > 0 or woelb.step > 0 or sigma_input_step > 0 then
        inputText = inputText:sub(1, -2)
    elseif inputMode then
        inputText = inputText:sub(1, -2)
    elseif #pending > 0 then
        table.remove(pending)
        status = "Letzten Punkt zurueckgenommen."
    else
        -- Loesche das letzte Element, je nachdem was gezeichnet wurde
        if #duenn_elemente > 0 then
            table.remove(duenn_elemente)
            berechneSystem()
            status = "Letztes duennwandiges Segment geloescht."
        elseif #massiv_elemente > 0 then
            table.remove(massiv_elemente)
            berechneSystem()
            status = "Letztes Massiv-Element geloescht."
        end
    end
    platform.window:invalidate()
end

function on.deleteKey()
    on.backspaceKey()
end

-- Initialize
berechneSystem()
    