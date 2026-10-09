-- ==========================================
-- 1. DATENSTRUKTUR & EINSTELLUNGEN
-- ==========================================
local knoten = {}
local staebe = {}
local auswahl = nil
local hoverObj = nil
local hoverTyp = nil
local mouseX, mouseY = 0, 0

-- Laufvariable x nur als eigenstaendigen Bezeichner behandeln (nicht in exp, max, q_x, x0 ...).
-- "2x" bleibt erlaubt. Als String-Methoden (s:subx / s:hasx), damit keine Upvalues verbraucht werden.
local function isVarXAt(str, pos)
    local prev = pos > 1 and str:sub(pos - 1, pos - 1) or ""
    local nxt = str:sub(pos + 1, pos + 1)
    return not prev:match("[%a_]") and not nxt:match("[%w_]")
end
function string.subx(str, repl)
    return (str:gsub("()x", function(pos) if isVarXAt(str, pos) then return repl end end))
end
function string.hasx(str)
    if not str then return false end
    for pos in str:gmatch("()x") do if isVarXAt(str, pos) then return true end end
    return false
end

pxProMeter = 30
offsetX = 160      
offsetY = 106      

rasterMass = 1.0   
defEA = 1e10
randDehnstarr = false  -- Standard-EA dehnstarr: alle Staebe ohne eigenes EA (Stabmenue) gelten als dehnsteif
randStarrDirekt = true -- Rand-LGS: starre Staebe direkt (Starrkoerper + Gleichgewicht) statt Grenzwert EA, EI -> unendlich
symbolFehlerOffen = false   -- Hinweisbox zu symbolFehler sichtbar (ESC schliesst sie, der Fehler bleibt bestehen)
meldungText, meldungTitel = nil, nil   -- einmalige Meldung (Export, Rand-LGS); gelbe Box, ESC schliesst sie
-- Disp aus Lua zeigt der Rechner nicht an: Meldungen muessen gezeichnet werden.
function zeigeMeldung(text, titel)
    meldungText, meldungTitel = tostring(text), titel or "Export"
    print(text)
    if platform and platform.window then platform.window:invalidate() end
end
hinweisListe = {}           -- Hinweise nach der Berechnung (gelbe Box, ESC schliesst sie)
hinweisOffen = false
hinweisSig, hinweisQuittiert = nil, nil   -- nach ESC erst wieder zeigen, wenn sich das System geaendert hat
hinweisScroll, hinweisScrollMax = 0, 0    -- erste sichtbare Zeile der gelben Box (Pfeiltasten hoch/runter)
hinweisScrollInhalt = nil                 -- Inhalt, zu dem hinweisScroll gehoert (neuer Inhalt beginnt oben)
hinweisBoxScrollbar = false               -- gelbe Box ist sichtbar und laenger als der Bildschirm

-- Gelbe Hinweis- bzw. Exportbox. Passt der Text nicht auf den Bildschirm, zeigt sie einen Ausschnitt,
-- den die Pfeiltasten hoch/runter verschieben (on.arrowKey), dazu einen Zeilenzaehler und rechts
-- Pfeile, solange oben bzw. unten noch etwas steht.
function zeichneHinweisBox(gc, b, h, liste, titel)
    local boxW = math.min(b - 20, 300)
    gc:setFont("sansserif", "r", 9)
    local zeilen = {}
    for hi, text in ipairs(liste) do
        if hi > 1 then zeilen[#zeilen + 1] = "" end
        for absatz in (text .. "\n"):gmatch("(.-)\n") do   -- \n erzwingt eine neue Zeile
            local zeile = ""
            for wort in absatz:gmatch("%S+") do
                local probe = (zeile == "") and wort or (zeile .. " " .. wort)
                if zeile ~= "" and gc:getStringWidth(probe) > boxW - 24 then zeilen[#zeilen + 1] = zeile; zeile = wort else zeile = probe end
            end
            if zeile ~= "" then zeilen[#zeilen + 1] = zeile end
        end
    end
    local boxH = math.min(28 + 13 * #zeilen, h - 10)
    local sichtbar = math.max(1, math.floor((boxH - 28) / 13))
    local inhalt = titel .. "\1" .. table.concat(liste, "\1")
    if inhalt ~= hinweisScrollInhalt then hinweisScrollInhalt, hinweisScroll = inhalt, 0 end
    hinweisScrollMax = math.max(0, #zeilen - sichtbar)
    hinweisScroll = math.max(0, math.min(hinweisScroll or 0, hinweisScrollMax))
    hinweisBoxScrollbar = hinweisScrollMax > 0
    local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
    gc:setColorRGB(255, 235, 150); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(0, 0, 0); gc:drawRect(boxX, boxY, boxW, boxH)
    gc:setFont("sansserif", "b", 10); gc:drawString(titel .. ":", boxX + 8, boxY + 6)
    gc:setFont("sansserif", "r", 9)
    for k = 1, math.min(sichtbar, #zeilen - hinweisScroll) do
        gc:drawString(zeilen[hinweisScroll + k], boxX + 8, boxY + 12 + 13 * k)
    end
    gc:drawString("[Esc]", boxX + boxW - 34, boxY + 6)
    if hinweisBoxScrollbar then
        local zaehler = string.format("%d-%d/%d", hinweisScroll + 1, hinweisScroll + sichtbar, #zeilen)
        gc:drawString(zaehler, boxX + boxW - 40 - gc:getStringWidth(zaehler), boxY + 6)
        local ax = boxX + boxW - 10
        if hinweisScroll > 0 then gc:fillPolygon({ ax - 4, boxY + 30, ax + 4, boxY + 30, ax, boxY + 24 }) end
        if hinweisScroll < hinweisScrollMax then gc:fillPolygon({ ax - 4, boxY + boxH - 10, ax + 4, boxY + boxH - 10, ax, boxY + boxH - 4 }) end
    end
end
loeschFrage = false         -- Sicherheitsfrage vor "alles loeschen" (Enter loescht, ESC bricht ab)
defEI = 1e8        
autoKGV = false    
zeigeN = true      

ptsBiegelinie = 20
zoomNormal = 2
zoomExplosion = 5
casToleranz = 5
verlaufSkalierung = 1
systemBerechnet = false
randErgebnis = nil   -- letztes Rand-LGS: Biege-/Laengslinien je Stab, Knotenverschiebungen, Schluessel
letzteSystemNr = nil -- zuletzt gespeicherte bzw. geoeffnete Systemnummer (Obermenue Seite 4)

ansichtsModus = "System"
explosionPage = 1

menuOffen = false
menuTyp = nil
menuIndex = nil
menuZeile = 1
menuSeite = 1      
eingabeModus = false
eingabeText = ""

zeigeMaxWerte = true
fachwerkModus = false
zeigeBemassung = true
bogenSegmente = 20
zahlenFormat = 1
rasterPunkte = 1            -- Rasterpunkte: 0 keine, 1 normal (1 px), 2 dick (2 px); Obermenue Seite 3

local warnungKinematisch = false 
local warnungStarrBestimmt = false

local polplan = { poles = {}, rays = {}, num_disks = 0, fixed = {}, contradictions = {} }
local buildPolplan -- Pre-declare function so on.charIn can call it
local calcKinematicStates -- Pre-declare for kinematic animation
local getKinematicDisp, getKinematicRot
local showKinematicAnim = false
local kinematic_anim_timer = 0
local pvvPrompt = false
local pvv_released_binding = nil
local pvvModus = false
local in_pvv_release = false
local kinematic_states = nil
local kinematic_states_staebe = nil
local kinematic_disk_states = nil
local kinematic_seed_info = nil
local applyKGVZustand -- Pre-declare function for KGV export
local berechneSystemGleichungen -- Pre-declare for KGV export
local rechneAktuellesSystem -- Pre-declare for KGV export
local exportBiegelinienToTI -- Pre-declare for Stab export
local exportULinienToTI -- Pre-declare for Stab export
local exportBiegelinienNeuToTI -- Pre-declare for symbolic boundary-LGS export
local exportULinienNeuToTI -- Pre-declare for symbolic axial export
local exportSchnittkraefteToTI -- Pre-declare for Stab export
local exportArbeitssatzToTI -- Pre-declare for Arbeitssatz export
local anzahlGleichungen = 0
local stabID = {} 
local render_pts_1 = {}
local render_pts_2 = {} 
local render_pts_4 = {}

local X_Werte = {}
local KGV_Zustand = -1 
local kgvInputString = "" 
local kgv_n = nil        


local glob_K = {}
local glob_F = {}
local glob_u = {}
local glob_Legend = {}

-- ==========================================
-- 2. KONSTRUKTOREN
-- ==========================================
local function erstelleKnoten(lx, ly)
    return { 
        x = lx, y = ly, 
        gelenk = false, 
        lager_x = false, lager_y = false, lager_m = false, 
        cx = 0, cy = 0, cm = 0,      
        last_x = 0, last_y = 0, last_m = 0, last_w = 0,
        winkel = 0, f_winkel = 0,
        R_xi = 0, R_eta = 0, R_m = 0,
        Rx_glob = 0, Ry_glob = 0, Rm_glob = 0
    }
end

local function erstelleStab(k1_idx, k2_idx)
    return { 
        k1 = k1_idx, k2 = k2_idx, 
        EA = defEA, EI = defEI, EA_str = defEA_str, EI_str = defEI_str, biegesteif = false, dehnsteif = false, bogen_r = 0, 
        q_str = "0", q_pts = nil, q_max = 0,
        n_str = "0", n_pts = nil, n_max = 0,
        m_str = "0", m_pts = nil, m_max = 0,
        gx_str = "0", gx_pts = nil,
        gy_str = "0", gy_pts = nil,
        Q_cas_pts = nil, M_cas_pts = nil, v_cas_pts_EI = nil,
        N_cas_pts = nil, u_cas_pts_EA = nil,
        q = 0, n = 0, m = 0,
        q_A = 0, q_B = 0, n_A = 0, n_B = 0,
        gx = 0, gy = 0, gx_proj = false, gy_proj = false, 
        To = 0, Tu = 0, alpha = 0.00001, h = 0.2,
        gelenk_A = false, gelenk_B = false,   
        n_gelenk_A = false, n_gelenk_B = false, 
        q_gelenk_A = false, q_gelenk_B = false, 
        x_mA = 0, x_mB = 0,
        s_local = {0, 0, 0, 0, 0, 0}, v_local = {0, 0, 0, 0, 0, 0} 
    }
end

-- ==========================================
-- Neuer Export 1: symbolische Biegelinie mit Rand-LGS.
local function pvvBackupSystem()
    for i, k in ipairs(knoten) do k.pvv_lager_x = k.lager_x; k.pvv_lager_y = k.lager_y; k.pvv_lager_m = k.lager_m; k.pvv_gelenk = k.gelenk end
    for i, s in ipairs(staebe) do 
        s.pvv_gelenk_A = s.gelenk_A; s.pvv_gelenk_B = s.gelenk_B
        s.pvv_n_gelenk_A = s.n_gelenk_A; s.pvv_n_gelenk_B = s.n_gelenk_B
        s.pvv_q_gelenk_A = s.q_gelenk_A; s.pvv_q_gelenk_B = s.q_gelenk_B
    end
end

local function pvvRestoreSystem()
    for i, k in ipairs(knoten) do
        if k.pvv_lager_x ~= nil then k.lager_x = k.pvv_lager_x; k.lager_y = k.pvv_lager_y; k.lager_m = k.pvv_lager_m; k.gelenk = k.pvv_gelenk end
    end
    for i, s in ipairs(staebe) do
        if s.pvv_gelenk_A ~= nil then 
            s.gelenk_A = s.pvv_gelenk_A; s.gelenk_B = s.pvv_gelenk_B 
            s.n_gelenk_A = s.pvv_n_gelenk_A; s.n_gelenk_B = s.pvv_n_gelenk_B
            s.q_gelenk_A = s.pvv_q_gelenk_A; s.q_gelenk_B = s.pvv_q_gelenk_B
        end
    end
end

symbolischer_modus = false
sym_vars = {}
local math_funcs = {sin=1, cos=1, tan=1, sqrt=1, exp=1, ln=1, log=1, abs=1, approx=1, pi=1, e=1, x=1, asin=1, acos=1, atan=1}

local function casToNumber(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local normalized = value:gsub(",", ".")
        return tonumber(normalized)
    end
    return nil
end

local function getDummyNumeric(text)
    local has_sym = false
    -- Finde alle potenziellen Variablen im Text
    for word in string.gmatch(text, "%a[%w_]*") do
        if not math_funcs[word] then
            if not sym_vars[word] then
                sym_vars[word] = 1.0
            end
            has_sym = true
            symbolischer_modus = true
        end
    end
    
    if has_sym then
        local eval_text = string.gsub(text, "%a[%w_]*", function(word)
            if sym_vars[word] then
                if math.eval then pcall(function() math.eval("DelVar " .. word) end) end
                return "(" .. tostring(sym_vars[word]) .. ")"
            end
            return word
        end)
        
        if math.eval then
            local ok, res = pcall(function() return math.eval("approx(" .. eval_text .. ")") end)
            if ok then
                if type(res) == "number" then return res end
                if type(res) == "string" and not string.find(res, "undef") then
                    return tonumber((res:gsub(",", ".")))
                end
            end
        end
        return 1.0 
    end
    return nil
end

local function casWithDummySymbols(text)
    return (text or ""):gsub("%a[%w_]*", function(word)
        if sym_vars[word] then return "(" .. tostring(sym_vars[word]) .. ")" end
        return word
    end)
end

-- Eingabetext fuer das CAS aufbereiten: Dezimalkomma auf Klammerebene 0 -> Punkt
-- (max(1,2) bleibt), e-Notation 1e8 -> 1*10^(8) (der TI liest "e" sonst als Variable).
local function neuCasText(text)
    if type(text) ~= "string" then return text end
    local out, depth = {}, 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == "(" then depth = depth + 1 elseif ch == ")" then depth = depth - 1 end
        if ch == "," and depth <= 0 then ch = "." end
        out[#out + 1] = ch
    end
    local res = table.concat(out)
    res = res:gsub("%f[%w_%.](%d+%.?%d*)[eE]([%+%-]?%d+)%f[^%w_]", function(m, e) return m .. "*10^(" .. tonumber(e) .. ")" end)
    return res
end

local function evalInput(text, keep_str)
    if type(text) ~= "string" then return nil, text end
    local t = text:gsub(",", ".")
    local num = tonumber(t)
    if num then return num, (keep_str and text or nil) end
    
    local has_sym = false
    for word in string.gmatch(t, "%a[%w_]*") do
        if not math_funcs[word] then
            has_sym = true
            break
        end
    end
    
    if has_sym then
        local dummy = getDummyNumeric(t)
        if dummy then return dummy, text end
    end
    
    if math.eval then
        local ok, res = pcall(function() return math.eval("approx(" .. t .. ")") end)
        if ok then
            if type(res) == "number" then return res, text end
            if type(res) == "string" and not string.find(res, "undef") then
                local n = tonumber((res:gsub(",", ".")))
                if n then return n, text end
            end
        end
    end
    
    return nil, text
end

local function speichereMatrix(name, mat)
    if var and var.store then var.store(name, mat) else print("Speichern nicht möglich.") end
end

local function floatToFrac_lua(val, tol, max_denom)
    if math.abs(val) < 1e-10 then return "0" end
    local sign = val < 0 and "-" or ""
    val = math.abs(val)
    max_denom = max_denom or 10000
    
    local h1, h2 = 1, 0
    local k1, k2 = 0, 1
    local b = val
    
    for i = 1, 30 do
        local a = math.floor(b)
        local h = a * h1 + h2
        local k = a * k1 + k2
        h2, h1 = h1, h
        k2, k1 = k1, k
        
        if k > max_denom then break end
        
        if math.abs(val - h/k) <= tol + 1e-10 then
            if k == 1 then return sign .. tostring(h) end
            return sign .. tostring(h) .. "/" .. tostring(k)
        end
        
        if math.abs(b - a) < 1e-10 then break end
        b = 1 / (b - a)
    end
    return nil
end

function smartToFracStr(v, tol)
    if math.abs(v) < 1e-10 then return "0" end
    if math.abs(v - 1) < 1e-10 then return "1" end
    if math.abs(v + 1) < 1e-10 then return "-1" end
    
    if zahlenFormat ~= 3 then
        -- 1. Try a STRICT rational fraction first (to catch exact rational numbers like 0.8, 13/200, 41/200, 11/150, 77/600 etc.)
        local strict_frac = floatToFrac_lua(v, 1e-12 * math.max(1, math.abs(v)), 10000)
        if strict_frac then return strict_frac end
        
        -- 2. Try square root of a simple fraction (using a slightly looser tolerance because numeric squaring amplifies errors)
        local sq = v * v
        if zahlenFormat == 1 and sq <= 10000 then
            local sq_frac = floatToFrac_lua(sq, 1e-9 * math.max(1, sq), 2000)   -- nur echte Wurzeln, keine Naeherungen wie sqrt(21)/10 fuer 0.4583
            if sq_frac and sq_frac ~= "0" then
                local sign = v < 0 and "-" or ""
                local num_str, den_str = sq_frac:match("^(%d+)/(%d+)$")
                local num = tonumber(num_str) or tonumber(sq_frac)
                local den = tonumber(den_str) or 1
                
                if num and den then
                    local function extract_square(n)
                        for i = math.floor(math.sqrt(n)), 2, -1 do
                            if n % (i*i) == 0 then return i, n / (i*i) end
                        end
                        return 1, n
                    end
                    
                    local coeff_n, rem_n = extract_square(num)
                    local coeff_d, rem_d = extract_square(den)
                    
                    local combined_rem = rem_n * rem_d
                    local combined_den = coeff_d * rem_d
                    local final_coeff_n, final_rem = extract_square(combined_rem)
                    local total_coeff_n = coeff_n * final_coeff_n
                    
                    local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end
                    local g = gcd(total_coeff_n, combined_den)
                    total_coeff_n = total_coeff_n / g
                    combined_den = combined_den / g
                    
                    if final_rem == 1 then
                        if combined_den == 1 then return sign .. tostring(total_coeff_n) end
                        return sign .. string.format("%d/%d", total_coeff_n, combined_den)
                    end
                    
                    -- unhandliche Wurzeln (z. B. sqrt(1000127/2)) lieber als Dezimalzahl zeigen
                    if final_rem > 1000 or combined_den > 1000 then return string.format("%.4f", v) end
                    local root_str = "sqrt(" .. final_rem .. ")"
                    if total_coeff_n == 1 and combined_den == 1 then
                        return sign .. root_str
                    elseif combined_den == 1 then
                        return sign .. total_coeff_n .. "*" .. root_str
                    elseif total_coeff_n == 1 then
                        return sign .. root_str .. "/" .. combined_den
                    else
                        return sign .. total_coeff_n .. "*" .. root_str .. "/" .. combined_den
                    end
                end
                return sign .. "sqrt(" .. sq_frac .. ")"
            end
        end
        
        -- 3. If no simple strict fraction or sqrt, try loose rational fraction (using user's tol)
        -- nur kleine Nenner: mit Nennern bis 10000 wurde aus jedem irrationalen Wert ein Bruch
        local loose_frac = floatToFrac_lua(v, tol, 100)
        if loose_frac then return loose_frac end
    end
    
    -- 4. Fallback to decimal
    return string.format("%.4f", v)
end


function formatLabel(val)
    if not val then return "0" end
    return smartToFracStr(val, 10^(-(casToleranz or 5)))
end

local function fN_export(n) 
    if type(n) == "string" then return n end
    if type(n) ~= "number" then return "0" end
    
    local tol = 10^(-(casToleranz or 5))
    -- smartToFracStr handles: strict rational -> sqrt (zahlenFormat==1) -> loose rational -> decimal
    local str = smartToFracStr(n, tol)
    if str:match("^%-?%d+%.%d+$") then
        return string.format("%.8f", n)
    end
    return str
end

-- Referenzlaenge des symbolischen Modus (bestimmt in checkSymbolischerModus):
-- symbLSym ist das Laengensymbol, symbLDummy sein Zahlenwert in der numerischen Rechnung.
-- Ohne Symbol in der Geometrie gilt ein Rasterabstand als l.
symbLSym, symbLDummy = "l", 1.0
function symbLaenge(L)
    local scale = L / (symbLDummy or 1)
    if math.abs(scale - 1) < 1e-9 then return symbLSym end
    local frac = floatToFrac_lua(scale, 1e-9, 10000)
    if not frac then
        local sq = floatToFrac_lua(scale * scale, 1e-9 * scale * scale, 10000)
        if sq and sq ~= "0" then frac = "sqrt(" .. sq .. ")" end
    end
    return "(" .. (frac or fN_export(scale)) .. "*" .. symbLSym .. ")"
end

local function eval_cas_string(expr, simplifyHugeFractions)
    if not expr then return "0" end
    if not math.eval then return expr end
    local cas_cmd = "exact(expand((" .. expr .. ")))"
    if zahlenFormat == 3 then
        cas_cmd = "approx(expand((" .. expr .. ")))"
    end
    local res = math.eval("string(" .. cas_cmd .. ")")
    if type(res) == "string" then
        if res:sub(1,1) == '"' then res = res:sub(2, -2) end
        res = res:gsub(string.char(226, 136, 146), "-")
        res = res:gsub("−", "-")
        res = res:gsub("–", "-")
        res = res:gsub("—", "-")
        res = res:gsub(string.char(239, 128, 128), "E")
    end
    
    if res == nil or res == "undef" then
        return expr
    end
    
    if simplifyHugeFractions and type(res) == "string" then
        local has_huge = false
        for num in res:gmatch("%d+") do
            if #num >= 6 then has_huge = true; break end
        end
        if res:find("[eE][%-−+]?%d+") or res:find("ᴇ[%-−+]?%d+") or res:find(string.char(225, 180, 135) .. "[%-−+]?%d+") then
            has_huge = true
        end
        if has_huge then
            local approx_res = math.eval("string(approx(expand((" .. expr .. "))))")
            if approx_res == nil or approx_res == "undef" then
                approx_res = math.eval("string(approx((" .. expr .. ")))")
            end
            if approx_res ~= nil and approx_res ~= "undef" then
                if type(approx_res) == "string" then
                    if approx_res:sub(1,1) == '"' then approx_res = approx_res:sub(2, -2) end
                    approx_res = approx_res:gsub(string.char(226, 136, 146), "-")
                    approx_res = approx_res:gsub("−", "-")
                    approx_res = approx_res:gsub("–", "-")
                    approx_res = approx_res:gsub("—", "-")
                    approx_res = approx_res:gsub(string.char(225, 180, 135), "E")
                    approx_res = approx_res:gsub(string.char(239, 128, 128), "E")
                    approx_res = approx_res:gsub("á´‡", "E")
                    approx_res = approx_res:gsub("%*10%^", "E")
                    approx_res = approx_res:gsub("·10%^", "E")
                end
                
                -- Convert any resulting floats back into clean fractions using smartToFracStr
                local processFloat = function(f)
                    local clean_f = f:gsub("%s", "")
                    local val = tonumber(clean_f)
                    if not val then return f end
                    if math.abs(val) < 1e-6 then return "0" end
                    local str = smartToFracStr(val, 10^(-(casToleranz or 5)))
                    if str:sub(1,1) == "(" and str:sub(-1) == ")" then return str end
                    if str:find("sqrt") then return "(" .. str .. ")" end
                    return string.format("%.6g", val)
                end
                
                approx_res = approx_res:gsub("(%d*%.?%d*%s*[eE]%s*[+-]?%s*%d+)", processFloat)
                approx_res = approx_res:gsub("(%d+%.%d+)", processFloat)
                approx_res = approx_res:gsub("(%d+)%.0+%f[^%d]", "%1")
                
                local cleaned = math.eval("string(exact(expand((" .. approx_res .. "))))")
                if cleaned and cleaned ~= "undef" then
                    if type(cleaned) == "string" and cleaned:sub(1,1) == '"' then cleaned = cleaned:sub(2, -2) end
                    res = cleaned
                else
                    res = approx_res
                end
            end
        end
    end
    
    return res
end

-- Ist Stab s ein Bogen? Nur dann wird er in Teilstaebe zerlegt (Radius mindestens halbe Sehne);
-- ein zu kleiner Radius wird ignoriert und der Stab gerade gerechnet.
function istBogen(s)
    local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
    local L = math.sqrt(dx^2 + dy^2)
    return (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= L/2 and L > 0
end

-- Punkt (x, y) und Tangente (tx, ty) Richtung Stabende auf dem Bogen beim Winkel phi (rad) ab Stabanfang
function bogenPunkt(g, phi)
    local b = phi - g.alpha / 2
    local xl, yl = g.R * math.sin(b), g.sgn * (g.R * math.cos(b) - g.d)
    local tl, tq = math.cos(b), -g.sgn * math.sin(b)
    return g.mx + xl * g.ex - yl * g.ey, g.my + xl * g.ey + yl * g.ex, tl * g.ex - tq * g.ey, tl * g.ey + tq * g.ex
end

-- Geometrie eines Bogens (nil, wenn kein Bogen): Radius R, Sehne L, Oeffnungswinkel alpha (rad),
-- Drehsinn kappa der Tangente (= -sgn; +1 heisst mathematisch positiv im Weltsystem mit y nach unten),
-- Tangente am Anfang (cA, sA) und die Teilungspunkte pts[0..n] = { x, y, phi } mit phi = Winkel ab
-- Stabanfang (rad). Punkt 1 und n-1 liegen tangential im Abstand L_Bogen/n von den Stabenden (erstes und
-- letztes Teilstueck tangential), die uebrigen auf dem Bogen bei gleichmaessig geteilter Sehne.
function bogenGeometrie(s, n)
    if not istBogen(s) then return nil end
    local k1, k2 = knoten[s.k1], knoten[s.k2]
    local dx, dy = k2.x - k1.x, k2.y - k1.y
    local L = math.sqrt(dx^2 + dy^2)
    local R = math.abs(s.bogen_r)
    local sgn = s.bogen_r > 0 and -1 or 1
    local g = { R = R, L = L, sgn = sgn, kappa = -sgn, n = n or bogenSegmente,
        alpha = 2 * math.asin(math.min(1, L / (2 * R))), d = math.sqrt(math.max(0, R^2 - (L / 2)^2)),
        mx = (k1.x + k2.x) / 2, my = (k1.y + k2.y) / 2, ex = dx / L, ey = dy / L }
    g.cA, g.sA = select(3, bogenPunkt(g, 0))
    local cB, sB = select(3, bogenPunkt(g, g.alpha))
    local seg = R * g.alpha / g.n
    g.pts = { [0] = { x = k1.x, y = k1.y, phi = 0 }, [g.n] = { x = k2.x, y = k2.y, phi = g.alpha } }
    for j = 1, g.n - 1 do
        if j == 1 then
            g.pts[j] = { x = k1.x + seg * g.cA, y = k1.y + seg * g.sA, phi = g.alpha / g.n }
        elseif j == g.n - 1 then
            g.pts[j] = { x = k2.x - seg * cB, y = k2.y - seg * sB, phi = g.alpha - g.alpha / g.n }
        else
            local xl = (j / g.n - 0.5) * L
            local yl = sgn * (math.sqrt(R^2 - xl^2) - g.d)
            g.pts[j] = { x = k1.x + j / g.n * dx - yl * g.ey, y = k1.y + j / g.n * dy + yl * g.ex,
                phi = g.alpha / 2 + math.asin(xl / R) }
        end
    end
    return g
end

-- Winkeleinheiten des Rechners je rad (RAD 1, DEG 180/pi, GRAD 200/pi), als Zahl und als CAS-Text.
-- In dieser Einheit zaehlen x in Lastfunktionen auf Boegen und p in M_bogen_i(p).
function bogenWinkelFaktor()
    local function minusEins(w)
        local ok, v = pcall(math.eval, "approx(cos(" .. w .. "))")
        v = ok and casToNumber(v)
        return v and math.abs(v + 1) < 1e-9
    end
    if math.eval then
        if minusEins("180") then return 180 / math.pi, "(180/pi)" end
        if minusEins("200") then return 200 / math.pi, "(200/pi)" end
    end
    return 1, "1"
end

-- Lastwerte eines Bogens an den Teilungspunkten j = 0..n: q quer und n laengs je Bogenlaenge, jeweils mit
-- dem Trapezanteil q_A..q_B bzw. n_A..n_B linear ueber die Bogenlaenge; gx/gy global (bei Projektion je
-- Grundriss- bzw. Hoehenlaenge), m. Eine Lastfunktion mit x wird beim Winkel ab Stabanfang im
-- Winkelmodus des Rechners ausgewertet (x = phi * Faktor, wie p in M_bogen_i(p)).
-- w.fehler[feld] = true: das CAS konnte den Lasttext nicht auswerten (Wert 0 gesetzt).
function bogenLastWerte(s, g)
    local w, u = { fehler = {} }, nil
    local function reihe(feld)
        local r, str = {}, s[feld .. "_str"]
        if type(str) == "string" and str:hasx() then
            u = u or bogenWinkelFaktor()
            local e = casWithDummySymbols(neuCasText(str))
            for j = 0, g.n do
                local v
                if math.eval then
                    local ok, res = pcall(math.eval, "approx(" .. e:subx("(" .. string.format("%.15g", g.pts[j].phi * u) .. ")") .. ")")
                    v = ok and casToNumber(res) or nil
                end
                if not v then w.fehler[feld] = true; v = 0 end
                r[j] = v
            end
        else
            for j = 0, g.n do r[j] = s[feld] or 0 end
        end
        return r
    end
    for _, feld in ipairs({ "q", "n", "m", "gx", "gy" }) do w[feld] = reihe(feld) end
    for j = 0, g.n do
        local f = g.pts[j].phi / g.alpha
        w.q[j] = w.q[j] + (s.q_A or 0) + ((s.q_B or 0) - (s.q_A or 0)) * f
        w.n[j] = w.n[j] + (s.n_A or 0) + ((s.n_B or 0) - (s.n_A or 0)) * f
    end
    return w
end

-- Lasten der Teilstaebe k = 1..n eines Bogens (Teilstab k von Punkt k-1 nach k). Je Lastart ein lokaler
-- Trapezanteil arten[art] = { qa, qb, na, nb } (quer bzw. laengs zum Teilstab, Anfang/Ende), dazu das
-- Streckenmoment m und die Summen qa, qb, na, nb:
--   q quer zum Teilstab (radial) und n laengs (tangential) mit den Werten der Endpunkte,
--   gx/gy global, projiziert je Grundriss- bzw. Hoehenlaenge des Teilstabs,
--   m als Mittel der Endwerte.
-- Lasten je Bogenlaenge (gx/gy ohne Projektion, m) werden mit Bogenstueck/Teilstablaenge skaliert, damit
-- jeder Teilstab die Last seines Bogenstuecks traegt. q und n brauchen das nicht: eine konstante radiale
-- bzw. tangentiale Last hat auf Bogenstueck und Sehne dieselbe Resultierende.
function bogenTeilLasten(s, g, w)
    local teile = {}
    for k = 1, g.n do
        local P, Q = g.pts[k - 1], g.pts[k]
        local l = math.sqrt((Q.x - P.x)^2 + (Q.y - P.y)^2)
        local c, sv = (Q.x - P.x) / l, -(Q.y - P.y) / l   -- c_val, s_val wie in getEqQ
        local skal = g.R * (Q.phi - P.phi) / l
        local fx = s.gx_proj and math.abs(sv) or skal
        local fy = s.gy_proj and math.abs(c) or skal
        local gxa, gxb = w.gx[k - 1] * fx, w.gx[k] * fx
        local gya, gyb = w.gy[k - 1] * fy, w.gy[k] * fy
        local t = { l = l, c = c, s = sv, m = (w.m[k - 1] + w.m[k]) / 2 * skal, arten = {
            q = { w.q[k - 1], w.q[k], 0, 0 },
            n = { 0, 0, w.n[k - 1], w.n[k] },
            gx = { gxa * sv, gxb * sv, gxa * c, gxb * c },
            gy = { gya * c, gyb * c, -gya * sv, -gyb * sv } } }
        local sum = { 0, 0, 0, 0 }
        for _, art in ipairs({ "q", "n", "gx", "gy" }) do
            for i = 1, 4 do sum[i] = sum[i] + t.arten[art][i] end
        end
        t.qa, t.qb, t.na, t.nb = sum[1], sum[2], sum[3], sum[4]
        teile[k] = t
    end
    return teile
end

-- Hat der Bogen eine Last zwischen den Enden (Strecken-, Trapez-, globale Linien- oder Momentenlast)?
-- Temperatur zaehlt nicht: sie erzeugt keine Kraefte zwischen den Enden.
function bogenHatLast(s)
    for _, f in ipairs({ "q", "q_A", "q_B", "n", "n_A", "n_B", "m", "gx", "gy" }) do
        if math.abs(s[f] or 0) > 1e-12 then return true end
    end
    for _, f in ipairs({ "q_str", "n_str", "m_str", "gx_str", "gy_str" }) do
        if type(s[f]) == "string" and s[f]:hasx() then return true end
    end
    return false
end

-- Stuetzwerte der Lastfunktionen eines Bogens fuer die Lastzeichnung, je 11 Werte bei den Winkeln
-- j/10*alpha (x = Winkel ab Stabanfang im Winkelmodus des Rechners). Wie bei geraden Staeben: q_pts = ganze
-- Querlast (mit Trapez), n_pts, m_pts, gx_pts, gy_pts nur der Anteil der Lastfunktion; nil ohne Funktion.
-- Die Integral-Stuetzwerte gerader Staebe (Q_cas_pts ...) entfallen, die Bogendiagramme kommen aus der FEM.
function bogenLastPunkte(s, g)
    s.q_pts, s.n_pts, s.m_pts, s.gx_pts, s.gy_pts = nil, nil, nil, nil, nil
    s.Q_cas_pts, s.M_cas_pts, s.v_cas_pts_EI, s.N_cas_pts, s.u_cas_pts_EA = nil, nil, nil, nil, nil
    s.q_in_cas, s.n_in_cas = false, false
    local h = { n = 10, alpha = g.alpha, pts = {} }
    for j = 0, 10 do h.pts[j] = { phi = g.alpha * j / 10 } end
    local w = bogenLastWerte(s, h)
    local function liste(feld, abzug)
        if not (type(s[feld .. "_str"]) == "string" and s[feld .. "_str"]:hasx()) then return nil end
        local r = {}
        for j = 0, 10 do r[j + 1] = w[feld][j] - (abzug and abzug(j / 10) or 0) end
        return r
    end
    s.q_pts = liste("q")
    s.n_pts = liste("n", function(f) return (s.n_A or 0) + ((s.n_B or 0) - (s.n_A or 0)) * f end)
    s.m_pts, s.gx_pts, s.gy_pts = liste("m"), liste("gx"), liste("gy")
end

-- Resultierende der Lasten auf einem Bogen je Lastart (q, n, gx, gy, m) und gesamt (summe), aus den
-- Teilstablasten wie in der FEM: { Fx, Fy, M } global (y nach unten), M um den Stabanfang gegen den
-- Uhrzeigersinn. nil, wenn s kein Bogen ist.
function bogenLastResultierende(s)
    local g = bogenGeometrie(s)
    if not g then return nil end
    local teile = bogenTeilLasten(s, g, bogenLastWerte(s, g))
    local k1 = knoten[s.k1]
    local res = {}
    for _, art in ipairs({ "q", "n", "gx", "gy", "m", "summe" }) do res[art] = { 0, 0, 0 } end
    local function dazu(art, Fx, Fy, M)
        for _, r in ipairs({ res[art], res.summe }) do r[1] = r[1] + Fx; r[2] = r[2] + Fy; r[3] = r[3] + M end
    end
    for k, t in ipairs(teile) do
        local P = g.pts[k - 1]
        local tx, ty = t.c, -t.s
        local dx, dy = P.x - k1.x, P.y - k1.y
        for _, art in ipairs({ "q", "n", "gx", "gy" }) do
            local a = t.arten[art]
            local Fq, Fn = t.l * (a[1] + a[2]) / 2, t.l * (a[3] + a[4]) / 2
            local Fx, Fy = -Fq * ty + Fn * tx, Fq * tx + Fn * ty
            -- Moment um k1 (gegen den Uhrzeigersinn) plus Hebel der Querlast entlang des Teilstabs
            dazu(art, Fx, Fy, (dy * Fx - dx * Fy) - t.l^2 * (a[1] + 2 * a[2]) / 6)
        end
        dazu("m", 0, 0, t.m * t.l)
    end
    return res
end

-- Ist das System berechnet? Boegen haben danach keine eigene Steifigkeitsmatrix (die steckt in ihren
-- Teilstaeben), deshalb zaehlt jeder Stab mit Ergebnis und nicht nur Stab 1.
function exportBereit()
    for _, s in ipairs(staebe) do
        if s.mat_k or s.arc_plot_data then return true end
    end
    return false
end

-- Lastanteile der Bogen-Schnittgroessen beim Schnitt p (CAS-Texte dN, dQ, dM; nil ohne Last). Die Last auf
-- dem Bogenstueck 0..p wird ueber t integriert, p und t im Winkelmodus des Rechners (u Einheiten je rad,
-- Bogenlaenge ds = R/u dt). Mit kappa = -sgn (Drehsinn der Tangente) und th(t) = Tangentenwinkel:
--   dN = -R/u int( kappa*q*sin(p-t) + n*cos(p-t) + Gx*cos th(p) + Gy*sin th(p) )
--   dQ = -R/u int( q*cos(p-t) - kappa*n*sin(p-t) - Gx*sin th(p) + Gy*cos th(p) )
--   dM = -R/u int( R*q*sin(p-t) - kappa*R*n*(1-cos(p-t))
--                  - kappa*R*((sin th(t)-sin th(p))*Gy + (cos th(t)-cos th(p))*Gx) + m )
-- q quer, n laengs (je Bogenlaenge, Trapez linear in t, Lastfunktion mit x = t), Gx/Gy global je
-- Bogenlaenge (projiziert mal |sin th| bzw. |cos th|), m Streckenmoment (gegen den Uhrzeigersinn).
-- Das ist das Gleichgewicht am exakten Kreisbogen; die Werte am Bogenanfang stammen aus der FEM.
function bogenExportLast(s)
    if not bogenHatLast(s) then return nil end
    local g = bogenGeometrie(s)
    if not g then return nil end
    local fN = fN_export
    local u, u_str = bogenWinkelFaktor()
    local kap, R = g.kappa, g.R
    local function zahl(v) return string.format("%.15g", v) end
    -- Lasttext je Bogenlaenge: Lastfunktion mit x = t oder Zahl, dazu das Trapez A..B linear in t
    local function lastText(feld, A, B)
        local teile, str = {}, s[feld .. "_str"]
        if type(str) == "string" and str:hasx() then
            teile[#teile + 1] = "(" .. casWithDummySymbols(neuCasText(str)):subx("(t)") .. ")"
        elseif math.abs(s[feld] or 0) > 1e-12 then
            teile[#teile + 1] = fN(s[feld])
        end
        if A and (math.abs(A) > 1e-12 or math.abs(B) > 1e-12) then
            teile[#teile + 1] = "(" .. fN(A) .. "+(" .. fN(B - A) .. ")*t/(" .. zahl(g.alpha * u) .. "))"
        end
        return #teile > 0 and ("(" .. table.concat(teile, "+") .. ")") or nil
    end
    local q = lastText("q", s.q_A or 0, s.q_B or 0)
    local n = lastText("n", s.n_A or 0, s.n_B or 0)
    local gx, gy, m = lastText("gx"), lastText("gy"), lastText("m")
    -- Tangentenwinkel th(v) = thA + kappa*v: cos/sin ueber die Tangente am Anfang (cA, sA), damit nur
    -- Winkelfunktionen von p bzw. t vorkommen (richtig in jedem Winkelmodus)
    local function cosTh(v) return "(" .. fN(g.cA) .. "*cos(" .. v .. ")-(" .. fN(kap * g.sA) .. ")*sin(" .. v .. "))" end
    local function sinTh(v) return "(" .. fN(g.sA) .. "*cos(" .. v .. ")+(" .. fN(kap * g.cA) .. ")*sin(" .. v .. "))" end
    -- Projektion je Bogenlaenge: |sin th| (gx) bzw. |cos th| (gy); abs nur, wenn das Vorzeichen wechselt
    local thA = math.atan2(g.sA, g.cA)
    local function projektion(f, text)
        local pos, neg = false, false
        for j = 0, 64 do
            local v = f(thA + kap * g.alpha * j / 64)
            if v > 1e-9 then pos = true elseif v < -1e-9 then neg = true end
        end
        if pos and neg then return "abs(" .. text .. ")" end
        return neg and ("(-" .. text .. ")") or text
    end
    if gx and s.gx_proj then gx = "(" .. gx .. "*" .. projektion(math.sin, sinTh("t")) .. ")" end
    if gy and s.gy_proj then gy = "(" .. gy .. "*" .. projektion(math.cos, cosTh("t")) .. ")" end
    local kR = fN(kap * R)
    local IN, IQ, IM = {}, {}, {}
    if q then
        IN[#IN + 1] = "(" .. fN(kap) .. ")*" .. q .. "*sin(p-t)"
        IQ[#IQ + 1] = q .. "*cos(p-t)"
        IM[#IM + 1] = "(" .. fN(R) .. ")*" .. q .. "*sin(p-t)"
    end
    if n then
        IN[#IN + 1] = n .. "*cos(p-t)"
        IQ[#IQ + 1] = "-(" .. fN(kap) .. ")*" .. n .. "*sin(p-t)"
        IM[#IM + 1] = "-(" .. kR .. ")*" .. n .. "*(1-cos(p-t))"
    end
    if gx then
        IN[#IN + 1] = gx .. "*" .. cosTh("p")
        IQ[#IQ + 1] = "-" .. gx .. "*" .. sinTh("p")
        IM[#IM + 1] = "-(" .. kR .. ")*(" .. cosTh("t") .. "-" .. cosTh("p") .. ")*" .. gx
    end
    if gy then
        IN[#IN + 1] = gy .. "*" .. sinTh("p")
        IQ[#IQ + 1] = gy .. "*" .. cosTh("p")
        IM[#IM + 1] = "-(" .. kR .. ")*(" .. sinTh("t") .. "-" .. sinTh("p") .. ")*" .. gy
    end
    if m then IM[#IM + 1] = m end
    local function integral(liste)
        if #liste == 0 then return nil end
        return "-(" .. fN(R) .. ")/" .. u_str .. "*integral(" .. table.concat(liste, "+") .. ",t,0,p)"
    end
    return integral(IN), integral(IQ), integral(IM)
end

-- Schnittgroessen eines Bogens ueber den Winkel p ab Stabanfang (im Winkelmodus des Rechners):
-- M_bogen_i(p), N_bogen_i(p), q_bogen_i(p) aus den Kraeften am Bogenanfang (das erste Teilstueck liegt
-- tangential, die Werte sind also die am Bogen) plus dem Anteil der Last auf dem Bogenstueck 0..p
-- (bogenExportLast). Rueckgabe: Oeffnungswinkel in Grad, nil wenn kein Bogen oder nicht berechnet.
function exportBogenSchnittkraefteToTI(i)
    local s = staebe[i]
    if not istBogen(s) or not s.arc_plot_data then return nil end
    local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
    local L = math.sqrt(dx^2 + dy^2)
    local fN = fN_export
    local R = math.abs(s.bogen_r)
    local sgn = s.bogen_r > 0 and -1 or 1
    local NA = s.arc_N_A or 0
    local VA = s.arc_V_A or 0
    local MA = s.arc_M_A or 0

    local expr_M = fN(MA) .. " + " .. fN(VA*R) .. "*sin(p) + " .. fN(sgn*NA*R) .. "*(1-cos(p))"
    local expr_N = fN(NA) .. "*cos(p) - " .. fN(sgn*VA) .. "*sin(p)"
    local expr_V = fN(sgn*NA) .. "*sin(p) + " .. fN(VA) .. "*cos(p)"
    local lastN, lastV, lastM = bogenExportLast(s)
    if lastN then expr_N = expr_N .. " + (" .. lastN .. ")" end
    if lastV then expr_V = expr_V .. " + (" .. lastV .. ")" end
    if lastM then expr_M = expr_M .. " + (" .. lastM .. ")" end

    if math.eval then
        math.eval("M_bogen" .. i .. "(p) := " .. eval_cas_string(expr_M, true))
        math.eval("N_bogen" .. i .. "(p) := " .. eval_cas_string(expr_N, true))
        math.eval("q_bogen" .. i .. "(p) := " .. eval_cas_string(expr_V, true))
        print("-> Bogen " .. i .. " (M, N, Q in Abh. v. Winkel p) exportiert!")
    end
    return math.deg(2 * math.asin(math.min(1, L / (2 * R))))
end

local function exportStabToTI(i)
    local s = staebe[i]
    if s.mat_k then
        speichereMatrix("stab" .. i .. "_k", s.mat_k)
        speichereMatrix("stab" .. i .. "_p", s.mat_p)
        speichereMatrix("stab" .. i .. "_v", s.mat_v)
    end

    if istBogen(s) then
        exportBogenSchnittkraefteToTI(i)
    elseif s.mat_k then
        exportSchnittkraefteToTI(i)
        exportBiegelinienToTI(i)
        exportULinienToTI(i)
        print("-> Daten von Stab " .. i .. " in TI exportiert!")
    end
end

local function exportKnotenToTI(i)
    local k = knoten[i]
    if k.mat_pv then speichereMatrix("knot" .. i .. "_pv", k.mat_pv) end
end

local function exportAllToTI()
    if not exportBereit() then zeigeMeldung("Bitte zuerst das System berechnen (Taste B).", "Export fehlgeschlagen"); return end
    for i = 1, #staebe do exportStabToTI(i) end
    for i = 1, #knoten do exportKnotenToTI(i) end
    if glob_K and glob_F and glob_u then
        speichereMatrix("sys_k", glob_K); local mat_F, mat_u = {}, {}
        for i = 1, anzahlGleichungen do mat_F[i] = {glob_F[i] or 0}; mat_u[i] = {glob_u[i] or 0} end
        if anzahlGleichungen > 0 then speichereMatrix("sys_f", mat_F); speichereMatrix("sys_u", mat_u) end
    end
    zeigeMeldung("Matrizen und Systemdaten exportiert.", "Export")
end

-- Globale Linienlast p_X ("gx") bzw. p_Y ("gy") als Text in der Stabkoordinate x (0..L) und der
-- Projektionsfaktor f (Kraft je Stablaenge = Last * f). Projiziert (Last je Hoehen- bzw.
-- Grundrisslaenge) zaehlt die Laufvariable der Eingabe entlang der globalen Achse ab dem
-- Stabanfang: p_X senkrecht (0..|dy|), p_Y waagerecht (0..|dx|), also x_global = x * f.
-- Nicht projiziert laeuft sie entlang der Stabachse (0..L).
function globaleLinienlast(s, typ)
    local str = s[typ .. "_str"] or "0"
    local k1, k2 = knoten[s.k1], knoten[s.k2]
    local L = math.sqrt((k2.x - k1.x)^2 + (k2.y - k1.y)^2)
    if not s[typ .. "_proj"] or L <= 0 then return str, 1 end
    local f = (typ == "gx") and math.abs(k2.y - k1.y) / L or math.abs(k2.x - k1.x) / L
    if str:hasx() then str = str:subx("(x*" .. string.format("%.15g", f) .. ")") end
    return str, f
end

local function getEqQ(s, L, fN, L_str)
    local c_val = (knoten[s.k2].x - knoten[s.k1].x) / L
    local s_val = -(knoten[s.k2].y - knoten[s.k1].y) / L
    local f_gx = s.gx_proj and math.abs(s_val) or 1
    local f_gy = s.gy_proj and math.abs(c_val) or 1
    local T = neuCasText
    local gx_str, gy_str = globaleLinienlast(s, "gx"), globaleLinienlast(s, "gy")
    local base = "("..T(s.q_str or "0")..") + ("..T(gx_str)..")*"..fN(f_gx * s_val).." + ("..T(gy_str)..")*"..fN(f_gy * c_val)
    if L_str and (s.q_A_str or s.q_B_str) then
        base = base .. " + ("..T(s.q_A_str or "0")..") + (("..T(s.q_B_str or "0")..")-("..T(s.q_A_str or "0").."))*x/("..L_str..")"
    end
    return base
end

local function getEqN(s, L, fN, L_str)
    local c_val = (knoten[s.k2].x - knoten[s.k1].x) / L
    local s_val = -(knoten[s.k2].y - knoten[s.k1].y) / L
    local f_gx = s.gx_proj and math.abs(s_val) or 1
    local f_gy = s.gy_proj and math.abs(c_val) or 1
    local gx_str, gy_str = globaleLinienlast(s, "gx"), globaleLinienlast(s, "gy")
    local base = "("..neuCasText(s.n_str or "0")..") + ("..neuCasText(gx_str)..")*"..fN(f_gx * c_val).." - ("..neuCasText(gy_str)..")*"..fN(f_gy * s_val)
    if L_str and (s.n_A_str or s.n_B_str) then
        base = base .. " + ("..neuCasText(s.n_A_str or "0")..") + (("..neuCasText(s.n_B_str or "0")..")-("..neuCasText(s.n_A_str or "0").."))*x/("..L_str..")"
    end
    return base
end

exportSchnittkraefteToTI = function(stab_index)
    if not exportBereit() then
        if not stab_index then zeigeMeldung("Bitte zuerst das System berechnen (Taste B).", "Export fehlgeschlagen") end
        return
    end
    if math.eval then
        local fN = fN_export
        local boegen = {}

        local start_i = stab_index or 1
        local end_i = stab_index or #staebe
        for i = start_i, end_i do
            local s = staebe[i]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2 + dy^2)
            local winkel = istBogen(s) and exportBogenSchnittkraefteToTI(i)
            if winkel then
                boegen[#boegen + 1] = string.format("Stab %d: p von 0 bis %g Grad", i, math.floor(winkel * 100 + 0.5) / 100)
            elseif L > 0 and not istBogen(s) then
                local N0 = symbolischer_modus and ("-(" .. (s.symb_start.N or "0") .. ")") or fN(-s.s_local[1])
                local Q0 = symbolischer_modus and ("-(" .. (s.symb_start.V or "0") .. ")") or fN(-s.s_local[2])
                local M0 = symbolischer_modus and ("-(" .. (s.symb_start.M or "0") .. ")") or fN(-s.s_local[3])
                
                local L_str = "(" .. fN(L) .. ")"
                if symbolischer_modus then
                    L_str = symbLaenge(L)
                end
                
                local eq_q = getEqQ(s, L, fN, L_str)
                local eq_n = getEqN(s, L, fN, L_str)
                local use_cas_q = symbolischer_modus or string.hasx(eq_q)
                local use_cas_n = symbolischer_modus or string.hasx(eq_n)
                local use_cas_m = symbolischer_modus or (s.m_str and string.hasx(s.m_str))
                
                local c_val, s_val = dx/L, -dy/L
                local eff_gx = (s.gx or 0) * (s.gx_proj and math.abs(s_val) or 1)
                local eff_gy = (s.gy or 0) * (s.gy_proj and math.abs(c_val) or 1)
                local n_add = eff_gx * c_val - eff_gy * s_val
                local q_add = eff_gx * s_val + eff_gy * c_val
                local qA, qB = s.q + s.q_A + q_add, s.q + s.q_B + q_add
                local nA, nB = s.n + s.n_A + n_add, s.n + s.n_B + n_add
                
                local expr_N = ""
                if use_cas_n then
                    expr_N = N0 .. " - integral(("..eq_n:subx("t").."),t,0,x)"
                else
                    expr_N = N0 .. " - ("..fN(nA).."*x + ("..fN(nB).."-"..fN(nA)..")*x^2/(2*"..L_str.."))"
                end
                
                local expr_Q = ""
                if use_cas_q then
                    expr_Q = Q0 .. " - integral(("..eq_q:subx("t").."),t,0,x)"
                else
                    expr_Q = Q0 .. " - ("..fN(qA).."*x + ("..fN(qB).."-"..fN(qA)..")*x^2/(2*"..L_str.."))"
                end
                
                local expr_M = M0 .. " + " .. Q0 .. "*x - " .. fN(s.m) .. "*x"
                if use_cas_q then
                    expr_M = expr_M .. " - integral(("..eq_q:subx("t")..")*(x-t),t,0,x)"
                else
                    expr_M = expr_M .. " - ("..fN(qA).."*x^2/2 + ("..fN(qB).."-"..fN(qA)..")*x^3/(6*"..L_str.."))"
                end
                
                if use_cas_m then
                    expr_M = expr_M .. " - integral(("..s.m_str:subx("t").."),t,0,x)"
                end
                
                math.eval("N_stab" .. i .. "(x) := " .. eval_cas_string(expr_N, true))
                math.eval("Q_stab" .. i .. "(x) := " .. eval_cas_string(expr_Q, true))
                math.eval("M_stab" .. i .. "(x) := " .. eval_cas_string(expr_M, true))
            end
        end
        -- nur melden, wenn der Export aus dem Menue kommt (intern je Stab: precalcSymbolicLabels)
        if not stab_index and #boegen > 0 then
            zeigeMeldung("Schnittkraftverlaeufe exportiert: N_stab_i(x), Q_stab_i(x), M_stab_i(x); Boegen: N_bogen_i(p), q_bogen_i(p), M_bogen_i(p) ueber den Winkel p ab Stabanfang (Winkelmodus des Rechners). "
                .. table.concat(boegen, ", ") .. ".", "Export")
        elseif not stab_index then zeigeMeldung("Analytische Schnittkraftverlaeufe (N, Q, M) exportiert.", "Export")
        else print("-> Analytische Schnittkraftverlaeufe (N, Q, M) exportiert!") end
    end
end

local function floatToFracStr(v)
    local str = smartToFracStr(v, 10^(-(casToleranz or 5)))
    -- floatToFracStr is usually used in contexts where we don't necessarily want parentheses around everything
    -- But since smartToFracStr returns (x) for fractions and sqrt(x) for roots, we can return it as-is.
    return str
end

local function precalcSymbolicLabels()
    if not symbolischer_modus or not math.eval then return end
    local fN = fN_export
    for i = 1, #staebe do exportSchnittkraefteToTI(i) end
    
    for i, s in ipairs(staebe) do
        local dx = knoten[s.k2].x - knoten[s.k1].x
        local dy = knoten[s.k2].y - knoten[s.k1].y
        local L = math.sqrt(dx*dx + dy*dy)
        local pts = 100
        local max_M, max_Q, max_N = 0, 0, 0
        local t_M, t_Q, t_N = 0.5, 0.5, 0.5
        
        local c_val, s_val = dx/L, -dy/L
        local eff_gx = (s.gx or 0) * (s.gx_proj and math.abs(s_val) or 1); local eff_gy = (s.gy or 0) * (s.gy_proj and math.abs(c_val) or 1)
        local n_add = eff_gx * c_val - eff_gy * s_val; local q_add = eff_gx * s_val + eff_gy * c_val
        local N0, Q0, M0 = -(s.s_local[1] or 0), -(s.s_local[2] or 0), -(s.s_local[3] or 0)
        local qA, qB = s.q + s.q_A + q_add, s.q + s.q_B + q_add; local nA, nB = s.n + s.n_A + n_add, s.n + s.n_B + n_add
        if s.q_in_cas then qA, qB = 0, 0 end; if s.n_in_cas then nA, nB = 0, 0 end -- sonst doppelt zu cas_*_drop

        local has_cas_pts = (s.M_cas_pts and #s.M_cas_pts > 0) or (s.N_cas_pts and #s.N_cas_pts > 0)
        for j = 0, pts do
            local t = j / pts
            -- CAS-Stuetzwerte liegen nur auf dem ptsBiegelinie-Raster: dort auswerten
            local jc = math.floor(t * ptsBiegelinie + 0.5)
            if has_cas_pts then t = jc / ptsBiegelinie end
            local x = t * L
            local cas_Q_drop = (s.Q_cas_pts and s.Q_cas_pts[jc+1]) or 0
            local cas_M_drop = (s.M_cas_pts and s.M_cas_pts[jc+1]) or 0
            local cas_N_drop = (s.N_cas_pts and s.N_cas_pts[jc+1]) or 0

            local val_M = M0 + Q0*x - (s.m or 0)*x - (qA*(x^2)/2 + (qB-qA)*(x^3)/(6*L)) - cas_M_drop
            local val_Q = Q0 - (qA*x + (qB-qA)*(x^2)/(2*L)) - cas_Q_drop
            local val_N = N0 - (nA*x + (nB-nA)*(x^2)/(2*L)) - cas_N_drop
            
            if math.abs(val_M) > math.abs(max_M) then max_M = val_M; t_M = t end
            if math.abs(val_Q) > math.abs(max_Q) then max_Q = val_Q; t_Q = t end
            if math.abs(val_N) > math.abs(max_N) then max_N = val_N; t_N = t end
        end
        
        local function refine_t(t_guess, poly_type)
            local best_t = t_guess
            local m_val = -1
            for step = -500, 500 do
                local t = t_guess + step * 0.00002
                if t >= 0 and t <= 1 then
                    local x = t * L
                    local val = 0
                    if poly_type == "M" then
                        val = M0 + Q0*x - (s.m or 0)*x - (qA*(x^2)/2 + (qB-qA)*(x^3)/(6*L))
                    elseif poly_type == "Q" then
                        val = Q0 - (qA*x + (qB-qA)*(x^2)/(2*L))
                    elseif poly_type == "N" then
                        val = N0 - (nA*x + (nB-nA)*(x^2)/(2*L))
                    end
                    if math.abs(val) > m_val then
                        m_val = math.abs(val)
                        best_t = t
                    end
                end
            end
            return best_t
        end
        
        -- Die Verfeinerung kennt nur das klassische Polynom; mit CAS-Lastanteil Rasterwert behalten
        if not has_cas_pts then
            t_M = refine_t(t_M, "M")
            t_Q = refine_t(t_Q, "Q")
            t_N = refine_t(t_N, "N")
        end
        
        local function fixT(t)
            if math.abs(t) < 1e-4 then return "0" end
            if math.abs(t - 1) < 1e-4 then return "1" end
            if math.abs(t - 1/math.sqrt(3)) < 1e-4 then return "(1/sqrt(3))" end
            if math.abs(t - (1 - 1/math.sqrt(3))) < 1e-4 then return "(1 - 1/sqrt(3))" end
            return fN(t)
        end
        
        local L_str = symbLaenge(L)
        
        -- Da das CAS bei Integralen mit symbolischen Grenzen (z.B. L) in Lua oft "Domain Warnings" wirft
        -- und deshalb 'nil' zurückgibt, bauen wir für diese UI-Labels das Polynom direkt auf.
        -- So umgehen wir das Integral bei der reinen Text-Auswertung für das Diagramm.
        local f_gx = s.gx_proj and math.abs(s_val) or 1
        local f_gy = s.gy_proj and math.abs(c_val) or 1
        
        local q_const_sym = "("..(s.q_str or fN(s.q or 0))..") + ("..(s.gx_str or fN(s.gx or 0))..")*"..fN(f_gx * s_val).." + ("..(s.gy_str or fN(s.gy or 0))..")*"..fN(f_gy * c_val)
        local qA_sym = q_const_sym .. " + ("..(s.q_A_str or fN(s.q_A or 0))..")"
        local qB_sym = q_const_sym .. " + ("..(s.q_B_str or fN(s.q_B or 0))..")"
        local m_sym = s.m_str or fN(s.m or 0)
        
        local n_const_sym = "("..(s.n_str or fN(s.n or 0))..") + ("..(s.gx_str or fN(s.gx or 0))..")*"..fN(f_gx * c_val).." - ("..(s.gy_str or fN(s.gy or 0))..")*"..fN(f_gy * s_val)
        local nA_sym = n_const_sym .. " + ("..(s.n_A_str or fN(s.n_A or 0))..")"
        local nB_sym = n_const_sym .. " + ("..(s.n_B_str or fN(s.n_B or 0))..")"
        
        local N0_str = symbolischer_modus and ("-(" .. (s.symb_start.N or "0") .. ")") or fN(-s.s_local[1])
        local Q0_str = symbolischer_modus and ("-(" .. (s.symb_start.V or "0") .. ")") or fN(-s.s_local[2])
        local M0_str = symbolischer_modus and ("-(" .. (s.symb_start.M or "0") .. ")") or fN(-s.s_local[3])
        
        local function evalPoly(poly_type, t)
            local c_t = fixT(t)
            
            local expr = ""
            if poly_type == "M" then
                expr = M0_str .. " + " .. Q0_str .. "*" .. c_t .. "*" .. L_str .. " - (" .. qA_sym .. ")*((" .. c_t .. ")^2/2)*(" .. L_str .. ")^2 - ((" .. qB_sym .. ")-(" .. qA_sym .. "))*((" .. c_t .. ")^3/6)*(" .. L_str .. ")^2 - (" .. m_sym .. ")*" .. c_t .. "*" .. L_str
            elseif poly_type == "Q" then
                expr = Q0_str .. " - (" .. qA_sym .. ")*" .. c_t .. "*" .. L_str .. " - ((" .. qB_sym .. ")-(" .. qA_sym .. "))*((" .. c_t .. ")^2/2)*" .. L_str
            elseif poly_type == "N" then
                expr = N0_str .. " - (" .. nA_sym .. ")*" .. c_t .. "*" .. L_str .. " - ((" .. nB_sym .. ")-(" .. nA_sym .. "))*((" .. c_t .. ")^2/2)*" .. L_str
            end
            
            return eval_cas_string(expr, true)
        end
        
        s.symb_M_start = evalPoly("M", 0)
        s.symb_M_end   = evalPoly("M", 1)
        s.symb_M_max   = evalPoly("M", t_M)
        
        s.symb_Q_start = evalPoly("Q", 0)
        s.symb_Q_end   = evalPoly("Q", 1)
        s.symb_Q_max   = evalPoly("Q", t_Q)
        
        s.symb_N_start = evalPoly("N", 0)
        s.symb_N_end   = evalPoly("N", 1)
        s.symb_N_max   = evalPoly("N", t_N)
        
        local orig_dx = knoten[s.k2].x - knoten[s.k1].x
        local orig_dy = knoten[s.k2].y - knoten[s.k1].y
        local orig_L = math.sqrt(orig_dx^2 + orig_dy^2)
        local cA = orig_L > 0 and orig_dx/orig_L or 1
        local sA = orig_L > 0 and orig_dy/orig_L or 0
        
        local cA_s = floatToFracStr(cA)
        local sA_s = floatToFracStr(sA)
        
        s.symb_Fx_a = eval_cas_string("-(" .. s.symb_N_start .. ")*(" .. cA_s .. ") + (" .. s.symb_Q_start .. ")*(" .. sA_s .. ")", true)
        s.symb_Fy_a = eval_cas_string("-(" .. s.symb_N_start .. ")*(" .. sA_s .. ") - (" .. s.symb_Q_start .. ")*(" .. cA_s .. ")", true)
        s.symb_Fx_b = eval_cas_string("(" .. s.symb_N_end .. ")*(" .. cA_s .. ") - (" .. s.symb_Q_end .. ")*(" .. sA_s .. ")", true)
        s.symb_Fy_b = eval_cas_string("(" .. s.symb_N_end .. ")*(" .. sA_s .. ") + (" .. s.symb_Q_end .. ")*(" .. cA_s .. ")", true)
        
        s.symb_Fx_a_disp = eval_cas_string("-(" .. (s.symb_Fx_a or "0") .. ")", true)
        s.symb_Fy_a_disp = eval_cas_string("-(" .. (s.symb_Fy_a or "0") .. ")", true)
        s.symb_Ma_disp = eval_cas_string("-(" .. (s.symb_M_start or "0") .. ")", true)
        s.symb_Mb_disp = eval_cas_string(s.symb_M_end or "0", true)
    end
    
    for i, k in ipairs(knoten) do
        local rx_terms, ry_terms, rm_terms = {}, {}, {}
        for _, s in ipairs(staebe) do
            if s.k1 == i then
                table.insert(rx_terms, s.symb_Fx_a or "0")
                table.insert(ry_terms, s.symb_Fy_a or "0")
                table.insert(rm_terms, string.format("-(%s)", s.symb_M_start or "0"))
            elseif s.k2 == i then
                table.insert(rx_terms, s.symb_Fx_b or "0")
                table.insert(ry_terms, s.symb_Fy_b or "0")
                table.insert(rm_terms, s.symb_M_end or "0")
            end
        end
        k.symb_Rx = #rx_terms > 0 and eval_cas_string(table.concat(rx_terms, " + "), true) or "0"
        k.symb_Ry = #ry_terms > 0 and eval_cas_string(table.concat(ry_terms, " + "), true) or "0"
        k.symb_Rm = #rm_terms > 0 and eval_cas_string(table.concat(rm_terms, " + "), true) or "0"
        
        local r = math.rad(k.winkel or 0)
        local c, s_val = math.cos(r), math.sin(r)
        local c_s, s_s = floatToFracStr(c), floatToFracStr(s_val)
        k.symb_R_xi = eval_cas_string("(" .. k.symb_Rx .. ")*(" .. c_s .. ") - (" .. k.symb_Ry .. ")*(" .. s_s .. ")", true)
        k.symb_R_eta = eval_cas_string("-(" .. k.symb_Rx .. ")*(" .. s_s .. ") - (" .. k.symb_Ry .. ")*(" .. c_s .. ")", true)
    end
    print("precalcSymbolicLabels completed")
end

exportBiegelinienToTI = function(stab_index)
    if not exportBereit() then zeigeMeldung("Bitte zuerst das System berechnen (Taste B).", "Export fehlgeschlagen"); return end
    if math.eval then
        local fN = fN_export
        
        local start_i = stab_index or 1
        local end_i = stab_index or #staebe
        for i = start_i, end_i do
            local s = staebe[i]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 and not istBogen(s) then
                local EI = stabEI(s)
                local qA, qB = s.q_A, s.q_B 
                local va = (math.abs(s.v_local[2] or 0) < 1e-12) and 0 or s.v_local[2]
                local phia = (math.abs(s.v_local[3] or 0) < 1e-12) and 0 or s.v_local[3]
                local vb = (math.abs(s.v_local[5] or 0) < 1e-12) and 0 or s.v_local[5]
                local phib = (math.abs(s.v_local[6] or 0) < 1e-12) and 0 or s.v_local[6]
                
                local L_str = "(" .. fN(L) .. ")"
                if symbolischer_modus then
                    L_str = symbLaenge(L)
                end
                
                local eq_q = getEqQ(s, L, fN, L_str)
                local use_cas_q = symbolischer_modus or string.hasx(eq_q)
                local use_cas_m = symbolischer_modus or (s.m_str and string.hasx(s.m_str))
                
                local v_L_last = 0
                local phi_L_last = 0
                local v_last_expr = ""
                local v_L_last_symb = "0"
                local phi_L_last_symb = "0"
                
                if use_cas_q or symbolischer_modus then
                    local q_t = eq_q:subx("t")
                    v_last_expr = "integral(("..q_t..")*(x-t)^3,t,0,x)/6"
                    v_L_last_symb = v_L_last_symb .. " + integral(("..q_t..")*("..L_str.."-t)^3,t,0,"..L_str..")/6"
                    if not symbolischer_modus then
                        v_L_last = v_L_last + (casToNumber(math.eval("approx(integral(("..q_t..")*("..L_str.."-t)^3,t,0,"..L_str..")/6)")) or 0)
                        phi_L_last = phi_L_last + (casToNumber(math.eval("approx(integral(("..q_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2)")) or 0)
                    end
                    phi_L_last_symb = phi_L_last_symb .. " + integral(("..q_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2"
                else
                    local alg_q = s.q + (s.gx or 0) * (s.gx_proj and math.abs(-dy/L) or 1) * (-dy/L) + (s.gy or 0) * (s.gy_proj and math.abs(dx/L) or 1) * (dx/L)
                    qA, qB = qA + alg_q, qB + alg_q
                    v_last_expr = "("..fN(qA).."/24)*x^4 + (("..fN(qB).."-"..fN(qA)..")/(120*"..L_str.."))*x^5"
                    v_L_last = v_L_last + (4*qA + qB) / 120 * (L^4)
                    phi_L_last = phi_L_last + (3*qA + qB) / 24 * (L^3)
                end
                
                if use_cas_m then
                    local m_t = s.m_str:subx("t")
                    -- EI*w'''' = q + m'  ->  EI*w enthaelt +int m(t)*(x-t)^2/2 dt (Vorzeichen wie M' = Q - m)
                    v_last_expr = v_last_expr .. " + integral(("..m_t..")*(x-t)^2,t,0,x)/2"
                    v_L_last_symb = v_L_last_symb .. " + integral(("..m_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2"
                    if not symbolischer_modus then
                        v_L_last = v_L_last + (casToNumber(math.eval("approx(integral(("..m_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2)")) or 0)
                        phi_L_last = phi_L_last + (casToNumber(math.eval("approx(integral(("..m_t..")*("..L_str.."-t),t,0,"..L_str.."))")) or 0)
                    end
                    phi_L_last_symb = phi_L_last_symb .. " + integral(("..m_t..")*("..L_str.."-t),t,0,"..L_str..")"
                end
                
                local c1 = symbolischer_modus and ("(" .. (s.symb_start.c1 or "0") .. ")") or fN(va * EI)
                local c2 = symbolischer_modus and ("(" .. (s.symb_start.c2 or "0") .. ")") or fN(-phia * EI)
                local c3 = symbolischer_modus and "((" .. (s.symb_start.vb or "0") .. ") - (" .. v_L_last_symb .. "))" or fN(vb * EI - v_L_last)
                local c4 = symbolischer_modus and "((" .. (s.symb_start.phib or "0") .. ") - (" .. phi_L_last_symb .. "))" or fN(-phib * EI - phi_L_last)
                -- Auch an Gelenken gilt die Hermite-Form: jedes Stabende hat seine eigene Verdrehung,
                -- ein Sonderzweig (nur Lastanteil + va + phia*x) liesse Q0- und M0-Anteile weg.
                local expr
                do
                    expr = v_last_expr .. " + " .. c1 .. "*(1-3*(x/"..L_str..")^2+2*(x/"..L_str..")^3) + " .. c2 .. "*(x-2*x^2/"..L_str.."+x^3/("..L_str.."^2)) + " .. c3 .. "*(3*(x/"..L_str..")^2-2*(x/"..L_str..")^3) + " .. c4 .. "*(-x^2/"..L_str.."+x^3/("..L_str.."^2))"
                end
                -- exact() liegt um das gesamte, in Lua bereits rausch-bereinigte Polynom!
                math.eval("v_EI_stab" .. i .. "(x) := " .. eval_cas_string(expr, true))
            end
        end
        zeigeMeldung("Exakte Biegelinien (v_EI_stab_i) exportiert.", "Export")
    end
end


exportULinienToTI = function(stab_index)
    if not exportBereit() then zeigeMeldung("Bitte zuerst das System berechnen (Taste B).", "Export fehlgeschlagen"); return end
    if math.eval then
        local fN = fN_export

        local start_i = stab_index or 1
        local end_i   = stab_index or #staebe
        for i = start_i, end_i do
            local s  = staebe[i]
            local dx = knoten[s.k2].x - knoten[s.k1].x
            local dy = knoten[s.k2].y - knoten[s.k1].y
            local L  = math.sqrt(dx^2 + dy^2)
            if L > 0 and not istBogen(s) then
                local EA = stabEA(s)

                -- Lokale Verschiebungen an den Stabenden (aus FEM-Loesung)
                local ua = (math.abs(s.v_local[1] or 0) < 1e-12) and 0 or s.v_local[1]
                local ub = (math.abs(s.v_local[4] or 0) < 1e-12) and 0 or s.v_local[4]

                local L_str = "(" .. fN(L) .. ")"

                -- Randbedingungen als Konstanten mal EA
                local c1 = fN(ua * EA)   -- EA*u(0) = ua*EA
                local c2 = fN(ub * EA)   -- EA*u(L) = ub*EA

                -- Streckenlast-Anteil: N_last(x) = Normalkraft nur aus Streckenlasten
                -- getEqN liefert den Ausdruck der verteilten Normallast (Streckenlast) in lokalen Koordinaten
                local eq_n   = getEqN(s, L, fN)
                local use_cas = string.hasx(eq_n)

                local expr = ""

                if use_cas then
                    -- CAS-Pfad: n(x) enthaelt x -> doppelte Integration via TI-CAS
                    -- u(x)*EA = c1*(1-x/L) + c2*(x/L)
                    --         - integral((x-t)*n(t), t, 0, x)
                    --         + (x/L) * integral((L-t)*n(t), t, 0, L)
                    local n_t = eq_n:subx("t")
                    local int_0_L = "integral((" .. n_t .. ")*(" .. L_str .. "-t), t, 0, " .. L_str .. ")"
                    local int_0_x = "integral((" .. n_t .. ")*(x-t), t, 0, x)"
                    expr = c1 .. "*(1-x/" .. L_str .. ") + " .. c2 .. "*(x/" .. L_str .. ") - " ..
                           int_0_x .. " + (x/" .. L_str .. ")*(" .. int_0_L .. ")"
                else
                    -- Algebraischer Pfad: N_last(x) = nA + (nB-nA)/L * x  (konstant oder linear)
                    -- Gesamtnormalkraft am Stabstart: N(0) = -s_local[1] (Auflagerkraft)
                    -- Streckenlast: gleichmaessig n + linear variierende n_A..n_B + Eigengewicht
                    local c_val  = dx / L
                    local s_val  = -dy / L
                    local f_gx   = (s.gx_proj)  and math.abs(s_val) or 1
                    local f_gy   = (s.gy_proj)  and math.abs(c_val) or 1
                    -- Gleichmaessige Streckenlast in Stabachsenrichtung (lokal)
                    local n_const = (s.n or 0)
                                  + (s.gx or 0) * f_gx * c_val
                                  - (s.gy or 0) * f_gy * s_val
                    -- Lineare Komponente (n_A am Stabstart, n_B am Stabende)
                    local nA_lin = (s.n_A or 0)
                    local nB_lin = (s.n_B or 0)
                    -- Gesamte Streckenlasten-Beitraege
                    local nA_tot = n_const + nA_lin   -- N_last(0)
                    local nB_tot = n_const + nB_lin   -- N_last(L)

                    -- Doppelte Integration einer konstanten/linearen Lastfunktion.
                    local slope = (nB_tot - nA_tot) / L
                    local int_0_L_val = nA_tot * L^2 / 2 + slope * L^3 / 6

                    local load_expr = "-(" .. fN(nA_tot) .. ")*x^2/2-(" .. fN(slope) .. ")*x^3/6"
                    local corr_expr = "(x/" .. L_str .. ")*(" .. fN(int_0_L_val) .. ")"

                    expr = load_expr .. " + " .. corr_expr
                         .. " + " .. c1 .. "*(1-x/" .. L_str .. ") + " .. c2 .. "*(x/" .. L_str .. ")"
                end

                -- Vereinfachtes Ergebnis exportieren
                math.eval("u_EA_stab" .. i .. "(x) := " .. eval_cas_string(expr, true))
            end
        end
        zeigeMeldung("Exakte Laengslinien (u_EA_stab_i) exportiert.", "Export")
    end
end

-- ============================================================================
-- NEUE SYMBOLISCHE EXPORTS: Rand-LGS fuer Biege- und Laengslinien
-- Suche im Editor nach "exportBiegelinienNeuToTI" oder "exportULinienNeuToTI".
-- Diese beiden Funktionen stehen bewusst nur in Biegelinieneu.lua.
-- ============================================================================

-- Zahl als exakter CAS-Text: Bruch, Wurzel eines Bruchs oder 12-stellige Dezimalzahl.
-- (fN_export liefert Anzeigeformen; fuer das LGS muessen z. B. cos(45) und sqrt(18) exakt sein.)
local function neuZahl(v)
    if type(v) ~= "number" then return tostring(v) end
    if v == 0 or math.abs(v) < 1e-300 then return "0" end
    local a = math.abs(v)
    local frac = floatToFrac_lua(v, 1e-12 * a, 10000)
    if frac and frac ~= "0" then return frac end
    if a >= 1e-4 and a <= 1e4 then
        local sq = floatToFrac_lua(v * v, 1e-12 * v * v, 10000)
        if sq and sq ~= "0" then return (v < 0 and "-" or "") .. "sqrt(" .. sq .. ")" end
    end
    -- Dezimalzahl, e-Notation als Zehnerpotenz
    return (string.format("%.12g", v):gsub("e([%+%-]?%d+)", function(e) return "*10^(" .. tonumber(e) .. ")" end))
end

-- exakte CAS-Vereinfachung ohne Rundung (fuer Zwischenwerte des LGS)
local function neuExakt(expr)
    if not expr or expr == "" then return "0" end
    local ok, cleaned = pcall(function() return eval_cas_string(expr, false) end)
    if ok and cleaned and cleaned ~= "" then return cleaned end
    return expr
end

local function neuSymbolText(value, text)
    if text and text ~= "" then return "(" .. neuCasText(text) .. ")" end
    return neuZahl(value or 0)
end

-- Dehnstarr (randDehnstarr): EA = EA_Zahl/RL_EPS im LGS, danach Grenzwert RL_EPS -> 0.
-- So bleibt das LGS auch dann regulaer, wenn N nur ueber die Dehnsteifigkeiten verteilt wird
-- (z. B. Festlager-Festlager mit Horizontallast); 1/EA = 0 direkt waere dort singulaer.
local RL_EPS = "rleps"

-- true, wenn ein EA-Text eine reine Zahl ist (auch "1e8", "2*10^8"), also nicht symbolisch
local function neuIstZahlText(str)
    if not str or str == "" then return true end
    local t = tostring(str):gsub("(%d)[eE]([%+%-]?%d)", "%1%2")
    return not t:find("%a")
end

-- Grenzwert rleps -> 0 als exakter CAS-Text; nil, wenn er nicht endlich oder nicht bestimmbar ist
-- (TI: undef bzw. Unendlich-Zeichen; bei einem CAS-Fehler kommt der Eingabetext mit "limit" zurueck)
local function neuGrenzwert(expr)
    local res = neuExakt("limit(" .. expr .. "," .. RL_EPS .. ",0)")
    local t = (res or ""):lower()
    if t == "" or t:find("limit") or t:find("undef") or t:find(string.char(226, 136, 158)) or t:find("%f[%w]z?oo%f[^%w]") then
        return nil
    end
    return res
end

-- Starre Staebe: biegesteif (EI -> unendlich) und dehnsteif (EA -> unendlich) je Stab im Stabmenue;
-- randDehnstarr macht zusaetzlich alle Staebe mit Standard-EA dehnsteif (Zahl, nicht im Stabmenue
-- eingegeben). Rand-LGS: exakter Grenzwert; FEM: exakte Zwangsbedingungen (baueZwangsbedingungen).
-- stabEA/stabEI (STARR_FAKTOR mal groesste Steifigkeit der nicht starren Staebe) dienen nur der
-- Nachbearbeitung (Zeichnung, Referenzexporte), nicht der Steifigkeitsmatrix. Global fuer on.paint.
STARR_FAKTOR = 1e6
function stabBiegesteif(s) return s.biegesteif and true or false end
function stabDehnsteif(s)
    if s.dehnsteif then return true end
    return (randDehnstarr and not s.EA_manuell and neuIstZahlText(s.EA_str)) and true or false
end
local function starrReferenz(feld, istStarr)
    local ref = 0
    for _, t in ipairs(staebe) do
        if not istStarr(t) and type(t[feld]) == "number" then ref = math.max(ref, t[feld]) end
    end
    if ref <= 0 then ref = ((feld == "EA") and defEA or defEI) or 1 end
    return ref
end
-- Steifigkeit in der Steifigkeitsmatrix: der starre Anteil ist 0, ihn ersetzen die Zwangsbedingungen
-- (sonst Ausloeschung neben weichen Federn). Im PvV-Modus gibt es keine Zwangsbedingungen.
function stabEA_K(s) if stabDehnsteif(s) and not return_kinematic_mode then return 0 end return s.EA end
function stabEI_K(s) if stabBiegesteif(s) and not return_kinematic_mode then return 0 end return s.EI end
-- sehr grosse Ersatzwerte nur fuer die Nachbearbeitung (Zeichnung, Referenzexporte)
function stabEA(s) if stabDehnsteif(s) then return STARR_FAKTOR * starrReferenz("EA", stabDehnsteif) end return s.EA end
function stabEI(s) if stabBiegesteif(s) then return STARR_FAKTOR * starrReferenz("EI", stabBiegesteif) end return s.EI end

-- Stablaenge als CAS-Text: symbolisch als Vielfaches der Referenzlaenge, sonst als Zahl
local function neuMemberLength(stab)
    local k1, k2 = knoten[stab.k1], knoten[stab.k2]
    local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
    if symbolischer_modus and L > 0 then return symbLaenge(L) end
    return neuZahl(L)
end

local function neuCleanTerm(expr)
    if not expr or expr == "" then return "0" end
    local ok, cleaned = pcall(function() return eval_cas_string(expr, true) end)
    if ok and cleaned and cleaned ~= "" then return cleaned end
    return expr
end

local function neuShowMessage(text)
    print("[Biegelinieneu] " .. tostring(text))
end

local function neuCasEval(command, name)
    neuShowMessage("CAS " .. (name or "Ausdruck"))
    local result
    local ok, err = pcall(function() result = math.eval(command) end)
    if not ok then
        neuShowMessage("Fehler bei " .. (name or "CAS-Ausdruck") .. ": " .. tostring(err))
    else
        if type(result) == "string" and (result:find("Error") or result:find("error") or result:find("Syntax")) then
            neuShowMessage("CAS meldet bei " .. (name or "Ausdruck") .. ": " .. result)
            return false
            
        end
        neuShowMessage("OK " .. (name or "Ausdruck"))
        if name and (name:find("^wneu") or name:find("^uneu")) then
            local check_result
            local check_ok, check_err = pcall(function()
                check_result = math.eval("string(" .. name .. "(0))")
            end)
            if not check_ok then
                neuShowMessage("Funktionspruefung fehlgeschlagen bei " .. name .. ": " .. tostring(check_err))
                return false
            end
            if type(check_result) == "string" and (check_result:find("Error") or check_result:find("error") or check_result:find("Syntax")) then
                neuShowMessage("Funktionspruefung meldet bei " .. name .. ": " .. check_result)
                return false
            end
            neuShowMessage(name .. "(0) = " .. tostring(check_result))
        end
    end
    return ok
end

local function neuExportStatus(text, titel)
    neuShowMessage(text)
    zeigeMeldung(text, titel or "Export")
end

-- =====================================================================
-- NEUE VERFORMUNGSLINIEN: globales Rand- und Uebergangsbedingungs-LGS
--
-- Ansatz je Stab i (lokale Koordinate x von 0 bis L_i, Zaehlrichtung k1 -> k2):
--   EI*w_i(x) = wp_i(x) + c1*x^3/6 + c2*x^2/2 + c3*x + c4
--   EA*u_i(x) = up_i(x) + C1*x + C2
--   wp = int q(t)(x-t)^3/6 dt + int m(t)(x-t)^2/2 dt - EI*kappaT*x^2/2
--   up = -int n(t)(x-t) dt + EA*epsT*x
--   Q = -c1 - int q,   M = -(wp'' + c1*x + c2),   N = C1 - int n,   phi = -w'
-- Das sind dieselben Vorzeichen wie im FEM-Modell: w und q positiv in lokaler
-- Querrichtung n = (-dy, dx)/L, phi = -w', M' = Q - m, Q' = -q, N' = -n.
--
-- Unbekannte: 6 je Stab (c1..c4, C1, C2). Knotenverschiebungen werden ueber ein
-- Referenz-Stabende ausgedrueckt; nur wenn an einem Knoten kein Stabende ohne
-- N-/Q-Gelenk existiert, bekommt der Knoten eigene Unbekannte ux(K), uy(K).
-- Bedingungen je Knoten:
--   Kinematik: u, w, phi der Stabenden vertraeglich bzw. N=0 / Q=0 / M=0 am Gelenk
--   Statik:    Lagerbedingung oder Gleichgewicht aus Stabendkraeften,
--              Knotenlast (last_x/last_y/last_m, Winkel last_w) und Federn (cx, cy, cm)
-- Geloest wird mit simult(); exportiert werden wneu_i(x) = EI*w_i(x),
-- uneu_i(x) = EA*u_i(x) und die Bedingungsliste randbed (Strings).
-- Starre Staebe (stabDehnsteif / stabBiegesteif): EA bzw. EI = 1/rleps, alle Konstanten werden mit
-- limit(..., rleps, 0) bestimmt. Bleibt EA*u bzw. EI*w endlich (Stab nicht als Ganzes verschoben
-- bzw. verdreht, keine Temperaturdehnung/-kruemmung), wird wie sonst EA*u bzw. EI*w exportiert,
-- sonst u_i(x) bzw. w_i(x) (Starrkoerperbewegung plus Temperaturanteil). randinfo beschreibt, was gilt.
-- =====================================================================

-- Linearform: sum c[j]*x_j + k, alle Eintraege als CAS-Strings
local function rlNeu() return { c = {}, k = "0" } end

-- Faktor (Zahl oder String) als CAS-String
local function rlFaktorText(f)
    if type(f) == "number" then return neuZahl(f) end
    return f
end

-- dst = dst + f * src
local function rlAdd(dst, src, f)
    local ft = rlFaktorText(f)
    if ft == "0" then return end
    for j, cj in pairs(src.c) do
        local term = (ft == "1") and cj or ((ft == "-1") and ("-(" .. cj .. ")") or ("(" .. ft .. ")*(" .. cj .. ")"))
        dst.c[j] = dst.c[j] and (dst.c[j] .. "+" .. term) or term
    end
    if src.k ~= "0" then
        local term = (ft == "1") and src.k or ((ft == "-1") and ("-(" .. src.k .. ")") or ("(" .. ft .. ")*(" .. src.k .. ")"))
        dst.k = (dst.k == "0") and term or (dst.k .. "+" .. term)
    end
end

local function rlKonst(k) local l = rlNeu(); l.k = k; return l end
local function rlEinheit(j, coef) local l = rlNeu(); l.c[j] = coef or "1"; return l end

-- Groesse eines Stabendes: Linearform plus lesbarer Name (z. B. "w1(x1=l)")
-- name: Anzeige in randbed, lin: Linearform der physikalischen Groesse, vz: Groesse = vz * name
-- (z. B. Q = -EIw''' -> name "EIw1'''(x1=0)", vz = -1)
local function rlGroesse(name, lin, vz) return { name = name, lin = lin, vz = vz or 1 } end

-- Text einer Bedingung sum f_i * groesse_i + k = 0
-- Anzeige-Hilfen: einfacher Term = kein + oder - ausser einem fuehrenden Minus
local function rlEinfach(x) return not x:sub(2):find("[%+%-]") end
local function rlNegiert(k)
    local innen = k:match("^%-%((.*)%)$")   -- "-(-2)" -> "-2"
    if innen and select(2, innen:gsub("%(", "")) == select(2, innen:gsub("%)", "")) then return innen end
    local vz, rest = k:match("^(%-?)(.*)$")
    if rest ~= "" and not rest:find("[%+%-]") then return (vz == "-") and rest or ("-" .. rest) end
    return "-(" .. k .. ")"
end
local function rlKlammer(x)
    if x:match("^%b()$") or x:match("^[%w_%.]+$") then return x end
    return "(" .. x .. ")"
end

-- wert(q) liefert den schon bekannten Wert einer Groesse (sonst nil): er wird statt des Namens
-- angezeigt, damit z. B. "w1(x1=l)=u2(x2=3*l)" bei dehnstarrem, gehaltenem Stab 2 zu "w1(x1=l)=0" wird.
-- Zweiter Rueckgabewert: Anzahl der noch offenen Groessen in der Bedingung.
local function rlBedText(cond, wert)
    -- Anzeigefaktoren: Faktor der Groesse mal Vorzeichen ihres Namens (Q = -EIw''' usw.)
    local terms, bekannt = {}, {}
    for _, t in ipairs(cond.terms) do
        local v = wert and wert(t.q)
        if v then
            if v ~= "0" then bekannt[#bekannt + 1] = { f = t.f, ft = t.ft, v = v } end
        else
            local vz = t.q.vz or 1
            local f, ft = t.f, t.ft
            if vz < 0 then
                if type(f) == "number" then f = -f else f = "-(" .. f .. ")" end
                if ft then ft = (ft:sub(1, 1) == "-" and rlEinfach(ft)) and ft:sub(2) or ("-" .. ft) end
            end
            terms[#terms + 1] = { f = f, ft = ft, q = t.q }
        end
    end
    local k = cond.ktext or cond.k or "0"
    k = k:match("^%((%-?[%w_%.]+)%)$") or k:match("^%(([^()%+%-]*)%)$") or k   -- "(F)" -> "F", "(-f)" -> "-f"
    -- eingesetzte bekannte Groessen gehoeren zum konstanten Teil (Faktor mal Wert)
    for _, e in ipairs(bekannt) do
        -- Vorzeichen des Wertes und des Faktors zusammenfassen: nicht "-(-2)", sondern "2"
        local minus, wert = false, e.v
        if wert:sub(1, 1) == "-" and rlEinfach(wert) then minus, wert = true, wert:sub(2) end
        local txt, f = nil, e.f
        if type(f) == "number" then
            if f < 0 then minus, f = not minus, -f end
            if math.abs(f - 1) < 1e-12 then txt = rlKlammer(wert)
            else txt = rlKlammer(fN_export(f)) .. "*" .. rlKlammer(wert) end
        else
            txt = rlKlammer(e.ft or f) .. "*" .. rlKlammer(wert)
        end
        if minus then txt = "-" .. txt end
        if k == "0" then k = txt
        elseif txt:sub(1, 1) == "-" then k = k .. txt
        else k = k .. "+" .. txt end
    end
    local function istEins(f) return type(f) == "number" and math.abs(f - 1) < 1e-12 end
    local function istMinusEins(f) return type(f) == "number" and math.abs(f + 1) < 1e-12 end
    if #terms == 2 and k == "0" and (istEins(terms[1].f) or istMinusEins(terms[1].f)) and (istEins(terms[2].f) or istMinusEins(terms[2].f)) then
        local a, b = terms[1], terms[2]
        if a.f < 0 and b.f > 0 then a, b = b, a end
        if (a.f > 0) == (b.f > 0) then return a.q.name .. "=-" .. b.q.name, 2 end   -- a + b = 0
        return a.q.name .. "=" .. b.q.name, 2                                          -- a - b = 0
    end
    if #terms == 1 and (istEins(terms[1].f) or istMinusEins(terms[1].f)) then
        if k == "0" then return terms[1].q.name .. "=0", 1 end
        local rhs = istEins(terms[1].f) and rlNegiert(k) or k
        return terms[1].q.name .. "=" .. rhs, 1
    end
    local parts = {}
    for i, t in ipairs(terms) do
        local f, txt = t.f, nil
        if istEins(f) then txt = t.q.name
        elseif istMinusEins(f) then txt = "-" .. t.q.name
        else
            local ft = t.ft or ((type(f) == "number") and fN_export(f) or f)   -- Anzeigeform
            if ft:sub(1, 1) == "-" and rlEinfach(ft) then txt = "-" .. rlKlammer(ft:sub(2)) .. "*" .. t.q.name
            else txt = rlKlammer(ft) .. "*" .. t.q.name end
        end
        if i > 1 and txt:sub(1, 1) ~= "-" then txt = "+" .. txt end
        parts[#parts + 1] = txt
    end
    local s = table.concat(parts)
    if k ~= "0" then
        if k:sub(1, 1) == "-" and rlEinfach(k) then s = s .. k
        elseif rlEinfach(k) then s = s .. "+" .. k
        else s = s .. "+(" .. k .. ")" end
    end
    return s .. "=0", #terms
end

-- Zeile (Linearform) einer Bedingung
local function rlBedZeile(cond)
    local row = rlNeu()
    for _, t in ipairs(cond.terms) do rlAdd(row, t.q.lin, t.f) end
    if cond.k and cond.k ~= "0" then rlAdd(row, rlKonst(cond.k), 1) end
    return row
end

-- Durchreichen wie von Hand: Laengsverschiebung und Normalkraft eines dehnsteifen Stabes (direkte
-- Methode) sind an beiden Enden dieselbe Unbekannte (C2 bzw. C1), ebenso die Knotenverschiebungen
-- ux(K), uy(K). Eine Bedingung, in der nur eine solche Unbekannte steht, legt sie fest; eingesetzt in
-- die anderen Bedingungen entstehen Beziehungen zwischen den Nachbarstaeben, z. B. aus
-- "u2(x2=0)=w1(x1=l)", "u3(x3=0)=u2(x2=l)" und "w4(x4=0)=-u3(x3=l)" die Bedingung "w4(x4=0)=-w1(x1=l)".
-- Bleiben danach nur Bedingungen mit Biegelinien-Unbekannten (c1..c4 aller Staebe) uebrig, genuegen
-- sie fuer w (Gauss-Schritte mit den festgelegten Unbekannten als Pivot, das LGS bleibt regulaer).
-- Rueckgabe { w = { {i = Nummer, text = neuer Text oder nil}, ... }, u = { Nummern } } oder nil.
function neuDurchreichen(conds, typVon, nW)
    local function zahl(t)
        if type(t) == "number" then return t end
        t = tostring(t or ""):gsub("%s", "")
        local n = tonumber(t)
        if n then return n end
        local innen = t:match("^%((.*)%)$")
        if innen then return zahl(innen) end
        innen = t:match("^%-%((.*)%)$")
        if innen then local v = zahl(innen); return v and -v end
        return nil
    end
    local function istU(j) return typVon(j) ~= "w" end
    -- durchreichbar: jede Groesse mit dieser Unbekannten haengt nur von ihr ab (Zahlenkoeffizient)
    -- und steht mit einem Zahlenfaktor in der Bedingung (keine symbolische Feder davor)
    local gut = {}
    for _, cond in ipairs(conds) do
        for _, t in ipairs(cond.terms) do
            local n = 0
            for _ in pairs(t.q.lin.c) do n = n + 1 end
            for j, cj in pairs(t.q.lin.c) do
                if istU(j) then
                    local ok = n == 1 and type(t.f) == "number" and zahl(cj) ~= nil
                    if gut[j] == nil then gut[j] = ok else gut[j] = gut[j] and ok end
                end
            end
        end
    end
    local zeilen = {}
    for i, cond in ipairs(conds) do
        local terms = {}
        for _, t in ipairs(cond.terms) do terms[#terms + 1] = { f = t.f, q = t.q, ft = t.ft } end
        zeilen[i] = { i = i, terms = terms, k = cond.k or "0", ktext = cond.ktext, aktiv = true }
    end
    -- Anzahl der u-Unbekannten einer Zeile, eine davon, und ob w-Groessen darin stehen
    local function uUnbek(z)
        local m, n, j1, wT = {}, 0, nil, false
        for _, t in ipairs(z.terms) do
            for j in pairs(t.q.lin.c) do
                if istU(j) then
                    if not m[j] then m[j], n, j1 = true, n + 1, j end
                else
                    wT = true
                end
            end
        end
        return n, j1, wT
    end
    local function kPlus(a, b, f)                  -- a + f*b als CAS-Text (f Zahl)
        if b == nil or b == "0" or math.abs(f) < 1e-15 then return a end
        local teil = (math.abs(f - 1) < 1e-15) and ("(" .. b .. ")") or ("(" .. neuZahl(f) .. ")*(" .. b .. ")")
        return (a == "0") and teil or (a .. "+" .. teil)
    end
    local function fMal(f, z)                       -- Faktor (Zahl oder Text) mal Zahl
        if type(f) == "number" then return f * z end
        if math.abs(z - 1) < 1e-15 then return f end
        return "(" .. neuZahl(z) .. ")*(" .. f .. ")"
    end
    local function dazu(terms, f, q, ft)
        if type(f) == "number" then
            for idx, t in ipairs(terms) do
                if t.q == q and type(t.f) == "number" then
                    t.f = t.f + f
                    if math.abs(t.f) < 1e-12 then table.remove(terms, idx) end
                    return
                end
            end
            if math.abs(f) < 1e-12 then return end
        end
        terms[#terms + 1] = { f = f, q = q, ft = ft }
    end
    local eingesetzt = false
    while true do
        -- zuerst Bedingungen nur mit der Laengsgroesse (u1(x1=0)=0), dann die mit Biegelinie
        local wahl, wj
        for stufe = 1, 2 do
            for _, z in ipairs(zeilen) do
                if z.aktiv then
                    local n, j, wT = uUnbek(z)
                    if n == 1 and gut[j] and (stufe == 2 or not wT) then wahl, wj = z, j; break end
                end
            end
            if wahl then break end
        end
        if not wahl then break end
        -- aus der gewaehlten Zeile: x_j = -(andere Terme + K)/A
        local A, K, andere = 0, wahl.k, {}
        for _, t in ipairs(wahl.terms) do
            local cj = t.q.lin.c[wj]
            if cj then
                A = A + t.f * zahl(cj)
                K = kPlus(K, t.q.lin.k, t.f)
            else
                andere[#andere + 1] = t
            end
        end
        if math.abs(A) < 1e-12 then return nil end
        wahl.aktiv, eingesetzt = false, true
        for _, z in ipairs(zeilen) do
            if z.aktiv then
                local neu, k, geaendert = {}, z.k, false
                for _, t in ipairs(z.terms) do
                    local cj = t.q.lin.c[wj]
                    if cj then
                        -- t.f*(a*x_j + k_t) mit x_j eingesetzt
                        local r = t.f * zahl(cj) / A
                        geaendert = true
                        k = kPlus(k, t.q.lin.k, t.f)
                        k = kPlus(k, K, -r)
                        for _, o in ipairs(andere) do
                            local ft = (type(o.f) ~= "number" and math.abs(r + 1) < 1e-15) and o.ft or nil
                            dazu(neu, fMal(o.f, -r), o.q, ft)
                        end
                    else
                        dazu(neu, t.f, t.q, t.ft)
                    end
                end
                if geaendert then
                    z.terms, z.geaendert = neu, true
                    if k ~= z.k then z.k, z.ktext = k, nil end
                end
            end
        end
    end
    if not eingesetzt then return nil end
    local erg, anzahlW = { w = {}, u = {} }, 0
    for _, z in ipairs(zeilen) do
        if z.aktiv then
            local n, _, wT = uUnbek(z)
            if n > 0 or not wT then return nil end   -- Laengsgroesse bleibt uebrig: nicht trennbar
            anzahlW = anzahlW + 1
            local text
            if z.geaendert then
                local kt = z.ktext
                if not kt and z.k ~= "0" then
                    -- vereinfachen; der CAS schreibt Symbole klein, also die Schreibweise der Eingabe
                    -- zurueckholen (h -> H), wie in den uebrigen Bedingungen
                    kt = neuExakt(z.k)
                    for name in pairs(sym_vars or {}) do
                        local klein = name:lower()
                        if klein ~= name then
                            kt = kt:gsub("%f[%w_]" .. klein:gsub("%p", "%%%0") .. "%f[^%w_]", name)
                        end
                    end
                end
                text = rlBedText({ terms = z.terms, k = z.k, ktext = kt })
            end
            erg.w[#erg.w + 1] = { i = z.i, text = text }
        else
            erg.u[#erg.u + 1] = z.i
        end
    end
    if anzahlW ~= nW then return nil end
    return erg
end

-- CAS-String-Auswertung ohne exact/expand (fuer Matrizen)
local function neuCasString(cmd)
    local res = math.eval("string(" .. cmd .. ")")
    if type(res) ~= "string" then return res ~= nil and tostring(res) or nil end
    if res:sub(1, 1) == '"' then res = res:sub(2, -2) end
    res = res:gsub(string.char(226, 136, 146), "-"):gsub(string.char(239, 128, 128), "E")
    if res == "undef" then return nil end
    return res
end

-- "(str)*num" mit Vereinfachung fuer 0, 1, -1; nil wenn Produkt 0.
-- fmt formatiert Zahlen (neuZahl exakt fuer das LGS, fN_export fuer die Anzeige).
local function neuSkaliert(str, num, fmt)
    fmt = fmt or neuZahl
    if not str or str == "0" or str == "(0)" or math.abs(num) < 1e-12 then return nil end
    local plain = tonumber((str:gsub("^%((.*)%)$", "%1")))
    if plain then
        if math.abs(plain * num) < 1e-12 then return nil end
        return fmt(plain * num)
    end
    if math.abs(num - 1) < 1e-12 then return str end
    if math.abs(num + 1) < 1e-12 then return "-(" .. str .. ")" end
    return "(" .. str .. ")*" .. fmt(num)
end

-- Temperatur eines Stabes als CAS-Texte (auch symbolisch): kappaT = alpha*(Tu-To)/h,
-- epsT = alpha*(To+Tu)/2; nil, wenn der Anteil 0 ist. h = 0 heisst: kein Gradient.
local function neuTemperatur(s)
    local function gesetzt(str, wert) return (type(str) == "string" and str ~= "" and str ~= "0") or (wert or 0) ~= 0 end
    if not (gesetzt(s.To_str, s.To) or gesetzt(s.Tu_str, s.Tu)) then return nil, nil end
    local To, Tu = neuSymbolText(s.To, s.To_str), neuSymbolText(s.Tu, s.Tu_str)
    local al = neuSymbolText(s.alpha, s.alpha_str)
    local eTs = neuExakt("(" .. al .. ")*((" .. To .. ")+(" .. Tu .. "))/2")
    if eTs == "0" then eTs = nil end
    local kTs = nil
    if gesetzt(s.h_str, s.h) then
        kTs = neuExakt("(" .. al .. ")*((" .. Tu .. ")-(" .. To .. "))/(" .. neuSymbolText(s.h, s.h_str) .. ")")
        if kTs == "0" then kTs = nil end
    end
    return kTs, eTs
end

-- true, wenn ein Lasttext nur aus Zahlen besteht und 0 ergibt (spart CAS-Integrale unbelasteter Staebe)
local function neuIstNull(expr)
    local t = tostring(expr or "0"):gsub("%s", "")
    if t:find("[^%d%.%+%-%*/%^%(%)]") then return false end
    local f = (loadstring or load)("return " .. t)
    if not f then return false end
    local ok, v = pcall(f)
    return ok and type(v) == "number" and v == 0
end

-- Stabdaten fuer das Rand-LGS: Laenge, Richtung, Steifigkeiten, Lastfunktionen, Stabendgroessen
local function neuStabDaten(i, s, base, direkt)
    local k1, k2 = knoten[s.k1], knoten[s.k2]
    local dx, dy = k2.x - k1.x, k2.y - k1.y
    local L = math.sqrt(dx * dx + dy * dy)
    local Ls = neuMemberLength(s)
    -- starre Staebe: Grenzwert-Methode mit Steifigkeit 1/rleps (danach rleps -> 0) oder direkt:
    -- biegesteif w = c4 + c3*x - kappaT*x^2/2, dehnsteif u = C2 + epsT*x; Schnittgroessen wie sonst
    local starrI, starr = stabBiegesteif(s), stabDehnsteif(s)
    local dirI, dirA = starrI and direkt, starr and direkt
    local EI = (starrI and not direkt) and ("(1/" .. RL_EPS .. ")") or neuSymbolText(s.EI, s.EI_str)
    local EA = (starr and not direkt) and ("(1/" .. RL_EPS .. ")") or neuSymbolText(s.EA, s.EA_str)
    local q = getEqQ(s, L, fN_export, Ls)
    local n = getEqN(s, L, fN_export, Ls)
    local m = "(" .. neuCasText(s.m_str or "0") .. ")"
    local qt, mt, nt = q:subx("t"), m:subx("t"), n:subx("t")
    local hasM = not (m == "(0)" or m == "()" or neuIstNull(m))
    local qNull, nNull = neuIstNull(q), neuIstNull(n)
    local kTs, eTs = neuTemperatur(s)
    -- Partikulaere Anteile als Funktionen von x
    local wp, wp1, wp2 = "0", "0", "0"
    if not qNull then
        wp = "integral((" .. qt .. ")*(x-t)^3,t,0,x)/6"
        wp1 = "integral((" .. qt .. ")*(x-t)^2,t,0,x)/2"
        wp2 = "integral((" .. qt .. ")*(x-t),t,0,x)"
    end
    if hasM then
        wp = wp .. "+integral((" .. mt .. ")*(x-t)^2,t,0,x)/2"
        wp1 = wp1 .. "+integral((" .. mt .. ")*(x-t),t,0,x)"
        wp2 = wp2 .. "+integral((" .. mt .. "),t,0,x)"
    end
    if kTs then
        wp = wp .. "-(" .. EI .. ")*(" .. kTs .. ")*x^2/2"
        wp1 = wp1 .. "-(" .. EI .. ")*(" .. kTs .. ")*x"
    end
    local iq = qNull and "0" or ("integral((" .. qt .. "),t,0,x)")
    local up = nNull and "0" or ("-integral((" .. nt .. ")*(x-t),t,0,x)")
    if eTs then up = up .. "+(" .. EA .. ")*(" .. eTs .. ")*x" end
    local inn = nNull and "0" or ("integral((" .. nt .. "),t,0,x)")
    local Lx = "(" .. Ls .. ")"
    local function beiL(expr)
        if expr == "0" then return "0" end
        return neuExakt(expr:subx(Lx))
    end
    local d = {
        i = i, s = s, L = L, Ls = Ls, EI = EI, EA = EA, base = base, starr = starr, starrI = starrI, kTs = kTs, eTs = eTs,
        tx = dx / L, ty = dy / L, nx = -dy / L, ny = dx / L,
        wp = wp, wp1 = wp1, up = up,
        WPL = dirI and "0" or beiL(wp), WP1L = dirI and "0" or beiL(wp1), WP2L = beiL(wp2), IQL = beiL(iq),
        UPL = dirA and "0" or beiL(up), INL = beiL(inn),
    }
    local c1, c2, c3, c4, C1, C2 = base + 1, base + 2, base + 3, base + 4, base + 5, base + 6
    local function nm(g, x) return g .. i .. "(x" .. i .. "=" .. x .. ")" end
    -- Anzeigenamen als Ableitungen: phi = -w', M = -EI(w''+kT), Q = -EIw''', N = EA(u'-eT)
    local function nmAbl(vor, g, strich, x, temp)
        local basis = g .. i .. strich .. "(x" .. i .. "=" .. x .. ")"
        if temp then return vor .. "(" .. basis .. temp .. ")" end
        return vor .. basis
    end
    local tM = kTs and ("+" .. rlKlammer(kTs)) or nil
    local tN = eTs and ("-" .. rlKlammer(eTs)) or nil
    -- Ende A (x = 0)
    local A = {}
    A.w = rlGroesse(nm("w", "0"), rlEinheit(c4, dirI and "1" or ("1/(" .. EI .. ")")))
    A.phi = rlGroesse(nmAbl("", "w", "'", "0"), rlEinheit(c3, dirI and "-1" or ("-1/(" .. EI .. ")")), -1)
    A.M = rlGroesse(nmAbl("EI", "w", "''", "0", tM), rlEinheit(c2, "-1"), -1)
    A.Q = rlGroesse(nmAbl("EI", "w", "'''", "0"), rlEinheit(c1, "-1"), -1)
    A.u = rlGroesse(nm("u", "0"), rlEinheit(C2, dirA and "1" or ("1/(" .. EA .. ")")))
    A.N = rlGroesse(nmAbl("EA", "u", "'", "0", tN), rlEinheit(C1, "1"))
    -- Ende B (x = L)
    local B = {}
    local lw, lphi = rlNeu(), rlNeu()
    if dirI then
        -- starr: w(L) = c4 + c3*L - kappaT*L^2/2, phi(L) = -c3 + kappaT*L
        lw.c[c3] = Lx; lw.c[c4] = "1"
        if kTs then lw.k = "-(" .. kTs .. ")*" .. Lx .. "^2/2" end
        lphi.c[c3] = "-1"
        if kTs then lphi.k = "(" .. kTs .. ")*" .. Lx end
    else
        lw.c[c1] = "(" .. Lx .. "^3/6)/(" .. EI .. ")"; lw.c[c2] = "(" .. Lx .. "^2/2)/(" .. EI .. ")"
        lw.c[c3] = Lx .. "/(" .. EI .. ")"; lw.c[c4] = "1/(" .. EI .. ")"; lw.k = "(" .. d.WPL .. ")/(" .. EI .. ")"
        lphi.c[c1] = "-(" .. Lx .. "^2/2)/(" .. EI .. ")"; lphi.c[c2] = "-" .. Lx .. "/(" .. EI .. ")"
        lphi.c[c3] = "-1/(" .. EI .. ")"; lphi.k = "-(" .. d.WP1L .. ")/(" .. EI .. ")"
    end
    B.w = rlGroesse(nm("w", Ls), lw)
    B.phi = rlGroesse(nmAbl("", "w", "'", Ls), lphi, -1)
    local lM = rlNeu()
    lM.c[c1] = "-" .. Lx; lM.c[c2] = "-1"; lM.k = "-(" .. d.WP2L .. ")"
    B.M = rlGroesse(nmAbl("EI", "w", "''", Ls, tM), lM, -1)
    local lQ = rlNeu()
    lQ.c[c1] = "-1"; lQ.k = "-(" .. d.IQL .. ")"
    B.Q = rlGroesse(nmAbl("EI", "w", "'''", Ls), lQ, -1)
    local lu = rlNeu()
    if dirA then
        -- starr: u(L) = C2 + epsT*L
        lu.c[C2] = "1"
        if eTs then lu.k = "(" .. eTs .. ")*" .. Lx end
    else
        lu.c[C1] = Lx .. "/(" .. EA .. ")"; lu.c[C2] = "1/(" .. EA .. ")"; lu.k = "(" .. d.UPL .. ")/(" .. EA .. ")"
    end
    B.u = rlGroesse(nm("u", Ls), lu)
    local lN = rlNeu()
    lN.c[C1] = "1"; lN.k = "-(" .. d.INL .. ")"
    B.N = rlGroesse(nmAbl("EA", "u", "'", Ls, tN), lN)
    d.A, d.B = A, B
    return d
end

-- Alle Bedingungen eines Knotens anhaengen
local function neuKnotenBedingungen(kidx, k, ends, conds, extra)
    if #ends == 0 then return end
    local function tt(a, b) return a.tx * b.tx + a.ty * b.ty end   -- t_a . t_b
    local function nt(a, b) return a.nx * b.tx + a.ny * b.ty end   -- n_a . t_b
    local function tn(a, b) return a.tx * b.nx + a.ty * b.ny end   -- t_a . n_b
    local function nn(a, b) return a.nx * b.nx + a.ny * b.ny end   -- n_a . n_b
    local function push(terms, k_str, k_text) conds[#conds + 1] = { terms = terms, k = k_str or "0", ktext = k_text } end
    local function add(terms, f, q, ft)
        if type(f) == "number" and not ft then
            for idx, t in ipairs(terms) do
                if t.q == q and type(t.f) == "number" and not t.ft then
                    t.f = t.f + f
                    if math.abs(t.f) < 1e-12 then table.remove(terms, idx) end
                    return
                end
            end
            if math.abs(f) < 1e-12 then return end
        end
        terms[#terms + 1] = { f = f, q = q, ft = ft }
    end
    -- Zahl hinter einem CAS-Text wie "(3)" oder "2" (sonst nil)
    local function zahlVon(txt) return tonumber((txt:gsub("^%((.*)%)$", "%1"))) end
    -- Feder-/Steifigkeitsfaktor c*num: numerisch als Zahl, symbolisch als Text (LGS exakt, Anzeige lesbar)
    local function addC(terms, cS, num, q)
        if math.abs(num) < 1e-12 then return end
        local cN = zahlVon(cS)
        if cN then add(terms, cN * num, q); return end
        local a = math.abs(num)
        local disp = (num < 0 and "-" or "") .. rlKlammer(cS) .. ((math.abs(a - 1) < 1e-12) and "" or ("*" .. fN_export(a)))
        add(terms, "(" .. cS .. ")*" .. neuZahl(num), q, disp)
    end

    -- Referenz-Stabenden
    local transRef, rotRef
    for _, e in ipairs(ends) do
        if not transRef and not e.relN and not e.relQ then transRef = e end
        if not rotRef and not e.relM then rotRef = e end
    end
    -- Knotenverschiebung U = (Ux, Uy) als Terme (Faktor, Groesse) je globaler Richtung
    local UX, UY
    if transRef then
        local r = transRef
        UX = { { f = r.d.tx, q = r.g.u }, { f = r.d.nx, q = r.g.w } }
        UY = { { f = r.d.ty, q = r.g.u }, { f = r.d.ny, q = r.g.w } }
    else
        extra.n = extra.n + 2
        local jx, jy = extra.n - 1, extra.n
        extra.names[jx], extra.names[jy] = "ux(K" .. kidx .. ")", "uy(K" .. kidx .. ")"
        extra.knoten[kidx] = { jx, jy }
        UX = { { f = 1, q = rlGroesse("ux(K" .. kidx .. ")", rlEinheit(jx)) } }
        UY = { { f = 1, q = rlGroesse("uy(K" .. kidx .. ")", rlEinheit(jy)) } }
    end
    -- Terme von U . e (e = (ex, ey)) mit Vorfaktor f in terms eintragen
    local function addU(terms, f, ex, ey)
        for _, t in ipairs(UX) do add(terms, f * ex * t.f, t.q) end
        for _, t in ipairs(UY) do add(terms, f * ey * t.f, t.q) end
    end

    -- 1) Kinematik der Stabenden
    for _, e in ipairs(ends) do
        if e.relN then push({ { f = 1, q = e.g.N } })
        elseif e ~= transRef then
            local terms = {}; add(terms, 1, e.g.u); addU(terms, -1, e.d.tx, e.d.ty); push(terms)
        end
        if e.relQ then push({ { f = 1, q = e.g.Q } })
        elseif e ~= transRef then
            local terms = {}; add(terms, 1, e.g.w); addU(terms, -1, e.d.nx, e.d.ny); push(terms)
        end
        if e.relM then push({ { f = 1, q = e.g.M } })
        elseif e ~= rotRef then push({ { f = 1, q = e.g.phi }, { f = -1, q = rotRef.g.phi } }) end
    end

    -- 2) Statik: Lager oder Gleichgewicht in den Lagerrichtungen xi, eta
    -- Lagerwinkel wie Zeichnung und FEM (Drehung um -winkel): xi = (cos, -sin), eta = (sin, cos)
    local wr = math.rad(k.winkel or 0)
    local dirs = {
        { name = "xi", ex = math.cos(wr), ey = -math.sin(wr), lager = k.lager_x, cn = "cx" },
        { name = "eta", ex = math.sin(wr), ey = math.cos(wr), lager = k.lager_y, cn = "cy" },
    }
    -- Knotenlast in globalen Komponenten (last_w dreht die Last)
    local rl = math.rad(-(k.last_w or 0)); local cl, sl = math.cos(rl), math.sin(rl)
    local Fx_s, Fy_s = neuSymbolText(k.last_x, k.last_x_str), neuSymbolText(k.last_y, k.last_y_str)
    local function lastText(ex, ey, fmt)
        -- (Fx*cl - Fy*sl)*ex + (Fx*sl + Fy*cl)*ey
        local parts = {}
        local a = neuSkaliert(Fx_s, cl * ex + sl * ey, fmt); if a then parts[#parts + 1] = a end
        local b = neuSkaliert(Fy_s, -sl * ex + cl * ey, fmt); if b then parts[#parts + 1] = b end
        if #parts == 0 then return "0" end
        local s = parts[1]; for i = 2, #parts do s = s .. (parts[i]:sub(1, 1) == "-" and "" or "+") .. parts[i] end
        return s
    end
    -- Federachsen wie gezeichnet (drawZigZag: Drehung um -f_winkel): cx = (cos, -sin), cy = (sin, cos)
    local fw = math.rad(k.f_winkel or 0)
    local feder = { { ex = math.cos(fw), ey = -math.sin(fw), c = k.cx, cs = k.cx_str },
                    { ex = math.sin(fw), ey = math.cos(fw), c = k.cy, cs = k.cy_str } }
    for _, dir in ipairs(dirs) do
        local terms = {}
        if dir.lager then
            addU(terms, 1, dir.ex, dir.ey)
            push(terms)
        else
            for _, e in ipairs(ends) do
                local sgn = (e.side == "A") and 1 or -1   -- Kraft des Stabendes auf den Knoten
                if not e.relN then add(terms, sgn * (e.d.tx * dir.ex + e.d.ty * dir.ey), e.g.N) end
                if not e.relQ then add(terms, sgn * (e.d.nx * dir.ex + e.d.ny * dir.ey), e.g.Q) end
            end
            for _, f in ipairs(feder) do
                if (f.c or 0) ~= 0 or (f.cs and f.cs ~= "") then
                    local proj = dir.ex * f.ex + dir.ey * f.ey   -- e . e_feder
                    if math.abs(proj) > 1e-12 then
                        local cS = neuSymbolText(f.c, f.cs)
                        -- Federkraft auf den Knoten: -c * (e_feder . U) * (e . e_feder)
                        for _, t in ipairs(UX) do addC(terms, cS, -proj * f.ex * t.f, t.q) end
                        for _, t in ipairs(UY) do addC(terms, cS, -proj * f.ey * t.f, t.q) end
                    end
                end
            end
            if #terms == 0 then
                -- Keine Stabkraft in dieser Richtung (alle Enden mit N-/Q-Gelenk): mit Last kinematisch,
                -- ohne Last ist die Knotenverschiebung beliebig und wird zu 0 gesetzt.
                if lastText(dir.ex, dir.ey) ~= "0" then
                    extra.fehler = "Knoten " .. kidx .. ": Last in frei beweglicher Richtung (kinematisch)"
                elseif not transRef then
                    addU(terms, 1, dir.ex, dir.ey); push(terms)
                end
            else
                push(terms, lastText(dir.ex, dir.ey), lastText(dir.ex, dir.ey, fN_export))
            end
        end
    end
    -- 3) Verdrehung: Einspannung oder Momentengleichgewicht
    if k.lager_m then
        if rotRef then push({ { f = 1, q = rotRef.g.phi } }) end
    elseif rotRef then
        local terms = {}
        for _, e in ipairs(ends) do
            if not e.relM then add(terms, (e.side == "A") and 1 or -1, e.g.M) end
        end
        if (k.cm or 0) ~= 0 or (k.cm_str and k.cm_str ~= "") then
            addC(terms, neuSymbolText(k.cm, k.cm_str), -1, rotRef.g.phi)
        end
        local mS = neuSymbolText(k.last_m, k.last_m_str)
        push(terms, (mS ~= "0" and mS ~= "(0)") and mS or "0")
    elseif (k.last_m or 0) ~= 0 then
        neuShowMessage("Knoten " .. kidx .. ": Moment am Vollgelenk wird ignoriert")
    end
end

-- Eliminiert Zeilen mit nur einer Unbekannten (typisch: Bedingungen bei x=0) und danach Zeilen mit
-- zwei Unbekannten (x_j = f*x_m + k, "Alias"): x_j wird in allen Zeilen ersetzt, das LGS fuer simult
-- wird dadurch kleiner. Das greift besonders bei starren Staeben, deren Konstanten unmittelbar an
-- denen des Nachbarstabs haengen (gleiche Verdrehung, gleiche Normalkraft ...).
-- Liefert bekannte Werte, verbleibende Zeilen und die vorab eliminierten Unbekannten mit ihrer Zeile.
local function neuVorElimination(rows, mitAlias)
    local values, reihe = {}, {}
    -- wannBekannt[j] = Schritt, in dem x_j feststand (fuer die Anzeige: nur vorher Bekanntes einsetzen)
    local wannBekannt, schritt = {}, 0
    -- Zahlenwert eines Koeffizienten-Strings (Zahlen, + - * / ^ und Klammern), sonst nil
    local function num(txt)
        if type(txt) ~= "string" then return nil end
        local pos, expr = 1, nil
        local function leer() while txt:sub(pos, pos) == " " do pos = pos + 1 end end
        local function prim()
            leer()
            local ch = txt:sub(pos, pos)
            if ch == "(" then
                pos = pos + 1
                local v = expr()
                leer()
                if v == nil or txt:sub(pos, pos) ~= ")" then return nil end
                pos = pos + 1
                return v
            end
            if ch == "-" then pos = pos + 1; local v = prim(); if v == nil then return nil end; return -v end
            if ch == "+" then pos = pos + 1; return prim() end
            local z = txt:match("^%d*%.?%d+", pos)
            if not z then return nil end
            pos = pos + #z
            local e = txt:match("^[eE][%+%-]?%d+", pos)
            if e then pos = pos + #e; z = z .. e end
            return tonumber(z)
        end
        local function pot()
            local a = prim()
            if a == nil then return nil end
            leer()
            if txt:sub(pos, pos) == "^" then
                pos = pos + 1
                local b = pot()
                if b == nil then return nil end
                return a ^ b
            end
            return a
        end
        local function term()
            local a = pot()
            while a ~= nil do
                leer()
                local ch = txt:sub(pos, pos)
                if ch ~= "*" and ch ~= "/" then return a end
                pos = pos + 1
                local b = pot()
                if b == nil or (ch == "/" and b == 0) then return nil end
                a = (ch == "*") and (a * b) or (a / b)
            end
            return nil
        end
        expr = function()
            local a = term()
            while a ~= nil do
                leer()
                local ch = txt:sub(pos, pos)
                if ch ~= "+" and ch ~= "-" then return a end
                pos = pos + 1
                local b = term()
                if b == nil then return nil end
                a = (ch == "+") and (a + b) or (a - b)
            end
            return nil
        end
        local v = expr()
        leer()
        if v == nil or pos <= #txt then return nil end
        return v
    end
    -- bekannten Wert einsetzen
    local function setzeWert(r, j, val)
        local cj = r.c[j]
        r.k = (r.k == "0") and ("(" .. cj .. ")*(" .. val .. ")") or (r.k .. "+(" .. cj .. ")*(" .. val .. ")")
        r.c[j] = nil
    end
    -- Alias x_j = f*x_m + k einsetzen (Zahlenkoeffizienten werden zusammengefasst)
    local function setzeAlias(r, j, a)
        local cj = r.c[j]
        r.c[j] = nil
        local cn, alt = num(cj), r.c[a.m]
        local an = alt and num(alt) or 0
        if cn and a.fn and (alt == nil or num(alt)) then
            local s = an + cn * a.fn
            local gr = math.max(math.abs(an), math.abs(cn * a.fn))
            r.c[a.m] = (math.abs(s) <= 1e-12 * gr) and nil or neuZahl(s)
        else
            local term = "(" .. cj .. ")*(" .. a.f .. ")"
            r.c[a.m] = alt and (alt .. "+" .. term) or term
        end
        if a.k ~= "0" then
            r.k = (r.k == "0") and ("(" .. cj .. ")*(" .. a.k .. ")") or (r.k .. "+(" .. cj .. ")*(" .. a.k .. ")")
        end
    end
    local changed = true
    while changed do
        changed = false
        -- 1) Zeilen mit einer Unbekannten liefern direkt einen Wert
        for _, r in ipairs(rows) do
            if not r.done then
                for j in pairs(r.c) do if values[j] then setzeWert(r, j, values[j]) end end
                local count, single = 0, nil
                for j in pairs(r.c) do count = count + 1; single = j end
                if count == 1 then
                    schritt = schritt + 1
                    values[single] = "-(" .. r.k .. ")/(" .. r.c[single] .. ")"
                    wannBekannt[single] = schritt
                    r.done = true; r.schritt = schritt; r.quelle = single; changed = true
                elseif count == 0 then
                    r.done = true; r.schritt = schritt; changed = true
                end
            end
        end
        -- 2) Unbekannte, die nur in einer Zeile vorkommen: Zeile und Unbekannte fallen aus dem LGS,
        -- der Wert wird am Schluss aus dieser Zeile nachgerechnet (kein Einsetzen, keine Aufblaehung)
        if not changed then
            local zahl, zeile = {}, {}
            for _, r in ipairs(rows) do
                if not r.done then
                    for j in pairs(r.c) do zahl[j] = (zahl[j] or 0) + 1; zeile[j] = r end
                end
            end
            for j, n in pairs(zahl) do
                if n == 1 and not zeile[j].done then
                    local satz = {}
                    for j2 in pairs(zeile[j].c) do satz[#satz + 1] = j2 end
                    reihe[#reihe + 1] = { j = j, r = zeile[j], satz = satz }
                    zeile[j].done = true; changed = true
                end
            end
        end
        -- 3) Zeilen mit zwei Unbekannten: die mit dem groesseren Zahlenkoeffizienten wird ersetzt
        if not changed and mitAlias then
            for _, r in ipairs(rows) do
                if not r.done then
                    local idx = {}
                    for j in pairs(r.c) do idx[#idx + 1] = j end
                    if #idx == 2 then
                        local a, b = idx[1], idx[2]
                        local na, nb = num(r.c[a]), num(r.c[b])
                        local j, m, cj
                        if na and nb then
                            if math.abs(na) >= math.abs(nb) then j, m, cj = a, b, na else j, m, cj = b, a, nb end
                        elseif na then j, m, cj = a, b, na
                        elseif nb then j, m, cj = b, a, nb end
                        if j and math.abs(cj) > 1e-12 then
                            local mn = num(r.c[m])
                            local fn = mn and (-mn / cj) or nil
                            -- nur reine Zahlenverhaeltnisse ohne Konstante einsetzen: x_j = f*x_m.
                            -- Alles andere wuerde die Zeilen verlaengern und kostet am Ende mehr Zeit,
                            -- als das kleinere LGS spart (lange Ausdruecke in exact/limit).
                            if fn and r.k == "0" then
                                local a_j = { m = m, f = neuZahl(fn), fn = fn, k = "0" }
                                reihe[#reihe + 1] = { j = j, r = r, satz = { j, m } }
                                r.done = true; changed = true
                                for _, r2 in ipairs(rows) do
                                    if not r2.done and r2.c[j] then setzeAlias(r2, j, a_j) end
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    local rest = {}
    for _, r in ipairs(rows) do if not r.done then rest[#rest + 1] = r end end
    -- Zeilen, die nach der Vorelimination noch zusammenhaengen (fuer die Trennung Biege-/Laengslinie)
    local koppel = {}
    for _, r in ipairs(rest) do
        local t = {}
        for j in pairs(r.c) do t[#t + 1] = j end
        koppel[#koppel + 1] = { r = r, satz = t }
    end
    for _, e in ipairs(reihe) do koppel[#koppel + 1] = { r = e.r, satz = e.satz } end
    return values, rest, reihe, wannBekannt, koppel
end

-- Fehler melden: Status und randbed = {"Fehler: ..."} (auf dem Rechner im Calculator sichtbar)
local function neuFehler(text)
    neuExportStatus(text, "Export fehlgeschlagen")
    if math.eval then pcall(math.eval, 'randbed:=["Fehler: ' .. tostring(text):gsub('"', "'") .. '"]') end
    return false
end

-- LGS aufstellen, loesen und exportieren. direkt = true: starre Staebe ohne Grenzwert (Starrkoerperbewegung
-- plus Gleichgewicht). Rueckgabe true oder false, { text, singulaer }.
local function neuRandLGSLoesen(direkt, methodeInfo)
    local function fehler(text, singulaer) return false, { text = text, singulaer = singulaer } end
    -- Stabdaten
    local bars = {}
    for i, s in ipairs(staebe) do
        local k1, k2 = knoten[s.k1], knoten[s.k2]
        local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
        if L > 0 and not s.is_cut and not s.is_virtual_parent then
            bars[#bars + 1] = neuStabDaten(i, s, #bars * 6, direkt)
        end
    end
    if #bars == 0 then return fehler("Kein gueltiger Stab") end
    -- Stabenden je Knoten
    local byNode = {}
    for _, d in ipairs(bars) do
        local s = d.s
        local relA = knoten[s.k1].gelenk or s.gelenk_A
        local relB = knoten[s.k2].gelenk or s.gelenk_B
        byNode[s.k1] = byNode[s.k1] or {}
        byNode[s.k2] = byNode[s.k2] or {}
        table.insert(byNode[s.k1], { d = d, side = "A", g = d.A, relM = relA, relN = s.n_gelenk_A, relQ = s.q_gelenk_A })
        table.insert(byNode[s.k2], { d = d, side = "B", g = d.B, relM = relB, relN = s.n_gelenk_B, relQ = s.q_gelenk_B })
    end
    local conds, extra = {}, { n = #bars * 6, names = {}, knoten = {} }
    for kidx = 1, #knoten do
        if byNode[kidx] then neuKnotenBedingungen(kidx, knoten[kidx], byNode[kidx], conds, extra) end
    end
    if extra.fehler then return fehler(extra.fehler) end
    local nUnknown = extra.n
    -- Zeilen aufbauen (die Anzeigetexte erst nach der Vorelimination, dann mit eingesetzten Werten)
    local rows = {}
    for _, cond in ipairs(conds) do
        local r = rlBedZeile(cond)
        r.idx = #rows + 1
        r.satzOrig = {}
        for j in pairs(r.c) do r.satzOrig[#r.satzOrig + 1] = j end
        rows[#rows + 1] = r
    end
    neuShowMessage(#rows .. " Bedingungen, " .. nUnknown .. " Unbekannte" .. (direkt and " (starre Staebe direkt)" or ""))
    if #rows ~= nUnknown then
        return fehler("Rand-LGS nicht quadratisch: " .. #rows .. " Bedingungen, " .. nUnknown .. " Unbekannte")
    end
    -- Vorelimination und Loesung
    -- Beim Grenzwert (rleps) werden die Ausdruecke durch das Einsetzen zu gross: dort nur Zeilen
    -- und Unbekannte streichen, die ohne Einsetzen wegfallen.
    local mitEps = false
    for _, d in ipairs(bars) do if (d.starr or d.starrI) and not direkt then mitEps = true end end
    local values, rest, vorab, wannBekannt, koppel = neuVorElimination(rows, not mitEps)
    -- Anzeigetexte: was vor einer Bedingung schon feststand (meist 0), wird eingesetzt.
    -- So steht dort "w1(x1=l)=0" statt "w1(x1=l)=u2(x2=3*l)", wenn u2 dehnstarr und gehalten ist.
    local texts = {}
    -- w-Unbekannte (c1..c4, Biegelinie) und u-Unbekannte (C1, C2, Laengslinie) eines Stabes
    local function typVon(j)
        if j > #bars * 6 then return "n" end   -- Knotenverschiebung, gehoert zu beiden
        return (((j - 1) % 6 + 1) <= 4) and "w" or "u"
    end
    do
        local cache = {}
        local function wertVon(q, grenze)
            local c = cache[q]
            if c == nil then
                local teile, schritt, ok = {}, 0, true
                for j, cj in pairs(q.lin.c) do
                    local s, w = wannBekannt[j], values[j]
                    if not s or not w then ok = false; break end
                    if s > schritt then schritt = s end
                    if w ~= "0" then teile[#teile + 1] = "(" .. cj .. ")*(" .. w .. ")" end
                end
                local wert
                if ok then
                    local kq = (q.lin.k ~= "0") and q.lin.k or nil
                    if #teile == 0 and not kq then
                        wert = "0"
                    else
                        local expr = table.concat(teile, "+")
                        if kq then expr = (expr == "") and kq or (expr .. "+" .. kq) end
                        if #expr <= 200 then
                            -- Grenzwertmethode: die Konstanten starrer Staebe enthalten rleps, die
                            -- Groesse selbst ist endlich -> Grenzwert bilden (sonst nur vereinfachen)
                            local v = expr:find(RL_EPS, 1, true) and neuGrenzwert(expr) or neuExakt(expr)
                            -- nur kurze Werte anzeigen, sonst bleibt der Name stehen
                            if v and #v <= 24 and not v:find(RL_EPS, 1, true) then wert = v end
                        end
                    end
                end
                c = wert and { wert = wert, schritt = schritt } or false
                cache[q] = c
            end
            if c and c.schritt < grenze then return c.wert end
            return nil
        end
        for i, cond in ipairs(conds) do
            local grenze = rows[i].schritt or math.huge
            local t, offen = rlBedText(cond, function(q) return wertVon(q, grenze) end)
            local roh = not (offen and offen > 0)
            texts[i] = roh and rlBedText(cond) or t
            -- welche Art von Groessen steht im Text noch mit Namen da (nicht eingesetzt)?
            local zeigt = {}
            for _, tm in ipairs(cond.terms) do
                if roh or not wertVon(tm.q, grenze) then
                    for j in pairs(tm.q.lin.c) do
                        local ty = typVon(j)
                        if ty ~= "n" then zeigt[ty] = true end
                    end
                end
            end
            rows[i].zeigt = zeigt
        end
    end
    local weg = {}
    for _, e in ipairs(vorab) do weg[e.j] = true end
    local restIdx = {}
    for j = 1, nUnknown do if not values[j] and not weg[j] then restIdx[#restIdx + 1] = j end end
    if #rest ~= #restIdx then
        return fehler("Rand-LGS singulaer (" .. #rest .. " Gleichungen fuer " .. #restIdx .. " Unbekannte): System kinematisch?", true)
    end
    -- Das verbleibende System zerfaellt oft in unabhaengige Bloecke (z. B. Biegung und Laengskraft):
    -- jeder Block wird einzeln mit simult geloest, das ist deutlich schneller als ein grosses LGS.
    local bloecke = {}
    if #restIdx > 0 then
        local wz = {}
        local function suche(j)
            while wz[j] and wz[j] ~= j do j = wz[j] end
            return j
        end
        for _, j in ipairs(restIdx) do wz[j] = j end
        for _, r in ipairs(rest) do
            local erste
            for j in pairs(r.c) do
                if erste then
                    local a, b = suche(erste), suche(j)
                    if a ~= b then wz[b] = a end
                else
                    erste = j
                end
            end
        end
        local nach, teilbar = {}, true
        local function block(w)
            if not nach[w] then
                nach[w] = { zeilen = {}, unbek = {}, nr = #bloecke + 1 }
                bloecke[#bloecke + 1] = nach[w]
            end
            return nach[w]
        end
        for _, r in ipairs(rest) do
            local erste
            for j in pairs(r.c) do erste = j; break end
            if not erste then teilbar = false; break end
            local b = block(suche(erste))
            b.zeilen[#b.zeilen + 1] = r
            r.block = b.nr
        end
        for _, j in ipairs(restIdx) do
            local b = block(suche(j))
            b.unbek[#b.unbek + 1] = j
        end
        for _, b in ipairs(bloecke) do if #b.zeilen ~= #b.unbek then teilbar = false end end
        if not teilbar then                      -- im Zweifel alles zusammen loesen
            bloecke = { { zeilen = rest, unbek = restIdx, nr = 1 } }
            for _, r in ipairs(rest) do r.block = 1 end
        end
    end
    for _, b in ipairs(bloecke) do
        local aRows, bRows = {}, {}
        for r = 1, #b.zeilen do
            local entries = {}
            for c = 1, #b.unbek do entries[c] = b.zeilen[r].c[b.unbek[c]] or "0" end
            aRows[r] = table.concat(entries, ",")
            bRows[r] = "-(" .. b.zeilen[r].k .. ")"
        end
        neuShowMessage("simult mit " .. #b.unbek .. " Unbekannten"
            .. ((#bloecke > 1) and (" (Block " .. b.nr .. " von " .. #bloecke .. ")") or ""))
        local cmd = "exact(simult([[" .. table.concat(aRows, "][") .. "]],[[" .. table.concat(bRows, "][") .. "]]))"
        local ok, res = pcall(neuCasString, cmd)
        if not ok or not res or res:sub(1, 2) ~= "[[" then
            local msg = tostring(res):gsub("^.-__ERROR__", ""):gsub("^[^%s]-:%d+: ", "")
            return fehler("Rand-LGS nicht loesbar (" .. msg:sub(1, 50) .. "): System kinematisch?", true)
        end
        local body = res:sub(3, -3)
        local c = 0
        for v in (body .. "]["):gmatch("(.-)%]%[") do
            c = c + 1
            if b.unbek[c] then values[b.unbek[c]] = v end
        end
        if c ~= #b.unbek then return fehler("Rand-LGS: unerwartete Loesung " .. res:sub(1, 40)) end
    end
    -- Welche Bedingungen braucht man nur fuer die Biegelinie (w), welche nur fuer die Laengslinie (u)?
    -- Dazu von den gesuchten Konstanten aus rueckwaerts durch die Zeilen gehen, die sie bestimmen.
    -- Groessen, die vorab feststehen, sind dabei Zahlen (sie stehen eingesetzt im Text) und trennen nicht.
    local bestimmt = {}                      -- Unbekannte -> Zeilennummer bzw. simult-Block
    for _, r in ipairs(rows) do if r.quelle then bestimmt[r.quelle] = r.idx end end
    for _, e in ipairs(vorab) do bestimmt[e.j] = e.r.idx end
    for _, b in ipairs(bloecke) do for _, j in ipairs(b.unbek) do bestimmt[j] = b end end
    local function huelle(typ)
        local zeilen, stapel, unbek, drin, rein = {}, {}, {}, {}, true
        local function nimmZeile(ri)
            if zeilen[ri] then return end
            zeilen[ri] = true
            for ty in pairs(rows[ri].zeigt or {}) do if ty ~= typ then rein = false end end
            for _, j2 in ipairs(rows[ri].satzOrig) do
                local ty = typVon(j2)
                if ty ~= typ and ty ~= "n" and not wannBekannt[j2] then rein = false end
                if not unbek[j2] and (ty == typ or ty == "n" or not wannBekannt[j2]) then
                    unbek[j2] = true; stapel[#stapel + 1] = j2
                end
            end
        end
        for j = 1, #bars * 6 do
            if typVon(j) == typ then unbek[j] = true; stapel[#stapel + 1] = j end
        end
        while #stapel > 0 do
            local b = bestimmt[table.remove(stapel)]
            if type(b) == "table" then
                if not drin[b.nr] then
                    drin[b.nr] = true
                    for _, r in ipairs(b.zeilen) do nimmZeile(r.idx) end
                end
            elseif b then
                nimmZeile(b)
            end
        end
        return zeilen, rein
    end
    local wZeilen, nurW = huelle("w")
    local uZeilen, nurU = huelle("u")
    -- gekoppelt nur ueber dehnsteife Staebe (Rahmen): u und N durchreichen wie von Hand
    local durch = (not nurW and not nurU) and neuDurchreichen(conds, typVon, #bars * 4) or nil
    -- vorab eliminierte Unbekannte rueckwaerts aus ihrer Zeile nachrechnen (alle anderen sind bekannt)
    for i = #vorab, 1, -1 do
        local e = vorab[i]
        local summe = e.r.k
        for j2, cj in pairs(e.r.c) do
            if j2 ~= e.j then summe = summe .. "+(" .. cj .. ")*(" .. (values[j2] or "0") .. ")" end
        end
        local v = "-(" .. summe .. ")/(" .. e.r.c[e.j] .. ")"
        -- lange Ausdruecke einmal vereinfachen: sonst wachsen sie beim weiteren Einsetzen stark an
        values[e.j] = (#v > 60) and neuExakt(v) or v
    end
    if #vorab > 0 then neuShowMessage(#vorab .. " Unbekannte vorab eliminiert") end
    local dehnListe, biegeListe, uListe, wListe = {}, {}, {}, {}
    local uStarr, wStarr, spezial = {}, {}, {}
    for _, d in ipairs(bars) do
        if d.starr then dehnListe[#dehnListe + 1] = tostring(d.i); spezial[d.base + 6] = { d = d, art = "u" } end
        if d.starrI then
            biegeListe[#biegeListe + 1] = tostring(d.i)
            spezial[d.base + 3] = { d = d, art = "w" }; spezial[d.base + 4] = { d = d, art = "w" }
        end
    end
    if #dehnListe + #biegeListe > 0 and not direkt then
        -- Grenzwert rleps -> 0 fuer alle Konstanten. C2 = EA*u(0) bzw. c3, c4 (EI*w-Anteile der
        -- Starrkoerperbewegung) sind nur endlich, wenn sich der Stab nicht als Ganzes bewegt; sonst
        -- werden u(x) bzw. w(x) exportiert.
        neuShowMessage("Starre Staebe: Grenzwert fuer dehnsteif " .. table.concat(dehnListe, ",") .. " / biegesteif " .. table.concat(biegeListe, ","))
        local teil = {}
        for j, sp in pairs(spezial) do
            teil[j] = neuGrenzwert(RL_EPS .. "*(" .. (values[j] or "0") .. ")")
            if not teil[j] then return fehler("Starrer Stab " .. sp.d.i .. ": Grenzwert nicht bestimmbar") end
        end
        for _, d in ipairs(bars) do
            local b = d.base
            if d.starr and not (teil[b + 6] == "0" and not d.eTs) then uStarr[d.i] = teil[b + 6] end
            if d.starrI and not (teil[b + 3] == "0" and teil[b + 4] == "0" and not d.kTs) then wStarr[d.i] = { teil[b + 3], teil[b + 4] } end
        end
        for j = 1, nUnknown do
            local sp = spezial[j]
            if sp and ((sp.art == "u" and uStarr[sp.d.i]) or (sp.art == "w" and wStarr[sp.d.i])) then
                values[j] = "0"   -- wird nicht gebraucht, Export ueber u(x) bzw. w(x)
            else
                values[j] = neuGrenzwert(values[j] or "0")
                if not values[j] then
                    return fehler("Starre Staebe: unendliche Zwangskraft (z. B. Temperatur in gehaltenem starrem Stab)")
                end
            end
        end
    else
        -- Konstanten stammen aus exact(simult(...)); vereinfacht wird erst beim Export der Funktionen
        for j = 1, nUnknown do values[j] = values[j] or "0" end
        if direkt then
            -- direkt: die Konstanten starrer Staebe sind die Starrkoerperbewegung selbst
            for _, d in ipairs(bars) do
                local b = d.base
                if d.starrI then wStarr[d.i] = { values[b + 3], values[b + 4] } end
                if d.starr then uStarr[d.i] = values[b + 6] end
            end
        end
    end
    local count, ergStab = 0, {}
    for _, d in ipairs(bars) do
        local b = d.base
        local ew, eu
        if wStarr[d.i] then
            -- EI*w unendlich bzw. starr: w(x) = -kappaT*x^2/2 + Starrkoerperbewegung
            ew = "-(" .. (d.kTs or "0") .. ")*x^2/2+(" .. wStarr[d.i][1] .. ")*x+(" .. wStarr[d.i][2] .. ")"
            wListe[#wListe + 1] = d.i
        else
            ew = d.wp .. "+(" .. values[b + 1] .. ")*x^3/6+(" .. values[b + 2] .. ")*x^2/2+(" .. values[b + 3] .. ")*x+(" .. values[b + 4] .. ")"
        end
        if uStarr[d.i] then
            -- EA*u unendlich bzw. starr: u(x) = epsT*x + u(0)
            eu = "(" .. (d.eTs or "0") .. ")*x+(" .. uStarr[d.i] .. ")"
            uListe[#uListe + 1] = d.i
        else
            eu = d.up .. "+(" .. values[b + 5] .. ")*x+(" .. values[b + 6] .. ")"
        end
        -- exakt (keine Rundung); auf dem Rechner bei Bedarf approx(wneu1(x)) verwenden
        if not neuCasEval("wneu" .. d.i .. "(x):=" .. neuExakt(ew), "wneu" .. d.i) then return fehler("Export wneu" .. d.i .. " fehlgeschlagen") end
        if not neuCasEval("uneu" .. d.i .. "(x):=" .. neuExakt(eu), "uneu" .. d.i) then return fehler("Export uneu" .. d.i .. " fehlgeschlagen") end
        -- Verschiebungen direkt (z. B. solve(uv2(l)=0,dt) oder solve(wv1(l)=1/2,f)):
        -- EI*w bzw. EA*u geteilt durch die Steifigkeit; starre Staebe ohne Starrkoerperbewegung: 0
        local wv = wStarr[d.i] and ew or (d.starrI and "0" or ("(" .. ew .. ")/(" .. d.EI .. ")"))
        local uv = uStarr[d.i] and eu or (d.starr and "0" or ("(" .. eu .. ")/(" .. d.EA .. ")"))
        wv, uv = neuExakt(wv), neuExakt(uv)
        if not neuCasEval("wv" .. d.i .. "(x):=" .. wv, "wv" .. d.i) then return fehler("Export wv" .. d.i .. " fehlgeschlagen") end
        if not neuCasEval("uv" .. d.i .. "(x):=" .. uv, "uv" .. d.i) then return fehler("Export uv" .. d.i .. " fehlgeschlagen") end
        -- fuer die Knotenverschiebungen merken; phi = -w' (starr: w = -kappaT*x^2/2 + c3*x + c4)
        local phi
        if wStarr[d.i] then
            phi = "(" .. (d.kTs or "0") .. ")*x-(" .. wStarr[d.i][1] .. ")"
        elseif d.starrI then
            phi = "0"
        else
            phi = "-((" .. d.wp1 .. ")+(" .. values[b + 1] .. ")*x^2/2+(" .. values[b + 2] .. ")*x+(" .. values[b + 3] .. "))/(" .. d.EI .. ")"
        end
        ergStab[d.i] = { wv = wv, uv = uv, phi = phi, Ls = d.Ls, tx = d.tx, ty = d.ty, nx = d.nx, ny = d.ny }
        count = count + 1
    end
    -- Referenz-Stabenden je Knoten wie in neuKnotenBedingungen: Verschiebung ueber ein Stabende ohne
    -- N-/Q-Gelenk (sonst die Knoten-Unbekannten ux(K), uy(K)), Verdrehung ueber eines ohne M-Gelenk
    local ergEnde = {}
    for kidx, ends in pairs(byNode) do
        local r = {}
        for _, e in ipairs(ends) do
            if not r.trans and not e.relN and not e.relQ then r.trans = { i = e.d.i, side = e.side } end
            if not r.rot and not e.relM then r.rot = { i = e.d.i, side = e.side } end
        end
        local ju = extra.knoten[kidx]
        if ju then r.ux, r.uy = values[ju[1]] or "0", values[ju[2]] or "0" end
        ergEnde[kidx] = r
    end
    randErgebnis = { stab = ergStab, ende = ergEnde, knoten = {} }
    -- Hinweise zur Bedeutung der Funktionen
    local info = {}
    if #dehnListe > 0 then info[#info + 1] = "dehnsteif (EA->unendlich): Stab " .. table.concat(dehnListe, ",") end
    if #biegeListe > 0 then info[#info + 1] = "biegesteif (EI->unendlich): Stab " .. table.concat(biegeListe, ",") end
    local grund = direkt and " (starr)" or ", da EI*w unendlich"
    for _, i in ipairs(wListe) do info[#info + 1] = "wneu" .. i .. "(x)=w" .. i .. "(x)" .. grund end
    grund = direkt and " (starr)" or ", da EA*u unendlich"
    for _, i in ipairs(uListe) do info[#info + 1] = "uneu" .. i .. "(x)=u" .. i .. "(x)" .. grund end
    if #info == 0 then info[1] = "keine starren Staebe: wneu_i(x)=EI*w_i(x), uneu_i(x)=EA*u_i(x)" end
    if methodeInfo then info[#info + 1] = methodeInfo end
    if nurW and nurU then
        info[#info + 1] = "Biege- und Laengslinie unabhaengig: randbed in zwei Gruppen"
    elseif nurW then
        info[#info + 1] = "Biegelinie w ohne Laengslinie loesbar: erste Gruppe in randbed"
    elseif nurU then
        info[#info + 1] = "Laengslinie u ohne Biegelinie loesbar: erste Gruppe in randbed"
    elseif durch then
        info[#info + 1] = "Biegelinie w ohne Laengslinie loesbar: erste Gruppe in randbed (u und N der dehnsteifen Staebe eingesetzt)"
    end
    info[#info + 1] = "Verschiebungen: wv_i(x)=w_i(x), uv_i(x)=u_i(x)"
    for i, t in ipairs(info) do info[i] = '"' .. t .. '"' end
    pcall(math.eval, "randinfo:=[" .. table.concat(info, ";") .. "]")
    -- Bedingungsliste als Strings; bei entkoppelten Linien nach w und u sortiert mit Ueberschrift
    local quoted = {}
    if durch then
        -- zusammengefasste Bedingungen fuer w, danach die, die u und N der dehnsteifen Staebe liefern
        quoted[#quoted + 1] = '"--- Biegelinie w: diese genuegen ---"'
        for _, e in ipairs(durch.w) do quoted[#quoted + 1] = '"' .. (e.text or texts[e.i]) .. '"' end
        quoted[#quoted + 1] = '"--- zusaetzlich fuer Laengslinie u ---"'
        for _, i in ipairs(durch.u) do quoted[#quoted + 1] = '"' .. texts[i] .. '"' end
    elseif nurW or nurU then
        -- erst die Bedingungen, die fuer eine Linie allein genuegen, dann der Rest
        local erst, zweit, titel1, titel2
        if nurW and nurU then
            erst, zweit = wZeilen, uZeilen
            titel1, titel2 = "--- nur Biegelinie w ---", "--- nur Laengslinie u ---"
        elseif nurW then
            erst, titel1, titel2 = wZeilen, "--- Biegelinie w: diese genuegen ---", "--- zusaetzlich fuer Laengslinie u ---"
        else
            erst, titel1, titel2 = uZeilen, "--- Laengslinie u: diese genuegen ---", "--- zusaetzlich fuer Biegelinie w ---"
        end
        quoted[#quoted + 1] = '"' .. titel1 .. '"'
        for i, t in ipairs(texts) do if erst[i] then quoted[#quoted + 1] = '"' .. t .. '"' end end
        quoted[#quoted + 1] = '"' .. titel2 .. '"'
        for i, t in ipairs(texts) do
            if not erst[i] and (zweit == nil or zweit[i]) then quoted[#quoted + 1] = '"' .. t .. '"' end
        end
        if zweit then
            for i, t in ipairs(texts) do
                if not erst[i] and not zweit[i] then quoted[#quoted + 1] = '"' .. t .. '"' end
            end
        end
    else
        for i, t in ipairs(texts) do quoted[i] = '"' .. t .. '"' end
    end
    pcall(math.eval, "randbed:=[" .. table.concat(quoted, ";") .. "]")   -- Spaltenvektor aus Strings
    -- starre Staebe nennen, bei denen wneu bzw. uneu die Verschiebung selbst ist (keine neuen Locals:
    -- die Funktion ist nah an der Grenze von 200 lokalen Variablen)
    neuExportStatus("Rand-LGS: " .. count .. " Staebe, " .. #texts .. " Bedingungen -> wneu_i(x)=EI*w, uneu_i(x)=EA*u, wv_i(x)=w, uv_i(x)=u, randbed"
        .. ((#wListe > 0) and (". Starr: wneu=w bei Stab " .. table.concat(wListe, ",")) or "")
        .. ((#uListe > 0) and (((#wListe > 0) and ", uneu=u bei Stab " or ". Starr: uneu=u bei Stab ") .. table.concat(uListe, ",")) or "")
        .. ((#wListe + #uListe > 0) and " (siehe randinfo)" or ""))
    return true
end

-- Hauptfunktion: Pruefungen, alte Ergebnisse loeschen, loesen (starre Staebe direkt, bei gegenseitig
-- statisch unbestimmten starren Teilen automatisch ueber den Grenzwert)
local function neuRandLGS()
    neuShowMessage("Rand-LGS gestartet")
    if not math.eval then neuExportStatus("Fehler: CAS nicht verfuegbar!", "Export fehlgeschlagen"); return false end
    -- alte Ergebnisse loeschen, damit nach einem Abbruch nichts Veraltetes stehen bleibt
    local alt = { "randbed", "randinfo", RL_EPS }
    for i = 1, math.max(30, #staebe) do
        alt[#alt + 1] = "wneu" .. i; alt[#alt + 1] = "uneu" .. i; alt[#alt + 1] = "wv" .. i; alt[#alt + 1] = "uv" .. i
    end
    -- Knotenverschiebungen nur loeschen, wenn sie zu einem anderen System gehoeren
    local schluessel = randLGSCacheSchluessel()
    if not (randErgebnis and randErgebnis.schluessel == schluessel) then
        for i = 1, math.max(30, #knoten) do
            alt[#alt + 1] = "ux_k" .. i; alt[#alt + 1] = "uy_k" .. i; alt[#alt + 1] = "phi_k" .. i
        end
    end
    randErgebnis = nil
    pcall(math.eval, "DelVar " .. table.concat(alt, ","))
    if #staebe == 0 then return neuFehler("Keine Staebe vorhanden") end
    if symbolFehler then return neuFehler("Symbolischer Modus: " .. symbolFehler) end
    if KGV_Zustand and KGV_Zustand > 0 then
        return neuFehler("Rand-LGS nicht im KGV-Einheitszustand X" .. KGV_Zustand .. " (Zustand 0 waehlen)")
    end
    local hatStarr = false
    for i, s in ipairs(staebe) do
        local k1, k2 = knoten[s.k1], knoten[s.k2]
        local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
        if (s.bogen_r or 0) ~= 0 and L > 0 and math.abs(s.bogen_r) >= L / 2 then
            return neuFehler("Stab " .. i .. ": Boegen werden vom Rand-LGS nicht unterstuetzt")
        end
        if stabBiegesteif(s) or stabDehnsteif(s) then hatStarr = true end
    end
    local direkt = hatStarr and randStarrDirekt
    local ok, err = neuRandLGSLoesen(direkt, hatStarr and (direkt and "starre Staebe: direkt" or "starre Staebe: Grenzwert") or nil)
    if not ok and direkt and err and err.singulaer then
        neuShowMessage("Starre Staebe direkt singulaer (gegenseitig statisch unbestimmt): Grenzwert-Methode")
        ok, err = neuRandLGSLoesen(false, "starre Staebe: Grenzwert (direkt singulaer, starre Teile gegenseitig statisch unbestimmt)")
    end
    if not ok then randErgebnis = nil; return neuFehler(err and err.text or "Rand-LGS fehlgeschlagen") end
    if randErgebnis then randErgebnis.schluessel = schluessel end
    return true
end

-- Neuer Export 1: Biegelinie ueber globales Rand-LGS (exportiert auch Laengslinie).
exportBiegelinienNeuToTI = function()
    neuShowMessage("Export Biegelinie (Rand-LGS)")
    return neuRandLGS()
end

-- Neuer Export 2: Laengslinie ueber globales Rand-LGS (identisches LGS).
exportULinienNeuToTI = function()
    neuShowMessage("Export Laengslinie (Rand-LGS)")
    return neuRandLGS()
end

-- Knotenverschiebung aus dem Rand-LGS (Knotenmenue Seite 4, Zeile 1): ux_k<i>, uy_k<i> global
-- (x nach rechts, y nach unten), phi_k<i> gegen den Uhrzeigersinn. Die Biege- und Laengslinien werden
-- nur neu aufgebaut, wenn sich das System seit dem letzten Rand-LGS geaendert hat.
function exportKnotenVerschiebungToTI(kidx)
    local titel = "Knoten " .. tostring(kidx) .. ": Verschiebung"
    if not math.eval then neuExportStatus("Fehler: CAS nicht verfuegbar!", "Export fehlgeschlagen"); return false end
    local k = knoten[kidx]
    if not k then return false end
    if randErgebnis and randErgebnis.schluessel == randLGSCacheSchluessel() then
        neuShowMessage("Rand-LGS aus dem Speicher (System unveraendert)")
    elseif not neuRandLGS() then
        return false
    end
    local erg = randErgebnis
    if not erg then neuExportStatus("Rand-LGS ohne Ergebnis", "Export fehlgeschlagen"); return false end
    local r = erg.knoten[kidx]
    if not r then
        local e = erg.ende[kidx]
        if not e then neuExportStatus("Knoten " .. kidx .. " haengt an keinem Stab.", "Export fehlgeschlagen"); return false end
        -- Groesse (uv, wv oder phi) am Stabende: x = 0 am Anfang, x = L am Ende
        local function amEnde(ref, feld)
            local st = erg.stab[ref.i]
            return st[feld]:subx((ref.side == "A") and "0" or ("(" .. st.Ls .. ")")), st
        end
        local ux, uy
        if e.trans then
            -- U = u*t + w*n mit t = (dx, dy)/L und n = (-dy, dx)/L
            local u, st = amEnde(e.trans, "uv")
            local w = amEnde(e.trans, "wv")
            local function komb(a, b)
                local t = {}
                if math.abs(a) > 1e-12 then t[#t + 1] = "(" .. neuZahl(a) .. ")*(" .. u .. ")" end
                if math.abs(b) > 1e-12 then t[#t + 1] = "(" .. neuZahl(b) .. ")*(" .. w .. ")" end
                return (#t > 0) and table.concat(t, "+") or "0"
            end
            ux, uy = komb(st.tx, st.nx), komb(st.ty, st.ny)
        else
            ux, uy = e.ux or "0", e.uy or "0"
        end
        r = { ux = neuExakt(ux), uy = neuExakt(uy) }
        if e.rot then r.phi = neuExakt((amEnde(e.rot, "phi"))) end
        erg.knoten[kidx] = r
    end
    local nx, ny, nphi = "ux_k" .. kidx, "uy_k" .. kidx, "phi_k" .. kidx
    pcall(math.eval, "DelVar " .. nx .. "," .. ny .. "," .. nphi)
    local ok = neuCasEval(nx .. ":=" .. r.ux, nx) and neuCasEval(ny .. ":=" .. r.uy, ny)
    if ok and r.phi then ok = neuCasEval(nphi .. ":=" .. r.phi, nphi) end
    if not ok then neuExportStatus("Knotenverschiebung konnte nicht gespeichert werden.", "Export fehlgeschlagen"); return false end
    local function kurz(t) return (#t > 40) and (t:sub(1, 37) .. "...") or t end
    neuExportStatus(nx .. " = " .. kurz(r.ux) .. "\n" .. ny .. " = " .. kurz(r.uy) .. "\n"
        .. (r.phi and (nphi .. " = " .. kurz(r.phi)) or "Gelenk: keine Knotenverdrehung")
        .. "\n(x nach rechts, y nach unten, phi gegen den Uhrzeigersinn)", titel)
    return true
end

function exportVerschiebungenToTI()
    if not exportBereit() then zeigeMeldung("Bitte zuerst das System berechnen (Taste B).", "Export fehlgeschlagen"); return end
    exportBiegelinienToTI()
    exportULinienToTI()
    zeigeMeldung("Verschiebungslinien (v*EI und u*EA) fuer alle Staebe exportiert.", "Export")
end

local function exportKGVToTI()
    if not autoKGV or #X_Werte == 0 then
        zeigeMeldung("KGV-Export: KGV ist nicht aktiv oder das System ist statisch bestimmt.", "Export fehlgeschlagen")
        return
    end
    print("Berechne KGV Matrizen...")
    local orig_zustand = KGV_Zustand
    local Delta0 = {}
    local Delta = {}
    local n = #X_Werte
    for i=1, n do Delta[i] = {} end
    
    -- Klaffung zur Freiwerteinheit X_i. Die Knotenfreiheitsgrade liegen schon im Lagersystem des
    -- Knotens (buildKnotenTransform: u_xi, u_eta), die Einheitslast eines Lagers wirkt in xi bzw. eta.
    local function getGap(x_val, u_vec)
        if x_val.typ == "lager_x" then
            return u_vec[knoten[x_val.knoten].eq_x] or 0
        elseif x_val.typ == "lager_y" then
            return u_vec[knoten[x_val.knoten].eq_y] or 0
        elseif x_val.typ == "lager_m" then 
            return u_vec[knoten[x_val.knoten].eq_m] or 0
        elseif x_val.typ == "gelenk_A" then
            local eq_node = knoten[staebe[x_val.stab].k1].eq_m
            local eq_stab = stabID[x_val.stab][3]
            local phi_node = (type(eq_node)=="number" and eq_node>0) and u_vec[eq_node] or 0
            local phi_stab = (eq_stab>0) and u_vec[eq_stab] or 0
            return phi_stab - phi_node
        elseif x_val.typ == "gelenk_B" then
            local eq_node = knoten[staebe[x_val.stab].k2].eq_m
            local eq_stab = stabID[x_val.stab][6]
            local phi_node = (type(eq_node)=="number" and eq_node>0) and u_vec[eq_node] or 0
            local phi_stab = (eq_stab>0) and u_vec[eq_stab] or 0
            return phi_stab - phi_node
        elseif x_val.typ == "pendel_n" then
            local s = staebe[x_val.stab]
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            local dx, dy = k2.x - k1.x, k2.y - k1.y
            local L = math.sqrt(dx^2+dy^2)
            if L <= 1e-12 then return 0 end
            local ux, uy = dx/L, dy/L
            -- Knotenverschiebung aus dem Lagersystem (xi, eta) zurueck ins globale System
            local function global(k)
                local u_xi = (k.eq_x > 0) and u_vec[k.eq_x] or 0
                local u_eta = (k.eq_y > 0) and u_vec[k.eq_y] or 0
                local b = math.rad(k.winkel or 0)
                return u_xi * math.cos(b) + u_eta * math.sin(b), -u_xi * math.sin(b) + u_eta * math.cos(b)
            end
            local u1x, u1y = global(k1)
            local u2x, u2y = global(k2)
            return (u1x - u2x)*ux + (u1y - u2y)*uy
        end
        return 0
    end
    
    -- Ein geloester Pendelstab ist aus dem System entfernt; seine eigene Laengenaenderung N*L/(EA)
    -- steckt nicht in den FEM-Knotenverschiebungen. Im Einheitszustand j traegt nur der eigene Stab
    -- N = 1, daher kommt L/(EA) genau zu delta_jj dazu (dehnsteife Staebe: 0). Ohne diesen Anteil
    -- waere das KGV nur fuer dehnstarre geloeste Staebe richtig.
    local function eigenNachgiebigkeit(x_val)
        if x_val.typ ~= "pendel_n" then return 0 end
        local s = staebe[x_val.stab]
        if not s or stabDehnsteif(s) then return 0 end
        local k1, k2 = knoten[s.k1], knoten[s.k2]
        local L = math.sqrt((k2.x - k1.x) ^ 2 + (k2.y - k1.y) ^ 2)
        if (s.EA or 0) <= 0 then return 0 end
        return L / s.EA
    end

    applyKGVZustand(0)
    local u0 = berechneSystemGleichungen(false)
    if u0 then for i, x_val in ipairs(X_Werte) do Delta0[i] = {getGap(x_val, u0)} end end
    
    for j = 1, n do
        applyKGVZustand(j)
        local uj = berechneSystemGleichungen(false)
        if uj then
            for i, x_val in ipairs(X_Werte) do
                Delta[i][j] = getGap(x_val, uj) + ((i == j) and eigenNachgiebigkeit(x_val) or 0)
            end
        end
    end
    
    applyKGVZustand(orig_zustand)
    rechneAktuellesSystem()
    
    speichereMatrix("kgv_delta", Delta)
    speichereMatrix("kgv_delta0", Delta0)
    zeigeMeldung("KGV-Matrizen exportiert: kgv_delta, kgv_delta0.", "Export")
end
local pvv_cas_cache = {}

function processDistLoad_PvV(L, L_eff, qs, qa, qb, R_cas, S_cas, R_num, S_num, load_type, skip_eval)
    local R_str, xS_str, S_str
    
    if symbolischer_modus and (qs or qa or qb or R_cas or S_cas) then
        local cache_key = string.format("%s_%s_%s_%s_%s_%s_%s_%s_%s", tostring(L_eff), tostring(qs), tostring(qa), tostring(qb), tostring(R_cas), tostring(S_cas), tostring(load_type), tostring(symbLSym), tostring(symbLDummy))
        if pvv_cas_cache[cache_key] then
            return pvv_cas_cache[cache_key].R, pvv_cas_cache[cache_key].S, pvv_cas_cache[cache_key].xS
        end
        
        local terms_R, terms_S = {}, {}
        if qs or qa or qb then
            qs = qs or "0"; qa = qa or "0"; qb = qb or "0"
            if load_type == "m" then
                table.insert(terms_R, string.format("(%s) * %s", qs, pvvLaenge(L_eff)))
            elseif load_type == "g" then
                table.insert(terms_R, string.format("(%s) * %s", qs, pvvLaenge(L_eff)))
                table.insert(terms_S, string.format("(%s) * %s", qs, pvvLaenge(L_eff * L/2, 2)))
            else
                table.insert(terms_R, string.format("((%s) + ((%s) + (%s))/2) * %s", qs, qa, qb, pvvLaenge(L_eff)))
                table.insert(terms_S, string.format("(3*(%s) + (%s) + 2*(%s)) * %s / 6", qs, qa, qb, pvvLaenge(L_eff^2, 2)))
            end
        end
        if R_cas then table.insert(terms_R, "("..R_cas..")") end
        if S_cas then table.insert(terms_S, "("..S_cas..")") end
        
        if #terms_R > 0 then
            R_str = table.concat(terms_R, " + ")
            if math.eval then R_str = eval_cas_string(R_str) or R_str end
            if R_str == "0" or R_str == "0." then R_str = nil end
        end
        if #terms_S > 0 then
            S_str = table.concat(terms_S, " + ")
            if math.eval then S_str = eval_cas_string(S_str) or S_str end
            if S_str == "0" or S_str == "0." then S_str = nil end
        end
        if R_str and S_str then
            xS_str = string.format("(%s)/(%s)", S_str, R_str)
            if math.eval then xS_str = eval_cas_string(xS_str) or xS_str end
        end
        pvv_cas_cache[cache_key] = {R = R_str, S = S_str, xS = xS_str}
    else
        if math.abs(R_num) > 1e-4 then R_str = fN_export(R_num) end
        if math.abs(S_num) > 1e-4 then S_str = fN_export(S_num) end
        if R_str and S_str and math.abs(R_num) > 1e-4 then xS_str = fN_export(S_num / R_num) end
    end
    return R_str, S_str, xS_str
end

-- Laenge (Zahl in Modelleinheiten) als Text fuer den PvV-Export: im symbolischen Modus als Vielfaches
-- des Laengensymbols (symbLSym, Zahlenwert symbLDummy), sonst als Zahl. potenz = Laengendimension
-- (1 Laenge, 2 Flaeche, -1 pro Laenge, 0 ohne Dimension).
function pvvLaenge(zahl, potenz)
    potenz = potenz or 1
    if not symbolischer_modus or potenz == 0 then return "(" .. fN_export(zahl) .. ")" end
    local wert = zahl / (symbLDummy or 1) ^ potenz
    if potenz == 1 then return "(" .. fN_export(wert) .. "*" .. symbLSym .. ")" end
    if potenz < 0 then return "(" .. fN_export(wert) .. "/" .. symbLSym .. (potenz < -1 and ("^" .. (-potenz)) or "") .. ")" end
    return "(" .. fN_export(wert) .. "*" .. symbLSym .. "^" .. potenz .. ")"
end

-- Wert einer Zeile von pvv_kin (Spalte 3) als kurzer Text fuer Zeichnung und Menues, so wie ihn der
-- Rechner vereinfacht anzeigt: zahl je Bezugsgroesse ref ("φ_0" bzw. "δ_0"), potenz = Laengendimension
-- wie bei pvvLaenge, z. B. -2*l*φ_0, -sqrt(2)*l*φ_0, φ_0
function pvvAnzeigeWert(zahl, potenz, ref)
    if math.abs(zahl) < 1e-12 then return "0" end
    local symb = symbolischer_modus and potenz ~= 0
    local wert = symb and zahl / (symbLDummy or 1) ^ potenz or zahl
    local c = fN_export(wert)
    if c:match("%.%d%d%d%d%d") then c = string.format("%.4g", wert) end
    local vorne = (c == "1") and "" or (c == "-1") and "-" or (c .. "*")
    if not symb then return vorne .. ref end
    if potenz == 1 then return vorne .. symbLSym .. "*" .. ref end
    if potenz == -1 then return vorne .. ref .. "/" .. symbLSym end
    return vorne .. symbLSym .. "^" .. potenz .. "*" .. ref
end

-- Arbeitssatz des PvV-Modus in drei Ebenen:
--   w_eq1   reines "Kraft mal Weg": jede Kraft mal ihren Weg (positiv in Richtung der Kraft), jedes
--           Moment mal den Drehwinkel phi_i seiner Scheibe (gegen den Uhrzeigersinn positiv)
--   pvv_kin Tabelle: Weg | durch die Bewegung der eigenen Scheibe | durch phi_0 (bzw. delta_0);
--           darunter die Scheiben phi_i (bzw. delta_i) | phi_i | Faktor * phi_0
--   pvv_pol Tabelle der Nebenpole: Verschiebung (bzw. Drehung) | ueber Scheibe A | ueber Scheibe B
--   w_eq2   alles durch die Bezugsscheibe ausgedrueckt (phi_0 bzw. delta_0)
--   pvvinfo Legende aller Namen
-- Die freigesetzte Groesse wirkt in der Richtung, die der PvV-Modus zeichnet (H, V: in
-- Lagerrichtung; M_A gegen den Uhrzeigersinn; Gelenkgroessen M, N, Q als positive Schnittgroessen).
-- nurTerme = true: nur zurueckgeben (ohne CAS-Speichern, fuer Tests):
--   eq1_lhs, eq2_lhs, kin (Zeilen {Name, Ausdruck1, Ausdruck0}), pol (Zeilen {Name, A, B}), info
exportArbeitssatzToTI = function(nurTerme)
    if not in_pvv_release or not kinematic_disk_states then
        zeigeMeldung("Arbeitssatz: bitte zuerst in den PvV-Modus wechseln.", "Export fehlgeschlagen")
        return
    end
    local zustaende = kinematic_disk_states
    local function bewegt(z)
        if not z then return false end
        if z.type == "rot" then return math.abs(z.phi or 0) > 1e-9 end
        return math.abs(z.vx or 0) > 1e-9 or math.abs(z.vy or 0) > 1e-9
    end

    -- Bezugsscheibe: Startscheibe der Kinematik, sonst die erste bewegte (drehende vor verschobener)
    local ref_disk = kinematic_seed_info and kinematic_seed_info.disk or nil
    if ref_disk and not bewegt(zustaende[ref_disk]) then ref_disk = nil end
    if not ref_disk then
        for s_idx, z in pairs(zustaende) do
            if z.type == "rot" and bewegt(z) then ref_disk = s_idx; break end
        end
    end
    if not ref_disk then
        for s_idx, z in pairs(zustaende) do
            if bewegt(z) then ref_disk = s_idx; break end
        end
    end
    local ref = ref_disk and zustaende[ref_disk]
    -- Bezugsgroesse: Drehwinkel der Bezugsscheibe (intern ist phi im Uhrzeigersinn positiv)
    -- oder ihre Verschiebung (Betrag des Bewegungsvektors)
    local ref_rot = ref ~= nil and ref.type == "rot"
    local ref_betrag = 0
    if ref then ref_betrag = ref_rot and -ref.phi or math.sqrt(ref.vx^2 + ref.vy^2) end
    local ref_var = ref_rot and "φ_0" or "δ_0"
    -- fuer Zeichnung und Menues (nurTerme == "anzeige"): wem ein Beitrag gehoert (Knoten bzw. Stab)
    -- und die Momente, die auf phi_i arbeiten
    local besitzer, momentListe = {}, {}

    local eq2_terms = {}
    local fN = fN_export
    local function istNull(v)
        return v == nil or v == "0" or (type(v) == "number" and math.abs(v) < 1e-12)
    end
    local function kraftText(v)
        if type(v) == "string" then return "(" .. v .. ")" end
        return "(" .. fN(v) .. ")"
    end

    -- Wege fuer w_eq1: wege[name] sammelt die Beitraege der Scheiben (kin1: durch phi_i bzw.
    -- delta_i, kin0: durch phi_0 bzw. delta_0). Momente arbeiten auf phi_i selbst (momente[i]).
    local wege, wegReihe, momente = {}, {}, {}
    local function wegEintrag(name, kraft, info)
        local w = wege[name]
        if not w then
            -- num: Weg je Bezugsgroesse als Zahl (Spalte 3 von pvv_kin); px, py, ex, ey: Ort und Richtung
            w = { name = name, kraft = kraft, info = info, kin1 = {}, kin0 = {}, num = 0,
                  knoten = besitzer.knoten, stab = besitzer.stab }
            wege[name] = w; wegReihe[#wegReihe + 1] = w
        end
        return w
    end
    local function scheibenVar(i)
        local z = zustaende[i]
        return ((z and z.type == "trans") and "δ_" or "φ_") .. i
    end

    -- Beitrag an Scheibe `scheibe`:
    --   Drehung:      Weg = hebel * phi_i   (hebel: Text mit Laengendimension, 1 fuer Momente)
    --   Verschiebung: Weg = Richtungskosinus * delta_i (trans_disp: Verschiebung in Kraftrichtung)
    -- weg: Eintrag aus wegEintrag; ohne weg ist es ein Moment (Wert hebel * Kraft) auf phi_i.
    -- vz = -1: Gegenseite eines Gelenks (Kraft dort entgegengesetzt).
    -- h_num: Hebel als Zahl fuer die Zeichnung (fehlt er, gilt hebel, falls das eine Zahl ist).
    local function addTerm(scheibe, hebel, force_str, is_rot, trans_disp, weg, vz, h_num)
        local z = zustaende[scheibe]
        if not bewegt(z) or not ref then return end
        vz = vz or 1
        if is_rot then
            if z.type ~= "rot" then return end
            if type(hebel) == "number" and math.abs(hebel) < 1e-9 then return end
            local h_str = type(hebel) == "string" and hebel or ("(" .. fN(hebel) .. ")")
            if vz < 0 then h_str = "(-" .. h_str .. ")" end
            -- Drehwinkel je Bezugsgroesse (bei verschobener Bezugsscheibe: pro Laenge)
            local k = -z.phi / ref_betrag
            local faktor = pvvLaenge(k, ref_rot and 0 or -1)
            if math.abs(k) > 1e-12 then
                table.insert(eq2_terms, string.format("%s * %s * %s", faktor, h_str, force_str))
            end
            if weg then
                table.insert(weg.kin1, string.format("%s * %s", h_str, scheibenVar(scheibe)))
                table.insert(weg.kin0, string.format("%s * %s", faktor, h_str))
                weg.num = weg.num + vz * (h_num or (type(hebel) == "number" and hebel) or 0) * k
            else
                local m = momente[scheibe] or {}
                momente[scheibe] = m
                table.insert(m, string.format("%s * %s", h_str, force_str))
                momentListe[#momentListe + 1] = { text = string.format("%s * %s * %s", h_str, force_str, scheibenVar(scheibe)),
                    scheibe = scheibe, knoten = besitzer.knoten, stab = besitzer.stab }
            end
        else
            if z.type ~= "trans" or math.abs(trans_disp or 0) < 1e-9 then return end
            local betrag = math.sqrt(z.vx^2 + z.vy^2)
            local td = trans_disp * vz
            -- Verschiebung je Bezugsgroesse (bei drehender Bezugsscheibe: Laenge; phi_0 = -phi_ref intern)
            local anteil0 = pvvLaenge(td / ref_betrag, ref_rot and 1 or 0)
            table.insert(eq2_terms, string.format("%s * %s", anteil0, force_str))
            if weg then
                table.insert(weg.kin1, string.format("(%s) * %s", fN(td / betrag), scheibenVar(scheibe)))
                table.insert(weg.kin0, anteil0)
                weg.num = weg.num + td / ref_betrag
            end
        end
    end

    -- Kraft `kraft` in Richtung e = (ex, ey) (global, y nach unten) im Punkt (px, py)
    local function processForce(scheibe, px, py, kraft, ex, ey, weg, vz)
        local z = zustaende[scheibe]
        if not z or istNull(kraft) then return end
        if weg and not weg.px then weg.px, weg.py, weg.ex, weg.ey = px, py, ex, ey end
        if z.type == "rot" then
            -- Weg in Richtung e je Drehwinkel: (py - cy) * ex - (px - cx) * ey, mit exakten Faktoren
            local teile = {}
            if math.abs(ex) > 1e-12 and math.abs(py - z.cy) > 1e-9 then
                teile[#teile + 1] = math.abs(ex - 1) < 1e-12 and pvvLaenge(py - z.cy) or (pvvLaenge(py - z.cy) .. "*(" .. fN(ex) .. ")")
            end
            if math.abs(ey) > 1e-12 and math.abs(px - z.cx) > 1e-9 then
                teile[#teile + 1] = math.abs(ey - 1) < 1e-12 and pvvLaenge(-(px - z.cx)) or (pvvLaenge(-(px - z.cx)) .. "*(" .. fN(ey) .. ")")
            end
            if #teile > 0 then
                local h = #teile == 1 and teile[1] or ("(" .. table.concat(teile, " + ") .. ")")
                addTerm(scheibe, h, kraftText(kraft), true, nil, weg, vz, (py - z.cy) * ex - (px - z.cx) * ey)
            end
        else
            addTerm(scheibe, 0, kraftText(kraft), false, z.vx * ex + z.vy * ey, weg, vz)
        end
    end
    local function processMoment(scheibe, kraft, vz)
        if istNull(kraft) then return end
        addTerm(scheibe, 1, kraftText(kraft), true, nil, nil, vz)
    end

    -- Scheibe, deren Bewegung ein Knoten mitmacht: ein Stab ohne Gelenk an diesem Knoten (auch eine
    -- feste Scheibe, dann leistet die Last keine Arbeit); sonst der erste Stab (reines Momentengelenk:
    -- gleiche Verschiebung fuer alle Staebe)
    local function knotenScheibe(i)
        local erste = nil
        for _, s in ipairs(staebe) do
            if s.k1 == i or s.k2 == i then
                local am_anfang = (s.k1 == i)
                local gelenk = am_anfang and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A) or (not am_anfang and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B))
                if not gelenk then return s.scheibe end
                erste = erste or s.scheibe
            end
        end
        return erste
    end

    -- Knotenlasten: im symbolischen Modus mit ihren Namen; jede eingegebene Komponente mit eigenem
    -- Weg in ihrer Richtung (last_w dreht das Lastsystem wie in der Berechnung)
    for i, k in ipairs(knoten) do
        besitzer = { knoten = i }
        local lx, ly, lm = k.last_x or 0, k.last_y or 0, k.last_m or 0
        if math.abs(lx) > 1e-12 or math.abs(ly) > 1e-12 or math.abs(lm) > 1e-12 then
            local function lastWert(zahl, text)
                if math.abs(zahl) < 1e-12 then return 0 end
                if symbolischer_modus and type(text) == "string" and text ~= "" then return text end
                return zahl
            end
            local sx, sy, sm = lastWert(lx, k.last_x_str), lastWert(ly, k.last_y_str), lastWert(lm, k.last_m_str)
            local rl = math.rad(-(k.last_w or 0))
            local cl, sl = math.cos(rl), math.sin(rl)
            local gedreht = math.abs(k.last_w or 0) > 1e-9 and string.format(", Lastsystem um %g Grad gedreht", k.last_w) or ""
            local scheibe = knotenScheibe(i)
            if scheibe then
                if not istNull(sx) then
                    processForce(scheibe, k.x, k.y, sx, cl, sl,
                        wegEintrag("δ_k" .. i .. "x", sx, "Knoten " .. i .. ", Verschiebung in Richtung der x-Last (nach rechts" .. gedreht .. ")"))
                end
                if not istNull(sy) then
                    processForce(scheibe, k.x, k.y, sy, -sl, cl,
                        wegEintrag("δ_k" .. i .. "y", sy, "Knoten " .. i .. ", Verschiebung in Richtung der y-Last (nach unten" .. gedreht .. ")"))
                end
                processMoment(scheibe, sm)
            end
        end
    end

    for i, s in ipairs(staebe) do
        besitzer = { stab = i }
        local d_state = zustaende[s.scheibe]
        if d_state then
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            local dx, dy = k2.x - k1.x, k2.y - k1.y
            local L = math.sqrt(dx^2 + dy^2)
            if L > 1e-6 and istBogen(s) then
                -- Bogen: Lasten wie in der FEM auf dem Bogen (bogenLastResultierende); auf der starren
                -- Scheibe leistet ihre Resultierende dieselbe Arbeit, angesetzt auf der Wirkungslinie
                local r = bogenHatLast(s) and bogenLastResultierende(s)
                if r then
                    local Fx, Fy, M = r.summe[1], r.summe[2], r.summe[3]
                    if math.abs(Fx) > 1e-12 or math.abs(Fy) > 1e-12 then
                        local wx, wy = bogenWirkungspunkt(s, Fx, Fy, M)
                        if math.abs(Fx) > 1e-12 then
                            processForce(s.scheibe, wx, wy, Fx, 1, 0, wegEintrag("δ_s" .. i .. "x", Fx, "Stab " .. i .. " (Bogen), Verschiebung der Resultierenden aller Bogenlasten in x (nach rechts)"))
                        end
                        if math.abs(Fy) > 1e-12 then
                            processForce(s.scheibe, wx, wy, Fy, 0, 1, wegEintrag("δ_s" .. i .. "y", Fy, "Stab " .. i .. " (Bogen), Verschiebung der Resultierenden aller Bogenlasten in y (nach unten)"))
                        end
                    else
                        processMoment(s.scheibe, M)
                    end
                end
            elseif L > 1e-6 then
                local cosA, sinA = dx/L, dy/L

                -- Querlast (Richtung z = (-sinA, cosA)), Resultierende im Abstand xS von k1
                local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                local Rq_num = (qA + qB)/2 * L + (s.R_q_cas or 0)
                local Sq_num = (L^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
                local Rq_str, Sq_str, xSq_str = processDistLoad_PvV(L, L, s.q_str, s.q_A_str, s.q_B_str, s.R_q_cas_str, s.S_q_cas_str, Rq_num, Sq_num, "q")
                if Rq_str then
                    local weg = wegEintrag("δ_s" .. i .. "q", "(" .. Rq_str .. ")", "Stab " .. i .. ", Verschiebung der Resultierenden der Querlast quer zum Stab (Richtung der Last, zur gestrichelten Faser)")
                    if d_state.type == "rot" then
                        local term1 = pvvLaenge(-sinA * (k1.y - d_state.cy) - cosA * (k1.x - d_state.cx))
                        local d_str = xSq_str and string.format("(%s - (%s))", term1, xSq_str) or term1
                        local xs = (xSq_str and math.abs(Rq_num) > 1e-12) and Sq_num / Rq_num or 0
                        addTerm(s.scheibe, d_str, "(" .. Rq_str .. ")", true, nil, weg, nil,
                            -sinA * (k1.y - d_state.cy) - cosA * (k1.x - d_state.cx) - xs)
                    else
                        addTerm(s.scheibe, 0, "(" .. Rq_str .. ")", false, -sinA * d_state.vx + cosA * d_state.vy, weg)
                    end
                elseif Sq_str then
                    -- Resultierende 0, aber ein Moment (z. B. antimetrische Trapezlast)
                    if d_state.type == "rot" then addTerm(s.scheibe, -1, "(" .. Sq_str .. ")", true) end
                end

                -- Laengslast: Wirkungslinie ist die Stabachse, der Hebel haengt nicht von der Lage ab
                local nA = s.n + (s.n_A or 0); local nB = s.n + (s.n_B or 0)
                local Rn_num = (nA + nB)/2 * L + (s.R_n_cas or 0)
                local Sn_num = (s.S_n_cas or 0)
                local Rn_str = processDistLoad_PvV(L, L, s.n_str, s.n_A_str, s.n_B_str, s.R_n_cas_str, s.S_n_cas_str, Rn_num, Sn_num, "q")
                if Rn_str then
                    local weg = wegEintrag("δ_s" .. i .. "n", "(" .. Rn_str .. ")", "Stab " .. i .. ", Verschiebung der Resultierenden der Laengslast in Stabrichtung")
                    if d_state.type == "rot" then
                        local hn = cosA * (k1.y - d_state.cy) - sinA * (k1.x - d_state.cx)
                        addTerm(s.scheibe, pvvLaenge(hn), "(" .. Rn_str .. ")", true, nil, weg, nil, hn)
                    else
                        addTerm(s.scheibe, 0, "(" .. Rn_str .. ")", false, cosA * d_state.vx + sinA * d_state.vy, weg)
                    end
                end

                local gx_val = s.gx or 0
                local L_eff_gx = s.gx_proj and math.abs(dy) or L
                local Rgx_num = gx_val * L_eff_gx + (s.R_gx_cas or 0)
                local Sgx_num = gx_val * L_eff_gx * (L/2) + (s.S_gx_cas or 0)
                local Rgx_str, Sgx_str, xSgx_str = processDistLoad_PvV(L, L_eff_gx, s.gx_str, nil, nil, s.R_gx_cas_str, s.S_gx_cas_str, Rgx_num, Sgx_num, "g")
                if Rgx_str then
                    local weg = wegEintrag("δ_s" .. i .. "x", "(" .. Rgx_str .. ")", "Stab " .. i .. ", Verschiebung der Resultierenden der globalen Linienlast in x (nach rechts)")
                    if d_state.type == "rot" then
                        local term1 = pvvLaenge(k1.y - d_state.cy)
                        local d_str = xSgx_str and string.format("(%s + (%s) * (%s))", term1, xSgx_str, fN(sinA)) or term1
                        local xs = (xSgx_str and math.abs(Rgx_num) > 1e-12) and Sgx_num / Rgx_num or 0
                        addTerm(s.scheibe, d_str, "(" .. Rgx_str .. ")", true, nil, weg, nil, (k1.y - d_state.cy) + xs * sinA)
                    else
                        addTerm(s.scheibe, 0, "(" .. Rgx_str .. ")", false, d_state.vx, weg)
                    end
                elseif Sgx_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, sinA, "(" .. Sgx_str .. ")", true) end
                end

                local gy_val = s.gy or 0
                local L_eff_gy = s.gy_proj and math.abs(dx) or L
                local Rgy_num = gy_val * L_eff_gy + (s.R_gy_cas or 0)
                local Sgy_num = gy_val * L_eff_gy * (L/2) + (s.S_gy_cas or 0)
                local Rgy_str, Sgy_str, xSgy_str = processDistLoad_PvV(L, L_eff_gy, s.gy_str, nil, nil, s.R_gy_cas_str, s.S_gy_cas_str, Rgy_num, Sgy_num, "g")
                if Rgy_str then
                    local weg = wegEintrag("δ_s" .. i .. "y", "(" .. Rgy_str .. ")", "Stab " .. i .. ", Verschiebung der Resultierenden der globalen Linienlast in y (nach unten)")
                    if d_state.type == "rot" then
                        local term1 = pvvLaenge(-(k1.x - d_state.cx))
                        local d_str = xSgy_str and string.format("(%s - (%s) * (%s))", term1, xSgy_str, fN(cosA)) or term1
                        local xs = (xSgy_str and math.abs(Rgy_num) > 1e-12) and Sgy_num / Rgy_num or 0
                        addTerm(s.scheibe, d_str, "(" .. Rgy_str .. ")", true, nil, weg, nil, -(k1.x - d_state.cx) - xs * cosA)
                    else
                        addTerm(s.scheibe, 0, "(" .. Rgy_str .. ")", false, d_state.vy, weg)
                    end
                elseif Sgy_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, -cosA, "(" .. Sgy_str .. ")", true) end
                end

                local Rm_num = (s.m or 0) * L + (s.R_m_cas or 0)
                local Rm_str = processDistLoad_PvV(L, L, s.m_str, nil, nil, s.R_m_cas_str, nil, Rm_num, 0, "m")
                if Rm_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, 1, "(" .. Rm_str .. ")", true) end
                end
            end
        end
    end

    -- freigesetzte Bindung als aeussere Last (Richtung wie in der PvV-Zeichnung)
    local function andereScheibe(nodeIdx, stabIdx)
        for j, s2 in ipairs(staebe) do
            if j ~= stabIdx and (s2.k1 == nodeIdx or s2.k2 == nodeIdx) then return s2.scheibe end
        end
        return nil
    end
    if pvv_released_binding then
        local b = pvv_released_binding
        if b.type == "lager_x" or b.type == "lager_y" or b.type == "lager_m" then
            besitzer = { knoten = b.node }
            local k = knoten[b.node]
            local scheibe = knotenScheibe(b.node)
            if scheibe then
                local wr = math.rad(k.winkel or 0)
                local cw, sw = math.cos(wr), math.sin(wr)
                -- Lagerrichtungen wie in der Berechnung: xi = (cos, -sin), eta = (sin, cos)
                if b.type == "lager_x" then
                    processForce(scheibe, k.x, k.y, "H", cw, -sw, wegEintrag("δ_H", "H", "Lager Knoten " .. b.node .. ", Verschiebung in Richtung von H"))
                elseif b.type == "lager_y" then
                    processForce(scheibe, k.x, k.y, "V", sw, cw, wegEintrag("δ_V", "V", "Lager Knoten " .. b.node .. ", Verschiebung in Richtung von V"))
                else processMoment(scheibe, "M_A") end
            end
        elseif b.type == "q_gelenk" or b.type == "n_gelenk" then
            -- positive Schnittkraft: am Stabanfang entgegen, am Stabende in Richtung der Stabachse
            -- (N) bzw. der Stabnormalen z = (-sinA, cosA) (Q); auf der Gegenseite umgekehrt
            local s = staebe[b.stab]
            local nodeIdx = b.endA and s.k1 or s.k2
            besitzer = { stab = b.stab, knoten = nodeIdx }
            local k_node = knoten[nodeIdx]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
            local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local nx, ny = dx/L, dy/L
                if b.type == "q_gelenk" then nx, ny = -ny, nx end
                local dir = b.endA and -1 or 1
                local ax, ay = nx * dir, ny * dir
                local force_var = (b.type == "q_gelenk") and "Q" or "N"
                local weg = wegEintrag("δ_G", force_var, "Gelenk Stab " .. b.stab .. (b.endA and " (Anfang)" or " (Ende)")
                    .. ", gegenseitige Verschiebung in Richtung von " .. force_var)
                processForce(s.scheibe, k_node.x, k_node.y, force_var, ax, ay, weg)
                local other_scheibe = andereScheibe(nodeIdx, b.stab)
                if other_scheibe then processForce(other_scheibe, k_node.x, k_node.y, force_var, ax, ay, weg, -1) end
            end
        elseif b.type == "m_gelenk" or b.type == "knoten_gelenk" then
            -- positives Schnittmoment des (ersten) Stabes am Gelenk: am Stabanfang im Uhrzeigersinn, am
            -- Stabende gegen den Uhrzeigersinn; Gegenmoment an der anderen Scheibe. Weg: gegenseitige
            -- Verdrehung phi_G.
            local s_idx, o_scheibe, nodeIdx
            if b.type == "m_gelenk" then
                s_idx = b.stab
                nodeIdx = b.endA and staebe[b.stab].k1 or staebe[b.stab].k2
                o_scheibe = andereScheibe(nodeIdx, b.stab)
            else
                nodeIdx = b.node
                local s2_idx = nil
                for j, s in ipairs(staebe) do
                    if s.k1 == b.node or s.k2 == b.node then
                        if not s_idx then s_idx = j elseif not s2_idx then s2_idx = j end
                    end
                end
                o_scheibe = s2_idx and staebe[s2_idx].scheibe
            end
            if s_idx then
                besitzer = { knoten = nodeIdx, stab = (b.type == "m_gelenk") and s_idx or nil }
                local dir = (staebe[s_idx].k1 == nodeIdx) and -1 or 1
                local weg = wegEintrag("φ_G", "M", "Gelenk Knoten " .. nodeIdx .. ", gegenseitige Verdrehung (Arbeit des Gelenkmoments M)")
                addTerm(staebe[s_idx].scheibe, dir, "(M)", true, nil, weg)
                if o_scheibe then addTerm(o_scheibe, -dir, "(M)", true, nil, weg) end
            end
        end
    end

    -- w_eq1: Kraft mal Weg, Momente mal Drehwinkel ihrer Scheibe
    local scheibenNr = {}
    for i in pairs(zustaende) do scheibenNr[#scheibenNr + 1] = i end
    table.sort(scheibenNr)
    local eq1_parts, kin, info = {}, {}, {}
    for _, w in ipairs(wegReihe) do
        if #w.kin1 > 0 then
            eq1_parts[#eq1_parts + 1] = kraftText(w.kraft) .. " * " .. w.name
            kin[#kin + 1] = { w.name, table.concat(w.kin1, " + "), "(" .. table.concat(w.kin0, " + ") .. ") * " .. ref_var }
            info[#info + 1] = w.name .. ": " .. w.info
        end
    end
    for _, i in ipairs(scheibenNr) do
        if momente[i] and #momente[i] > 0 then
            eq1_parts[#eq1_parts + 1] = "(" .. table.concat(momente[i], " + ") .. ") * " .. scheibenVar(i)
        end
    end
    -- Scheiben: Drehwinkel (bzw. Verschiebung) je Bezugsgroesse
    for _, i in ipairs(scheibenNr) do
        local z = zustaende[i]
        if bewegt(z) and ref then
            local v = scheibenVar(i)
            local faktor = z.type == "rot" and pvvLaenge(-z.phi / ref_betrag, ref_rot and 0 or -1)
                or pvvLaenge(math.sqrt(z.vx^2 + z.vy^2) / ref_betrag, ref_rot and 1 or 0)
            kin[#kin + 1] = { v, v, faktor .. " * " .. ref_var }
            info[#info + 1] = v .. ": " .. (z.type == "rot" and "Drehwinkel von Scheibe " .. i .. " (gegen den Uhrzeigersinn)"
                or "Verschiebung von Scheibe " .. i .. " in ihrer Bewegungsrichtung") .. ((i == ref_disk) and ", Bezugsscheibe" or "")
        end
    end
    local eq1_lhs = #eq1_parts > 0 and table.concat(eq1_parts, " + ") or "0"
    local eq2_lhs = #eq2_terms > 0 and (ref_var .. " * (" .. table.concat(eq2_terms, " + ") .. ")") or "0"

    -- Nebenpole zwischen zwei bewegten Scheiben: dieselbe Bewegung, einmal ueber jede Scheibe
    -- ausgedrueckt. Daraus folgen die Verhaeltnisse der Drehwinkel in pvv_kin.
    local pol = {}
    local function wegUeber(i, px, py, ex, ey)
        local z = zustaende[i]
        if z.type == "rot" then
            local h = (py - z.cy) * ex - (px - z.cx) * ey
            if math.abs(h) < 1e-9 then return nil end
            return pvvLaenge(h) .. " * " .. scheibenVar(i)
        end
        local c = (z.vx * ex + z.vy * ey) / math.sqrt(z.vx^2 + z.vy^2)
        if math.abs(c) < 1e-9 then return nil end
        return "(" .. fN(c) .. ") * " .. scheibenVar(i)
    end
    for _, A in ipairs(scheibenNr) do
        for _, B in ipairs(scheibenNr) do
            local zA, zB = zustaende[A], zustaende[B]
            local liste = A < B and pvvPolplan and pvvPolplan.poles[A] and pvvPolplan.poles[A][B]
            if liste and liste[1] and bewegt(zA) and bewegt(zB) then
                local p = liste[1]
                local id = (A < 10 and B < 10) and (A .. B) or (A .. "_" .. B)
                if p.type == "finite" then
                    -- Komponente, in die sich der Nebenpol hauptsaechlich bewegt (y nach unten)
                    local vx, vy
                    if zA.type == "rot" then vx, vy = -zA.phi * (p.y - zA.cy), zA.phi * (p.x - zA.cx) else vx, vy = zA.vx, zA.vy end
                    local inX = math.abs(vx) >= math.abs(vy)
                    local ex, ey = inX and 1 or 0, inX and 0 or 1
                    local a, bb = wegUeber(A, p.x, p.y, ex, ey), wegUeber(B, p.x, p.y, ex, ey)
                    if a and bb then
                        local name = (inX and "δx_P" or "δy_P") .. id
                        pol[#pol + 1] = { name, a, bb }
                        info[#info + 1] = name .. ": Nebenpol (" .. A .. "," .. B .. "), Verschiebung in " .. (inX and "x (nach rechts)" or "y (nach unten)")
                            .. ", Spalte 2 ueber Scheibe " .. A .. ", Spalte 3 ueber Scheibe " .. B
                    end
                elseif zA.type == "rot" and zB.type == "rot" then
                    local name = "φ_P" .. id
                    pol[#pol + 1] = { name, scheibenVar(A), scheibenVar(B) }
                    info[#info + 1] = name .. ": Nebenpol (" .. A .. "," .. B .. ") im Unendlichen, beide Scheiben drehen gleich"
                elseif zA.type == "trans" and zB.type == "trans" then
                    local a, bb = wegUeber(A, 0, 0, p.dx, p.dy), wegUeber(B, 0, 0, p.dx, p.dy)
                    if a and bb then
                        local name = "δ_P" .. id
                        pol[#pol + 1] = { name, a, bb }
                        info[#info + 1] = name .. ": Nebenpol (" .. A .. "," .. B .. ") im Unendlichen, gleiche Verschiebung in Polrichtung"
                    end
                end
            end
        end
    end
    table.insert(info, 1, "w_eq1: Kraft mal Weg (Weg positiv in Kraftrichtung), Momente mal Drehwinkel der Scheibe")
    table.insert(info, 2, "pvv_kin: Weg | ueber die eigene Scheibe | ueber " .. ref_var .. "; darunter die Scheiben")
    if #pol > 0 then table.insert(info, 3, "pvv_pol: Nebenpol | ueber die erste Scheibe | ueber die zweite (beide gleich)") end

    if nurTerme == "anzeige" then
        -- Zeichnung und Menues: genau die Wege und Scheiben von pvv_kin, mit Zahlenwert und Text
        local d = { ref_var = ref_var, ref_disk = ref_disk, wege = {}, reihe = {}, scheiben = {}, momente = momentListe }
        for _, w in ipairs(wegReihe) do
            if #w.kin1 > 0 then
                w.dim = (w.name == "φ_G") and (ref_rot and 0 or -1) or (ref_rot and 1 or 0)
                w.text = pvvAnzeigeWert(w.num, w.dim, ref_var)
                w.kraftText = kraftText(w.kraft)
                d.wege[w.name] = w; d.reihe[#d.reihe + 1] = w
            end
        end
        for _, i in ipairs(scheibenNr) do
            local z = zustaende[i]
            if bewegt(z) and ref then
                local num = z.type == "rot" and -z.phi / ref_betrag or math.sqrt(z.vx^2 + z.vy^2) / ref_betrag
                local dim = z.type == "rot" and (ref_rot and 0 or -1) or (ref_rot and 1 or 0)
                d.scheiben[i] = { var = scheibenVar(i), num = num, dim = dim, text = pvvAnzeigeWert(num, dim, ref_var) }
            end
        end
        return d
    end
    print("eq1_lhs: " .. eq1_lhs)
    print("eq2_lhs: " .. eq2_lhs)
    if nurTerme then return eq1_lhs, eq2_lhs, kin, pol, info end

    if math.eval then
        local cas_wrap = zahlenFormat == 3 and "approx" or "exact"
        local function matrixText(zeilen)
            local r = {}
            for _, z in ipairs(zeilen) do r[#r + 1] = table.concat(z, ",") end
            return "[" .. table.concat(r, ";") .. "]"
        end
        local success1 = pcall(function() math.eval("w_eq1 := " .. cas_wrap .. "(expand(" .. eq1_lhs .. ")) = 0") end)
        local success2 = pcall(function() math.eval("w_eq2 := " .. cas_wrap .. "(expand(" .. eq2_lhs .. ")) = 0") end)
        pcall(math.eval, "DelVar pvv_kin, pvv_pol, pvvinfo")
        if #kin > 0 then pcall(math.eval, "pvv_kin := " .. cas_wrap .. "(" .. matrixText(kin) .. ")") end
        if #pol > 0 then pcall(math.eval, "pvv_pol := " .. cas_wrap .. "(" .. matrixText(pol) .. ")") end
        local quoted = {}
        for j, t in ipairs(info) do quoted[j] = '"' .. t:gsub('"', "'") .. '"' end
        pcall(math.eval, "pvvinfo := [" .. table.concat(quoted, ";") .. "]")
        if success1 and success2 then
            zeigeMeldung("Arbeitssatz exportiert: w_eq1, w_eq2, pvv_kin" .. (#pol > 0 and ", pvv_pol" or "") .. ", pvvinfo.", "Export")
            print("-> Arbeitssatz als exakte CAS-Gleichung (w_eq1, w_eq2) exportiert!")
        else
            zeigeMeldung("Fehler beim Export des Arbeitssatzes.", "Export fehlgeschlagen")
            print("-> Fehler beim Export des Arbeitssatzes.")
        end
    else
        zeigeMeldung("Dieser Export erfordert das CAS.", "Export fehlgeschlagen")
    end
end

local function matMult(A, B)
    local C = {}; for i = 1, #A do C[i] = {}; for j = 1, #B[1] do local sum = 0; for k = 1, #A[1] do sum = sum + A[i][k] * B[k][j] end; C[i][j] = sum end end; return C
end

local function matTrans(A)
    local AT = {}; for i = 1, #A[1] do AT[i] = {}; for j = 1, #A do AT[i][j] = A[j][i] end end; return AT
end

local function buildKnotenTransform(stab)
    local k1, k2 = knoten[stab.k1], knoten[stab.k2]
    local c1, s1 = math.cos(math.rad(k1.winkel or 0)), math.sin(math.rad(k1.winkel or 0))
    local c2, s2 = math.cos(math.rad(k2.winkel or 0)), math.sin(math.rad(k2.winkel or 0))
    return { {c1,-s1,0,0,0,0}, {s1,c1,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c2,-s2,0}, {0,0,0,s2,c2,0}, {0,0,0,0,0,1} }
end

local function getTopologicalN()
    local a, rel = 0, 0
    for i, k in ipairs(knoten) do
        if k.lager_x then a=a+1 end; if k.lager_y then a=a+1 end; if k.lager_m then a=a+1 end
        if not k.lager_x and (k.cx or 0) > 0 then a=a+1 end
        if not k.lager_y and (k.cy or 0) > 0 then a=a+1 end
        if not k.lager_m and (k.cm or 0) > 0 then a=a+1 end
        if k.gelenk then local m=0; for _,s in ipairs(staebe) do if s.k1==i or s.k2==i then m=m+1 end end; if m>1 then a=a-(m-1) end end
    end
    for _, s in ipairs(staebe) do
        if s.gelenk_A then rel=rel+1 end; if s.gelenk_B then rel=rel+1 end
        if s.n_gelenk_A then rel=rel+1 end; if s.n_gelenk_B then rel=rel+1 end
        if s.q_gelenk_A then rel=rel+1 end; if s.q_gelenk_B then rel=rel+1 end
    end
    return a + 3 * #staebe - 3 * #knoten - rel
end

local function updateAlleLasten()
    local function fN(n) 
        local s = string.format("%.12g", n):gsub(",", ".")
        if s:find("e") then s = s:gsub("e(.-)$", "*10^(%1)") end
        return "("..s..")" 
    end
    for i, s in ipairs(staebe) do
        local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
        local L = math.sqrt(dx^2 + dy^2)
        s.q_pts = {}; s.Q_cas_pts = {}; s.M_cas_pts = {}; s.v_cas_pts_EI = {}
        s.q_in_cas = false; s.n_in_cas = false
        s.n_pts = {}; s.N_cas_pts = {}; s.u_cas_pts_EA = {}
        s.m_pts = {};
        s.gx_pts = {}; s.gy_pts = {}
        
        local L_str = "(" .. fN(L) .. ")"
        local eq_q = getEqQ(s, L, fN, L_str)
        local eq_n = getEqN(s, L, fN, L_str)
        local eq_q_num = casWithDummySymbols(eq_q)
        local eq_n_num = casWithDummySymbols(eq_n)
        local has_q = string.hasx(eq_q)
        local has_n = string.hasx(eq_n)
        local has_m = s.m_str and string.hasx(s.m_str)
        local has_gx = string.hasx(s.gx_str or "")
        local has_gy = string.hasx(s.gy_str or "")
        
        -- HIER IST DER FIX: Lokale Lasten optisch von globalen entkoppeln
        local pure_q_cas = s.q_str and string.hasx(s.q_str)
        local pure_n_cas = s.n_str and string.hasx(s.n_str)
        local pure_m_cas = s.m_str and string.hasx(s.m_str)

        -- Bogen: x ist der Winkel ab Stabanfang; Stuetzwerte fuer die Lastzeichnung und Resultierende je
        -- Lastart fuer E-Seite und Teilsystem-Hover (die Rechnung verteilt die Lasten in injectVirtualArcs)
        local bogen = bogenGeometrie(s)
        s.bogen_res = bogen and bogenHatLast(s) and bogenLastResultierende(s) or nil
        if bogen then
            bogenLastPunkte(s, bogen)
        elseif L > 0 and math.eval and (has_q or has_n or has_m or has_gx or has_gy or pure_q_cas or pure_n_cas or pure_m_cas) then
            local vars_to_del = {}
            
            if has_q then
                s.q_in_cas = true -- Q/M/v-Stuetzwerte enthalten die gesamte Querlast inkl. q_A/q_B
                local q_t = eq_q_num:subx("t")
                math.eval("q_temp(x) := " .. eq_q_num)
                math.eval("q_cas_Q(x) := integral("..eq_q_num..",x,0,x)")
                math.eval("q_cas_M(x) := integral(("..q_t..")*(x-t),t,0,x)")
                math.eval("q_cas_vK_EI(x) := integral(("..q_t..")*(x-t)^3,t,0,x)/6")
                s.vK_L_EI = casToNumber(math.eval("approx(q_cas_vK_EI("..fN(L).."))")) or 0
                s.phiK_L_EI = casToNumber(math.eval("approx(integral(("..q_t..")*("..fN(L).."-t)^2,t,0,"..fN(L)..")/2)")) or 0
                table.insert(vars_to_del, "q_temp"); table.insert(vars_to_del, "q_cas_Q"); table.insert(vars_to_del, "q_cas_M"); table.insert(vars_to_del, "q_cas_vK_EI")
            end
            
            if has_n then
                s.n_in_cas = true -- N/u-Stuetzwerte enthalten die gesamte Laengslast inkl. n_A/n_B
                local n_t = eq_n_num:subx("t")
                math.eval("n_temp(x) := " .. eq_n_num)
                math.eval("n_cas_N(x) := integral("..eq_n_num..",x,0,x)")
                math.eval("n_cas_uK_EA(x) := integral(("..n_t..")*(x-t),t,0,x)")
                s.uK_L_EA = casToNumber(math.eval("approx(n_cas_uK_EA("..fN(L).."))")) or 0
                table.insert(vars_to_del, "n_temp"); table.insert(vars_to_del, "n_cas_N"); table.insert(vars_to_del, "n_cas_uK_EA")
            end
            
            if has_m then
                local m_e = s.m_str
                local m_t = m_e:subx("t")
                math.eval("m_temp(x) := " .. m_e)
                math.eval("m_cas_M(x) := integral("..m_e..",x,0,x)")
                math.eval("m_cas_vK_EI(x) := integral(("..m_t..")*(x-t)^2,t,0,x)/2")
                s.vK_L_EI_m = casToNumber(math.eval("approx(m_cas_vK_EI("..fN(L).."))")) or 0
                s.phiK_L_EI_m = casToNumber(math.eval("approx(integral(("..m_t..")*("..fN(L).."-t),t,0,"..fN(L).."))")) or 0
                table.insert(vars_to_del, "m_temp"); table.insert(vars_to_del, "m_cas_M"); table.insert(vars_to_del, "m_cas_vK_EI")
            end
            
            if pure_q_cas then math.eval("q_pure(x) := " .. s.q_str); table.insert(vars_to_del, "q_pure") end
            if pure_n_cas then math.eval("n_pure(x) := " .. s.n_str); table.insert(vars_to_del, "n_pure") end
            if pure_m_cas then math.eval("m_pure(x) := " .. s.m_str); table.insert(vars_to_del, "m_pure") end
            if has_gx then math.eval("gx_temp(x) := " .. (globaleLinienlast(s, "gx"))); table.insert(vars_to_del, "gx_temp") end
            if has_gy then math.eval("gy_temp(x) := " .. (globaleLinienlast(s, "gy"))); table.insert(vars_to_del, "gy_temp") end
            
            for j = 0, ptsBiegelinie do
                local x_val = (j / ptsBiegelinie) * L; local x_str = fN(x_val)
                local vK_total = 0
                local M_total = 0
                
                if has_q then
                    M_total = M_total + (casToNumber(math.eval("approx(q_cas_M("..x_str.."))")) or 0)
                    table.insert(s.Q_cas_pts, casToNumber(math.eval("approx(q_cas_Q("..x_str.."))")) or 0)
                    local vK_x_EI = casToNumber(math.eval("approx(q_cas_vK_EI("..x_str.."))")) or 0
                    local N3_val = 3*(x_val/L)^2 - 2*(x_val/L)^3
                    local N4_val = -(x_val^2)/L + (x_val^3)/(L^2)
                    vK_total = vK_total + (vK_x_EI - s.vK_L_EI * N3_val - s.phiK_L_EI * N4_val)
                end
                
                if has_m then
                    M_total = M_total - (casToNumber(math.eval("approx(m_cas_M("..x_str.."))")) or 0)
                    local vK_x_EI_m = casToNumber(math.eval("approx(m_cas_vK_EI("..x_str.."))")) or 0
                    local N3_val = 3*(x_val/L)^2 - 2*(x_val/L)^3
                    local N4_val = -(x_val^2)/L + (x_val^3)/(L^2)
                    vK_total = vK_total + (vK_x_EI_m - s.vK_L_EI_m * N3_val - s.phiK_L_EI_m * N4_val)
                end
                
                table.insert(s.M_cas_pts, M_total)
                table.insert(s.v_cas_pts_EI, vK_total)
                
                if has_n then
                    table.insert(s.N_cas_pts, casToNumber(math.eval("approx(n_cas_N("..x_str.."))")) or 0)
                    local uK_x_EA = casToNumber(math.eval("approx(n_cas_uK_EA("..x_str.."))")) or 0
                    table.insert(s.u_cas_pts_EA, -uK_x_EA + (x_val/L) * s.uK_L_EA)
                end
            end
            
            for j = 0, 10 do
                local x_val = (j / 10) * L; local x_str = fN(x_val)
                if has_q then table.insert(s.q_pts, casToNumber(math.eval("approx(q_temp("..x_str.."))")) or 0) end
                if pure_n_cas then table.insert(s.n_pts, casToNumber(math.eval("approx(n_pure("..x_str.."))")) or 0) end
                if pure_m_cas then table.insert(s.m_pts, casToNumber(math.eval("approx(m_pure("..x_str.."))")) or 0) end
                if has_gx then table.insert(s.gx_pts, casToNumber(math.eval("approx(gx_temp("..x_str.."))")) or 0) end
                if has_gy then table.insert(s.gy_pts, casToNumber(math.eval("approx(gy_temp("..x_str.."))")) or 0) end
            end
            
            if #vars_to_del > 0 then math.eval("DelVar " .. table.concat(vars_to_del, ", ")) end
        else 
            s.q_pts = nil; s.Q_cas_pts = nil; s.M_cas_pts = nil; s.v_cas_pts_EI = nil
            s.n_pts = nil; s.N_cas_pts = nil; s.u_cas_pts_EA = nil
            s.m_pts = nil
            s.gx_pts = nil; s.gy_pts = nil
        end
    end
end

local function pixelZuMeterX(px) 
    local drawPxProMeter = pxProMeter
    return math.floor(((px - offsetX) / drawPxProMeter) / rasterMass + 0.5) * rasterMass 
end
local function pixelZuMeterY(py) 
    local drawPxProMeter = pxProMeter
    return math.floor(((py - offsetY) / drawPxProMeter) / rasterMass + 0.5) * rasterMass 
end
local function abstand(x1, y1, x2, y2) return math.sqrt((x2 - x1)^2 + (y2 - y1)^2) end
local function abstandZurLinie(px, py, x1, y1, x2, y2)
    local lineLen = abstand(x1, y1, x2, y2); if lineLen == 0 then return abstand(px, py, x1, y1) end
    local t = math.max(0, math.min(1, ((px - x1)*(x2 - x1) + (py - y1)*(y2 - y1)) / (lineLen^2)))
    return abstand(px, py, x1 + t * (x2 - x1), y1 + t * (y2 - y1))
end

local function drawRotatedPolygon(gc, pts, cx, cy, angle)
    local r = {}; local c, s = math.cos(math.rad(-angle)), math.sin(math.rad(-angle))
    for i = 1, #pts, 2 do local dx, dy = pts[i]-cx, pts[i+1]-cy; table.insert(r, cx+dx*c-dy*s); table.insert(r, cy+dx*s+dy*c) end; gc:fillPolygon(r)
end

-- Streckenlasten bekommen etwas groessere Pfeilspitzen als die uebrigen Pfeile
LASTPFEIL_KOPF = 1.4

local function drawArrow(gc, x1, y1, x2, y2, kopf)
    gc:drawLine(x1, y1, x2, y2); local dx, dy = x2 - x1, y2 - y1; local L = math.sqrt(dx*dx + dy*dy)
    local hl, hw = 6 * (kopf or 1), 2 * (kopf or 1)
    if L > 0 then local ux, uy = dx/L, dy/L; local bx, by = x2 - hl*ux, y2 - hl*uy; gc:fillPolygon({x2, y2, bx + hw*-uy, by + hw*ux, bx - hw*-uy, by - hw*ux}) end
end

local function drawMoment(gc, cx, cy, r, isClockwise)
    local pts = render_pts_4; for k_idx=1,#pts do pts[k_idx]=nil end; local startAng = -math.pi/2
    for i = 0, 16 do local a = startAng + (isClockwise and 1 or -1) * (math.pi * 1.5) * (i / 16); pts[#pts + 1] = cx + r * math.cos(a); pts[#pts + 1] = cy + r * math.sin(a) end
    gc:drawPolyLine(pts); local dx, dy = pts[#pts-1] - pts[#pts-3], pts[#pts] - pts[#pts-2]; local L = math.sqrt(dx*dx + dy*dy)
    if L > 0 then local ux, uy = dx/L, dy/L; local bx, by = pts[#pts-1] - 5*ux, pts[#pts] - 5*uy; gc:fillPolygon({pts[#pts-1], pts[#pts], bx + 2*-uy, by + 2*ux, bx - 2*-uy, by - 2*ux}) end
end

local function drawRodMoment(gc, cx, cy, ux, uy, isPos)
    local a, r = math.atan2(uy, ux), 12
    local function dh(o, isCCW)
        local cx2, cy2, pts = cx + math.cos(o)*14, cy + math.sin(o)*14, {}
        for i=0,16 do local an = isCCW and (o+math.pi*0.25+(math.pi*1.5)*(i/16)) or (o-math.pi*0.25-(math.pi*1.5)*(i/16)); pts[#pts+1]=cx2+r*math.cos(an); pts[#pts+1]=cy2+r*math.sin(an) end
        gc:drawPolyLine(pts); local L = math.sqrt((pts[#pts-1]-pts[#pts-3])^2 + (pts[#pts]-pts[#pts-2])^2)
        if L>0 then local dx, dy = (pts[#pts-1]-pts[#pts-3])/L, (pts[#pts]-pts[#pts-2])/L; local bx, by = pts[#pts-1]-7*dx, pts[#pts]-7*dy; gc:fillPolygon({pts[#pts-1], pts[#pts], bx-4*dy, by+4*dx, bx+4*dy, by-4*dx}) end
    end
    if isPos then dh(a, true); dh(a+math.pi, false) else dh(a, false); dh(a+math.pi, true) end
end

local function drawZigZag(gc, px, py, angle_deg)
    local r_pts, c_a, s_a = {}, math.cos(math.rad(-angle_deg)), math.sin(math.rad(-angle_deg)); local pts = {0,0, -5,4, -10,-4, -15,4, -20,-4, -25,0, -30,0}
    for j=1, #pts, 2 do table.insert(r_pts, px + pts[j]*c_a - pts[j+1]*s_a); table.insert(r_pts, py + pts[j]*s_a + pts[j+1]*c_a) end; gc:drawPolyLine(r_pts)
end

local function drawSupport(gc, k, node_idx, cx, cy)
    local lines = {}
    local angle = k.winkel or 0
    
    local conn = {}
    for _, s in ipairs(staebe) do
        if not s.is_cut then
            if s.k1 == node_idx then table.insert(conn, math.atan2(knoten[s.k2].y - k.y, knoten[s.k2].x - k.x))
            elseif s.k2 == node_idx then table.insert(conn, math.atan2(knoten[s.k1].y - k.y, knoten[s.k1].x - k.x)) end
        end
    end
    
    local is_sliding_sleeve = false
    
    if (not k.winkel or k.winkel == 0) then
        if (k.lager_x and k.lager_y and k.lager_m) then
            if #conn == 1 then
                angle = -math.deg(conn[1])
            elseif #conn > 1 then
                table.sort(conn)
                local max_gap = (conn[1] + 2*math.pi) - conn[#conn]
                local bisect = (conn[1] + 2*math.pi + conn[#conn]) / 2
                for j = 1, #conn - 1 do
                    local gap = conn[j+1] - conn[j]
                    if gap > max_gap then max_gap = gap; bisect = (conn[j+1] + conn[j]) / 2 end
                end
                angle = -math.deg(bisect)
            end
        end
    end
    
    local is_sliding_sleeve = false
    if #conn == 1 and k.lager_m and (k.lager_x ~= k.lager_y) then
        local beam_ang_deg = math.deg(-conn[1])
        local free_dir = k.lager_y and (k.winkel or 0) or ((k.winkel or 0) + 90)
        local diff = math.abs((free_dir - beam_ang_deg) % 180)
        if diff < 2 or diff > 178 then is_sliding_sleeve = true end
    end
    
    if is_sliding_sleeve then
        angle = -math.deg(conn[1])
        table.insert(lines, {cx - 15, cy - 4, cx + 15, cy - 4})
        for x = cx - 12, cx + 12, 4 do table.insert(lines, {x, cy - 4, x + 4, cy - 10}) end
        table.insert(lines, {cx - 15, cy + 4, cx + 15, cy + 4})
        for x = cx - 12, cx + 12, 4 do table.insert(lines, {x, cy + 4, x - 4, cy + 10}) end
    elseif k.lager_x and k.lager_y and k.lager_m then
        table.insert(lines, {cx, cy - 15, cx, cy + 15})
        for y = cy - 12, cy + 12, 4 do table.insert(lines, {cx, y, cx - 6, y + 4}) end
    elseif k.lager_x and k.lager_y then
        table.insert(lines, {cx, cy, cx - 8, cy + 12}); table.insert(lines, {cx, cy, cx + 8, cy + 12}); table.insert(lines, {cx - 8, cy + 12, cx + 8, cy + 12})
        for x = cx - 8, cx + 8, 4 do table.insert(lines, {x, cy + 12, x - 4, cy + 18}) end
    elseif k.lager_x and k.lager_m then
        table.insert(lines, {cx, cy - 12, cx, cy + 12})
        table.insert(lines, {cx - 4, cy - 15, cx - 4, cy + 15})
        for y = cy - 12, cy + 12, 4 do table.insert(lines, {cx - 4, y, cx - 10, y + 4}) end
    elseif k.lager_y and k.lager_m then
        table.insert(lines, {cx - 12, cy, cx + 12, cy})
        table.insert(lines, {cx - 15, cy + 4, cx + 15, cy + 4})
        for x = cx - 12, cx + 12, 4 do table.insert(lines, {x, cy + 4, x - 4, cy + 10}) end
    elseif k.lager_x then
        table.insert(lines, {cx, cy, cx - 12, cy - 8}); table.insert(lines, {cx, cy, cx - 12, cy + 8}); table.insert(lines, {cx - 12, cy - 8, cx - 12, cy + 8})
        table.insert(lines, {cx - 16, cy - 12, cx - 16, cy + 12})
    elseif k.lager_y then
        table.insert(lines, {cx, cy, cx - 8, cy + 12}); table.insert(lines, {cx, cy, cx + 8, cy + 12}); table.insert(lines, {cx - 8, cy + 12, cx + 8, cy + 12})
        table.insert(lines, {cx - 12, cy + 16, cx + 12, cy + 16})
    elseif k.lager_m then
        table.insert(lines, {cx - 8, cy - 8, cx + 8, cy - 8}); table.insert(lines, {cx + 8, cy - 8, cx + 8, cy + 8}); table.insert(lines, {cx + 8, cy + 8, cx - 8, cy + 8}); table.insert(lines, {cx - 8, cy + 8, cx - 8, cy - 8})
        for i = -4, 4, 4 do table.insert(lines, {cx - 8, cy + i, cx + i, cy + 8}); table.insert(lines, {cx - i, cy - 8, cx + 8, cy - i}) end
    end
    
    local c_ang, s_ang = math.cos(math.rad(-angle)), math.sin(math.rad(-angle))
    for _, l in ipairs(lines) do
        local x1, y1 = l[1]-cx, l[2]-cy
        local x2, y2 = l[3]-cx, l[4]-cy
        gc:drawLine(cx + x1*c_ang - y1*s_ang, cy + x1*s_ang + y1*c_ang, cx + x2*c_ang - y2*s_ang, cy + x2*s_ang + y2*c_ang)
    end
end

local function updateHover()
    if menuOffen then return end; hoverObj, hoverTyp = nil, nil
    local drawPxProMeter = pxProMeter
    for i, k in ipairs(knoten) do 
        local n_px = k.x * drawPxProMeter + offsetX
        local n_py = k.y * drawPxProMeter + offsetY
        if ansichtsModus == "V" then
            local ux, uy = getKinematicDisp(i)
            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
            n_px = n_px + ux * anim_f
            n_py = n_py + uy * anim_f
        end
        if abstand(mouseX, mouseY, n_px, n_py) < 10 then hoverObj, hoverTyp = i, "knoten"; return end 
    end
    for i, s in ipairs(staebe) do 
        local px1, py1 = knoten[s.k1].x * drawPxProMeter + offsetX, knoten[s.k1].y * drawPxProMeter + offsetY
        local px2, py2 = knoten[s.k2].x * drawPxProMeter + offsetX, knoten[s.k2].y * drawPxProMeter + offsetY
        if ansichtsModus == "V" then
            local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(i)
            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
            px1 = px1 + u1x * anim_f
            py1 = py1 + u1y * anim_f
            px2 = px2 + u2x * anim_f
            py2 = py2 + u2y * anim_f
        end
        if (s.bogen_r or 0) ~= 0 then
            local R = math.abs(s.bogen_r) * drawPxProMeter
            local dx, dy = px2 - px1, py2 - py1
            local L_screen = math.sqrt(dx^2 + dy^2)
            if L_screen > 0 and R >= L_screen/2 then
                local sgn = s.bogen_r > 0 and -1 or 1
                local d_px = math.sqrt(R^2 - (L_screen/2)^2)
                local cx = (px1+px2)/2 + (dy/L_screen) * sgn * d_px
                local cy = (py1+py2)/2 - (dx/L_screen) * sgn * d_px
                local dist = abstand(mouseX, mouseY, cx, cy)
                if math.abs(dist - R) < 8 then
                    local v1x, v1y = px1 - cx, py1 - cy
                    local v2x, v2y = px2 - cx, py2 - cy
                    local vmx, vmy = mouseX - cx, mouseY - cy
                    local angle1 = math.atan2(v1y, v1x)
                    local angle2 = math.atan2(v2y, v2x)
                    local angleM = math.atan2(vmy, vmx)
                    local function angDiff(a, b) local d = (a - b) % (2*math.pi); if d > math.pi then d = d - 2*math.pi end; return d end
                    local d12 = angDiff(angle2, angle1)
                    local d1m = angDiff(angleM, angle1)
                    if d12 * d1m >= 0 and math.abs(d1m) <= math.abs(d12) then
                        hoverObj, hoverTyp = i, "stab"; return
                    end
                end
            end
        else
            if abstandZurLinie(mouseX, mouseY, px1, py1, px2, py2) < 5 then hoverObj, hoverTyp = i, "stab"; return end 
        end
    end
end

local function factorLGS(A)
    local n = #A
    local max_diag = 0
    for i = 1, n do if math.abs(A[i][i]) > max_diag then max_diag = math.abs(A[i][i]) end end
    local tol = math.max(1e-10, max_diag * 1e-12)
    local L = {}; local D = {}
    for i = 1, n do L[i] = {}; for j = 1, n do L[i][j] = 0 end end
    
    local top = {}
    for j = 1, n do
        top[j] = j
        for i = 1, j - 1 do
            if math.abs(A[i][j]) > 1e-12 then
                top[j] = i
                break
            end
        end
    end

    for j = 1, n do
        local sum_d = A[j][j]
        for k = top[j], j - 1 do 
            sum_d = sum_d - L[j][k] * L[j][k] * D[k] 
        end
        if sum_d < tol then return nil end
        D[j] = sum_d
        L[j][j] = 1
        for i = j + 1, n do
            if j >= top[i] then
                local sum_l = A[i][j]
                local k_start = math.max(top[i], top[j])
                for k = k_start, j - 1 do 
                    sum_l = sum_l - L[i][k] * L[j][k] * D[k] 
                end
                L[i][j] = sum_l / sum_d
            else
                L[i][j] = 0
            end
        end
    end
    return {L = L, D = D, n = n, top = top}
end

local function solveFactoredLGS(fact, b)
    local n = fact.n
    local L = fact.L
    local D = fact.D
    local top = fact.top
    local x = {}; for i=1,n do x[i] = b[i] end
    for i = 1, n do
        local sum = x[i]
        for k = top[i], i - 1 do sum = sum - L[i][k] * x[k] end
        x[i] = sum
    end
    for i = 1, n do x[i] = x[i] / D[i] end
    for i = n, 1, -1 do
        local sum = x[i]
        for k = i + 1, n do 
            if i >= top[k] then sum = sum - L[k][i] * x[k] end
        end
        x[i] = sum
    end
    return x
end

-- ========================================================
-- ELEMENTMATRIZEN UND LASTEN 
-- ========================================================
local function getFesteinspannkraefte(stab, L, ignoreCondensation)
    local function fN(n) 
        local s = string.format("%.12g", n):gsub(",", ".")
        if s:find("e") then s = s:gsub("e(.-)$", "*10^(%1)") end
        return "("..s..")" 
    end
    
    local c_val = (knoten[stab.k2].x - knoten[stab.k1].x) / L
    local s_val = -(knoten[stab.k2].y - knoten[stab.k1].y) / L
    
    local L_s = fN(L)
    local eq_q = getEqQ(stab, L, fN, L_s)
    local eq_n = getEqN(stab, L, fN, L_s)
    local eq_q_num = casWithDummySymbols(eq_q)
    local eq_n_num = casWithDummySymbols(eq_n)
    local global_cas = string.hasx(stab.gx_str or "") or string.hasx(stab.gy_str or "")
    local use_q_cas = (stab.q_str and string.hasx(stab.q_str)) or global_cas
    local use_n_cas = (stab.n_str and string.hasx(stab.n_str)) or global_cas
    local use_m_cas = (stab.m_str and string.hasx(stab.m_str))
    
    local eff_gx = (stab.gx or 0) * (stab.gx_proj and math.abs(s_val) or 1)
    local eff_gy = (stab.gy or 0) * (stab.gy_proj and math.abs(c_val) or 1)
    local n_add = eff_gx * c_val - eff_gy * s_val
    local q_add = eff_gx * s_val + eff_gy * c_val
    
    -- eq_q/eq_n enthalten q_A/q_B bzw. n_A/n_B bereits, sobald deren Strings gesetzt sind.
    -- Im CAS-Pfad duerfen sie dann nicht zusaetzlich klassisch addiert werden.
    local trap_q_in_cas = use_q_cas and (stab.q_A_str or stab.q_B_str)
    local trap_n_in_cas = use_n_cas and (stab.n_A_str or stab.n_B_str)
    local p_i = (trap_q_in_cas and 0 or stab.q_A) + (not use_q_cas and (stab.q + q_add) or 0)
    local p_k = (trap_q_in_cas and 0 or stab.q_B) + (not use_q_cas and (stab.q + q_add) or 0)
    local ax_i = (trap_n_in_cas and 0 or stab.n_A) + (not use_n_cas and (stab.n + n_add) or 0)
    local ax_k = (trap_n_in_cas and 0 or stab.n_B) + (not use_n_cas and (stab.n + n_add) or 0)
    
    local N_i = -((2 * ax_i + ax_k) / 6) * L; local N_k = -((ax_i + 2 * ax_k) / 6) * L      
    local Q_i = -(L / 60) * (21 * p_i + 9 * p_k); local Q_k = -(L / 60) * (9 * p_i + 21 * p_k) 
    local M_i = (L^2 / 60) * (3 * p_i + 2 * p_k)
    local M_k = -(L^2 / 60) * (2 * p_i + 3 * p_k)
    -- konstantes Streckenmoment m: konsistente Stabendkraefte sind Q_i = -m, Q_k = +m (kein Endmoment),
    -- identisch zum CAS-Pfad unten mit int m*N' dx
    if not use_m_cas then Q_i = Q_i - stab.m; Q_k = Q_k + stab.m end
    
    if use_q_cas and math.eval then
        Q_i = Q_i + (casToNumber(math.eval("approx(-integral(("..eq_q_num..")*(1-3*(x/"..L_s..")^2+2*(x/"..L_s..")^3),x,0,"..L_s.."))")) or 0)
        M_i = M_i + (casToNumber(math.eval("approx(integral(("..eq_q_num..")*("..L_s.."*(x/"..L_s.."-2*(x/"..L_s..")^2+(x/"..L_s..")^3)),x,0,"..L_s.."))")) or 0)
        Q_k = Q_k + (casToNumber(math.eval("approx(-integral(("..eq_q_num..")*(3*(x/"..L_s..")^2-2*(x/"..L_s..")^3),x,0,"..L_s.."))")) or 0)
        M_k = M_k + (casToNumber(math.eval("approx(integral(("..eq_q_num..")*("..L_s.."*(-(x/"..L_s..")^2+(x/"..L_s..")^3)),x,0,"..L_s.."))")) or 0)
    end
    
    if use_n_cas and math.eval then
        N_i = N_i + (casToNumber(math.eval("approx(-integral(("..eq_n_num..")*(1-(x/"..L_s..")),x,0,"..L_s.."))")) or 0)
        N_k = N_k + (casToNumber(math.eval("approx(-integral(("..eq_n_num..")*(x/"..L_s.."),x,0,"..L_s.."))")) or 0)
    end
    
    if use_m_cas and math.eval then
        local L_s, eq_m = fN(L), stab.m_str
        Q_i = Q_i + (casToNumber(math.eval("approx(integral(("..eq_m..")*(-6*x/("..L_s.."^2)+6*x^2/("..L_s.."^3)),x,0,"..L_s.."))")) or 0)
        M_i = M_i + (casToNumber(math.eval("approx(integral(("..eq_m..")*(-1+4*x/"..L_s.."-3*x^2/("..L_s.."^2)),x,0,"..L_s.."))")) or 0)
        Q_k = Q_k + (casToNumber(math.eval("approx(integral(("..eq_m..")*(6*x/("..L_s.."^2)-6*x^2/("..L_s.."^3)),x,0,"..L_s.."))")) or 0)
        M_k = M_k + (casToNumber(math.eval("approx(integral(("..eq_m..")*(2*x/"..L_s.."-3*x^2/("..L_s.."^2)),x,0,"..L_s.."))")) or 0)
    end
    
    if (stab.To or 0) ~= 0 or (stab.Tu or 0) ~= 0 then
        -- gleichmaessiger Anteil immer, Temperaturgradient nur mit Hoehe h > 0
        local N_t = stabEA_K(stab) * (stab.alpha or 0) * ((stab.To + stab.Tu) / 2)
        local M_t = ((stab.h or 0) > 0) and (stabEI_K(stab) * (stab.alpha or 0) * ((stab.Tu - stab.To) / stab.h)) or 0
        N_i = N_i + N_t; N_k = N_k - N_t; M_i = M_i + M_t; M_k = M_k - M_t
    end
    
    if not ignoreCondensation then
        if stab.n_gelenk_A and stab.n_gelenk_B then N_i = 0; N_k = 0 
        elseif stab.n_gelenk_A then N_k = N_k + N_i; N_i = 0 
        elseif stab.n_gelenk_B then N_i = N_i + N_k; N_k = 0 end
        
        if stab.q_gelenk_A and stab.q_gelenk_B then Q_i = 0; Q_k = 0
        elseif stab.q_gelenk_A then M_i = M_i + Q_i*(L/2); M_k = M_k + Q_i*(L/2); Q_k = Q_k + Q_i; Q_i = 0 
        elseif stab.q_gelenk_B then M_i = M_i - Q_k*(L/2); M_k = M_k - Q_k*(L/2); Q_i = Q_i + Q_k; Q_k = 0 end
    end
    
    return N_i, Q_i, M_i, N_k, Q_k, M_k
end

local function berechneElementLastvektor(stab)
    local k1, k2 = knoten[stab.k1], knoten[stab.k2]
    local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
    if L == 0 then return nil end
    local c_val, s_val = dx / L, -dy / L
    local N_i, Q_i, M_i, N_k, Q_k, M_k = getFesteinspannkraefte(stab, L, false)
    local T = { {c_val,-s_val,0,0,0,0}, {s_val,c_val,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c_val,-s_val,0}, {0,0,0,s_val,c_val,0}, {0,0,0,0,0,1} }
    return matMult(buildKnotenTransform(stab), matMult(matTrans(T), { {N_i}, {Q_i}, {M_i}, {N_k}, {Q_k}, {M_k} }))
end

local function berechneStabMatrix(stab)
    local k1, k2 = knoten[stab.k1], knoten[stab.k2]
    local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
    if L == 0 then return nil end
    local EA_s, EI_s = stabEA_K(stab), stabEI_K(stab)
    local EA_L, EI12, EI6, EI4, EI2 = EA_s/L, (12*EI_s)/(L^3), (6*EI_s)/(L^2), (4*EI_s)/L, (2*EI_s)/L
    local k_loc = { {EA_L,0,0,-EA_L,0,0}, {0,EI12,-EI6,0,-EI12,-EI6}, {0,-EI6,EI4,0,EI6,EI2}, {-EA_L,0,0,EA_L,0,0}, {0,-EI12,EI6,0,EI12,EI6}, {0,-EI6,EI2,0,EI6,EI4} }
    if stab.n_gelenk_A or stab.n_gelenk_B then k_loc[1][1]=0; k_loc[1][4]=0; k_loc[4][1]=0; k_loc[4][4]=0 end
    if stab.q_gelenk_A or stab.q_gelenk_B then for i=1,6 do k_loc[2][i]=0; k_loc[5][i]=0; k_loc[i][2]=0; k_loc[i][5]=0 end; k_loc[3][3]=EI_s/L; k_loc[3][6]=-EI_s/L; k_loc[6][3]=-EI_s/L; k_loc[6][6]=EI_s/L end
    local c, s = dx/L, -dy/L; local T = { {c,-s,0,0,0,0}, {s,c,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c,-s,0}, {0,0,0,s,c,0}, {0,0,0,0,0,1} }
    local TK = buildKnotenTransform(stab)
    return matMult(matMult(TK, matMult(matMult(matTrans(T), k_loc), T)), matTrans(TK)), k_loc
end

local function baueLastvektor()
    local F = {}; for i = 1, anzahlGleichungen do F[i] = 0 end
    for i, k in ipairs(knoten) do
        local rad_last, rad_lager = math.rad(-(k.last_w or 0)), math.rad(k.winkel or 0)
        local cl, sl, c, s = math.cos(rad_last), math.sin(rad_last), math.cos(rad_lager), math.sin(rad_lager)
        -- Last global -> Lagersystem mit derselben Drehung wie buildKnotenTransform (TK = R(winkel))
        local fx_g, fy_g = k.last_x*cl - k.last_y*sl, k.last_x*sl + k.last_y*cl
        local f_xi = fx_g*c - fy_g*s; local f_eta = fx_g*s + fy_g*c
        if k.eq_x > 0 then F[k.eq_x] = F[k.eq_x] + f_xi end; if k.eq_y > 0 then F[k.eq_y] = F[k.eq_y] + f_eta end
        if type(k.eq_m) == "number" and k.eq_m > 0 then F[k.eq_m] = F[k.eq_m] + k.last_m end
    end
    for i, s in ipairs(staebe) do
        if not s.is_cut then
            -- Bogen: die Lasten tragen seine Teilstaebe (injectVirtualArcs), nicht die Sehne
            local id, p_global = stabID[i], (not s.is_virtual_parent) and berechneElementLastvektor(s) or nil
            if p_global then for j = 1, 6 do if id[j] > 0 then F[id[j]] = F[id[j]] - p_global[j][1] end end end
            if s.gelenk_A and s.x_mA ~= 0 then if id[3] > 0 then F[id[3]] = F[id[3]] + s.x_mA end; if type(knoten[s.k1].eq_m)=="number" and knoten[s.k1].eq_m>0 then F[knoten[s.k1].eq_m] = F[knoten[s.k1].eq_m] - s.x_mA end end
            if s.gelenk_B and s.x_mB ~= 0 then if id[6] > 0 then F[id[6]] = F[id[6]] + s.x_mB end; if type(knoten[s.k2].eq_m)=="number" and knoten[s.k2].eq_m>0 then F[knoten[s.k2].eq_m] = F[knoten[s.k2].eq_m] - s.x_mB end end
        end
        if (s.x_nA or 0) ~= 0 then
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2+dy^2)
            if L > 0 then
                local ux, uy = dx/L, dy/L
                -- Kraftpaar N = X_i in Stabrichtung, je Knoten ins Lagersystem (xi, eta) projiziert
                for _, kp in ipairs({{knoten[s.k1], 1}, {knoten[s.k2], -1}}) do
                    local k, vz = kp[1], kp[2] * s.x_nA
                    local b = math.rad(k.winkel or 0)
                    local c, sn = math.cos(b), math.sin(b)
                    if k.eq_x > 0 then F[k.eq_x] = F[k.eq_x] + vz * (ux * c - uy * sn) end
                    if k.eq_y > 0 then F[k.eq_y] = F[k.eq_y] + vz * (ux * sn + uy * c) end
                end
            end
        end
    end
    return F
end

local cached_factored_K = nil

-- ============================================================================
-- Starre Staebe in der FEM: exakte Zwangsbedingungen statt grosser Ersatzsteifigkeit
--   dehnsteif:  u_B - u_A = epsT*L
--   biegesteif: phi_A - phi_B = -kappaT*L,  w_B - w_A + L*phi_A = -kappaT*L^2/2   (phi = -w')
-- Geloest wird im Unterraum der zulaessigen Verschiebungen u = Tz*ur + u0, die Kondition bleibt
-- wie ohne starre Staebe. Die Stabkraefte starrer Staebe folgen aus K*u + C'*lambda = F.
-- ============================================================================
glob_zwang = nil   -- je Stab lokale Zusatz-Endkraefte aus den Zwangsbedingungen
-- { unbestimmt = Anzahl ueberzaehliger Zwangsbedingungen, widerspruch = Temperatur in gegenseitig
--   gehaltenen starren Staeben } fuer die Hinweise nach der Berechnung
glob_zwang_info = nil

local function starrTemperatur(s)
    local kT, eT = 0, 0
    if (s.To or 0) ~= 0 or (s.Tu or 0) ~= 0 then
        eT = (s.alpha or 0) * ((s.To or 0) + (s.Tu or 0)) / 2
        if (s.h or 0) > 0 then kT = (s.alpha or 0) * ((s.Tu or 0) - (s.To or 0)) / s.h end
    end
    return kT, eT
end

-- Zeilen { c = {[Freiheitsgrad] = Wert}, g, stab, cl (lokale Zeile), leer } fuer alle starren Staebe
local function baueZwangsbedingungen(ids)
    local zeilen = {}
    for i, s in ipairs(staebe) do
        local bieg, dehn = stabBiegesteif(s), stabDehnsteif(s)
        if (bieg or dehn) and not s.is_cut and not s.is_virtual_parent and ids[i] then
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local c, sn = dx/L, -dy/L
                local T = { {c,-sn,0,0,0,0}, {sn,c,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c,-sn,0}, {0,0,0,sn,c,0}, {0,0,0,0,0,1} }
                local A = matMult(T, matTrans(buildKnotenTransform(s)))   -- lokale Endverschiebungen = A * Element-Freiheitsgrade
                local kT, eT = starrTemperatur(s)
                local lokal = {}
                if dehn and not (s.n_gelenk_A or s.n_gelenk_B) then lokal[#lokal + 1] = { cl = {-1, 0, 0, 1, 0, 0}, g = eT * L } end
                if bieg then
                    lokal[#lokal + 1] = { cl = {0, 0, 1, 0, 0, -1}, g = -kT * L }
                    if not (s.q_gelenk_A or s.q_gelenk_B) then lokal[#lokal + 1] = { cl = {0, -1, L, 0, 1, 0}, g = -kT * L * L / 2 } end
                end
                local id = ids[i]
                for _, z in ipairs(lokal) do
                    local row, leer = {}, true
                    for j = 1, 6 do
                        local v = 0
                        for k = 1, 6 do v = v + z.cl[k] * A[k][j] end
                        if id[j] > 0 and math.abs(v) > 1e-14 then row[id[j]] = (row[id[j]] or 0) + v; leer = false end
                    end
                    zeilen[#zeilen + 1] = { c = row, g = z.g, stab = i, cl = z.cl, leer = leer }
                end
            end
        end
    end
    return zeilen
end

-- kleines dichtes LGS mit Spaltenpivot; nil, wenn singulaer
local function gaussLoesen(A, b)
    local n = #b
    local M = {}
    for i = 1, n do M[i] = {}; for j = 1, n do M[i][j] = A[i][j] end; M[i][n + 1] = b[i] end
    for k = 1, n do
        local p, best = k, math.abs(M[k][k])
        for i = k + 1, n do if math.abs(M[i][k]) > best then p, best = i, math.abs(M[i][k]) end end
        if best < 1e-300 then return nil end
        M[k], M[p] = M[p], M[k]
        for i = k + 1, n do
            local f = M[i][k] / M[k][k]
            if f ~= 0 then for j = k, n + 1 do M[i][j] = M[i][j] - f * M[k][j] end end
        end
    end
    local x = {}
    for i = n, 1, -1 do
        local s = M[i][n + 1]
        for j = i + 1, n do s = s - M[i][j] * x[j] end
        x[i] = s / M[i][i]
    end
    return x
end

-- Zwangsbedingungen eliminieren und reduziertes System faktorisieren
-- Nachgiebigkeit eines starren Stabes mit EA = EI = 1 in seinen Zwangszeilen (wie der Grenzwert
-- EA = EI = 1/eps im Rand-LGS): Laengszeile L, Drehzeile L, Querzeile L^3/3, Dreh/Quer L^2/2
local function zwangsNachgiebigkeit(za, zb)
    if za.stab ~= zb.stab then return 0 end
    local k1, k2 = knoten[staebe[za.stab].k1], knoten[staebe[za.stab].k2]
    local L = math.sqrt((k2.x - k1.x)^2 + (k2.y - k1.y)^2)
    local function art(z) return (z.cl[1] ~= 0 and "n") or (z.cl[2] ~= 0 and "q") or "m" end
    local a, b = art(za), art(zb)
    if a == "n" or b == "n" then return (a == b) and L or 0 end
    if a == "m" and b == "m" then return L end
    if a == "q" and b == "q" then return L^3 / 3 end
    return L^2 / 2
end

local function faktorisiereMitZwang(K, zeilen)
    local n = #K
    local R, kept, pivot, istPivot = {}, {}, {}, {}
    -- alle nicht leeren Zeilen; h = Herkunft einer Stufenzeile als Kombination dieser Zeilen
    local alle, nullvek, widerspruch = {}, {}, false
    for _, z in ipairs(zeilen) do
        if not z.leer then
            alle[#alle + 1] = z
            local d, norm = {}, 0
            for j = 1, n do d[j] = z.c[j] or 0; norm = math.max(norm, math.abs(d[j])) end
            local g = z.g
            local h = { [#alle] = 1 }
            -- bisherige Pivotspalten aus der Zeile entfernen
            for r = 1, #R do
                local f = d[pivot[r]]
                if f ~= 0 then
                    for j = 1, n do d[j] = d[j] - f * R[r].d[j] end; g = g - f * R[r].g
                    for k, v in pairs(R[r].h) do h[k] = (h[k] or 0) - f * v end
                end
            end
            local p, best = nil, 0
            for j = 1, n do if not istPivot[j] and math.abs(d[j]) > best then p, best = j, math.abs(d[j]) end end
            if p and best > 1e-9 * math.max(norm, 1e-300) then
                local inv = 1 / d[p]
                for j = 1, n do d[j] = d[j] * inv end; g = g * inv
                for k, v in pairs(h) do h[k] = v * inv end
                -- Pivot aus den frueheren Zeilen entfernen (reduzierte Stufenform)
                for r = 1, #R do
                    local f = R[r].d[p]
                    if f ~= 0 then
                        for j = 1, n do R[r].d[j] = R[r].d[j] - f * d[j] end; R[r].g = R[r].g - f * g
                        for k, v in pairs(h) do R[r].h[k] = (R[r].h[k] or 0) - f * v end
                    end
                end
                R[#R + 1] = { d = d, g = g, h = h }; pivot[#R] = p; istPivot[p] = true
                kept[#kept + 1] = z; z.alle_index = #alle
            else
                -- abhaengige Zeile: h ist eine Kombination der Zeilen mit sum h_k * C_k = 0 (Nullvektor
                -- von C'); die Zwangskraefte sind in dieser Richtung durch das Gleichgewicht nicht bestimmt
                nullvek[#nullvek + 1] = h
                if math.abs(g) > 1e-9 * math.max(math.abs(z.g), 1e-12) and math.abs(g) > 1e-12 then widerspruch = true end
            end
        end
    end
    glob_zwang_info = { unbestimmt = #nullvek, widerspruch = widerspruch }
    -- u = Tz*ur + u0: unabhaengige Freiheitsgrade durchnummerieren
    local idx, nr = {}, 0
    for j = 1, n do if not istPivot[j] then nr = nr + 1; idx[j] = nr end end
    local Tz, u0 = {}, {}
    for i = 1, n do Tz[i] = {}; for a = 1, nr do Tz[i][a] = 0 end; u0[i] = 0 end
    for j = 1, n do if idx[j] then Tz[j][idx[j]] = 1 end end
    for r = 1, #R do
        local pr = pivot[r]
        u0[pr] = R[r].g
        for j = 1, n do if idx[j] and R[r].d[j] ~= 0 then Tz[pr][idx[j]] = -R[r].d[j] end end
    end
    local fact = nil
    if nr > 0 then
        local KT = {}
        for i = 1, n do
            KT[i] = {}
            for a = 1, nr do
                local s = 0
                for j = 1, n do local t = Tz[j][a]; if t ~= 0 then s = s + K[i][j] * t end end
                KT[i][a] = s
            end
        end
        local Kr = {}
        for a = 1, nr do
            Kr[a] = {}
            for b = 1, nr do
                local s = 0
                for i = 1, n do local t = Tz[i][a]; if t ~= 0 then s = s + t * KT[i][b] end end
                Kr[a][b] = s
            end
        end
        fact = factorLGS(Kr)
        if not fact then return nil end
    end
    return { zwang = true, fact = fact, Tz = Tz, u0 = u0, nr = nr, n = n, K = K, zeilen = kept,
             alle = alle, nullvek = nullvek, info = glob_zwang_info }
end

-- Loesung mit Zwang; setzt glob_zwang (lokale Zusatz-Endkraefte je starrem Stab)
local function loeseMitZwang(zf, F)
    local n, nr, Tz, K, u0 = zf.n, zf.nr, zf.Tz, zf.K, zf.u0
    local Fm = {}
    for i = 1, n do
        local s = F[i] or 0
        for j = 1, n do if u0[j] ~= 0 then s = s - K[i][j] * u0[j] end end
        Fm[i] = s
    end
    local ur = {}
    if nr > 0 then
        local Fr = {}
        for a = 1, nr do
            local s = 0
            for i = 1, n do local t = Tz[i][a]; if t ~= 0 then s = s + t * Fm[i] end end
            Fr[a] = s
        end
        ur = solveFactoredLGS(zf.fact, Fr)
        if not ur then return nil end
    end
    local u = {}
    for i = 1, n do
        local s = u0[i]
        for a = 1, nr do local t = Tz[i][a]; if t ~= 0 then s = s + t * ur[a] end end
        u[i] = s
    end
    -- Lagrange-Multiplikatoren: (C C') lambda = C (F - K u)
    local r = {}
    for i = 1, n do
        local s = F[i] or 0
        for j = 1, n do s = s - K[i][j] * u[j] end
        r[i] = s
    end
    local m = #zf.zeilen
    local A, b = {}, {}
    for p = 1, m do
        local cp = zf.zeilen[p].c
        local s = 0
        for j, v in pairs(cp) do s = s + v * r[j] end
        b[p] = s
        A[p] = {}
        for q = 1, m do
            local cq, t = zf.zeilen[q].c, 0
            for j, v in pairs(cp) do if cq[j] then t = t + v * cq[j] end end
            A[p][q] = t
        end
    end
    local lambda = (m > 0) and gaussLoesen(A, b) or {}
    -- lambda ueber alle Zeilen; ueberzaehlige Zeilen starten mit 0
    local alle, lam = zf.alle or zf.zeilen, {}
    for k = 1, #alle do lam[k] = 0 end
    for p = 1, m do lam[zf.zeilen[p].alle_index or p] = (lambda and lambda[p]) or 0 end
    -- Starre Teile gegenseitig statisch unbestimmt: lambda + sum t_i mu_i erfuellt das Gleichgewicht
    -- fuer jedes t. Gewaehlt wird die Aufteilung gleich steifer starrer Staebe (Grenzwert
    -- EA = EI = 1/eps, eps -> 0, wie im Rand-LGS): minimale Ergaenzungsenergie 1/2 lambda' W lambda.
    local mu = zf.nullvek or {}
    if #mu > 0 then
        local function W_mal(v)   -- W * v (W blockweise je Stab)
            local out = {}
            for a = 1, #alle do
                local s_ = 0
                for b_, vb in pairs(v) do if vb ~= 0 then s_ = s_ + zwangsNachgiebigkeit(alle[a], alle[b_]) * vb end end
                out[a] = s_
            end
            return out
        end
        local function skalar(x, y) local s_ = 0; for k = 1, #alle do s_ = s_ + (x[k] or 0) * (y[k] or 0) end; return s_ end
        local Wmu, Wlam = {}, W_mal(lam)
        for i = 1, #mu do Wmu[i] = W_mal(mu[i]) end
        -- Haengt das Ergebnis ueberhaupt von der Annahme "gleich steif" ab? Nur wenn lambda_p auf einer
        -- Zeile, die ueber W mit einem Eigenspannungszustand gekoppelt ist, nicht null ist. Sonst ist
        -- t = 0 fuer jede Steifigkeitsannahme (z. B. senkrechte Kraft in einer starren Platte zwischen
        -- zwei Loslagern ohne senkrechte Last), und der Hinweis waere ueberfluessig.
        local lmax, relevant = 0, false
        for k = 1, #alle do lmax = math.max(lmax, math.abs(lam[k] or 0)) end
        for i = 1, #mu do
            for k = 1, #alle do
                if (Wmu[i][k] or 0) ~= 0 and math.abs(lam[k] or 0) > 1e-9 * lmax then relevant = true end
            end
        end
        if zf.info then zf.info.relevant = relevant end
        local Ms, rhs = {}, {}
        for i = 1, #mu do
            Ms[i] = {}
            for j = 1, #mu do Ms[i][j] = skalar(mu[i], Wmu[j]) end
            rhs[i] = -skalar(mu[i], Wlam)
        end
        local t = gaussLoesen(Ms, rhs)
        if t then
            for i = 1, #mu do for k, v in pairs(mu[i]) do lam[k] = lam[k] + t[i] * v end end
        end
    end
    local kraefte = {}
    for p = 1, #alle do
        local z, l = alle[p], lam[p] or 0
        local f = kraefte[z.stab] or {0, 0, 0, 0, 0, 0}
        for k = 1, 6 do f[k] = f[k] + z.cl[k] * l end
        kraefte[z.stab] = f
    end
    glob_zwang = kraefte
    return u
end

berechneSystemGleichungen = function(checkKinematicsOnly, useCache)
    anzahlGleichungen = 0; glob_Legend = {}
    for i, k in ipairs(knoten) do
        if not k.lager_x then anzahlGleichungen=anzahlGleichungen+1; k.eq_x=anzahlGleichungen; glob_Legend[anzahlGleichungen]="Knoten "..i.." u_x" else k.eq_x=0 end
        if not k.lager_y then anzahlGleichungen=anzahlGleichungen+1; k.eq_y=anzahlGleichungen; glob_Legend[anzahlGleichungen]="Knoten "..i.." u_y" else k.eq_y=0 end
        if not k.lager_m then if k.gelenk then k.eq_m="gelenk" else anzahlGleichungen=anzahlGleichungen+1; k.eq_m=anzahlGleichungen; glob_Legend[anzahlGleichungen]="Knoten "..i.." phi" end else k.eq_m=0 end
    end
    stabID = {}
    for i, s in ipairs(staebe) do
        local k1, k2 = knoten[s.k1], knoten[s.k2]; local id = {k1.eq_x, k1.eq_y, 0, k2.eq_x, k2.eq_y, 0}
        -- HIER IST DER FIX: Freiheitsgrade für zerschnittene Stäbe werden nicht mehr gebildet!
        if not s.is_cut and not s.is_virtual_parent then 
            if k1.gelenk or s.gelenk_A then anzahlGleichungen=anzahlGleichungen+1; id[3]=anzahlGleichungen; glob_Legend[anzahlGleichungen]="Stab "..i.." phi_a" else id[3]=k1.eq_m end
            if k2.gelenk or s.gelenk_B then anzahlGleichungen=anzahlGleichungen+1; id[6]=anzahlGleichungen; glob_Legend[anzahlGleichungen]="Stab "..i.." phi_b" else id[6]=k2.eq_m end
        end
        stabID[i] = id
    end
    if anzahlGleichungen == 0 then return {}, stabID end

    local F = {}; 
    if not checkKinematicsOnly and not return_kinematic_mode then 
        F = baueLastvektor() 
    elseif return_kinematic_mode then
        for i = 1, anzahlGleichungen do F[i] = (i % 3) + 1.0 end
    else
        for i = 1, anzahlGleichungen do F[i] = 0 end
    end

    if useCache and cached_factored_K and cached_factored_K.n == anzahlGleichungen and not return_kinematic_mode then
        glob_F = F
        local u
        if cached_factored_K.zwang then u = loeseMitZwang(cached_factored_K, F) else glob_zwang = nil; u = solveFactoredLGS(cached_factored_K, F) end
        if not u then return nil, stabID end
        for i = 1, #u do if u[i] ~= u[i] or math.abs(u[i]) > 1e10 then return nil, stabID end end
        glob_u = u; return u, stabID
    end

    local K = {}; for i = 1, anzahlGleichungen do K[i] = {}; for j = 1, anzahlGleichungen do K[i][j] = 0 end end
    for i, s in ipairs(staebe) do
        if not s.is_cut and not s.is_virtual_parent then
            local k_elem, _ = berechneStabMatrix(s); local id = stabID[i]
            if k_elem then for r=1,6 do for c=1,6 do if id[r]>0 and id[c]>0 then K[id[r]][id[c]] = K[id[r]][id[c]] + k_elem[r][c] end end end end
        end
    end
    for i, k in ipairs(knoten) do
        if k.cx > 0 or k.cy > 0 or k.cm > 0 then
            -- Federachse cx wie gezeichnet: Winkel -f_winkel (drawZigZag), cy dazu senkrecht
            local r = math.rad(k.f_winkel or 0); local c, s = math.cos(r), math.sin(r)
            local k_glob = matMult(matMult({{c,s,0},{-s,c,0},{0,0,1}}, {{k.cx,0,0},{0,k.cy,0},{0,0,k.cm}}), {{c,-s,0},{s,c,0},{0,0,1}})
            if (k.winkel or 0) ~= 0 then
                local rw = math.rad(k.winkel); local cw, sw = math.cos(rw), math.sin(rw)
                local Rw = {{cw,-sw,0},{sw,cw,0},{0,0,1}}
                k_glob = matMult(matMult(Rw, k_glob), matTrans(Rw))
            end
            local eqs = {k.eq_x, k.eq_y, type(k.eq_m)=="number" and k.eq_m or 0}
            for row=1,3 do for col=1,3 do if eqs[row]>0 and eqs[col]>0 then K[eqs[row]][eqs[col]] = K[eqs[row]][eqs[col]] + k_glob[row][col] end end end
        end
    end
    if return_kinematic_mode then
        for i = 1, anzahlGleichungen do K[i][i] = K[i][i] + 1.0 end
    end
    
    -- starre Staebe als exakte Zwangsbedingungen (nicht im PvV-Modus)
    local zeilen, hatZwang = {}, false
    if not return_kinematic_mode then
        zeilen = baueZwangsbedingungen(stabID)
        for _, z in ipairs(zeilen) do if not z.leer then hatZwang = true end end
    end
    local fact
    if hatZwang then fact = faktorisiereMitZwang(K, zeilen) else glob_zwang_info = nil; fact = factorLGS(K) end
    if checkKinematicsOnly and not return_kinematic_mode then return fact ~= nil, stabID end
    
    if not checkKinematicsOnly and not return_kinematic_mode then cached_factored_K = fact end
    
    glob_K = K; glob_F = F; 
    if not fact then return nil, stabID end
    local u
    if hatZwang then u = loeseMitZwang(fact, F) else glob_zwang = nil; u = solveFactoredLGS(fact, F) end
    if not u then return nil, stabID end
    if return_kinematic_mode then
        local max_u = 0
        for i = 1, #u do if math.abs(u[i]) > max_u then max_u = math.abs(u[i]) end end
        if max_u > 0 then for i = 1, #u do u[i] = u[i] / max_u end end
        return u, stabID
    end
    for i = 1, #u do if u[i] ~= u[i] or math.abs(u[i]) > 1e10 then return nil, stabID end end
    glob_u = u; return u, stabID
end

local function berechneAlleSchnittgroessen(u)
    for i, stab in ipairs(staebe) do
        if stab.is_cut or stab.is_virtual_parent then
            for j = 1, 6 do stab.s_local[j] = 0; stab.v_local[j] = 0 end
            stab.mat_k = nil; stab.mat_p = nil; stab.mat_v = nil
        else
            local id, v_k = stabID[i], {{0}, {0}, {0}, {0}, {0}, {0}}
            for j = 1, 6 do if id[j] > 0 then v_k[j][1] = u[id[j]] end end
            local k1, k2 = knoten[stab.k1], knoten[stab.k2]
            local v_g = matMult(matTrans(buildKnotenTransform(stab)), v_k) 
            local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
            
            if L > 0 then
                local c, s = dx/L, -dy/L
                local T = { {c,-s,0,0,0,0}, {s,c,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c,-s,0}, {0,0,0,s,c,0}, {0,0,0,0,0,1} }
                local v_l = matMult(T, v_g)
                local N_i_o, Q_i_o, M_i_o, N_k_o, Q_k_o, M_k_o = getFesteinspannkraefte(stab, L, true)
                local p_orig = { {N_i_o}, {Q_i_o}, {M_i_o}, {N_k_o}, {Q_k_o}, {M_k_o} }
                local EA_s, EI_s = stabEA_K(stab), stabEI_K(stab)
                local EA_L = EA_s / L; local EI12 = 12*EI_s/L^3
                -- starre Staebe: keine Verformung aus den Festeinspannkraeften am Gelenk
                local EA_Lr = stabDehnsteif(stab) and math.huge or EA_L
                local EI12r = stabBiegesteif(stab) and math.huge or EI12
                
                local true_v_l = {v_l[1][1], v_l[2][1], v_l[3][1], v_l[4][1], v_l[5][1], v_l[6][1]}
                if stab.n_gelenk_A and not stab.n_gelenk_B then true_v_l[1] = true_v_l[4] - N_i_o / EA_Lr
                elseif stab.n_gelenk_B and not stab.n_gelenk_A then true_v_l[4] = true_v_l[1] - N_k_o / EA_Lr
                elseif stab.n_gelenk_A and stab.n_gelenk_B then true_v_l[1] = true_v_l[4] end
                if stab.q_gelenk_A and not stab.q_gelenk_B then true_v_l[2] = true_v_l[5] + (L/2)*true_v_l[3] + (L/2)*true_v_l[6] - Q_i_o / EI12r
                elseif stab.q_gelenk_B and not stab.q_gelenk_A then true_v_l[5] = true_v_l[2] - (L/2)*true_v_l[3] - (L/2)*true_v_l[6] - Q_k_o / EI12r
                elseif stab.q_gelenk_A and stab.q_gelenk_B then true_v_l[2] = true_v_l[5] + (L/2)*(true_v_l[3] + true_v_l[6]) end
                
                local EI6 = 6*EI_s/L^2; local EI4 = 4*EI_s/L; local EI2 = 2*EI_s/L
                local k_orig = {
                    { EA_L,      0,         0,       -EA_L,      0,         0       },
                    { 0,         EI12,     -EI6,      0,        -EI12,     -EI6     },
                    { 0,        -EI6,       EI4,      0,         EI6,       EI2     },
                    {-EA_L,      0,         0,        EA_L,      0,         0       },
                    { 0,        -EI12,      EI6,      0,         EI12,      EI6     },
                    { 0,        -EI6,       EI2,      0,         EI6,       EI4     }
                }
                local true_v_l_col = {{true_v_l[1]}, {true_v_l[2]}, {true_v_l[3]}, {true_v_l[4]}, {true_v_l[5]}, {true_v_l[6]}}
                local s_orig = matMult(k_orig, true_v_l_col)
                local zk = glob_zwang and glob_zwang[i]   -- Zwangskraefte starrer Staebe (Lagrange-Multiplikatoren)
                for j = 1, 6 do stab.s_local[j] = s_orig[j][1] + p_orig[j][1] + (zk and zk[j] or 0); stab.v_local[j] = true_v_l[j] end
                
                local N_i, Q_i, M_i, N_k, Q_k, M_k = getFesteinspannkraefte(stab, L, false)
                local p_fest = { {N_i}, {Q_i}, {M_i}, {N_k}, {Q_k}, {M_k} }
                local _, k_loc = berechneStabMatrix(stab)
                local k_global = matMult(matMult(matTrans(T), k_loc), T); local p_global = matMult(matTrans(T), p_fest)
                stab.mat_k = {}; stab.mat_p = {}; stab.mat_v = {}
                for row = 1, 6 do stab.mat_k[row] = {}; for col = 1, 6 do stab.mat_k[row][col] = k_loc[row][col]; stab.mat_k[row][col+6] = k_global[row][col] end
                stab.mat_p[row] = {p_fest[row][1], p_global[row][1]}; stab.mat_v[row] = {true_v_l[row], v_g[row][1]} end
            end
        end
    end
    for i, k in ipairs(knoten) do k.mat_pv = { {k.last_x, (k.eq_x > 0) and u[k.eq_x] or 0}, {k.last_y, (k.eq_y > 0) and u[k.eq_y] or 0}, {k.last_m, (type(k.eq_m)=="number" and k.eq_m>0) and u[k.eq_m] or 0} } end
end

local function berechneAuflagerkraefte()
    for i, k in ipairs(knoten) do
        local r = math.rad(-(k.last_w or 0)); local c, s = math.cos(r), math.sin(r)
        k.Rx_glob, k.Ry_glob, k.Rm_glob = -(k.last_x*c - k.last_y*s), -(k.last_x*s + k.last_y*c), -k.last_m
    end
    for i, s in ipairs(staebe) do
        if not s.is_cut then
            local k1, k2 = knoten[s.k1], knoten[s.k2]; local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local c, s_val = dx/L, -dy/L
                k1.Rx_glob = k1.Rx_glob + s.s_local[1]*c + s.s_local[2]*s_val; k1.Ry_glob = k1.Ry_glob - s.s_local[1]*s_val + s.s_local[2]*c; k1.Rm_glob = k1.Rm_glob + s.s_local[3]
                k2.Rx_glob = k2.Rx_glob + s.s_local[4]*c + s.s_local[5]*s_val; k2.Ry_glob = k2.Ry_glob - s.s_local[4]*s_val + s.s_local[5]*c; k2.Rm_glob = k2.Rm_glob + s.s_local[6]
            end
        end
        if (s.x_nA or 0) ~= 0 then
            local k1, k2 = knoten[s.k1], knoten[s.k2]; local dx, dy = k2.x - k1.x, k2.y - k1.y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local ux, uy = dx/L, dy/L
                k1.Rx_glob = k1.Rx_glob - s.x_nA * ux; k1.Ry_glob = k1.Ry_glob - s.x_nA * uy
                k2.Rx_glob = k2.Rx_glob + s.x_nA * ux; k2.Ry_glob = k2.Ry_glob + s.x_nA * uy
            end
        end
    end
    for i, k in ipairs(knoten) do
        local r = math.rad(k.winkel or 0); local c, s = math.cos(r), math.sin(r)
        k.R_xi = k.Rx_glob*c - k.Ry_glob*s; k.R_eta = -(k.Rx_glob*s + k.Ry_glob*c); k.R_m = k.Rm_glob
        if math.abs(k.R_xi) < 1e-6 then k.R_xi = 0 end; if math.abs(k.R_eta) < 1e-6 then k.R_eta = 0 end; if math.abs(k.R_m) < 1e-6 then k.R_m = 0 end
    end
end

-- ========================================================
-- KGV-LOGIK
-- ========================================================
local function isUnloaded(stab_idx)
    local s = staebe[stab_idx]
    if (s.q or 0) ~= 0 or (s.q_A or 0) ~= 0 or (s.q_B or 0) ~= 0 then return false end
    if (s.n or 0) ~= 0 or (s.n_A or 0) ~= 0 or (s.n_B or 0) ~= 0 then return false end
    if (s.m or 0) ~= 0 then return false end
    if (s.gx or 0) ~= 0 or (s.gy or 0) ~= 0 then return false end
    if (s.To or 0) ~= 0 or (s.Tu or 0) ~= 0 then return false end
    if s.q_str and s.q_str:hasx() then return false end
    if s.n_str and s.n_str:hasx() then return false end
    if s.m_str and s.m_str:hasx() then return false end
    if s.gx_str and s.gx_str:hasx() then return false end
    if s.gy_str and s.gy_str:hasx() then return false end
    return true
end

local function isEffectiveHinge(stab_idx, end_node)
    local s = staebe[stab_idx]
    local k_idx = (end_node == "A") and s.k1 or s.k2
    local k = knoten[k_idx]
    if k.gelenk then return true end
    if end_node == "A" and s.gelenk_A then return true end
    if end_node == "B" and s.gelenk_B then return true end
    if k.lager_m then return false end
    
    local count_bars, count_hinges = 0, 0
    for _, bs in ipairs(staebe) do
        if bs.k1 == k_idx then
            count_bars = count_bars + 1
            if bs.gelenk_A then count_hinges = count_hinges + 1 end
        elseif bs.k2 == k_idx then
            count_bars = count_bars + 1
            if bs.gelenk_B then count_hinges = count_hinges + 1 end
        end
    end
    return (count_bars - count_hinges) <= 1
end

local function backupSystem()
    for i, k in ipairs(knoten) do k.orig_lager_x = k.lager_x; k.orig_lager_y = k.lager_y; k.orig_lager_m = k.lager_m; k.orig_last_x = k.last_x; k.orig_last_y = k.last_y; k.orig_last_m = k.last_m; k.orig_last_w = k.last_w end
    for i, s in ipairs(staebe) do 
        s.orig_gelenk_A=s.gelenk_A; s.orig_gelenk_B=s.gelenk_B; 
        s.orig_n_gelenk_A=s.n_gelenk_A;
        s.orig_q=s.q; s.orig_n=s.n; s.orig_m=s.m; 
        s.orig_q_A=s.q_A; s.orig_q_B=s.q_B; s.orig_n_A=s.n_A; s.orig_n_B=s.n_B; 
        s.orig_gx=s.gx; s.orig_gy=s.gy; s.orig_To=s.To; s.orig_Tu=s.Tu;
        s.orig_q_str = s.q_str; s.orig_n_str = s.n_str; s.orig_m_str = s.m_str;
        s.orig_gx_str = s.gx_str; s.orig_gy_str = s.gy_str;
        s.orig_q_A_str = s.q_A_str; s.orig_q_B_str = s.q_B_str; s.orig_n_A_str = s.n_A_str; s.orig_n_B_str = s.n_B_str;
        s.orig_is_cut = s.is_cut; s.orig_x_nA = s.x_nA
    end
end

applyKGVZustand = function(lf)
    if lf == -1 then
        for i, k in ipairs(knoten) do if k.orig_lager_x~=nil then k.lager_x=k.orig_lager_x; k.lager_y=k.orig_lager_y; k.lager_m=k.orig_lager_m; k.last_x=k.orig_last_x; k.last_y=k.orig_last_y; k.last_m=k.orig_last_m; k.last_w=k.orig_last_w end end
        for i, s in ipairs(staebe) do if s.orig_gelenk_A~=nil then s.gelenk_A=s.orig_gelenk_A; s.gelenk_B=s.orig_gelenk_B; s.n_gelenk_A=s.orig_n_gelenk_A; s.q=s.orig_q; s.n=s.orig_n; s.m=s.orig_m; s.q_A=s.orig_q_A; s.q_B=s.orig_q_B; s.n_A=s.orig_n_A; s.n_B=s.orig_n_B; s.gx=s.orig_gx; s.gy=s.orig_gy; s.To=s.orig_To; s.Tu=s.orig_Tu; s.x_mA=0; s.x_mB=0; s.q_str=s.orig_q_str; s.n_str=s.orig_n_str; s.m_str=s.orig_m_str; s.gx_str=s.orig_gx_str; s.gy_str=s.orig_gy_str; s.q_A_str=s.orig_q_A_str; s.q_B_str=s.orig_q_B_str; s.n_A_str=s.orig_n_A_str; s.n_B_str=s.orig_n_B_str; s.is_cut=s.orig_is_cut; s.x_nA=s.orig_x_nA end end
        updateAlleLasten()
        return
    end
    for i, k in ipairs(knoten) do k.lager_x = k.orig_lager_x; k.lager_y = k.orig_lager_y; k.lager_m = k.orig_lager_m end
    for i, s in ipairs(staebe) do s.gelenk_A = s.orig_gelenk_A; s.gelenk_B = s.orig_gelenk_B; s.n_gelenk_A = s.orig_n_gelenk_A; s.x_mA = 0; s.x_mB = 0; s.is_cut = s.orig_is_cut; s.x_nA = 0 end
    
    for _, x in ipairs(X_Werte) do
        if x.typ == "lager_x" then knoten[x.knoten].lager_x = false 
        elseif x.typ == "lager_y" then knoten[x.knoten].lager_y = false 
        elseif x.typ == "lager_m" then knoten[x.knoten].lager_m = false 
        elseif x.typ == "gelenk_A" then staebe[x.stab].gelenk_A = true 
        elseif x.typ == "gelenk_B" then staebe[x.stab].gelenk_B = true 
        elseif x.typ == "pendel_n" then 
            staebe[x.stab].is_cut = true
            staebe[x.stab].n_gelenk_A = true
        end
    end
    
    if lf == 0 then
        for i, k in ipairs(knoten) do k.last_x=k.orig_last_x; k.last_y=k.orig_last_y; k.last_m=k.orig_last_m; k.last_w=k.orig_last_w end
        for i, s in ipairs(staebe) do s.q=s.orig_q; s.n=s.orig_n; s.m=s.orig_m; s.q_A=s.orig_q_A; s.q_B=s.orig_q_B; s.n_A=s.orig_n_A; s.n_B=s.orig_n_B; s.gx=s.orig_gx; s.gy=s.orig_gy; s.To=s.orig_To; s.Tu=s.orig_Tu; s.q_str=s.orig_q_str; s.n_str=s.orig_n_str; s.m_str=s.orig_m_str; s.gx_str=s.orig_gx_str; s.gy_str=s.orig_gy_str; s.q_A_str=s.orig_q_A_str; s.q_B_str=s.orig_q_B_str; s.n_A_str=s.orig_n_A_str; s.n_B_str=s.orig_n_B_str end
    else
        for i, k in ipairs(knoten) do k.last_x=0; k.last_y=0; k.last_m=0; k.last_w=0 end
        for i, s in ipairs(staebe) do s.q=0; s.n=0; s.m=0; s.q_A=0; s.q_B=0; s.n_A=0; s.n_B=0; s.gx=0; s.gy=0; s.To=0; s.Tu=0; s.q_str="0"; s.n_str="0"; s.m_str="0"; s.gx_str="0"; s.gy_str="0"; s.q_A_str=nil; s.q_B_str=nil; s.n_A_str=nil; s.n_B_str=nil end
        local x = X_Werte[lf]; if x.typ == "lager_x" then local rad = math.rad(knoten[x.knoten].winkel or 0); knoten[x.knoten].last_x = math.cos(rad); knoten[x.knoten].last_y = -math.sin(rad) elseif x.typ == "lager_y" then local rad = math.rad(knoten[x.knoten].winkel or 0); knoten[x.knoten].last_x = math.sin(rad); knoten[x.knoten].last_y = math.cos(rad) elseif x.typ == "lager_m" then knoten[x.knoten].last_m = 1 elseif x.typ == "gelenk_A" then staebe[x.stab].x_mA = 1 elseif x.typ == "gelenk_B" then staebe[x.stab].x_mB = 1 elseif x.typ == "pendel_n" then staebe[x.stab].x_nA = 1 end
    end
    updateAlleLasten()
end

local function checkStabilitat() local ok, _ = berechneSystemGleichungen(true); return ok and true or false end

local function findeAutoHauptsystem()
    X_Werte = {}; if not checkStabilitat() then print("Kinematisch!"); return false end
    for i, k in ipairs(knoten) do if k.lager_m then k.lager_m=false; if checkStabilitat() then table.insert(X_Werte, {typ="lager_m", knoten=i}) else k.lager_m=true end end end
    for i, k in ipairs(knoten) do
        if k.lager_x then k.lager_x=false; if checkStabilitat() then table.insert(X_Werte, {typ="lager_x", knoten=i}) else k.lager_x=true end end
        if k.lager_y then k.lager_y=false; if checkStabilitat() then table.insert(X_Werte, {typ="lager_y", knoten=i}) else k.lager_y=true end end
    end
    for i, s in ipairs(staebe) do
        if not s.gelenk_A and not knoten[s.k1].gelenk then s.gelenk_A=true; if checkStabilitat() then table.insert(X_Werte, {typ="gelenk_A", stab=i}) else s.gelenk_A=false end end
        if not s.gelenk_B and not knoten[s.k2].gelenk then s.gelenk_B=true; if checkStabilitat() then table.insert(X_Werte, {typ="gelenk_B", stab=i}) else s.gelenk_B=false end end
    end
    for i, s in ipairs(staebe) do
        if isUnloaded(i) and isEffectiveHinge(i, "A") and isEffectiveHinge(i, "B") then
            s.is_cut = true
            s.n_gelenk_A = true
            if checkStabilitat() then 
                table.insert(X_Werte, {typ="pendel_n", stab=i}) 
            else 
                s.is_cut = false; s.n_gelenk_A = false 
            end
        end
    end
    kgv_n = #X_Werte
    for _, x in ipairs(X_Werte) do 
        if x.typ == "lager_m" then knoten[x.knoten].lager_m = true 
        elseif x.typ == "lager_x" then knoten[x.knoten].lager_x = true 
        elseif x.typ == "lager_y" then knoten[x.knoten].lager_y = true 
        elseif x.typ == "gelenk_A" then staebe[x.stab].gelenk_A = false 
        elseif x.typ == "gelenk_B" then staebe[x.stab].gelenk_B = false 
        elseif x.typ == "pendel_n" then staebe[x.stab].is_cut = false; staebe[x.stab].n_gelenk_A = false 
        end 
    end
end

-- Boegen fuer die Rechnung in gerade Teilstaebe zerlegen (Geometrie: bogenGeometrie). Die Teilstaebe
-- erben Steifigkeit, Gelenke an den Enden, Temperatur und die Lasten des Bogens (bogenTeilLasten): q quer
-- (radial), n laengs (tangential), Trapez linear ueber die Bogenlaenge, gx/gy global, m. Der Bogen selbst
-- bekommt keinen Lastvektor mehr (baueLastvektor), sonst zaehlte die Last doppelt bzw. auf der Sehne.
local function injectVirtualArcs()
    local orig_num_staebe = #staebe
    for i=1, orig_num_staebe do
        local s = staebe[i]
        local g = bogenGeometrie(s)
        s.bogen_last_fehler = nil
        if g then
            s.is_virtual_parent = true
            s.virt_start_stab = #staebe + 1
            s.virt_anzahl = g.n
            s.bogen_alpha = g.alpha
            local w = bogenLastWerte(s, g)
            local teile = bogenTeilLasten(s, g, w)
            for _, feld in ipairs({ "q", "n", "m", "gx", "gy" }) do
                if w.fehler[feld] then s.bogen_last_fehler = s.bogen_last_fehler or {}; table.insert(s.bogen_last_fehler, feld) end
            end
            local idx = { [0] = s.k1, [g.n] = s.k2 }
            for j = 1, g.n - 1 do
                table.insert(knoten, {x = g.pts[j].x, y = g.pts[j].y, gelenk=false, is_virtual = true,
                                      lager_x = false, lager_y = false, lager_m = false,
                                      last_x=0, last_y=0, last_m=0, last_w=0,
                                      cx=0, cy=0, cm=0, f_winkel=0})
                idx[j] = #knoten
            end
            for j = 1, g.n do
                local v_stab = erstelleStab(idx[j - 1], idx[j])
                v_stab.EA = s.EA; v_stab.EI = s.EI; v_stab.EA_str = s.EA_str; v_stab.EI_str = s.EI_str
                v_stab.biegesteif, v_stab.dehnsteif, v_stab.EA_manuell = s.biegesteif, s.dehnsteif, s.EA_manuell
                v_stab.is_virtual = true; v_stab.parent_idx = i
                v_stab.bogen_phi1, v_stab.bogen_phi2 = g.pts[j - 1].phi, g.pts[j].phi
                local t = teile[j]
                v_stab.q_A, v_stab.q_B, v_stab.n_A, v_stab.n_B, v_stab.m = t.qa, t.qb, t.na, t.nb, t.m
                v_stab.To, v_stab.Tu, v_stab.alpha, v_stab.h = s.To or 0, s.Tu or 0, s.alpha, s.h
                v_stab.To_str, v_stab.Tu_str, v_stab.alpha_str, v_stab.h_str = s.To_str, s.Tu_str, s.alpha_str, s.h_str
                if j == 1 then
                    v_stab.gelenk_A = s.gelenk_A
                    v_stab.n_gelenk_A = s.n_gelenk_A
                    v_stab.q_gelenk_A = s.q_gelenk_A
                end
                if j == g.n then
                    v_stab.gelenk_B = s.gelenk_B
                    v_stab.n_gelenk_B = s.n_gelenk_B
                    v_stab.q_gelenk_B = s.q_gelenk_B
                end
                table.insert(staebe, v_stab)
            end
        end
    end
end

local function cleanupVirtualArcs()
    for i, s in ipairs(staebe) do
        if s.is_virtual_parent then
            local anzahl = s.virt_anzahl or bogenSegmente
            local virt1 = staebe[s.virt_start_stab]
            local virt_last = staebe[s.virt_start_stab + (anzahl - 1)]
            if virt1 and virt1.s_local then
                s.arc_N_A = -virt1.s_local[1]
                s.arc_V_A = -virt1.s_local[2]
                s.arc_M_A = -virt1.s_local[3]
            end
            if virt1 and virt1.s_local and virt_last and virt_last.s_local then
                s.s_local = {
                    virt1.s_local[1], virt1.s_local[2], virt1.s_local[3],
                    virt_last.s_local[4], virt_last.s_local[5], virt_last.s_local[6]
                }
                s.v_local = {
                    virt1.v_local[1], virt1.v_local[2], virt1.v_local[3],
                    virt_last.v_local[4], virt_last.v_local[5], virt_last.v_local[6]
                }
            else
                s.s_local = {0,0,0,0,0,0}
                s.v_local = {0,0,0,0,0,0}
            end
            
            -- je Teilstueck Werte am Anfang (N, Q, M1) und am Ende (N2, Q2, M2): mit Last auf dem Bogen
            -- aendern sich N und Q auch innerhalb eines Teilstuecks; phi1/phi2 = Winkel ab Stabanfang (rad)
            s.arc_plot_data = {}
            for v = 0, anzahl - 1 do
                local virt = staebe[s.virt_start_stab + v]
                if virt and virt.s_local then
                    local k1 = knoten[virt.k1]
                    local k2 = knoten[virt.k2]
                    local dx1 = k1.mat_pv and k1.mat_pv[1][2] or 0
                    local dy1 = k1.mat_pv and k1.mat_pv[2][2] or 0
                    local dx2 = k2.mat_pv and k2.mat_pv[1][2] or 0
                    local dy2 = k2.mat_pv and k2.mat_pv[2][2] or 0
                    table.insert(s.arc_plot_data, {
                        x1 = k1.x, y1 = k1.y,
                        x2 = k2.x, y2 = k2.y,
                        disp_x1 = dx1, disp_y1 = dy1,
                        disp_x2 = dx2, disp_y2 = dy2,
                        N = -virt.s_local[1],
                        Q = -virt.s_local[2],
                        M1 = -virt.s_local[3],
                        N2 = virt.s_local[4],
                        Q2 = virt.s_local[5],
                        M2 = virt.s_local[6],
                        phi1 = virt.bogen_phi1, phi2 = virt.bogen_phi2,
                    })
                end
            end
            
            s.is_virtual_parent = nil
            s.virt_start_stab = nil
            s.virt_anzahl = nil
        end
    end
    for i = #staebe, 1, -1 do
        if staebe[i].is_virtual then table.remove(staebe, i) end
    end
    for i = #knoten, 1, -1 do
        if knoten[i].is_virtual then table.remove(knoten, i) end
    end
end

local findZeroForceMembers
function assignTeilsysteme()
    local uf_parent = {}
    local function uf_find(i)
        if uf_parent[i] == i then return i end
        uf_parent[i] = uf_find(uf_parent[i])
        return uf_parent[i]
    end
    local function uf_union(i, j)
        local root_i = uf_find(i)
        local root_j = uf_find(j)
        if root_i ~= root_j then
            if root_i < root_j then uf_parent[root_j] = root_i 
            else uf_parent[root_i] = root_j end
        end
    end
    for i = 1, #staebe do uf_parent[i] = i end
    for i, k in ipairs(knoten) do
        if not k.gelenk then
            local rigid_bars = {}
            for j, s in ipairs(staebe) do
                local is_rigid_at_node = false
                if s.k1 == i and not (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A) then is_rigid_at_node = true end
                if s.k2 == i and not (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B) then is_rigid_at_node = true end
                if is_rigid_at_node then table.insert(rigid_bars, j) end
            end
            for j = 2, #rigid_bars do uf_union(rigid_bars[1], rigid_bars[j]) end
        end
    end
    
    local root_mapping = {}
    glob_num_disks = 0
    glob_ts_scheibe = {}
    
    for i = 1, #staebe do
        local root = uf_find(i)
        if not root_mapping[root] then
            glob_num_disks = glob_num_disks + 1
            root_mapping[root] = glob_num_disks
        end
        staebe[i].ts_scheibe = root_mapping[root]
        glob_ts_scheibe[i] = root_mapping[root]
    end
    
    if glob_num_disks == 0 then glob_num_disks = 1 end
    
    glob_disk_centers = {}
    for d = 1, glob_num_disks do
        local cx_geom, cy_geom, count = 0, 0, 0
        local nodes_in_d = {}
        for j, s in ipairs(staebe) do
            if glob_ts_scheibe[j] == d then
                cx_geom = cx_geom + knoten[s.k1].x + knoten[s.k2].x
                cy_geom = cy_geom + knoten[s.k1].y + knoten[s.k2].y
                nodes_in_d[s.k1] = true
                nodes_in_d[s.k2] = true
                count = count + 2
            end
        end
        if count > 0 then cx_geom = cx_geom/count; cy_geom = cy_geom/count end
        
        local x_lines = {}
        local y_lines = {}
        local has_unknowns = false
        
        for n_idx, _ in pairs(nodes_in_d) do
            local k = knoten[n_idx]
            local is_inter_disk = false
            for j, s in ipairs(staebe) do
                if (s.k1 == n_idx or s.k2 == n_idx) and glob_ts_scheibe[j] and glob_ts_scheibe[j] ~= d then
                    is_inter_disk = true
                    break
                end
            end
            
            local has_H = k.lager_x or is_inter_disk
            local has_V = k.lager_y or is_inter_disk
            
            if has_H then
                y_lines[k.y] = (y_lines[k.y] or 0) + 1
                has_unknowns = true
            end
            if has_V then
                x_lines[k.x] = (x_lines[k.x] or 0) + 1
                has_unknowns = true
            end
        end
        
        if not has_unknowns then
            glob_disk_centers[d] = {x = cx_geom, y = cy_geom, node_id = nil}
        else
            local max_x_count, max_y_count = 0, 0
            for x, c in pairs(x_lines) do if c > max_x_count then max_x_count = c end end
            for y, c in pairs(y_lines) do if c > max_y_count then max_y_count = c end end
            
            local best_x_cands, best_y_cands = {}, {}
            for x, c in pairs(x_lines) do if c == max_x_count then best_x_cands[x] = true end end
            for y, c in pairs(y_lines) do if c == max_y_count then best_y_cands[y] = true end end
            
            local best_node, best_node_id = nil, nil
            for n_idx, _ in pairs(nodes_in_d) do
                local k = knoten[n_idx]
                if (max_x_count == 0 or best_x_cands[k.x]) and (max_y_count == 0 or best_y_cands[k.y]) then
                    best_node = k
                    best_node_id = n_idx
                    break
                end
            end
            
            if best_node then
                glob_disk_centers[d] = {x = best_node.x, y = best_node.y, node_id = best_node_id}
            else
                local bx = (max_x_count > 0) and next(best_x_cands) or cx_geom
                local by = (max_y_count > 0) and next(best_y_cands) or cy_geom
                glob_disk_centers[d] = {x = bx, y = by, node_id = nil}
            end
        end
    end
end

rechneAktuellesSystem = function()
    if #knoten == 0 then return end
    assignTeilsysteme()
    
    local useCache = (autoKGV and KGV_Zustand and KGV_Zustand > 0)
    if not useCache then cached_factored_K = nil end
    
    if not useCache and not checkStabilitat() then 
        warnungKinematisch = true
        platform.window:invalidate()
        return 
    end
    warnungKinematisch = false
    
    injectVirtualArcs()
    local u, _ = berechneSystemGleichungen(false, useCache)
    if not u then 
        cleanupVirtualArcs()
        warnungKinematisch = true
        platform.window:invalidate()
        return 
    end
    berechneAlleSchnittgroessen(u)
    berechneAuflagerkraefte()
    cleanupVirtualArcs()
    
    warnungStarrBestimmt = false
    local n_top = getTopologicalN()
    if n_top ~= 0 then
        local all_rigid = starrModus
        if not all_rigid then
            all_rigid = true
            for _, s in ipairs(staebe) do
                if stabEA(s) < 1e7 or stabEI(s) < 1e7 then
                    all_rigid = false
                    break
                end
            end
        end
        if all_rigid then warnungStarrBestimmt = true end
    end
    
    buildPolplan()
    if fachwerkModus then findZeroForceMembers() else for _, s in ipairs(staebe) do s.is_zero_force = false end end
end

local function runSymbolicSuperposition()
    if not symbolischer_modus then return end
    
    local backup_loads = { knoten = {}, staebe = {} }
    for i, k in ipairs(knoten) do
        backup_loads.knoten[i] = { last_x = k.last_x, last_y = k.last_y, last_m = k.last_m }
        k.last_x, k.last_y, k.last_m = 0, 0, 0
    end
    for i, s in ipairs(staebe) do
        backup_loads.staebe[i] = { q = s.q, n = s.n, m = s.m, q_A = s.q_A, q_B = s.q_B, n_A = s.n_A, n_B = s.n_B, gx = s.gx, gy = s.gy, To = s.To, Tu = s.Tu }
        s.q, s.n, s.m = 0, 0, 0
        s.q_A, s.q_B, s.n_A, s.n_B = 0, 0, 0, 0
        s.gx, s.gy, s.To, s.Tu = 0, 0, 0, 0
    end

    local L_sym, L_dummy = symbLSym, symbLDummy

    for _, s in ipairs(staebe) do
        s.symb_start = {N = "0", V = "0", M = "0", c1 = "0", c2 = "0", vb = "0", phib = "0"}
        s.symb_u_start, s.symb_u_end = "0", "0"
    end

    -- Zahlenwert eines Superpositionsfaktors als Text. smartToFracStr liefert einen exakten Bruch,
    -- sonst (Zahlenformat 1) die Wurzel eines Bruchs -- z. B. sqrt(1/2) bei 45-Grad-Fachwerkstaeben --
    -- und sonst eine Dezimalzahl. Frueher wurde hier ein Naeherungsbruch mit Toleranz 1e-5 gebildet,
    -- das ergab Beschriftungen wie 169/239 statt sqrt(1/2) und ignorierte das eingestellte Format.
    local function numToSymFrac(val)
        if math.abs(val) < 1e-10 then return "0" end
        return "(" .. smartToFracStr(val, 10 ^ (-(casToleranz or 5))) .. ")"
    end

    local function runSuperposIter(input_str, input_dummy, input_type)
        if not input_str or input_str == "" or input_str == "0" then return end
        
        local u, _ = berechneSystemGleichungen(false, true)
        if not u then return end
        berechneAlleSchnittgroessen(u)
        
        for _, s in ipairs(staebe) do
            local N_out, V_out, M_out = s.s_local[1], s.s_local[2], s.s_local[3]
            if math.abs(N_out) < 1e-6 then N_out = 0 end
            if math.abs(V_out) < 1e-6 then V_out = 0 end
            if math.abs(M_out) < 1e-6 then M_out = 0 end
            
            if N_out ~= 0 or V_out ~= 0 or M_out ~= 0 then
                local cn, cv, cm = 0, 0, 0
                if input_type == "Force" then
                    cn = N_out / input_dummy; cv = V_out / input_dummy; cm = M_out / (input_dummy * L_dummy)
                    if math.abs(cn) < 1e-6 then cn = 0 end; if math.abs(cv) < 1e-6 then cv = 0 end; if math.abs(cm) < 1e-6 then cm = 0 end
                    s.symb_start.N = s.symb_start.N .. string.format(" + %s*(%s)", numToSymFrac(cn), input_str)
                    s.symb_start.V = s.symb_start.V .. string.format(" + %s*(%s)", numToSymFrac(cv), input_str)
                    s.symb_start.M = s.symb_start.M .. string.format(" + %s*(%s)*(%s)", numToSymFrac(cm), input_str, L_sym)
                elseif input_type == "Moment" then
                    cn = N_out / (input_dummy / L_dummy); cv = V_out / (input_dummy / L_dummy); cm = M_out / input_dummy
                    if math.abs(cn) < 1e-6 then cn = 0 end; if math.abs(cv) < 1e-6 then cv = 0 end; if math.abs(cm) < 1e-6 then cm = 0 end
                    s.symb_start.N = s.symb_start.N .. string.format(" + %s*(%s)/(%s)", numToSymFrac(cn), input_str, L_sym)
                    s.symb_start.V = s.symb_start.V .. string.format(" + %s*(%s)/(%s)", numToSymFrac(cv), input_str, L_sym)
                    s.symb_start.M = s.symb_start.M .. string.format(" + %s*(%s)", numToSymFrac(cm), input_str)
                elseif input_type == "DistLoad" then
                    cn = N_out / (input_dummy * L_dummy); cv = V_out / (input_dummy * L_dummy); cm = M_out / (input_dummy * L_dummy^2)
                    if math.abs(cn) < 1e-6 then cn = 0 end; if math.abs(cv) < 1e-6 then cv = 0 end; if math.abs(cm) < 1e-6 then cm = 0 end
                    s.symb_start.N = s.symb_start.N .. string.format(" + %s*(%s)*(%s)", numToSymFrac(cn), input_str, L_sym)
                    s.symb_start.V = s.symb_start.V .. string.format(" + %s*(%s)*(%s)", numToSymFrac(cv), input_str, L_sym)
                    s.symb_start.M = s.symb_start.M .. string.format(" + %s*(%s)*(%s)^2", numToSymFrac(cm), input_str, L_sym)
                elseif input_type == "DistMoment" then
                    cn = N_out / input_dummy; cv = V_out / input_dummy; cm = M_out / (input_dummy * L_dummy)
                    if math.abs(cn) < 1e-6 then cn = 0 end; if math.abs(cv) < 1e-6 then cv = 0 end; if math.abs(cm) < 1e-6 then cm = 0 end
                    s.symb_start.N = s.symb_start.N .. string.format(" + %s*(%s)", numToSymFrac(cn), input_str)
                    s.symb_start.V = s.symb_start.V .. string.format(" + %s*(%s)", numToSymFrac(cv), input_str)
                    s.symb_start.M = s.symb_start.M .. string.format(" + %s*(%s)*(%s)", numToSymFrac(cm), input_str, L_sym)
                end
            end
            
            -- Displacements (for Biegelinien w(x))
            local pow_v, pow_phi = 3, 2
            if input_type == "Moment" or input_type == "DistMoment" then pow_v, pow_phi = 2, 1 elseif input_type == "DistLoad" then pow_v, pow_phi = 4, 3 end
            
            local EI_s = stabEI(s)
            local c1_out = s.v_local[2] * EI_s; local c2_out = -s.v_local[3] * EI_s
            local vb_out = s.v_local[5] * EI_s; local phib_out = -s.v_local[6] * EI_s
            
            if math.abs(c1_out) > 1e-6 then s.symb_start.c1 = s.symb_start.c1 .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(c1_out / (input_dummy * L_dummy^pow_v)), input_str, L_sym, pow_v) end
            if math.abs(c2_out) > 1e-6 then s.symb_start.c2 = s.symb_start.c2 .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(c2_out / (input_dummy * L_dummy^pow_phi)), input_str, L_sym, pow_phi) end
            if math.abs(vb_out) > 1e-6 then s.symb_start.vb = s.symb_start.vb .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(vb_out / (input_dummy * L_dummy^pow_v)), input_str, L_sym, pow_v) end
            if math.abs(phib_out) > 1e-6 then s.symb_start.phib = s.symb_start.phib .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(phib_out / (input_dummy * L_dummy^pow_phi)), input_str, L_sym, pow_phi) end

            local u_a, u_b = s.v_local[1] or 0, s.v_local[4] or 0
            if math.abs(u_a) > 1e-6 or math.abs(u_b) > 1e-6 then
                local power = (input_type == "DistLoad") and 4 or ((input_type == "Force") and 3 or 2)
                -- Stab mit Zahl als EI bekommt die Zahl, nicht das Symbol (Mischung aus Zahl und Symbol)
                local stiffness = (sym_vars.EI and not neuIstZahlText(s.EI_str) and "EI") or fN_export(s.EI or 1)
                local scale = input_dummy * L_dummy^power
                s.symb_u_start = s.symb_u_start .. string.format(" + %s*(%s)*(%s)^%d/(%s)", numToSymFrac(u_a / scale), input_str, L_sym, power, stiffness)
                s.symb_u_end = s.symb_u_end .. string.format(" + %s*(%s)*(%s)^%d/(%s)", numToSymFrac(u_b / scale), input_str, L_sym, power, stiffness)
            end
        end
    end

    for i, k in ipairs(knoten) do
        local orig = backup_loads.knoten[i]
        if orig.last_x ~= 0 then k.last_x = orig.last_x; runSuperposIter(k.last_x_str or tostring(orig.last_x), orig.last_x, "Force"); k.last_x = 0 end
        if orig.last_y ~= 0 then k.last_y = orig.last_y; runSuperposIter(k.last_y_str or tostring(orig.last_y), orig.last_y, "Force"); k.last_y = 0 end
        if orig.last_m ~= 0 then k.last_m = orig.last_m; runSuperposIter(k.last_m_str or tostring(orig.last_m), orig.last_m, "Moment"); k.last_m = 0 end
    end
    
    for i, s in ipairs(staebe) do
        local orig = backup_loads.staebe[i]
        if orig.q ~= 0 then s.q = orig.q; runSuperposIter(s.q_str or tostring(orig.q), orig.q, "DistLoad"); s.q = 0 end
        if orig.q_A ~= 0 then s.q_A = orig.q_A; runSuperposIter(s.q_A_str or tostring(orig.q_A), orig.q_A, "DistLoad"); s.q_A = 0 end
        if orig.q_B ~= 0 then s.q_B = orig.q_B; runSuperposIter(s.q_B_str or tostring(orig.q_B), orig.q_B, "DistLoad"); s.q_B = 0 end
        if orig.n ~= 0 then s.n = orig.n; runSuperposIter(s.n_str or tostring(orig.n), orig.n, "DistLoad"); s.n = 0 end
        if orig.n_A ~= 0 then s.n_A = orig.n_A; runSuperposIter(s.n_A_str or tostring(orig.n_A), orig.n_A, "DistLoad"); s.n_A = 0 end
        if orig.n_B ~= 0 then s.n_B = orig.n_B; runSuperposIter(s.n_B_str or tostring(orig.n_B), orig.n_B, "DistLoad"); s.n_B = 0 end
        if orig.m ~= 0 then s.m = orig.m; runSuperposIter(s.m_str or tostring(orig.m), orig.m, "DistMoment"); s.m = 0 end
        if orig.gx ~= 0 then s.gx = orig.gx; runSuperposIter(s.gx_str or tostring(orig.gx), orig.gx, "DistLoad"); s.gx = 0 end
        if orig.gy ~= 0 then s.gy = orig.gy; runSuperposIter(s.gy_str or tostring(orig.gy), orig.gy, "DistLoad"); s.gy = 0 end
    end

    for i, k in ipairs(knoten) do k.last_x, k.last_y, k.last_m = backup_loads.knoten[i].last_x, backup_loads.knoten[i].last_y, backup_loads.knoten[i].last_m end
    for i, s in ipairs(staebe) do
        local orig = backup_loads.staebe[i]
        s.q, s.n, s.m = orig.q, orig.n, orig.m
        s.q_A, s.q_B, s.n_A, s.n_B = orig.q_A, orig.q_B, orig.n_A, orig.n_B
        s.gx, s.gy, s.To, s.Tu = orig.gx, orig.gy, orig.To, orig.Tu
    end
end

-- Symbole (Bezeichner ausser Funktionsnamen) eines Eingabetextes in die Menge set eintragen
local function symboleIn(text, set)
    if type(text) ~= "string" or tonumber((text:gsub(",", "."))) then return set end
    for word in text:gmatch("%a[%w_]*") do
        if not math_funcs[word] then set[word] = true end
    end
    return set
end

-- Grenzen des symbolischen Modus pruefen. Liefert eine Fehlermeldung oder nil.
local function pruefeSymbolischenModus(geo_list)
    if #geo_list > 1 then
        return "Nur ein Laengensymbol erlaubt: " .. table.concat(geo_list, ", ")
    end
    if #geo_list == 1 and math.eval then
        -- Jede Koordinate muss ein reines Vielfaches des Symbols sein (0, l, 2*l, 3/2*l ...)
        local var = geo_list[1]
        local d = sym_vars[var] or 1
        for i, k in ipairs(knoten) do
            for _, c in ipairs({ { k.x_str, k.x }, { k.y_str, k.y } }) do
                local text, value = c[1], c[2] or 0
                local doppelt = value
                if type(text) == "string" and not tonumber((text:gsub(",", "."))) then
                    local probe = text:gsub("%f[%w_]" .. var .. "%f[^%w_]", "(" .. (2 * d) .. ")")
                    local ok, res = pcall(math.eval, "approx(" .. probe .. ")")
                    doppelt = ok and casToNumber(res) or nil
                end
                if not doppelt or math.abs(doppelt - 2 * value) > 1e-9 * math.max(1, math.abs(value)) then
                    return "Knoten " .. i .. ": Koordinate kein Vielfaches von " .. var
                end
            end
        end
    end
    for name in pairs(sym_vars) do
        if name:lower() == "t" then return "Symbol t ist reserviert (Integrationsvariable)" end
    end
    -- Mischung aus symbolischer und numerischer Steifigkeit ist kein Fehler mehr: es wird gerechnet
    -- und exportiert. sammleHinweise warnt nur, wenn der Zahlenwert das Ergebnis wirklich beeinflusst.
    for i, s in ipairs(staebe) do
        for _, f in ipairs({ s.To_str, s.Tu_str, s.alpha_str, s.h_str }) do
            if type(f) == "string" and f:hasx() then
                return "Stab " .. i .. ": Temperatur als Funktion von x nicht moeglich"
            end
        end
        for _, f in ipairs({ s.q_str, s.n_str, s.m_str, s.gx_str, s.gy_str }) do
            if type(f) == "string" and f:hasx() then
                return "Stab " .. i .. ": Lastfunktion f(x) nicht symbolisch moeglich"
            end
        end
        if (s.bogen_r or 0) ~= 0 then
            return "Stab " .. i .. ": Boegen nicht symbolisch moeglich"
        end
    end
    return nil
end

local function checkSymbolischerModus()
    symbolischer_modus = false
    sym_vars = {}
    symbolFehler = nil
    local function checkStr(str)
        if not str then return nil end
        local val, _ = evalInput(str, true)
        return val
    end
    local rm = checkStr(rasterMass_str); if rm then rasterMass = rm end
    -- Referenzlaenge: Symbol aus der Geometrie, sonst gilt ein Rasterabstand als l.
    -- l wird vorab mit dem Rastermass belegt, damit Lasten wie q*l denselben Zahlenwert nutzen.
    local geo = {}
    for _, k in ipairs(knoten) do symboleIn(k.x_str, geo); symboleIn(k.y_str, geo) end
    local geo_list = {}
    for name in pairs(geo) do geo_list[#geo_list + 1] = name end
    table.sort(geo_list)
    if #geo_list == 0 then sym_vars.l = rasterMass end
    for _, k in ipairs(knoten) do
        local vx = checkStr(k.x_str); if vx then k.x = vx end
        local vy = checkStr(k.y_str); if vy then k.y = vy end
        local vlx = checkStr(k.last_x_str); if vlx then k.last_x = vlx end
        local vly = checkStr(k.last_y_str); if vly then k.last_y = vly end
        local vlm = checkStr(k.last_m_str); if vlm then k.last_m = vlm end
        local vcx = checkStr(k.cx_str); if vcx then k.cx = vcx end
        local vcy = checkStr(k.cy_str); if vcy then k.cy = vcy end
        local vcm = checkStr(k.cm_str); if vcm then k.cm = vcm end
    end
    for _, s in ipairs(staebe) do
        local vq = checkStr(s.q_str); if vq then s.q = vq end
        local vqa = checkStr(s.q_A_str); if vqa then s.q_A = vqa end
        local vqb = checkStr(s.q_B_str); if vqb then s.q_B = vqb end
        local vn = checkStr(s.n_str); if vn then s.n = vn end
        local vna = checkStr(s.n_A_str); if vna then s.n_A = vna end
        local vnb = checkStr(s.n_B_str); if vnb then s.n_B = vnb end
        local vm = checkStr(s.m_str); if vm then s.m = vm end
        local ve = checkStr(s.EA_str); if ve then s.EA = ve end
        local vi = checkStr(s.EI_str); if vi then s.EI = vi end
        local vgx = checkStr(s.gx_str); if vgx then s.gx = vgx end
        local vgy = checkStr(s.gy_str); if vgy then s.gy = vgy end
        local vto = checkStr(s.To_str); if vto then s.To = vto end
        local vtu = checkStr(s.Tu_str); if vtu then s.Tu = vtu end
        local val = checkStr(s.alpha_str); if val then s.alpha = val end
        local vh = checkStr(s.h_str); if vh then s.h = vh end
    end
    if #geo_list == 0 then
        symbLSym, symbLDummy = "l", rasterMass
    else
        symbLSym, symbLDummy = geo_list[1], sym_vars[geo_list[1]] or 1.0
    end
    if symbolischer_modus then symbolFehler = pruefeSymbolischenModus(geo_list) end
    symbolFehlerOffen = symbolFehler ~= nil
end

-- Hinweise nach der Berechnung (keine Fehler, das Ergebnis ist gueltig):
--  * Temperatur mit To ~= Tu, aber h = 0: nur die mittlere Erwaermung wirkt
--  * Temperatur im symbolischen Modus: Diagrammbeschriftungen ohne Temperaturanteil
--  * symbolischer Modus: Zahl-EI bzw. Zahl-EA neben symbolischen Steifigkeiten (Ergebnis mischt Zahl
--    und Symbol), nur fuer Staebe, bei denen die Groesse laut FEM tatsaechlich beansprucht wird
-- Fingerabdruck aller Eingaben (Knoten, Staebe, Schalter). Nur Eingabefelder, keine Rechenergebnisse,
-- damit Zeichnen oder erneutes Rechnen ohne Aenderung den Abdruck nicht veraendert.
local KNOTEN_EINGABEN = { "x", "y", "x_str", "y_str", "gelenk", "lager_x", "lager_y", "lager_m", "winkel",
    "cx", "cy", "cm", "cx_str", "cy_str", "cm_str", "f_winkel",
    "last_x", "last_y", "last_m", "last_w", "last_x_str", "last_y_str", "last_m_str", "last_w_str" }
local STAB_EINGABEN = { "k1", "k2", "EA", "EI", "EA_str", "EI_str", "biegesteif", "dehnsteif", "EA_manuell",
    "bogen_r", "bogen_r_str", "q", "q_str", "n", "n_str", "m", "m_str", "q_A", "q_B", "n_A", "n_B",
    "q_A_str", "q_B_str", "n_A_str", "n_B_str", "gx", "gy", "gx_str", "gy_str", "gx_proj", "gy_proj",
    "To", "Tu", "alpha", "h", "To_str", "Tu_str", "alpha_str", "h_str",
    "gelenk_A", "gelenk_B", "n_gelenk_A", "n_gelenk_B", "q_gelenk_A", "q_gelenk_B", "x_mA", "x_mB" }
local function systemFingerabdruck()
    local teile = { tostring(randDehnstarr), tostring(rasterMass), tostring(fachwerkModus), tostring(#knoten), tostring(#staebe) }
    local function felder(t, namen)
        local p = {}
        for i, k in ipairs(namen) do
            local v = t[k]
            p[i] = (type(v) == "number") and string.format("%.12g", v) or tostring(v)
        end
        return table.concat(p, ",")
    end
    for _, k in ipairs(knoten) do teile[#teile + 1] = "K" .. felder(k, KNOTEN_EINGABEN) end
    for _, st in ipairs(staebe) do
        if not st.is_virtual then teile[#teile + 1] = "S" .. felder(st, STAB_EINGABEN) end
    end
    return table.concat(teile, ";")
end

-- Schluessel des Rand-LGS-Speichers (randErgebnis): der Fingerabdruck aller Eingaben (mit Knoten- und
-- Stabnummern) und alles, was das Rand-LGS sonst beeinflusst. Gleicher Schluessel = gleiches System,
-- auch wenn es zwischendurch geloescht und identisch neu gezeichnet oder geoeffnet wurde.
function randLGSCacheSchluessel()
    return table.concat({ systemFingerabdruck(), tostring(randStarrDirekt),
        tostring(symbolischer_modus), tostring(symbLSym), tostring(symbLDummy), tostring(KGV_Zustand),
        tostring(zahlenFormat), tostring(casToleranz) }, "#")
end

-- =====================================================================
-- SYSTEME SPEICHERN UND OEFFNEN (Obermenue Seite 4)
-- Alle Eingaben (Knoten, Staebe, Einstellungen) als ein String in der TI-Variable system<Nr>:
--   "TWS1;G:feld=wert,...;K:feld=wert,...;S:feld=wert,..."
-- Werte: #Zahl, 'Text (% ; , = : " und Zeilenumbruch als %XX), T/F (Wahrheitswert), ~ (nil).
-- Knoten und Staebe enthalten nur Felder, die vom Standard eines neuen Knotens bzw. Stabes abweichen;
-- beim Oeffnen werden deshalb zuerst die Einstellungen (defEA, defEI ...) gesetzt.
-- =====================================================================
SYSTEM_GLOBALE = { "rasterMass", "rasterMass_str", "defEA", "defEA_str", "defEI", "defEI_str",
    "randDehnstarr", "randStarrDirekt", "fachwerkModus", "pxProMeter", "offsetX", "offsetY" }

function systemWertText(v)
    if v == nil then return "~" end
    if type(v) == "boolean" then return v and "T" or "F" end
    if type(v) == "number" then
        local t = string.format("%.15g", v)
        if tonumber(t) ~= v then t = string.format("%.17g", v) end
        return "#" .. t
    end
    return "'" .. (tostring(v):gsub("[%%;,=:\"\n]", function(c) return string.format("%%%02X", c:byte()) end))
end

function systemTextWert(t)
    local c = t:sub(1, 1)
    if t == "T" then return true elseif t == "F" then return false end
    if c == "#" then return tonumber(t:sub(2)) end
    if c == "'" then return (t:sub(2):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
    return nil
end

-- aktuelles System als Text; Rueckgabe Text, Anzahl Knoten, Anzahl Staebe
function systemAlsText()
    local function felder(obj, namen, standard)
        local p = {}
        for _, n in ipairs(namen) do
            if obj[n] ~= standard[n] then p[#p + 1] = n .. "=" .. systemWertText(obj[n]) end
        end
        return table.concat(p, ",")
    end
    local g = {}
    for _, n in ipairs(SYSTEM_GLOBALE) do g[#g + 1] = n .. "=" .. systemWertText(_G[n]) end
    local teile = { "TWS1", "G:" .. table.concat(g, ",") }
    -- virtuelle Knoten und Staebe (Bogensegmente) gibt es nur waehrend der Rechnung
    local neu, nK, nS = {}, 0, 0
    local kStd = erstelleKnoten(0, 0)
    for i, k in ipairs(knoten) do
        if not k.is_virtual then
            nK = nK + 1; neu[i] = nK
            teile[#teile + 1] = "K:" .. felder(k, KNOTEN_EINGABEN, kStd)
        end
    end
    local sStd = erstelleStab(0, 0)
    for _, st in ipairs(staebe) do
        if not st.is_virtual and neu[st.k1] and neu[st.k2] then
            local kopie = {}
            for _, n in ipairs(STAB_EINGABEN) do kopie[n] = st[n] end
            kopie.k1, kopie.k2 = neu[st.k1], neu[st.k2]
            nS = nS + 1
            teile[#teile + 1] = "S:" .. felder(kopie, STAB_EINGABEN, sStd)
        end
    end
    return table.concat(teile, ";"), nK, nS
end

-- Text -> { G = {{name, wert}...}, K = {...}, S = {...} }; nil und Fehlertext, wenn es kein System ist
function systemAusText(text)
    if type(text) ~= "string" or text:sub(1, 5) ~= "TWS1;" then return nil, "keine gespeicherte Tragwerksdatei" end
    local daten = { G = {}, K = {}, S = {} }
    for teil in (text:sub(6) .. ";"):gmatch("(.-);") do
        local typ, rest = teil:match("^(%a):(.*)$")
        if typ then
            local felder = {}
            for paar in (rest .. ","):gmatch("(.-),") do
                local n, w = paar:match("^([%w_]+)=(.*)$")
                if n then felder[#felder + 1] = { n, systemTextWert(w) } end
            end
            if typ == "G" then daten.G = felder
            elseif typ == "K" then daten.K[#daten.K + 1] = felder
            elseif typ == "S" then daten.S[#daten.S + 1] = felder end
        end
    end
    return daten
end

function speichereSystem(nr)
    local name = "system" .. tostring(nr)
    if #knoten == 0 then zeigeMeldung("Kein System vorhanden.", "System speichern"); return false end
    if not (var and var.store) then zeigeMeldung("Speichern nicht moeglich.", "System speichern"); return false end
    local text, nK, nS = systemAlsText()
    local ok, res = pcall(var.store, name, text)
    if ok and var.recall then
        local ok2, zurueck = pcall(var.recall, name)
        ok = ok2 and zurueck == text
    elseif ok then
        ok = (res == nil)
    end
    if not ok then zeigeMeldung(name .. " konnte nicht gespeichert werden.", "System speichern"); return false end
    letzteSystemNr = nr
    zeigeMeldung("System als " .. name .. " gespeichert: " .. nK .. " Knoten, " .. nS .. " Staebe.", "System speichern")
    return true
end

function oeffneSystem(nr)
    local name = "system" .. tostring(nr)
    local text
    if var and var.recall then
        local ok, v = pcall(var.recall, name)
        if ok then text = v end
    end
    if text == nil then zeigeMeldung(name .. " ist nicht vorhanden.", "System oeffnen"); return false end
    local daten, fehler = systemAusText(text)
    if not daten then zeigeMeldung(name .. ": " .. fehler, "System oeffnen"); return false end
    local function erlaubt(liste)
        local m = {}
        for _, n in ipairs(liste) do m[n] = true end
        return m
    end
    local okG, okK, okS = erlaubt(SYSTEM_GLOBALE), erlaubt(KNOTEN_EINGABEN), erlaubt(STAB_EINGABEN)
    loescheAlles()
    -- zuerst die Einstellungen: der Standard neuer Staebe (EA, EI) haengt davon ab
    for _, f in ipairs(daten.G) do if okG[f[1]] then _G[f[1]] = f[2] end end
    local neuK, neuS = {}, {}
    for _, felder in ipairs(daten.K) do
        local k = erstelleKnoten(0, 0)
        for _, f in ipairs(felder) do if okK[f[1]] then k[f[1]] = f[2] end end
        if type(k.x) == "number" and type(k.y) == "number" then neuK[#neuK + 1] = k end
    end
    for _, felder in ipairs(daten.S) do
        local st = erstelleStab(0, 0)
        for _, f in ipairs(felder) do if okS[f[1]] then st[f[1]] = f[2] end end
        if neuK[st.k1] and neuK[st.k2] and st.k1 ~= st.k2 then neuS[#neuS + 1] = st end
    end
    knoten, staebe = neuK, neuS
    auswahl = nil
    letzteSystemNr = nr
    updateAlleLasten()
    systemBerechnet = false
    zeigeMeldung(name .. " geoeffnet: " .. #neuK .. " Knoten, " .. #neuS .. " Staebe.", "System oeffnen")
    platform.window:invalidate()
    return true
end

local function sammleHinweise()
    local liste = {}
    local tempStaebe, ohneH = false, {}
    for i, s in ipairs(staebe) do
        local To, Tu = s.To_str or tostring(s.To or 0), s.Tu_str or tostring(s.Tu or 0)
        if (To ~= "" and To ~= "0") or (Tu ~= "" and Tu ~= "0") then
            tempStaebe = true
            local hNull = (s.h or 0) == 0 and (not s.h_str or s.h_str == "" or s.h_str == "0")
            if hNull and To ~= Tu then ohneH[#ohneH + 1] = tostring(i) end
        end
    end
    if #ohneH > 0 then
        liste[#liste + 1] = "Stab " .. table.concat(ohneH, ", ") .. ": To und Tu verschieden, aber h = 0. Es wirkt nur die mittlere Erwaermung (To+Tu)/2, keine Kruemmung. Fuer die Kruemmung h eingeben."
    end
    -- Bogen: Lastfunktion, die das CAS beim Winkel x nicht auswerten konnte (injectVirtualArcs)
    for i, s in ipairs(staebe) do
        if s.bogen_last_fehler then
            local namen = { q = "q", n = "n", m = "m", gx = "p_X", gy = "p_Y" }
            local felder = {}
            for _, f in ipairs(s.bogen_last_fehler) do felder[#felder + 1] = namen[f] or f end
            liste[#liste + 1] = "Stab " .. i .. " (Bogen): Lastfunktion " .. table.concat(felder, ", ") .. " nicht auswertbar (x = Winkel ab Stabanfang im Winkelmodus). Dort mit 0 gerechnet."
        end
    end
    -- nur wenn die angenommene Aufteilung das Ergebnis auch beeinflusst (relevant, siehe loeseMitZwang)
    if glob_zwang_info and glob_zwang_info.unbestimmt > 0 and glob_zwang_info.relevant ~= false and not warnungKinematisch then
        liste[#liste + 1] = "Starre Staebe halten sich gegenseitig statisch unbestimmt: Das Gleichgewicht legt die Kraftaufteilung zwischen ihnen nicht fest. Gerechnet wird wie im Rand-LGS so, als waeren alle starren Staebe gleich steif (EA = EI)."
    end
    if glob_zwang_info and glob_zwang_info.widerspruch and not warnungKinematisch then
        liste[#liste + 1] = "Temperatur in starren Staeben, die sich gegenseitig halten: Die behinderte Verformung erzeugt eine unendliche Zwangskraft. Verformungen gelten, die Kraefte in den starren Staeben nicht."
    end
    if symbolischer_modus and tempStaebe then
        liste[#liste + 1] = "Temperatur symbolisch: Diagrammwerte ohne Temperaturanteil. Vollstaendig im Export (wneu, uneu, wv, uv)."
    end
    if symbolischer_modus and not warnungKinematisch then
        -- gibt es ueberhaupt symbolische Steifigkeiten (Stab-EI/EA, Federn oder EI/EA in einem Lasttext)?
        local symbolisch = false
        for _, s in ipairs(staebe) do
            if (not stabBiegesteif(s) and not neuIstZahlText(s.EI_str)) or (not stabDehnsteif(s) and not neuIstZahlText(s.EA_str)) then symbolisch = true end
        end
        for _, k in ipairs(knoten) do
            -- feste Schleife statt ipairs: ipairs bricht beim ersten leeren Feld (nil) ab
            local felder = { k.cx_str, k.cy_str, k.cm_str }
            for j = 1, 3 do
                local t = felder[j]
                if type(t) == "string" and t ~= "" and not neuIstZahlText(t) then symbolisch = true end
            end
        end
        for name in pairs(sym_vars) do
            local low = name:lower()
            if low == "ei" or low == "ea" then symbolisch = true end
        end
        if symbolisch then
            local maxK = 0
            for _, s in ipairs(staebe) do
                if s.s_local then for j = 1, 6 do maxK = math.max(maxK, math.abs(s.s_local[j] or 0)) end end
            end
            local tol = 1e-9 * maxK
            -- Gemischt ist das Ergebnis nur, wenn auf beiden Seiten eine Steifigkeit wirklich mitwirkt.
            -- Ein Stab ohne Biegung haengt nicht von seinem EI ab, einer ohne Normalkraft nicht von seinem
            -- EA: Die Loesung erfuellt dann jedes EI bzw. EA. Das gilt fuer Zahlen wie fuer Symbole.
            local eiListe, eaListe, symAktiv = {}, {}, false
            for i, s in ipairs(staebe) do
                local sl = s.s_local
                if sl and maxK > 0 and not s.is_cut and not s.is_virtual_parent then
                    local pendel = (s.gelenk_A or knoten[s.k1].gelenk) and (s.gelenk_B or knoten[s.k2].gelenk)
                    local biegung = not pendel and math.max(math.abs(sl[2] or 0), math.abs(sl[3] or 0), math.abs(sl[5] or 0), math.abs(sl[6] or 0)) > tol
                    local normal = math.max(math.abs(sl[1] or 0), math.abs(sl[4] or 0)) > tol
                    if not stabBiegesteif(s) and biegung then
                        if neuIstZahlText(s.EI_str) then eiListe[#eiListe + 1] = tostring(i) else symAktiv = true end
                    end
                    if not stabDehnsteif(s) and normal then
                        if neuIstZahlText(s.EA_str) then eaListe[#eaListe + 1] = tostring(i) else symAktiv = true end
                    end
                end
            end
            -- symbolische Federn wirken, sobald sich ihr Knoten bewegt; EI/EA als Symbol in einem
            -- Lasttext zaehlt immer
            local maxU = 0
            for _, k in ipairs(knoten) do
                if k.mat_pv then for j = 1, 3 do maxU = math.max(maxU, math.abs(k.mat_pv[j][2] or 0)) end end
            end
            for _, k in ipairs(knoten) do
                local bewegt = false
                if k.mat_pv then for j = 1, 3 do if math.abs(k.mat_pv[j][2] or 0) > 1e-9 * maxU then bewegt = true end end end
                local felder = { k.cx_str, k.cy_str, k.cm_str }
                for j = 1, 3 do
                    local t = felder[j]
                    if bewegt and type(t) == "string" and t ~= "" and not neuIstZahlText(t) then symAktiv = true end
                end
            end
            -- (nur Lasttexte: sym_vars enthaelt auch die Symbole der Steifigkeitsfelder selbst)
            local function nenntEIEA(t)
                if type(t) ~= "string" then return false end
                for w in t:gmatch("%a[%w_]*") do local l = w:lower(); if l == "ei" or l == "ea" then return true end end
                return false
            end
            for _, k in ipairs(knoten) do
                if nenntEIEA(k.last_x_str) or nenntEIEA(k.last_y_str) or nenntEIEA(k.last_m_str) then symAktiv = true end
            end
            for _, s in ipairs(staebe) do
                local felder = { s.q_str, s.q_A_str, s.q_B_str, s.n_str, s.n_A_str, s.n_B_str, s.m_str, s.gx_str, s.gy_str, s.To_str, s.Tu_str }
                for j = 1, 11 do
                    if nenntEIEA(felder[j]) then symAktiv = true end
                end
            end
            if not symAktiv then eiListe, eaListe = {}, {} end
            -- Folge der Mischung: bei statisch bestimmten Systemen nur die Verformung, sonst auch die Kraefte
            local folge
            if getTopologicalN() ~= 0 then
                folge = "Das System ist statisch unbestimmt, deshalb kann der Zahlenwert auch die Schnittgroessen verfaelschen (Symbole rechnen intern mit 1)."
            else
                folge = "Die Schnittgroessen bleiben richtig (statisch bestimmt), Biegelinie und Export mischen aber Zahl und Symbol."
            end
            if #eiListe > 0 then
                liste[#liste + 1] = "Stab " .. table.concat(eiListe, ", ") .. " wird auf Biegung belastet, EI ist dort eine Zahl, andere Steifigkeiten sind symbolisch. " .. folge .. " Abhilfe: EI symbolisch eingeben, Stab biegesteif setzen oder bei einem Pendelstab Gelenke an beiden Enden."
            end
            if #eaListe > 0 then
                liste[#liste + 1] = "Stab " .. table.concat(eaListe, ", ") .. " traegt Normalkraft, EA ist dort eine Zahl, andere Steifigkeiten sind symbolisch. " .. folge .. " Abhilfe: EA symbolisch eingeben oder Stab dehnsteif setzen (bzw. Standard-EA dehnstarr)."
            end
        end
    end
    hinweisListe = liste
    -- nach ESC erst wieder zeigen, wenn sich das System (oder der Hinweis) geaendert hat
    hinweisSig = (#liste > 0) and (table.concat(liste, "|") .. "#" .. systemFingerabdruck()) or nil
    hinweisOffen = hinweisSig ~= nil and hinweisSig ~= hinweisQuittiert
end

local function clearOldCASVars()
    if not math.eval then return end
    local vars = {}
    for i = 1, 30 do
        table.insert(vars, "N_bogen"..i); table.insert(vars, "q_bogen"..i); table.insert(vars, "M_bogen"..i)
        table.insert(vars, "N_stab"..i); table.insert(vars, "Q_stab"..i); table.insert(vars, "M_stab"..i)
        table.insert(vars, "w_stab"..i); table.insert(vars, "u_stab"..i)
        table.insert(vars, "x_stab"..i); table.insert(vars, "y_stab"..i)
        table.insert(vars, "knot"..i.."_pv")
    end
    table.insert(vars, "sys_k"); table.insert(vars, "sys_f"); table.insert(vars, "sys_u")
    math.eval("DelVar " .. table.concat(vars, ", "))
end

-- Alle Variablen, die das Skript im Dokument anlegt (Exporte und Hilfsvariablen), loeschen:
-- Obermenue Seite 4, Zeile 7, zweimal Enter. Gespeicherte Systeme (system<Nr>) und eigene Variablen
-- bleiben, geloescht wird nur, was zu den Namen unten passt (# steht fuer eine Nummer).
SKRIPT_VARIABLEN = { "randbed", "randinfo", "rleps", "sys_k", "sys_f", "sys_u", "kgv_delta", "kgv_delta0",
    "w_eq1", "w_eq2", "pvv_kin", "pvv_pol", "pvvinfo", "ggw_a", "ggw_b", "ggw_x", "ggw_eqs", "lgs",
    "q_temp", "q_cas_q", "q_cas_m", "q_cas_vk_ei", "n_temp", "n_cas_n", "n_cas_uk_ea", "m_temp", "m_cas_m",
    "m_cas_vk_ei", "q_pure", "n_pure", "m_pure", "gx_temp", "gy_temp",
    "wneu#", "uneu#", "wv#", "uv#", "v_ei_stab#", "u_ea_stab#", "n_stab#", "q_stab#", "m_stab#", "w_stab#",
    "u_stab#", "x_stab#", "y_stab#", "m_bogen#", "n_bogen#", "q_bogen#", "stab#_k", "stab#_p", "stab#_v",
    "knot#_pv", "ux_k#", "uy_k#", "phi_k#" }
varLoeschFrage = false   -- erstes Enter in Zeile 7 fragt nach, das zweite loescht

function istSkriptVariable(name)
    local n = tostring(name):lower()
    if n:match("^system%d+$") then return false end
    for _, muster in ipairs(SKRIPT_VARIABLEN) do
        if n:match("^" .. muster:gsub("#", "%%d+") .. "$") then return true end
    end
    return false
end

-- liefert die Zahl der Namen, fuer die DelVar ausgefuehrt wurde
function loescheSkriptVariablen()
    if not math.eval then return 0 end
    local namen, gesehen = {}, {}
    local function dazu(n)
        n = tostring(n):lower()
        if not gesehen[n] and istSkriptVariable(n) then gesehen[n] = true; namen[#namen + 1] = n end
    end
    -- alle Nummern bis zur Stab-/Knotenzahl (mindestens 30), dazu mit var.list auch Reste
    -- groesserer Systeme (z. B. wneu45)
    local nMax = math.max(30, #staebe, #knoten)
    for _, muster in ipairs(SKRIPT_VARIABLEN) do
        if muster:find("#", 1, true) then
            for i = 1, nMax do dazu((muster:gsub("#", tostring(i)))) end
        else dazu(muster) end
    end
    if var and var.list then
        local ok, liste = pcall(var.list)
        if ok and type(liste) == "table" then for _, n in ipairs(liste) do dazu(n) end end
    end
    for i = 1, #namen, 40 do   -- in Stuecken, eine einzige DelVar-Zeile wuerde sehr lang
        local teil = {}
        for j = i, math.min(i + 39, #namen) do teil[#teil + 1] = namen[j] end
        pcall(math.eval, "DelVar " .. table.concat(teil, ","))
    end
    randErgebnis = nil   -- sonst meldete das Rand-LGS "aus dem Speicher", obwohl wneu usw. fehlen
    return #namen
end

local function starteBerechnung()
    clearOldCASVars()
    warnungKinematisch, warnungStarrBestimmt, meldungText, kgv_n = false, false, nil, nil
    print("Starte Systemanalyse...")
    checkSymbolischerModus()
    if symbolFehler then
        -- Symbolischer Modus kann dieses System nicht korrekt abbilden: abbrechen statt falsche Ergebnisse
        hinweisListe, hinweisOffen = {}, false
        systemBerechnet = false
        print("Symbolischer Modus: " .. symbolFehler)
        platform.window:invalidate()
        return
    end
    if KGV_Zustand and KGV_Zustand ~= -1 then applyKGVZustand(-1) end 
    
    backupSystem() 
    if autoKGV then
        findeAutoHauptsystem(); KGV_Zustand = (#X_Werte > 0) and 0 or -1; applyKGVZustand(KGV_Zustand)
    else 
        if zeigeN then findeAutoHauptsystem(); X_Werte = {} end
        KGV_Zustand = -1; applyKGVZustand(-1)
    end
    rechneAktuellesSystem()
    runSymbolicSuperposition()
    rechneAktuellesSystem() -- Restore the numeric system state after superposition iterations
    precalcSymbolicLabels()
    sammleHinweise()
    systemBerechnet = true
    print("Berechnung erfolgreich!")
end

-- ==========================================
-- 4. TASTATUR- UND MAUS-STEUERUNG
-- ==========================================
function on.mouseMove(x, y) mouseX, mouseY = x, y; updateHover(); platform.window:invalidate() end

function on.mouseUp(x, y)
    if menuOffen then menuOffen, eingabeModus = false, false; platform.window:invalidate(); return end
    
    if pvvModus then
        if hoverTyp == "knoten" then
            menuOffen, menuTyp, menuIndex, menuZeile, menuSeite, eingabeModus = true, "pvv_knoten", hoverObj, 1, 1, false
            buildPolplan()
            calcKinematicStates()
            ansichtsModus = "V"
            pvvPrepareCAS()
            platform.window:invalidate()
        elseif hoverTyp == "stab" then
            menuOffen, menuTyp, menuIndex, menuZeile, menuSeite, eingabeModus = true, "pvv_stab", hoverObj, 1, 1, false
            buildPolplan()
            calcKinematicStates()
            ansichtsModus = "V"
            pvvPrepareCAS()
            platform.window:invalidate()
        end
        return
    end
    
    if hoverTyp == "knoten" then 
        if auswahl and auswahl ~= hoverObj then 
            table.insert(staebe, erstelleStab(auswahl, hoverObj)); auswahl = nil 
            systemBerechnet = false
        else 
            auswahl = hoverObj 
        end
    elseif hoverTyp == "stab" then
        if schnittAnzeigeModus == "Hover" and (ansichtsModus == "M" or ansichtsModus == "N" or ansichtsModus == "Q") then
            local s = staebe[hoverObj]
            local px1, py1 = knoten[s.k1].x * pxProMeter + offsetX, knoten[s.k1].y * pxProMeter + offsetY
            local px2, py2 = knoten[s.k2].x * pxProMeter + offsetX, knoten[s.k2].y * pxProMeter + offsetY
            if (s.bogen_r or 0) ~= 0 then
                -- Arc messpunkte
                local R = math.abs(s.bogen_r) * pxProMeter
                local mx, my = px1 + (px2-px1)/2, py1 + (py2-py1)/2
                local bar_dx, bar_dy = px2 - px1, py2 - py1
                local dist = math.sqrt(R^2 - (math.sqrt(bar_dx^2 + bar_dy^2)/2)^2)
                local norm_x, norm_y = -bar_dy, bar_dx
                local len = math.sqrt(norm_x^2 + norm_y^2)
                if len > 0 then norm_x, norm_y = norm_x/len, norm_y/len end
                if (s.bogen_r > 0) then norm_x, norm_y = -norm_x, -norm_y end
                local cx, cy = mx + norm_x*dist, my + norm_y*dist
                local a1 = math.atan2(py1 - cy, px1 - cx)
                local am = math.atan2(y - cy, x - cx)
                local a2 = math.atan2(py2 - cy, px2 - cx)
                local d_a = a2 - a1
                if s.bogen_r > 0 and d_a < 0 then d_a = d_a + 2*math.pi end
                if s.bogen_r < 0 and d_a > 0 then d_a = d_a - 2*math.pi end
                local cur_d = am - a1
                if s.bogen_r > 0 and cur_d < 0 then cur_d = cur_d + 2*math.pi end
                if s.bogen_r < 0 and cur_d > 0 then cur_d = cur_d - 2*math.pi end
                local t_h = math.max(0, math.min(1, cur_d / d_a))
                s.messpunkte = s.messpunkte or {}
                table.insert(s.messpunkte, t_h)
            else
                local dx_bar, dy_bar = px2 - px1, py2 - py1
                local L_screen2 = dx_bar*dx_bar + dy_bar*dy_bar
                if L_screen2 > 0 then
                    local t_h = ((x - px1)*dx_bar + (y - py1)*dy_bar) / L_screen2
                    t_h = math.max(0, math.min(1, t_h))
                    s.messpunkte = s.messpunkte or {}
                    table.insert(s.messpunkte, t_h)
                end
            end
        end
    elseif not hoverTyp then 
        local nx, ny = pixelZuMeterX(x), pixelZuMeterY(y)
        local existing_node = nil
        for i, k in ipairs(knoten) do
            if math.abs(k.x - nx) < 1e-4 and math.abs(k.y - ny) < 1e-4 then existing_node = i; break end
        end
        
        if existing_node then
            if auswahl and auswahl ~= existing_node then 
                table.insert(staebe, erstelleStab(auswahl, existing_node)); auswahl = nil 
                systemBerechnet = false
            else auswahl = existing_node end
        else
            local neu_k = erstelleKnoten(nx, ny)
            if fachwerkModus then neu_k.gelenk = true end
            table.insert(knoten, neu_k)
            auswahl = #knoten 
            systemBerechnet = false
        end
    end
    platform.window:invalidate()
end

function on.timer() 
    if ansichtsModus == "V" then
        kinematic_anim_timer = kinematic_anim_timer + 0.1
        platform.window:invalidate()
    else
        kgvInputString = ""
        timer.stop() 
    end
end

local lgs_equations = {}


function getSuppLetter(nodeIndex)
    local letterIndex = 1
    for i, k in ipairs(knoten) do
        if k.lager_x or k.lager_y or k.lager_m or (k.cx and k.cx > 0) or (k.cy and k.cy > 0) or (k.cm and k.cm > 0) then
            if i == nodeIndex then
                return string.char(64 + letterIndex)
            end
            letterIndex = letterIndex + 1
        end
    end
    return string.char(64 + nodeIndex)
end

function getHingeNumber(nodeIndex)
    local hingeIndex = 1
    for i, k in ipairs(knoten) do
        local hasHinge = k.gelenk
        if not hasHinge then
            for _, s in ipairs(staebe) do
                if (s.k1 == i and (s.n_gelenk_A or s.q_gelenk_A or s.gelenk_A)) or
                   (s.k2 == i and (s.n_gelenk_B or s.q_gelenk_B or s.gelenk_B)) then
                    hasHinge = true
                    break
                end
            end
        end
        if hasHinge then
            if i == nodeIndex then return hingeIndex end
            hingeIndex = hingeIndex + 1
        end
    end
    return nodeIndex
end

-- Gelenkknoten fuer Explosionszeichnung (Seite 2) und LGS-Export: Staebe mit Gelenk (H) bzw.
-- biegesteif (R) am Knoten, Zahl der Teilsysteme dort und erster Gelenkstab r1 (Stabreihenfolge)
function gelenkKnoten(k_idx)
    local k = knoten[k_idx]
    local H, R = {}, {}
    for j, s in ipairs(staebe) do
        if not s.is_cut and (s.k1 == k_idx or s.k2 == k_idx) then
            local g = k.gelenk
                or (s.k1 == k_idx and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A))
                or (s.k2 == k_idx and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B))
            if g then H[#H + 1] = j else R[#R + 1] = j end
        end
    end
    return { H = H, R = R, numTS = #H + ((#R > 0) and 1 or 0), r1 = H[1] }
end

-- Positive Richtung der Gelenkgroessen am Gelenkstab j (Seite 2 und LGS): der erste Gelenkstab r1
-- traegt sie wie positive Schnittgroessen (Stabanfang -1: nach links/oben bzw. gegen Stabachse und
-- -normale, Moment im Uhrzeigersinn; Stabende +1), alle anderen Seiten entgegengesetzt
function gelenkRichtung(k_idx, j, info)
    info = info or gelenkKnoten(k_idx)
    local r1 = info.r1 or j
    local e1 = (staebe[r1].k1 == k_idx) and -1 or 1
    return (j == r1) and e1 or -e1
end

-- Stab, an dem Seite 2 die Lasten und Lager eines Knotens zeichnet: der erste Stab mit Gelenk am
-- Knoten, sonst der erste Stab dort (alle biegesteif verbunden, also dasselbe Teilsystem)
function lastStabKnoten(k_idx)
    local erster
    for j, s in ipairs(staebe) do
        if not s.is_cut and (s.k1 == k_idx or s.k2 == k_idx) then
            erster = erster or j
            if knoten[k_idx].gelenk
                or (s.k1 == k_idx and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A))
                or (s.k2 == k_idx and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B)) then
                return j
            end
        end
    end
    return erster
end

-- Gleichgewichts-LGS zur Explosionszeichnung, Seite 2: die Handrechnung zu genau den dort
-- gezeichneten Kraeften (TM1: statisch bestimmte Systeme). Je Teilsystem Summe der Kraefte nach
-- rechts, nach oben und Summe der Momente gegen den Uhrzeigersinn um den Bezugspunkt P.
-- Unbekannte mit Namen und positiver Richtung wie auf Seite 2:
--   Lager X (getSuppLetter): X_h in xi = (cos w, -sin w), X_v nach oben (-eta), M_X gegen den Uhrzeigersinn
--   Momentengelenk n: Gx_n, Gy_n; N-/Q-Gelenk: Gn_n, Gq_n (Stabachse bzw. -normale), Gm_n;
--     Richtung nach gelenkRichtung, auf der Gegenseite entgegengesetzt
--   mehr als zwei Teilsysteme am Gelenk: je Gelenkstab eigene Groessen (Suffix s<Teilsystem>); ohne
--     biegesteifen Rest zusaetzlich das Gleichgewicht des Gelenkbolzens
-- Lasten und Lager eines Knotens gehoeren zum Teilsystem von lastStabKnoten (wie auf Seite 2).
-- Symbolischer Modus: Lasten mit Namen, Laengen als Vielfache von l.
function exportLGSMatrixToTI(only_build)
    local sym = symbolischer_modus
    local fN = fN_export
    local eq_strings, x_labels, A, b = {}, {}, {}, {}
    local unbekannte = {}

    local function addVar(name)
        table.insert(x_labels, {name})
        unbekannte[#x_labels] = { name = name, eintraege = {} }
        return #x_labels
    end

    local function istNull(v) return v == nil or v == 0 or v == "0" end
    local function txt(v) return type(v) == "number" and fN(v) or v end
    local function laenge(d)
        if math.abs(d) < 1e-12 then return 0 end
        if not sym then return d end
        return pvvLaenge(d)
    end
    local function mal(a, c)
        if istNull(a) or istNull(c) then return 0 end
        if type(a) == "number" and type(c) == "number" then return a * c end
        if a == 1 then return c end
        if c == 1 then return a end
        return "(" .. txt(a) .. ")*(" .. txt(c) .. ")"
    end
    local function summe(a, c)
        if istNull(a) then return c end
        if istNull(c) then return a end
        if type(a) == "number" and type(c) == "number" then return a + c end
        return "(" .. txt(a) .. ")+(" .. txt(c) .. ")"
    end

    -- Zelle einer Matrix: Zahlanteil plus Textanteile (symbolisch)
    local function zelle() return { n = 0, t = {} } end
    local function dazu(z, v)
        if istNull(v) then return end
        if type(v) == "number" then z.n = z.n + v else z.t[#z.t + 1] = v end
    end
    local function zellText(z)
        if not z then return "0" end
        if #z.t == 0 then return fN(math.abs(z.n) < 1e-9 and 0 or z.n) end
        local teile = {}
        for _, t in ipairs(z.t) do teile[#teile + 1] = "(" .. t .. ")" end
        if math.abs(z.n) > 1e-12 then teile[#teile + 1] = fN(z.n) end
        local s = table.concat(teile, "+")
        if math.eval then s = eval_cas_string(s) or s end
        return s
    end

    local koerper = {}
    local function neuerKoerper(px, py, mitMoment, namen)
        local kp = { px = px, py = py, mitMoment = mitMoment, namen = namen, rx = {}, ry = {}, rm = {},
                     bx = zelle(), by = zelle(), bm = zelle() }
        koerper[#koerper + 1] = kp
        return kp
    end
    local function zelleVon(tab, var) tab[var] = tab[var] or zelle(); return tab[var] end

    -- unbekannte Kraft in Richtung (fx, fy) (y nach unten) bzw. Moment m (gegen den Uhrzeigersinn) am Punkt (x, y)
    local function unbekannt(kp, var, x, y, fx, fy, m)
        if not kp or not var then return end
        fx, fy, m = fx or 0, fy or 0, m or 0
        dazu(zelleVon(kp.rx, var), fx)
        dazu(zelleVon(kp.ry, var), -fy)
        if kp.mitMoment then
            dazu(zelleVon(kp.rm, var), laenge((y - kp.py) * fx - (x - kp.px) * fy))
            dazu(zelleVon(kp.rm, var), m)
        end
        table.insert(unbekannte[var].eintraege, { koerper = kp, fx = fx, fy = fy, m = m, x = x, y = y })
    end
    -- bekannte Kraft F in Richtung (cx, cy) am Punkt (x, y) und bekanntes Moment M (gegen den Uhrzeigersinn)
    local function bekannt(kp, x, y, F, cx, cy, M)
        if not kp then return end
        if not istNull(F) then
            dazu(kp.bx, mal(F, -cx))
            dazu(kp.by, mal(F, cy))
            if kp.mitMoment then dazu(kp.bm, mal(F, mal(-1, laenge((y - kp.py) * cx - (x - kp.px) * cy)))) end
        end
        if kp.mitMoment and not istNull(M) then dazu(kp.bm, mal(-1, M)) end
    end
    -- Streckenlast: Resultierende R in Richtung (cx, cy) und statisches Moment S um k1 entlang der Stabachse
    -- (e_x, e_y): Moment um P = R*d0 + S*(e_y cx - e_x cy)
    local function streckenlast(kp, k1, ex, ey, R, S, cx, cy)
        if not kp then return end
        if not istNull(R) then
            dazu(kp.bx, mal(R, -cx))
            dazu(kp.by, mal(R, cy))
            if kp.mitMoment then dazu(kp.bm, mal(R, mal(-1, laenge((k1.y - kp.py) * cx - (k1.x - kp.px) * cy)))) end
        end
        local c1 = ey * cx - ex * cy
        if kp.mitMoment and not istNull(S) and math.abs(c1) > 1e-12 then dazu(kp.bm, mal(S, -c1)) end
    end

    -- Knotenlast global (y nach unten), wie in der Berechnung um -last_w gedreht; symbolisch mit Namen
    local function knotenlast(k)
        local function wert(z, t)
            if math.abs(z or 0) < 1e-12 then return 0 end
            if sym and type(t) == "string" and t ~= "" then return "(" .. t .. ")" end
            return z
        end
        local sx, sy, sm = wert(k.last_x, k.last_x_str), wert(k.last_y, k.last_y_str), wert(k.last_m, k.last_m_str)
        local r = math.rad(-(k.last_w or 0))
        local c, sn = math.cos(r), math.sin(r)
        return summe(mal(sx, c), mal(sy, -sn)), summe(mal(sx, sn), mal(sy, c)), sm
    end

    -- Resultierende und statisches Moment (um k1, entlang der Stabachse) der Streckenlasten eines Stabes
    local function integriere(p_str, L)
        local Ls = string.format("%.15g", L)
        local R = casToNumber(math.eval("approx(integral(" .. p_str .. ",x,0," .. Ls .. "))")) or 0
        local S = casToNumber(math.eval("approx(integral((" .. p_str .. ")*x,x,0," .. Ls .. "))")) or 0
        return R, S
    end
    local function streckenlasten(s, L, ex, ey)
        -- Bogen: Lasten wie in der FEM auf dem Bogen verteilt (bogenLastResultierende), als Kraft am
        -- Stabanfang plus Moment um ihn
        if istBogen(s) then
            local r = bogenHatLast(s) and bogenLastResultierende(s)
            if not r then return {} end
            return { { R = r.summe[1], S = 0, cx = 1, cy = 0 }, { R = r.summe[2], S = 0, cx = 0, cy = 1 },
                     { moment = true, M = r.summe[3] } }
        end
        local out = {}
        local function trapezText(A_, B_) return string.format("(%.15g)+((%.15g)-(%.15g))*x/(%.15g)", A_, B_, A_, L) end
        -- Querlast q (Richtung z = (-e_y, e_x)) und Laengslast n (Richtung e)
        for _, art in ipairs({ { "q", -ey, ex }, { "n", ex, ey } }) do
            local t = art[1]
            local R, S
            if sym then
                R, S = processDistLoad_PvV(L, L, s[t .. "_str"], s[t .. "_A_str"], s[t .. "_B_str"], nil, nil, 0, 0, "q")
            else
                local str = s[t .. "_str"] or ""
                if str:hasx() then
                    R, S = integriere("(" .. str .. ")+" .. trapezText(s[t .. "_A"] or 0, s[t .. "_B"] or 0), L)
                else
                    local a, c = (s[t] or 0) + (s[t .. "_A"] or 0), (s[t] or 0) + (s[t .. "_B"] or 0)
                    R, S = (a + c) / 2 * L, L * L / 6 * (a + 2 * c)
                end
            end
            out[#out + 1] = { R = R, S = S, cx = art[2], cy = art[3] }
        end
        -- globale Linienlasten p_X (nach rechts) und p_Y (nach unten), ggf. projiziert
        for _, art in ipairs({ { "gx", 1, 0, math.abs(ey) }, { "gy", 0, 1, math.abs(ex) } }) do
            local t = art[1]
            local L_eff = s[t .. "_proj"] and L * art[4] or L
            local R, S
            if sym then
                R, S = processDistLoad_PvV(L, L_eff, s[t .. "_str"], nil, nil, nil, nil, 0, 0, "g")
            else
                local str, f = globaleLinienlast(s, t)
                if str:hasx() then
                    R, S = integriere("(" .. str .. ")*" .. string.format("%.15g", f), L)
                else
                    R = (s[t] or 0) * L_eff; S = R * L / 2
                end
            end
            out[#out + 1] = { R = R, S = S, cx = art[2], cy = art[3] }
        end
        -- Streckenmoment m (gegen den Uhrzeigersinn je Laenge)
        local M
        if sym then
            M = processDistLoad_PvV(L, L, s.m_str, nil, nil, nil, nil, 0, 0, "m")
        elseif (s.m_str or ""):hasx() then
            M = integriere("(" .. s.m_str .. ")", L)
        else
            M = (s.m or 0) * L
        end
        out[#out + 1] = { moment = true, M = M }
        return out
    end

    -- Lagerunbekannte (Lager und Federn wie auf Seite 2)
    local lagerVar = {}
    local function lagerVariablen()
        for i, k in ipairs(knoten) do
            local L = getSuppLetter(i)
            local v = {}
            if k.lager_x or (k.cx or 0) > 0 then v.h = addVar(L .. "_h"); unbekannte[v.h].quelle = { knoten = i, komp = "h" } end
            if k.lager_y or (k.cy or 0) > 0 then v.v = addVar(L .. "_v"); unbekannte[v.v].quelle = { knoten = i, komp = "v" } end
            if not fachwerkModus and (k.lager_m or (k.cm or 0) > 0) then v.m = addVar("M_" .. L); unbekannte[v.m].quelle = { knoten = i, komp = "m" } end
            lagerVar[i] = v
        end
    end
    local function lagerUndLasten(i, kp)
        local k, v = knoten[i], lagerVar[i]
        local w = math.rad(k.winkel or 0)
        if v.h then unbekannt(kp, v.h, k.x, k.y, math.cos(w), -math.sin(w), 0) end
        if v.v then unbekannt(kp, v.v, k.x, k.y, -math.sin(w), -math.cos(w), 0) end
        if v.m then unbekannt(kp, v.m, k.x, k.y, 0, 0, 1) end
        local fx, fy, m = knotenlast(k)
        bekannt(kp, k.x, k.y, fx, 1, 0, 0)
        bekannt(kp, k.x, k.y, fy, 0, 1, 0)
        bekannt(kp, k.x, k.y, 0, 0, 0, m)
    end

    if fachwerkModus then
        -- Knotenschnittverfahren: Stabkraefte S_j (Zug positiv, am Knoten vom Knoten weg)
        local knotenKp = {}
        for i, k in ipairs(knoten) do knotenKp[i] = neuerKoerper(k.x, k.y, false, { "→ K" .. i, "↑ K" .. i }) end
        local sVar = {}
        for j, s in ipairs(staebe) do if not s.is_cut then sVar[j] = addVar("S_" .. j); unbekannte[sVar[j]].quelle = { stab = j, komp = "S" } end end
        lagerVariablen()
        for j, s in ipairs(staebe) do
            if sVar[j] then
                local k1, k2 = knoten[s.k1], knoten[s.k2]
                local dx, dy = k2.x - k1.x, k2.y - k1.y
                local L = math.sqrt(dx * dx + dy * dy)
                if L > 0 then
                    unbekannt(knotenKp[s.k1], sVar[j], k1.x, k1.y, dx / L, dy / L, 0)
                    unbekannt(knotenKp[s.k2], sVar[j], k2.x, k2.y, -dx / L, -dy / L, 0)
                end
            end
        end
        for i in ipairs(knoten) do lagerUndLasten(i, knotenKp[i]) end
    else
        if not glob_ts_scheibe or not glob_disk_centers then assignTeilsysteme() end
        local ts_von = glob_ts_scheibe
        local ts = {}
        for d = 1, glob_num_disks do
            local c = glob_disk_centers[d]
            ts[d] = neuerKoerper(c.x, c.y, true, { "→ TS " .. d, "↑ TS " .. d,
                c.node_id and ("ΣM P" .. c.node_id) or ("ΣM TS " .. d) })
        end
        local function tsVonStab(j) return j and ts_von[j] and ts[ts_von[j]] or nil end

        lagerVariablen()

        -- Gelenke
        local bolzen = {}
        for i, k in ipairs(knoten) do
            local info = gelenkKnoten(i)
            if info.numTS > 1 then
                local nr = getHingeNumber(i)
                local rest = (#info.R > 0) and tsVonStab(info.R[1]) or nil
                local function freigabe(j)
                    local s = staebe[j]
                    local amA = (s.k1 == i)
                    local rel_m = k.gelenk or (amA and s.gelenk_A) or ((not amA) and s.gelenk_B)
                    local rel_n = (amA and s.n_gelenk_A) or ((not amA) and s.n_gelenk_B)
                    local rel_q = (amA and s.q_gelenk_A) or ((not amA) and s.q_gelenk_B)
                    return rel_m and true or false, rel_n and true or false, rel_q and true or false
                end
                local function groessen(j, suffix)
                    local rel_m, rel_n, rel_q = freigabe(j)
                    local g = {}
                    if rel_m and not rel_n and not rel_q then
                        g.x = addVar("Gx_" .. nr .. suffix); g.y = addVar("Gy_" .. nr .. suffix)
                    else
                        if not rel_n then g.n = addVar("Gn_" .. nr .. suffix) end
                        if not rel_q then g.q = addVar("Gq_" .. nr .. suffix) end
                        if not rel_m then g.m = addVar("Gm_" .. nr .. suffix) end
                    end
                    for komp, var in pairs(g) do unbekannte[var].quelle = { knoten = i, stab = j, komp = komp } end
                    return g
                end
                -- Gelenkgroessen g des Stabes j am Koerper kp, in faktor * Richtung von Seite 2
                local function eintragen(j, g, kp, faktor)
                    local s = staebe[j]
                    local d = gelenkRichtung(i, j, info) * faktor
                    local ka, kb = knoten[s.k1], knoten[s.k2]
                    local L = math.sqrt((kb.x - ka.x)^2 + (kb.y - ka.y)^2)
                    local tx, ty = (kb.x - ka.x) / L, (kb.y - ka.y) / L
                    if g.x then unbekannt(kp, g.x, k.x, k.y, d, 0, 0) end
                    if g.y then unbekannt(kp, g.y, k.x, k.y, 0, d, 0) end
                    if g.n then unbekannt(kp, g.n, k.x, k.y, d * tx, d * ty, 0) end
                    if g.q then unbekannt(kp, g.q, k.x, k.y, -d * ty, d * tx, 0) end
                    if g.m then unbekannt(kp, g.m, k.x, k.y, 0, 0, d) end
                end
                if info.numTS == 2 then
                    local r1 = info.r1
                    local g = groessen(r1, "")
                    eintragen(r1, g, tsVonStab(r1), 1)
                    eintragen(r1, g, rest or tsVonStab(info.H[2]), -1)
                else
                    local pin
                    if not rest then
                        local mitMoment = false
                        for _, j in ipairs(info.H) do if not freigabe(j) then mitMoment = true end end
                        local namen = { "→ G" .. nr, "↑ G" .. nr }
                        if mitMoment then namen[3] = "ΣM G" .. nr end
                        pin = { px = k.x, py = k.y, mitMoment = mitMoment, namen = namen, bolzen = true, rx = {}, ry = {}, rm = {},
                                bx = zelle(), by = zelle(), bm = zelle() }
                        bolzen[#bolzen + 1] = pin
                    end
                    for _, j in ipairs(info.H) do
                        local g = groessen(j, "s" .. (ts_von[j] or j))
                        eintragen(j, g, tsVonStab(j), 1)
                        eintragen(j, g, rest or pin, -1)
                    end
                end
            end
        end

        -- Lager und Knotenlasten am Teilsystem, an dem Seite 2 sie zeichnet
        for i in ipairs(knoten) do
            local kp = tsVonStab(lastStabKnoten(i))
            if kp then lagerUndLasten(i, kp) end
        end

        -- Streckenlasten als Resultierende
        for j, s in ipairs(staebe) do
            local kp = tsVonStab(j)
            if kp and not s.is_cut then
                local k1, k2 = knoten[s.k1], knoten[s.k2]
                local dx, dy = k2.x - k1.x, k2.y - k1.y
                local L = math.sqrt(dx * dx + dy * dy)
                if L > 1e-9 then
                    local ex, ey = dx / L, dy / L
                    for _, last in ipairs(streckenlasten(s, L, ex, ey)) do
                        if last.moment then bekannt(kp, 0, 0, 0, 0, 0, last.M)
                        else streckenlast(kp, k1, ex, ey, last.R, last.S, last.cx, last.cy) end
                    end
                end
            end
        end
        for _, pin in ipairs(bolzen) do koerper[#koerper + 1] = pin end
    end

    -- Zeilen: je Koerper Summe nach rechts, nach oben (und Momente)
    for _, kp in ipairs(koerper) do
        local zeilen = { { kp.rx, kp.bx }, { kp.ry, kp.by } }
        if kp.mitMoment then zeilen[3] = { kp.rm, kp.bm } end
        for z, zl in ipairs(zeilen) do
            local row = {}
            for c = 1, #x_labels do row[c] = zellText(zl[1][c]) end
            table.insert(A, row)
            table.insert(b, { zellText(zl[2]) })
            table.insert(eq_strings, { kp.namen[z] })
        end
    end
    lgs_modell = { unbekannte = unbekannte, koerper = koerper, A = A, b = b, x = x_labels }

    if #A > 0 then
        for r = 1, #A do
            local new_r = {}
            for c = 1, #x_labels do 
                local val = A[r][c] or 0
                if type(val) == 'number' and math.abs(val) < 1e-9 then val = 0 end
                new_r[c] = fN_export(val) 
            end
            A[r] = new_r
        end
        for r = 1, #b do
            local val = b[r][1] or 0
            if type(val) == 'number' and math.abs(val) < 1e-9 then val = 0 end
            b[r][1] = fN_export(val)
        end
        
        if only_build then
            lgs_equations = {}
            for r = 1, #A do
                local eq_str = ""
                for c = 1, #x_labels do
                    local val = A[r][c]
                    if val ~= "0" and val ~= 0 then
                        local valStr = tostring(val)
                        if not valStr:match("^%-") then valStr = "+" .. valStr end
                        eq_str = eq_str .. " " .. valStr .. "*" .. x_labels[c][1]
                    end
                end
                if eq_str == "" then eq_str = "0" end
                eq_str = eq_str:gsub("^ %+", ""):gsub("^ ", "")
                local b_val = b[r][1]
                table.insert(lgs_equations, string.format("%s: %s = %s", eq_strings[r][1], eq_str, b_val))
            end
            return
        end
        
        if speichereMatrix then
            if math.eval then 
                local function evalMatSafe(name, mat)
                    if #mat == 0 then return end
                    for r = 1, #mat do
                        local row_str = "[" .. table.concat(mat[r], ",") .. "]"
                        if r == 1 then
                            pcall(function() math.eval(name .. ":=exact([" .. row_str .. "])") end)
                        else
                            pcall(function() math.eval(name .. ":=exact(colAugment(" .. name .. ",[" .. row_str .. "]))") end)
                        end
                    end
                end
                
                pcall(function() math.eval("DelVar ggw_a, ggw_b, ggw_x, lgs") end)
                evalMatSafe("ggw_a", A)
                evalMatSafe("ggw_b", b)
                
                local x_str_eval = "ggw_x:=["
                for i, x in ipairs(x_labels) do
                    x_str_eval = x_str_eval .. x[1]
                    if i < #x_labels then x_str_eval = x_str_eval .. ";" end
                end
                x_str_eval = x_str_eval .. "]"
                
                pcall(function() math.eval(x_str_eval) end)
                
                -- Wir nutzen wieder die Vektor-Multiplikation, erzwingen aber das exakte Ergebnis!
                -- Da unsere Matrix jetzt saubere "sqrt(2)/2" (und nicht "sqrt(1/2)") enthält, 
                -- sollte exact() jetzt ohne diesen 14-stelligen Bruch-Bug funktionieren!
                -- Baue lgs als Zeilenvektor mit Gleichungsbezeichnung + Gleichung
                -- Format: {name: Ax=b}
                local function build_named_lgs()
                    local lgs_rows = {}
                    for r = 1, #A do
                        local name = (eq_strings[r] and eq_strings[r][1]) or ("Gl."..r)
                        local row_parts = {}
                        for c = 1, #x_labels do
                            local val = A[r][c]
                            if val ~= "0" and val ~= 0 then
                                local vs = tostring(val)
                                if not vs:match("^%-") then vs = "+"..vs end
                                table.insert(row_parts, vs .. "*" .. x_labels[c][1])
                            end
                        end
                        local lhs = #row_parts > 0 and table.concat(row_parts, "") or "0"
                        lhs = lhs:gsub("^%+", "")
                        table.insert(lgs_rows, string.format("\"%s: %s=%s\"", name, lhs, b[r][1]))
                    end
                    local lgs_str = "[" .. table.concat(lgs_rows, ";") .. "]"
                    pcall(function() math.eval("lgs:=" .. lgs_str) end)
                end
                build_named_lgs()
                
                speichereMatrix("ggw_eqs", eq_strings)
                
                if #A ~= #x_labels then
                    zeigeMeldung("LGS exportiert (ggw_a, ggw_b, ggw_x, lgs). Achtung: LGS nicht quadratisch, " ..
                        #A .. " Gleichungen fuer " .. #x_labels .. " Unbekannte.", "Export")
                else
                    zeigeMeldung("LGS exportiert: ggw_a, ggw_b, ggw_x, lgs.", "Export")
                end
            else
                speichereMatrix("ggw_a", A)
                speichereMatrix("ggw_b", b)
                speichereMatrix("ggw_x", x_labels)
                speichereMatrix("ggw_eqs", eq_strings)
            end
        end
    end
end

local function buildLGS()
    exportLGSMatrixToTI(true)
end


function on.charIn(char)
    if char == "-" or char == "?" or char == string.char(226, 136, 146) or char == string.char(226, 129, 187) or char == string.char(173) or char == string.char(226, 128, 147) or char == "–" or char == "—" then char = "-" end
    if char == "×" then char = "*" end
    if eingabeModus then
        local pattern = "[%w%+%-%*/%^%(%)%.%,_ ]"
        if char:match(pattern) then eingabeText = eingabeText .. char; platform.window:invalidate() end
    elseif not menuOffen then
        if char:match("[%d]") then
            if autoKGV and KGV_Zustand ~= -1 then
                kgvInputString = kgvInputString .. char; local num = tonumber(kgvInputString)
                if num <= #X_Werte then KGV_Zustand=num; applyKGVZustand(num); rechneAktuellesSystem(); platform.window:invalidate(); timer.start(1.5)
                else kgvInputString=char; num=tonumber(kgvInputString); if num<=#X_Werte then KGV_Zustand=num; applyKGVZustand(num); rechneAktuellesSystem(); platform.window:invalidate(); timer.start(1.5) end end
            end
        elseif char == "+" then 
            local step = (ansichtsModus == "E") and zoomExplosion or zoomNormal
            local factor = 1 + step / 10
            local cx = platform.window:width() / 2
            local cy = platform.window:height() / 2
            
            local new_pxProMeter = pxProMeter * factor
            offsetX = cx - (cx - offsetX) * (new_pxProMeter / pxProMeter)
            offsetY = cy - (cy - offsetY) * (new_pxProMeter / pxProMeter)
            pxProMeter = new_pxProMeter
            platform.window:invalidate()
        elseif char == "-" then 
            local step = (ansichtsModus == "E") and zoomExplosion or zoomNormal
            local factor = 1 + step / 10
            local cx = platform.window:width() / 2
            local cy = platform.window:height() / 2
            
            local new_pxProMeter = math.max(5, pxProMeter / factor)
            offsetX = cx - (cx - offsetX) * (new_pxProMeter / pxProMeter)
            offsetY = cy - (cy - offsetY) * (new_pxProMeter / pxProMeter)
            pxProMeter = new_pxProMeter
            platform.window:invalidate()
        elseif char == "o" or char == "O" then menuOffen, menuTyp, menuZeile, menuSeite, eingabeModus = true, "obermenue", 1, 1, false; platform.window:invalidate()
        elseif (char == "f" or char == "F") and hoverTyp == "stab" and hoverObj then
            -- nur Start- und Endknoten tauschen, alle anderen Stabwerte bleiben, wie sie eingegeben sind
            local s = staebe[hoverObj]; s.k1, s.k2 = s.k2, s.k1
            systemBerechnet = false; updateAlleLasten(); platform.window:invalidate()
        elseif char == "b" or char == "B" then if starteBerechnung then starteBerechnung() end; platform.window:invalidate()
        elseif char == "c" or char == "C" then on.clearKey()
        elseif char == "l" or char == "L" then 
    ansichtsModus = "L"
    buildLGS()
    platform.window:invalidate()
elseif char == "s" or char == "S" then 
    if pvvModus or in_pvv_release then pvvRestoreSystem(); pvvModus = false; in_pvv_release = false; pvv_released_binding = nil end
    ansichtsModus = "System"; platform.window:invalidate()
elseif char == "n" or char == "N" then ansichtsModus = "N"; platform.window:invalidate()
elseif char == "q" or char == "Q" then ansichtsModus = "Q"; platform.window:invalidate()
elseif char == "m" or char == "M" then ansichtsModus = "M"; platform.window:invalidate()
elseif char == "w" or char == "W" then ansichtsModus = "W"; platform.window:invalidate()
elseif char == "u" or char == "U" then ansichtsModus = "U"; platform.window:invalidate()
elseif char == "e" or char == "E" then 
    if ansichtsModus == "E" then
        if explosionPage == 1 then explosionPage = 2
        else ansichtsModus = "System"; explosionPage = 1 end
    else ansichtsModus = "E"; explosionPage = 1 end
    platform.window:invalidate()
elseif char == "t" or char == "T" then 
    if showExplosionLabels == nil then showExplosionLabels = true end
    showExplosionLabels = not showExplosionLabels; platform.window:invalidate()
elseif char == "p" or char == "P" then
    if pvvModus then 
        wasInPVV = true
        savedMenuTyp = menuTyp; savedMenuIndex = menuIndex; savedMenuZeile = menuZeile; savedMenuSeite = menuSeite
        pvvRestoreSystem(); pvvModus = false 
    else
        wasInPVV = false
    end
    ansichtsModus = "P"; buildPolplan(); platform.window:invalidate()
        elseif char == "v" or char == "V" then
            if in_pvv_release then
                pvvRestoreSystem()
                in_pvv_release = false
                pvv_released_binding = nil
            end
            if ansichtsModus == "V" then
                if pvvModus then pvvRestoreSystem(); pvvModus = false end
                ansichtsModus = "System"
            else
                if checkStabilitat() then
                    pvvPrompt = true
                    pvv_released_binding = nil
                else
                    calcKinematicStates()
                    ansichtsModus = "V"
                    pvvPrepareCAS()
                end
            end
            platform.window:invalidate()
        elseif char == "h" or char == "H" then 
                    local b, h_win = platform.window:width(), platform.window:height()
                    if #knoten > 0 then
                        local minX, maxX, minY, maxY = knoten[1].x, knoten[1].x, knoten[1].y, knoten[1].y
                        for _, k in ipairs(knoten) do
                            if k.x < minX then minX = k.x end; if k.x > maxX then maxX = k.x end
                            if k.y < minY then minY = k.y end; if k.y > maxY then maxY = k.y end
                        end
                        
                        local w_sys = math.max(maxX - minX, 1)
                        local h_sys = math.max(maxY - minY, 1)
                        
                        local scaleX = (b * 0.8) / w_sys
                        local scaleY = (h_win * 0.8) / h_sys
                        pxProMeter = math.min(scaleX, scaleY)
                        
                        if pxProMeter > 200 then pxProMeter = 200 end
                        if pxProMeter < 5 then pxProMeter = 5 end
                        
                        offsetX = b / 2 - ((minX + maxX) / 2) * pxProMeter
                        offsetY = h_win / 2 - ((minY + maxY) / 2) * pxProMeter
                    else
                        pxProMeter = 60
                        offsetX, offsetY = b / 3, h_win / 2
                    end
                    platform.window:invalidate()
        end
    end
end

local function getMenuMaxZeile()
    if menuTyp == "knoten" then
        if menuSeite == 1 then return 6 elseif menuSeite == 2 then return 5 elseif menuSeite == 3 then return 4 elseif menuSeite == 4 then return 9 else return 6 end
    elseif menuTyp == "stab" then
        if menuSeite == 1 then return 8 elseif menuSeite == 2 then return 4 elseif menuSeite == 3 then return 8 elseif menuSeite == 6 then return 6 elseif menuSeite == 7 then return 7 else return 6 end
    elseif menuTyp == "obermenue" then
        if menuSeite == 1 then return 8 elseif menuSeite == 2 then return 9 elseif menuSeite == 3 then return 9 elseif menuSeite == 4 then return 7 else return 3 end
    elseif menuTyp == "pvv_knoten" then
        return 4
    elseif menuTyp == "pvv_stab" then
        return 6
    end
    return 1
end

function on.enterKey()
    if loeschFrage then loescheAlles(); return end
    if pvvPrompt then
        pvvPrompt = false
        pvvModus = true
        platform.window:invalidate()
        return
    end
    local sys_changed = false
    if not menuOffen then if hoverObj then menuOffen, menuTyp, menuIndex, menuZeile, menuSeite, eingabeModus, auswahl = true, hoverTyp, hoverObj, 1, 1, false, nil; platform.window:invalidate(); return end
    else
        if menuTyp == "knoten" then
            local k = knoten[menuIndex]
            if menuSeite == 1 then
                if menuZeile == 3 then if k.last_m == 0 then k.gelenk = not k.gelenk; sys_changed = true end
                elseif menuZeile == 4 then k.lager_x = not k.lager_x; sys_changed = true elseif menuZeile == 5 then k.lager_y = not k.lager_y; sys_changed = true elseif menuZeile == 6 then k.lager_m = not k.lager_m; sys_changed = true
                elseif eingabeModus then local z, s_val = evalInput(eingabeText, true); if z then if menuZeile==1 then k.x=z; sys_changed = true; k.x_str=s_val end; if menuZeile==2 then k.y=z; sys_changed = true; k.y_str=s_val end end; eingabeModus = false else eingabeModus, eingabeText = true, "" end
            elseif menuSeite == 2 then
                if eingabeModus then local z, s_val = evalInput(eingabeText, true); if z then if menuZeile==1 then k.last_x=z; sys_changed = true; k.last_x_str=s_val end; if menuZeile==2 then k.last_y=z; sys_changed = true; k.last_y_str=s_val end; if menuZeile==3 and not k.gelenk then k.last_m=z; sys_changed = true; k.last_m_str=s_val end; if menuZeile==4 then k.last_w=z; sys_changed = true; k.last_w_str=s_val end; if menuZeile==5 then k.winkel=z; sys_changed = true end end; eingabeModus = false elseif not (menuZeile == 3 and k.gelenk) then eingabeModus, eingabeText = true, "" end
            elseif menuSeite == 3 then
                if eingabeModus then local z, s_val = evalInput(eingabeText, true); if z then if menuZeile==1 then k.cx=z; sys_changed = true; k.cx_str=s_val end; if menuZeile==2 then k.cy=z; sys_changed = true; k.cy_str=s_val end; if menuZeile==3 then k.cm=z; sys_changed = true; k.cm_str=s_val end; if menuZeile==4 then k.f_winkel=z; sys_changed = true end end; eingabeModus = false else eingabeModus, eingabeText = true, "" end
            elseif menuSeite == 4 then
                if menuZeile == 1 then menuOffen = false; exportKnotenVerschiebungToTI(menuIndex); platform.window:invalidate(); return
                elseif menuZeile == 9 then exportKnotenToTI(menuIndex); menuOffen = false; platform.window:invalidate(); return end
            end
        elseif menuTyp == "stab" then
            local s = staebe[menuIndex]
            if menuSeite == 5 or menuSeite == 6 or (menuSeite == 7 and menuZeile ~= 7) then return end
            if menuSeite == 2 then if menuZeile == 2 then s.gx_proj = not s.gx_proj; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 4 then s.gy_proj = not s.gy_proj; sys_changed = true; platform.window:invalidate(); return end
            elseif menuSeite == 4 then
                if menuZeile == 1 then s.gelenk_A = not s.gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 2 then s.gelenk_B = not s.gelenk_B; sys_changed = true; platform.window:invalidate(); return end
                if menuZeile == 3 then s.n_gelenk_A = not s.n_gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 4 then s.n_gelenk_B = not s.n_gelenk_B; sys_changed = true; platform.window:invalidate(); return end
                if menuZeile == 5 then s.q_gelenk_A = not s.q_gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 6 then s.q_gelenk_B = not s.q_gelenk_B; sys_changed = true; platform.window:invalidate(); return end
            elseif menuSeite == 7 then if menuZeile == 7 then exportStabToTI(menuIndex); menuOffen = false; platform.window:invalidate(); return end end
            -- Seite 1: Zeile 2 biegesteif, Zeile 4 dehnsteif umschalten; EI bzw. EA sind dann gesperrt
            local umgeschaltet = false
            if menuSeite == 1 and not eingabeModus then
                if menuZeile == 2 then s.biegesteif = not s.biegesteif; sys_changed = true; umgeschaltet = true
                elseif menuZeile == 4 then s.dehnsteif = not s.dehnsteif; sys_changed = true; umgeschaltet = true
                elseif (menuZeile == 1 and s.biegesteif) or (menuZeile == 3 and s.dehnsteif) then platform.window:invalidate(); return end
            end

            if umgeschaltet then
                -- keine Eingabe oeffnen
            elseif eingabeModus then
                local z, s_val = evalInput(eingabeText, true)
                if z then
                    if menuSeite == 1 then if menuZeile==1 and z > 0 then s.EI=z; sys_changed = true; s.EI_str=s_val end; if menuZeile==3 and z > 0 then s.EA=z; sys_changed = true; s.EA_str=s_val; s.EA_manuell = true end; if menuZeile==8 then s.bogen_r=z; sys_changed = true; s.bogen_r_str=s_val end
                    elseif menuSeite == 3 then if menuZeile==1 then s.q_A=z; sys_changed = true; s.q_A_str=s_val end; if menuZeile==2 then s.q_B=z; sys_changed = true; s.q_B_str=s_val end; if menuZeile==3 then s.n_A=z; sys_changed = true; s.n_A_str=s_val end; if menuZeile==4 then s.n_B=z; sys_changed = true; s.n_B_str=s_val end; if menuZeile==5 then s.To=z; sys_changed = true; s.To_str=s_val end; if menuZeile==6 then s.Tu=z; sys_changed = true; s.Tu_str=s_val end; if menuZeile==7 then s.alpha=z; sys_changed = true; s.alpha_str=s_val end; if menuZeile==8 then s.h=z; sys_changed = true; s.h_str=s_val end end
                end
                
                if menuSeite == 1 and (menuZeile >= 5 and menuZeile <= 7) then
                    if menuZeile == 5 then
                        s.q_str = neuCasText(eingabeText)
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.q = check_num else s.q = 0; sys_changed = true end
                    elseif menuZeile == 6 then
                        s.n_str = neuCasText(eingabeText)
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.n = check_num else s.n = 0; sys_changed = true end
                    elseif menuZeile == 7 then
                        s.m_str = neuCasText(eingabeText)
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.m = check_num else s.m = 0; sys_changed = true end
                    end
                elseif menuSeite == 2 and (menuZeile == 1 or menuZeile == 3) then
                    if menuZeile == 1 then
                        s.gx_str = neuCasText(eingabeText)
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.gx = check_num else s.gx = 0; sys_changed = true end
                    elseif menuZeile == 3 then
                        s.gy_str = neuCasText(eingabeText)
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.gy = check_num else s.gy = 0; sys_changed = true end
                    end
                end
                
                eingabeModus = false
            else eingabeModus, eingabeText = true, "" end
        elseif menuTyp == "pvv_knoten" then
            local k = knoten[menuIndex]
            pvvBackupSystem()
            if menuZeile == 1 and k.lager_x then k.lager_x = false; pvv_released_binding = {type="lager_x", node=menuIndex}
            elseif menuZeile == 2 and k.lager_y then k.lager_y = false; pvv_released_binding = {type="lager_y", node=menuIndex}
            elseif menuZeile == 3 and k.lager_m then k.lager_m = false; pvv_released_binding = {type="lager_m", node=menuIndex}
            elseif menuZeile == 4 and not k.gelenk then
                local rod_count = 0
                for _, s in ipairs(staebe) do if s.k1 == menuIndex or s.k2 == menuIndex then rod_count = rod_count + 1 end end
                if rod_count == 2 then
                    k.gelenk = true
                    pvv_released_binding = {type="knoten_gelenk", node=menuIndex}
                else
                    pvvRestoreSystem()
                    return
                end
            else 
                pvvRestoreSystem()
                return 
            end
            
            menuOffen = false
            pvvModus = false
            in_pvv_release = true
            buildPolplan()
            calcKinematicStates()
            ansichtsModus = "V"
            pvvPrepareCAS()
        elseif menuTyp == "pvv_stab" then
            local s = staebe[menuIndex]
            pvvBackupSystem()
            if menuZeile == 1 and not s.gelenk_A then s.gelenk_A = true; pvv_released_binding = {type="m_gelenk", stab=menuIndex, endA=true}
            elseif menuZeile == 2 and not s.gelenk_B then s.gelenk_B = true; pvv_released_binding = {type="m_gelenk", stab=menuIndex, endA=false}
            elseif menuZeile == 3 and not s.n_gelenk_A then s.n_gelenk_A = true; pvv_released_binding = {type="n_gelenk", stab=menuIndex, endA=true}
            elseif menuZeile == 4 and not s.n_gelenk_B then s.n_gelenk_B = true; pvv_released_binding = {type="n_gelenk", stab=menuIndex, endA=false}
            elseif menuZeile == 5 and not s.q_gelenk_A then s.q_gelenk_A = true; pvv_released_binding = {type="q_gelenk", stab=menuIndex, endA=true}
            elseif menuZeile == 6 and not s.q_gelenk_B then s.q_gelenk_B = true; pvv_released_binding = {type="q_gelenk", stab=menuIndex, endA=false}
            else 
                pvvRestoreSystem()
                return 
            end
            
            menuOffen = false
            pvvModus = false
            in_pvv_release = true
            buildPolplan()
            calcKinematicStates()
            ansichtsModus = "V"
            pvvPrepareCAS()
            platform.window:invalidate()
        elseif menuTyp == "obermenue" then
            if menuSeite == 1 then
                if menuZeile == 1 or menuZeile == 2 or menuZeile == 3 then
                    if eingabeModus then
                        eingabeModus = false
                        if menuZeile == 1 then local v, s_val = evalInput(eingabeText, true); if v and v > 0 then rasterMass = v; sys_changed = true; rasterMass_str = s_val end
                        elseif menuZeile == 2 then local v, s_val = evalInput(eingabeText, true); if v and v > 0 then defEA = v; sys_changed = true; defEA_str = s_val; for _, s in ipairs(staebe) do s.EA = defEA; s.EA_str = s_val; s.EA_manuell = nil end end
                        elseif menuZeile == 3 then local v, s_val = evalInput(eingabeText, true); if v and v > 0 then defEI = v; sys_changed = true; defEI_str = s_val; for _, s in ipairs(staebe) do s.EI = defEI; s.EI_str = s_val end end
                        end
                        if starteBerechnung then starteBerechnung() end
                    else eingabeModus, eingabeText = true, "" end
                else
                    if menuZeile == 4 then defEA, defEI = 1e8, 1e8; sys_changed = true; defEA_str, defEI_str = "1e8", "1e8"; for _, s in ipairs(staebe) do s.EA = defEA; s.EI = defEI; s.EA_str = defEA_str; s.EI_str = defEI_str; s.EA_manuell = nil end; menuOffen = false
                    elseif menuZeile == 5 then autoKGV = not autoKGV; if not autoKGV then KGV_Zustand = -1; applyKGVZustand(-1); if #knoten > 0 then rechneAktuellesSystem() end end; platform.window:invalidate()
                    elseif menuZeile == 6 then zeigeN = not zeigeN; platform.window:invalidate()
                    elseif menuZeile == 7 then schnittAnzeigeModus = (schnittAnzeigeModus == "Hover") and "Start&End" or "Hover"; platform.window:invalidate()
                    elseif menuZeile == 8 then 
                        fachwerkModus = not fachwerkModus; sys_changed = true; 
                        if fachwerkModus then for _, k in ipairs(knoten) do k.gelenk = true end end
                        if starteBerechnung then starteBerechnung() end; 
                        platform.window:invalidate()
                    elseif menuZeile == 9 then zeigeMaxWerte = not zeigeMaxWerte; platform.window:invalidate()
                    end

                end
            elseif menuSeite == 2 then
                if menuZeile >= 1 and menuZeile <= 9 then
                    if menuZeile == 1 then exportAllToTI()
                    elseif menuZeile == 2 then exportBiegelinienToTI()
                    elseif menuZeile == 3 then exportULinienToTI()
                    elseif menuZeile == 4 then exportKGVToTI()
                    elseif menuZeile == 5 then exportArbeitssatzToTI()
                    elseif menuZeile == 6 then exportSchnittkraefteToTI()
                    elseif menuZeile == 7 then exportLGSMatrixToTI()
                    elseif menuZeile == 8 then neuShowMessage("Menue: Biegelinie Rand-LGS"); exportBiegelinienNeuToTI()
                    elseif menuZeile == 9 then neuShowMessage("Menue: Laengslinie Rand-LGS"); exportULinienNeuToTI() end
                    menuOffen = false; platform.window:invalidate()
                end                
            elseif menuSeite == 3 then
                if menuZeile == 5 then zeigeBemassung = not zeigeBemassung; platform.window:invalidate()
                elseif menuZeile == 7 then
                    zahlenFormat = (zahlenFormat % 3) + 1
                    -- die symbolischen Beschriftungen stecken in den Stabdaten: neu rechnen
                    if symbolischer_modus and systemBerechnet and starteBerechnung then starteBerechnung() end
                    platform.window:invalidate()
                elseif menuZeile == 8 then zeigeMaxWerte = not zeigeMaxWerte; platform.window:invalidate()
                elseif menuZeile == 9 then rasterPunkte = ((rasterPunkte or 1) + 1) % 3; platform.window:invalidate()
                elseif eingabeModus then
                    eingabeModus = false
                    if menuZeile == 1 then local v = evalInput(eingabeText); if v and v > 0 then casToleranz = math.floor(v) end
                    elseif menuZeile == 2 then local v = evalInput(eingabeText); if v and v > 1 then ptsBiegelinie = math.floor(v); if starteBerechnung then starteBerechnung() end end
                    elseif menuZeile == 3 then local v = evalInput(eingabeText); if v and v > 0 then zoomNormal = v end
                    elseif menuZeile == 4 then local v = evalInput(eingabeText); if v and v > 0 then zoomExplosion = v end
                    elseif menuZeile == 6 then local v = evalInput(eingabeText); if v and v > 2 and v <= 100 then bogenSegmente = math.floor(v); if starteBerechnung then starteBerechnung() end end
                    end
                else eingabeModus, eingabeText = true, "" end
            elseif menuSeite == 4 then
                if menuZeile == 1 then
                    polstrahlModus = ((polstrahlModus or 1) + 1) % 3
                    platform.window:invalidate()
                elseif menuZeile == 2 and eingabeModus then
                    eingabeModus = false
                    local v = evalInput(eingabeText)
                    if v and v > 0 then verlaufSkalierung = v end
                elseif menuZeile == 2 then
                    eingabeModus, eingabeText = true, ""
                elseif menuZeile == 3 then
                    randDehnstarr = not randDehnstarr
                    sys_changed = true
                    platform.window:invalidate()
                elseif menuZeile == 4 then
                    randStarrDirekt = not randStarrDirekt
                    platform.window:invalidate()
                elseif menuZeile == 5 or menuZeile == 6 then
                    -- System speichern als / System oeffnen: Nummer eingeben, Variable system<Nr>
                    if eingabeModus then
                        eingabeModus = false
                        local nr = tonumber(eingabeText)
                        if nr and nr >= 0 and nr == math.floor(nr) and nr < 1e6 then
                            menuOffen = false
                            if menuZeile == 5 then speichereSystem(nr) else oeffneSystem(nr) end
                        else
                            zeigeMeldung("Bitte eine ganze Zahl eingeben (z. B. 3 fuer system3).", "System")
                        end
                    else eingabeModus, eingabeText = true, "" end
                elseif menuZeile == 7 then
                    -- Variablen des Skripts loeschen: erstes Enter fragt nach, das zweite loescht
                    if varLoeschFrage then
                        varLoeschFrage = false
                        loescheSkriptVariablen()
                        menuOffen = false
                        zeigeMeldung("Alle Variablen des Skripts geloescht (Exporte wie wneu, randbed, lgs, ux_k ...). Gespeicherte Systeme (system<Nr>) und eigene Variablen bleiben.", "Variablen loeschen")
                    else
                        varLoeschFrage = true
                    end
                    platform.window:invalidate()
                end
            end
        end
    end
    if sys_changed then
        systemBerechnet = false
        updateAlleLasten()
    end 
    platform.window:invalidate()
end

function on.arrowKey(key)
    varLoeschFrage = false   -- Zeile verlassen: Nachfrage "Variablen loeschen" verfaellt
    -- zu lange gelbe Box: hoch/runter blaettert zeilenweise durch den Text
    if hinweisBoxScrollbar and not menuOffen and not eingabeModus and (key == "up" or key == "down") then
        hinweisScroll = math.max(0, math.min(hinweisScrollMax, hinweisScroll + ((key == "down") and 1 or -1)))
        platform.window:invalidate()
        return
    end
    if menuOffen and not eingabeModus then
        if menuTyp == "knoten" then 
            if not isKinematic then
                if key == "left" then if menuSeite > 1 then menuSeite=menuSeite-1; menuZeile=1 else menuSeite=4; menuZeile=1 end elseif key == "right" then if menuSeite < 4 then menuSeite=menuSeite+1; menuZeile=1 else menuSeite=1; menuZeile=1 end end
            end
        elseif menuTyp == "stab" then 
            if not isKinematic then
                if key == "left" then if menuSeite > 1 then menuSeite=menuSeite-1; menuZeile=1 else menuSeite=7; menuZeile=1 end elseif key == "right" then if menuSeite < 7 then menuSeite=menuSeite+1; menuZeile=1 else menuSeite=1; menuZeile=1 end end 
            end
        elseif menuTyp == "obermenue" then if key == "left" then if menuSeite > 1 then menuSeite=menuSeite-1; menuZeile=1 else menuSeite=4; menuZeile=1 end elseif key == "right" then if menuSeite < 4 then menuSeite=menuSeite+1; menuZeile=1 else menuSeite=1; menuZeile=1 end end end
        
        local maxZ = getMenuMaxZeile()
        if menuZeile < 1 then menuZeile = 1 elseif menuZeile > maxZ then menuZeile = maxZ end
        
        if not (isKinematic and (menuTyp == "knoten" or menuTyp == "stab")) then
            if key == "up" and menuZeile > 1 then menuZeile = menuZeile - 1 elseif key == "down" and menuZeile < maxZ then menuZeile = menuZeile + 1 end
        end
        platform.window:invalidate()
    elseif not menuOffen and not eingabeModus then
        if ansichtsModus == "L" then
            local p = 30
            if not lgs_scroll_y then lgs_scroll_y = 0 end
            if not lgs_scroll_x then lgs_scroll_x = 0 end
            if key == "up" then lgs_scroll_y = lgs_scroll_y + p 
            elseif key == "down" then lgs_scroll_y = lgs_scroll_y - p 
            elseif key == "left" then lgs_scroll_x = lgs_scroll_x + p 
            elseif key == "right" then lgs_scroll_x = lgs_scroll_x - p 
            end
            if lgs_scroll_y > 0 then lgs_scroll_y = 0 end
            if lgs_scroll_x > 0 then lgs_scroll_x = 0 end
            platform.window:invalidate()
        else
            local p = 20; if key == "up" then offsetY = offsetY + p elseif key == "down" then offsetY = offsetY - p elseif key == "left" then offsetX = offsetX + p elseif key == "right" then offsetX = offsetX - p end; updateHover(); platform.window:invalidate()
        end
    end
end

-- Alles loeschen; on.clearKey fragt vorher nach (loeschFrage), damit nichts versehentlich verschwindet
function loescheAlles()
    loeschFrage = false
    knoten = {}
    staebe = {}
    auswahl = 1
    menuOffen = false
    ansichtsModus = "System"
    warnungKinematisch = false
    warnungStarrBestimmt = false
    KGV_Zustand = -1
    kgv_n = nil
    systemBerechnet = false
    eingabeModus = false
    eingabeText = ""
    platform.window:invalidate()
end

function on.clearKey()
    if #knoten == 0 and #staebe == 0 then loescheAlles(); return end
    loeschFrage = true
    platform.window:invalidate()
end

function on.backspaceKey()
    if eingabeModus then eingabeText = string.sub(eingabeText, 1, -2)
    else
        if hoverTyp == "stab" then table.remove(staebe, hoverObj); updateHover(); systemBerechnet = false
        elseif hoverTyp == "knoten" then
            for i = #staebe, 1, -1 do if staebe[i].k1 == hoverObj or staebe[i].k2 == hoverObj then table.remove(staebe, i) end end
            for i, s in ipairs(staebe) do if s.k1 > hoverObj then s.k1 = s.k1 - 1 end; if s.k2 > hoverObj then s.k2 = s.k2 - 1 end end
            table.remove(knoten, hoverObj); if auswahl == hoverObj then auswahl = nil end; if auswahl and auswahl > hoverObj then auswahl = auswahl - 1 end; updateHover()
            systemBerechnet = false
        end
    end
    platform.window:invalidate()
end

function on.escapeKey()
    varLoeschFrage = false   -- offene Nachfrage "Variablen loeschen" verfaellt
    if loeschFrage then loeschFrage = false; platform.window:invalidate(); return end
    -- Reihenfolge wie auf dem Bildschirm von oben nach unten: Eingabe/Menue, Warnhinweise, dann Modi.
    -- Ein ESC schliesst alle sichtbaren Warnhinweise und tut sonst nichts.
    local warnungOffen = (symbolFehler and symbolFehlerOffen) or warnungKinematisch or warnungStarrBestimmt or meldungText or hinweisOffen
    if warnungOffen and not eingabeModus and not menuOffen then
        symbolFehlerOffen = false; warnungKinematisch = false; warnungStarrBestimmt = false
        if meldungText then meldungText = nil
        elseif hinweisOffen then hinweisOffen = false; hinweisQuittiert = hinweisSig end
        platform.window:invalidate()
        return
    end
    if ansichtsModus == "P" then
        if in_pvv_release then ansichtsModus = "V" elseif pvvModus then ansichtsModus = "System" else ansichtsModus = "System" end
        platform.window:invalidate()
        return
    end
    if eingabeModus then 
        eingabeModus = false 
    elseif menuOffen then 
        menuOffen = false
        if pvvModus and ansichtsModus == "V" then ansichtsModus = "System" end
    elseif pvvPrompt then
        pvvPrompt = false
    elseif pvvModus then
        pvvModus = false
    elseif in_pvv_release then
        pvvRestoreSystem()
        in_pvv_release = false
        pvv_released_binding = nil
        if ansichtsModus == "V" then ansichtsModus = "System" end
        calcKinematicStates()
        if starteBerechnung then starteBerechnung() end
    else auswahl = nil end
    updateHover(); platform.window:invalidate()
end

-- ==========================================
-- 5. BILDSCHIRM ZEICHNEN
-- ==========================================

-- Algorithmus zur iterativen Identifikation von Nullstäben im Fachwerk.
-- Dieser Prozess wird wiederholt, bis in einem Durchlauf kein neuer Nullstab mehr gefunden wird.
-- Logik:
-- 1. unbelasteter Knoten mit 2 Stäben, die nicht auf einer Geraden liegen -> beide Nullstäbe
-- 2. unbelasteter Knoten mit 3 Stäben, wobei 2 auf einer Geraden liegen -> der dritte ist ein Nullstab
-- 3. unbelasteter Knoten mit 2 Stäben, wobei eine Kraft oder ein Rollenlager in Richtung des einen Stabs wirkt -> der andere ist ein Nullstab
findZeroForceMembers = function()
    for _, s in ipairs(staebe) do s.is_zero_force = false end
    
    local function checkUnloaded(s)
        if (s.q or 0) ~= 0 or (s.q_A or 0) ~= 0 or (s.q_B or 0) ~= 0 then return false end
        if (s.n or 0) ~= 0 or (s.n_A or 0) ~= 0 or (s.n_B or 0) ~= 0 then return false end
        if (s.m or 0) ~= 0 then return false end
        if (s.gx or 0) ~= 0 or (s.gy or 0) ~= 0 then return false end
        if (s.To or 0) ~= 0 or (s.Tu or 0) ~= 0 then return false end
        if s.q_str and s.q_str:hasx() then return false end
        if s.n_str and s.n_str:hasx() then return false end
        if s.m_str and s.m_str:hasx() then return false end
        if s.gx_str and s.gx_str:hasx() then return false end
        if s.gy_str and s.gy_str:hasx() then return false end
        return true
    end
    
    local changed = true
    while changed do
        changed = false
        for i, k in ipairs(knoten) do
            local active = {}
            local mem_loaded = false
            for j, s in ipairs(staebe) do
                if not s.is_zero_force and (s.k1 == i or s.k2 == i) then
                    if not checkUnloaded(s) then mem_loaded = true end
                    local dx, dy = 0, 0
                    if s.k1 == i then dx = knoten[s.k2].x - k.x; dy = knoten[s.k2].y - k.y
                    else dx = knoten[s.k1].x - k.x; dy = knoten[s.k1].y - k.y end
                    local L = math.sqrt(dx^2 + dy^2)
                    if L > 0 then table.insert(active, {id=j, ux=dx/L, uy=dy/L}) end
                end
            end
            
            if not mem_loaded then
                local n = #active
                local rad = math.rad(-(k.last_w or 0))
                local Fx = (k.last_x or 0) * math.cos(rad) - (k.last_y or 0) * math.sin(rad)
                local Fy = (k.last_x or 0) * math.sin(rad) + (k.last_y or 0) * math.cos(rad)
                local has_f = (math.abs(Fx) > 1e-4 or math.abs(Fy) > 1e-4)
                local is_fully_sup = (k.lager_x and k.lager_y) or k.lager_m or (k.cx and k.cx>0) or (k.cy and k.cy>0) or (k.cm and k.cm>0)
                local has_roller_y = k.lager_y and not k.lager_x and not is_fully_sup
                local has_roller_x = k.lager_x and not k.lager_y and not is_fully_sup
                local has_sup = k.lager_x or k.lager_y or k.lager_m or (k.cx and k.cx>0) or (k.cy and k.cy>0) or (k.cm and k.cm>0)
                
                local function coll(v1, v2) return math.abs(v1.ux*v2.uy - v1.uy*v2.ux) < 1e-4 end
                
                if n == 1 then
                    if not has_f and not has_sup then
                        staebe[active[1].id].is_zero_force = true; changed = true
                    else
                        local force_vec = nil
                        if has_f and not has_sup then
                            local FL = math.sqrt(Fx^2 + Fy^2)
                            force_vec = {ux = Fx/FL, uy = Fy/FL}
                        elseif not has_f and has_roller_y then
                            local r = math.rad(k.winkel or 0)
                            force_vec = {ux = math.sin(r), uy = math.cos(r)}
                        elseif not has_f and has_roller_x then
                            local r = math.rad(k.winkel or 0)
                            force_vec = {ux = math.cos(r), uy = -math.sin(r)}
                        end
                        if force_vec and not coll(force_vec, active[1]) then
                            staebe[active[1].id].is_zero_force = true; changed = true
                        end
                    end
                elseif n == 2 and not has_f and not has_sup then
                    if not coll(active[1], active[2]) then
                        staebe[active[1].id].is_zero_force = true; staebe[active[2].id].is_zero_force = true; changed = true
                    end
                elseif n == 2 then
                    local force_vec = nil
                    if has_f and not has_sup then
                        local FL = math.sqrt(Fx^2 + Fy^2)
                        force_vec = {ux = Fx/FL, uy = Fy/FL}
                    elseif not has_f and has_roller_y then
                        local r = math.rad(k.winkel or 0)
                        force_vec = {ux = -math.sin(r), uy = math.cos(r)}
                    elseif not has_f and has_roller_x then
                        local r = math.rad(k.winkel or 0)
                        force_vec = {ux = math.cos(r), uy = math.sin(r)}
                    end
                    if force_vec then
                        if coll(force_vec, active[1]) and not coll(force_vec, active[2]) then
                            staebe[active[2].id].is_zero_force = true; changed = true
                        elseif coll(force_vec, active[2]) and not coll(force_vec, active[1]) then
                            staebe[active[1].id].is_zero_force = true; changed = true
                        end
                    end
                elseif n == 3 and not has_f and not has_sup then
                    if coll(active[1], active[2]) and not coll(active[1], active[3]) then
                        staebe[active[3].id].is_zero_force = true; changed = true
                    elseif coll(active[1], active[3]) and not coll(active[1], active[2]) then
                        staebe[active[2].id].is_zero_force = true; changed = true
                    elseif coll(active[2], active[3]) and not coll(active[2], active[1]) then
                        staebe[active[1].id].is_zero_force = true; changed = true
                    end
                end
            end
        end
    end
end

-- ==========================================

-- ==========================================
-- 5. BILDSCHIRM ZEICHNEN
-- ==========================================

-- ==========================================
-- POLPLAN 2.0 (Kinematik)
-- ==========================================
local polplan = { poles = {}, rays = {}, num_disks = 0, fixed = {}, contradictions = {} }


buildPolplan = function()
    local internal_rigid_pairs = {}
    
    -- Der Polplan-Algorithmus gruppiert zunächst starr verbundene Elemente zu "Scheiben"
    -- und berechnet anschließend die Lage der Hauptpole und Relativpole.
    -- Dies geschieht in zwei Durchläufen (Passes):
    -- Pass 1: Erste grobe Zuordnung (Sammeln von implizit starren Verbindungen).
    -- Pass 2: Finale Zuordnung unter Berücksichtigung aller gesammelten Kopplungen.
    local function runPass(isPass1)
        polplan = { poles = {}, rays = {}, is_rigid = {}, contradictions = {}, num_disks = 0, fixed = {} }
        
        -- Union-Find-Datenstruktur zum Gruppieren starrer Elemente
        local parent = {}
        parent[0] = 0
        local function find(i)
            if parent[i] == i then return i end
            parent[i] = find(parent[i])
            return parent[i]
        end
        local function union(i, j)
            local root_i = find(i)
            local root_j = find(j)
            if root_i ~= root_j then
                if root_i == 0 then parent[root_j] = 0
                elseif root_j == 0 then parent[root_i] = 0
                elseif root_i < root_j then parent[root_j] = root_i 
                else parent[root_i] = root_j end
            end
        end

        for i = 1, #staebe do parent[i] = i end

        for i, k in ipairs(knoten) do
            if not k.gelenk then
                local rigid_bars = {}
                for j, s in ipairs(staebe) do
                    if not s.is_cut then
                        local is_rigid_at_node = false
                        if s.k1 == i and not (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A) then is_rigid_at_node = true end
                        if s.k2 == i and not (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B) then is_rigid_at_node = true end
                        if is_rigid_at_node then table.insert(rigid_bars, j) end
                    end
                end
                for j = 2, #rigid_bars do union(rigid_bars[1], rigid_bars[j]) end
            end
            
            if not isPass1 then
                if (k.lager_x and k.lager_y and k.lager_m) or (k.lager_x and k.lager_y and not k.gelenk and k.cm and k.cm > 0) then
                    for j, s in ipairs(staebe) do
                        if not s.is_cut then
                            local has_m = (s.k1 == i and (s.gelenk_A or k.gelenk)) or (s.k2 == i and (s.gelenk_B or k.gelenk))
                            local has_n = (s.k1 == i and s.n_gelenk_A) or (s.k2 == i and s.n_gelenk_B)
                            local has_q = (s.k1 == i and s.q_gelenk_A) or (s.k2 == i and s.q_gelenk_B)
                            if (s.k1 == i or s.k2 == i) and not (has_m or has_n or has_q) then union(0, j) end
                        end
                    end
                end
            end
        end

        if not isPass1 then
            for _, pair in ipairs(internal_rigid_pairs) do
                union(pair.s1, pair.s2)
            end
        end

        local root_mapping = {}
        root_mapping[0] = 0
        local next_id = 1
        for i = 1, #staebe do
            if not staebe[i].is_cut then
                local root = find(i)
                if not root_mapping[root] then
                    root_mapping[root] = next_id
                    next_id = next_id + 1
                end
                staebe[i].scheibe = root_mapping[root]
            else
                staebe[i].scheibe = nil
            end
        end
        polplan.num_disks = next_id - 1

        for i = 0, polplan.num_disks do
            polplan.poles[i] = {}
            polplan.rays[i] = {}
            polplan.is_rigid[i] = {}
            for j = 0, polplan.num_disks do
                polplan.poles[i][j] = {}
                polplan.rays[i][j] = {}
                polplan.is_rigid[i][j] = false
            end
        end

        local function addPole(A, B, type, x_or_dx, y_or_dy, r1, r2)
            if A > B then A, B = B, A end
            if A == B then return false end
            
            if type == "infinite" then
                local len = math.sqrt(x_or_dx*x_or_dx + y_or_dy*y_or_dy)
                if len < 1e-6 then return false end
                x_or_dx, y_or_dy = x_or_dx/len, y_or_dy/len
            end

            for _, p in ipairs(polplan.poles[A][B]) do
                local is_same = false
                if p.type == type then
                    if type == "finite" then
                        if math.abs(p.x - x_or_dx) < 1e-2 and math.abs(p.y - y_or_dy) < 1e-2 then is_same = true end
                    else
                        if math.abs(p.dx*y_or_dy - p.dy*x_or_dx) < 1e-2 then is_same = true end
                    end
                end
                if is_same then return false end
                
                if not polplan.is_rigid[A][B] then
                    polplan.is_rigid[A][B] = true
                    table.insert(polplan.contradictions, {A=A, B=B, msg="Pol-Kollision"})
                end
            end
            
            for _, r in ipairs(polplan.rays[A][B]) do
                if type == "finite" then
                    local dist = math.abs((x_or_dx - r.px)*r.dy - (y_or_dy - r.py)*r.dx)
                    if dist > 1e-2 then
                        if not polplan.is_rigid[A][B] then
                            polplan.is_rigid[A][B] = true
                            table.insert(polplan.contradictions, {A=A, B=B, msg="Pol nicht auf Strahl"})
                        end
                    end
                elseif type == "infinite" then
                    local cross = x_or_dx*r.dy - y_or_dy*r.dx
                    if math.abs(cross) > 1e-2 then
                        if not polplan.is_rigid[A][B] then
                            polplan.is_rigid[A][B] = true
                            table.insert(polplan.contradictions, {A=A, B=B, msg="Strahl-Richtung falsch"})
                        end
                    end
                end
            end

            if #polplan.poles[A][B] >= 3 then return false end
            
            if type == "finite" then
                table.insert(polplan.poles[A][B], {type="finite", x=x_or_dx, y=y_or_dy})
            else
                table.insert(polplan.poles[A][B], {type="infinite", dx=x_or_dx, dy=y_or_dy})
            end
            if r1 then r1.is_useful = true end
            if r2 then r2.is_useful = true end
            return true
        end

        local function addRay(A, B, px, py, dx, dy, is_useful)
            if A > B then A, B = B, A end
            if A == B then return false end
            local len = math.sqrt(dx*dx + dy*dy)
            if len < 1e-6 then return false end
            dx, dy = dx/len, dy/len
            
            for _, p in ipairs(polplan.poles[A][B]) do
                if p.type == "finite" then
                    local dist = math.abs((p.x - px)*dy - (p.y - py)*dx)
                    if dist > 1e-2 then
                        if not polplan.is_rigid[A][B] then
                            polplan.is_rigid[A][B] = true
                            table.insert(polplan.contradictions, {A=A, B=B, msg="Pol nicht auf Strahl"})
                        end
                    end
                elseif p.type == "infinite" then
                    local cross = p.dx*dy - p.dy*dx
                    if math.abs(cross) > 1e-2 then
                        if not polplan.is_rigid[A][B] then
                            polplan.is_rigid[A][B] = true
                            table.insert(polplan.contradictions, {A=A, B=B, msg="Strahl-Richtung falsch"})
                        end
                    end
                end
            end

            for _, r in ipairs(polplan.rays[A][B]) do
                local cross = r.dx*dy - r.dy*dx
                local dist = math.abs((px - r.px)*r.dy - (py - r.py)*r.dx)
                if math.abs(cross) < 1e-2 and dist < 1e-2 then
                    if is_useful then r.is_useful = true end
                    return false
                end
            end
            if #polplan.rays[A][B] >= 4 then return false end
            table.insert(polplan.rays[A][B], {type="ray", px=px, py=py, dx=dx, dy=dy, is_useful=(is_useful==true)})
            return true
        end

        local function getRays(a, b)
            if a > b then a, b = b, a end
            return polplan.rays[a][b] or {}
        end

        for i, k in ipairs(knoten) do
            local connections = {}
            if not isPass1 then
                if k.lager_x and k.lager_y and k.lager_m then
                    table.insert(connections, { id=0, rot=false, trans=nil })
                elseif k.lager_x and k.lager_y then
                    table.insert(connections, { id=0, rot=true, trans=nil })
                elseif k.lager_x or k.lager_y then
                    local nx, ny = 0, 0
                    if k.lager_y then nx, ny = 0, 1 else nx, ny = 1, 0 end
                    if k.winkel and k.winkel ~= 0 then
                        -- Lagerrichtungen wie in der Berechnung und Zeichnung (gegen den Uhrzeigersinn
                        -- gedreht, y nach unten): xi = (cos, -sin), eta = (sin, cos)
                        local rad = math.rad(k.winkel)
                        if k.lager_y then nx, ny = math.sin(rad), math.cos(rad) else nx, ny = math.cos(rad), -math.sin(rad) end
                    end
                    local tx, ty = -ny, nx
                    local rot = true
                    if k.lager_m or (k.cm and k.cm > 0) then rot = false end
                    table.insert(connections, { id=0, rot=rot, trans={x=tx, y=ty} })
                end
            end
            
            for j, s in ipairs(staebe) do
                if not s.is_cut and s.scheibe then
                    if s.k1 == i or s.k2 == i then
                        local s_id = s.scheibe
                        local is_start = (s.k1 == i)
                        local dx = knoten[s.k2].x - knoten[s.k1].x
                        local dy = knoten[s.k2].y - knoten[s.k1].y
                        local len = math.sqrt(dx*dx + dy*dy)
                        if len > 1e-6 then dx, dy = dx/len, dy/len else dx, dy = 1, 0 end
                        
                        local has_m = is_start and (s.gelenk_A or k.gelenk) or (not is_start and (s.gelenk_B or k.gelenk))
                        local has_n = is_start and s.n_gelenk_A or (not is_start and s.n_gelenk_B)
                        local has_q = is_start and s.q_gelenk_A or (not is_start and s.q_gelenk_B)
                        
                        local rot = false; local trans = nil
                        if has_m then rot = true end
                        if has_n then trans = {x=dx, y=dy} end
                        if has_q then trans = {x=-dy, y=dx} end
                        if has_m and has_n then rot = true; trans = {x=dx, y=dy} end
                        if has_m and has_q then rot = true; trans = {x=-dy, y=dx} end
                        
                        local found = false
                        for _, c in ipairs(connections) do
                            if c.id == s_id then found = true; break end
                        end
                        if not found then table.insert(connections, {id=s_id, rot=rot, trans=trans}) end
                    end
                end
            end
            
            for a = 1, #connections do
                for b = a+1, #connections do
                    local cA, cB = connections[a], connections[b]
                    if cA.id ~= cB.id then
                        if not cA.trans and not cB.trans then
                            addPole(cA.id, cB.id, "finite", k.x, k.y)
                        elseif cA.trans and not cB.trans then
                            if cA.rot or cB.rot then
                                addRay(cA.id, cB.id, k.x, k.y, -cA.trans.y, cA.trans.x, true)
                            else
                                addPole(cA.id, cB.id, "infinite", -cA.trans.y, cA.trans.x)
                            end
                        elseif not cA.trans and cB.trans then
                            if cA.rot or cB.rot then
                                addRay(cA.id, cB.id, k.x, k.y, -cB.trans.y, cB.trans.x, true)
                            else
                                addPole(cA.id, cB.id, "infinite", -cB.trans.y, cB.trans.x)
                            end
                        end
                    end
                end
            end
        end

        local changed = true
        local max_iters = 10

        local function getPoles(a, b)
            if a > b then a, b = b, a end
            return polplan.poles[a][b] or {}
        end

        while changed and max_iters > 0 do
            changed = false
            max_iters = max_iters - 1

            for i = 0, polplan.num_disks do
                for j = i+1, polplan.num_disks do
                    for k = j+1, polplan.num_disks do
                        local pairs = {{i,j,k}, {i,k,j}, {j,i,k}}
                        for _, p in ipairs(pairs) do
                            local a, b, c = p[1], p[2], p[3]
                            local polesAB = getPoles(a, b)
                            local polesBC = getPoles(b, c)

                            for _, p1 in ipairs(polesAB) do
                                for _, p2 in ipairs(polesBC) do
                                    if p1.type == "finite" and p2.type == "finite" then
                                        local dx, dy = p2.x - p1.x, p2.y - p1.y
                                        if math.sqrt(dx*dx + dy*dy) > 1e-4 then
                                            if addRay(a, c, p1.x, p1.y, dx, dy, false) then changed = true end
                                        end
                                    elseif p1.type == "finite" and p2.type == "infinite" then
                                        if addRay(a, c, p1.x, p1.y, p2.dx, p2.dy, false) then changed = true end
                                    elseif p1.type == "infinite" and p2.type == "finite" then
                                        if addRay(a, c, p2.x, p2.y, p1.dx, p1.dy, false) then changed = true end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            for i = 0, polplan.num_disks do
                for j = i+1, polplan.num_disks do
                    local rays = polplan.rays[i][j]
                    if #rays >= 2 then
                        for a = 1, #rays do
                            for b = a+1, #rays do
                                local r1, r2 = rays[a], rays[b]
                                local det = r1.dx * r2.dy - r1.dy * r2.dx
                                if math.abs(det) > 1e-4 then
                                    local s = ((r2.px - r1.px)*r2.dy - (r2.py - r1.py)*r2.dx) / det
                                    local ix, iy = r1.px + s * r1.dx, r1.py + s * r1.dy
                                    if addPole(i, j, "finite", ix, iy, r1, r2) then changed = true end
                                else
                                    if addPole(i, j, "infinite", r1.dx, r1.dy, r1, r2) then changed = true end
                                end
                            end
                        end
                    end
                end
            end
            
            for A = 0, polplan.num_disks do
                for B = A+1, polplan.num_disks do
                    if polplan.is_rigid[A][B] then
                        for C = 0, polplan.num_disks do
                            if C ~= A and C ~= B then
                                local polesA = getPoles(A, C)
                                local polesB = getPoles(B, C)
                                for _, p in ipairs(polesA) do
                                    if addPole(B, C, p.type, p.x or p.dx, p.y or p.dy) then changed = true end
                                end
                                for _, p in ipairs(polesB) do
                                    if addPole(A, C, p.type, p.x or p.dx, p.y or p.dy) then changed = true end
                                end
                                local raysA = getRays(A, C)
                                local raysB = getRays(B, C)
                                for _, r in ipairs(raysA) do
                                    if addRay(B, C, r.px, r.py, r.dx, r.dy, r.is_useful) then changed = true end
                                end
                                for _, r in ipairs(raysB) do
                                    if addRay(A, C, r.px, r.py, r.dx, r.dy, r.is_useful) then changed = true end
                                end
                            end
                        end
                    end
                end
            end
        end

        if isPass1 then
            local disk_to_rods = {}
            for i = 1, #staebe do
                local d = staebe[i].scheibe
                if d then
                    if not disk_to_rods[d] then disk_to_rods[d] = {} end
                    table.insert(disk_to_rods[d], i)
                end
            end
            for A = 1, polplan.num_disks do
                for B = A+1, polplan.num_disks do
                    if polplan.is_rigid[A][B] then
                        local rodA = disk_to_rods[A] and disk_to_rods[A][1]
                        local rodB = disk_to_rods[B] and disk_to_rods[B][1]
                        if rodA and rodB then table.insert(internal_rigid_pairs, {s1=rodA, s2=rodB}) end
                    end
                end
            end
        else
            polplan.display_scheibe = {}
            local r_parent = {}
            for i = 0, polplan.num_disks do r_parent[i] = i end
            local function findR(i)
                if r_parent[i] == i then return i end
                r_parent[i] = findR(r_parent[i])
                return r_parent[i]
            end
            local function unionR(i, j)
                local rI = findR(i)
                local rJ = findR(j)
                if rI ~= rJ then
                    if rI == 0 then r_parent[rJ] = rI
                    elseif rJ == 0 then r_parent[rI] = rJ
                    elseif rI < rJ then r_parent[rJ] = rI
                    else r_parent[rI] = rJ end
                end
            end
            for A = 0, polplan.num_disks do
                for B = A+1, polplan.num_disks do
                    if polplan.is_rigid[A][B] then unionR(A, B) end
                end
            end
            for i = 1, polplan.num_disks do
                local rep = findR(i)
                if rep ~= 0 then
                    polplan.display_scheibe[i] = rep
                else
                    polplan.display_scheibe[i] = i
                    polplan.fixed[i] = true
                end
            end
        end
    end
runPass(true)
    runPass(false)
end
calcKinematicStates = function()
    -- 1. Polplan berechnen: Ermittelt alle absoluten und relativen Hauptpole des Systems.
    buildPolplan()
    if polplan.num_disks == 0 then
        kinematic_states = nil
        kinematic_states_staebe = nil
        kinematic_seed_info = nil
        kinematic_max_disp = 1
        return
    end

    -- states speichert die kinematischen Zustände (Verschiebung vx, vy oder Rotation phi um cx, cy) jeder Scheibe
    local states = {}
    local queue = {}
    local visited = {}
    
    -- 2. "Seed" (Startscheibe) auswählen und Kinematik propagieren
    local seeds = {}
    for i = 1, polplan.num_disks do
        if not polplan.fixed[i] then
            local score = 0
            local abs_poles = polplan.poles[0][i]
            if abs_poles and #abs_poles > 0 then
                local p = abs_poles[1]
                if p.type == "finite" then
                    local on_node = false
                    for _, s in ipairs(staebe) do
                        if s.scheibe == i then
                            local k1, k2 = knoten[s.k1], knoten[s.k2]
                            if (math.abs(k1.x - p.x) < 1e-4 and math.abs(k1.y - p.y) < 1e-4) or
                               (math.abs(k2.x - p.x) < 1e-4 and math.abs(k2.y - p.y) < 1e-4) then
                                on_node = true
                                break
                            end
                        end
                    end
                    if on_node then score = 4 else score = 3 end
                else
                    score = 1
                end
            else
                score = 2
            end
            table.insert(seeds, {idx = i, score = score})
        end
    end
    table.sort(seeds, function(a, b) return a.score > b.score end)

    local function trySeed(seed_idx, ignore_contradiction)
        local tmp_states = {}
        local queue = {}
        local visited = {}
        
        local abs_poles = polplan.poles[0][seed_idx]
        if abs_poles and #abs_poles > 0 then
            local p = abs_poles[1]
            if p.type == "finite" then
                tmp_states[seed_idx] = { type = "rot", cx = p.x, cy = p.y, phi = -1 }
            else
                local L = math.sqrt(p.dx^2 + p.dy^2)
                tmp_states[seed_idx] = { type = "trans", vx = -p.dy/L, vy = p.dx/L }
            end
        else
            tmp_states[seed_idx] = { type = "trans", vx = 1, vy = 0 }
        end
        table.insert(queue, seed_idx)
        visited[seed_idx] = true
        
        local head = 1
        while head <= #queue do
            local A = queue[head]; head = head + 1
            local stateA = tmp_states[A]
            
            for B = 1, polplan.num_disks do
                if not visited[B] and not polplan.fixed[B] then
                    local a_min, b_max = math.min(A, B), math.max(A, B)
                    local p_rel_list = polplan.poles[a_min][b_max]
                    
                    if p_rel_list and #p_rel_list > 0 then
                        local pAB = p_rel_list[1]
                        if pAB.type == "finite" then
                            local v_x, v_y = 0, 0
                            if stateA.type == "rot" then
                                v_x = -stateA.phi * (pAB.y - stateA.cy)
                                v_y = stateA.phi * (pAB.x - stateA.cx)
                            elseif stateA.type == "trans" then
                                v_x = stateA.vx
                                v_y = stateA.vy
                            end
                            
                            local p0B = polplan.poles[0][B] and polplan.poles[0][B][1]
                            if p0B then
                                if p0B.type == "finite" then
                                    if math.abs(pAB.x - p0B.x) < 1e-4 and math.abs(pAB.y - p0B.y) < 1e-4 then
                                        if (math.abs(v_x) > 1e-4 or math.abs(v_y) > 1e-4) and not ignore_contradiction then
                                            return nil -- Widerspruch!
                                        end
                                        tmp_states[B] = { type = "rot", cx = p0B.x, cy = p0B.y, phi = 0 }
                                    else
                                        local phiB = 0
                                        if math.abs(pAB.x - p0B.x) > math.abs(pAB.y - p0B.y) then
                                            phiB = v_y / (pAB.x - p0B.x)
                                        else
                                            if math.abs(pAB.y - p0B.y) > 1e-6 then phiB = -v_x / (pAB.y - p0B.y) end
                                        end
                                        tmp_states[B] = { type = "rot", cx = p0B.x, cy = p0B.y, phi = phiB }
                                    end
                                else
                                    local dir_x, dir_y = -p0B.dy, p0B.dx
                                    local scaleB = 0
                                    if math.abs(dir_x) > math.abs(dir_y) then
                                        scaleB = v_x / dir_x
                                    else
                                        if math.abs(dir_y) > 1e-6 then scaleB = v_y / dir_y end
                                    end
                                    tmp_states[B] = { type = "trans", vx = scaleB * dir_x, vy = scaleB * dir_y }
                                end
                            else
                                tmp_states[B] = { type = "trans", vx = v_x, vy = v_y }
                            end
                            
                            visited[B] = true
                            table.insert(queue, B)
                        elseif pAB.type == "infinite" then
                            local p0B = polplan.poles[0][B] and polplan.poles[0][B][1]
                            if p0B then
                                if p0B.type == "finite" then
                                    tmp_states[B] = { type = "rot", cx = p0B.x, cy = p0B.y, phi = stateA.phi or 0 }
                                else
                                    local dir_x, dir_y = -p0B.dy, p0B.dx
                                    local vAx = stateA.vx or 0
                                    local vAy = stateA.vy or 0
                                    local scaleB = 0
                                    local denom = dir_x * pAB.dx + dir_y * pAB.dy
                                    if math.abs(denom) > 1e-6 then
                                        scaleB = (vAx * pAB.dx + vAy * pAB.dy) / denom
                                    end
                                    tmp_states[B] = { type = "trans", vx = scaleB * dir_x, vy = scaleB * dir_y }
                                end
                            else
                                tmp_states[B] = { type = "rot", cx = 0, cy = 0, phi = stateA.phi or 0 }
                            end
                            
                            visited[B] = true
                            table.insert(queue, B)
                        end
                    end
                end
            end
        end
        return tmp_states
    end

    local best_seed = nil
    for _, sd in ipairs(seeds) do
        local st = trySeed(sd.idx, false)
        if st then
            states = st
            best_seed = sd.idx
            break
        end
    end
    
    if not best_seed and #seeds > 0 then
        best_seed = seeds[1].idx
        states = trySeed(best_seed, true)
    end
    
    if best_seed then
        local abs_poles = polplan.poles[0][best_seed]
        if abs_poles and #abs_poles > 0 then
            local p = abs_poles[1]
            if p.type == "finite" then
                kinematic_seed_info = { disk = best_seed, is_rot = true, cx = p.x, cy = p.y }
            else
                kinematic_seed_info = { disk = best_seed, is_rot = false }
            end
        else
            kinematic_seed_info = { disk = best_seed, is_rot = false }
        end
    end

    -- Share calculated states within rigid bodies
    local rep_states = {}
    for i = 1, polplan.num_disks do
        local rep = polplan.display_scheibe[i]
        if rep and states[i] then
            rep_states[rep] = states[i]
        end
    end
    for i = 1, polplan.num_disks do
        local rep = polplan.display_scheibe[i]
        if rep and not states[i] and rep_states[rep] then
            states[i] = rep_states[rep]
        end
    end

    -- 5. Kinematische Zustände der Knoten berechnen:
    -- Wir durchlaufen alle Knoten und weisen ihnen die Verschiebung der Scheibe zu, an der sie befestigt sind.
    -- Knoten, die ein Gelenk haben, übernehmen die Verschiebung einer angeschlossenen Scheibe, die KEIN Gelenk hat (da sie starr mit dieser verbunden sind).
    kinematic_disk_states = states
    -- global fuer den Arbeitssatz-Export: der steht in der Datei vor der zweiten Deklaration von
    -- polplan und saehe sonst nur die erste, leere Tabelle
    pvvPolplan = polplan
    kinematic_states = {}
    kinematic_states_staebe = {}
    kinematic_max_disp = 1
    local max_disp = 0
    for i, k in ipairs(knoten) do
        local u_x, u_y, u_phi = 0, 0, 0
        local u_scheibe = nil
        local assigned = false
        
        for _, s in ipairs(staebe) do
            if s.k1 == i or s.k2 == i then
                local is_k1 = (s.k1 == i)
                local has_hinge = is_k1 and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A) or (not is_k1 and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B))
                if s.scheibe and not states[s.scheibe] and not has_hinge then
                    -- Knoten haengt ohne Gelenk an einer festen Scheibe: er bewegt sich nicht
                    -- (auch wenn ein anderer Stab ueber ein N- oder Q-Gelenk angeschlossen ist)
                    u_x, u_y, u_phi, u_scheibe = 0, 0, 0, nil
                    assigned = false
                    break
                end
                if s.scheibe and states[s.scheibe] then
                    if not assigned or not has_hinge then
                        local d = states[s.scheibe]
                        if d.type == "rot" then
                            -- Verschiebung durch Rotation u = phi * r (mit 90° gedrehtem Hebelarm)
                            u_x = -d.phi * (k.y - d.cy)
                            u_y = d.phi * (k.x - d.cx)
                            u_phi = d.phi
                        elseif d.type == "trans" then
                            -- Reine Translation
                            u_x = d.vx
                            u_y = d.vy
                            u_phi = 0
                        end
                        u_scheibe = s.scheibe
                        assigned = true
                        if not has_hinge then break end
                    end
                end
            end
        end
        
        if assigned then
            kinematic_states[i] = { ux = u_x, uy = u_y, phi = u_phi, scheibe = u_scheibe }
            local dist = math.sqrt(u_x^2 + u_y^2)
            if dist > max_disp then max_disp = dist end
        else
            kinematic_states[i] = { ux = 0, uy = 0, phi = 0, scheibe = nil }
        end
    end

    for i, s in ipairs(staebe) do
        local u1x, u1y, u2x, u2y = 0, 0, 0, 0
        if s.scheibe and states[s.scheibe] then
            local d = states[s.scheibe]
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            if d.type == "rot" then
                u1x = -d.phi * (k1.y - d.cy)
                u1y = d.phi * (k1.x - d.cx)
                u2x = -d.phi * (k2.y - d.cy)
                u2y = d.phi * (k2.x - d.cx)
            elseif d.type == "trans" then
                u1x, u1y = d.vx, d.vy
                u2x, u2y = d.vx, d.vy
            end
        end
        kinematic_states_staebe[i] = { u1x = u1x, u1y = u1y, u2x = u2x, u2y = u2y }
        local d1 = math.sqrt(u1x^2 + u1y^2)
        local d2 = math.sqrt(u2x^2 + u2y^2)
        if d1 > max_disp then max_disp = d1 end
        if d2 > max_disp then max_disp = d2 end
    end
    kinematic_max_disp = max_disp
end

getKinematicDisp = function(i)
    if not kinematic_states or not kinematic_states[i] then return 0, 0 end
    return kinematic_states[i].ux, kinematic_states[i].uy
end

getKinematicRot = function(i)
    if not kinematic_states or not kinematic_states[i] then return 0 end
    return -(kinematic_states[i].phi or 0)
end

getKinematicDisp_Stab = function(stabIdx)
    if not kinematic_states_staebe or not kinematic_states_staebe[stabIdx] then
        return 0, 0, 0, 0
    end
    local ks = kinematic_states_staebe[stabIdx]
    return ks.u1x, ks.u1y, ks.u2x, ks.u2y
end

-- NEU: Diese Funktion wird einmalig aufgerufen, wenn der PvV-Modus gestartet wird.
-- Sie bereitet beliebige Lastfunktionen (wie sin(x)) über das TI-Nspire CAS vor.
-- Wir berechnen exakt zwei Konstanten: Die Resultierende (R_cas) und das 
-- statische Moment (S_cas). Dadurch vermeiden wir teure CAS-Aufrufe im 
-- Animations-Loop (60 FPS), was den Rechner andernfalls blockieren würde.
pvvPrepareCAS = function()
    if not math.eval then return end
    for i, s in ipairs(staebe) do
        local k1, k2 = knoten[s.k1], knoten[s.k2]
        local L = math.sqrt((k2.x - k1.x)^2 + (k2.y - k1.y)^2)
        local L_str = string.format("%.4f", L)
        
        -- Querlast q(x)
        if s.q_str and s.q_str:hasx() then
            -- Wir berechnen R_q (Resultierende) und S_q (Flächenmoment 1. Grades bezogen auf k1)
            -- Dies fängt den Edge-Case (R_q = 0) automatisch ab, da wir nicht durch R_q teilen 
            -- müssen, um einen Schwerpunkt zu finden. Die Arbeit ist dann später exakt S_q * phi.
            s.R_q_cas = casToNumber(math.eval("approx(integral("..s.q_str..",x,0,"..L_str.."))")) or 0
            s.S_q_cas = casToNumber(math.eval("approx(integral(("..s.q_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_q_cas = nil; s.S_q_cas = nil
        end
        
        -- Längslast n(x)
        if s.n_str and s.n_str:hasx() then
            s.R_n_cas = casToNumber(math.eval("approx(integral("..s.n_str..",x,0,"..L_str.."))")) or 0
            s.S_n_cas = casToNumber(math.eval("approx(integral(("..s.n_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_n_cas = nil; s.S_n_cas = nil
        end
        
        -- Momentenlast m(x) - hierbei leistet das Gesamtmoment Arbeit an der Verdrehung
        if s.m_str and s.m_str:hasx() then
            s.R_m_cas = casToNumber(math.eval("approx(integral("..s.m_str..",x,0,"..L_str.."))")) or 0
        else
            s.R_m_cas = nil
        end
        
        -- Globale Lasten (gx und gy)
        if s.gx_str and s.gx_str:hasx() then
            local g_str, f = globaleLinienlast(s, "gx")
            s.R_gx_cas = casToNumber(math.eval("approx(integral(("..g_str..")*"..f..",x,0,"..L_str.."))")) or 0
            s.S_gx_cas = casToNumber(math.eval("approx(integral(("..g_str..")*"..f.."*x,x,0,"..L_str.."))")) or 0
        else
            s.R_gx_cas = nil; s.S_gx_cas = nil
        end
        
        if s.gy_str and s.gy_str:hasx() then
            local g_str, f = globaleLinienlast(s, "gy")
            s.R_gy_cas = casToNumber(math.eval("approx(integral(("..g_str..")*"..f..",x,0,"..L_str.."))")) or 0
            s.S_gy_cas = casToNumber(math.eval("approx(integral(("..g_str..")*"..f.."*x,x,0,"..L_str.."))")) or 0
        else
            s.R_gy_cas = nil; s.S_gy_cas = nil
        end
    end
end

-- Zeichnung und Menues des PvV-Modus holen Namen und Werte aus derselben Rechnung wie der Export
-- (exportArbeitssatzToTI("anzeige")), damit sie 1:1 zu w_eq1 und pvv_kin passen. Gemerkt, bis sich
-- der Verschiebungszustand aendert (calcKinematicStates legt dafuer jedes Mal neue Tabellen an).
pvvAnzeigeCache = nil
function pvvAnzeige()
    if not in_pvv_release or not kinematic_disk_states then return nil end
    local c = pvvAnzeigeCache
    if c and c.zustand == kinematic_disk_states and c.bindung == pvv_released_binding
        and c.symb == symbolischer_modus and c.format == zahlenFormat then return c.daten end
    local ok, d = pcall(exportArbeitssatzToTI, "anzeige")
    pvvAnzeigeCache = { zustand = kinematic_disk_states, bindung = pvv_released_binding,
        symb = symbolischer_modus, format = zahlenFormat, daten = (ok and type(d) == "table") and d or nil }
    return pvvAnzeigeCache.daten
end

-- "Name = Wert" eines Weges wie in pvv_kin (Spalte 3); nil, wenn der Export ihn nicht hat
function pvvLabel(name)
    local d = pvvAnzeige()
    local w = d and d.wege[name]
    return w and (name .. " = " .. w.text) or nil
end

-- Beschriftung einer Scheibe: "φ_1 = -2*φ_0", Bezugsscheibe "φ_3 = φ_0", verschobene "δ_2 = ..."
function pvvScheibenText(i)
    local d = pvvAnzeige()
    local z = d and d.scheiben[i]
    if not z then return "φ_" .. i end
    return z.var .. " = " .. z.text
end

function pvvAnimFaktor(pxm)
    return (0.5 * pxm) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
end

-- Wege eines Knotens (Knotenlasten in Lastrichtung, H und V in Lagerrichtung): Pfeil von P - u*e
-- nach P, u = Verschiebung in Richtung e; beschriftet wie pvv_kin
function pvvZeichneKnotenWege(gc, i, px, py, pxm)
    local d = pvvAnzeige()
    if not d then return end
    local ux, uy = getKinematicDisp(i)
    local f = pvvAnimFaktor(pxm)
    for _, w in ipairs(d.reihe) do
        if w.knoten == i and w.ex and w.name ~= "δ_G" then
            local u = (ux * w.ex + uy * w.ey) * f
            local ax, ay = px - w.ex * u, py - w.ey * u
            gc:setColorRGB(200, 0, 200)
            drawArrow(gc, ax, ay, px, py)
            gc:setFont("sansserif", "r", 8)
            gc:drawString(w.name .. " = " .. w.text, ax + 5, ay - 10)
        end
    end
end

-- gegenseitige Verdrehung am geloesten Momentengelenk (φ_G) neben dem Gelenk
function pvvZeichneGelenkWinkel(gc, pxm)
    local b = pvv_released_binding
    if not b or (b.type ~= "m_gelenk" and b.type ~= "knoten_gelenk") then return end
    local lbl = pvvLabel("φ_G")
    if not lbl then return end
    local n = b.node or (b.endA and staebe[b.stab].k1 or staebe[b.stab].k2)
    local ux, uy = getKinematicDisp(n)
    local f = pvvAnimFaktor(pxm)
    gc:setColorRGB(200, 0, 200); gc:setFont("sansserif", "r", 8)
    gc:drawString(lbl, knoten[n].x * pxm + offsetX + ux * f + 20, knoten[n].y * pxm + offsetY + uy * f + 12)
end

-- Scheibe, die sich nur verschiebt: "δ_i = ..." an ihrem ersten Stab
function pvvZeichneVerschiebung(gc, i, pxm)
    local d = pvvAnzeige()
    if not d or not d.scheiben[i] then return end
    for j, s in ipairs(staebe) do
        if s.scheibe == i then
            local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(j)
            local f = pvvAnimFaktor(pxm)
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            gc:setColorRGB(0, 0, 255); gc:setFont("sansserif", "r", 10)
            gc:drawString(pvvScheibenText(i), (k1.x + k2.x) / 2 * pxm + offsetX + (u1x + u2x) / 2 * f + 8,
                (k1.y + k2.y) / 2 * pxm + offsetY + (u1y + u2y) / 2 * f - 22)
            return
        end
    end
end

-- Zeilen des PvV-Menues eines Knotens bzw. Stabes, alles wie im Export: Wege (Spalte 3 von
-- pvv_kin), Drehwinkel der beteiligten Scheiben, Arbeitsanteile (die Terme von w_eq1)
function pvvMenueZeilen(typ, idx)
    local d = pvvAnzeige()
    local zeilen = {}
    if not d then return zeilen end
    -- "(1) * " weg und Klammern um einzelne Namen, aber nicht um Funktionsargumente wie sqrt(2)
    local function kurz(t)
        t = t:gsub("%(1%) %* ", "")
        t = (" " .. t):gsub("([^%w_])%(([%w_%.]+)%)", "%1%2")
        return t:sub(2)
    end
    local function gehoert(e) return (typ == "knoten" and e.knoten == idx) or (typ == "stab" and e.stab == idx) end
    local wege, arbeit, scheiben, gesehen = {}, {}, {}, {}
    local function merke(i)
        if i and d.scheiben[i] and not gesehen[i] then gesehen[i] = true; scheiben[#scheiben + 1] = i end
    end
    if typ == "stab" and staebe[idx] then merke(staebe[idx].scheibe) end
    for _, w in ipairs(d.reihe) do
        if gehoert(w) then
            wege[#wege + 1] = w.name .. " = " .. w.text
            arbeit[#arbeit + 1] = kurz(w.kraftText .. " * " .. w.name)
        end
    end
    for _, m in ipairs(d.momente) do
        if gehoert(m) then arbeit[#arbeit + 1] = kurz(m.text); merke(m.scheibe) end
    end
    if #wege > 0 then
        zeilen[#zeilen + 1] = { "Wege (pvv_kin):", "kopf" }
        for _, t in ipairs(wege) do zeilen[#zeilen + 1] = { t, "weg" } end
    end
    if #scheiben > 0 then
        zeilen[#zeilen + 1] = { "Scheiben:", "kopf" }
        for _, i in ipairs(scheiben) do zeilen[#zeilen + 1] = { pvvScheibenText(i), "scheibe" } end
    end
    if #arbeit > 0 then
        zeilen[#zeilen + 1] = { "Arbeit (Terme von w_eq1):", "kopf" }
        for _, t in ipairs(arbeit) do zeilen[#zeilen + 1] = { t, "arbeit" } end
    end
    return zeilen
end

function pvvMenueHoehe(typ, idx)
    local n = #pvvMenueZeilen(typ, idx)
    return n > 0 and (46 + 14 * n) or 70
end

PVV_MENUE_FARBEN = { kopf = { 0, 0, 0 }, weg = { 200, 0, 200 }, scheibe = { 0, 120, 0 }, arbeit = { 200, 50, 50 } }
function pvvZeichneMenue(gc, typ, idx, b)
    local zeilen = pvvMenueZeilen(typ, idx)
    if #zeilen == 0 then
        gc:setColorRGB(150, 150, 150); gc:setFont("sansserif", "r", 9)
        gc:drawString("Keine Arbeit an " .. (typ == "knoten" and "diesem Knoten" or "diesem Stab"), b - 160, 38)
        return
    end
    local y = 38
    for _, z in ipairs(zeilen) do
        local f = PVV_MENUE_FARBEN[z[2]]
        gc:setColorRGB(f[1], f[2], f[3])
        gc:setFont("sansserif", z[2] == "kopf" and "b" or "r", 8)
        gc:drawString(z[1], b - 160 + (z[2] == "kopf" and 0 or 6), y)
        y = y + 14
    end
end

local function getScreenEdgeIntersection(px, py, dx, dy, b, h)
    local ts = {}
    if math.abs(dx) > 1e-5 then
        local tl = (5 - px) / dx; local yl = py + tl * dy
        if yl >= 5 and yl <= h - 5 then table.insert(ts, tl) end
        local tr = (b - 5 - px) / dx; local yr = py + tr * dy
        if yr >= 5 and yr <= h - 5 then table.insert(ts, tr) end
    end
    if math.abs(dy) > 1e-5 then
        local tt = (5 - py) / dy; local xt = px + tt * dx
        if xt >= 5 and xt <= b - 5 then table.insert(ts, tt) end
        local tb = (h - 5 - py) / dy; local xb = px + tb * dx
        if xb >= 5 and xb <= b - 5 then table.insert(ts, tb) end
    end
    
    if #ts >= 1 then
        local best_x, best_y = px + ts[1]*dx, py + ts[1]*dy
        for i = 2, #ts do
            local ix, iy = px + ts[i]*dx, py + ts[i]*dy
            if iy < best_y then best_x, best_y = ix, iy end
        end
        return best_x, best_y
    end
    return px, py
end
function drawBemassung(gc, custom_pts)
    local use_pts = custom_pts or knoten
    if not custom_pts and (ansichtsModus ~= "System" or not zeigeBemassung) then return end
    if #use_pts < 2 then return end
    
    local x_vals = {}
    local y_vals = {}
    
    for _, k in ipairs(use_pts) do
        if not k.is_virtual then
            local found_x, found_y = false, false
            for _, v in ipairs(x_vals) do if math.abs(v - k.x) < 1e-4 then found_x = true; break end end
            for _, v in ipairs(y_vals) do if math.abs(v - k.y) < 1e-4 then found_y = true; break end end
            if not found_x then table.insert(x_vals, k.x) end
            if not found_y then table.insert(y_vals, k.y) end
        end
    end
    
    table.sort(x_vals)
    table.sort(y_vals)
    
    local b, h = platform.window:width(), platform.window:height()
    
    if #x_vals > 1 then
        local max_y_px = 0
        for _, k in ipairs(use_pts) do
            if not k.is_virtual then
                local py = k.y * pxProMeter + offsetY
                if py > max_y_px then max_y_px = py end
            end
        end
        local dim_y = max_y_px + 45
        if dim_y > h - 15 then dim_y = h - 15 end
        
        gc:setColorRGB(100, 150, 100)
        gc:setPen("thin", "smooth")
        
        local start_x = x_vals[1] * pxProMeter + offsetX
        local end_x = x_vals[#x_vals] * pxProMeter + offsetX
        gc:drawLine(start_x, dim_y, end_x, dim_y)
        
        for i, xv in ipairs(x_vals) do
            local px = xv * pxProMeter + offsetX
            gc:drawLine(px - 4, dim_y + 4, px + 4, dim_y - 4)
            
            if i < #x_vals then
                local next_px = x_vals[i+1] * pxProMeter + offsetX
                local val = math.floor(math.abs(x_vals[i+1] - xv) * 100 + 0.5) / 100
                local text = string.format("%g", val)
                gc:setFont("sansserif", "r", 9)
                local tw = gc:getStringWidth(text)
                gc:drawString(text, (px + next_px)/2 - tw/2, dim_y - 14)
            end
        end
    end
    
    if #y_vals > 1 then
        local min_x_px = b
        for _, k in ipairs(use_pts) do
            if not k.is_virtual then
                local px = k.x * pxProMeter + offsetX
                if px < min_x_px then min_x_px = px end
            end
        end
        local dim_x = min_x_px - 45
        if dim_x < 15 then dim_x = 15 end
        
        gc:setColorRGB(100, 150, 100)
        gc:setPen("thin", "smooth")
        
        local start_y = y_vals[1] * pxProMeter + offsetY
        local end_y = y_vals[#y_vals] * pxProMeter + offsetY
        gc:drawLine(dim_x, start_y, dim_x, end_y)
        
        for i, yv in ipairs(y_vals) do
            local py = yv * pxProMeter + offsetY
            gc:drawLine(dim_x - 4, py + 4, dim_x + 4, py - 4)
            
            if i < #y_vals then
                local next_py = y_vals[i+1] * pxProMeter + offsetY
                local val = math.floor(math.abs(y_vals[i+1] - yv) * 100 + 0.5) / 100
                local text = string.format("%g", val)
                gc:setFont("sansserif", "r", 9)
                local tw = gc:getStringWidth(text)
                gc:drawString(text, dim_x - tw - 6, (py + next_py)/2 - 5)
            end
        end
    end
end

-- ==========================================
-- ==========================================
-- HAUPT-ZEICHENFUNKTION (on.paint)
-- ==========================================
-- Diese Funktion wird bei jedem Frame-Update aufgerufen und zeichnet das gesamte System:
-- Raster, Maßketten, Knoten, Stäbe, Lager, Gelenke, Lasten und Menüs.
-- Sie behandelt auch die verschiedenen Darstellungsmodi (System, Schnittgrößen, Kinematik, Polplan).
-- Resultierende R und statisches Moment S (um den Anfangsknoten) einer Streckenlast.
-- Liegen CAS-Stuetzwerte vor (11 Punkte, sie enthalten die gesamte Last), wird mit Simpson
-- integriert -- das ist fuer lineare und quadratische Lasten exakt. Sonst gilt der klassische
-- Trapezanteil plus der im PvV vorbereitete CAS-Anteil. faktor bildet projizierte Lasten ab
-- (Verhaeltnis von wirksamer zu Stablaenge).
function lastResultierende(pts, L, wA, wB, R_cas, S_cas, faktor)
    faktor = faktor or 1
    if pts and #pts == 11 and L > 1e-9 then
        local h = L / 10
        local R, S = 0, 0
        for j = 1, 11 do
            local g = (j == 1 or j == 11) and 1 or ((j % 2 == 0) and 4 or 2)
            R = R + g * pts[j]
            S = S + g * pts[j] * (j - 1) * h
        end
        return R * h / 3 * faktor, S * h / 3 * faktor
    end
    local R = ((wA + wB) / 2 * L) * faktor + (R_cas or 0)
    local S = ((L^2) / 6 * (wA + 2 * wB)) * faktor + (S_cas or 0)
    return R, S
end

-- Resultierende einer Streckenlast beschriften: im symbolischen Modus der CAS-Term,
-- sonst der Zahlenwert. Die Richtung zeigt der Pfeil, darum steht der Betrag.
function resultierendenLabel(L_phys, L_eff, qs, qa, qb, R_cas, S_cas, R_num, S_num, typ)
    if symbolischer_modus then
        local R_str = processDistLoad_PvV(L_phys, L_eff, qs, qa, qb, R_cas, S_cas, R_num, S_num, typ, true)
        if R_str then return "R = " .. R_str end
    end
    return "R = " .. formatLabel(math.abs(R_num))
end

-- Wirkungslinie einer Resultierenden merken, damit die globale Bemassung ihre Lage zeigt
function merkeResultierende(x, y)
    if not glob_resultant_pts then glob_resultant_pts = {} end
    table.insert(glob_resultant_pts, {x = x, y = y, is_virtual = false})
end

-- Bogen in Bildschirmkoordinaten zwischen (px1, py1) und (px2, py2), wie er gezeichnet wird (fuer
-- bogenPunkt); nil, wenn der Radius kleiner als die halbe Sehne ist
function bogenBildGeometrie(s, px1, py1, px2, py2, skala)
    local dx, dy = px2 - px1, py2 - py1
    local L = math.sqrt(dx^2 + dy^2)
    local R = math.abs(s.bogen_r or 0) * skala
    if L <= 0 or R < L / 2 then return nil end
    return { R = R, sgn = s.bogen_r > 0 and -1 or 1, alpha = 2 * math.asin(math.min(1, L / (2 * R))),
        d = math.sqrt(math.max(0, R^2 - (L / 2)^2)), mx = (px1 + px2) / 2, my = (py1 + py2) / 2, ex = dx / L, ey = dy / L }
end

-- Punkt (Weltkoordinaten) auf der Wirkungslinie einer Resultierenden (Fx, Fy) mit Moment M um den
-- Stabanfang (gegen den Uhrzeigersinn) eines Bogens: Schnitt mit dem Bogen (der Bogenmitte naechste),
-- ohne Schnitt der Fusspunkt des Lots von der Bogenmitte
function bogenWirkungspunkt(s, Fx, Fy, M)
    local g = bogenGeometrie(s, 2)
    local k1 = knoten[s.k1]
    local F = math.sqrt(Fx^2 + Fy^2)
    local fx, fy = Fx / F, Fy / F
    local x0, y0 = k1.x - M / F * fy, k1.y + M / F * fx
    local function abstand(x, y) return (x - x0) * fy - (y - y0) * fx end
    local mx, my = bogenPunkt(g, g.alpha / 2)
    local px, py = mx - abstand(mx, my) * fy, my + abstand(mx, my) * fx
    local best = math.huge
    local n = 40
    local ax, ay = bogenPunkt(g, 0)
    local da = abstand(ax, ay)
    for j = 1, n do
        local bx, by = bogenPunkt(g, g.alpha * j / n)
        local db = abstand(bx, by)
        if (da <= 0 and db >= 0) or (da >= 0 and db <= 0) then
            local f = (da ~= db) and da / (da - db) or 0
            local cx, cy = ax + f * (bx - ax), ay + f * (by - ay)
            local d = (cx - mx)^2 + (cy - my)^2
            if d < best then best, px, py = d, cx, cy end
        end
        ax, ay, da = bx, by, db
    end
    return px, py
end

-- PvV-Ansicht: Resultierende aller Lasten eines Bogens (wie im Arbeitssatz) mit den Wegen
-- δ_s<i>x und δ_s<i>y aus dem Export. (opx1, opy1) = Stabanfang im Bild (mit Verschiebung), die
-- Scheibe ist starr: u(P) = u1 + theta * (-(P-K1)_y, (P-K1)_x). Die Resultierende kommt aus
-- s.bogen_res (updateAlleLasten), nicht aus dem Export: das CAS waere im Zeichenaufruf zu langsam.
function zeichneBogenPvv(gc, s, i, opx1, opy1, skala)
    local r = s.bogen_res
    if not r then return end
    local Fx, Fy, M = r.summe[1], r.summe[2], r.summe[3]
    local F = math.sqrt(Fx^2 + Fy^2)
    local k1, k2 = knoten[s.k1], knoten[s.k2]
    local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(i)
    local lx, ly = k2.x - k1.x, k2.y - k1.y
    local theta = ((u2x - u1x) * -ly + (u2y - u1y) * lx) / (lx^2 + ly^2)
    local anim_f = (0.5 * skala) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
    gc:setFont("sansserif", "r", 8)
    if F > 1e-4 then
        local wx, wy = bogenWirkungspunkt(s, Fx, Fy, M)
        local ux = u1x - theta * (wy - k1.y)
        local uy = u1y + theta * (wx - k1.x)
        -- (opx1, opy1) ist schon um u1 verschoben, dazu nur die Drehung um den Stabanfang
        local px = opx1 + (wx - k1.x) * skala + (ux - u1x) * anim_f
        local py = opy1 + (wy - k1.y) * skala + (uy - u1y) * anim_f
        gc:setColorRGB(255, 0, 0)
        drawArrow(gc, px - Fx / F * 25, py - Fy / F * 25, px, py)
        gc:drawString(string.format("R = %.2f", F), px - Fx / F * 25 + 5, py - Fy / F * 25 - 10)
        for _, w in ipairs({ { "x", ux * anim_f, 0 }, { "y", 0, uy * anim_f } }) do
            local lbl = pvvLabel("δ_s" .. i .. w[1])
            if lbl then
                gc:setColorRGB(200, 0, 200)
                drawArrow(gc, px - w[2], py - w[3], px, py)
                gc:drawString(lbl, px - w[2] + 5, py - w[3] - 10)
            end
        end
    elseif math.abs(M) > 1e-4 then
        local g = bogenGeometrie(s, 2)
        local mx, my = bogenPunkt(g, g.alpha / 2)
        local px, py = opx1 + (mx - k1.x) * skala, opy1 + (my - k1.y) * skala
        gc:setColorRGB(255, 150, 0)
        drawMoment(gc, px, py, 12, M < 0)
        gc:drawString(string.format("M = %.2f", math.abs(M)), px + 15, py - 10)
    end
end

-- E-Seite und Teilsystem-Hover: Lasten auf einem Bogen als Resultierende je Lastart (s.bogen_res aus
-- updateAlleLasten). Kraft in ihrer Richtung auf der Wirkungslinie, Fusspunkt auf dem Bogen (sonst
-- nahe der Bogenmitte); ohne Kraft ein Drehpfeil fuer das Moment. (opx1, opy1) = Stabanfang im Bild.
function zeichneBogenResultierende(gc, s, opx1, opy1, skala, resPfeil)
    local res = s.bogen_res
    local g = bogenGeometrie(s, 2)
    if not res or not g then return end
    local k1 = knoten[s.k1]
    local function bild(x, y) return opx1 + (x - k1.x) * skala, opy1 + (y - k1.y) * skala end
    local mx, my = bogenPunkt(g, g.alpha / 2)
    for _, art in ipairs({ "q", "n", "gx", "gy", "m" }) do
        local Fx, Fy, M = res[art][1], res[art][2], res[art][3]
        local F = math.sqrt(Fx^2 + Fy^2)
        if art == "q" or art == "n" then gc:setColorRGB(255, 50, 50) else gc:setColorRGB(255, 150, 0) end
        gc:setFont("sansserif", "b", 8)
        if F > 1e-4 then
            local fx, fy = Fx / F, Fy / F
            local px, py = bogenWirkungspunkt(s, Fx, Fy, M)
            local sx, sy = bild(px, py)
            drawArrow(gc, sx - fx * resPfeil, sy - fy * resPfeil, sx, sy)
            gc:drawString("R = " .. formatLabel(F), sx - fx * (resPfeil + 5) + 5, sy - fy * (resPfeil + 5) - 10)
            merkeResultierende(px, py)
        elseif math.abs(M) > 1e-4 then
            local sx, sy = bild(mx, my)
            drawMoment(gc, sx, sy, 12, M < 0)
            gc:drawString("M = " .. formatLabel(math.abs(M)), sx + 15, sy - 10)
        end
    end
end

local function getSymbLabel(s, mode, type_str, num_val)
    
    if symbolischer_modus and s["symb_" .. mode .. "_" .. type_str] then
        local str = tostring(s["symb_" .. mode .. "_" .. type_str])
        
        if type(str) == "string" and not str:find("undef") then
            if type_str == "max" then return "max: " .. str else return str end
        end
    end
    
    if type_str == "max" then return string.format("max: %.2f", num_val)
    else return string.format("%.2f", math.abs(num_val) < 1e-5 and 0 or num_val) end
end



function on.paint(gc)

    -- A partially entered or cleared model can briefly contain a member whose
    -- endpoint was removed. Drop such dangling members before any draw pass.
    for i = #staebe, 1, -1 do
        local stab = staebe[i]
        if not knoten[stab.k1] or not knoten[stab.k2] then
            table.remove(staebe, i)
        end
    end

    if ansichtsModus == "L" then
        gc:setFont("sansserif", "r", 7)
        gc:setColorRGB(0, 0, 0)
        gc:drawString("Globales Gleichungssystem (LGS):", 10, 10)
        local y_pos = 30 + (lgs_scroll_y or 0)
        local x_pos = 10 + (lgs_scroll_x or 0)
        local w_h = platform.window:height() - 20
        for i, eq in ipairs(lgs_equations or {}) do
            -- Only draw if visible on screen
            if y_pos > 10 and y_pos < platform.window:height() + 10 then
                gc:drawString(eq, x_pos, y_pos)
            end
            y_pos = y_pos + 12
        end
        return
    end
    
    local function fm(str, keep_sign)
        if type(str) ~= "string" then return "0" end
        str = str:match("^%s*(.-)%s*$")
        
        -- Replace special minus signs with standard minus for processing
        str = str:gsub(string.char(226, 136, 146), "-")
        str = str:gsub("−", "-")
        
        if not keep_sign then
            -- Robustly strip leading minus or leading "(-" to get the absolute value for display
            str = str:gsub("^%s*%-", "")
            str = str:gsub("^%s*%(%s*%-", "(")
        end
        
        return str:gsub("%*", "·"):gsub("%^2", "²"):gsub("%^3", "³")
    end
    local isKinematic = (ansichtsModus == "V")
    local orig_ansichtsModus = ansichtsModus
    -- Für Kinematik und den Prinzip-der-virtuellen-Verschiebungen-Modus (PvV)
    -- greifen wir primär auf die System-Darstellung (als Basis) zurück.
    if isKinematic or in_pvv_release then ansichtsModus = "System" end
    local isPolplan = (orig_ansichtsModus == "P")

    local b, h = platform.window:width(), platform.window:height()
    local drawPxProMeter = pxProMeter

    local stepPx = drawPxProMeter * rasterMass
    local startX = offsetX % stepPx
    local startY = offsetY % stepPx


    gc:setColorRGB(0, 0, 0)
    gc:setFont("sansserif", "b", 12)
    gc:setColorRGB(180, 180, 180)
    if rasterPunkte ~= 0 then   -- ohne neue Locals: on.paint ist nah an der Grenze von 200
        for rx = startX, b, stepPx do
            for ry = startY, h, stepPx do gc:fillRect(rx, ry, (rasterPunkte == 2) and 2 or 1, (rasterPunkte == 2) and 2 or 1) end
        end
    end
    gc:setColorRGB(200, 200, 255); gc:drawLine(offsetX, 0, offsetX, h); gc:drawLine(0, offsetY, b, offsetY)

    local modusText = isPolplan and "Polplan" or (isKinematic and "Verschiebungszustand" or (ansichtsModus or "System"))
    if (pvvModus or in_pvv_release) and isKinematic then modusText = "PvV" end
    -- Rot wenn Stäbe vorhanden aber noch nicht berechnet
    local needsCalc = (#staebe > 0) and not systemBerechnet
    gc:setFont("sansserif", "b", 12)
    if needsCalc then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 100, 200) end
    gc:drawString("Modus: " .. modusText, 5, 5)
    
    if pvvModus then
        gc:setFont("sansserif", "r", 10); gc:drawString("Wähle Knoten zum Lösen (ESC abbrechen)", 5, 25)
    elseif in_pvv_release then
        gc:setFont("sansserif", "r", 10); gc:setColorRGB(200, 0, 0); gc:drawString("Verschiebungs-Ansicht. [ESC] zum Beenden", 5, 25)
    end

    if autoKGV and KGV_Zustand >= 0 then gc:setColorRGB(200, 0, 200); gc:drawString("Auto-KGV: " .. ((KGV_Zustand == 0) and "Nullsystem" or ("X" .. KGV_Zustand .. " = 1")), 5, 25) end
    -- n=... Anzeige: symb. jetzt als zweite Zeile darunter
    do
        local n_val = getTopologicalN()
        local n_text = "n = " .. n_val
        if zeigeN and kgv_n ~= nil then n_text = n_text .. " (" .. kgv_n .. ")" end
        gc:setFont("sansserif", "b", 12); gc:setColorRGB(0, 100, 200)
        local n_w = gc:getStringWidth(n_text)
        local n_x = b - n_w - 10
        gc:drawString(n_text, n_x, 5)
        
        -- "symb." als zweite Zeile unter n=...
        if symbolischer_modus then
            gc:setFont("sansserif", "r", 9); gc:setColorRGB(0, 100, 200)
            local s_str = "symb."
            gc:drawString(s_str, b - gc:getStringWidth(s_str) - 10, 20)
        end
        
        -- Hover-Tooltip: r+z-3*p Formel (nur bei Hover berechnen)
        local mx = mouseX or -1
        local my = mouseY or -1
        if mx >= n_x - 5 and mx <= b - 5 and my >= 0 and my <= 18 then
            -- r, z, p nur bei Hover ermitteln
            local r_val = 0
            for _, k in ipairs(knoten) do
                if k.lager_x then r_val=r_val+1 end
                if k.lager_y then r_val=r_val+1 end
                if k.lager_m then r_val=r_val+1 end
            end
            local p_val = (glob_num_disks and glob_num_disks > 0) and glob_num_disks or nil
            local z_val = p_val and (n_val + 3*p_val - r_val) or nil
            gc:setFont("sansserif", "r", 9); gc:setColorRGB(60, 60, 60)
            local tip1, tip2
            if fachwerkModus then
                -- Fachwerk: n = s + r - 2k (Federn zaehlen als Lager wie in getTopologicalN)
                local r_fw = 0
                for _, k in ipairs(knoten) do
                    if k.lager_x or (k.cx or 0) > 0 then r_fw = r_fw + 1 end
                    if k.lager_y or (k.cy or 0) > 0 then r_fw = r_fw + 1 end
                    if k.lager_m or (k.cm or 0) > 0 then r_fw = r_fw + 1 end
                end
                local s_fw, k_fw = #staebe, #knoten
                local n_fw = s_fw + r_fw - 2 * k_fw
                tip1 = string.format("s=%d  r=%d  k=%d", s_fw, r_fw, k_fw)
                tip2 = string.format("n=s+r-2k: %d+%d-%d=%d", s_fw, r_fw, 2 * k_fw, n_fw)
                if n_fw ~= n_val then tip2 = tip2 .. " (kein reines Fachwerk)" end
            elseif p_val and z_val then
                tip1 = string.format("r=%d  z=%d  p=%d", r_val, z_val, p_val)
                tip2 = string.format("n=r+z-3p: %d+%d-%d=%d", r_val, z_val, 3*p_val, n_val)
            else
                tip1 = string.format("r=%d  (B berechnen!)", r_val)
                tip2 = string.format("n=%d", n_val)
            end
            local tw = math.max(gc:getStringWidth(tip1), gc:getStringWidth(tip2))
            gc:drawString(tip1, b - tw - 5, 22)
            gc:drawString(tip2, b - tw - 5, 34)
        end
    end

    local palette = { {220, 20, 60}, {0, 100, 220}, {34, 139, 34}, {255, 140, 0}, {128, 0, 128}, {0, 206, 209}, {139, 69, 19}, {255, 20, 147} }

    local function drawExplosionArrow(gc, x1, y1, x2, y2)
        gc:drawLine(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        local L = math.sqrt(dx*dx + dy*dy)
        if L > 0 then
            local ux, uy = dx/L, dy/L; local nx, ny = -uy, ux
            local hL, hW = 6, 2
            local bx, by = x2 - hL*ux, y2 - hL*uy
            gc:fillPolygon({x2, y2, bx + hW*nx, by + hW*ny, bx - hW*nx, by - hW*ny})
        end
    end

    -- Protokoll der Seite 2 (nur fuer Tests: E2_PROTOKOLL = {} setzen): Name und Richtung jedes Pfeils
    local function e2Pfeil(name, dx, dy)
        if E2_PROTOKOLL and explosionPage == 2 then table.insert(E2_PROTOKOLL, { name = name, dx = dx, dy = dy }) end
    end
    local function e2Moment(name, isClockwise)
        if E2_PROTOKOLL and explosionPage == 2 then table.insert(E2_PROTOKOLL, { name = name, m = isClockwise and -1 or 1 }) end
    end

    local function drawReactionArrow(gc, val, dirX, dirY, cx, cy, labelPrefix, symb_label, custom_val_str, forceDraw)
        if math.abs(val) < 1e-4 and not forceDraw then return end
        local arrowLen = math.max(18, drawPxProMeter * 0.24)   -- kurze Pfeile im E-Modus
        local sign = val >= 0 and 1 or -1
        if forceDraw then sign = 1 end
        local mag = math.abs(val)
        e2Pfeil(symb_label or labelPrefix:gsub(" = ", ""), sign * dirX, sign * dirY)

        local tailX = cx - sign * dirX * arrowLen
        local tailY = cy - sign * dirY * arrowLen

        if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
        gc:setPen("thin", "smooth")
        drawExplosionArrow(gc, tailX, tailY, cx, cy)

        gc:setFont("sansserif", "r", 10)
        if showExplosionLabels ~= false then
            local label
            if explosionPage == 2 then
                if symb_label then label = symb_label else label = labelPrefix:gsub(" = ", "") end
            elseif custom_val_str then
                label = labelPrefix .. custom_val_str
            else
                label = labelPrefix .. formatLabel(mag)
            end
            local tw = gc:getStringWidth(label)

            local ox, oy = -dirY * sign, dirX * sign
            if oy > 0 or (oy == 0 and ox < 0) then ox = -ox; oy = -oy end
            gc:drawString(label, (cx + tailX)/2 - tw/2 + ox*12, (cy + tailY)/2 - 5 + oy*12)
        end
    end

    local function drawFBDArrow(gc, val, dirX, dirY, x, y, labelPrefix, symb_label, custom_val_str, forceDraw, flipMultiplier)
        if math.abs(val) < 1e-4 and not forceDraw then return end
        local arrowLen = math.max(18, drawPxProMeter * 0.27)   -- kurze Pfeile im E-Modus
        local sign = val >= 0 and 1 or -1
        if forceDraw then sign = 1 end
        if forceDraw and flipMultiplier then sign = sign * flipMultiplier end
        local mag = math.abs(val)
        e2Pfeil(symb_label or labelPrefix:gsub(" = ", ""), sign * dirX, sign * dirY)

        local tailX = x - sign * dirX * arrowLen
        local tailY = y - sign * dirY * arrowLen

        if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
        gc:setPen("thin", "smooth")
        drawExplosionArrow(gc, tailX, tailY, x, y)

        gc:setFont("sansserif", "r", 10)
        if showExplosionLabels ~= false then
            local label
            if explosionPage == 2 then
                if symb_label then label = symb_label else label = labelPrefix:gsub(" = ", "") end
            elseif custom_val_str then
                label = labelPrefix .. custom_val_str
            else
                label = labelPrefix .. formatLabel(mag)
            end

            local tw = gc:getStringWidth(label)

            local ox, oy = -dirY * sign, dirX * sign
            if oy > 0 or (oy == 0 and ox < 0) then ox = -ox; oy = -oy end
            gc:drawString(label, (x + tailX)/2 - tw/2 + ox*10, (y + tailY)/2 - 5 + oy*10)
        end
    end

    local function get_u_val(s, x, L_m, j, nA, nB)
        local u_homogen = (s.v_local[1] or 0)*(1-x/L_m) + (s.v_local[4] or 0)*(x/L_m)
        local u_part_class_EA = -(nA*x^2/2 + (nB-nA)*x^3/(6*L_m)) + (x/L_m) * (nA*L_m^2/2 + (nB-nA)*L_m^2/6)
        local u_part_cas_EA = (s.u_cas_pts_EA and s.u_cas_pts_EA[j+1]) or 0
        return u_homogen + (u_part_class_EA + u_part_cas_EA) / stabEA(s)
    end

    local max_val = 0

    if ansichtsModus ~= "System" and ansichtsModus ~= "E" and not isPolplan and not isKinematic and not in_pvv_release then
        for i, s in ipairs(staebe) do
            if not s.is_cut then
                local L_m = math.sqrt((knoten[s.k2].x - knoten[s.k1].x)^2 + (knoten[s.k2].y - knoten[s.k1].y)^2)
                if L_m > 0 then
                    local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local c_val, s_val = dx/L_m, -dy/L_m
                    local eff_gx = (s.gx or 0) * (s.gx_proj and math.abs(s_val) or 1); local eff_gy = (s.gy or 0) * (s.gy_proj and math.abs(c_val) or 1)
                    local n_add = eff_gx * c_val - eff_gy * s_val; local q_add = eff_gx * s_val + eff_gy * c_val
                    local N0, Q0, M0 = -s.s_local[1], -s.s_local[2], -s.s_local[3]
                    local qA, qB, nA, nB = s.q + s.q_A + q_add, s.q + s.q_B + q_add, s.n + s.n_A + n_add, s.n + s.n_B + n_add
                    if s.q_in_cas then qA, qB = 0, 0 end; if s.n_in_cas then nA, nB = 0, 0 end -- sonst doppelt zu cas_*_drop

                    for j = 0, ptsBiegelinie do
                        local x = (j/ptsBiegelinie) * L_m; local val = 0
                        local cas_Q_drop = (s.Q_cas_pts and s.Q_cas_pts[j+1]) or 0
                        local cas_M_drop = (s.M_cas_pts and s.M_cas_pts[j+1]) or 0
                        local cas_N_drop = (s.N_cas_pts and s.N_cas_pts[j+1]) or 0

                        if ansichtsModus == "N" then val = N0 - (nA*x + (nB-nA)*(x^2)/(2*L_m)) - cas_N_drop
                        elseif ansichtsModus == "Q" then val = Q0 - (qA*x + (qB-qA)*(x^2)/(2*L_m)) - cas_Q_drop
                        elseif ansichtsModus == "M" then val = M0 + Q0*x - s.m*x - (qA*(x^2)/2 + (qB-qA)*(x^3)/(6*L_m)) - cas_M_drop
                        elseif ansichtsModus == "U" then val = get_u_val(s, x, L_m, j, nA, nB)
                        elseif ansichtsModus == "W" and not skip_diagram then
                            local EI = stabEI(s)
                            local c1 = (s.v_local[2] or 0) * EI
                            local c2 = -(s.v_local[3] or 0) * EI
                            local c3 = (s.v_local[5] or 0) * EI
                            local c4 = -(s.v_local[6] or 0) * EI
                            local xi = x / L_m
                            local val_homogen_EI = c1*(1-3*xi^2+2*xi^3) + c2*(x-2*x^2/L_m+x^3/(L_m^2)) + c3*(3*xi^2-2*xi^3) + c4*(-x^2/L_m+x^3/(L_m^2))
                            local v_part_class_EI = (x^2 * (L_m - x)^2) / (120 * L_m) * ((3*L_m - x)*qA + (2*L_m + x)*qB)
                            local v_part_cas_EI = (s.v_cas_pts_EI and s.v_cas_pts_EI[j+1]) or 0
                            val = (val_homogen_EI + v_part_class_EI + v_part_cas_EI) / EI
                        end
                        -- Rauschen unterdruecken: Kraefte unter 1e-5, Verschiebungen (in m) erst unter 1e-12,
                        -- sonst fehlt bei Verformungen unter 0,01 mm die Linie bzw. ein Stueck wird flach
                        if math.abs(val) < (((ansichtsModus == "W" or ansichtsModus == "U") and 1e-12) or 1e-5) then val = 0 end
                        if math.abs(val) > max_val then max_val = math.abs(val) end
                    end
                end
            elseif s.arc_plot_data then
                if ansichtsModus == "W" or ansichtsModus == "U" then
                    for v = 1, #s.arc_plot_data do
                        local pd = s.arc_plot_data[v]
                        local val_disp1 = math.sqrt((pd.disp_x1 or 0)^2 + (pd.disp_y1 or 0)^2)
                        local val_disp2 = math.sqrt((pd.disp_x2 or 0)^2 + (pd.disp_y2 or 0)^2)
                        local val_disp = math.max(val_disp1, val_disp2)
                        if val_disp > max_val then max_val = val_disp end
                    end
                else
                    for _, pd in ipairs(s.arc_plot_data) do
                        local v1, v2 = 0, 0
                        if ansichtsModus == "N" then v1 = pd.N; v2 = pd.N2 or pd.N
                        elseif ansichtsModus == "Q" then v1 = pd.Q; v2 = pd.Q2 or pd.Q
                        elseif ansichtsModus == "M" then v1 = pd.M1; v2 = pd.M2
                        end
                        if math.abs(v1) > max_val then max_val = math.abs(v1) end
                        if math.abs(v2) > max_val then max_val = math.abs(v2) end
                    end
                end
            end
        end
    end
    if max_val < 1e-15 then max_val = 1 end
    local drawScale = (40 / max_val) * (drawPxProMeter / 100) * (verlaufSkalierung or 1)

    local isExplosion = (ansichtsModus == "E")
    glob_resultant_pts = {}
    local hovered_ts = nil
    if isExplosion and explosionPage == 2 and not fachwerkModus then
        if hoverTyp == "stab" and hoverObj and glob_ts_scheibe then
            hovered_ts = glob_ts_scheibe[hoverObj]
        end
    end

    local loadApplied = {}
    local loadApplied = {}

    if isKinematic then
        gc:setPen("thin", "dotted")
        gc:setColorRGB(0, 0, 0)
        for _, s in ipairs(staebe) do
            local opx1 = knoten[s.k1].x * drawPxProMeter + offsetX
            local opy1 = knoten[s.k1].y * drawPxProMeter + offsetY
            local opx2 = knoten[s.k2].x * drawPxProMeter + offsetX
            local opy2 = knoten[s.k2].y * drawPxProMeter + offsetY
            gc:drawLine(opx1, opy1, opx2, opy2)
        end
    end


    for i, s in ipairs(staebe) do
        local px1, py1 = knoten[s.k1].x * drawPxProMeter + offsetX, knoten[s.k1].y * drawPxProMeter + offsetY
        local px2, py2 = knoten[s.k2].x * drawPxProMeter + offsetX, knoten[s.k2].y * drawPxProMeter + offsetY
        if isKinematic then
            local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(i)
            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
            px1, py1 = px1 + u1x * anim_f, py1 + u1y * anim_f
            px2, py2 = px2 + u2x * anim_f, py2 + u2y * anim_f
        end
        local orig_px1, orig_py1 = px1, py1
        local orig_px2, orig_py2 = px2, py2
        local dx_orig, dy_orig = px2 - px1, py2 - py1;
        local L_orig = math.sqrt(dx_orig^2 + dy_orig^2)

        local explodeA = knoten[s.k1].gelenk or s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A
        local explodeB = knoten[s.k2].gelenk or s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B
        
        local gapA, gapB = 0, 0
        if s.gelenk_A then gapA = 6 end
        if s.q_gelenk_A then gapA = 10 end
        if s.n_gelenk_A then gapA = 12 end
        if s.gelenk_B then gapB = 6 end
        if s.q_gelenk_B then gapB = 10 end
        if s.n_gelenk_B then gapB = 12 end
        
        if ansichtsModus == "W" or ansichtsModus == "U" then gapA, gapB = 0, 0 end

        local L = L_orig
        if L_orig > gapA + gapB + 10 then
            local ux, uy = dx_orig/L_orig, dy_orig/L_orig
            local expl_gap = isExplosion and math.min(1.5 * drawPxProMeter, L_orig * 0.35) or 0
            if hovered_ts then expl_gap = 0 end
            if explodeA then px1 = px1 + ux * (gapA + expl_gap); py1 = py1 + uy * (gapA + expl_gap) end
            if explodeB then px2 = px2 - ux * (gapB + expl_gap); py2 = py2 - uy * (gapB + expl_gap) end
            L = math.sqrt((px2-px1)^2 + (py2-py1)^2)
        end

        local dx, dy = px2 - px1, py2 - py1
        local ux, uy, nx, ny = 0, 0, 0, 0
        if L > 0 then ux, uy = dx/L, dy/L; nx, ny = -uy, ux end

        local skip_diagram = false
        if hoverTyp == "stab" and hoverObj and hoverObj ~= i then skip_diagram = true end



        if ansichtsModus == "W" then gc:setColorRGB(150, 150, 150)
        elseif isPolplan then
            local d_scheibe = s.scheibe and polplan.display_scheibe[s.scheibe] or s.scheibe
            if d_scheibe == 0 or (d_scheibe and polplan.fixed[d_scheibe]) then
                gc:setColorRGB(100, 100, 100)
            else
                local col = palette[((d_scheibe or 1) % #palette) + 1]
                gc:setColorRGB(col[1], col[2], col[3])
            end
    elseif (menuOffen and menuTyp == "stab" and menuIndex == i) or (not menuOffen and hoverTyp == "stab" and hoverObj == i) then 
                    gc:setColorRGB(0, 100, 255) 
                else 
                    if hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] ~= hovered_ts then
                        gc:setColorRGB(200, 200, 200)
                    else
                        gc:setColorRGB(0, 0, 0) 
                    end
                end

        local penSize = "thin"
        if isPolplan then penSize = "medium" end
        gc:setPen(penSize, "smooth")


        if ansichtsModus == "W" or ansichtsModus == "U" or s.is_cut then gc:setPen("thin", "dashed") end
        
        local true_L = (L / drawPxProMeter)
        if not (fachwerkModus and isExplosion) then
            if (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= true_L/2 and true_L > 0 then
                local r_px = math.abs(s.bogen_r) * drawPxProMeter
                local sgn = s.bogen_r > 0 and -1 or 1
                local d_px = math.sqrt(r_px^2 - (L/2)^2)
                local arc_pts = {}
                for j=0, 50 do
                    local t = j/50
                    local x_local = (t - 0.5) * L
                    local y_local = sgn * (math.sqrt(r_px^2 - x_local^2) - d_px)
                    local ax = (px1+px2)/2 + x_local * (dx/L) - y_local * (dy/L)
                    local ay = (py1+py2)/2 + x_local * (dy/L) + y_local * (dx/L)
                    table.insert(arc_pts, ax); table.insert(arc_pts, ay)
                end
                gc:drawPolyLine(arc_pts)
            else
                gc:drawLine(px1, py1, px2, py2)
            end
        end
        gc:setPen("medium", "smooth")



        if isPolplan and L > 0 and not s.is_cut and s.scheibe and s.scheibe ~= 0 then
            gc:setFont("sansserif", "b", 10)
            if polplan.fixed[s.scheibe] then
                gc:setColorRGB(100, 100, 100)
                gc:drawString("S" .. tostring(s.scheibe) .. " (FEST)", (px1+px2)/2 + nx*10, (py1+py2)/2 + ny*10)
            else
                local col = palette[((s.scheibe or 1) % #palette) + 1]
                gc:setColorRGB(col[1], col[2], col[3])
                gc:drawString("S" .. tostring(s.scheibe or 1), (px1+px2)/2 + nx*10, (py1+py2)/2 + ny*10)
            end
        end
        if fachwerkModus and s.is_zero_force and modusText == "System" and not isExplosion then
            gc:setColorRGB(0, 180, 0)
            gc:setPen("medium", "smooth")
            local midX, midY = (px1+px2)/2, (py1+py2)/2
            local cSize = 6
            gc:drawLine(midX - cSize, midY - cSize, midX + cSize, midY + cSize)
            gc:drawLine(midX - cSize, midY + cSize, midX + cSize, midY - cSize)
            gc:setFont("sansserif", "b", 11)
            gc:drawString("0", midX + 8, midY - 12)
        end

        if s.is_cut and L > 0 then
            gc:setColorRGB(0, 0, 0); local midX, midY = (px1+px2)/2, (py1+py2)/2
            gc:drawLine(midX - ux*5 + nx*3, midY - uy*5 + ny*3, midX + ux*5 + nx*3, midY + uy*5 + ny*3)
            gc:drawLine(midX - ux*5 - nx*3, midY - uy*5 - ny*3, midX + ux*5 - nx*3, midY + uy*5 - ny*3)
        end

        if (s.x_nA or 0) ~= 0 and L > 0 then
            gc:setColorRGB(200, 0, 200); gc:setPen("medium", "smooth")
            local midX, midY = (px1+px2)/2, (py1+py2)/2
            drawArrow(gc, midX + ux*5, midY + uy*5, midX + ux*25, midY + uy*25)
            drawArrow(gc, midX - ux*5, midY - uy*5, midX - ux*25, midY - uy*25)
            gc:setFont("sansserif", "b", 9); gc:drawString("1.00", midX + ny*10 - 10, midY - nx*10 - 5)
        end

        if L > 0 and ansichtsModus ~= "W" and ansichtsModus ~= "U" and not isPolplan then
            local uxA, uyA, nxA, nyA = ux, uy, nx, ny
            local uxB, uyB, nxB, nyB = ux, uy, nx, ny
            if (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= true_L/2 then
                local R = math.abs(s.bogen_r)
                local sgn = s.bogen_r > 0 and -1 or 1
                local function getTang(t)
                    local xl = (t - 0.5) * true_L
                    local denom = math.sqrt(math.max(1e-6, R^2 - xl^2))
                    local tx_l, ty_l = 1, -sgn * (xl / denom)
                    local len = math.sqrt(tx_l^2 + ty_l^2)
                    tx_l, ty_l = tx_l/len, ty_l/len
                    local t_gx = tx_l * (dx/L) - ty_l * (dy/L)
                    local t_gy = tx_l * (dy/L) + ty_l * (dx/L)
                    return t_gx, t_gy, -t_gy, t_gx
                end
                uxA, uyA, nxA, nyA = getTang(0)
                uxB, uyB, nxB, nyB = getTang(1)
            end
            
            local ux_orig, uy_orig = dx_orig/L_orig, dy_orig/L_orig
            local nx_orig, ny_orig = -uy_orig, ux_orig
            local jx1, jy1 = px1 - ux_orig * gapA, py1 - uy_orig * gapA
            local jx2, jy2 = px2 + ux_orig * gapB, py2 + uy_orig * gapB

            if s.q_gelenk_A and not s.is_cut then
                gc:setPen("thin", "smooth"); gc:setColorRGB(0, 0, 0)
                gc:drawLine(jx1, jy1, jx1 + ux_orig*3, jy1 + uy_orig*3)
                gc:drawLine(jx1 + ux_orig*3 + nx_orig*5, jy1 + uy_orig*3 + ny_orig*5, jx1 + ux_orig*3 - nx_orig*5, jy1 + uy_orig*3 - ny_orig*5)
                gc:drawLine(jx1 + ux_orig*7 + nx_orig*5, jy1 + uy_orig*7 + ny_orig*5, jx1 + ux_orig*7 - nx_orig*5, jy1 + uy_orig*7 - ny_orig*5)
                gc:drawLine(jx1 + ux_orig*7, jy1 + uy_orig*7, px1, py1)
            end
            if s.q_gelenk_B and not s.is_cut then
                gc:setPen("thin", "smooth"); gc:setColorRGB(0, 0, 0)
                gc:drawLine(jx2, jy2, jx2 - ux_orig*3, jy2 - uy_orig*3)
                gc:drawLine(jx2 - ux_orig*3 + nx_orig*5, jy2 - uy_orig*3 + ny_orig*5, jx2 - ux_orig*3 - nx_orig*5, jy2 - uy_orig*3 - ny_orig*5)
                gc:drawLine(jx2 - ux_orig*7 + nx_orig*5, jy2 - uy_orig*7 + ny_orig*5, jx2 - ux_orig*7 - nx_orig*5, jy2 - uy_orig*7 - ny_orig*5)
                gc:drawLine(jx2 - ux_orig*7, jy2 - uy_orig*7, px2, py2)
            end

            if s.n_gelenk_A and not s.is_cut then
                gc:setPen("thin", "smooth"); gc:setColorRGB(0, 0, 0)
                gc:drawLine(jx1, jy1, jx1 + ux_orig*3, jy1 + uy_orig*3)
                gc:drawLine(jx1 + ux_orig*3 + nx_orig*4, jy1 + uy_orig*3 + ny_orig*4, jx1 + ux_orig*3 - nx_orig*4, jy1 + uy_orig*3 - ny_orig*4)
                gc:drawLine(jx1 + ux_orig*3 + nx_orig*4, jy1 + uy_orig*3 + ny_orig*4, jx1 + ux_orig*11 + nx_orig*4, jy1 + uy_orig*11 + ny_orig*4)
                gc:drawLine(jx1 + ux_orig*3 - nx_orig*4, jy1 + uy_orig*3 - ny_orig*4, jx1 + ux_orig*11 - nx_orig*4, jy1 + uy_orig*11 - ny_orig*4)
                gc:fillArc(jx1 + ux_orig*9 - 2, jy1 + uy_orig*9 - 2, 4, 4, 0, 360)
                gc:drawLine(jx1 + ux_orig*9, jy1 + uy_orig*9, px1, py1)
            end
            if s.n_gelenk_B and not s.is_cut then
                gc:setPen("thin", "smooth"); gc:setColorRGB(0, 0, 0)
                gc:drawLine(jx2, jy2, jx2 - ux_orig*3, jy2 - uy_orig*3)
                gc:drawLine(jx2 - ux_orig*3 + nx_orig*4, jy2 - uy_orig*3 + ny_orig*4, jx2 - ux_orig*3 - nx_orig*4, jy2 - uy_orig*3 - ny_orig*4)
                gc:drawLine(jx2 - ux_orig*3 + nx_orig*4, jy2 - uy_orig*3 + ny_orig*4, jx2 - ux_orig*11 + nx_orig*4, jy2 - uy_orig*11 + ny_orig*4)
                gc:drawLine(jx2 - ux_orig*3 - nx_orig*4, jy2 - uy_orig*3 - ny_orig*4, jx2 - ux_orig*11 - nx_orig*4, jy2 - uy_orig*11 - ny_orig*4)
                gc:fillArc(jx2 - ux_orig*9 - 2, jy2 - uy_orig*9 - 2, 4, 4, 0, 360)
                gc:drawLine(jx2 - ux_orig*9, jy2 - uy_orig*9, px2, py2)
            end
        end

        if L > 0 then
            if ansichtsModus ~= "W" and ansichtsModus ~= "U" and not (fachwerkModus and isExplosion) then
                gc:setPen("thin", "dashed")
                if (menuOffen and menuTyp == "stab" and menuIndex == i) or (not menuOffen and hoverTyp == "stab" and hoverObj == i) then gc:setColorRGB(100, 150, 255) else gc:setColorRGB(150, 150, 150) end
                if (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= (L / drawPxProMeter)/2 then
                    local r_px = math.abs(s.bogen_r) * drawPxProMeter
                    local sgn = s.bogen_r > 0 and -1 or 1
                    local d_px = math.sqrt(r_px^2 - (L/2)^2)
                    local dashed_pts = {}
                    for j=0, bogenSegmente do
                        local t = j/bogenSegmente
                        local x_local = (t - 0.5) * L
                        local y_local = sgn * (math.sqrt(r_px^2 - x_local^2) - d_px)
                        local ax = (px1+px2)/2 + x_local * (dx/L) - y_local * (dy/L)
                        local ay = (py1+py2)/2 + x_local * (dy/L) + y_local * (dx/L)
                        local tang_x = dx/L + sgn * (x_local / math.sqrt(r_px^2 - x_local^2)) * (dy/L)
                        local tang_y = dy/L - sgn * (x_local / math.sqrt(r_px^2 - x_local^2)) * (dx/L)
                        local len = math.sqrt(tang_x^2 + tang_y^2)
                        local lnx, lny = -tang_y/len, tang_x/len
                        table.insert(dashed_pts, ax + lnx*3)
                        table.insert(dashed_pts, ay + lny*3)
                    end
                    gc:drawPolyLine(dashed_pts)
                else
                    gc:drawLine(px1 + nx*3, py1 + ny*3, px2 + nx*3, py2 + ny*3)
                end
                gc:setPen("thin", "smooth")
            end
                if in_pvv_release and isKinematic then
                    local L_m = math.sqrt((knoten[s.k2].x - knoten[s.k1].x)^2 + (knoten[s.k2].y - knoten[s.k1].y)^2)
                    if L_m > 0 and istBogen(s) then
                        zeichneBogenPvv(gc, s, i, orig_px1, orig_py1, drawPxProMeter)
                    elseif L_m > 0 then
                        local u_phys_xA, u_phys_yA, u_phys_xB, u_phys_yB = getKinematicDisp_Stab(i)
                        local orig_dx_phys = knoten[s.k2].x - knoten[s.k1].x
                        local orig_dy_phys = knoten[s.k2].y - knoten[s.k1].y
                        local L_phys = math.sqrt(orig_dx_phys^2 + orig_dy_phys^2)
                        local cA = L_phys > 0 and orig_dx_phys/L_phys or 1
                        local sA = L_phys > 0 and orig_dy_phys/L_phys or 0
                        
                        -- Wege mit Namen und Wert aus dem Export (pvvLabel), 1:1 wie pvv_kin
                        local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)

                        local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                        local Rq = (qA + qB)/2 * L_phys + (s.R_q_cas or 0)
                        local Sq = (L_phys^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
                        if math.abs(Rq) > 1e-4 then
                            local xs = Sq / Rq
                            local px = px1 + dx * (xs / L_phys); local py = py1 + dy * (xs / L_phys)
                            gc:setColorRGB(255, 0, 0)
                            local dir = Rq > 0 and -1 or 1; local h = 25 * dir
                            drawArrow(gc, px - sA*h, py + cA*h, px, py)
                            gc:setFont("sansserif", "r", 8)
                            local Rq_lbl_str, _, _ = processDistLoad_PvV(L_phys, L_phys, s.q_str, s.q_A_str, s.q_B_str, s.R_q_cas_str, s.S_q_cas_str, Rq, Sq, "q", true)
                            local lbl = Rq_lbl_str and ("R = " .. Rq_lbl_str) or string.format("R = %.2f", math.abs(Rq))
                            gc:drawString(lbl, px - sA*h + 5, py + cA*h - 10)
                            
                            local uxs = u_phys_xA + (xs / L_phys) * (u_phys_xB - u_phys_xA)
                            local uys = u_phys_yA + (xs / L_phys) * (u_phys_yB - u_phys_yA)
                            local vs = -uxs * sA + uys * cA
                            lbl = pvvLabel("δ_s" .. i .. "q")
                            if lbl then
                                local disp_px = vs * anim_f
                                local ax1, ay1 = px - (-sA) * disp_px, py - cA * disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(lbl, ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local nA = s.n + (s.n_A or 0); local nB = s.n + (s.n_B or 0)
                        local Rn = (nA + nB)/2 * L_phys + (s.R_n_cas or 0)
                        local Sn = (L_phys^2)/6 * (nA + 2*nB) + (s.S_n_cas or 0)
                        if math.abs(Rn) > 1e-4 then
                            local xs = Sn / Rn
                            local px = px1 + dx * (xs / L_phys); local py = py1 + dy * (xs / L_phys)
                            gc:setColorRGB(255, 0, 0)
                            local dir = Rn > 0 and 1 or -1; local len = 25
                            drawArrow(gc, px - cA*len*dir, py - sA*len*dir, px, py)
                            gc:setFont("sansserif", "r", 8)
                            local Rn_lbl_str, _, _ = processDistLoad_PvV(L_phys, L_phys, s.n_str, s.n_A_str, s.n_B_str, s.R_n_cas_str, s.S_n_cas_str, Rn, Sn, "q", true)
                            local lbl = Rn_lbl_str and ("R = " .. Rn_lbl_str) or string.format("R = %.2f", math.abs(Rn))
                            gc:drawString(lbl, px - cA*len*dir + 5, py - sA*len*dir - 10)
                            
                            local uxs = u_phys_xA + (xs / L_phys) * (u_phys_xB - u_phys_xA)
                            local uys = u_phys_yA + (xs / L_phys) * (u_phys_yB - u_phys_yA)
                            local us = uxs * cA + uys * sA
                            lbl = pvvLabel("δ_s" .. i .. "n")
                            if lbl then
                                local disp_px = us * anim_f
                                local ax1, ay1 = px - cA * disp_px, py - sA * disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(lbl, ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local Rgy = (s.gy or 0) * (s.gy_proj and math.abs(orig_dx_phys) or L_phys) + (s.R_gy_cas or 0)
                        local Sgy = (s.gy or 0) * (s.gy_proj and math.abs(orig_dx_phys) or L_phys) * (L_phys/2) + (s.S_gy_cas or 0)
                        if math.abs(Rgy) > 1e-4 then
                            local xs = Sgy / Rgy
                            local px = px1 + dx * (xs / L_phys); local py = py1 + dy * (xs / L_phys)
                            gc:setColorRGB(255, 150, 0)
                            local dir = Rgy > 0 and -1 or 1; local h = 25 * dir
                            drawArrow(gc, px, py + h, px, py)
                            gc:setFont("sansserif", "r", 8)
                            local L_eff_gy = s.gy_proj and math.abs(orig_dx_phys) or L_phys
                            local Rgy_lbl_str, _, _ = processDistLoad_PvV(L_phys, L_eff_gy, s.gy_str, nil, nil, s.R_gy_cas_str, s.S_gy_cas_str, Rgy, Sgy, "g", true)
                            local lbl = Rgy_lbl_str and ("R = " .. Rgy_lbl_str) or string.format("R = %.2f", math.abs(Rgy))
                            gc:drawString(lbl, px + 5, py + h - 10)
                            
                            local uys = u_phys_yA + (xs / L_phys) * (u_phys_yB - u_phys_yA)
                            lbl = pvvLabel("δ_s" .. i .. "y")
                            if lbl then
                                local disp_px = uys * anim_f
                                local ax1, ay1 = px, py - disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(lbl, ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local Rgx = (s.gx or 0) * (s.gx_proj and math.abs(orig_dy_phys) or L_phys) + (s.R_gx_cas or 0)
                        local Sgx = (s.gx or 0) * (s.gx_proj and math.abs(orig_dy_phys) or L_phys) * (L_phys/2) + (s.S_gx_cas or 0)
                        if math.abs(Rgx) > 1e-4 then
                            local xs = Sgx / Rgx
                            local px = px1 + dx * (xs / L_phys); local py = py1 + dy * (xs / L_phys)
                            gc:setColorRGB(255, 150, 0)
                            local dir = Rgx > 0 and -1 or 1; local h = 25 * dir
                            drawArrow(gc, px + h, py, px, py)
                            gc:setFont("sansserif", "r", 8)
                            local L_eff_gx = s.gx_proj and math.abs(orig_dy_phys) or L_phys
                            local Rgx_lbl_str, _, _ = processDistLoad_PvV(L_phys, L_eff_gx, s.gx_str, nil, nil, s.R_gx_cas_str, s.S_gx_cas_str, Rgx, Sgx, "g", true)
                            local lbl = Rgx_lbl_str and ("R = " .. Rgx_lbl_str) or string.format("R = %.2f", math.abs(Rgx))
                            gc:drawString(lbl, px + h + 5, py - 10)
                            
                            local uxs = u_phys_xA + (xs / L_phys) * (u_phys_xB - u_phys_xA)
                            lbl = pvvLabel("δ_s" .. i .. "x")
                            if lbl then
                                local disp_px = uxs * anim_f
                                local ax1, ay1 = px - disp_px, py
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(lbl, ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local Rm = (s.m or 0) * L_phys
                        if math.abs(Rm) > 1e-4 then
                            local px, py = px1 + dx*0.5, py1 + dy*0.5
                            gc:setColorRGB(255, 150, 0)
                            drawMoment(gc, px, py, 12, Rm < 0)
                            gc:setFont("sansserif", "r", 8)
                            gc:drawString(string.format("M = %.2f", math.abs(Rm)), px + 15, py - 10)
                        end
                    end
                end

            local should_draw_loads = true
            if isExplosion and hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] ~= hovered_ts then should_draw_loads = false end
            if should_draw_loads and (modusText == "System" or (modusText == "PvV" and not in_pvv_release) or isExplosion) then
                local has_cas_gy = s.gy_str and string.hasx(s.gy_str)
                local has_classic_gy = (s.gy or 0) ~= 0
                -- Auf der E-Seite (und beim Hovern eines Teilsystems) wird jede Streckenlast
                -- durch ihre Resultierende ersetzt; die Lage zeigt die globale Bemassung.
                local zeigeResultierende = isExplosion
                    or (hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or false
                local resPfeil = isExplosion and math.max(18, drawPxProMeter * 0.24) or 40
                -- Bogen: Lasten entlang des Bogens (t = Anteil des Winkels, wie x in den Lastfunktionen),
                -- Resultierende je Lastart in beliebiger Richtung (zeichneBogenResultierende)
                local gb = istBogen(s) and bogenBildGeometrie(s, px1, py1, px2, py2, drawPxProMeter) or nil
                local function achse(t)
                    if gb then
                        local ax, ay, atx, aty = bogenPunkt(gb, t * gb.alpha)
                        return ax, ay, atx, aty, -aty, atx
                    end
                    return px1 + dx * t, py1 + dy * t, ux, uy, nx, ny
                end
                local resGerade = zeigeResultierende and not gb
                if zeigeResultierende and gb then zeichneBogenResultierende(gc, s, orig_px1, orig_py1, drawPxProMeter, resPfeil) end
                if resGerade and (has_classic_gy or has_cas_gy) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local L_eff = s.gy_proj and math.abs(dx_m) or L_phys
                    local gy0 = s.gy or 0
                    local Rgy, Sgy = lastResultierende(s.gy_pts, L_phys, gy0, gy0,
                        s.R_gy_cas, s.S_gy_cas, L_phys > 1e-9 and (L_eff / L_phys) or 1)
                    if math.abs(Rgy) > 1e-4 then
                        local x_res = Sgy / Rgy
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        gc:setColorRGB(255, 150, 0)
                        local dir = Rgy > 0 and 1 or -1
                        drawArrow(gc, px_res, py_res - resPfeil * dir, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(resultierendenLabel(L_phys, L_eff, s.gy_str, nil, nil, s.R_gy_cas_str, s.S_gy_cas_str, Rgy, Sgy, "g"),
                            px_res + 5, py_res - (resPfeil + 5) * dir - 10)
                        merkeResultierende(knoten[s.k1].x + ux * x_res, knoten[s.k1].y + uy * x_res)
                    end
                elseif not zeigeResultierende and (has_classic_gy or has_cas_gy) then
                    local steps = 10
                    local max_gy = 0
                    if has_cas_gy and s.gy_pts then
                        for j=1, 11 do if math.abs(s.gy_pts[j]) > max_gy then max_gy = math.abs(s.gy_pts[j]) end end
                else max_gy = math.abs(s.gy) end

                    if max_gy > 0 then
                        gc:setColorRGB(255, 150, 0)
                        local scale_gy = 20 / max_gy
                        if s.gy_proj then
                            local ref_gy = has_cas_gy and (s.gy_pts and s.gy_pts[1] or 0) or s.gy
                            -- Bezugslinie ueber (bzw. unter) dem ganzen Stab, beim Bogen ueber dem Scheitel
                            local y_min, y_max = math.min(py1, py2), math.max(py1, py2)
                            for j = 1, steps - 1 do local _, ay = achse(j / steps); y_min, y_max = math.min(y_min, ay), math.max(y_max, ay) end
                            local top_y = y_min - 25; if ref_gy < 0 then top_y = y_max + 25 end
                            gc:drawLine(px1, py1, px1, top_y); gc:drawLine(px2, py2, px2, top_y)
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gy_val = has_cas_gy and (s.gy_pts and s.gy_pts[j+1] or 0) or s.gy
                                local dir = gy_val > 0 and -1 or 1
                                local h_curr = math.abs(gy_val) * scale_gy * dir
                                local ax = achse(t)
                                local tailX, tailY = ax, top_y + h_curr
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, ax, top_y, LASTPFEIL_KOPF) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts); gc:drawLine(px1, top_y, px2, top_y)
                        else
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gy_val = has_cas_gy and (s.gy_pts and s.gy_pts[j+1] or 0) or s.gy
                                local dir = gy_val > 0 and -1 or 1
                                local h_curr = math.abs(gy_val) * scale_gy * dir
                                local ax, ay = achse(t)
                                local tailX, tailY = ax, ay + h_curr
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, ax, ay, LASTPFEIL_KOPF) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts)
                        end
                    end
                end

                local has_cas_gx = s.gx_str and string.hasx(s.gx_str)
                local has_classic_gx = (s.gx or 0) ~= 0
                if resGerade and (has_classic_gx or has_cas_gx) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local L_eff = s.gx_proj and math.abs(dy_m) or L_phys
                    local gx0 = s.gx or 0
                    local Rgx, Sgx = lastResultierende(s.gx_pts, L_phys, gx0, gx0,
                        s.R_gx_cas, s.S_gx_cas, L_phys > 1e-9 and (L_eff / L_phys) or 1)
                    if math.abs(Rgx) > 1e-4 then
                        local x_res = Sgx / Rgx
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        gc:setColorRGB(255, 150, 0)
                        local dir = Rgx > 0 and -1 or 1
                        drawArrow(gc, px_res + resPfeil * dir, py_res, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(resultierendenLabel(L_phys, L_eff, s.gx_str, nil, nil, s.R_gx_cas_str, s.S_gx_cas_str, Rgx, Sgx, "g"),
                            px_res + (resPfeil + 5) * dir + 5, py_res - 10)
                        merkeResultierende(knoten[s.k1].x + ux * x_res, knoten[s.k1].y + uy * x_res)
                    end
                elseif not zeigeResultierende and (has_classic_gx or has_cas_gx) then
                    local steps = 10
                    local max_gx = 0
                    if has_cas_gx and s.gx_pts then
                        for j=1, 11 do if math.abs(s.gx_pts[j]) > max_gx then max_gx = math.abs(s.gx_pts[j]) end end
                else max_gx = math.abs(s.gx) end

                    if max_gx > 0 then
                        gc:setColorRGB(255, 150, 0)
                        local scale_gx = 20 / max_gx
                        if s.gx_proj then
                            local ref_gx = has_cas_gx and (s.gx_pts and s.gx_pts[1] or 0) or s.gx
                            -- Bezugslinie links (bzw. rechts) neben dem ganzen Stab, beim Bogen neben seinem Scheitel
                            local x_min, x_max = math.min(px1, px2), math.max(px1, px2)
                            for j = 1, steps - 1 do local ax = achse(j / steps); x_min, x_max = math.min(x_min, ax), math.max(x_max, ax) end
                            local side_x = x_min - 25; if ref_gx < 0 then side_x = x_max + 25 end
                            gc:drawLine(px1, py1, side_x, py1); gc:drawLine(px2, py2, side_x, py2)
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gx_val = has_cas_gx and (s.gx_pts and s.gx_pts[j+1] or 0) or s.gx
                                local dir = gx_val > 0 and -1 or 1
                                local h_curr = math.abs(gx_val) * scale_gx * dir
                                local _, ay = achse(t)
                                local tailX, tailY = side_x + h_curr, ay
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, side_x, ay, LASTPFEIL_KOPF) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts); gc:drawLine(side_x, py1, side_x, py2)
                        else
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gx_val = has_cas_gx and (s.gx_pts and s.gx_pts[j+1] or 0) or s.gx
                                local dir = gx_val > 0 and -1 or 1
                                local h_curr = math.abs(gx_val) * scale_gx * dir
                                local ax, ay = achse(t)
                                local tailX, tailY = ax + h_curr, ay
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, ax, ay, LASTPFEIL_KOPF) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts)
                        end
                    end
                end

                gc:setColorRGB(255, 50, 50)
                local has_classic_q = (s.q + s.q_A ~= 0) or (s.q + s.q_B ~= 0)
                local has_cas_q = (s.q_pts and #s.q_pts == 11)

                if resGerade and (has_classic_q or has_cas_q) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                    local Rq, Sq = lastResultierende(s.q_pts, L_phys, qA, qB, s.R_q_cas, s.S_q_cas)
                    if math.abs(Rq) > 1e-4 then
                        local x_res = Sq / Rq
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        local vz = Rq > 0 and 1 or -1
                        drawArrow(gc, px_res - nx * resPfeil * vz, py_res - ny * resPfeil * vz, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(resultierendenLabel(L_phys, L_phys, s.q_str, s.q_A_str, s.q_B_str, s.R_q_cas_str, s.S_q_cas_str, Rq, Sq, "q"),
                            px_res - nx * (resPfeil + 5) * vz - 10, py_res - ny * (resPfeil + 5) * vz - 10)
                        merkeResultierende(knoten[s.k1].x + ux * x_res, knoten[s.k1].y + uy * x_res)
                    end
                elseif not zeigeResultierende and (has_classic_q or has_cas_q) then
                    local combined_q = {}; local max_abs_q = 0
                    for j = 0, 10 do
                        local t = j / 10; local q_class = (s.q + s.q_A)*(1-t) + (s.q + s.q_B)*t
                        local q_tot = has_cas_q and s.q_pts[j+1] or q_class
                        table.insert(combined_q, q_tot)
                        if math.abs(q_tot) > max_abs_q then max_abs_q = math.abs(q_tot) end
                    end

                    if max_abs_q > 0 then
                        local scale_q = 25 / max_abs_q; local pts_env = {}
                        for j = 0, 10 do
                            local t = j / 10; local h_curr = -combined_q[j+1] * scale_q
                            local fx, fy, _, _, qnx, qny = achse(t)
                            table.insert(pts_env, fx + qnx*h_curr); table.insert(pts_env, fy + qny*h_curr)
                            if math.abs(h_curr) > 0.5 then drawArrow(gc, fx + qnx*h_curr, fy + qny*h_curr, fx, fy, LASTPFEIL_KOPF) end
                        end
                        gc:setPen("thin", "smooth"); gc:drawPolyLine(pts_env)
                        gc:drawLine(px1, py1, pts_env[1], pts_env[2]); gc:drawLine(px2, py2, pts_env[#pts_env-1], pts_env[#pts_env])
                        
                    end
                end

                local has_classic_n = (s.n + s.n_A ~= 0) or (s.n + s.n_B ~= 0)
                local has_cas_n = (s.n_pts and #s.n_pts == 11)

                if resGerade and (has_classic_n or has_cas_n) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local nA = s.n + (s.n_A or 0); local nB = s.n + (s.n_B or 0)
                    local Rn, Sn = lastResultierende(s.n_pts, L_phys, nA, nB, s.R_n_cas, s.S_n_cas)
                    if math.abs(Rn) > 1e-4 then
                        local x_res = Sn / Rn
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        local vz = Rn > 0 and 1 or -1
                        drawArrow(gc, px_res - ux * resPfeil * vz, py_res - uy * resPfeil * vz, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(resultierendenLabel(L_phys, L_phys, s.n_str, s.n_A_str, s.n_B_str, s.R_n_cas_str, s.S_n_cas_str, Rn, Sn, "q"),
                            px_res - ux * (resPfeil + 5) * vz + 5, py_res - uy * (resPfeil + 5) * vz - 10)
                        merkeResultierende(knoten[s.k1].x + ux * x_res, knoten[s.k1].y + uy * x_res)
                    end
                elseif not zeigeResultierende and (has_classic_n or has_cas_n) then
                    local combined_n = {}; local max_abs_n = 0
                    for j = 0, 10 do
                        local t = j / 10; local n_class = (s.n + s.n_A)*(1-t) + (s.n + s.n_B)*t
                        local n_c = (has_cas_n and s.n_pts[j+1]) or 0
                        local n_tot = n_class + n_c
                        table.insert(combined_n, n_tot)
                        if math.abs(n_tot) > max_abs_n then max_abs_n = math.abs(n_tot) end
                    end

                    if max_abs_n > 0 then
                        local dist = 14
                        if gb then
                            local linie = {}
                            for j = 0, 10 do
                                local ax, ay, _, _, anx, any = achse(j / 10)
                                linie[#linie + 1] = ax + anx*dist; linie[#linie + 1] = ay + any*dist
                            end
                            gc:drawPolyLine(linie)
                        else
                            gc:drawLine(px1 + nx*dist, py1 + ny*dist, px2 + nx*dist, py2 + ny*dist)
                        end
                        for j = 0, 10, 2 do
                            local ax, ay, aux, auy, anx, any = achse(j/10)
                            local n_curr = combined_n[j+1]; local fx, fy = ax + anx*dist, ay + any*dist
                            if math.abs(n_curr) > 0.5 then
                                local arr_len = (n_curr/max_abs_n)*12
                                drawArrow(gc, fx - aux*arr_len, fy - auy*arr_len, fx + aux*arr_len, fy + auy*arr_len, LASTPFEIL_KOPF)
                            end
                        end
                        
                    end
                end

                local has_classic_m = (s.m ~= 0)
                local has_cas_m = (s.m_pts and #s.m_pts == 11)

                if resGerade and (has_classic_m or has_cas_m) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local m0 = s.m or 0
                    local Rm = lastResultierende(s.m_pts, L_phys, m0, m0, s.R_m_cas, nil)
                    if math.abs(Rm) > 1e-4 then
                        local pxm = (orig_px1 + orig_px2) / 2
                        local pym = (orig_py1 + orig_py2) / 2
                        gc:setColorRGB(255, 150, 0)
                        drawMoment(gc, pxm, pym, 12, Rm < 0)
                        gc:setFont("sansserif", "b", 8)
                        local lbl = "M = " .. formatLabel(math.abs(Rm))
                        if symbolischer_modus and s.m_str and s.m_str ~= "0" then
                            lbl = "M = (" .. s.m_str .. ")*" .. symbLaenge(L_phys)
                        end
                        gc:drawString(lbl, pxm + 15, pym - 10)
                    end
                elseif not zeigeResultierende and (has_classic_m or has_cas_m) then
                    local combined_m = {}; local max_abs_m = 0
                    for j = 0, 10 do
                        local m_class = s.m; local m_c = (has_cas_m and s.m_pts[j+1]) or 0; local m_tot = m_class + m_c
                        table.insert(combined_m, m_tot)
                        if math.abs(m_tot) > max_abs_m then max_abs_m = math.abs(m_tot) end
                    end
                    if max_abs_m > 0 then
                        for j = 1, 9, 2 do
                            local t = j/10; local m_curr = combined_m[j+1]; local fx, fy = achse(t)
                            if math.abs(m_curr) > 0.5 then drawMoment(gc, fx, fy, 8, m_curr < 0) end
                        end
                        
                    end
                end

                if (s.x_mA or 0) ~= 0 then gc:setColorRGB(200, 0, 200); gc:setPen("thin", "smooth"); drawRodMoment(gc, px1, py1, ux, uy, s.x_mA < 0) end
                if (s.x_mB or 0) ~= 0 then gc:setColorRGB(200, 0, 200); gc:setPen("thin", "smooth"); drawRodMoment(gc, px2, py2, -ux, -uy, s.x_mB < 0) end
                
                if (modusText == "System" or (fachwerkModus and ansichtsModus == "N")) and fachwerkModus and s.s_local and L > 0 and not isExplosion then
                    local N_val = -(s.s_local[1] or 0)
                    local is_zero = math.abs(N_val) < 1e-4
                    if not is_zero or symbolischer_modus or not s.is_zero_force or modusText ~= "System" then
                        gc:setFont("sansserif", "r", 8)
                        if N_val > 1e-4 then gc:setColorRGB(0, 0, 200) elseif N_val < -1e-4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 180, 0) end
                        local n_str = symbolischer_modus and fm(s.symb_N_start or "0", true) or formatLabel(N_val)
                        gc:drawString(n_str, (px1+px2)/2 - gc:getStringWidth(n_str)/2, (py1+py2)/2 - 15)
                        gc:setColorRGB(0, 0, 0)
                    end
                end

            elseif not isExplosion and not s.is_cut and not isPolplan and (s.bogen_r or 0) ~= 0 and s.arc_plot_data and (ansichtsModus == "N" or ansichtsModus == "Q" or ansichtsModus == "M" or ansichtsModus == "W" or ansichtsModus == "U") and not skip_diagram then
                local max_val_ext, best_px, best_py, best_nx, best_ny = 0, 0, 0, 0, 0
                local R = math.abs(s.bogen_r)
                local sgn = s.bogen_r > 0 and -1 or 1
                local r_px = R * drawPxProMeter
                local d_px = math.sqrt(r_px^2 - (L/2)^2)
                
                local poly_pts = render_pts_1; for k_idx=1,#poly_pts do poly_pts[k_idx]=nil end
                local ref_pts = render_pts_2; for k_idx=1,#ref_pts do ref_pts[k_idx]=nil end
                local num_seg = #s.arc_plot_data
                for j = 0, num_seg do
                    local t = j / num_seg
                    
                    local val = 0
                    local px_val, py_val
                    local nx_t, ny_t = 0, 0
                    
                    local xl = (t - 0.5) * true_L
                    local denom = math.sqrt(math.max(1e-6, R^2 - xl^2))
                    local tx_l, ty_l = 1, -sgn * (xl / denom)
                    local len = math.sqrt(tx_l^2 + ty_l^2)
                    tx_l, ty_l = tx_l/len, ty_l/len
                    local t_gx = tx_l * (dx/L) - ty_l * (dy/L)
                    local t_gy = tx_l * (dy/L) + ty_l * (dx/L)
                    local nx_t, ny_t = -t_gy, t_gx
                    
                    if j == 0 then s.arc_nx0, s.arc_ny0 = nx_t, ny_t end
                    if j == num_seg then s.arc_nx1, s.arc_ny1 = nx_t, ny_t end
                    
                    local x_local_px = (t - 0.5) * L
                    local y_local_px = sgn * (math.sqrt(r_px^2 - x_local_px^2) - d_px)
                    local ax = (px1+px2)/2 + x_local_px * (dx/L) - y_local_px * (dy/L)
                    local ay = (py1+py2)/2 + x_local_px * (dy/L) + y_local_px * (dx/L)
                    
                    if ansichtsModus == "W" then
                        local pd_left = j > 0 and s.arc_plot_data[j] or s.arc_plot_data[1]
                        local disp_x = (j == 0) and (pd_left.disp_x1 or 0) or (pd_left.disp_x2 or 0)
                        local disp_y = (j == 0) and (pd_left.disp_y1 or 0) or (pd_left.disp_y2 or 0)
                        val = math.sqrt(disp_x^2 + disp_y^2)
                        px_val = ax + disp_x * drawScale
                        py_val = ay + disp_y * drawScale
                    elseif ansichtsModus == "U" then
                        local pd_left = j > 0 and s.arc_plot_data[j] or s.arc_plot_data[1]
                        local disp_x = (j == 0) and (pd_left.disp_x1 or 0) or (pd_left.disp_x2 or 0)
                        local disp_y = (j == 0) and (pd_left.disp_y1 or 0) or (pd_left.disp_y2 or 0)
                        val = disp_x * t_gx + disp_y * t_gy
                        local dist = val * drawScale
                        px_val = ax + nx_t * dist
                        py_val = ay + ny_t * dist
                    else
                        local pd_left = j > 0 and s.arc_plot_data[j] or s.arc_plot_data[1]
                        local pd_right = j < num_seg and s.arc_plot_data[j+1] or s.arc_plot_data[num_seg]
                        if ansichtsModus == "M" then
                            if j == 0 then val = pd_right.M1
                            elseif j == num_seg then val = pd_left.M2
                            else val = (pd_left.M2 + pd_right.M1) / 2 end
                        else
                            -- Endwert des linken und Anfangswert des rechten Teilstuecks (mit Bogenlast verschieden)
                            local f = ansichtsModus == "N" and "N" or "Q"
                            local links = pd_left[f .. "2"] or pd_left[f]
                            if j == 0 then val = pd_right[f]
                            elseif j == num_seg then val = links
                            else val = (links + pd_right[f]) / 2 end
                        end
                        local dist = val * drawScale
                        px_val = ax + nx_t * dist
                        py_val = ay + ny_t * dist
                    end
                    
                    table.insert(poly_pts, px_val)
                    table.insert(poly_pts, py_val)
                    table.insert(ref_pts, ax)
                    table.insert(ref_pts, ay)
                    
                    if math.abs(val) >= math.abs(max_val_ext) then max_val_ext = val; best_px = px_val; best_py = py_val; best_nx = nx_t; best_ny = ny_t; best_j = j end
                end
                
                if ansichtsModus == "M" then gc:setColorRGB(200, 50, 50) elseif ansichtsModus == "Q" then gc:setColorRGB(50, 150, 50) elseif ansichtsModus == "N" then gc:setColorRGB(50, 50, 200) elseif ansichtsModus == "W" then gc:setColorRGB(200, 0, 200) elseif ansichtsModus == "U" then gc:setColorRGB(255, 120, 0) end
                gc:setPen("thin", "smooth")
                
                if ansichtsModus == "W" or ansichtsModus == "U" then
                    local smooth_pts = render_pts_3 or {}; render_pts_3 = smooth_pts; for k_idx=1,#smooth_pts do smooth_pts[k_idx]=nil end
                    local n_pts = #poly_pts / 2
                    for i = 1, n_pts - 1 do
                        local p0x = poly_pts[math.max(1, i-1)*2 - 1]
                        local p0y = poly_pts[math.max(1, i-1)*2]
                        local p1x = poly_pts[i*2 - 1]
                        local p1y = poly_pts[i*2]
                        local p2x = poly_pts[(i+1)*2 - 1]
                        local p2y = poly_pts[(i+1)*2]
                        local p3x = poly_pts[math.min(n_pts, i+2)*2 - 1]
                        local p3y = poly_pts[math.min(n_pts, i+2)*2]
                        
                        local steps = 4
                        for j = 0, steps - 1 do
                            local t = j / steps
                            local t2 = t * t
                            local t3 = t2 * t
                            local v0x = (p2x - p0x) * 0.5
                            local v0y = (p2y - p0y) * 0.5
                            local v1x = (p3x - p1x) * 0.5
                            local v1y = (p3y - p1y) * 0.5
                            
                            local px = (2*p1x - 2*p2x + v0x + v1x)*t3 + (-3*p1x + 3*p2x - 2*v0x - v1x)*t2 + v0x*t + p1x
                            local py = (2*p1y - 2*p2y + v0y + v1y)*t3 + (-3*p1y + 3*p2y - 2*v0y - v1y)*t2 + v0y*t + p1y
                            table.insert(smooth_pts, px)
                            table.insert(smooth_pts, py)
                        end
                    end
                    table.insert(smooth_pts, poly_pts[#poly_pts-1])
                    table.insert(smooth_pts, poly_pts[#poly_pts])
                    gc:drawPolyLine(smooth_pts)
                else
                    gc:drawPolyLine(poly_pts)
                end
                
                if ansichtsModus ~= "W" and ansichtsModus ~= "U" then
                    gc:setColorRGB(180, 180, 180); gc:setPen("thin", "smooth")
                    for j=1, num_seg+1 do
                        gc:drawLine(ref_pts[j*2-1], ref_pts[j*2], poly_pts[j*2-1], poly_pts[j*2])
                    end
                end
                
                if ansichtsModus ~= "W" and ansichtsModus ~= "U" then
                    local pd_first = s.arc_plot_data[1]
                    local pd_last = s.arc_plot_data[num_seg]
                    local v_start = (ansichtsModus == "N" and pd_first.N) or (ansichtsModus == "Q" and pd_first.Q) or (pd_first.M1)
                    local v_end = (ansichtsModus == "N" and (pd_last.N2 or pd_last.N)) or (ansichtsModus == "Q" and (pd_last.Q2 or pd_last.Q)) or (pd_last.M2)
                    
                    gc:setFont("sansserif", "r", 8); gc:setColorRGB(0, 0, 0)
                    if schnittAnzeigeModus ~= "Hover" then
                        gc:drawString(getSymbLabel(s, ansichtsModus, "start", v_start), poly_pts[1] + s.arc_nx0*5, poly_pts[2] + s.arc_ny0*5)
                        gc:drawString(getSymbLabel(s, ansichtsModus, "end", v_end), poly_pts[#poly_pts-1] + s.arc_nx1*5, poly_pts[#poly_pts] + s.arc_ny1*5)
                    end
                end

                if ansichtsModus == "W" or ansichtsModus == "U" then
                    if math.abs(max_val_ext) > 1e-12 then
                        if ansichtsModus == "W" then
                            gc:setColorRGB(200, 0, 200)
                            gc:fillArc(best_px - 1, best_py - 1, 3, 3, 0, 360)
                        else
                            gc:setColorRGB(255, 120, 0)
                            gc:fillArc(best_px - 2, best_py - 2, 5, 5, 0, 360)
                        end
                        gc:setFont("sansserif", "r", 8)
                        if zeigeMaxWerte then gc:drawString(string.format("max: %.3f mm", max_val_ext*1000), best_px + best_nx*6, best_py + best_ny*6) end
                    end
                elseif ansichtsModus == "N" or ansichtsModus == "Q" or ansichtsModus == "M" then
                    if math.abs(max_val_ext) > 1e-12 then
                        if ansichtsModus == "M" then gc:setColorRGB(200, 50, 50) elseif ansichtsModus == "Q" then gc:setColorRGB(50, 150, 50) else gc:setColorRGB(50, 50, 200) end
                        gc:fillArc(best_px - 2, best_py - 2, 5, 5, 0, 360)
                        if zeigeMaxWerte and best_j > 0 and best_j < num_seg then 
                            gc:setFont("sansserif", "r", 8)
                            gc:drawString(getSymbLabel(s, ansichtsModus, "max", max_val_ext), best_px + best_nx*6, best_py + best_ny*6)
                        end
                    end
                end
                
                if (ansichtsModus == "M" or ansichtsModus == "N" or ansichtsModus == "Q") then
                    -- Wert am Teilungspunkt idx-1 (Anfang von Teilstueck idx; letzter Punkt: Ende des letzten)
                    local function get_arc_val(idx)
                        local pd = s.arc_plot_data[idx]
                        if not pd then
                            pd = s.arc_plot_data[idx - 1]
                            if not pd then return 0 end
                            if ansichtsModus == "N" then return pd.N2 or pd.N
                            elseif ansichtsModus == "Q" then return pd.Q2 or pd.Q end
                            return pd.M2
                        end
                        if ansichtsModus == "N" then return pd.N
                        elseif ansichtsModus == "Q" then return pd.Q
                        elseif ansichtsModus == "M" then return pd.M1 end
                        return 0
                    end
                    
                    if s.messpunkte then
                        for _, t_m in ipairs(s.messpunkte) do
                            local hover_j = math.max(1, math.min(#s.arc_plot_data, math.floor(t_m * #s.arc_plot_data + 0.5)))
                            local h_px = poly_pts[hover_j*2 - 1] or poly_pts[1]
                            local h_py = poly_pts[hover_j*2] or poly_pts[2]
                            local h_val = get_arc_val(hover_j)
                            local h_x = t_m * math.abs(s.bogen_alpha or 1) * math.abs(s.bogen_r or 1)
                            gc:setColorRGB(0, 150, 0)
                            gc:fillArc(h_px - 3, h_py - 3, 7, 7, 0, 360)
                            gc:setColorRGB(255, 255, 220); gc:fillRect(h_px, h_py, 100, 16)
                            gc:setColorRGB(0, 0, 0); gc:drawRect(h_px, h_py, 100, 16)
                            gc:drawString(string.format("s=%.2fm: %.2f", h_x, h_val), h_px + 2, h_py)
                        end
                    end
                    
                    if schnittAnzeigeModus == "Hover" and hoverObj == i and hoverTyp == "stab" then
                        -- Find closest point on arc
                        local min_dist = math.huge
                        local best_idx = 1
                        local n_pts = #poly_pts / 2
                        for j = 1, n_pts do
                            local px = poly_pts[j*2 - 1]
                            local py = poly_pts[j*2]
                            local d = (mouseX - px)^2 + (mouseY - py)^2
                            if d < min_dist then min_dist = d; best_idx = j end
                        end
                        
                        if min_dist < 400 then
                            local h_px = poly_pts[best_idx*2 - 1]
                            local h_py = poly_pts[best_idx*2]
                            local h_val = get_arc_val(best_idx)
                            -- Bogenlaenge bis zum Teilungspunkt (Winkel aus der Rechnung)
                            local pd_h = s.arc_plot_data[best_idx]
                            local phi_h = pd_h and pd_h.phi1 or s.bogen_alpha or 0
                            local h_x = math.abs(phi_h) * math.abs(s.bogen_r or 1)
                            gc:setColorRGB(255, 0, 0)
                            gc:fillArc(h_px - 3, h_py - 3, 7, 7, 0, 360)
                            gc:setColorRGB(255, 255, 220); gc:fillRect(h_px, h_py, 100, 16)
                            gc:setColorRGB(0, 0, 0); gc:drawRect(h_px, h_py, 100, 16)
                            gc:drawString(string.format("s=%.2fm: %.2f", h_x, h_val), h_px + 2, h_py)
                        end
                    end
                end
            elseif ansichtsModus ~= "System" and not isExplosion and not s.is_cut and not isPolplan and (s.bogen_r or 0) == 0 and not skip_diagram then
                local L_m = math.sqrt((knoten[s.k2].x - knoten[s.k1].x)^2 + (knoten[s.k2].y - knoten[s.k1].y)^2)
                local c_val, s_val = dx/L, -dy/L
                local eff_gx = (s.gx or 0) * (s.gx_proj and math.abs(s_val) or 1); local eff_gy = (s.gy or 0) * (s.gy_proj and math.abs(c_val) or 1)
                local n_add = eff_gx * c_val - eff_gy * s_val; local q_add = eff_gx * s_val + eff_gy * c_val

                local N0, Q0, M0 = -s.s_local[1], -s.s_local[2], -s.s_local[3]
                local qA, qB = s.q + s.q_A + q_add, s.q + s.q_B + q_add; local nA, nB = s.n + s.n_A + n_add, s.n + s.n_B + n_add
                if s.q_in_cas then qA, qB = 0, 0 end; if s.n_in_cas then nA, nB = 0, 0 end -- sonst doppelt zu cas_*_drop
                local pts = render_pts_1; for k_idx=1,#pts do pts[k_idx]=nil end
                local min_val, max_val_ext, best_t, best_px, best_py = 0, 0, 0, px1, py1

                for j = 0, ptsBiegelinie do
                    local t = j / ptsBiegelinie; local x = t * L_m; local val = 0
                    local cas_Q_drop = (s.Q_cas_pts and s.Q_cas_pts[j+1]) or 0
                    local cas_M_drop = (s.M_cas_pts and s.M_cas_pts[j+1]) or 0
                    local cas_N_drop = (s.N_cas_pts and s.N_cas_pts[j+1]) or 0

                    if ansichtsModus == "N" then val = N0 - (nA*x + (nB-nA)*(x^2)/(2*L_m)) - cas_N_drop
                    elseif ansichtsModus == "Q" then val = Q0 - (qA*x + (qB-qA)*(x^2)/(2*L_m)) - cas_Q_drop
                    elseif ansichtsModus == "M" then val = M0 + Q0*x - s.m*x - (qA*(x^2)/2 + (qB-qA)*(x^3)/(6*L_m)) - cas_M_drop
                    elseif ansichtsModus == "U" then val = get_u_val(s, x, L_m, j, nA, nB)
                    elseif ansichtsModus == "W" then
                        local EI = stabEI(s)
                        local c1 = (s.v_local[2] or 0) * EI
                        local c2 = -(s.v_local[3] or 0) * EI
                        local c3 = (s.v_local[5] or 0) * EI
                        local c4 = -(s.v_local[6] or 0) * EI
                        local xi = x / L_m
                        local val_homogen_EI = c1*(1-3*xi^2+2*xi^3) + c2*(x-2*x^2/L_m+x^3/(L_m^2)) + c3*(3*xi^2-2*xi^3) + c4*(-x^2/L_m+x^3/(L_m^2))
                        local v_part_class_EI = (x^2 * (L_m - x)^2) / (120 * L_m) * ((3*L_m - x)*qA + (2*L_m + x)*qB)
                        local v_part_cas_EI = (s.v_cas_pts_EI and s.v_cas_pts_EI[j+1]) or 0
                        val = (val_homogen_EI + v_part_class_EI + v_part_cas_EI) / EI
                    end

                    -- wie oben: Verschiebungen (in m) erst unter 1e-12 auf null, sonst Knick bei 0,01 mm
                    if math.abs(val) < (((ansichtsModus == "W" or ansichtsModus == "U") and 1e-12) or 1e-5) then val = 0 end
                    local dist = val * drawScale
                    local cur_px = px1 + dx*t + nx*dist
                    local cur_py = py1 + dy*t + ny*dist

                    if ansichtsModus == "W" then
                        local u_val = get_u_val(s, x, L_m, j, nA, nB)
                        cur_px = cur_px + (dx/L)*u_val*drawScale
                        cur_py = cur_py + (dy/L)*u_val*drawScale
                    end

                    if math.abs(val) >= math.abs(max_val_ext) then
                        max_val_ext = val; best_t = t; best_px = cur_px; best_py = cur_py
                    end

                    table.insert(pts, cur_px); table.insert(pts, cur_py)
                    if ansichtsModus ~= "System" and ansichtsModus ~= "E" and ansichtsModus ~= "W" and ansichtsModus ~= "U" and not isPolplan and not isKinematic and not in_pvv_release then gc:setColorRGB(180, 180, 180); gc:drawLine(px1 + dx*t, py1 + dy*t, cur_px, cur_py) end
                end

                if ansichtsModus == "M" then gc:setColorRGB(200, 50, 50) elseif ansichtsModus == "Q" then gc:setColorRGB(50, 150, 50) elseif ansichtsModus == "W" then gc:setColorRGB(200, 0, 200) elseif ansichtsModus == "U" then gc:setColorRGB(255, 120, 0) else gc:setColorRGB(50, 50, 200) end

                if ansichtsModus == "W" or ansichtsModus == "U" then gc:setPen("thin", "smooth") else gc:setPen("thin", "smooth") end
                gc:drawPolyLine(pts); gc:setFont("sansserif", "r", 8); gc:setColorRGB(0, 0, 0)

                local v_start = (ansichtsModus == "N" and N0) or (ansichtsModus == "Q" and Q0) or M0; local v_end = 0
                local cas_Q_end = (s.Q_cas_pts and s.Q_cas_pts[ptsBiegelinie+1]) or 0
                local cas_M_end = (s.M_cas_pts and s.M_cas_pts[ptsBiegelinie+1]) or 0
                local cas_N_end = (s.N_cas_pts and s.N_cas_pts[ptsBiegelinie+1]) or 0

                if ansichtsModus == "N" then v_end = N0 - (nA*L_m + (nB-nA)*(L_m^2)/(2*L_m)) - cas_N_end
                elseif ansichtsModus == "Q" then v_end = Q0 - (qA*L_m + (qB-qA)*(L_m^2)/(2*L_m)) - cas_Q_end
                elseif ansichtsModus == "M" then v_end = M0 + Q0*L_m - s.m*L_m - (qA*(L_m^2)/2 + (qB-qA)*(L_m^3)/(6*L_m)) - cas_M_end
                end

                if ansichtsModus ~= "W" and ansichtsModus ~= "U" then
                if schnittAnzeigeModus ~= "Hover" then
                    gc:drawString(getSymbLabel(s, ansichtsModus, "start", v_start), pts[1] + nx*5, pts[2] + ny*5)
                    gc:drawString(getSymbLabel(s, ansichtsModus, "end", v_end), pts[#pts-1] + nx*5, pts[#pts] + ny*5)
                end
            end

            if ansichtsModus == "W" or ansichtsModus == "U" then
                if math.abs(max_val_ext) > 1e-12 then
                    if ansichtsModus == "W" then
                        gc:setColorRGB(200, 0, 200)
                        gc:fillArc(best_px - 1, best_py - 1, 3, 3, 0, 360)
                    else
                        gc:setColorRGB(255, 120, 0)
                        gc:fillArc(best_px - 2, best_py - 2, 5, 5, 0, 360)
                    end
                    if zeigeMaxWerte then gc:drawString(string.format("max: %.3f mm", max_val_ext*1000), best_px + nx*6, best_py + ny*6) end
                end
            elseif ansichtsModus == "N" or ansichtsModus == "Q" or ansichtsModus == "M" then
                if math.abs(max_val_ext) > 1e-12 then
                    if ansichtsModus == "M" then gc:setColorRGB(200, 50, 50) elseif ansichtsModus == "Q" then gc:setColorRGB(50, 150, 50) else gc:setColorRGB(50, 50, 200) end
                    gc:fillArc(best_px - 2, best_py - 2, 5, 5, 0, 360)
                    if zeigeMaxWerte and best_t > 0.02 and best_t < 0.98 then 
                        gc:setFont("sansserif", "r", 8)
                        gc:drawString(getSymbLabel(s, ansichtsModus, "max", max_val_ext), best_px + nx*6, best_py + ny*6)
                    end
                end
            end
            
            if (ansichtsModus == "M" or ansichtsModus == "N" or ansichtsModus == "Q") then
                local function eval_at_t(t_h)
                    local hover_j = math.floor(t_h * ptsBiegelinie + 0.5)
                    local h_px = pts[hover_j*2 + 1] or pts[1]
                    local h_py = pts[hover_j*2 + 2] or pts[2]
                    local h_x = t_h * L_m
                    local h_val = 0
                    local cas_Q_drop = (s.Q_cas_pts and s.Q_cas_pts[hover_j+1]) or 0
                    local cas_M_drop = (s.M_cas_pts and s.M_cas_pts[hover_j+1]) or 0
                    local cas_N_drop = (s.N_cas_pts and s.N_cas_pts[hover_j+1]) or 0
                    if ansichtsModus == "N" then h_val = N0 - (nA*h_x + (nB-nA)*(h_x^2)/(2*L_m)) - cas_N_drop
                    elseif ansichtsModus == "Q" then h_val = Q0 - (qA*h_x + (qB-qA)*(h_x^2)/(2*L_m)) - cas_Q_drop
                    elseif ansichtsModus == "M" then h_val = M0 + Q0*h_x - s.m*h_x - (qA*(h_x^2)/2 + (qB-qA)*(h_x^3)/(6*L_m)) - cas_M_drop end
                    return h_px, h_py, h_x, h_val
                end
                
                if s.messpunkte then
                    for _, t_m in ipairs(s.messpunkte) do
                        local h_px, h_py, h_x, h_val = eval_at_t(t_m)
                        gc:setColorRGB(0, 150, 0)
                        gc:fillArc(h_px - 3, h_py - 3, 7, 7, 0, 360)
                        gc:setColorRGB(255, 255, 220); gc:fillRect(h_px + nx*10, h_py + ny*10, 100, 16)
                        gc:setColorRGB(0, 0, 0); gc:drawRect(h_px + nx*10, h_py + ny*10, 100, 16)
                        gc:drawString(string.format("X=%.2fm : %.2f", h_x, h_val), h_px + nx*10 + 2, h_py + ny*10)
                    end
                end
                
                if schnittAnzeigeModus == "Hover" and hoverObj == i and hoverTyp == "stab" then
                    local dx_bar, dy_bar = px2 - px1, py2 - py1
                    local L_screen2 = dx_bar*dx_bar + dy_bar*dy_bar
                    if L_screen2 > 0 then
                        local t_h = ((mouseX - px1)*dx_bar + (mouseY - py1)*dy_bar) / L_screen2
                        t_h = math.max(0, math.min(1, t_h))
                        local h_px, h_py, h_x, h_val = eval_at_t(t_h)
                        gc:setColorRGB(255, 0, 0)
                        gc:fillArc(h_px - 3, h_py - 3, 7, 7, 0, 360)
                        gc:setColorRGB(255, 255, 220); gc:fillRect(h_px + nx*10, h_py + ny*10, 100, 16)
                        gc:setColorRGB(0, 0, 0); gc:drawRect(h_px + nx*10, h_py + ny*10, 100, 16)
                        gc:drawString(string.format("X=%.2fm : %.2f", h_x, h_val), h_px + nx*10 + 2, h_py + ny*10)
                    end
                end
            end
            end
        end

        -- ==========================================================
        -- EXPLOSIONSZEICHNUNG: FEINE GELENKKRÄFTE (Anti-Overlap)
        -- ==========================================================
        if isExplosion and s.s_local and L_orig > 0 and not s.is_cut then
            repeat
            if fachwerkModus and isExplosion then
                local ux, uy = dx_orig/L_orig, dy_orig/L_orig
                local startOffset = 5
                local arrowLen = 45
                gc:setColorRGB(0, 150, 0)
                gc:setPen("thin", "smooth")
                
                local val = s.s_local and -s.s_local[1] or 0
                local is_tension = (val >= -1e-7)
                local dir = is_tension and 1 or -1
                if explosionPage == 2 then dir = 1 end
                
                local tailX1 = orig_px1 + ux * startOffset
                local tailY1 = orig_py1 + uy * startOffset  
                local outerX1 = orig_px1 + ux * (startOffset + arrowLen)
                local outerY1 = orig_py1 + uy * (startOffset + arrowLen)
                
                if dir == 1 then drawExplosionArrow(gc, tailX1, tailY1, outerX1, outerY1)
                else drawExplosionArrow(gc, outerX1, outerY1, tailX1, tailY1) end
                
                local lbl
                if explosionPage == 2 then
                    lbl = "S_" .. i
                    e2Pfeil(lbl, ux, uy); e2Pfeil(lbl, -ux, -uy)
                else
                    if symbolischer_modus and s.symb_N_start then
                        local s_str = fm(s.symb_N_start)
                        if dir == -1 and string.sub(s_str, 1, 1) == "-" then
                            s_str = string.sub(s_str, 2)
                        end
                        lbl = s_str
                    else
                        lbl = formatLabel(math.abs(val))
                    end
                end
                gc:setFont("sansserif", "r", 10)
                local tw = gc:getStringWidth(lbl)
                gc:drawString(lbl, outerX1 - tw/2, outerY1 + 5)
                
                local tailX2 = orig_px2 - ux * startOffset
                local tailY2 = orig_py2 - uy * startOffset
                local outerX2 = orig_px2 - ux * (startOffset + arrowLen)
                local outerY2 = orig_py2 - uy * (startOffset + arrowLen)
                
                if dir == 1 then drawExplosionArrow(gc, tailX2, tailY2, outerX2, outerY2)
                else drawExplosionArrow(gc, outerX2, outerY2, tailX2, tailY2) end
                
                gc:drawString(lbl, outerX2 - tw/2, outerY2 + 5)
                
                break
            end
            
            -- Knotenlast global (y nach unten), wie in der Berechnung um -last_w gedreht
            local function knotenlastGlobal(kn)
                local r = math.rad(-(kn.last_w or 0))
                local c, sn = math.cos(r), math.sin(r)
                return (kn.last_x or 0) * c - (kn.last_y or 0) * sn, (kn.last_x or 0) * sn + (kn.last_y or 0) * c
            end
            local function lastLabel(kn, wert, text)
                if symbolischer_modus and (kn.last_w or 0) == 0 and text then return "F = " .. fm(text) end
                return "F = " .. formatLabel(math.abs(wert))
            end

            local function isRigidNodeInTS(node_idx, ts)
                if not ts then return true end
                for _idx, st in ipairs(staebe) do
                    if not st.is_cut and (st.k1 == node_idx or st.k2 == node_idx) and glob_ts_scheibe[_idx] == ts then
                        local explA = knoten[st.k1].gelenk or st.gelenk_A or st.n_gelenk_A or st.q_gelenk_A
                        local explB = knoten[st.k2].gelenk or st.gelenk_B or st.n_gelenk_B or st.q_gelenk_B
                        if st.k1 == node_idx and not explA then return true end
                        if st.k2 == node_idx and not explB then return true end
                    end
                end
                return false
            end

            local function getShiftedNodePos(node_idx, ts)
                local orig_x = knoten[node_idx].x * drawPxProMeter + offsetX
                local orig_y = knoten[node_idx].y * drawPxProMeter + offsetY
                if not isExplosion or not ts then return orig_x, orig_y end
                for _idx, st in ipairs(staebe) do
                    if not st.is_cut and (st.k1 == node_idx or st.k2 == node_idx) and glob_ts_scheibe[_idx] == ts then
                        local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(_idx)
                        local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
                        if st.k1 == node_idx then
                            return orig_x + u1x * anim_f, orig_y + u1y * anim_f
                        else
                            return orig_x + u2x * anim_f, orig_y + u2y * anim_f
                        end
                    end
                end
                return orig_x, orig_y
            end
            
            local ux, uy = dx_orig/L_orig, dy_orig/L_orig
            local nx, ny = -uy, ux

            local Na, Va, Ma = s.s_local[1] or 0, s.s_local[2] or 0, s.s_local[3] or 0
            local Nb, Vb, Mb = s.s_local[4] or 0, s.s_local[5] or 0, s.s_local[6] or 0

            local offsetX_A, offsetY_A, offsetM_A, offsetRx_A, offsetRy_A, offsetRm_A = 0,0,0,0,0,0
            local offsetX_B, offsetY_B, offsetM_B, offsetRx_B, offsetRy_B, offsetRm_B = 0,0,0,0,0,0
            local drawExtA, drawExtB = false, false

            local useLocalA = s.n_gelenk_A or s.q_gelenk_A
            local useLocalB = s.n_gelenk_B or s.q_gelenk_B

            local nodeA_in_ts = (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k1, hovered_ts))
            if explodeA and not loadApplied[s.k1] then
                local kn = knoten[s.k1]
                offsetX_A, offsetY_A = knotenlastGlobal(kn); offsetM_A = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_A = isSupp and kn.Rx_glob or 0; offsetRy_A = isSupp and kn.Ry_glob or 0; offsetRm_A = isSupp and kn.Rm_glob or 0
                if nodeA_in_ts then
                    loadApplied[s.k1] = true; drawExtA = true
                end
            elseif explodeA then
                local kn = knoten[s.k1]
                offsetX_A, offsetY_A = knotenlastGlobal(kn); offsetM_A = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_A = isSupp and kn.Rx_glob or 0; offsetRy_A = isSupp and kn.Ry_glob or 0; offsetRm_A = isSupp and kn.Rm_glob or 0
            end

            local nodeB_in_ts = (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k2, hovered_ts))
            if explodeB and not loadApplied[s.k2] then
                local kn = knoten[s.k2]
                offsetX_B, offsetY_B = knotenlastGlobal(kn); offsetM_B = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_B = isSupp and kn.Rx_glob or 0; offsetRy_B = isSupp and kn.Ry_glob or 0; offsetRm_B = isSupp and kn.Rm_glob or 0
                if nodeB_in_ts then
                    loadApplied[s.k2] = true; drawExtB = true
                end
            elseif explodeB then
                local kn = knoten[s.k2]
                offsetX_B, offsetY_B = knotenlastGlobal(kn); offsetM_B = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_B = isSupp and kn.Rx_glob or 0; offsetRy_B = isSupp and kn.Ry_glob or 0; offsetRm_B = isSupp and kn.Rm_glob or 0
            end

            local uxA, uyA = dx_orig/L_orig, dy_orig/L_orig
            local nxA, nyA = -uyA, uxA
            local uxB, uyB = dx_orig/L_orig, dy_orig/L_orig
            local nxB, nyB = -uyB, uxB
            
            if (s.bogen_r or 0) ~= 0 then
                local true_L = (L_orig / drawPxProMeter)
                local R = math.abs(s.bogen_r)
                local sgn = s.bogen_r > 0 and -1 or 1
                local function getTang(t)
                    local xl = (t - 0.5) * true_L
                    local denom = math.sqrt(math.max(1e-6, R^2 - xl^2))
                    local tx_l, ty_l = 1, -sgn * (xl / denom)
                    local len = math.sqrt(tx_l^2 + ty_l^2)
                    tx_l, ty_l = tx_l/len, ty_l/len
                    local t_gx = tx_l * (dx_orig/L_orig) - ty_l * (dy_orig/L_orig)
                    local t_gy = tx_l * (dy_orig/L_orig) + ty_l * (dx_orig/L_orig)
                    return t_gx, t_gy, -t_gy, t_gx
                end
                uxA, uyA, nxA, nyA = getTang(0)
                uxB, uyB, nxB, nyB = getTang(1)
            end

            local Fx_a = Na * uxA + Va * nxA - (offsetX_A + offsetRx_A)
            local Fy_a = Na * uyA + Va * nyA - (offsetY_A + offsetRy_A)
            local Fx_b = Nb * uxB + Vb * nxB - (offsetX_B + offsetRx_B)
            local Fy_b = Nb * uyB + Vb * nyB - (offsetY_B + offsetRy_B)

            local N_a_proj = Fx_a * uxA + Fy_a * uyA; local V_a_proj = Fx_a * nxA + Fy_a * nyA
            local N_b_proj = Fx_b * uxB + Fy_b * uyB; local V_b_proj = Fx_b * nxB + Fy_b * nyB

            local M_a_disp = -(Ma - (offsetM_A + offsetRm_A))
            local M_b_disp = Mb - (offsetM_B + offsetRm_B)

            local s_Fx_a, s_Fy_a, s_Fx_b, s_Fy_b = nil, nil, nil, nil
            if symbolischer_modus then
                s_Fx_a = s.symb_Fx_a or s.symb_N_start
                s_Fy_a = s.symb_Fy_a or s.symb_Q_start
                s_Fx_b = s.symb_Fx_b or s.symb_N_end
                s_Fy_b = s.symb_Fy_b or s.symb_Q_end
            end

            local function getNumTS(node_idx) return gelenkKnoten(node_idx).numTS end
            local lblSuffixA = getNumTS(s.k1) > 2 and ("s"..(s.ts_scheibe or i)) or ""
            local lblSuffixB = getNumTS(s.k2) > 2 and ("s"..(s.ts_scheibe or i)) or ""
            -- Richtung der Gelenkgroessen wie im LGS-Export (gelenkRichtung), bezogen auf die
            -- Grundrichtung der Zeichnung (Stabanfang -1, Stabende +1)
            local function getFlipMultiplier(node_idx, s_idx)
                local e = (staebe[s_idx].k1 == node_idx) and -1 or 1
                return gelenkRichtung(node_idx, s_idx) * e
            end
            -- Gelenkgroessen nur, wenn am Knoten mindestens zwei Teilsysteme zusammenkommen
            local mehrA, mehrB = getNumTS(s.k1) > 1, getNumTS(s.k2) > 1

            local flipA = getFlipMultiplier(s.k1, i)
            local flipB = getFlipMultiplier(s.k2, i)
            local isHingeA = s.n_gelenk_A or s.q_gelenk_A or s.gelenk_A or knoten[s.k1].gelenk
            local prefixN_A = (explosionPage == 2 and isHingeA) and ("Gn_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "N = "
            local prefixQ_A = (explosionPage == 2 and isHingeA) and ("Gq_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "Q = "
            local prefixM_A = (explosionPage == 2 and isHingeA) and ("Gm_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "M = "
            local isMHingeA = knoten[s.k1].gelenk or s.gelenk_A

            if explodeA and (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k1, hovered_ts)) then
                local val_N, val_Q, val_h, val_v
                if mehrA and (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts)) then
                    if useLocalA then
                        val_N = -N_a_proj; val_Q = -V_a_proj
                        if not s.n_gelenk_A then drawFBDArrow(gc, val_N, -ux, -uy, px1, py1, prefixN_A, nil, symbolischer_modus and fm(s.symb_N_start) or nil, explosionPage == 2, flipA) end
                        if not s.q_gelenk_A then drawFBDArrow(gc, val_Q, -nx, -ny, px1, py1, prefixQ_A, nil, symbolischer_modus and fm(s.symb_Q_start) or nil, explosionPage == 2, flipA) end
                    else
                        val_h = -Fx_a; val_v = -Fy_a
                        drawFBDArrow(gc, val_h, -1, 0, px1, py1, "h = ", "Gx_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fx_a) or nil, explosionPage == 2, flipA)
                        drawFBDArrow(gc, val_v, 0, -1, px1, py1, "v = ", "Gy_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fy_a) or nil, explosionPage == 2, flipA)
                    end

                    if not isMHingeA then
                        if math.abs(M_a_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            local cw = M_a_disp > 0
                            if explosionPage == 2 then cw = flipA > 0; e2Moment(prefixM_A:gsub(" = ", ""), cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px1, py1, 16, cw)
                            gc:setFont("sansserif", "r", 10)
                            local label_m
                            if explosionPage == 2 then
                                label_m = prefixM_A:gsub(" = ", "")
                            else
                                local m_lbl = symbolischer_modus and fm(s.symb_Ma_disp) or formatLabel(math.abs(M_a_disp))
                                label_m = prefixM_A .. m_lbl
                            end
                            gc:drawString(label_m, px1 - ux*45 - 20, py1 - uy*45 - 10)
                        end
                    end
                end

                if drawExtA then
                    if offsetX_A ~= 0 or offsetY_A ~= 0 or offsetM_A ~= 0 then
                        if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(255, 50, 50) end
                        gc:setPen("thin", "smooth")
                        if fachwerkModus and explosionPage == 2 then
                            drawReactionArrow(gc, -N_a_proj, ux, uy, px1, py1, "S" .. i, "S" .. i)
                        else
                            local kn_l = knoten[s.k1]
                            if offsetX_A ~= 0 then local lbl = lastLabel(kn_l, offsetX_A, kn_l.last_x_str); drawReactionArrow(gc, offsetX_A, 1, 0, px1, py1, "F = ", lbl, lbl:sub(5)) end
                            if offsetY_A ~= 0 then local lbl = lastLabel(kn_l, offsetY_A, kn_l.last_y_str); drawReactionArrow(gc, offsetY_A, 0, 1, px1, py1, "F = ", lbl, lbl:sub(5)) end
                        end
                        if offsetM_A ~= 0 then drawMoment(gc, px1, py1, 24, offsetM_A < 0) end
                    end
                    local isSuppNode_A = knoten[s.k1].lager_x or knoten[s.k1].lager_y or knoten[s.k1].lager_m or (knoten[s.k1].cx and knoten[s.k1].cx > 0) or (knoten[s.k1].cy and knoten[s.k1].cy > 0) or (knoten[s.k1].cm and knoten[s.k1].cm > 0)
                    if math.abs(offsetRx_A) > 1e-4 or math.abs(offsetRy_A) > 1e-4 or math.abs(offsetRm_A) > 1e-4 or (explosionPage == 2 and isSuppNode_A) then
                        local kn = knoten[s.k1]
                        local r = math.rad(kn.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        if math.abs(kn.R_xi) > 1e-4 or (explosionPage == 2 and (kn.lager_x or (kn.cx and kn.cx > 0))) then drawReactionArrow(gc, kn.R_xi, cw, -sw, px1, py1, "H = ", getSuppLetter(s.k1).."_h", symbolischer_modus and fm(kn.symb_R_xi) or nil, explosionPage == 2) end
                        if math.abs(kn.R_eta) > 1e-4 or (explosionPage == 2 and (kn.lager_y or (kn.cy and kn.cy > 0))) then drawReactionArrow(gc, kn.R_eta, -sw, -cw, px1, py1, "V = ", getSuppLetter(s.k1).."_v", symbolischer_modus and fm(kn.symb_R_eta) or nil, explosionPage == 2) end
                        if math.abs(offsetRm_A) > 1e-4 or (explosionPage == 2 and (kn.lager_m or (kn.cm and kn.cm > 0))) then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                            local cw = offsetRm_A < 0
                            local m_lbl = "M = " .. formatLabel(math.abs(offsetRm_A))
                            if explosionPage == 2 then cw = false; m_lbl = "M_" .. getSuppLetter(s.k1); e2Moment(m_lbl, cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px1, py1, 28, cw)
                            gc:setFont("sansserif", "r", 8); gc:drawString(m_lbl, px1 + 22, py1 + 22)
                        end
                    end
                end

                -- Gegenseite am Knoten nur, wenn dort ein biegesteifer Rest haengt (sonst zeichnet sie der
                -- andere Gelenkstab bzw. sie gehoert zum Gelenkbolzen)
                local should_draw_A = false
                if not knoten[s.k1].gelenk and #gelenkKnoten(s.k1).R > 0 and mehrA then
                    should_draw_A = (not hovered_ts or isRigidNodeInTS(s.k1, hovered_ts))
                end
                
                if should_draw_A then
                    local draw_orig_px1, draw_orig_py1 = orig_px1, orig_py1
                    if isExplosion and hovered_ts and isRigidNodeInTS(s.k1, hovered_ts) then
                        draw_orig_px1, draw_orig_py1 = getShiftedNodePos(s.k1, hovered_ts)
                    end

                    if useLocalA then
                        if not s.n_gelenk_A then drawFBDArrow(gc, -(-N_a_proj), -ux, -uy, draw_orig_px1, draw_orig_py1, prefixN_A, nil, symbolischer_modus and fm(s.symb_N_start) or nil, explosionPage == 2, flipA and -flipA or nil) end
                        if not s.q_gelenk_A then drawFBDArrow(gc, -(-V_a_proj), -nx, -ny, draw_orig_px1, draw_orig_py1, prefixQ_A, nil, symbolischer_modus and fm(s.symb_Q_start) or nil, explosionPage == 2, flipA and -flipA or nil) end
                    else
                        drawFBDArrow(gc, -(-Fx_a), -1, 0, draw_orig_px1, draw_orig_py1, "h = ", "Gx_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fx_a) or nil, explosionPage == 2, flipA and -flipA or nil)
                        drawFBDArrow(gc, -(-Fy_a), 0, -1, draw_orig_px1, draw_orig_py1, "v = ", "Gy_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fy_a) or nil, explosionPage == 2, flipA and -flipA or nil)
                    end

                    if not s.gelenk_A then
                        if math.abs(M_a_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            local cw = M_a_disp <= 0
                            if explosionPage == 2 then cw = flipA < 0; e2Moment(prefixM_A:gsub(" = ", ""), cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, draw_orig_px1, draw_orig_py1, 16, cw)
                            gc:setFont("sansserif", "r", 10)
                            local label_m
                            if explosionPage == 2 then
                                label_m = prefixM_A:gsub(" = ", "")
                            else
                                local m_lbl = symbolischer_modus and fm(s.symb_Ma_disp) or formatLabel(math.abs(M_a_disp))
                                label_m = prefixM_A .. m_lbl
                            end
                            gc:drawString(label_m, orig_px1 + ux*30, orig_py1 + uy*30)
                        end
                    end
                end
            end

            local isHingeB = s.n_gelenk_B or s.q_gelenk_B or s.gelenk_B or knoten[s.k2].gelenk
            local prefixN_B = (explosionPage == 2 and isHingeB) and ("Gn_"..getHingeNumber(s.k2)..lblSuffixB.." = ") or "N = "
            local prefixQ_B = (explosionPage == 2 and isHingeB) and ("Gq_"..getHingeNumber(s.k2)..lblSuffixB.." = ") or "Q = "
            local prefixM_B = (explosionPage == 2 and isHingeB) and ("Gm_"..getHingeNumber(s.k2)..lblSuffixB.." = ") or "M = "
            local isMHingeB = knoten[s.k2].gelenk or s.gelenk_B
            if explodeB and (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k2, hovered_ts)) then
                local val_N, val_Q, val_h, val_v
                if mehrB and (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts)) then
                    if useLocalB then
                        val_N = N_b_proj; val_Q = V_b_proj
                        if not s.n_gelenk_B then drawFBDArrow(gc, val_N, ux, uy, px2, py2, prefixN_B, nil, symbolischer_modus and fm(s.symb_N_end) or nil, explosionPage == 2, flipB) end
                        if not s.q_gelenk_B then drawFBDArrow(gc, val_Q, nx, ny, px2, py2, prefixQ_B, nil, symbolischer_modus and fm(s.symb_Q_end) or nil, explosionPage == 2, flipB) end
                    else
                        val_h = Fx_b; val_v = Fy_b
                        drawFBDArrow(gc, val_h, 1, 0, px2, py2, "h = ", "Gx_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fx_b) or nil, explosionPage == 2, flipB)
                        drawFBDArrow(gc, val_v, 0, 1, px2, py2, "v = ", "Gy_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fy_b) or nil, explosionPage == 2, flipB)
                    end

                    if not isMHingeB then
                        if math.abs(M_b_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            local cw = M_b_disp < 0
                            if explosionPage == 2 then cw = flipB < 0; e2Moment(prefixM_B:gsub(" = ", ""), cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px2, py2, 16, cw)
                            gc:setFont("sansserif", "r", 10)
                            local label_m
                            if explosionPage == 2 then
                                label_m = prefixM_B:gsub(" = ", "")
                            else
                                local m_lbl = symbolischer_modus and fm(s.symb_Ma_disp) or formatLabel(math.abs(M_b_disp))
                                label_m = prefixM_B .. m_lbl
                            end
                            gc:drawString(label_m, px2 + ux*45, py2 + uy*45)
                        end
                    end
                end

                if drawExtB then
                    if offsetX_B ~= 0 or offsetY_B ~= 0 or offsetM_B ~= 0 then
                        if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(255, 50, 50) end
                        gc:setPen("thin", "smooth")
                        if fachwerkModus and explosionPage == 2 then
                            drawReactionArrow(gc, -N_b_proj, ux, uy, px2, py2, "S" .. i, "S" .. i)
                        else
                            local kn_l = knoten[s.k2]
                            if offsetX_B ~= 0 then local lbl = lastLabel(kn_l, offsetX_B, kn_l.last_x_str); drawReactionArrow(gc, offsetX_B, 1, 0, px2, py2, "F = ", lbl, lbl:sub(5)) end
                            if offsetY_B ~= 0 then local lbl = lastLabel(kn_l, offsetY_B, kn_l.last_y_str); drawReactionArrow(gc, offsetY_B, 0, 1, px2, py2, "F = ", lbl, lbl:sub(5)) end
                        end
                        if offsetM_B ~= 0 then drawMoment(gc, px2, py2, 24, offsetM_B < 0) end
                    end
                    local isSuppNode_B = knoten[s.k2].lager_x or knoten[s.k2].lager_y or knoten[s.k2].lager_m or (knoten[s.k2].cx and knoten[s.k2].cx > 0) or (knoten[s.k2].cy and knoten[s.k2].cy > 0) or (knoten[s.k2].cm and knoten[s.k2].cm > 0)
                    if math.abs(offsetRx_B) > 1e-4 or math.abs(offsetRy_B) > 1e-4 or math.abs(offsetRm_B) > 1e-4 or (explosionPage == 2 and isSuppNode_B) then
                        local kn = knoten[s.k2]
                        local r = math.rad(kn.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        if math.abs(kn.R_xi) > 1e-4 or (explosionPage == 2 and (kn.lager_x or (kn.cx and kn.cx > 0))) then drawReactionArrow(gc, kn.R_xi, cw, -sw, px2, py2, "H = ", getSuppLetter(s.k2).."_h", symbolischer_modus and fm(kn.symb_R_xi) or nil, explosionPage == 2) end
                        if math.abs(kn.R_eta) > 1e-4 or (explosionPage == 2 and (kn.lager_y or (kn.cy and kn.cy > 0))) then drawReactionArrow(gc, kn.R_eta, -sw, -cw, px2, py2, "V = ", getSuppLetter(s.k2).."_v", symbolischer_modus and fm(kn.symb_R_eta) or nil, explosionPage == 2) end
                        if math.abs(offsetRm_B) > 1e-4 or (explosionPage == 2 and (kn.lager_m or (kn.cm and kn.cm > 0))) then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                            local cw = offsetRm_B < 0
                            local m_lbl = "M = " .. formatLabel(math.abs(offsetRm_B))
                            if explosionPage == 2 then cw = false; m_lbl = "M_" .. getSuppLetter(s.k2); e2Moment(m_lbl, cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px2, py2, 28, cw)
                            gc:setFont("sansserif", "r", 8); gc:drawString(m_lbl, px2 + 22, py2 + 22)
                        end
                    end
                end

                -- Gegenseite am Knoten nur, wenn dort ein biegesteifer Rest haengt (sonst zeichnet sie der
                -- andere Gelenkstab bzw. sie gehoert zum Gelenkbolzen)
                local should_draw_B = false
                if not knoten[s.k2].gelenk and #gelenkKnoten(s.k2).R > 0 and mehrB then
                    should_draw_B = (not hovered_ts or isRigidNodeInTS(s.k2, hovered_ts))
                end
                
                if should_draw_B then
                    local draw_orig_px2, draw_orig_py2 = orig_px2, orig_py2
                    if isExplosion and hovered_ts and isRigidNodeInTS(s.k2, hovered_ts) then
                        draw_orig_px2, draw_orig_py2 = getShiftedNodePos(s.k2, hovered_ts)
                    end

                    if useLocalB then
                        if not s.n_gelenk_B then drawFBDArrow(gc, -(N_b_proj), ux, uy, draw_orig_px2, draw_orig_py2, prefixN_B, nil, symbolischer_modus and fm(s.symb_N_end) or nil, explosionPage == 2, flipB and -flipB or nil) end
                        if not s.q_gelenk_B then drawFBDArrow(gc, -(V_b_proj), nx, ny, draw_orig_px2, draw_orig_py2, prefixQ_B, nil, symbolischer_modus and fm(s.symb_Q_end) or nil, explosionPage == 2, flipB and -flipB or nil) end
                    else
                        drawFBDArrow(gc, -(Fx_b), 1, 0, draw_orig_px2, draw_orig_py2, "h = ", "Gx_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fx_b) or nil, explosionPage == 2, flipB and -flipB or nil)
                        drawFBDArrow(gc, -(Fy_b), 0, 1, draw_orig_px2, draw_orig_py2, "v = ", "Gy_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fy_b) or nil, explosionPage == 2, flipB and -flipB or nil)
                    end

                    if not s.gelenk_B then
                        if math.abs(M_b_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            local cw = M_b_disp >= 0
                            if explosionPage == 2 then cw = flipB > 0; e2Moment(prefixM_B:gsub(" = ", ""), cw) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, draw_orig_px2, draw_orig_py2, 16, cw)
                            gc:setFont("sansserif", "r", 10)
                            local label_m
                            if explosionPage == 2 then
                                label_m = prefixM_B:gsub(" = ", "")
                            else
                                local m_lbl = symbolischer_modus and fm(s.symb_Mb_disp) or formatLabel(math.abs(M_b_disp))
                                label_m = prefixM_B .. m_lbl
                            end
                            gc:drawString(label_m, orig_px2 - ux*30, orig_py2 - uy*30)
                        end
                    end
                end
            end
            until true
        end
    end

    gc:setPen("thin", "smooth")
    if ansichtsModus ~= "W" then
        for i, k in ipairs(knoten) do
            local node_in_ts = true
            if hovered_ts and glob_ts_scheibe then
                node_in_ts = false
                for _, ns in ipairs(staebe) do
                    if (ns.k1 == i or ns.k2 == i) and glob_ts_scheibe[_] == hovered_ts then
                        node_in_ts = true; break
                    end
                end
            end
            local hide_node = not node_in_ts and ansichtsModus == "E"
            
            if not hide_node then
                local px, py = k.x * drawPxProMeter + offsetX, k.y * drawPxProMeter + offsetY
                if isKinematic then
                    local ux, uy = getKinematicDisp(i)
                    local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
                    px = px + ux * anim_f
                    py = py + uy * anim_f
                end
                
                if isExplosion then
                    local attach_s = nil
                    local attach_side = 0
                    for _, s in ipairs(staebe) do
                        if s.k1 == i and not s.is_cut then
                            local explodeA = knoten[s.k1].gelenk
                            if explodeA then attach_s = s; attach_side = 1; break end
                        elseif s.k2 == i and not s.is_cut then
                            local explodeB = knoten[s.k2].gelenk
                            if explodeB then attach_s = s; attach_side = 2; break end
                        end
                    end
                    if attach_s and not (fachwerkModus and isExplosion) then
                        local s = attach_s
                        local side = attach_side
                        local px1, py1 = knoten[s.k1].x * drawPxProMeter + offsetX, knoten[s.k1].y * drawPxProMeter + offsetY
                        local px2, py2 = knoten[s.k2].x * drawPxProMeter + offsetX, knoten[s.k2].y * drawPxProMeter + offsetY
                        local dx_orig, dy_orig = px2 - px1, py2 - py1
                        local L_orig = math.sqrt(dx_orig^2 + dy_orig^2)
                        if L_orig > 0 then
                            local ux, uy = dx_orig/L_orig, dy_orig/L_orig
                            local expl_gap = math.min(1.5 * drawPxProMeter, L_orig * 0.35)
                            local gap = 0
                            if side == 1 then
                                if s.gelenk_A then gap = 6 end
                                if s.q_gelenk_A then gap = 10 end
                                if s.n_gelenk_A then gap = 12 end
                                px = px + ux * (gap + expl_gap)
                                py = py + uy * (gap + expl_gap)
                            else
                                if s.gelenk_B then gap = 6 end
                                if s.q_gelenk_B then gap = 10 end
                                if s.n_gelenk_B then gap = 12 end
                                px = px - ux * (gap + expl_gap)
                                py = py - uy * (gap + expl_gap)
                            end
                        end
                    end
                end
        
                if k.gelenk and (not isExplosion or fachwerkModus) then
                    gc:setPen("thin", "smooth")
                    gc:setColorRGB(255, 255, 255); gc:fillArc(px - 4, py - 4, 8, 8, 0, 360)
                    gc:setColorRGB(100, 100, 100); gc:drawArc(px - 4, py - 4, 8, 8, 0, 360)
                elseif ansichtsModus ~= "W" and ansichtsModus ~= "U" and not isPolplan then
                    local all_conn = {}
                    local hinged_conn = {}
                    for _, s in ipairs(staebe) do
                        if s.k1 == i then
                            local dx, dy = knoten[s.k2].x - k.x, knoten[s.k2].y - k.y
                            local ang = math.atan2(-dy, dx)
                            table.insert(all_conn, ang)
                            if s.gelenk_A then table.insert(hinged_conn, ang) end
                        elseif s.k2 == i then
                            local dx, dy = knoten[s.k1].x - k.x, knoten[s.k1].y - k.y
                            local ang = math.atan2(-dy, dx)
                            table.insert(all_conn, ang)
                            if s.gelenk_B then table.insert(hinged_conn, ang) end
                        end
                    end
                    if #hinged_conn > 0 then
                        gc:setPen("thin", "smooth"); gc:setColorRGB(100, 100, 100)
                        for _, A in ipairs(hinged_conn) do
                            local min_pos_delta = math.pi / 2
                            local max_neg_delta = -math.pi / 2
                            
                            local found_pos = false
                            local found_neg = false
                            local best_pos = 2 * math.pi
                            local best_neg = -2 * math.pi
                            
                            for _, B in ipairs(all_conn) do
                                local delta = B - A
                                delta = (delta + math.pi) % (2 * math.pi) - math.pi
                                
                                if delta > 1e-4 then
                                    if delta < best_pos then
                                        best_pos = delta
                                        found_pos = true
                                    end
                                elseif delta < -1e-4 then
                                    if delta > best_neg then
                                        best_neg = delta
                                        found_neg = true
                                    end
                                end
                            end
                            
                            if found_pos then min_pos_delta = best_pos end
                            if found_neg then max_neg_delta = best_neg end
                            
                            local start_ang = A + max_neg_delta
                            local sweep = min_pos_delta - max_neg_delta
                            gc:drawArc(px - 6, py - 6, 12, 12, math.deg(start_ang), math.deg(sweep))
                        end
                    end
                end

                if modusText == "System" or modusText == "PvV" or (isExplosion and not loadApplied[i]) then
                    if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(255, 50, 50) end
                    local lx = k.last_x or 0
                    local ly = k.last_y or 0
                    local fx, fy = 0, 0
                    if lx ~= 0 or ly ~= 0 then
                        local rw = math.rad(-(k.last_w or 0))
                        local cl, sl = math.cos(rw), math.sin(rw)
                        fx = lx * cl - ly * sl
                        fy = lx * sl + ly * cl
                        local res = math.sqrt(fx*fx + fy*fy)
                        if res > 1e-4 then
                            local ux, uy = fx / res, fy / res
                            drawArrow(gc, px - 40*ux, py - 40*uy, px - 10*ux, py - 10*uy)
                            gc:setFont("sansserif", "r", 8)
                            local lbl_x = (symbolischer_modus and k.last_x_str) and fm(k.last_x_str) or formatLabel(math.abs(lx))
                            local lbl_y = (symbolischer_modus and k.last_y_str) and fm(k.last_y_str) or formatLabel(math.abs(ly))
                            local lbl = ""
                            if math.abs(lx) > 1e-4 and math.abs(ly) > 1e-4 then lbl = lbl_x .. ", " .. lbl_y
                            elseif math.abs(lx) > 1e-4 then lbl = lbl_x
                            else lbl = lbl_y end
                            gc:drawString(lbl, px - 45*ux, py - 45*uy - 10)
                        end
                    end
                    if k.last_m ~= 0 then 
                        drawMoment(gc, px, py, 22, k.last_m < 0) 
                        gc:setFont("sansserif", "r", 8)
                        local lbl_m = (symbolischer_modus and k.last_m_str) and fm(k.last_m_str) or formatLabel(math.abs(k.last_m))
                        gc:drawString(lbl_m, px + 25, py - 25)
                    end
                    
                    if modusText == "PvV" then
                        -- Wege wie im Export (pvv_kin): Knotenlasten in Lastrichtung, H und V in Lagerrichtung
                        pvvZeichneKnotenWege(gc, i, px, py, drawPxProMeter)
                    end
                end

                if isExplosion and not loadApplied[i] and node_in_ts then
                    local isSupp = k.lager_x or k.lager_y or k.lager_m or k.cx > 0 or k.cy > 0 or k.cm > 0
                    if isSupp then
                        local s_Rx, s_Ry, s_Rm
                        if symbolischer_modus then
                            for _, st in ipairs(staebe) do
                                if st.k1 == i or st.k2 == i then
                                    local dx = knoten[st.k2].x - knoten[st.k1].x
                                    local dy = knoten[st.k2].y - knoten[st.k1].y
                                    local L_len = math.sqrt(dx^2 + dy^2)
                                    if L_len > 0 then
                                        local uX, uY = dx/L_len, dy/L_len
                                        local nX, nY = -uY, uX
                                        if st.k1 == i then
                                            s_Rx = (math.abs(uX) > 0.5) and st.symb_N_start or st.symb_Q_start
                                            s_Ry = (math.abs(nY) > 0.5) and st.symb_Q_start or st.symb_N_start
                                            s_Rm = st.symb_M_start
                                            break
                                        elseif st.k2 == i then
                                            s_Rx = (math.abs(uX) > 0.5) and st.symb_N_end or st.symb_Q_end
                                            s_Ry = (math.abs(nY) > 0.5) and st.symb_Q_end or st.symb_N_end
                                            s_Rm = st.symb_M_end
                                            break
                                        end
                                    end
                                end
                            end
                        end

                        local r = math.rad(k.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        if orig_ansichtsModus ~= "N" and orig_ansichtsModus ~= "Q" and orig_ansichtsModus ~= "M" and not ansicht_ausgeblendet then
                            if (k.lager_x or k.cx > 0) and (math.abs(k.R_xi or 0) > 1e-4 or explosionPage == 2) then drawReactionArrow(gc, k.R_xi or 0, cw, -sw, px, py, "H = ", getSuppLetter(i).."_h", symbolischer_modus and fm(k.symb_R_xi) or nil, explosionPage == 2) end
                            if (k.lager_y or k.cy > 0) and (math.abs(k.R_eta or 0) > 1e-4 or explosionPage == 2) then drawReactionArrow(gc, k.R_eta or 0, -sw, -cw, px, py, "V = ", getSuppLetter(i).."_v", symbolischer_modus and fm(k.symb_R_eta) or nil, explosionPage == 2) end
                            if (k.lager_m or k.cm > 0) and (math.abs(k.R_m or 0) > 1e-4 or explosionPage == 2) then
                                if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                                gc:setPen("thin", "smooth")
                                local cw_m = (k.R_m or 0) < 0
                                if explosionPage == 2 then cw_m = false; e2Moment("M_" .. getSuppLetter(i), cw_m) end
                                drawMoment(gc, px, py, 28, cw_m)
                                gc:setFont("sansserif", "r", 9)
                                local m_lbl = ""
                                if explosionPage == 2 then
                                    m_lbl = "M_" .. getSuppLetter(i)
                                else
                                    m_lbl = "M = " .. (symbolischer_modus and fm(k.symb_Rm) or formatLabel(math.abs(k.R_m)))
                                end
                                gc:drawString(m_lbl, px + 22, py + 22)
                            end
                        end
                    end
                end

                if k.cx > 0 or k.cy > 0 or k.cm > 0 then
                    gc:setColorRGB(100, 220, 100); gc:setPen("thin", "smooth")
                    if k.cx > 0 then drawZigZag(gc, px, py, k.f_winkel or 0) end
                    if k.cy > 0 then drawZigZag(gc, px, py, (k.f_winkel or 0) - 90) end
                    if k.cm > 0 then gc:drawArc(px - 14, py - 14, 28, 28, 0, 360); gc:drawArc(px - 10, py - 10, 20, 20, 0, 360) end
                end

                if not isExplosion then
                    gc:setColorRGB(140, 140, 140)
                    gc:setPen("thin", "smooth")
                    drawSupport(gc, k, i, px, py)
                end

                if not isExplosion or not k.gelenk then
                    if k.gelenk then
                        gc:setColorRGB(255, 255, 255); gc:fillArc(px - 4, py - 4, 8, 8, 0, 360)
                        if i == auswahl then gc:setColorRGB(255, 0, 0) elseif (menuOffen and menuTyp == "knoten" and menuIndex == i) or (not menuOffen and hoverTyp == "knoten" and hoverObj == i) then gc:setColorRGB(0, 100, 255) else gc:setColorRGB(0, 0, 0) end
                        gc:setPen("thin", "smooth"); gc:drawArc(px - 4, py - 4, 8, 8, 0, 360)
                    else
                        if i == auswahl then gc:setColorRGB(255, 0, 0) elseif (menuOffen and menuTyp == "knoten" and menuIndex == i) or (not menuOffen and hoverTyp == "knoten" and hoverObj == i) then gc:setColorRGB(0, 100, 255) else gc:setColorRGB(0, 0, 0) end
                        gc:fillArc(px - 3, py - 3, 6, 6, 0, 360)
                    end
                end
                if fachwerkModus and isExplosion and explosionPage == 2 then
                    gc:setFont("sansserif", "b", 10)
                    gc:setColorRGB(0, 0, 0)
                    gc:drawString("K " .. i, px + 6, py - 12)
                    gc:drawString("S = " .. string.char(64 + i), px - 10, py + 10)
                end
            end
        end
    end

    if isPolplan then
        -- 1. Strahlen zeichnen
        local grouped_rays = {}
        for i=0, polplan.num_disks do
            for j=i+1, polplan.num_disks do
                for _, r in ipairs(polplan.rays[i][j]) do
                    local pm = polstrahlModus or 1
                    if pm == 2 or (pm == 1 and r.is_useful) then
                        local lbl = (i==0) and ("HP" .. j) or ("(" .. i .. "," .. j .. ")")
                        local found = false
                        for _, gr in ipairs(grouped_rays) do
                            if math.abs(r.dx*gr.dy - r.dy*gr.dx) < 1e-4 then
                                local cross = (r.px - gr.px)*gr.dy - (r.py - gr.py)*gr.dx
                                if math.abs(cross) < 1e-4 then
                                    gr.labels[lbl] = true
                                    found = true; break
                                end
                            end
                        end
                        if not found then
                            table.insert(grouped_rays, {px=r.px, py=r.py, dx=r.dx, dy=r.dy, labels={[lbl]=true}})
                        end
                    end
                end
            end
        end
            
    for _, gr in ipairs(grouped_rays) do
        local sx = gr.px * drawPxProMeter + offsetX; local sy = gr.py * drawPxProMeter + offsetY
        gc:setPen("thin", "dashed"); gc:setColorRGB(150, 150, 200)

        local ts = {}
        if math.abs(gr.dx) > 1e-5 then
            local tl = (-10 - sx) / gr.dx; local yl = sy + tl * gr.dy; if yl >= -10 and yl <= h + 10 then table.insert(ts, tl) end
            local tr = (b + 10 - sx) / gr.dx; local yr = sy + tr * gr.dy; if yr >= -10 and yr <= h + 10 then table.insert(ts, tr) end
        end
        if math.abs(gr.dy) > 1e-5 then
            local tt = (-10 - sy) / gr.dy; local xt = sx + tt * gr.dx; if xt >= -10 and xt <= b + 10 then table.insert(ts, tt) end
            local tb = (h + 10 - sy) / gr.dy; local xb = sx + tb * gr.dx; if xb >= -10 and xb <= b + 10 then table.insert(ts, tb) end
        end
        table.sort(ts)
        if #ts >= 2 then
            gc:drawLine(sx + ts[1]*gr.dx, sy + ts[1]*gr.dy, sx + ts[#ts]*gr.dx, sy + ts[#ts]*gr.dy)
        else
            gc:drawLine(sx - gr.dx*1000, sy - gr.dy*1000, sx + gr.dx*1000, sy + gr.dy*1000)
        end

        local ex, ey = getScreenEdgeIntersection(sx, sy, gr.dx, gr.dy, b, h)
        local lbl_arr = {}; for l, _ in pairs(gr.labels) do table.insert(lbl_arr, l) end
        table.sort(lbl_arr)
        local full_label = "g(" .. table.concat(lbl_arr, ", ") .. ")"

        gc:setFont("sansserif", "r", 8)
        local tw = gc:getStringWidth(full_label)
        local tx, ty = ex - gr.dx * 5, ey - gr.dy * 5

        if tx > b/2 then tx = tx - tw - 8 else tx = tx + 8 end
        if ty > h/2 then ty = ty - 8 else ty = ty + 12 end
        if tx > b - tw - 5 then tx = b - tw - 5 end; if tx < 5 then tx = 5 end
        if ty > h - 5 then ty = h - 5 end; if ty < 5 then ty = 5 end

        gc:setColorRGB(100, 100, 150)
        gc:drawString(full_label, tx, ty)
    end

    -- 2. Endliche Pole zeichnen
    local grouped_poles = {}
    for i = 0, polplan.num_disks do
        for j = i+1, polplan.num_disks do
            local is_contra = false
            for _, c in ipairs(polplan.contradictions) do
                if (c.A == i and c.B == j) or (c.A == j and c.B == i) then is_contra = true; break end
            end

            for _, p in ipairs(polplan.poles[i][j]) do
                if p.type == "finite" then
                    local sx = p.x * drawPxProMeter + offsetX
                    local sy = p.y * drawPxProMeter + offsetY
                    local lbl = (i == 0) and ("HP" .. j) or ("(" .. i .. "," .. j .. ")")

                    local found = false
                    for _, gp in ipairs(grouped_poles) do
                        if math.abs(gp.x - sx) < 2 and math.abs(gp.y - sy) < 2 then
                            table.insert(gp.labels, lbl)
                            if i == 0 then gp.has_hp = true end
                            if is_contra then gp.is_contra = true end
                            found = true; break
                        end
                    end
                    if not found then
                        table.insert(grouped_poles, {x=sx, y=sy, labels={lbl}, has_hp=(i==0), is_contra=is_contra})
                    end
                end
            end
        end
    end

    for _, gp in ipairs(grouped_poles) do
        if gp.is_contra then gc:setColorRGB(255, 0, 0)
        elseif gp.has_hp then gc:setColorRGB(0, 0, 255)
        else gc:setColorRGB(0, 180, 0) end
        
        gc:fillArc(gp.x-3, gp.y-3, 6, 6, 0, 360)
        
        if gp.is_contra then gc:setColorRGB(255, 0, 0) end
        gc:setFont("sansserif", "b", 8)
        table.sort(gp.labels)
        gc:drawString(table.concat(gp.labels, ", "), gp.x+6, gp.y-14)
    end

    -- 3. Unendliche Pole auflisten (als Text oben rechts)
    local inf_y = 20
    local inf_x = b - 80
    for i = 0, polplan.num_disks do
        for j = i+1, polplan.num_disks do
            local is_contra = false
            for _, c in ipairs(polplan.contradictions) do
                if (c.A == i and c.B == j) or (c.A == j and c.B == i) then is_contra = true; break end
            end

            for _, p in ipairs(polplan.poles[i][j]) do
                if p.type == "infinite" then
                    local lbl = (i == 0) and ("HP" .. j) or ("(" .. i .. "," .. j .. ")")
                    local text = lbl .. " inf"
                    gc:setFont("sansserif", "b", 12)
                    if is_contra then gc:setColorRGB(255, 0, 0) else gc:setColorRGB(0, 100, 200) end
                    gc:drawString(text, inf_x, inf_y)
                    
                    -- Doppel-Pfeil
                    local cx, cy = inf_x - 20, inf_y + 8
                    gc:setPen("thin", "smooth")
                    local l = 10
                    local x1, y1 = cx - p.dx*l, cy - p.dy*l
                    local x2, y2 = cx + p.dx*l, cy + p.dy*l
                    gc:drawLine(x1, y1, x2, y2)
                    
                    local as = 4 -- arrow head size
                    gc:drawLine(x1, y1, x1 + p.dx*as - p.dy*as, y1 + p.dy*as + p.dx*as)
                    gc:drawLine(x1, y1, x1 + p.dx*as + p.dy*as, y1 + p.dy*as - p.dx*as)
                    gc:drawLine(x2, y2, x2 - p.dx*as - p.dy*as, y2 - p.dy*as + p.dx*as)
                    gc:drawLine(x2, y2, x2 - p.dx*as + p.dy*as, y2 - p.dy*as - p.dx*as)
                    inf_y = inf_y + 20
                    if inf_y > h - 30 then
                        inf_y = 20
                        inf_x = inf_x - 70
                    end
                end
            end
        end
    end
    end

    if hovered_ts then
        gc:setFont("sansserif", "b", 10)
        gc:setColorRGB(0, 0, 255)
        gc:drawString("Teilsystem " .. hovered_ts, 10, 25)
        
        local pts = {}
        for j, s in ipairs(staebe) do
            if glob_ts_scheibe and glob_ts_scheibe[j] == hovered_ts then
                pts[#pts+1] = knoten[s.k1]
                pts[#pts+1] = knoten[s.k2]
            end
        end
        if glob_disk_centers and glob_disk_centers[hovered_ts] then
            local c = glob_disk_centers[hovered_ts]
            pts[#pts+1] = {x = c.x, y = c.y, is_virtual = false}
            
            if glob_resultant_pts then
                for _, pt in ipairs(glob_resultant_pts) do
                    pts[#pts+1] = pt
                end
            end
            
            local px = c.x * drawPxProMeter + offsetX
            local py = c.y * drawPxProMeter + offsetY
            gc:setColorRGB(0, 0, 255)
            gc:setPen("medium", "smooth")
            gc:drawLine(px - 3, py - 3, px + 3, py + 3)
            gc:drawLine(px - 3, py + 3, px + 3, py - 3)
            gc:setFont("sansserif", "b", 10)
            gc:drawString("P" .. (c.node_id or hovered_ts), px + 8, py - 15)
        end
        drawBemassung(gc, pts)
    elseif isExplosion and glob_resultant_pts and #glob_resultant_pts > 0 then
        -- E-Seite: Knoten und die Wirkungslinien der Resultierenden zusammen bemassen
        local pts = {}
        for _, k in ipairs(knoten) do pts[#pts+1] = k end
        for _, pt in ipairs(glob_resultant_pts) do pts[#pts+1] = pt end
        drawBemassung(gc, pts)
    else
        drawBemassung(gc)
    end

    gc:setPen("thin", "smooth")

    if isKinematic and pvv_released_binding then
        gc:setColorRGB(255, 0, 0)
        local bind = pvv_released_binding
        if bind.type == "n_gelenk" or bind.type == "q_gelenk" or bind.type == "m_gelenk" then
            local s = staebe[bind.stab]
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            local px1, py1 = k1.x * drawPxProMeter + offsetX, k1.y * drawPxProMeter + offsetY
            local px2, py2 = k2.x * drawPxProMeter + offsetX, k2.y * drawPxProMeter + offsetY
            local nodeIdx = bind.endA and s.k1 or s.k2
            local n_px = knoten[nodeIdx].x * drawPxProMeter + offsetX
            local n_py = knoten[nodeIdx].y * drawPxProMeter + offsetY
            local ux_n, uy_n = getKinematicDisp(nodeIdx)
            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
            local nd_px = n_px + ux_n * anim_f
            local nd_py = n_py + uy_n * anim_f
            
            local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(bind.stab)
            local rd_px = (bind.endA and px1 + u1x * anim_f) or (px2 + u2x * anim_f)
            local rd_py = (bind.endA and py1 + u1y * anim_f) or (py2 + u2y * anim_f)
            
            -- Richtung (dx, dy) des UNVERFORMTEN Systems nutzen, wie vom Benutzer gewünscht.
            local dx, dy = px2 - px1, py2 - py1
            local L = math.sqrt(dx^2 + dy^2)
            
            if bind.type == "n_gelenk" or bind.type == "q_gelenk" then
                if L > 0 then
                    local nx, ny = dx/L, dy/L
                    if bind.type == "q_gelenk" then nx, ny = -ny, nx end
                    local arrowL = 20
                    local dir = bind.endA and -1 or 1
                    local ax, ay = nx * arrowL * dir, ny * arrowL * dir
                    drawArrow(gc, nd_px, nd_py, nd_px - ax, nd_py - ay)
                    drawArrow(gc, rd_px, rd_py, rd_px + ax, rd_py + ay)
                    
                    gc:setFont("sansserif", "b", 10)
                    local text = bind.type == "q_gelenk" and "Q" or "N"
                    gc:drawString(text, nd_px - ax - 8 * nx, nd_py - ay - 8 * ny)
                    gc:drawString(text, rd_px + ax + 8 * nx, rd_py + ay + 8 * ny)
                    
                    -- Klaffung mit Name und Wert wie im Export (δ_G, Spalte 3 von pvv_kin)
                    local disp_str = pvvLabel("δ_G") or ""

                    gc:setColorRGB(200, 0, 200)
                    gc:setPen("thin", "smooth")
                    local ox, oy = -ny * 15, nx * 15
                    drawArrow(gc, nd_px + ox, nd_py + oy, rd_px + ox, rd_py + oy)
                    gc:setFont("sansserif", "r", 8)
                    gc:drawString(disp_str, rd_px + ox + 5, rd_py + oy)
                    gc:setColorRGB(255, 0, 0)
                end
            elseif bind.type == "m_gelenk" then
                local angle = 0
                if L > 0 then angle = math.deg(math.atan2(-dy, dx)) end
                if bind.endA then angle = angle + 180 end
                
                -- Funktion zum Zeichnen eines Bogenpfeils für das Moment.
                -- ext < 0 ermöglicht das Zeichnen im Uhrzeigersinn (CW),
                -- da drawArc standardmäßig nur positive Winkel (CCW) unterstützt.
                local function drawPvVArc(cx, cy, sA, ext)
                    gc:drawArc(cx - 15, cy - 15, 30, 30, ext < 0 and sA + ext or sA, math.abs(ext))
                    local eA = math.rad(sA + ext)
                    local tA = math.rad(sA + ext - 15 * (ext > 0 and 1 or -1))
                    drawArrow(gc, cx + 15*math.cos(tA), cy - 15*math.sin(tA), cx + 15*math.cos(eA), cy - 15*math.sin(eA))
                end
                
                -- Vorzeichen entsprechend den positiven Schnittgrößen am Stabende/Stabanfang:
                -- Wenn das Gelenk am Stabanfang (k1) ist, ist das pos. Moment CW (-150).
                -- Wenn es am Stabende (k2) ist, ist es CCW (150).
                local rod_ext = bind.endA and -150 or 150
                local node_ext = -rod_ext
                
                -- Zeichnen des Momentenpaares am Angelenk.
                -- Wir zentrieren die Bögen so, dass sie sich jeweils über den Stab ("Stabseite")
                -- und über den Knoten stülpen.
                -- angle zeigt vom Stab zum Knoten. Die Stabrichtung ist angle + 180.
                
                -- Der Bogen für den Knoten wird über dem Knoten zentriert (angle).
                drawPvVArc(nd_px, nd_py, angle - node_ext / 2, node_ext)
                -- Der Bogen für den Stab wird über dem Stab zentriert (angle + 180).
                drawPvVArc(rd_px, rd_py, angle + 180 - rod_ext / 2, rod_ext)
            end
        elseif bind.type == "lager_x" or bind.type == "lager_y" or bind.type == "lager_m" or bind.type == "knoten_gelenk" then
            local k = knoten[bind.node]
            local n_px = k.x * drawPxProMeter + offsetX
            local n_py = k.y * drawPxProMeter + offsetY
            local ux_n, uy_n = getKinematicDisp(bind.node)
            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
            local nd_px = n_px + ux_n * anim_f
            local nd_py = n_py + uy_n * anim_f
            
            -- H und V in Lagerrichtung wie im Arbeitssatz: xi = (cos, -sin), eta = (sin, cos)
            local lw = math.rad(k.winkel or 0)
            local lcw, lsw = math.cos(lw), math.sin(lw)
            if bind.type == "lager_x" then
                drawArrow(gc, nd_px, nd_py, nd_px + 20 * lcw, nd_py - 20 * lsw)
                gc:setFont("sansserif", "b", 10)
                gc:drawString("H", nd_px + 25 * lcw, nd_py - 25 * lsw - 5)
            elseif bind.type == "lager_y" then
                drawArrow(gc, nd_px, nd_py, nd_px + 20 * lsw, nd_py + 20 * lcw)
                gc:setFont("sansserif", "b", 10)
                gc:drawString("V", nd_px + 25 * lsw + 5, nd_py + 25 * lcw)
            elseif bind.type == "lager_m" then
                -- positive moment is mathematically CCW. On screen (y down), this visually goes from right (0) to UP (-90).
                -- let's draw a CCW arc of 270 degrees
                local startAng = 90
                local sweep = 270
                gc:drawArc(nd_px - 15, nd_py - 15, 30, 30, startAng, sweep)
                local eA = math.rad(startAng + sweep); local tA = math.rad(startAng + sweep - 15)
                drawArrow(gc, nd_px + 15*math.cos(tA), nd_py - 15*math.sin(tA), nd_px + 15*math.cos(eA), nd_py - 15*math.sin(eA))
                gc:setFont("sansserif", "b", 10)
                gc:drawString("M_A", nd_px + 20, nd_py - 15)
            elseif bind.type == "knoten_gelenk" then
                local found_rods = {}
                for i, s in ipairs(staebe) do
                    if s.k1 == bind.node or s.k2 == bind.node then
                        table.insert(found_rods, {idx=i, s=s})
                    end
                end
                if #found_rods == 2 then
                    local s1 = found_rods[1].s
                    local s1_is_start = (s1.k1 == bind.node)
                    -- Positives Schnittmoment: Anfang (k1) -> CW (-150), Ende (k2) -> CCW (150)
                    local base_ext = s1_is_start and -150 or 150
                    
                    for i, r_info in ipairs(found_rods) do
                        local s = r_info.s
                        local k1, k2 = knoten[s.k1], knoten[s.k2]
                        local px1, py1 = k1.x * drawPxProMeter + offsetX, k1.y * drawPxProMeter + offsetY
                        local px2, py2 = k2.x * drawPxProMeter + offsetX, k2.y * drawPxProMeter + offsetY
                        
                        if isKinematic then
                            local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(r_info.idx)
                            local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
                            px1, py1 = px1 + u1x * anim_f, py1 + u1y * anim_f
                            px2, py2 = px2 + u2x * anim_f, py2 + u2y * anim_f
                        end
                        
                        -- Richtung (dx, dy) des (ggf. verformten) Systems nutzen
                        local dx, dy = px2 - px1, py2 - py1
                        
                        local angle = 0
                        if math.sqrt(dx^2 + dy^2) > 0 then angle = math.deg(math.atan2(-dy, dx)) end
                        if s.k1 == bind.node then angle = angle + 180 end
                        
                        -- Erster Stab erhält das Moment, zweiter Stab das exakte Gegenmoment
                        local ext = (i == 1) and base_ext or -base_ext
                        
                        -- Den Mittelpunkt des Bogens etwas entlang des Stabes verschieben
                        local offset = 15
                        local dir_rad = math.rad(angle + 180)
                        local cx = nd_px + offset * math.cos(dir_rad)
                        local cy = nd_py - offset * math.sin(dir_rad)
                        
                        local sA = angle + 180 - ext / 2
                        gc:drawArc(cx - 15, cy - 15, 30, 30, ext < 0 and sA + ext or sA, math.abs(ext))
                        local eA = math.rad(sA + ext); local tA = math.rad(sA + ext - 15 * (ext > 0 and 1 or -1))
                        drawArrow(gc, cx + 15*math.cos(tA), cy - 15*math.sin(tA), cx + 15*math.cos(eA), cy - 15*math.sin(eA))
                    end
                end
            end
        end
    end

    if isKinematic and pvv_released_binding then pvvZeichneGelenkWinkel(gc, drawPxProMeter) end
    if isKinematic and kinematic_disk_states then
        for i, state in ipairs(kinematic_disk_states) do
            if state.type == "rot" and math.abs(state.phi) > 1e-9 then
                local cx = state.cx * drawPxProMeter + offsetX
                local cy = state.cy * drawPxProMeter + offsetY
                
                local best_s = nil
                local ref_node = nil
                local ref_other = nil
                local needs_hilfslinie = true
                local score = -1
                
                for s_idx, s in ipairs(staebe) do
                    if s.scheibe == i then
                        local ux1, uy1 = getKinematicDisp(s.k1)
                        local ux2, uy2 = getKinematicDisp(s.k2)
                        local is_k1_stat = (math.abs(ux1) < 1e-5 and math.abs(uy1) < 1e-5)
                        local is_k2_stat = (math.abs(ux2) < 1e-5 and math.abs(uy2) < 1e-5)
                        
                        local current_score = 0
                        local c_ref_node, c_ref_other, c_needs_h
                        
                        if is_k1_stat then
                            c_ref_node = s.k1; c_ref_other = s.k2; c_needs_h = false; current_score = 10
                        elseif is_k2_stat then
                            c_ref_node = s.k2; c_ref_other = s.k1; c_needs_h = false; current_score = 10
                        elseif pvv_released_binding and pvv_released_binding.stab == s_idx then
                            local rel_node = pvv_released_binding.endA and s.k1 or s.k2
                            c_ref_node = (rel_node == s.k1) and s.k2 or s.k1
                            c_ref_other = rel_node
                            c_needs_h = true
                            current_score = 5
                        else
                            c_ref_node = s.k1; c_ref_other = s.k2; c_needs_h = true; current_score = 1
                        end
                        
                        if current_score > score then
                            score = current_score; best_s = s; ref_node = c_ref_node; ref_other = c_ref_other; needs_hilfslinie = c_needs_h
                        end
                    end
                end
                
                if ref_node and ref_other then
                    local rx = knoten[ref_node].x * drawPxProMeter + offsetX
                    local ry = knoten[ref_node].y * drawPxProMeter + offsetY
                    local ox = knoten[ref_other].x * drawPxProMeter + offsetX
                    local oy = knoten[ref_other].y * drawPxProMeter + offsetY
                    
                    local dx = ox - rx; local dy = oy - ry
                    local angle_0 = math.deg(math.atan2(-dy, dx))
                    local dist = math.sqrt(dx^2 + dy^2)
                    local r_ref = math.max(25, math.min(50, dist * 0.3)) -- now used as RADIUS
                    
                    local ux, uy = getKinematicDisp(ref_node)
                    local o_ux, o_uy = getKinematicDisp(ref_other)
                    local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
                    local nd_rx = rx + ux * anim_f; local nd_ry = ry + uy * anim_f
                    local nd_ox = ox + o_ux * anim_f; local nd_oy = oy + o_uy * anim_f
                    
                    local nd_dx = nd_ox - nd_rx; local nd_dy = nd_oy - nd_ry
                    local angle_1 = math.deg(math.atan2(-nd_dy, nd_dx))
                    
                    local v_phi = angle_1 - angle_0
                    while v_phi > 180 do v_phi = v_phi - 360 end
                    while v_phi < -180 do v_phi = v_phi + 360 end
                    local v_phi_dir = v_phi > 0 and 1 or -1
                    
                    gc:setColorRGB(0, 0, 255)
                    
                    if needs_hilfslinie then
                        gc:setPen("thin", "dashed")
                        local hx = nd_rx + r_ref * 1.2 * math.cos(math.rad(angle_0))
                        local hy = nd_ry - r_ref * 1.2 * math.sin(math.rad(angle_0))
                        gc:drawLine(nd_rx, nd_ry, hx, hy)
                    end
                    
                    gc:setPen("thin", "smooth")
                    local start_ang = v_phi > 0 and angle_0 or angle_1
                    gc:drawArc(nd_rx - r_ref, nd_ry - r_ref, 2*r_ref, 2*r_ref, start_ang, math.abs(v_phi))
                    
                    local eA = math.rad(angle_1)
                    local arr_sweep = math.min(15, math.abs(v_phi) * 0.8)
                    local tA = math.rad(angle_1 - arr_sweep * v_phi_dir)
                    drawArrow(gc, nd_rx + r_ref*math.cos(tA), nd_ry - r_ref*math.sin(tA), nd_rx + r_ref*math.cos(eA), nd_ry - r_ref*math.sin(eA))
                    
                    if (not kinematic_seed_info or kinematic_seed_info.disk == i) and (not kinematic_seed_info or not kinematic_seed_info.node_idx) then
                        local cx = state.cx * drawPxProMeter + offsetX
                        local cy = state.cy * drawPxProMeter + offsetY
                        gc:setPen("thin", "dashed"); gc:setColorRGB(180, 180, 180)
                        gc:drawLine(cx, cy, rx, ry); gc:drawLine(cx, cy, nd_rx, nd_ry)
                        gc:setColorRGB(0, 0, 255)
                        gc:fillArc(cx - 3, cy - 3, 6, 6, 0, 360)
                        gc:setFont("sansserif", "r", 9)
                        gc:drawString("Pol", cx + 5, cy + 5)
                    end
                    
                    gc:setFont("sansserif", "r", 10)
                    local txt = pvvScheibenText(i)
                    local txt_w = gc:getStringWidth(txt)
                    local midAng = math.rad(angle_0 + v_phi / 2)
                    local r_txt = r_ref + 10
                    gc:drawString(txt, nd_rx + r_txt*math.cos(midAng) - txt_w/2, nd_ry - r_txt*math.sin(midAng) - 6)
                end
            elseif state.type == "trans" then
                pvvZeichneVerschiebung(gc, i, drawPxProMeter)
            end
        end
    end

    -- Warnhinweise; ESC schliesst sie (on.escapeKey), eine neue Berechnung zeigt sie wieder
    hinweisBoxScrollbar = false   -- setzt zeichneHinweisBox wieder, wenn die gelbe Box zu lang ist
    if symbolFehler and symbolFehlerOffen then
        local boxW = math.min(b - 20, 300)
        -- Meldung auf Boxbreite umbrechen
        gc:setFont("sansserif", "r", 9)
        local zeilen, zeile = {}, ""
        for wort in symbolFehler:gmatch("%S+") do
            local probe = (zeile == "") and wort or (zeile .. " " .. wort)
            if zeile ~= "" and gc:getStringWidth(probe) > boxW - 16 then zeilen[#zeilen + 1] = zeile; zeile = wort else zeile = probe end
        end
        if zeile ~= "" then zeilen[#zeilen + 1] = zeile end
        local boxH = 28 + 14 * #zeilen
        local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 0, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(255, 255, 255); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("Symbolischer Modus nicht moeglich:", boxX + 8, boxY + 6)
        gc:setFont("sansserif", "r", 9)
        for zi, z in ipairs(zeilen) do gc:drawString(z, boxX + 8, boxY + 12 + 14 * zi) end
        gc:drawString("[Esc]", boxX + boxW - 34, boxY + 6)
    elseif warnungKinematisch then
        local boxW, boxH = math.min(b - 20, 210), 36; local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 0, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(255, 255, 255); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("System ist kinematisch!", boxX + 8, boxY + 12)
        gc:setFont("sansserif", "r", 9); gc:drawString("[Esc]", boxX + boxW - 34, boxY + 12)
    elseif warnungStarrBestimmt then
        local boxW, boxH = math.min(b - 20, 270), 36; local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 165, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(0, 0, 0); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("Starrmodus & statisch unbestimmt!", boxX + 8, boxY + 12)
        gc:setFont("sansserif", "r", 9); gc:drawString("[Esc]", boxX + boxW - 34, boxY + 12)
    elseif meldungText or (hinweisOffen and #hinweisListe > 0) then
        zeichneHinweisBox(gc, b, h, meldungText and { meldungText } or hinweisListe, meldungText and (meldungTitel or "Export") or "Hinweis")
    end
    
    if pvvPrompt then
        local boxW, boxH = 320, 40; local boxX, boxY = math.floor((b - boxW) / 2), 20
        gc:setColorRGB(255, 200, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(0, 0, 0); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 11); gc:drawString("System ist starr! [Enter] für PvV-Modus", boxX + 15, boxY + 12)
    end
    if menuOffen then
        local menueHoehe = 150
        if menuTyp == "knoten" then
            if isKinematic then
                menueHoehe = pvvMenueHoehe("knoten", menuIndex)
            else
                if menuSeite == 1 then menueHoehe = 160 elseif menuSeite == 2 then menueHoehe = 140 elseif menuSeite == 3 then menueHoehe = 120 elseif menuSeite == 4 then menueHoehe = 220 elseif menuSeite == 5 then menueHoehe = 160 else menueHoehe = 140 end
            end
        elseif menuTyp == "stab" then
            if isKinematic then
                menueHoehe = pvvMenueHoehe("stab", menuIndex)
            else
                if menuSeite == 1 then menueHoehe = 200 elseif menuSeite == 2 then menueHoehe = 120 elseif menuSeite == 3 then menueHoehe = 200 elseif menuSeite == 6 then menueHoehe = 160 elseif menuSeite == 7 then menueHoehe = 180 else menueHoehe = 160 end
            end
        elseif menuTyp == "obermenue" then if menuSeite == 1 then menueHoehe = 220 elseif menuSeite == 2 then menueHoehe = 220 elseif menuSeite == 3 then menueHoehe = 240 else menueHoehe = 180 end
        elseif menuTyp == "pvv_knoten" then menueHoehe = 120
        elseif menuTyp == "pvv_stab" then menueHoehe = 160 end

        local mW = (menuTyp == "obermenue") and 210 or 155
        -- Menues stehen links: alle Positionen im Menue sind relativ zur Fensterbreite b,
        -- daher genuegt hier ein eigener Bezugswert; der Kasten liegt damit bei x = 10.
        local b = mW + 20
        local mX = b - mW - 10
        gc:setColorRGB(240, 240, 240); gc:fillRect(mX, 10, mW, menueHoehe); gc:setColorRGB(0, 0, 0); gc:drawRect(mX, 10, mW, menueHoehe)
        
        if not (isKinematic and (menuTyp == "knoten" or menuTyp == "stab")) then
            gc:setColorRGB(200, 200, 255); gc:fillRect(mX + 2, 20 + (menuZeile * 20), mW - 4, 18)
        end
        gc:setColorRGB(0, 0, 0); gc:setFont("sansserif", "b", 9)

        if menuTyp == "knoten" then
            if isKinematic then
                gc:drawString("Knoten " .. menuIndex .. " (PvV-Modus)", b - 160, 15)
                pvvZeichneMenue(gc, "knoten", menuIndex, b)
            else
                local menueHoehe = 150
                if menuSeite == 1 then menueHoehe = 160 elseif menuSeite == 2 then menueHoehe = 140 elseif menuSeite == 3 then menueHoehe = 120 elseif menuSeite == 4 then menueHoehe = 220 else menueHoehe = 140 end
                
                gc:drawString("Knoten " .. menuIndex .. " < S." .. menuSeite .. "/4 >", b - 160, 15); gc:setFont("sansserif", "r", 9)
                local k = knoten[menuIndex]
                if menuSeite == 1 then
                    -- URSPRÜNGLICHE REIHENFOLGE WIEDERHERGESTELLT: 
                    -- Zeile 3 ist "Gelenkig", Zeilen 4-6 sind die Lager-Eigenschaften.
                    -- Dies stimmt jetzt wieder 100% mit der Logik in on.enterKey überein!
                    gc:drawString("X Koord:", b - 160, 40); gc:drawString("Y Koord:", b - 160, 60); gc:drawString("Gelenkig:", b - 160, 80); gc:drawString("Lager X:", b - 160, 100); gc:drawString("Lager Y:", b - 160, 120); gc:drawString("Lager M:", b - 160, 140)
                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 40) else gc:drawString(k.x_str or tostring(k.x), b - 65, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 60) else gc:drawString(k.y_str or tostring(k.y), b - 65, 60) end
                    gc:drawString(k.gelenk and "Ja" or "Nein", b - 65, 80)
                    gc:drawString(k.lager_x and "Ja" or "Nein", b - 65, 100); gc:drawString(k.lager_y and "Ja" or "Nein", b - 65, 120); gc:drawString(k.lager_m and "Ja" or "Nein", b - 65, 140)
                elseif menuSeite == 2 then
                    -- URSPRÜNGLICHE NAMEN WIEDERHERGESTELLT ("Last-Winkel" und "Lager-Winkel")
                    gc:drawString("Last Fx (kN):", b - 160, 40); gc:drawString("Last Fy (kN):", b - 160, 60); gc:drawString("Last M (kNm):", b - 160, 80); gc:drawString("Last-Winkel:", b - 160, 100); gc:drawString("Lager-Winkel:", b - 160, 120)
                    gc:setColorRGB(0, 0, 255)
                    local v_x = (symbolischer_modus and k.last_x_str) and k.last_x_str or tostring(k.last_x or 0)
                    local v_y = (symbolischer_modus and k.last_y_str) and k.last_y_str or tostring(k.last_y or 0)
                    local v_m = (symbolischer_modus and k.last_m_str) and k.last_m_str or tostring(k.last_m or 0)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 40) else gc:drawString(v_x, b - 65, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 60) else gc:drawString(v_y, b - 65, 60) end
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 80) else gc:drawString(v_m, b - 65, 80) end
                    if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 100) else gc:drawString(tostring(k.last_w or 0), b - 65, 100) end
                    if menuZeile == 5 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 120) else gc:drawString(tostring(k.winkel or 0), b - 65, 120) end
                elseif menuSeite == 3 then
                    gc:drawString("Feder cx (kN/m):", b - 160, 40); gc:drawString("Feder cy (kN/m):", b - 160, 60); gc:drawString("Feder cm (kNm/r):", b - 160, 80); gc:drawString("Feder-Winkel:", b - 160, 100)

                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 40) else gc:drawString(k.cx_str or tostring(k.cx or 0), b - 65, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 60) else gc:drawString(k.cy_str or tostring(k.cy or 0), b - 65, 60) end
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 80) else gc:drawString(k.cm_str or tostring(k.cm or 0), b - 65, 80) end
                    if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 100) else gc:drawString(tostring(k.f_winkel or 0), b - 65, 100) end
                elseif menuSeite == 4 then
                    gc:drawString("Verschiebung:", b - 160, 40)
                    if menuZeile == 1 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                    gc:drawString("Export", b - 60, 40)
                    gc:setColorRGB(0, 0, 0)
                    gc:drawString("R_xi (Parallel):", b - 160, 60); gc:drawString("R_eta (Senkr.):", b - 160, 80); gc:drawString("R_m (Moment):", b - 160, 100)
                    gc:drawString("ü_x (WGV):", b - 160, 120); gc:drawString("ü_y (WGV):", b - 160, 140); gc:drawString("ü_ges (WGV):", b - 160, 160); gc:drawString("phi (WGV):", b - 160, 180)
                    gc:drawString("In TI speichern:", b - 160, 200)
                    
                    local ux = (k.eq_x and k.eq_x > 0 and glob_u) and glob_u[k.eq_x] or 0
                    local uy = (k.eq_y and k.eq_y > 0 and glob_u) and glob_u[k.eq_y] or 0
                    local u_ges = math.sqrt(ux^2 + uy^2)
                    local phi = (type(k.eq_m) == "number" and k.eq_m > 0 and glob_u) and glob_u[k.eq_m] or 0
                    
                    gc:setColorRGB(0, 120, 0)
                    
                    local function fm(str)
                        if not str then return "0" end
                        return str:gsub("%*", "·"):gsub("%^2", "²"):gsub("%^3", "³")
                    end

                    if symbolischer_modus then
                        local s_Rx = k.symb_Rx or "0"
                        local s_Ry = k.symb_Ry or "0"
                        local s_Rm = k.symb_Rm or "0"
                        
                        gc:drawString(fm(s_Rx), b - 60, 60)
                        gc:drawString(fm(s_Ry), b - 60, 80)
                        gc:drawString(fm(s_Rm), b - 60, 100)
                    else
                        gc:drawString(formatLabel(k.R_xi or 0), b - 60, 60); gc:drawString(formatLabel(k.R_eta or 0), b - 60, 80); gc:drawString(formatLabel(k.R_m or 0), b - 60, 100)
                    end
                    
                    gc:setColorRGB(255, 120, 0)
                    gc:drawString(string.format("%.4f", ux), b - 60, 120); gc:drawString(string.format("%.4f", uy), b - 60, 140); gc:drawString(string.format("%.4f", u_ges), b - 60, 160); gc:drawString(string.format("%.4f", phi), b - 60, 180)
                    if menuZeile == 9 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 60, 200)
                end
            end

        elseif menuTyp == "stab" then
            local s = staebe[menuIndex]
            if isKinematic then
                gc:drawString("Stab " .. menuIndex .. " (PvV-Modus)", b - 160, 15)
                pvvZeichneMenue(gc, "stab", menuIndex, b)
            else
                gc:drawString("Stab " .. menuIndex .. " < S." .. menuSeite .. "/7 >", b - 160, 15); gc:setFont("sansserif", "r", 9)
                if menuSeite == 1 then
                    gc:drawString("EI (kNm2):", b - 160, 40); gc:drawString("  biegesteif:", b - 160, 60); gc:drawString("EA (kN):", b - 160, 80); gc:drawString("  dehnsteif:", b - 160, 100)
                    gc:drawString("Last q(x):", b - 160, 120); gc:drawString("Last n(x):", b - 160, 140); gc:drawString("Momentenlast m:", b - 160, 160); gc:drawString("Bogen Radius R:", b - 160, 180)
                    gc:setColorRGB(0, 0, 255)
                    -- EI/EA starrer Staebe gesperrt (grau); dehnsteif ueber Standard-EA als "(Std.)"
                    if s.biegesteif then gc:setColorRGB(150, 150, 150); gc:drawString("starr", b - 60, 40); gc:setColorRGB(0, 0, 255)
                    elseif menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 40) else gc:drawString(s.EI_str or tostring(s.EI), b - 60, 40) end
                    gc:drawString(s.biegesteif and "Ja" or "Nein", b - 60, 60)
                    if s.dehnsteif then gc:setColorRGB(150, 150, 150); gc:drawString("starr", b - 60, 80); gc:setColorRGB(0, 0, 255)
                    elseif menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 80) else gc:drawString(s.EA_str or tostring(s.EA), b - 60, 80) end
                    gc:drawString(s.dehnsteif and "Ja" or (stabDehnsteif(s) and "Ja (Std.)" or "Nein"), b - 60, 100)
                    if menuZeile == 5 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 120) else gc:drawString(s.q_str or "0", b - 60, 120) end
                    if menuZeile == 6 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 140) else gc:drawString(s.n_str or "0", b - 60, 140) end
                    if menuZeile == 7 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 160) else gc:drawString(s.m_str or tostring(s.m), b - 60, 160) end
                    if menuZeile == 8 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 180) else gc:drawString(tostring(s.bogen_r or 0), b - 60, 180) end
                elseif menuSeite == 2 then
                    gc:drawString("Global pX:", b - 160, 40); gc:drawString("pX projiziert:", b - 160, 60); gc:drawString("Global pY:", b - 160, 80); gc:drawString("pY projiziert:", b - 160, 100)
                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 40) else gc:drawString(s.gx_str or tostring(s.gx or 0), b - 60, 40) end
                    gc:drawString((s.gx_proj and "Ja" or "Nein"), b - 60, 60)
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 80) else gc:drawString(s.gy_str or tostring(s.gy or 0), b - 60, 80) end
                    gc:drawString((s.gy_proj and "Ja" or "Nein"), b - 60, 100)
                elseif menuSeite == 3 then
                    gc:drawString("Trapez q Start:", b - 160, 40); gc:drawString("Trapez q Ende:", b - 160, 60); gc:drawString("Trapez n Start:", b - 160, 80); gc:drawString("Trapez n Ende:", b - 160, 100)
                    gc:drawString("Temp. T_oben:", b - 160, 120); gc:drawString("Temp. T_unten:", b - 160, 140); gc:drawString("Alpha_t:", b - 160, 160); gc:drawString("Höhe h (m):", b - 160, 180)
                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 40) else gc:drawString(s.q_A_str or tostring(s.q_A or 0), b - 60, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 60) else gc:drawString(s.q_B_str or tostring(s.q_B or 0), b - 60, 60) end
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 80) else gc:drawString(s.n_A_str or tostring(s.n_A or 0), b - 60, 80) end
                    if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 100) else gc:drawString(s.n_B_str or tostring(s.n_B or 0), b - 60, 100) end
                    if menuZeile == 5 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 120) else gc:drawString(s.To_str or tostring(s.To), b - 60, 120) end
                    if menuZeile == 6 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 140) else gc:drawString(s.Tu_str or tostring(s.Tu), b - 60, 140) end
                    if menuZeile == 7 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 160) else gc:drawString(s.alpha_str or tostring(s.alpha), b - 60, 160) end
                    if menuZeile == 8 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 180) else gc:drawString(s.h_str or tostring(s.h), b - 60, 180) end
                elseif menuSeite == 4 then
                    gc:drawString("M-Gelenk Start:", b - 160, 40); gc:drawString("M-Gelenk Ende:", b - 160, 60); gc:drawString("N-Gelenk Start:", b - 160, 80); gc:drawString("N-Gelenk Ende:", b - 160, 100); gc:drawString("Q-Gelenk Start:", b - 160, 120); gc:drawString("Q-Gelenk Ende:", b - 160, 140)
                    gc:setColorRGB(0, 0, 255)
                    gc:drawString(s.gelenk_A and "Ja" or "Nein", b - 60, 40); gc:drawString(s.gelenk_B and "Ja" or "Nein", b - 60, 60)
                    gc:drawString(s.n_gelenk_A and "Ja" or "Nein", b - 60, 80); gc:drawString(s.n_gelenk_B and "Ja" or "Nein", b - 60, 100)
                    gc:drawString(s.q_gelenk_A and "Ja" or "Nein", b - 60, 120); gc:drawString(s.q_gelenk_B and "Ja" or "Nein", b - 60, 140)
                elseif menuSeite == 5 then
                    gc:drawString("Na (Start):", b - 160, 40); gc:drawString("Qa (Start):", b - 160, 60); gc:drawString("Ma (Start):", b - 160, 80); gc:drawString("Nb (Ende):", b - 160, 100); gc:drawString("Qb (Ende):", b - 160, 120); gc:drawString("Mb (Ende):", b - 160, 140)
                    gc:setColorRGB(0, 120, 0)
                    
                    local function fm(str)
                        if not str then return "0" end
                        return str:gsub("%*", "·"):gsub("%^2", "²"):gsub("%^3", "³")
                    end

                    if symbolischer_modus then
                        gc:drawString(fm(s.symb_N_start), b - 60, 40); gc:drawString(fm(s.symb_Q_start), b - 60, 60); gc:drawString(fm(s.symb_M_start), b - 60, 80)
                        gc:drawString(fm(s.symb_N_end), b - 60, 100); gc:drawString(fm(s.symb_Q_end), b - 60, 120); gc:drawString(fm(s.symb_M_end), b - 60, 140)
                    else
                        gc:drawString(formatLabel(-s.s_local[1] or 0), b - 60, 40); gc:drawString(formatLabel(-s.s_local[2] or 0), b - 60, 60); gc:drawString(formatLabel(-s.s_local[3] or 0), b - 60, 80)
                        gc:drawString(formatLabel(s.s_local[4] or 0), b - 60, 100); gc:drawString(formatLabel(s.s_local[5] or 0), b - 60, 120); gc:drawString(formatLabel(s.s_local[6] or 0), b - 60, 140)
                    end
                elseif menuSeite == 6 then
                    gc:drawString("h_a (links+):", b - 160, 40); gc:drawString("v_a (oben+):", b - 160, 60); gc:drawString("M_a (Uhrz.+):", b - 160, 80); gc:drawString("h_b (rechts+):", b - 160, 100); gc:drawString("v_b (unten+):", b - 160, 120); gc:drawString("M_b (Gegen-U.+):", b - 160, 140)
                    gc:setColorRGB(0, 120, 0)
    
                    local k1, k2 = knoten[s.k1], knoten[s.k2]
                    local dx, dy = k2.x - k1.x, k2.y - k1.y
                local L = math.sqrt(dx^2 + dy^2)
                if L > 0 then
                    local c, s_val = dx/L, -dy/L
                    local Na, Va, Ma = s.s_local[1] or 0, s.s_local[2] or 0, s.s_local[3] or 0
                    local Nb, Vb, Mb = s.s_local[4] or 0, s.s_local[5] or 0, s.s_local[6] or 0

                    local loadAppliedMenu = {}
                    local offsetX_A, offsetY_A, offsetM_A = 0, 0, 0
                    local offsetRx_A, offsetRy_A, offsetRm_A = 0, 0, 0
                    local offsetX_B, offsetY_B, offsetM_B = 0, 0, 0
                    local offsetRx_B, offsetRy_B, offsetRm_B = 0, 0, 0

                    for idx, temp_s in ipairs(staebe) do
                        local explA = knoten[temp_s.k1].gelenk or temp_s.gelenk_A or temp_s.n_gelenk_A or temp_s.q_gelenk_A
                        local explB = knoten[temp_s.k2].gelenk or temp_s.gelenk_B or temp_s.n_gelenk_B or temp_s.q_gelenk_B
                        if explA and not loadAppliedMenu[temp_s.k1] then
                            if idx == menuIndex then
                                local kn = knoten[temp_s.k1]
                                offsetX_A = kn.last_x; offsetY_A = kn.last_y; offsetM_A = kn.last_m
                                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                                offsetRx_A = isSupp and kn.Rx_glob or 0; offsetRy_A = isSupp and kn.Ry_glob or 0; offsetRm_A = isSupp and kn.Rm_glob or 0
                            end
                            loadAppliedMenu[temp_s.k1] = true
                        end
                        if explB and not loadAppliedMenu[temp_s.k2] then
                            if idx == menuIndex then
                                local kn = knoten[temp_s.k2]
                                offsetX_B = kn.last_x; offsetY_B = kn.last_y; offsetM_B = kn.last_m
                                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                                offsetRx_B = isSupp and kn.Rx_glob or 0; offsetRy_B = isSupp and kn.Ry_glob or 0; offsetRm_B = isSupp and kn.Rm_glob or 0
                            end
                            loadAppliedMenu[temp_s.k2] = true
                        end
                    end

                    local uxA, uyA = dx/L, dy/L
                    local nxA, nyA = -uyA, uxA
                    local uxB, uyB = dx/L, dy/L
                    local nxB, nyB = -uyB, uxB
                    
                    if (s.bogen_r or 0) ~= 0 then
                        local true_L = (L / drawPxProMeter)
                        local R = math.abs(s.bogen_r)
                        local sgn = s.bogen_r > 0 and -1 or 1
                        local function getTang(t)
                            local xl = (t - 0.5) * true_L
                            local denom = math.sqrt(math.max(1e-6, R^2 - xl^2))
                            local tx_l, ty_l = 1, -sgn * (xl / denom)
                            local len = math.sqrt(tx_l^2 + ty_l^2)
                            tx_l, ty_l = tx_l/len, ty_l/len
                            local t_gx = tx_l * (dx/L) - ty_l * (dy/L)
                            local t_gy = tx_l * (dy/L) + ty_l * (dx/L)
                            return t_gx, t_gy, -t_gy, t_gx
                        end
                        uxA, uyA, nxA, nyA = getTang(0)
                        uxB, uyB, nxB, nyB = getTang(1)
                    end

                    local Fx_a = Na * uxA + Va * nxA - (offsetX_A + offsetRx_A)
                    local Fy_a = Na * uyA + Va * nyA - (offsetY_A + offsetRy_A)
                    local Fx_b = Nb * uxB + Vb * nxB - (offsetX_B + offsetRx_B)
                    local Fy_b = Nb * uyB + Vb * nyB - (offsetY_B + offsetRy_B)

                    local M_a_disp = -(Ma - (offsetM_A + offsetRm_A))
                    local M_b_disp = Mb - (offsetM_B + offsetRm_B)

            local s_Fx_a, s_Fy_a, s_Fx_b, s_Fy_b = nil, nil, nil, nil
            if symbolischer_modus then
                s_Fx_a = s.symb_Fx_a or s.symb_N_start
                s_Fy_a = s.symb_Fy_a or s.symb_Q_start
                s_Fx_b = s.symb_Fx_b or s.symb_N_end
                s_Fy_b = s.symb_Fy_b or s.symb_Q_end
            end

                    local function cl(v) return math.abs(v) < 1e-4 and 0 or v end
                    
                    local function fm(str)
                        if not str then return "0" end
                        return str:gsub("%*", "·"):gsub("%^2", "²"):gsub("%^3", "³")
                    end

                    if symbolischer_modus then
                        -- Für Gelenkkräfte ignorieren wir im symbolischen Modus die Auflagerkräfte, da diese numerisch (z.B. 0.5) berechnet wurden.
                        -- Bei geraden Einfeldträgern sind uxA, uyA entweder 1 oder 0, sodass die Projektion trivial ist.
                        local s_Fx_a = s.symb_Fx_a_disp or ("-(" .. (s.symb_N_start or "0") .. ")")
                        local s_Fy_a = s.symb_Fy_a_disp or ("-(" .. (s.symb_Q_start or "0") .. ")")
                        local s_Fx_b = s.symb_Fx_b or s.symb_N_end
                        local s_Fy_b = s.symb_Fy_b or s.symb_Q_end
                        
                        gc:drawString(fm(s_Fx_a), b - 60, 40)
                        gc:drawString(fm(s_Fy_a), b - 60, 60)
                        gc:drawString(fm(s.symb_Ma_disp or "0"), b - 60, 80)
                        gc:drawString(fm(s_Fx_b), b - 60, 100)
                        gc:drawString(fm(s_Fy_b), b - 60, 120)
                        gc:drawString(fm(s.symb_M_end), b - 60, 140)
                    else
                        gc:drawString(string.format("%.2f kN", cl(-Fx_a)), b - 60, 40)
                        gc:drawString(string.format("%.2f kN", cl(-Fy_a)), b - 60, 60)
                        gc:drawString(string.format("%.2f kNm", cl(M_a_disp)), b - 60, 80)
                        gc:drawString(string.format("%.2f kN", cl(Fx_b)), b - 60, 100)
                        gc:drawString(string.format("%.2f kN", cl(Fy_b)), b - 60, 120)
                        gc:drawString(string.format("%.2f kNm", cl(M_b_disp)), b - 60, 140)
                    end
                end
            elseif menuSeite == 7 then
                gc:drawString("ua (m):", b - 160, 40); gc:drawString("va (m):", b - 160, 60); gc:drawString("phi_a (rad):", b - 160, 80); gc:drawString("ub (m):", b - 160, 100); gc:drawString("vb (m):", b - 160, 120); gc:drawString("phi_b (rad):", b - 160, 140)
                gc:setColorRGB(180, 0, 180)
                gc:drawString(string.format("%.3e", s.v_local[1] or 0):gsub("%.", ","), b - 70, 40); gc:drawString(string.format("%.3e", s.v_local[2] or 0):gsub("%.", ","), b - 70, 60); gc:drawString(string.format("%.3e", s.v_local[3] or 0):gsub("%.", ","), b - 70, 80)
                gc:drawString(string.format("%.3e", s.v_local[4] or 0):gsub("%.", ","), b - 70, 100); gc:drawString(string.format("%.3e", s.v_local[5] or 0):gsub("%.", ","), b - 70, 120); gc:drawString(string.format("%.3e", s.v_local[6] or 0):gsub("%.", ","), b - 70, 140)
                gc:setColorRGB(0, 0, 0); gc:drawString("In TI speichern:", b - 160, 160)
                if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 160)
            end
        end

        elseif menuTyp == "pvv_knoten" then
            local k = knoten[menuIndex]
            gc:drawString("PvV-Bindungslösung", b - 160, 15); gc:setFont("sansserif", "r", 9)
            gc:drawString("Lager X entfernen", b - 160, 40)
            gc:drawString("Lager Y entfernen", b - 160, 60)
            gc:drawString("Lager M entfernen", b - 160, 80)
            local rod_count = 0
            for _, s in ipairs(staebe) do if s.k1 == menuIndex or s.k2 == menuIndex then rod_count = rod_count + 1 end end
            
            if rod_count == 2 then
                gc:drawString("Gelenk einfügen", b - 160, 100)
            else
                gc:setColorRGB(150, 150, 150)
                gc:drawString("Gelenk (nur bei 2 Stäben)", b - 160, 100)
            end
            
            gc:setColorRGB(0, 0, 255)
            if menuZeile == 1 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if not k.lager_x then gc:setColorRGB(150, 150, 150) end
            gc:drawString(k.lager_x and "Ja" or "Fehlt", b - 60, 40)
            
            if menuZeile == 2 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if not k.lager_y then gc:setColorRGB(150, 150, 150) end
            gc:drawString(k.lager_y and "Ja" or "Fehlt", b - 60, 60)
            
            if menuZeile == 3 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if not k.lager_m then gc:setColorRGB(150, 150, 150) end
            gc:drawString(k.lager_m and "Ja" or "Fehlt", b - 60, 80)
            
            if rod_count == 2 then
                if menuZeile == 4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                if k.gelenk then gc:setColorRGB(150, 150, 150) end
                gc:drawString(not k.gelenk and "Einfügen" or "Vorhanden", b - 60, 100)
            end
        elseif menuTyp == "pvv_stab" then
            local s = staebe[menuIndex]
            gc:drawString("PvV-Stablösung", b - 160, 15); gc:setFont("sansserif", "r", 9)
            gc:drawString("M-Gelenk A", b - 160, 40)
            gc:drawString("M-Gelenk B", b - 160, 60)
            gc:drawString("N-Gelenk A", b - 160, 80)
            gc:drawString("N-Gelenk B", b - 160, 100)
            gc:drawString("Q-Gelenk A", b - 160, 120)
            gc:drawString("Q-Gelenk B", b - 160, 140)
            
            if menuZeile == 1 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if s.gelenk_A then gc:setColorRGB(150, 150, 150) end
            gc:drawString(not s.gelenk_A and "Einfügen" or "Vorh.", b - 60, 40)
            
            if menuZeile == 2 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if s.gelenk_B then gc:setColorRGB(150, 150, 150) end
            gc:drawString(not s.gelenk_B and "Einfügen" or "Vorh.", b - 60, 60)
            
            if menuZeile == 3 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if s.n_gelenk_A then gc:setColorRGB(150, 150, 150) end
            gc:drawString(not s.n_gelenk_A and "Einfügen" or "Vorh.", b - 60, 80)
            
            if menuZeile == 4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if s.n_gelenk_B then gc:setColorRGB(150, 150, 150) end
            gc:drawString(not s.n_gelenk_B and "Einfügen" or "Vorh.", b - 60, 100)
            
            if menuZeile == 5 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 120)
                            if menuZeile == 6 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 140)
                            if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            if s.q_gelenk_A then gc:setColorRGB(150, 150, 150) end
            gc:drawString(not s.q_gelenk_A and "Einfügen" or "Vorh.", b - 60, 120)
            
            if menuZeile == 6 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
            gc:drawString(not s.q_gelenk_B and "Einfügen" or "Vorh.", b - 60, 140)
        elseif menuTyp == "obermenue" then
            gc:drawString("Einstellungen < S." .. menuSeite .. "/4 >", b - 200, 15); gc:setFont("sansserif", "r", 9)
            if menuSeite == 1 then
                gc:drawString("Raster (m):", b - 200, 40)
                gc:drawString("Alle EA setzen:", b - 200, 60)
                gc:drawString("Alle EI setzen:", b - 200, 80)
                gc:drawString("Starr-Modus:", b - 200, 100)
                gc:drawString("Auto-KGV Solver:", b - 200, 120)
                gc:drawString("Anzeige N:", b - 200, 140)
                gc:drawString("Schnittgrößen Modus:", b - 200, 160)
                gc:drawString("Fachwerk-Modus:", b - 200, 180)

                gc:setColorRGB(0, 0, 255)
                if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 40) else gc:drawString(rasterMass_str or tostring(rasterMass), b - 80, 40) end
                if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 60) else gc:drawString(defEA_str or string.format("%.3e", defEA):gsub("%.", ","), b - 80, 60) end
                if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 80) else gc:drawString(defEI_str or string.format("%.3e", defEI):gsub("%.", ","), b - 80, 80) end
                if menuZeile == 4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString("Aktivieren", b - 80, 100)
                if menuZeile == 5 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(autoKGV and "An" or "Aus", b - 80, 120)
                if menuZeile == 6 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(zeigeN and "An" or "Aus", b - 80, 140)
                if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString((schnittAnzeigeModus == "Hover") and "Hover" or "Start&End", b - 80, 160)
                if menuZeile == 8 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(fachwerkModus and "An" or "Aus", b - 80, 180)

            elseif menuSeite == 2 then
                gc:drawString("Alles Exportieren:", b - 200, 40)
                gc:drawString("Nur Biegelinien exp.:", b - 200, 60)
                gc:drawString("Nur Längslinien exp.:", b - 200, 80)
                gc:drawString("KGV Daten exp.:", b - 200, 100)
                gc:drawString("Arbeitssatz exp.:", b - 200, 120)
                gc:drawString("Nur Schnittgrößen exp.:", b - 200, 140)
                gc:drawString("LGS Matrix exp.:", b - 200, 160)
                gc:drawString("Neue Biegelinie exp.:", b - 200, 180)
                gc:drawString("Neue Längslinie exp.:", b - 200, 200)

                gc:setColorRGB(0, 0, 255)
                if menuZeile == 1 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 40)
                
                if menuZeile == 2 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 60)
                
                if menuZeile == 3 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 80)
                
                if menuZeile == 4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 100)
                
                if menuZeile == 5 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 120)
                
                if menuZeile == 6 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 140)
                
                if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 160)
                if menuZeile == 8 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 180)
                if menuZeile == 9 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 70, 200)
            elseif menuSeite == 3 then
                gc:drawString("CAS Bruch-Tol. (1E-x):", b - 200, 40)
                gc:drawString("Punkte/Stab (Graph):", b - 200, 60)
                gc:drawString("Zoom-Schritt Normal:", b - 200, 80)
                gc:drawString("Zoom-Schritt Expl.:", b - 200, 100)
                gc:drawString("Bemaßung zeigen:", b - 200, 120)
                gc:drawString("Bogen-Segmente:", b - 200, 140)
                gc:drawString("Zahlen-Format:", b - 200, 160)
                gc:drawString("Maximalwerte an/aus:", b - 200, 180)
                gc:drawString("Rasterpunkte:", b - 200, 200)

                gc:setColorRGB(0, 0, 255)
                if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 40) else gc:drawString(tostring(casToleranz), b - 80, 40) end
                if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 60) else gc:drawString(tostring(ptsBiegelinie), b - 80, 60) end
                if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 80) else gc:drawString(tostring(zoomNormal), b - 80, 80) end
                if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 100) else gc:drawString(tostring(zoomExplosion), b - 80, 100) end
                
                gc:setColorRGB(0, 0, 255)
                if menuZeile == 5 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(zeigeBemassung and "An" or "Aus", b - 80, 120)
                
                gc:setColorRGB(0, 0, 255)
                if menuZeile == 6 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 140) else gc:drawString(tostring(bogenSegmente), b - 80, 140) end

                gc:setColorRGB(0, 0, 255)
                if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                local fmtStr = "Wurzelbrüche"
                if zahlenFormat == 2 then fmtStr = "Nur Brüche"
                elseif zahlenFormat == 3 then fmtStr = "Dezimal" end
                gc:drawString(fmtStr, b - 80, 160)
                
                gc:setColorRGB(0, 0, 255)
                if menuZeile == 8 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(zeigeMaxWerte and "An" or "Aus", b - 80, 180)
                if menuZeile == 9 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString((rasterPunkte == 0) and "Keine" or ((rasterPunkte == 2) and "Dick" or "Normal"), b - 80, 200)
            elseif menuSeite == 4 then
                gc:drawString("Polstrahle zeichnen:", b - 200, 40)
                gc:setColorRGB(0, 0, 255)
                if menuZeile == 1 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                
                local polStr = "Notwendige"
                local pm = polstrahlModus or 1
                if pm == 0 then polStr = "Keine"
                elseif pm == 2 then polStr = "Alle" end
                
                gc:drawString(polStr, b - 80, 40)
                
                gc:setColorRGB(0, 0, 0)
                gc:drawString("Verlauf-Skalierung:", b - 200, 60)
                gc:setColorRGB(0, 0, 255)
                if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 80, 60) else
                    if menuZeile == 2 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                    gc:drawString(string.format("%.2f", verlaufSkalierung or 1), b - 80, 60)
                end
                gc:setColorRGB(0, 0, 0)
                gc:drawString("Standard-EA dehnstarr:", b - 200, 80)
                if menuZeile == 3 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(randDehnstarr and "An" or "Aus", b - 80, 80)
                gc:setColorRGB(0, 0, 0)
                gc:drawString("Starre Staebe (Export):", b - 200, 100)
                if menuZeile == 4 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString(randStarrDirekt and "direkt" or "Grenzwert", b - 80, 100)
                gc:setColorRGB(0, 0, 0)
                gc:drawString("System speichern als:", b - 200, 120)
                gc:drawString("System öffnen:", b - 200, 140)
                local nrText = letzteSystemNr and ("system" .. letzteSystemNr) or "Nr. eingeben"
                for z = 5, 6 do
                    if menuZeile == z and eingabeModus then
                        gc:setColorRGB(0, 0, 255); gc:drawString(eingabeText .. "_", b - 80, 20 + 20 * z)
                    else
                        if menuZeile == z then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                        gc:drawString(nrText, b - 80, 20 + 20 * z)
                    end
                end
                gc:setColorRGB(0, 0, 0)
                gc:drawString("Variablen loeschen:", b - 200, 160)
                if menuZeile == 7 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                gc:drawString((varLoeschFrage and menuZeile == 7) and "Sicher? Enter" or "Loeschen", b - 80, 160)
            end
        end
    end
    if loeschFrage then
        local boxW, boxH = math.min(b - 20, 260), 44
        local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 165, 0); gc:fillRect(boxX, boxY, boxW, boxH)
        gc:setColorRGB(0, 0, 0); gc:setPen("thin", "smooth"); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("Wirklich alles loeschen?", boxX + 8, boxY + 6)
        gc:setFont("sansserif", "r", 9); gc:drawString("[Enter] loeschen    [Esc] abbrechen", boxX + 8, boxY + 24)
    end
    ansichtsModus = orig_ansichtsModus
end