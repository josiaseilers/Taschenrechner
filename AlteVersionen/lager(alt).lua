-- ==========================================
-- 1. DATENSTRUKTUR & EINSTELLUNGEN
-- ==========================================
local knoten = {}
local staebe = {}
local auswahl = nil
local hoverObj = nil
local hoverTyp = nil
local mouseX, mouseY = 0, 0

pxProMeter = 30    
offsetX = 160      
offsetY = 106      

rasterMass = 1.0   
defEA = 1e8        
defEI = 1e8        
autoKGV = false    
zeigeN = true      

ptsBiegelinie = 20
zoomNormal = 2
zoomExplosion = 5
casToleranz = 5
verlaufSkalierung = 1
systemBerechnet = false

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
        cx_str = "0", cy_str = "0", cm_str = "0",
        last_x = 0, last_y = 0, last_m = 0, last_w = 0,
        winkel = 0, f_winkel = 0,
        R_xi = 0, R_eta = 0, R_m = 0,
        Rx_glob = 0, Ry_glob = 0, Rm_glob = 0
    }
end

local function erstelleStab(k1_idx, k2_idx)
    return { 
        k1 = k1_idx, k2 = k2_idx, 
        EA = defEA, EI = defEI, bogen_r = 0, 
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
-- 3. HILFSFUNKTIONEN & CAS EXPORT
-- ==========================================
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
    if type(value) == "string" then return tonumber(value:gsub(",", ".")) end
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
                    return tonumber(res:gsub(",", "."))
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
                local n = tonumber(res:gsub(",", "."))
                if n then return n, text end
            end
        end
    end
    
    return nil, text
end

local function evalFederInput(text, k, keep_str)
    if type(text) ~= "string" then return nil, text end

    local evalText = text
    local nodeIndex = nil
    for i, node in ipairs(knoten) do
        if node == k then nodeIndex = i; break end
    end

    local refStab = nil
    if nodeIndex then
        for _, stab in ipairs(staebe) do
            if stab.k1 == nodeIndex or stab.k2 == nodeIndex then
                refStab = stab
                break
            end
        end
    end

    if refStab then
        local k1, k2 = knoten[refStab.k1], knoten[refStab.k2]
        local dx, dy = k2.x - k1.x, k2.y - k1.y
        local L = math.sqrt(dx^2 + dy^2)
        evalText = evalText:gsub("%f[%a]EI%f[%A]", "(" .. tostring(refStab.EI or 0) .. ")")
        evalText = evalText:gsub("%f[%a]l%f[%A]", "(" .. tostring(L) .. ")")
    end

    local hasSymbolicReference = text:find("%f[%a]EI%f[%A]") or text:find("%f[%a]l%f[%A]")
    if hasSymbolicReference then getDummyNumeric(text) end
    local value = evalInput(evalText)
    return value, keep_str and text or nil
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
        local strict_frac = floatToFrac_lua(v, 1e-5, 10000)
        if strict_frac then return strict_frac end
        
        -- 2. Try square root of a simple fraction (using a slightly looser tolerance because numeric squaring amplifies errors)
        local sq = v * v
        if zahlenFormat == 1 and sq <= 10000 then
            local sq_frac = floatToFrac_lua(sq, 1e-4, 2000)
            if sq_frac then
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
        local loose_frac = floatToFrac_lua(v, tol, 10000)
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
                    return string.format("%.2f", val)
                end
                
                approx_res = approx_res:gsub("(%d*%.?%d*%s*[eE]%s*[+-]?%s*%d+)", processFloat)
                approx_res = approx_res:gsub("(%d+%.%d+)", processFloat)
                approx_res = approx_res:gsub("(%d+)%.00", "%1")
                
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

local function exportStabToTI(i)
    local s = staebe[i]
    if s.mat_k then
        speichereMatrix("stab" .. i .. "_k", s.mat_k)
        speichereMatrix("stab" .. i .. "_p", s.mat_p)
        speichereMatrix("stab" .. i .. "_v", s.mat_v)
    end
        
    local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
    local L = math.sqrt(dx^2 + dy^2)
    if (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= L/2 and L > 0 then
        local fN = fN_export
        local R = math.abs(s.bogen_r)
        local sgn = s.bogen_r > 0 and -1 or 1
        local NA = s.arc_N_A or 0
        local VA = s.arc_V_A or 0
        local MA = s.arc_M_A or 0
        
        local expr_M = fN(MA) .. " + " .. fN(VA*R) .. "*sin(p) + " .. fN(sgn*NA*R) .. "*(1-cos(p))"
        local expr_N = fN(NA) .. "*cos(p) - " .. fN(sgn*VA) .. "*sin(p)"
        local expr_V = fN(sgn*NA) .. "*sin(p) + " .. fN(VA) .. "*cos(p)"
        
        if math.eval then
            math.eval("M_bogen" .. i .. "(p) := " .. eval_cas_string(expr_M, true))
            math.eval("N_bogen" .. i .. "(p) := " .. eval_cas_string(expr_N, true))
            math.eval("q_bogen" .. i .. "(p) := " .. eval_cas_string(expr_V, true))
            print("-> Bogen " .. i .. " (M, N, Q in Abh. v. Winkel p) exportiert!")
        end
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
    if #staebe == 0 or not staebe[1].mat_k then print("Fehler: Bitte zuerst das System berechnen!"); return end
    for i = 1, #staebe do exportStabToTI(i) end
    for i = 1, #knoten do exportKnotenToTI(i) end
    if glob_K and glob_F and glob_u then
        speichereMatrix("sys_k", glob_K); local mat_F, mat_u = {}, {}
        for i = 1, anzahlGleichungen do mat_F[i] = {glob_F[i] or 0}; mat_u[i] = {glob_u[i] or 0} end
        if anzahlGleichungen > 0 then speichereMatrix("sys_f", mat_F); speichereMatrix("sys_u", mat_u) end
    end
    print("-> Matrizen und Systemdaten exportiert!")
end

local function getEqQ(s, L, fN, L_str)
    local c_val = (knoten[s.k2].x - knoten[s.k1].x) / L
    local s_val = -(knoten[s.k2].y - knoten[s.k1].y) / L
    local f_gx = s.gx_proj and math.abs(s_val) or 1
    local f_gy = s.gy_proj and math.abs(c_val) or 1
    local base = "("..(s.q_str or "0")..") + ("..(s.gx_str or "0")..")*"..fN(f_gx * s_val).." + ("..(s.gy_str or "0")..")*"..fN(f_gy * c_val)
    if L_str and (s.q_A_str or s.q_B_str) then
        base = base .. " + ("..(s.q_A_str or "0")..") + (("..(s.q_B_str or "0")..")-("..(s.q_A_str or "0").."))*x/("..L_str..")"
    end
    return base
end

local function getEqN(s, L, fN, L_str)
    local c_val = (knoten[s.k2].x - knoten[s.k1].x) / L
    local s_val = -(knoten[s.k2].y - knoten[s.k1].y) / L
    local f_gx = s.gx_proj and math.abs(s_val) or 1
    local f_gy = s.gy_proj and math.abs(c_val) or 1
    local base = "("..(s.n_str or "0")..") + ("..(s.gx_str or "0")..")*"..fN(f_gx * c_val).." - ("..(s.gy_str or "0")..")*"..fN(f_gy * s_val)
    if L_str and (s.n_A_str or s.n_B_str) then
        base = base .. " + ("..(s.n_A_str or "0")..") + (("..(s.n_B_str or "0")..")-("..(s.n_A_str or "0").."))*x/("..L_str..")"
    end
    return base
end

exportSchnittkraefteToTI = function(stab_index)
    if #staebe == 0 or not staebe[1].mat_k then return end
    if math.eval then
        local fN = fN_export
        
        local start_i = stab_index or 1
        local end_i = stab_index or #staebe
        for i = start_i, end_i do
            local s = staebe[i]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 and (s.bogen_r or 0) == 0 then
                local N0 = symbolischer_modus and ("-(" .. (s.symb_start.N or "0") .. ")") or fN(-s.s_local[1])
                local Q0 = symbolischer_modus and ("-(" .. (s.symb_start.V or "0") .. ")") or fN(-s.s_local[2])
                local M0 = symbolischer_modus and ("-(" .. (s.symb_start.M or "0") .. ")") or fN(-s.s_local[3])
                
                local L_str = fN(L)
                if symbolischer_modus then
                    local L_sym = "L"
                    for var, _ in pairs(sym_vars) do
                        for _, k_node in ipairs(knoten) do
                            if (k_node.x_str and k_node.x_str:find("%f[%a]" .. var .. "%f[%A]")) or (k_node.y_str and k_node.y_str:find("%f[%a]" .. var .. "%f[%A]")) then L_sym = var; break end
                        end
                    end
                    local L_dummy = sym_vars[L_sym] or 1.0
                    local scale = L / L_dummy
                    L_str = (math.abs(scale - 1) < 1e-5) and L_sym or ("(" .. scale .. "*" .. L_sym .. ")")
                end
                
                local eq_q = getEqQ(s, L, fN, L_str)
                local eq_n = getEqN(s, L, fN, L_str)
                local use_cas_q = symbolischer_modus or string.find(eq_q, "x")
                local use_cas_n = symbolischer_modus or string.find(eq_n, "x")
                local use_cas_m = symbolischer_modus or (s.m_str and string.find(s.m_str, "x"))
                
                local c_val, s_val = dx/L, -dy/L
                local eff_gx = (s.gx or 0) * (s.gx_proj and math.abs(s_val) or 1)
                local eff_gy = (s.gy or 0) * (s.gy_proj and math.abs(c_val) or 1)
                local n_add = eff_gx * c_val - eff_gy * s_val
                local q_add = eff_gx * s_val + eff_gy * c_val
                local qA, qB = s.q + s.q_A + q_add, s.q + s.q_B + q_add
                local nA, nB = s.n + s.n_A + n_add, s.n + s.n_B + n_add
                
                local expr_N = ""
                if use_cas_n then
                    expr_N = N0 .. " - integral(("..eq_n:gsub("x","t").."),t,0,x)"
                else
                    expr_N = N0 .. " - ("..fN(nA).."*x + ("..fN(nB).."-"..fN(nA)..")*x^2/(2*"..L_str.."))"
                end
                
                local expr_Q = ""
                if use_cas_q then
                    expr_Q = Q0 .. " - integral(("..eq_q:gsub("x","t").."),t,0,x)"
                else
                    expr_Q = Q0 .. " - ("..fN(qA).."*x + ("..fN(qB).."-"..fN(qA)..")*x^2/(2*"..L_str.."))"
                end
                
                local expr_M = M0 .. " + " .. Q0 .. "*x - " .. fN(s.m) .. "*x"
                if use_cas_q then
                    expr_M = expr_M .. " - integral(("..eq_q:gsub("x","t")..")*(x-t),t,0,x)"
                else
                    expr_M = expr_M .. " - ("..fN(qA).."*x^2/2 + ("..fN(qB).."-"..fN(qA)..")*x^3/(6*"..L_str.."))"
                end
                
                if use_cas_m then
                    expr_M = expr_M .. " - integral(("..s.m_str:gsub("x","t").."),t,0,x)"
                end
                
                math.eval("N_stab" .. i .. "(x) := " .. eval_cas_string(expr_N, true))
                math.eval("Q_stab" .. i .. "(x) := " .. eval_cas_string(expr_Q, true))
                math.eval("M_stab" .. i .. "(x) := " .. eval_cas_string(expr_M, true))
            end
        end
        print("-> Analytische Schnittkraftverläufe (N, Q, M) exportiert!")
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
    
    local L_sym = "L"
    for var, _ in pairs(sym_vars) do
        for _, k_node in ipairs(knoten) do
            if (k_node.x_str and k_node.x_str:find("%f[%a]" .. var .. "%f[%A]")) or (k_node.y_str and k_node.y_str:find("%f[%a]" .. var .. "%f[%A]")) then L_sym = var; break end
        end
    end
    
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

        for j = 0, pts do
            local t = j / pts
            local x = t * L
            local cas_Q_drop = (s.Q_cas_pts and s.Q_cas_pts[j+1]) or 0
            local cas_M_drop = (s.M_cas_pts and s.M_cas_pts[j+1]) or 0
            local cas_N_drop = (s.N_cas_pts and s.N_cas_pts[j+1]) or 0
            
            local val_M = M0 + Q0*x - (s.m or 0)*x - (qA*(x^2)/2 + (qB-qA)*(x^3)/(6*L)) + cas_M_drop
            local val_Q = Q0 - (qA*x + (qB-qA)*(x^2)/(2*L)) + cas_Q_drop
            local val_N = N0 - (nA*x + (nB-nA)*(x^2)/(2*L)) + cas_N_drop
            
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
        
        t_M = refine_t(t_M, "M")
        t_Q = refine_t(t_Q, "Q")
        t_N = refine_t(t_N, "N")
        
        local function fixT(t)
            if math.abs(t) < 1e-4 then return "0" end
            if math.abs(t - 1) < 1e-4 then return "1" end
            if math.abs(t - 1/math.sqrt(3)) < 1e-4 then return "(1/sqrt(3))" end
            if math.abs(t - (1 - 1/math.sqrt(3))) < 1e-4 then return "(1 - 1/sqrt(3))" end
            return fN(t)
        end
        
        local L_dummy = sym_vars[L_sym] or 1.0
        local scale = L / L_dummy
        local L_str = (math.abs(scale - 1) < 1e-5) and L_sym or ("(" .. fN(scale) .. "*" .. L_sym .. ")")
        
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
    if #staebe == 0 or not staebe[1].mat_k then print("Fehler: Bitte zuerst das System berechnen!"); return end
    if math.eval then
        local fN = fN_export
        
        local start_i = stab_index or 1
        local end_i = stab_index or #staebe
        for i = start_i, end_i do
            local s = staebe[i]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local EI = s.EI
                local qA, qB = s.q_A, s.q_B 
                local va = (math.abs(s.v_local[2] or 0) < 1e-12) and 0 or s.v_local[2]
                local phia = (math.abs(s.v_local[3] or 0) < 1e-12) and 0 or s.v_local[3]
                local vb = (math.abs(s.v_local[5] or 0) < 1e-12) and 0 or s.v_local[5]
                local phib = (math.abs(s.v_local[6] or 0) < 1e-12) and 0 or s.v_local[6]
                
                local L_str = fN(L)
                if symbolischer_modus then
                    local L_sym = "L"
                    for var, _ in pairs(sym_vars) do
                        for _, k_node in ipairs(knoten) do
                            if (k_node.x_str and k_node.x_str:find("%f[%a]" .. var .. "%f[%A]")) or (k_node.y_str and k_node.y_str:find("%f[%a]" .. var .. "%f[%A]")) then L_sym = var; break end
                        end
                    end
                    local L_dummy = sym_vars[L_sym] or 1.0
                    local scale = L / L_dummy
                    L_str = (math.abs(scale - 1) < 1e-5) and L_sym or ("(" .. scale .. "*" .. L_sym .. ")")
                end
                
                local eq_q = getEqQ(s, L, fN, L_str)
                local use_cas_q = symbolischer_modus or string.find(eq_q, "x")
                local use_cas_m = symbolischer_modus or (s.m_str and string.find(s.m_str, "x"))
                
                local v_L_last = 0
                local phi_L_last = 0
                local v_last_expr = ""
                local v_L_last_symb = "0"
                local phi_L_last_symb = "0"
                
                if use_cas_q or symbolischer_modus then
                    local q_t = eq_q:gsub("x", "t")
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
                    local m_t = s.m_str:gsub("x", "t")
                    v_last_expr = v_last_expr .. " - integral(("..m_t..")*(x-t)^2,t,0,x)/2"
                    v_L_last_symb = v_L_last_symb .. " - integral(("..m_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2"
                    if not symbolischer_modus then
                        v_L_last = v_L_last + (casToNumber(math.eval("approx(-integral(("..m_t..")*("..L_str.."-t)^2,t,0,"..L_str..")/2)")) or 0)
                        phi_L_last = phi_L_last + (casToNumber(math.eval("approx(-integral(("..m_t..")*("..L_str.."-t),t,0,"..L_str.."))")) or 0)
                    end
                    phi_L_last_symb = phi_L_last_symb .. " - integral(("..m_t..")*("..L_str.."-t),t,0,"..L_str..")"
                end
                
                local c1 = symbolischer_modus and ("(" .. (s.symb_start.c1 or "0") .. ")") or fN(-va * EI)
                local c2 = symbolischer_modus and ("(" .. (s.symb_start.c2 or "0") .. ")") or fN(-phia * EI)
                local c3 = symbolischer_modus and "((" .. (s.symb_start.vb or "0") .. ") - (" .. v_L_last_symb .. "))" or fN(-vb * EI - v_L_last)
                local c4 = symbolischer_modus and "((" .. (s.symb_start.phib or "0") .. ") - (" .. phi_L_last_symb .. "))" or fN(-phib * EI - phi_L_last)
                
                local has_inner_hinge = knoten[s.k1].gelenk or knoten[s.k2].gelenk or s.gelenk_A or s.gelenk_B
                local expr
                if has_inner_hinge and not symbolischer_modus then
                    -- At an inner hinge, the integrated load function is continued
                    -- from the hinge with its displacement and rotation as constants.
                    expr = v_last_expr .. " + " .. fN(va * EI) .. " - " .. fN(phia * EI) .. "*x"
                else
                    expr = v_last_expr .. " + " .. c1 .. "*(1-3*(x/"..L_str..")^2+2*(x/"..L_str..")^3) + " .. c2 .. "*(x-2*x^2/"..L_str.."+x^3/("..L_str.."^2)) + " .. c3 .. "*(3*(x/"..L_str..")^2-2*(x/"..L_str..")^3) + " .. c4 .. "*(-x^2/"..L_str.."+x^3/("..L_str.."^2))"
                end
                
                math.eval("v_EI_dbg_c1_" .. i .. "(x) := " .. c1)
                math.eval("v_EI_dbg_c2_" .. i .. "(x) := " .. c2)
                math.eval("v_EI_dbg_c3_" .. i .. "(x) := " .. c3)
                math.eval("v_EI_dbg_c4_" .. i .. "(x) := " .. c4)
                math.eval("v_EI_dbg_load_" .. i .. "(x) := " .. v_last_expr)
                math.eval("v_EI_dbg_h1_" .. i .. "(x) := " .. c1 .. "*(1-3*(x/"..L_str..")^2+2*(x/"..L_str..")^3)")
                math.eval("v_EI_dbg_h2_" .. i .. "(x) := " .. c2 .. "*(x-2*x^2/"..L_str.."+x^3/("..L_str.."^2))")
                math.eval("v_EI_dbg_h3_" .. i .. "(x) := " .. c3 .. "*(3*(x/"..L_str..")^2-2*(x/"..L_str..")^3)")
                math.eval("v_EI_dbg_h4_" .. i .. "(x) := " .. c4 .. "*(-x^2/"..L_str.."+x^3/("..L_str.."^2))")
                math.eval("v_EI_stab_raw" .. i .. "(x) := " .. expr)
                -- HIER IST DER FIX: exact() liegt jetzt um das gesamte, in Lua bereits rausch-bereinigte Polynom!
                math.eval("v_EI_stab" .. i .. "(x) := " .. eval_cas_string(expr, true))
            end
        end
        print("-> NUR exakte Biegelinien (*EI) exportiert!")
    end
end


exportULinienToTI = function(stab_index)
    if #staebe == 0 or not staebe[1].mat_k then print("Fehler: Bitte zuerst das System berechnen!"); return end
    if math.eval then
        local fN = fN_export
        
        local start_i = stab_index or 1
        local end_i = stab_index or #staebe
        for i = start_i, end_i do
            local s = staebe[i]
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local EA = s.EA
                local nA, nB = s.n_A, s.n_B 
                local ua = (math.abs(s.v_local[1] or 0) < 1e-12) and 0 or s.v_local[1]
                local ub = (math.abs(s.v_local[4] or 0) < 1e-12) and 0 or s.v_local[4]
                local L_str = fN(L)
                local eq_n = getEqN(s, L, fN)
                local use_cas = string.find(eq_n, "x")
                local expr = ""
                
                local c1 = fN(ua * EA)
                local c2 = fN(ub * EA)
                
                if use_cas then
                    local n_t = eq_n:gsub("x", "t")
                    local u_L_last_str = "integral(("..n_t..")*("..L_str.."-t),t,0,"..L_str..")"
                    expr = "-integral(("..n_t..")*(x-t),t,0,x) + (x/"..L_str..") * " .. u_L_last_str .. " + " .. c1 .. "*(1-x/"..L_str..") + " .. c2 .. "*(x/"..L_str..")"
                else
                    local alg_n = s.n + (s.gx or 0) * (s.gx_proj and math.abs(-dy/L) or 1) * (dx/L) - (s.gy or 0) * (s.gy_proj and math.abs(dx/L) or 1) * (-dy/L)
                    nA, nB = nA + alg_n, nB + alg_n
                    local u_L_last = (nA * L^2 / 2) + ((nB - nA) * L^2 / 6)
                    local c3 = fN(u_L_last)
                    local u_last_expr = "-("..fN(nA).."/2)*x^2 - (("..fN(nB).."-"..fN(nA)..")/(6*"..L_str.."))*x^3"
                    expr = u_last_expr .. " + (x/"..L_str..") * " .. c3 .. " + " .. c1 .. "*(1-x/"..L_str..") + " .. c2 .. "*(x/"..L_str..")"
                end
                
                -- HIER IST DER FIX: exact() umspannt das gesamte Polynom!
                math.eval("u_EA_stab" .. i .. "(x) := " .. eval_cas_string(expr, true))
            end
        end
        print("-> Exakte Längslinien (*EA) exportiert!")
    end
end

local function exportKGVToTI()
    if not autoKGV or #X_Werte == 0 then
        print("Fehler: KGV nicht aktiv oder System statisch bestimmt!")
        return
    end
    print("Berechne KGV Matrizen...")
    local orig_zustand = KGV_Zustand
    local Delta0 = {}
    local Delta = {}
    local n = #X_Werte
    for i=1, n do Delta[i] = {} end
    
    local function getGap(x_val, u_vec)
        local rad = math.rad(knoten[x_val.knoten] and knoten[x_val.knoten].winkel or 0)
        if x_val.typ == "lager_x" then 
            local ux = u_vec[knoten[x_val.knoten].eq_x] or 0
            local uy = u_vec[knoten[x_val.knoten].eq_y] or 0
            return ux * math.cos(rad) + uy * math.sin(rad)
        elseif x_val.typ == "lager_y" then 
            local ux = u_vec[knoten[x_val.knoten].eq_x] or 0
            local uy = u_vec[knoten[x_val.knoten].eq_y] or 0
            return -ux * math.sin(rad) + uy * math.cos(rad)
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
            local u1x = (k1.eq_x > 0) and u_vec[k1.eq_x] or 0
            local u1y = (k1.eq_y > 0) and u_vec[k1.eq_y] or 0
            local u2x = (k2.eq_x > 0) and u_vec[k2.eq_x] or 0
            local u2y = (k2.eq_y > 0) and u_vec[k2.eq_y] or 0
            return (u1x - u2x)*ux + (u1y - u2y)*uy
        end
        return 0
    end
    
    applyKGVZustand(0)
    local u0 = berechneSystemGleichungen(false)
    if u0 then for i, x_val in ipairs(X_Werte) do Delta0[i] = {getGap(x_val, u0)} end end
    
    for j = 1, n do
        applyKGVZustand(j)
        local uj = berechneSystemGleichungen(false)
        if uj then for i, x_val in ipairs(X_Werte) do Delta[i][j] = getGap(x_val, uj) end end
    end
    
    applyKGVZustand(orig_zustand)
    rechneAktuellesSystem()
    
    speichereMatrix("kgv_delta", Delta)
    speichereMatrix("kgv_delta0", Delta0)
    print("-> KGV Matrizen (kgv_delta, kgv_delta0) exportiert!")
end
local pvv_cas_cache = {}

function processDistLoad_PvV(L, L_eff, qs, qa, qb, R_cas, S_cas, R_num, S_num, load_type, skip_eval)
    local R_str, xS_str, S_str
    
    if symbolischer_modus and (qs or qa or qb or R_cas or S_cas) then
        local cache_key = string.format("%s_%s_%s_%s_%s_%s_%s", tostring(L_eff), tostring(qs), tostring(qa), tostring(qb), tostring(R_cas), tostring(S_cas), tostring(load_type))
        if pvv_cas_cache[cache_key] then
            return pvv_cas_cache[cache_key].R, pvv_cas_cache[cache_key].S, pvv_cas_cache[cache_key].xS
        end
        
        local terms_R, terms_S = {}, {}
        if qs or qa or qb then
            qs = qs or "0"; qa = qa or "0"; qb = qb or "0"
            if load_type == "m" then
                table.insert(terms_R, string.format("(%s) * (%s * L)", qs, fN_export(L_eff)))
            elseif load_type == "g" then
                table.insert(terms_R, string.format("(%s) * (%s * L)", qs, fN_export(L_eff)))
                table.insert(terms_S, string.format("(%s) * (%s * L^2)", qs, fN_export(L_eff * L/2)))
            else
                table.insert(terms_R, string.format("((%s) + ((%s) + (%s))/2) * (%s * L)", qs, qa, qb, fN_export(L_eff)))
                table.insert(terms_S, string.format("(3*(%s) + (%s) + 2*(%s)) * (%s * L^2) / 6", qs, qa, qb, fN_export(L_eff^2)))
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

exportArbeitssatzToTI = function()
    if not in_pvv_release or not kinematic_disk_states then
        print("Fehler: Bitte zuerst in den PvV-Modus wechseln!")
        return
    end
    
    local ref_disk = kinematic_seed_info and kinematic_seed_info.disk or nil
    if not ref_disk and kinematic_disk_states then
        for s_idx, state in pairs(kinematic_disk_states) do
            if state.type == "rot" and math.abs(state.phi) > 1e-9 then
                ref_disk = s_idx
                break
            end
        end
        if not ref_disk then
            for s_idx, state in pairs(kinematic_disk_states) do
                if state.type == "trans" and (math.abs(state.ux) > 1e-9 or math.abs(state.uy) > 1e-9) then
                    ref_disk = s_idx
                    break
                end
            end
        end
    end
    
    local eq1_terms = {}
    local eq2_terms = {}
    local fN = fN_export
    local function addTerm(scheibe, d, force_str, is_rot, trans_disp)
        if type(d) ~= "string" and math.abs(d) < 1e-6 and is_rot then return end
        if not is_rot and type(trans_disp) ~= "string" and math.abs(trans_disp) < 1e-6 then return end
        
        if is_rot then
            local k_val = 0
            if ref_disk and kinematic_disk_states[ref_disk].type == "rot" and math.abs(kinematic_disk_states[ref_disk].phi) > 1e-9 then
                k_val = kinematic_disk_states[scheibe].phi / kinematic_disk_states[ref_disk].phi
            end
            local d_str = type(d) == "string" and string.format("(%s)", d) or string.format("(%s)", fN(d))
            local var_name = (scheibe == ref_disk) and "φ_0" or string.format("φ_%d", scheibe)
            table.insert(eq1_terms, string.format("%s * %s * %s", var_name, d_str, force_str))
            table.insert(eq2_terms, string.format("(%s) * %s * %s", fN(k_val), d_str, force_str))
        else
            local var_name = string.format("δ_%d", scheibe)
            table.insert(eq1_terms, string.format("%s * %s", var_name, force_str))
            local k_val = 0
            if ref_disk and kinematic_disk_states[ref_disk].type == "rot" and math.abs(kinematic_disk_states[ref_disk].phi) > 1e-9 then
                local base_k = -1 / kinematic_disk_states[ref_disk].phi
                if type(trans_disp) == "string" then
                    table.insert(eq2_terms, symbolischer_modus and string.format("(%s * L) * (%s) * %s", fN(base_k), trans_disp, force_str) or string.format("(%s) * (%s) * %s", fN(base_k), trans_disp, force_str))
                else
                    k_val = base_k * trans_disp
                    table.insert(eq2_terms, symbolischer_modus and string.format("(%s * L) * %s", fN(k_val), force_str) or string.format("(%s) * %s", fN(k_val), force_str))
                end
            else
                if type(trans_disp) == "string" then
                    table.insert(eq2_terms, symbolischer_modus and string.format("(0.0000 * L) * (%s) * %s", trans_disp, force_str) or string.format("(0.0000) * (%s) * %s", trans_disp, force_str))
                else
                    table.insert(eq2_terms, symbolischer_modus and string.format("(0.0000 * L) * %s", force_str) or string.format("(0.0000) * %s", force_str))
                end
            end
        end
    end

    local function processForce(scheibe, px, py, fx, fy, fm, is_moment_only)
        local d_state = kinematic_disk_states[scheibe]
        if not d_state then return end
        
        if d_state.type == "rot" then
            if fx and (type(fx)=="string" or math.abs(fx) > 0) then
                local d_y = (py - d_state.cy)
                local str_d = symbolischer_modus and string.format("(%s * L)", fN(d_y)) or string.format("(%s)", fN(d_y))
                addTerm(scheibe, str_d, type(fx)=="string" and fx or fN(fx), true)
            end
            if fy and (type(fy)=="string" or math.abs(fy) > 0) then
                local d_x = -(px - d_state.cx)
                local str_d = symbolischer_modus and string.format("(%s * L)", fN(d_x)) or string.format("(%s)", fN(d_x))
                addTerm(scheibe, str_d, type(fy)=="string" and fy or fN(fy), true)
            end
            if fm and (type(fm)=="string" or math.abs(fm) > 0) then
                addTerm(scheibe, 1, type(fm)=="string" and fm or fN(fm), true)
            end
        else
            if fx and (type(fx)=="string" or math.abs(fx) > 0) then
                addTerm(scheibe, 0, type(fx)=="string" and fx or fN(fx), false, d_state.vx)
            end
            if fy and (type(fy)=="string" or math.abs(fy) > 0) then
                addTerm(scheibe, 0, type(fy)=="string" and fy or fN(fy), false, d_state.vy)
            end
        end
    end

    for i, k in ipairs(knoten) do
        local fx, fy, fm = k.last_x or 0, k.last_y or 0, k.last_m or 0
        local fx_pass, fy_pass = fx, fy
        if k.last_w and k.last_w ~= 0 then
            local rad = math.rad(k.last_w)
            local tfx = fx * math.cos(rad) - fy * math.sin(rad)
            local tfy = fx * math.sin(rad) + fy * math.cos(rad)
            
            if zahlenFormat ~= 3 then
                -- Build symbolic CAS strings so the CAS can compute exact trig
                local w_str = fN(k.last_w)
                local parts_x, parts_y = {}, {}
                if math.abs(fx) > 1e-6 then
                    table.insert(parts_x, fN(fx) .. "*cos(" .. w_str .. ")")
                    table.insert(parts_y, fN(fx) .. "*sin(" .. w_str .. ")")
                end
                if math.abs(fy) > 1e-6 then
                    table.insert(parts_x, "(-" .. fN(fy) .. "*sin(" .. w_str .. "))")
                    table.insert(parts_y, fN(fy) .. "*cos(" .. w_str .. ")")
                end
                fx_pass = #parts_x > 0 and "(" .. table.concat(parts_x, "+") .. ")" or 0
                fy_pass = #parts_y > 0 and "(" .. table.concat(parts_y, "+") .. ")" or 0
            else
                fx_pass, fy_pass = tfx, tfy
            end
            fx, fy = tfx, tfy
        end
        if math.abs(fx) > 1e-4 or math.abs(fy) > 1e-4 or math.abs(fm) > 1e-4 then
            local scheibe = nil
            for j, s in ipairs(staebe) do
                if s.k1 == i or s.k2 == i then scheibe = s.scheibe; break end
            end
            if scheibe then processForce(scheibe, k.x, k.y, fx_pass, fy_pass, fm) end
        end
    end

    for i, s in ipairs(staebe) do
        local d_state = kinematic_disk_states[s.scheibe]
        if d_state then
            local k1, k2 = knoten[s.k1], knoten[s.k2]
            local dx, dy = k2.x - k1.x, k2.y - k1.y
            local L = math.sqrt(dx^2 + dy^2)
            if L > 1e-6 then
                local cosA, sinA = dx/L, dy/L
                
                local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                local Rq_num = (qA + qB)/2 * L + (s.R_q_cas or 0)
                local Sq_num = (L^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
                local Rq_str, Sq_str, xSq_str = processDistLoad_PvV(L, L, s.q_str, s.q_A_str, s.q_B_str, s.R_q_cas_str, s.S_q_cas_str, Rq_num, Sq_num, "q")
                if Rq_str then
                    if d_state.type == "rot" then
                        local c_qA = -sinA * (k1.y - d_state.cy) - cosA * (k1.x - d_state.cx)
                        local term1 = symbolischer_modus and string.format("(%s * L)", fN(c_qA)) or string.format("(%s)", fN(c_qA))
                        local d_str = xSq_str and string.format("(%s - (%s))", term1, xSq_str) or term1
                        addTerm(s.scheibe, d_str, Rq_str, true)
                    else
                        addTerm(s.scheibe, 0, Rq_str, false, -sinA * d_state.vx + cosA * d_state.vy)
                    end
                elseif Sq_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, -1, Sq_str, true) end
                end
                
                local nA = s.n + (s.n_A or 0); local nB = s.n + (s.n_B or 0)
                local Rn_num = (nA + nB)/2 * L + (s.R_n_cas or 0)
                local Sn_num = (s.S_n_cas or 0)
                local Rn_str, Sn_str, xSn_str = processDistLoad_PvV(L, L, s.n_str, s.n_A_str, s.n_B_str, s.R_n_cas_str, s.S_n_cas_str, Rn_num, Sn_num, "q")
                if Rn_str then
                    if d_state.type == "rot" then
                        local c_nA = cosA * (k1.y - d_state.cy) - sinA * (k1.x - d_state.cx)
                        addTerm(s.scheibe, fN(c_nA), Rn_str, true)
                    else
                        addTerm(s.scheibe, 0, Rn_str, false, cosA * d_state.vx + sinA * d_state.vy)
                    end
                elseif Sn_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, -1, Sn_str, true) end
                end
                
                local gx_val = s.gx or 0
                local L_eff_gx = s.gx_proj and math.abs(dy) or L
                local Rgx_num = gx_val * L_eff_gx + (s.R_gx_cas or 0)
                local Sgx_num = Rgx_num * (L/2) + (s.S_gx_cas or 0)
                local Rgx_str, Sgx_str, xSgx_str = processDistLoad_PvV(L, L_eff_gx, s.gx_str, nil, nil, s.R_gx_cas_str, s.S_gx_cas_str, Rgx_num, Sgx_num, "g")
                if Rgx_str then
                    if d_state.type == "rot" then
                        local c_gxA = (k1.y - d_state.cy)
                        local term1 = symbolischer_modus and string.format("(%s * L)", fN(c_gxA)) or string.format("(%s)", fN(c_gxA))
                        local d_str = xSgx_str and string.format("(%s + (%s) * %s)", term1, xSgx_str, fN(sinA)) or term1
                        addTerm(s.scheibe, d_str, Rgx_str, true)
                    else
                        addTerm(s.scheibe, 0, Rgx_str, false, d_state.vx)
                    end
                elseif Sgx_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, sinA, Sgx_str, true) end
                end
                
                local gy_val = s.gy or 0
                local L_eff_gy = s.gy_proj and math.abs(dx) or L
                local Rgy_num = gy_val * L_eff_gy + (s.R_gy_cas or 0)
                local Sgy_num = Rgy_num * (L/2) + (s.S_gy_cas or 0)
                local Rgy_str, Sgy_str, xSgy_str = processDistLoad_PvV(L, L_eff_gy, s.gy_str, nil, nil, s.R_gy_cas_str, s.S_gy_cas_str, Rgy_num, Sgy_num, "g")
                if Rgy_str then
                    if d_state.type == "rot" then
                        local c_gyA = -(k1.x - d_state.cx)
                        local term1 = symbolischer_modus and string.format("(%s * L)", fN(c_gyA)) or string.format("(%s)", fN(c_gyA))
                        local d_str = xSgy_str and string.format("(%s - (%s) * %s)", term1, xSgy_str, fN(cosA)) or term1
                        addTerm(s.scheibe, d_str, Rgy_str, true)
                    else
                        addTerm(s.scheibe, 0, Rgy_str, false, d_state.vy)
                    end
                elseif Sgy_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, -cosA, Sgy_str, true) end
                end
                
                local Rm_num = (s.m or 0) * L + (s.R_m_cas or 0)
                local Rm_str = processDistLoad_PvV(L, L, s.m_str, nil, nil, s.R_m_cas_str, nil, Rm_num, 0, "m")
                if Rm_str then
                    if d_state.type == "rot" then addTerm(s.scheibe, 1, Rm_str, true) end
                end
            end
        end
    end

    if pvv_released_binding then
        local b = pvv_released_binding
        if b.type == "lager_x" or b.type == "lager_y" or b.type == "lager_m" then
            local k = knoten[b.node]
            local scheibe = nil
            for j, s in ipairs(staebe) do
                if s.k1 == b.node or s.k2 == b.node then scheibe = s.scheibe; break end
            end
            if scheibe then 
                if b.type == "lager_x" then processForce(scheibe, k.x, k.y, "H", 0, 0)
                elseif b.type == "lager_y" then processForce(scheibe, k.x, k.y, 0, "V", 0)
                elseif b.type == "lager_m" then processForce(scheibe, k.x, k.y, 0, 0, "M_A") end
            end
        elseif b.type == "q_gelenk" or b.type == "n_gelenk" then
            local s = staebe[b.stab]
            local nodeIdx = b.endA and s.k1 or s.k2
            local k_node = knoten[nodeIdx]
            
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
            local L = math.sqrt(dx^2 + dy^2)
            if L > 0 then
                local nx, ny = dx/L, dy/L
                if b.type == "q_gelenk" then nx, ny = -ny, nx end
                local dir = b.endA and -1 or 1
                local ax, ay = nx * dir, ny * dir
                
                local force_var = (b.type == "q_gelenk") and "Q" or "N"
                local fx_str = (math.abs(ax) > 1e-6) and string.format("(%s * %s)", fN(ax), force_var) or nil
                local fy_str = (math.abs(ay) > 1e-6) and string.format("(%s * %s)", fN(ay), force_var) or nil
                
                processForce(s.scheibe, k_node.x, k_node.y, fx_str, fy_str, 0)
                
                local other_scheibe = nil
                for j, s2 in ipairs(staebe) do
                    if j ~= b.stab and (s2.k1 == nodeIdx or s2.k2 == nodeIdx) then other_scheibe = s2.scheibe; break end
                end
                if other_scheibe then
                    local n_fx_str = (math.abs(ax) > 1e-6) and string.format("(%s * %s)", fN(-ax), force_var) or nil
                    local n_fy_str = (math.abs(ay) > 1e-6) and string.format("(%s * %s)", fN(-ay), force_var) or nil
                    processForce(other_scheibe, k_node.x, k_node.y, n_fx_str, n_fy_str, 0)
                end
            end
        elseif b.type == "m_gelenk" then
            local s = staebe[b.stab]
            local nodeIdx = b.endA and s.k1 or s.k2
            local k_node = knoten[nodeIdx]
            
            local force_var = "M"
            local dir = b.endA and 1 or -1
            local fm_str = string.format("(%d * %s)", dir, force_var)
            processForce(s.scheibe, k_node.x, k_node.y, 0, 0, fm_str)
            
            local other_scheibe = nil
            for j, s2 in ipairs(staebe) do
                if j ~= b.stab and (s2.k1 == nodeIdx or s2.k2 == nodeIdx) then other_scheibe = s2.scheibe; break end
            end
            if other_scheibe then
                local n_fm_str = string.format("(%d * %s)", -dir, force_var)
                processForce(other_scheibe, k_node.x, k_node.y, 0, 0, n_fm_str)
            end
        end
    end
    
    local eq1_lhs = #eq1_terms > 0 and table.concat(eq1_terms, " + ") or "0"
    local ref_var = ref_disk and (kinematic_disk_states[ref_disk].type == "rot" and "φ_0" or string.format("δ_%d", ref_disk)) or "φ_0"
    local eq2_lhs = #eq2_terms > 0 and (ref_var .. " * (" .. table.concat(eq2_terms, " + ") .. ")") or "0"
    
    print("eq1_lhs: " .. eq1_lhs)
    print("eq2_lhs: " .. eq2_lhs)
    
    if math.eval then
        local cas_wrap = zahlenFormat == 3 and "approx" or "exact"
        local success1 = pcall(function() math.eval("w_eq1 := " .. cas_wrap .. "(expand(" .. eq1_lhs .. ")) = 0") end)
        local success2 = pcall(function() math.eval("w_eq2 := " .. cas_wrap .. "(expand(" .. eq2_lhs .. ")) = 0") end)
        if success1 and success2 then
            pcall(function() math.eval('Disp "Arbeitssatz in w_eq1 und w_eq2 exportiert!"') end)
            print("-> Arbeitssatz als exakte CAS-Gleichung (w_eq1, w_eq2) exportiert!")
        else
            pcall(function() math.eval('Disp "Fehler beim Export des Arbeitssatzes!"') end)
            print("-> Fehler beim Export des Arbeitssatzes.")
        end
    else
        print("Export erfordert CAS!")
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
        s.n_pts = {}; s.N_cas_pts = {}; s.u_cas_pts_EA = {}
        s.m_pts = {};
        s.gx_pts = {}; s.gy_pts = {}
        
        local L_str = fN(L)
        local eq_q = getEqQ(s, L, fN, L_str)
        local eq_n = getEqN(s, L, fN, L_str)
        local eq_q_num = casWithDummySymbols(eq_q)
        local eq_n_num = casWithDummySymbols(eq_n)
        local has_q = string.find(eq_q, "x")
        local has_n = string.find(eq_n, "x")
        local has_m = s.m_str and string.find(s.m_str, "x")
        local has_gx = string.find(s.gx_str or "", "x")
        local has_gy = string.find(s.gy_str or "", "x")
        
        -- HIER IST DER FIX: Lokale Lasten optisch von globalen entkoppeln
        local pure_q_cas = s.q_str and string.find(s.q_str, "x")
        local pure_n_cas = s.n_str and string.find(s.n_str, "x")
        local pure_m_cas = s.m_str and string.find(s.m_str, "x")
        
        if L > 0 and math.eval and (has_q or has_n or has_m or has_gx or has_gy or pure_q_cas or pure_n_cas or pure_m_cas) then
            local vars_to_del = {}
            
            if has_q then
                local q_t = eq_q_num:gsub("x", "t")
                math.eval("q_temp(x) := " .. eq_q_num)
                math.eval("q_cas_Q(x) := integral("..eq_q_num..",x,0,x)")
                math.eval("q_cas_M(x) := integral(("..q_t..")*(x-t),t,0,x)")
                math.eval("q_cas_vK_EI(x) := integral(("..q_t..")*(x-t)^3,t,0,x)/6")
                s.vK_L_EI = casToNumber(math.eval("approx(q_cas_vK_EI("..fN(L).."))")) or 0
                s.phiK_L_EI = casToNumber(math.eval("approx(integral(("..q_t..")*("..fN(L).."-t)^2,t,0,"..fN(L)..")/2)")) or 0
                table.insert(vars_to_del, "q_temp"); table.insert(vars_to_del, "q_cas_Q"); table.insert(vars_to_del, "q_cas_M"); table.insert(vars_to_del, "q_cas_vK_EI")
            end
            
            if has_n then
                local n_t = eq_n_num:gsub("x", "t")
                math.eval("n_temp(x) := " .. eq_n_num)
                math.eval("n_cas_N(x) := integral("..eq_n_num..",x,0,x)")
                math.eval("n_cas_uK_EA(x) := integral(("..n_t..")*(x-t),t,0,x)")
                s.uK_L_EA = casToNumber(math.eval("approx(n_cas_uK_EA("..fN(L).."))")) or 0
                table.insert(vars_to_del, "n_temp"); table.insert(vars_to_del, "n_cas_N"); table.insert(vars_to_del, "n_cas_uK_EA")
            end
            
            if has_m then
                local m_e = s.m_str
                local m_t = m_e:gsub("x", "t")
                math.eval("m_temp(x) := " .. m_e)
                math.eval("m_cas_M(x) := integral("..m_e..",x,0,x)")
                math.eval("m_cas_vK_EI(x) := -integral(("..m_t..")*(x-t)^2,t,0,x)/2")
                s.vK_L_EI_m = casToNumber(math.eval("approx(m_cas_vK_EI("..fN(L).."))")) or 0
                s.phiK_L_EI_m = casToNumber(math.eval("approx(-integral(("..m_t..")*("..fN(L).."-t),t,0,"..fN(L).."))")) or 0
                table.insert(vars_to_del, "m_temp"); table.insert(vars_to_del, "m_cas_M"); table.insert(vars_to_del, "m_cas_vK_EI")
            end
            
            if pure_q_cas then math.eval("q_pure(x) := " .. s.q_str); table.insert(vars_to_del, "q_pure") end
            if pure_n_cas then math.eval("n_pure(x) := " .. s.n_str); table.insert(vars_to_del, "n_pure") end
            if pure_m_cas then math.eval("m_pure(x) := " .. s.m_str); table.insert(vars_to_del, "m_pure") end
            if has_gx then math.eval("gx_temp(x) := " .. s.gx_str); table.insert(vars_to_del, "gx_temp") end
            if has_gy then math.eval("gy_temp(x) := " .. s.gy_str); table.insert(vars_to_del, "gy_temp") end
            
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

local function drawArrow(gc, x1, y1, x2, y2)
    gc:drawLine(x1, y1, x2, y2); local dx, dy = x2 - x1, y2 - y1; local L = math.sqrt(dx*dx + dy*dy)
    if L > 0 then local ux, uy = dx/L, dy/L; local bx, by = x2 - 6*ux, y2 - 6*uy; gc:fillPolygon({x2, y2, bx + 2*-uy, by + 2*ux, bx - 2*-uy, by - 2*ux}) end
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
    local use_q_cas = (stab.q_str and string.find(stab.q_str, "x"))
    local use_n_cas = (stab.n_str and string.find(stab.n_str, "x"))
    local use_m_cas = (stab.m_str and string.find(stab.m_str, "x"))
    
    local eff_gx = (stab.gx or 0) * (stab.gx_proj and math.abs(s_val) or 1)
    local eff_gy = (stab.gy or 0) * (stab.gy_proj and math.abs(c_val) or 1)
    local n_add = eff_gx * c_val - eff_gy * s_val
    local q_add = eff_gx * s_val + eff_gy * c_val
    
    local p_i = stab.q_A + (not use_q_cas and (stab.q + q_add) or 0)
    local p_k = stab.q_B + (not use_q_cas and (stab.q + q_add) or 0)
    local ax_i = stab.n_A + (not use_n_cas and (stab.n + n_add) or 0)
    local ax_k = stab.n_B + (not use_n_cas and (stab.n + n_add) or 0)
    
    local N_i = -((2 * ax_i + ax_k) / 6) * L; local N_k = -((ax_i + 2 * ax_k) / 6) * L      
    local Q_i = -(L / 60) * (21 * p_i + 9 * p_k); local Q_k = -(L / 60) * (9 * p_i + 21 * p_k) 
    local M_i = (L^2 / 60) * (3 * p_i + 2 * p_k) - (not use_m_cas and (stab.m * L) / 2 or 0)
    local M_k = -(L^2 / 60) * (2 * p_i + 3 * p_k) - (not use_m_cas and (stab.m * L) / 2 or 0)
    
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
    
    if stab.h > 0 then local N_t, M_t = stab.EA * stab.alpha * ((stab.To+stab.Tu)/2), stab.EI * stab.alpha * ((stab.Tu-stab.To)/stab.h); N_i = N_i + N_t; N_k = N_k - N_t; M_i = M_i + M_t; M_k = M_k - M_t end
    
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
    local EA_L, EI12, EI6, EI4, EI2 = stab.EA/L, (12*stab.EI)/(L^3), (6*stab.EI)/(L^2), (4*stab.EI)/L, (2*stab.EI)/L
    local k_loc = { {EA_L,0,0,-EA_L,0,0}, {0,EI12,-EI6,0,-EI12,-EI6}, {0,-EI6,EI4,0,EI6,EI2}, {-EA_L,0,0,EA_L,0,0}, {0,-EI12,EI6,0,EI12,EI6}, {0,-EI6,EI2,0,EI6,EI4} }
    if stab.n_gelenk_A or stab.n_gelenk_B then k_loc[1][1]=0; k_loc[1][4]=0; k_loc[4][1]=0; k_loc[4][4]=0 end
    if stab.q_gelenk_A or stab.q_gelenk_B then for i=1,6 do k_loc[2][i]=0; k_loc[5][i]=0; k_loc[i][2]=0; k_loc[i][5]=0 end; k_loc[3][3]=stab.EI/L; k_loc[3][6]=-stab.EI/L; k_loc[6][3]=-stab.EI/L; k_loc[6][6]=stab.EI/L end
    local c, s = dx/L, -dy/L; local T = { {c,-s,0,0,0,0}, {s,c,0,0,0,0}, {0,0,1,0,0,0}, {0,0,0,c,-s,0}, {0,0,0,s,c,0}, {0,0,0,0,0,1} }
    local TK = buildKnotenTransform(stab)
    return matMult(matMult(TK, matMult(matMult(matTrans(T), k_loc), T)), matTrans(TK)), k_loc
end

local function baueLastvektor()
    local F = {}; for i = 1, anzahlGleichungen do F[i] = 0 end
    for i, k in ipairs(knoten) do
        local rad_last, rad_lager = math.rad(-(k.last_w or 0)), math.rad(k.winkel or 0)
        local cl, sl, c, s = math.cos(rad_last), math.sin(rad_last), math.cos(rad_lager), math.sin(rad_lager)
        local f_xi = (k.last_x*cl - k.last_y*sl)*c + (k.last_x*sl + k.last_y*cl)*s; local f_eta = -(k.last_x*cl - k.last_y*sl)*s + (k.last_x*sl + k.last_y*cl)*c
        if k.eq_x > 0 then F[k.eq_x] = F[k.eq_x] + f_xi end; if k.eq_y > 0 then F[k.eq_y] = F[k.eq_y] + f_eta end
        if type(k.eq_m) == "number" and k.eq_m > 0 then F[k.eq_m] = F[k.eq_m] + k.last_m end
    end
    for i, s in ipairs(staebe) do
        if not s.is_cut then
            local id, p_global = stabID[i], berechneElementLastvektor(s)
            if p_global then for j = 1, 6 do if id[j] > 0 then F[id[j]] = F[id[j]] - p_global[j][1] end end end
            if s.gelenk_A and s.x_mA ~= 0 then if id[3] > 0 then F[id[3]] = F[id[3]] + s.x_mA end; if type(knoten[s.k1].eq_m)=="number" and knoten[s.k1].eq_m>0 then F[knoten[s.k1].eq_m] = F[knoten[s.k1].eq_m] - s.x_mA end end
            if s.gelenk_B and s.x_mB ~= 0 then if id[6] > 0 then F[id[6]] = F[id[6]] + s.x_mB end; if type(knoten[s.k2].eq_m)=="number" and knoten[s.k2].eq_m>0 then F[knoten[s.k2].eq_m] = F[knoten[s.k2].eq_m] - s.x_mB end end
        end
        if (s.x_nA or 0) ~= 0 then
            local dx, dy = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y; local L = math.sqrt(dx^2+dy^2)
            if L > 0 then
                local ux, uy = dx/L, dy/L
                if knoten[s.k1].eq_x > 0 then F[knoten[s.k1].eq_x] = F[knoten[s.k1].eq_x] + s.x_nA * ux end
                if knoten[s.k1].eq_y > 0 then F[knoten[s.k1].eq_y] = F[knoten[s.k1].eq_y] + s.x_nA * uy end
                if knoten[s.k2].eq_x > 0 then F[knoten[s.k2].eq_x] = F[knoten[s.k2].eq_x] - s.x_nA * ux end
                if knoten[s.k2].eq_y > 0 then F[knoten[s.k2].eq_y] = F[knoten[s.k2].eq_y] - s.x_nA * uy end
            end
        end
    end
    return F
end

local cached_factored_K = nil

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
        local u = solveFactoredLGS(cached_factored_K, F)
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
            local r = math.rad(k.f_winkel or 0); local c, s = math.cos(r), math.sin(r)
            local k_glob = matMult(matMult({{c,-s,0},{s,c,0},{0,0,1}}, {{k.cx,0,0},{0,k.cy,0},{0,0,k.cm}}), {{c,s,0},{-s,c,0},{0,0,1}})
            local eqs = {k.eq_x, k.eq_y, type(k.eq_m)=="number" and k.eq_m or 0}
            for row=1,3 do for col=1,3 do if eqs[row]>0 and eqs[col]>0 then K[eqs[row]][eqs[col]] = K[eqs[row]][eqs[col]] + k_glob[row][col] end end end
        end
    end
    if return_kinematic_mode then
        for i = 1, anzahlGleichungen do K[i][i] = K[i][i] + 1.0 end
    end
    
    local fact = factorLGS(K)
    if checkKinematicsOnly and not return_kinematic_mode then return fact ~= nil, stabID end
    
    if not checkKinematicsOnly and not return_kinematic_mode then cached_factored_K = fact end
    
    glob_K = K; glob_F = F; 
    if not fact then return nil, stabID end
    local u = solveFactoredLGS(fact, F)
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
                local EA_L = stab.EA / L; local EI12 = 12*stab.EI/L^3
                
                local true_v_l = {v_l[1][1], v_l[2][1], v_l[3][1], v_l[4][1], v_l[5][1], v_l[6][1]}
                if stab.n_gelenk_A and not stab.n_gelenk_B then true_v_l[1] = true_v_l[4] - N_i_o / EA_L
                elseif stab.n_gelenk_B and not stab.n_gelenk_A then true_v_l[4] = true_v_l[1] + N_k_o / EA_L
                elseif stab.n_gelenk_A and stab.n_gelenk_B then true_v_l[1] = true_v_l[4] end
                if stab.q_gelenk_A and not stab.q_gelenk_B then true_v_l[2] = true_v_l[5] + (L/2)*true_v_l[3] + (L/2)*true_v_l[6] - Q_i_o / EI12
                elseif stab.q_gelenk_B and not stab.q_gelenk_A then true_v_l[5] = true_v_l[2] - (L/2)*true_v_l[3] - (L/2)*true_v_l[6] - Q_k_o / EI12
                elseif stab.q_gelenk_A and stab.q_gelenk_B then true_v_l[2] = true_v_l[5] end
                
                local EI6 = 6*stab.EI/L^2; local EI4 = 4*stab.EI/L; local EI2 = 2*stab.EI/L
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
                for j = 1, 6 do stab.s_local[j] = s_orig[j][1] + p_orig[j][1]; stab.v_local[j] = true_v_l[j] end
                
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
    if s.q_str and s.q_str:find("x") then return false end
    if s.n_str and s.n_str:find("x") then return false end
    if s.m_str and s.m_str:find("x") then return false end
    if s.gx_str and s.gx_str:find("x") then return false end
    if s.gy_str and s.gy_str:find("x") then return false end
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
        s.orig_is_cut = s.is_cut; s.orig_x_nA = s.x_nA
    end
end

applyKGVZustand = function(lf)
    if lf == -1 then
        for i, k in ipairs(knoten) do if k.orig_lager_x~=nil then k.lager_x=k.orig_lager_x; k.lager_y=k.orig_lager_y; k.lager_m=k.orig_lager_m; k.last_x=k.orig_last_x; k.last_y=k.orig_last_y; k.last_m=k.orig_last_m; k.last_w=k.orig_last_w end end
        for i, s in ipairs(staebe) do if s.orig_gelenk_A~=nil then s.gelenk_A=s.orig_gelenk_A; s.gelenk_B=s.orig_gelenk_B; s.n_gelenk_A=s.orig_n_gelenk_A; s.q=s.orig_q; s.n=s.orig_n; s.m=s.orig_m; s.q_A=s.orig_q_A; s.q_B=s.orig_q_B; s.n_A=s.orig_n_A; s.n_B=s.orig_n_B; s.gx=s.orig_gx; s.gy=s.orig_gy; s.To=s.orig_To; s.Tu=s.orig_Tu; s.x_mA=0; s.x_mB=0; s.q_str=s.orig_q_str; s.n_str=s.orig_n_str; s.m_str=s.orig_m_str; s.gx_str=s.orig_gx_str; s.gy_str=s.orig_gy_str; s.is_cut=s.orig_is_cut; s.x_nA=s.orig_x_nA end end
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
        for i, s in ipairs(staebe) do s.q=s.orig_q; s.n=s.orig_n; s.m=s.orig_m; s.q_A=s.orig_q_A; s.q_B=s.orig_q_B; s.n_A=s.orig_n_A; s.n_B=s.orig_n_B; s.gx=s.orig_gx; s.gy=s.orig_gy; s.To=s.orig_To; s.Tu=s.orig_Tu; s.q_str=s.orig_q_str; s.n_str=s.orig_n_str; s.m_str=s.orig_m_str; s.gx_str=s.orig_gx_str; s.gy_str=s.orig_gy_str end
    else
        for i, k in ipairs(knoten) do k.last_x=0; k.last_y=0; k.last_m=0; k.last_w=0 end
        for i, s in ipairs(staebe) do s.q=0; s.n=0; s.m=0; s.q_A=0; s.q_B=0; s.n_A=0; s.n_B=0; s.gx=0; s.gy=0; s.To=0; s.Tu=0; s.q_str="0"; s.n_str="0"; s.m_str="0"; s.gx_str="0"; s.gy_str="0" end
        local x = X_Werte[lf]; if x.typ == "lager_x" then local rad = math.rad(knoten[x.knoten].winkel or 0); knoten[x.knoten].last_x = math.cos(rad); knoten[x.knoten].last_y = math.sin(rad) elseif x.typ == "lager_y" then local rad = math.rad(knoten[x.knoten].winkel or 0); knoten[x.knoten].last_x = -math.sin(rad); knoten[x.knoten].last_y = math.cos(rad) elseif x.typ == "lager_m" then knoten[x.knoten].last_m = 1 elseif x.typ == "gelenk_A" then staebe[x.stab].x_mA = 1 elseif x.typ == "gelenk_B" then staebe[x.stab].x_mB = 1 elseif x.typ == "pendel_n" then staebe[x.stab].x_nA = 1 end
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

local function injectVirtualArcs()
    local orig_num_staebe = #staebe
    for i=1, orig_num_staebe do
        local s = staebe[i]
        local k1 = knoten[s.k1]
        local k2 = knoten[s.k2]
        local dx, dy = k2.x - k1.x, k2.y - k1.y
        local L_true = math.sqrt(dx^2 + dy^2)
        if (s.bogen_r or 0) ~= 0 and math.abs(s.bogen_r) >= L_true/2 and L_true > 0 then
            s.is_virtual_parent = true
            s.virt_start_stab = #staebe + 1
            local R = math.abs(s.bogen_r)
            local sgn = s.bogen_r > 0 and -1 or 1
            local d = math.sqrt(R^2 - (L_true/2)^2)
            local segments = bogenSegmente
            local prev_node_idx = s.k1
            for j=1, segments-1 do
                local t = j/segments
                local nx, ny
                if j == 1 then
                    local slope = sgn * (L_true/2) / d
                    local tx = dx/L_true - slope * (dy/L_true)
                    local ty = dy/L_true + slope * (dx/L_true)
                    local len = math.sqrt(tx^2 + ty^2)
                    local L_arc = R * 2 * math.asin(L_true / (2*R))
                    local seg_len = L_arc / segments
                    nx = k1.x + (seg_len) * (tx/len)
                    ny = k1.y + (seg_len) * (ty/len)
                elseif j == segments - 1 then
                    local slope = -sgn * (L_true/2) / d
                    local tx = dx/L_true - slope * (dy/L_true)
                    local ty = dy/L_true + slope * (dx/L_true)
                    local len = math.sqrt(tx^2 + ty^2)
                    local L_arc = R * 2 * math.asin(L_true / (2*R))
                    local seg_len = L_arc / segments
                    nx = k2.x - (seg_len) * (tx/len)
                    ny = k2.y - (seg_len) * (ty/len)
                else
                    local x_local = (t - 0.5) * L_true
                    local y_local = sgn * (math.sqrt(R^2 - x_local^2) - d)
                    nx = k1.x + t * dx - y_local * (dy/L_true)
                    ny = k1.y + t * dy + y_local * (dx/L_true)
                end
                table.insert(knoten, {x = nx, y = ny, gelenk=false, is_virtual = true, 
                                      lager_x = false, lager_y = false, lager_m = false, 
                                      last_x=0, last_y=0, last_m=0, last_w=0,
                                      cx=0, cy=0, cm=0, f_winkel=0})
                local new_node_idx = #knoten
                local v_stab = erstelleStab(prev_node_idx, new_node_idx)
                v_stab.EA = s.EA; v_stab.EI = s.EI
                v_stab.is_virtual = true; v_stab.parent_idx = i
                if j == 1 then 
                    v_stab.gelenk_A = s.gelenk_A 
                    v_stab.n_gelenk_A = s.n_gelenk_A
                    v_stab.q_gelenk_A = s.q_gelenk_A
                end
                table.insert(staebe, v_stab)
                prev_node_idx = new_node_idx
            end
            local v_stab_last = erstelleStab(prev_node_idx, s.k2)
            v_stab_last.EA = s.EA; v_stab_last.EI = s.EI
            v_stab_last.is_virtual = true; v_stab_last.parent_idx = i
            v_stab_last.gelenk_B = s.gelenk_B
            v_stab_last.n_gelenk_B = s.n_gelenk_B
            v_stab_last.q_gelenk_B = s.q_gelenk_B
            table.insert(staebe, v_stab_last)
        end
    end
end

local function cleanupVirtualArcs()
    for i, s in ipairs(staebe) do
        if s.is_virtual_parent then
            local virt1 = staebe[s.virt_start_stab]
            local virt_last = staebe[s.virt_start_stab + (bogenSegmente - 1)]
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
            
            s.arc_plot_data = {}
            for v = 0, bogenSegmente - 1 do
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
                        M2 = virt.s_local[6],
                    })
                end
            end
            
            s.is_virtual_parent = nil
            s.virt_start_stab = nil
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
                if s.EA < 1e7 or s.EI < 1e7 then
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

    local L_sym = "L"
    for var, _ in pairs(sym_vars) do
        local used_in_geom = false
        for _, k in ipairs(knoten) do
            if (k.x_str and k.x_str:find("%f[%a]" .. var .. "%f[%A]")) or (k.y_str and k.y_str:find("%f[%a]" .. var .. "%f[%A]")) then used_in_geom = true; break end
        end
        if used_in_geom then L_sym = var; break end
    end
    local L_dummy = sym_vars[L_sym] or 1.0

    for _, s in ipairs(staebe) do
        s.symb_start = {N = "0", V = "0", M = "0", c1 = "0", c2 = "0", vb = "0", phib = "0"}
    end

    local function numToSymFrac(val)
        if math.abs(val) < 1e-10 then return "0" end
        local frac = floatToFrac_lua(val, 1e-5, 10000)
        if frac then return "(" .. frac .. ")" end
        return string.format("(%.10g)", val)
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
            
            local c1_out = -s.v_local[2] * s.EI; local c2_out = -s.v_local[3] * s.EI
            local vb_out = s.v_local[5] * s.EI; local phib_out = -s.v_local[6] * s.EI
            
            if math.abs(c1_out) > 1e-6 then s.symb_start.c1 = s.symb_start.c1 .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(c1_out / (input_dummy * L_dummy^pow_v)), input_str, L_sym, pow_v) end
            if math.abs(c2_out) > 1e-6 then s.symb_start.c2 = s.symb_start.c2 .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(c2_out / (input_dummy * L_dummy^pow_phi)), input_str, L_sym, pow_phi) end
            if math.abs(vb_out) > 1e-6 then s.symb_start.vb = s.symb_start.vb .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(vb_out / (input_dummy * L_dummy^pow_v)), input_str, L_sym, pow_v) end
            if math.abs(phib_out) > 1e-6 then s.symb_start.phib = s.symb_start.phib .. string.format(" + %s*(%s)*(%s)^%d", numToSymFrac(phib_out / (input_dummy * L_dummy^pow_phi)), input_str, L_sym, pow_phi) end
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
    end

    for i, k in ipairs(knoten) do k.last_x, k.last_y, k.last_m = backup_loads.knoten[i].last_x, backup_loads.knoten[i].last_y, backup_loads.knoten[i].last_m end
    for i, s in ipairs(staebe) do
        local orig = backup_loads.staebe[i]
        s.q, s.n, s.m = orig.q, orig.n, orig.m
        s.q_A, s.q_B, s.n_A, s.n_B = orig.q_A, orig.q_B, orig.n_A, orig.n_B
        s.gx, s.gy, s.To, s.Tu = orig.gx, orig.gy, orig.To, orig.Tu
    end
end

local function checkSymbolischerModus()
    symbolischer_modus = false
    sym_vars = {}
    local function checkStr(str)
        if not str then return nil end
        local val, _ = evalInput(str, true)
        return val
    end
    local rm = checkStr(rasterMass_str); if rm then rasterMass = rm end
    for _, k in ipairs(knoten) do
        local vx = checkStr(k.x_str); if vx then k.x = vx end
        local vy = checkStr(k.y_str); if vy then k.y = vy end
        local vlx = checkStr(k.last_x_str); if vlx then k.last_x = vlx end
        local vly = checkStr(k.last_y_str); if vly then k.last_y = vly end
        local vlm = checkStr(k.last_m_str); if vlm then k.last_m = vlm end
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
    end
end

local function clearOldCASVars()
    if not math.eval then return end
    local vars = {}
    for i = 1, 30 do
        table.insert(vars, "N_bogen"..i); table.insert(vars, "q_bogen"..i)
        table.insert(vars, "N_stab"..i); table.insert(vars, "Q_stab"..i); table.insert(vars, "M_stab"..i)
        table.insert(vars, "w_stab"..i); table.insert(vars, "u_stab"..i)
        table.insert(vars, "x_stab"..i); table.insert(vars, "y_stab"..i)
        table.insert(vars, "knot"..i.."_pv")
    end
    table.insert(vars, "sys_k"); table.insert(vars, "sys_f"); table.insert(vars, "sys_u")
    math.eval("DelVar " .. table.concat(vars, ", "))
end

local function starteBerechnung()
    clearOldCASVars()
    warnungKinematisch = false; warnungStarrBestimmt = false; kgv_n = nil; print("Starte Systemanalyse...")
    checkSymbolischerModus()
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

function exportLGSMatrixToTI(only_build)
    local eq_strings = {}
    local x_labels = {}
    local A = {}
    local b = {}
    
    local function addVar(name)
        table.insert(x_labels, {name})
        return #x_labels
    end
    
    if fachwerkModus then
        -- Fachwerk LGS
        local vars_S = {}
        for j = 1, #staebe do vars_S[j] = addVar("S_"..j) end
        local vars_H = {}
        local vars_V = {}
        for i, k in ipairs(knoten) do
            if k.lager_x then vars_H[i] = addVar(getSuppLetter(i).."_h") end
            if k.lager_y then vars_V[i] = addVar(getSuppLetter(i).."_v") end
        end
        
        for i, k in ipairs(knoten) do
            local row_x = {}; local row_y = {}
            for c = 1, #x_labels do row_x[c] = 0; row_y[c] = 0 end
            
            for j, s in ipairs(staebe) do
                if s.k1 == i or s.k2 == i then
                    local dx = knoten[s.k2].x - knoten[s.k1].x
                    local dy = knoten[s.k2].y - knoten[s.k1].y
                    local L = math.sqrt(dx*dx + dy*dy)
                    if L > 0 then
                        local sign = (s.k2 == i) and -1 or 1
                        row_x[vars_S[j]] = formatLabel(sign * dx/L)
                        row_y[vars_S[j]] = formatLabel(sign * dy/L)
                    end
                end
            end
            
            if vars_H[i] then row_x[vars_H[i]] = 1 end
            if vars_V[i] then row_y[vars_V[i]] = -1 end
            
            local b_x = -(k.last_x or 0)
            local b_y = -(k.last_y or 0)
            table.insert(b, {formatLabel(b_x)})
            table.insert(b, {formatLabel(b_y)})
            table.insert(A, row_x)
            table.insert(A, row_y)
            table.insert(eq_strings, {"→ K"..i})
            table.insert(eq_strings, {"↑ K"..i})
        end
    else
        -- Teilsystem LGS (nutzt globale Zuordnung)
        if not glob_ts_scheibe or not glob_disk_centers then assignTeilsysteme() end
        local ts_scheibe = glob_ts_scheibe
        local num_disks = glob_num_disks
        
        local vars_H = {}; local vars_V = {}; local vars_M = {}
        for i, k in ipairs(knoten) do
            if k.lager_x then vars_H[i] = addVar(getSuppLetter(i).."_h") end
            if k.lager_y then vars_V[i] = addVar(getSuppLetter(i).."_v") end
            if k.lager_m then vars_M[i] = addVar("M_"..getSuppLetter(i)) end
        end
        
        local hinge_vars = {}
        for i, k in ipairs(knoten) do
            local hasHinge = k.gelenk
            local conn_rods = {}
            if not hasHinge then
                for j, s in ipairs(staebe) do
                    if (s.k1 == i and (s.n_gelenk_A or s.q_gelenk_A or s.gelenk_A)) or
                       (s.k2 == i and (s.n_gelenk_B or s.q_gelenk_B or s.gelenk_B)) then
                        hasHinge = true
                    end
                    if s.k1 == i or s.k2 == i then table.insert(conn_rods, j) end
                end
            else
                for j, s in ipairs(staebe) do
                    if s.k1 == i or s.k2 == i then table.insert(conn_rods, j) end
                end
            end
            
            if hasHinge then
                hinge_vars[i] = { rods = conn_rods }
                
                local ang_count, rigid_count = 0, 0
                if k.gelenk then
                    ang_count = #conn_rods
                else
                    for _, j in ipairs(conn_rods) do
                        local s = staebe[j]
                        if (s.k1 == i and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A)) or
                           (s.k2 == i and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B)) then
                            ang_count = ang_count + 1
                        else
                            rigid_count = rigid_count + 1
                        end
                    end
                end
                local numTS = ang_count + (rigid_count > 0 and 1 or 0)
                
                if numTS > 2 then
                    hinge_vars[i].multi = true
                    for _, j in ipairs(conn_rods) do
                        hinge_vars[i][j] = {
                            H = addVar("Gx_"..getHingeNumber(i).."s"..ts_scheibe[j]),
                            V = addVar("Gy_"..getHingeNumber(i).."s"..ts_scheibe[j])
                        }
                    end
                else
                    hinge_vars[i].multi = false
                    hinge_vars[i].single = {
                        H = addVar("Gx_"..getHingeNumber(i)),
                        V = addVar("Gy_"..getHingeNumber(i))
                    }
                    
                    local r1, r2
                    if k.gelenk then
                        r1 = conn_rods[1]
                        r2 = conn_rods[2]
                    else
                        for _, j in ipairs(conn_rods) do
                            local s = staebe[j]
                            if (s.k1 == i and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A)) or
                               (s.k2 == i and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B)) then
                                r1 = j
                            else
                                r2 = j
                            end
                        end
                    end
                    hinge_vars[i].r1 = r1
                    hinge_vars[i].r2 = r2
                end
            end
        end
        
        local disk_centers = glob_disk_centers
        
        local rows_per_disk = {}
        for d = 1, num_disks do
            local rx = {}; local ry = {}; local rm = {}
            for c = 1, #x_labels do rx[c]=0; ry[c]=0; rm[c]=0 end
            rows_per_disk[d] = {rx=rx, ry=ry, rm=rm, bx=0, by=0, bm=0}
        end
        
        local function addForceToDisk(d, x, y, H, V, M)
            if not d or d < 1 or d > num_disks then return end
            local row = rows_per_disk[d]
            row.bx = row.bx - H
            row.by = row.by - V
            row.bm = row.bm - M
            local cx, cy = disk_centers[d].x, disk_centers[d].y
            row.bm = row.bm - ((x - cx) * V - (y - cy) * H)
        end

        local function addVarForceToDisk(d, x, y, varH, varV, varM, sign)
            if not d or d < 1 or d > num_disks then return end
            local row = rows_per_disk[d]
            if varH then
                row.rx[varH] = row.rx[varH] + sign * 1
                local cx, cy = disk_centers[d].x, disk_centers[d].y
                row.rm[varH] = row.rm[varH] - sign * (y - cy)
            end
            if varV then
                row.ry[varV] = row.ry[varV] + sign * 1
                local cx, cy = disk_centers[d].x, disk_centers[d].y
                row.rm[varV] = row.rm[varV] + sign * (x - cx)
            end
            if varM then
                row.rm[varM] = row.rm[varM] + sign * 1
            end
        end
        
        for i, k in ipairs(knoten) do
            local assigned_disk = nil
            for j, s in ipairs(staebe) do
                if s.k1 == i or s.k2 == i then assigned_disk = ts_scheibe[j]; break end
            end
            if assigned_disk then
                if vars_H[i] then addVarForceToDisk(assigned_disk, k.x, k.y, vars_H[i], nil, nil, 1) end
                if vars_V[i] then addVarForceToDisk(assigned_disk, k.x, k.y, nil, vars_V[i], nil, -1) end
                if vars_M[i] then addVarForceToDisk(assigned_disk, k.x, k.y, nil, nil, vars_M[i], -1) end
                addForceToDisk(assigned_disk, k.x, k.y, k.last_x or 0, k.last_y or 0, k.last_m or 0)
            end
        end
        
        for j, s in ipairs(staebe) do
            local d = ts_scheibe[j]
            if d then
                local k1, k2 = knoten[s.k1], knoten[s.k2]
                local dx, dy = k2.x - k1.x, k2.y - k1.y
                local L = math.sqrt(dx*dx + dy*dy)
                if L > 1e-6 then
                    local qA_v = s.q + (s.q_A or 0); local qB_v = s.q + (s.q_B or 0)
                    local Rq = (qA_v + qB_v)/2 * L + (s.R_q_cas or 0)
                    local Sq = (L^2)/6 * (qA_v + 2*qB_v) + (s.S_q_cas or 0)
                    if math.abs(Rq) > 1e-6 then
                        local xs = Sq/Rq
                        local px = k1.x + dx * (xs/L); local py = k1.y + dy * (xs/L)
                        local nx, ny = -dy/L, dx/L
                        addForceToDisk(d, px, py, Rq*nx, Rq*ny, 0)
                    end
                    
                    local nA_v = s.n + (s.n_A or 0); local nB_v = s.n + (s.n_B or 0)
                    local Rn = (nA_v + nB_v)/2 * L + (s.R_n_cas or 0)
                    local Sn = (s.S_n_cas or 0)
                    if math.abs(Rn) > 1e-6 then
                        local xs = Sn/Rn
                        local px = k1.x + dx * (xs/L); local py = k1.y + dy * (xs/L)
                        local ux, uy = dx/L, dy/L
                        addForceToDisk(d, px, py, Rn*ux, Rn*uy, 0)
                    end
                    
                    local gx_val = s.gx or 0
                    local L_eff_gx = s.gx_proj and math.abs(dy) or L
                    local Rgx = gx_val * L_eff_gx + (s.R_gx_cas or 0)
                    local Sgx = Rgx * (L/2) + (s.S_gx_cas or 0)
                    if math.abs(Rgx) > 1e-6 then
                        local xs = Sgx/Rgx
                        local px = k1.x + dx * (xs/L); local py = k1.y + dy * (xs/L)
                        addForceToDisk(d, px, py, Rgx, 0, 0)
                    end
                    
                    local gy_val = s.gy or 0
                    local L_eff_gy = s.gy_proj and math.abs(dx) or L
                    local Rgy = gy_val * L_eff_gy + (s.R_gy_cas or 0)
                    local Sgy = Rgy * (L/2) + (s.S_gy_cas or 0)
                    if math.abs(Rgy) > 1e-6 then
                        local xs = Sgy/Rgy
                        local px = k1.x + dx * (xs/L); local py = k1.y + dy * (xs/L)
                        addForceToDisk(d, px, py, 0, Rgy, 0)
                    end
                    
                    local Rm = (s.m or 0) * L + (s.R_m_cas or 0)
                    if math.abs(Rm) > 1e-6 then
                        addForceToDisk(d, (k1.x+k2.x)/2, (k1.y+k2.y)/2, 0, 0, Rm)
                    end
                end
            end
        end
        
        local node_eqs = {}
        for i, k in ipairs(knoten) do
            if hinge_vars[i] then
                local hv = hinge_vars[i]
                if hv.multi then
                    local n_rx = {}; local n_ry = {}
                    for c = 1, #x_labels do n_rx[c]=0; n_ry[c]=0 end
                    for _, j in ipairs(hv.rods) do
                        local s = staebe[j]
                        local h_sign = (s.k1 == i) and -1 or 1
                        addVarForceToDisk(ts_scheibe[j], k.x, k.y, hv[j].H, hv[j].V, nil, h_sign)
                        n_rx[hv[j].H] = -h_sign
                        n_ry[hv[j].V] = -h_sign
                    end
                    table.insert(node_eqs, {rx=n_rx, ry=n_ry, bx=0, by=0, name="G"..i})
                else
                    local r1 = hv.r1
                    local r2 = hv.r2
                    if r1 and r2 then
                        local sign1 = (staebe[r1].k1 == i) and -1 or 1
                        local sign2 = (staebe[r2].k1 == i) and -1 or 1
                        if sign1 == sign2 then sign2 = -sign1 end
                        addVarForceToDisk(ts_scheibe[r1], k.x, k.y, hv.single.H, hv.single.V, nil, sign1)
                        addVarForceToDisk(ts_scheibe[r2], k.x, k.y, hv.single.H, hv.single.V, nil, sign2)
                    end
                end
            end
        end
        
        for d = 1, num_disks do
            table.insert(A, rows_per_disk[d].rx)
            table.insert(A, rows_per_disk[d].ry)
            table.insert(A, rows_per_disk[d].rm)
            table.insert(b, {rows_per_disk[d].bx})
            table.insert(b, {rows_per_disk[d].by})
            table.insert(b, {rows_per_disk[d].bm})
            table.insert(eq_strings, {"→ TS "..d})
            table.insert(eq_strings, {"↑ TS "..d})
            local c = glob_disk_centers and glob_disk_centers[d]
            if c and c.node_id then
                table.insert(eq_strings, {"ΣM P"..c.node_id})
            else
                table.insert(eq_strings, {"ΣM TS "..d})
            end
        end
        for _, ne in ipairs(node_eqs) do
            table.insert(A, ne.rx)
            table.insert(A, ne.ry)
            table.insert(b, {ne.bx})
            table.insert(b, {ne.by})
            table.insert(eq_strings, {"→ "..ne.name})
            table.insert(eq_strings, {"↑ "..ne.name})
        end
    end
    
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
                
                pcall(function() math.eval('Disp "LGS exportiert: ggw_a, ggw_b, ggw_x, lgs"') end)
                if #A ~= #x_labels then
                    pcall(function() math.eval('Disp "WARNUNG: LGS nicht quadratisch!"') end)
                    pcall(function() math.eval('Disp "' .. #A .. ' Gleichungen, ' .. #x_labels .. ' Unbekannte."') end)
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
            local s = staebe[hoverObj]; local temp = s.k1; s.k1 = s.k2; s.k2 = temp; local temp_q = s.q_A; s.q_A = s.q_B; s.q_B = temp_q; local temp_n = s.n_A; s.n_A = s.n_B; s.n_B = temp_n; platform.window:invalidate()
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
        if menuSeite == 1 then return 6 elseif menuSeite == 2 then return 7 elseif menuSeite == 3 then return 4 elseif menuSeite == 4 then return 8 else return 6 end
    elseif menuTyp == "stab" then
        if menuSeite == 1 then return 6 elseif menuSeite == 2 then return 4 elseif menuSeite == 3 then return 8 elseif menuSeite == 6 then return 6 elseif menuSeite == 7 then return 7 else return 6 end
    elseif menuTyp == "obermenue" then
        if menuSeite == 1 then return 8 elseif menuSeite == 2 then return 7 elseif menuSeite == 3 then return 8 elseif menuSeite == 4 then return 2 else return 3 end
    elseif menuTyp == "pvv_knoten" then
        return 4
    elseif menuTyp == "pvv_stab" then
        return 6
    end
    return 1
end

function on.enterKey()
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
                if eingabeModus then local z, s_val = evalFederInput(eingabeText, k, true); if z then if menuZeile==1 then k.cx=z; sys_changed = true; k.cx_str=s_val end; if menuZeile==2 then k.cy=z; sys_changed = true; k.cy_str=s_val end; if menuZeile==3 then k.cm=z; sys_changed = true; k.cm_str=s_val end; if menuZeile==4 then k.f_winkel=z; sys_changed = true end end; eingabeModus = false else eingabeModus, eingabeText = true, "" end
            elseif menuSeite == 4 then if menuZeile == 4 then exportKnotenToTI(menuIndex); menuOffen = false; platform.window:invalidate(); return end end
        elseif menuTyp == "stab" then
            local s = staebe[menuIndex]
            if menuSeite == 5 or menuSeite == 6 or (menuSeite == 7 and menuZeile ~= 7) then return end
            if menuSeite == 2 then if menuZeile == 2 then s.gx_proj = not s.gx_proj; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 4 then s.gy_proj = not s.gy_proj; sys_changed = true; platform.window:invalidate(); return end
            elseif menuSeite == 4 then
                if menuZeile == 1 then s.gelenk_A = not s.gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 2 then s.gelenk_B = not s.gelenk_B; sys_changed = true; platform.window:invalidate(); return end
                if menuZeile == 3 then s.n_gelenk_A = not s.n_gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 4 then s.n_gelenk_B = not s.n_gelenk_B; sys_changed = true; platform.window:invalidate(); return end
                if menuZeile == 5 then s.q_gelenk_A = not s.q_gelenk_A; sys_changed = true; platform.window:invalidate(); return end; if menuZeile == 6 then s.q_gelenk_B = not s.q_gelenk_B; sys_changed = true; platform.window:invalidate(); return end
            elseif menuSeite == 7 then if menuZeile == 7 then exportStabToTI(menuIndex); menuOffen = false; platform.window:invalidate(); return end end
            
            if eingabeModus then
                local z, s_val = evalInput(eingabeText, true)
                if z then
                    if menuSeite == 1 then if menuZeile==1 and z > 0 then s.EI=z; sys_changed = true; s.EI_str=s_val end; if menuZeile==2 and z > 0 then s.EA=z; sys_changed = true; s.EA_str=s_val end; if menuZeile==6 then s.bogen_r=z; sys_changed = true; s.bogen_r_str=s_val end
                    elseif menuSeite == 3 then if menuZeile==1 then s.q_A=z; sys_changed = true; s.q_A_str=s_val end; if menuZeile==2 then s.q_B=z; sys_changed = true; s.q_B_str=s_val end; if menuZeile==3 then s.n_A=z; sys_changed = true; s.n_A_str=s_val end; if menuZeile==4 then s.n_B=z; sys_changed = true; s.n_B_str=s_val end; if menuZeile==5 then s.To=z; sys_changed = true end; if menuZeile==6 then s.Tu=z; sys_changed = true end; if menuZeile==7 then s.alpha=z; sys_changed = true end; if menuZeile==8 then s.h=z; sys_changed = true end end
                end
                
                if menuSeite == 1 and (menuZeile >= 3 and menuZeile <= 5) then
                    if menuZeile == 3 then
                        s.q_str = eingabeText
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.q = check_num else s.q = 0; sys_changed = true end
                    elseif menuZeile == 4 then
                        s.n_str = eingabeText
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.n = check_num else s.n = 0; sys_changed = true end
                    elseif menuZeile == 5 then
                        s.m_str = eingabeText
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.m = check_num else s.m = 0; sys_changed = true end
                    end
                elseif menuSeite == 2 and (menuZeile == 1 or menuZeile == 3) then
                    if menuZeile == 1 then
                        s.gx_str = eingabeText
                        local check_num = evalInput(eingabeText)
                        if check_num then sys_changed = true; s.gx = check_num else s.gx = 0; sys_changed = true end
                    elseif menuZeile == 3 then
                        s.gy_str = eingabeText
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
                        elseif menuZeile == 2 then local v, s_val = evalInput(eingabeText, true); if v and v > 0 then defEA = v; sys_changed = true; defEA_str = s_val; for _, s in ipairs(staebe) do s.EA = defEA; s.EA_str = s_val end end
                        elseif menuZeile == 3 then local v, s_val = evalInput(eingabeText, true); if v and v > 0 then defEI = v; sys_changed = true; defEI_str = s_val; for _, s in ipairs(staebe) do s.EI = defEI; s.EI_str = s_val end end
                        end
                        if starteBerechnung then starteBerechnung() end
                    else eingabeModus, eingabeText = true, "" end
                else
                    if menuZeile == 4 then defEA, defEI = 1e8, 1e8; sys_changed = true; defEA_str, defEI_str = "1e8", "1e8"; for _, s in ipairs(staebe) do s.EA = defEA; s.EI = defEI; s.EA_str = defEA_str; s.EI_str = defEI_str end; menuOffen = false
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
                if menuZeile >= 1 and menuZeile <= 7 then
                    if menuZeile == 1 then exportAllToTI()
                    elseif menuZeile == 2 then exportBiegelinienToTI()
                    elseif menuZeile == 3 then exportVerschiebungenToTI()
                    elseif menuZeile == 4 then exportKGVToTI()
                    elseif menuZeile == 5 then exportArbeitssatzToTI()
                    elseif menuZeile == 6 then exportSchnittkraefteToTI()
elseif menuZeile == 7 then exportLGSMatrixToTI() end
                    menuOffen = false; platform.window:invalidate()
                end                
            elseif menuSeite == 3 then
                if menuZeile == 5 then zeigeBemassung = not zeigeBemassung; platform.window:invalidate()
                elseif menuZeile == 7 then zahlenFormat = (zahlenFormat % 3) + 1; platform.window:invalidate()
                elseif menuZeile == 8 then zeigeMaxWerte = not zeigeMaxWerte; platform.window:invalidate()
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

function on.clearKey()
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
    warnungKinematisch = false; warnungStarrBestimmt = false
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
        if s.q_str and s.q_str:find("x") then return false end
        if s.n_str and s.n_str:find("x") then return false end
        if s.m_str and s.m_str:find("x") then return false end
        if s.gx_str and s.gx_str:find("x") then return false end
        if s.gy_str and s.gy_str:find("x") then return false end
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
                            force_vec = {ux = -math.sin(r), uy = math.cos(r)}
                        elseif not has_f and has_roller_x then
                            local r = math.rad(k.winkel or 0)
                            force_vec = {ux = math.cos(r), uy = math.sin(r)}
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
                        local rad = math.rad(k.winkel)
                        if k.lager_y then nx, ny = -math.sin(rad), math.cos(rad) else nx, ny = math.cos(rad), math.sin(rad) end
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
                if s.scheibe and states[s.scheibe] then
                    local is_k1 = (s.k1 == i)
                    local has_hinge = is_k1 and (s.gelenk_A or s.n_gelenk_A or s.q_gelenk_A) or (not is_k1 and (s.gelenk_B or s.n_gelenk_B or s.q_gelenk_B))
                    
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

getKinematicDisp_Point = function(scheibeIdx, x, y)
    if not kinematic_disk_states or not kinematic_disk_states[scheibeIdx] then return 0, 0 end
    local d = kinematic_disk_states[scheibeIdx]
    if d.type == "rot" then
        local u_x = -d.phi * (y - d.cy)
        local u_y = d.phi * (x - d.cx)
        return u_x, u_y
    elseif d.type == "trans" then
        return d.vx, d.vy
    end
    return 0, 0
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
        if s.q_str and s.q_str:find("x") then
            -- Wir berechnen R_q (Resultierende) und S_q (Flächenmoment 1. Grades bezogen auf k1)
            -- Dies fängt den Edge-Case (R_q = 0) automatisch ab, da wir nicht durch R_q teilen 
            -- müssen, um einen Schwerpunkt zu finden. Die Arbeit ist dann später exakt S_q * phi.
            s.R_q_cas = casToNumber(math.eval("approx(integral("..s.q_str..",x,0,"..L_str.."))")) or 0
            s.S_q_cas = casToNumber(math.eval("approx(integral(("..s.q_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_q_cas = nil; s.S_q_cas = nil
        end
        
        -- Längslast n(x)
        if s.n_str and s.n_str:find("x") then
            s.R_n_cas = casToNumber(math.eval("approx(integral("..s.n_str..",x,0,"..L_str.."))")) or 0
            s.S_n_cas = casToNumber(math.eval("approx(integral(("..s.n_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_n_cas = nil; s.S_n_cas = nil
        end
        
        -- Momentenlast m(x) - hierbei leistet das Gesamtmoment Arbeit an der Verdrehung
        if s.m_str and s.m_str:find("x") then
            s.R_m_cas = casToNumber(math.eval("approx(integral("..s.m_str..",x,0,"..L_str.."))")) or 0
        else
            s.R_m_cas = nil
        end
        
        -- Globale Lasten (gx und gy)
        if s.gx_str and s.gx_str:find("x") then
            s.R_gx_cas = casToNumber(math.eval("approx(integral("..s.gx_str..",x,0,"..L_str.."))")) or 0
            s.S_gx_cas = casToNumber(math.eval("approx(integral(("..s.gx_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_gx_cas = nil; s.S_gx_cas = nil
        end
        
        if s.gy_str and s.gy_str:find("x") then
            s.R_gy_cas = casToNumber(math.eval("approx(integral("..s.gy_str..",x,0,"..L_str.."))")) or 0
            s.S_gy_cas = casToNumber(math.eval("approx(integral(("..s.gy_str..")*x,x,0,"..L_str.."))")) or 0
        else
            s.R_gy_cas = nil; s.S_gy_cas = nil
        end
    end
end

getKinematicWork_Stab = function(stabIdx)
    local s = staebe[stabIdx]
    if not kinematic_disk_states or not kinematic_disk_states[s.scheibe] then return 0, "0" end
    local k1, k2 = knoten[s.k1], knoten[s.k2]
    local d = kinematic_disk_states[s.scheibe]
    local phi = (d.type == "rot") and d.phi or 0
    
    local dx = k2.x - k1.x
    local dy = k2.y - k1.y
    local L = math.sqrt(dx^2 + dy^2)
    if L < 1e-6 then return 0, "0" end
    
    local cosA = dx/L
    local sinA = dy/L
    
    local uxA, uyA = getKinematicDisp_Point(s.scheibe, k1.x, k1.y)
    
    -- Verschiebungen des Knoten A im lokalen System des Stabes
    local unA = uxA * cosA + uyA * sinA
    local uqA = -uxA * sinA + uyA * cosA
    
    local qA = s.q + (s.q_A or 0)
    local qB = s.q + (s.q_B or 0)
    local nA = s.n + (s.n_A or 0)
    local nB = s.n + (s.n_B or 0)
    
    -- Arbeit der Querlast:
    local Rq = (qA + qB)/2 * L + (s.R_q_cas or 0)
    local Sq = (L^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
    local w_q = uqA * Rq + phi * Sq
    local w_q_str = nil
    if math.abs(Rq) > 1e-4 then
        local xs = Sq / Rq
        local vs = uqA + phi * xs
        w_q_str = string.format("Wq: %.2f * %.4f", Rq, vs)
    elseif math.abs(Sq) > 1e-4 then
        w_q_str = string.format("Wq: %.2f * %.4f", Sq, phi)
    end
    
    -- Arbeit der Axiallast:
    local Rn = (nA + nB)/2 * L + (s.R_n_cas or 0)
    local Sn = (s.S_n_cas or 0)
    local w_n = unA * Rn + phi * Sn
    local w_n_str = nil
    if math.abs(Rn) > 1e-4 then
        local xs = Sn / Rn
        local vs = unA + phi * xs
        w_n_str = string.format("Wn: %.2f * %.4f", Rn, vs)
    elseif math.abs(Sn) > 1e-4 then
        w_n_str = string.format("Wn: %.2f * %.4f", Sn, phi)
    end
    
    -- Arbeit der globalen Last gx(x)
    local gx = s.gx or 0
    local dy_real = knoten[s.k2].y - knoten[s.k1].y
    local Rgx = gx * (s.gx_proj and math.abs(dy_real) or L) + (s.R_gx_cas or 0)
    local Sgx = Rgx * (L/2) + (s.S_gx_cas or 0)
    local w_gx = Rgx * uxA - Sgx * phi * sinA
    local w_gx_str = nil
    if math.abs(Rgx) > 1e-4 then
        local xs = Sgx / Rgx
        local uxs = uxA - phi * sinA * xs
        w_gx_str = string.format("Wgx: %.2f * %.4f", Rgx, uxs)
    elseif math.abs(Sgx) > 1e-4 then
        w_gx_str = string.format("Wgx: %.2f * %.4f", -Sgx * sinA, phi)
    end
    
    -- Arbeit der globalen Last gy(x)
    local gy = s.gy or 0
    local dx_real = knoten[s.k2].x - knoten[s.k1].x
    local Rgy = gy * (s.gy_proj and math.abs(dx_real) or L) + (s.R_gy_cas or 0)
    local Sgy = Rgy * (L/2) + (s.S_gy_cas or 0)
    local w_gy = Rgy * uyA + Sgy * phi * cosA
    local w_gy_str = nil
    if math.abs(Rgy) > 1e-4 then
        local xs = Sgy / Rgy
        local uys = uyA + phi * cosA * xs
        w_gy_str = string.format("Wgy: %.2f * %.4f", Rgy, uys)
    elseif math.abs(Sgy) > 1e-4 then
        w_gy_str = string.format("Wgy: %.2f * %.4f", Sgy * cosA, phi)
    end
    
    -- Arbeit der Momentenlast
    local m = s.m or 0
    local Rm = m * L + (s.R_m_cas or 0)
    local w_m = Rm * phi
    local w_m_str = nil
    if math.abs(Rm) > 1e-4 then
        w_m_str = string.format("Wm: %.2f * %.4f", Rm, phi)
    end
    
    local w_tot = w_q + w_n + w_gx + w_gy + w_m
    
    local terms = {}
    if w_q_str then table.insert(terms, w_q_str) end
    if w_n_str then table.insert(terms, w_n_str) end
    if w_gx_str then table.insert(terms, w_gx_str) end
    if w_gy_str then table.insert(terms, w_gy_str) end
    if w_m_str then table.insert(terms, w_m_str) end
    
    if #terms == 0 then return 0, {} end
    return w_tot, terms
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
    for rx = startX, b, stepPx do
        for ry = startY, h, stepPx do gc:fillRect(rx, ry, 1, 1) end
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
            if p_val and z_val then
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

    local function drawReactionArrow(gc, val, dirX, dirY, cx, cy, labelPrefix, symb_label, custom_val_str, forceDraw)
        if math.abs(val) < 1e-4 and not forceDraw then return end
        local arrowLen = math.max(30, drawPxProMeter * 0.4)
        local sign = val >= 0 and 1 or -1
        if forceDraw then sign = 1 end
        local mag = math.abs(val)

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
        local arrowLen = math.max(30, drawPxProMeter * 0.45)
        local sign = val >= 0 and 1 or -1
        if forceDraw then sign = 1 end
        if forceDraw and flipMultiplier then sign = sign * flipMultiplier end
        local mag = math.abs(val)

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
        return u_homogen + (u_part_class_EA + u_part_cas_EA) / s.EA
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
                            local EI = s.EI
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
                        if math.abs(val) < 1e-5 then val = 0 end
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
                        if ansichtsModus == "N" then v1 = pd.N; v2 = pd.N
                        elseif ansichtsModus == "Q" then v1 = pd.Q; v2 = pd.Q
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
                    if L_m > 0 then
                        local u_phys_xA, u_phys_yA, u_phys_xB, u_phys_yB = getKinematicDisp_Stab(i)
                        local orig_dx_phys = knoten[s.k2].x - knoten[s.k1].x
                        local orig_dy_phys = knoten[s.k2].y - knoten[s.k1].y
                        local L_phys = math.sqrt(orig_dx_phys^2 + orig_dy_phys^2)
                        local cA = L_phys > 0 and orig_dx_phys/L_phys or 1
                        local sA = L_phys > 0 and orig_dy_phys/L_phys or 0
                        
                        local phi_stab = 0
                        if L_phys > 1e-6 then phi_stab = (orig_dx_phys * (u_phys_yB - u_phys_yA) - orig_dy_phys * (u_phys_xB - u_phys_xA)) / (L_phys^2) end
                        local phi_abs = math.abs(phi_stab)
                        local function formatDeltaStab(lbl, val)
                            if phi_abs > 1e-4 then 
                                return string.format("%s = %.2f * φ_0", lbl, math.abs(val)/phi_abs)
                            else 
                                local real_lbl = (s.scheibe and kinematic_disk_states and kinematic_disk_states[s.scheibe] and kinematic_disk_states[s.scheibe].type == "trans") and string.format("δ_%d", s.scheibe) or lbl
                                return string.format("%s = %.2f", real_lbl, math.abs(val)) 
                            end
                        end
                        
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
                            if math.abs(Rq * vs) > 1e-4 then
                                local disp_px = vs * anim_f
                                local ax1, ay1 = px - (-sA) * disp_px, py - cA * disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(formatDeltaStab("δ_q", vs), ax1 + 5, ay1 - 10)
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
                            if math.abs(Rn * us) > 1e-4 then
                                local disp_px = us * anim_f
                                local ax1, ay1 = px - cA * disp_px, py - sA * disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(formatDeltaStab("δ_n", us), ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local Rgy = (s.gy or 0) * (s.gy_proj and math.abs(orig_dx_phys) or L_phys) + (s.R_gy_cas or 0)
                        local Sgy = Rgy * (L_phys/2) + (s.S_gy_cas or 0)
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
                            if math.abs(Rgy * uys) > 1e-4 then
                                local disp_px = uys * anim_f
                                local ax1, ay1 = px, py - disp_px
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(formatDeltaStab("δ_gy", uys), ax1 + 5, ay1 - 10)
                            end
                        end
                        
                        local Rgx = (s.gx or 0) * (s.gx_proj and math.abs(orig_dy_phys) or L_phys) + (s.R_gx_cas or 0)
                        local Sgx = Rgx * (L_phys/2) + (s.S_gx_cas or 0)
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
                            if math.abs(Rgx * uxs) > 1e-4 then
                                local disp_px = uxs * anim_f
                                local ax1, ay1 = px - disp_px, py
                                gc:setColorRGB(200, 0, 200)
                                drawArrow(gc, ax1, ay1, px, py)
                                gc:drawString(formatDeltaStab("δ_gx", uxs), ax1 + 5, ay1 - 10)
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
                local has_cas_gy = s.gy_str and string.find(s.gy_str, "x")
                local has_classic_gy = (s.gy or 0) ~= 0
                if hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts and (has_classic_gy or has_cas_gy) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local Rgy = (s.gy or 0) * (s.gy_proj and math.abs(dx_m) or L_phys) + (s.R_gy_cas or 0)
                    local Sgy = Rgy * (L_phys/2) + (s.S_gy_cas or 0)
                    if math.abs(Rgy) > 1e-4 then
                        local x_res = Sgy / Rgy
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        gc:setColorRGB(255, 150, 0)
                        local dir = Rgy > 0 and 1 or -1
                        drawArrow(gc, px_res, py_res - 40 * dir, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(formatLabel(math.abs(Rgy)), px_res + 5, py_res - 45 * dir - 10)
                        if not glob_resultant_pts then glob_resultant_pts = {} end
                        table.insert(glob_resultant_pts, {x = knoten[s.k1].x + ux * x_res, y = knoten[s.k1].y + uy * x_res, is_virtual = false})
                    end
                elseif has_classic_gy or has_cas_gy then
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
                            local top_y = math.min(py1, py2) - 25; if ref_gy < 0 then top_y = math.max(py1, py2) + 25 end
                            gc:drawLine(px1, py1, px1, top_y); gc:drawLine(px2, py2, px2, top_y)
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gy_val = has_cas_gy and (s.gy_pts and s.gy_pts[j+1] or 0) or s.gy
                                local dir = gy_val > 0 and -1 or 1
                                local h_curr = math.abs(gy_val) * scale_gy * dir
                                local tailX, tailY = px1 + dx*t, top_y + h_curr
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, px1 + dx*t, top_y) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts); gc:drawLine(px1, top_y, px2, top_y)
                        else
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gy_val = has_cas_gy and (s.gy_pts and s.gy_pts[j+1] or 0) or s.gy
                                local dir = gy_val > 0 and -1 or 1
                                local h_curr = math.abs(gy_val) * scale_gy * dir
                                local tailX, tailY = px1 + dx*t, py1 + dy*t + h_curr
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, px1 + dx*t, py1 + dy*t) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts)
                        end
                    end
                end

                local has_cas_gx = s.gx_str and string.find(s.gx_str, "x")
                local has_classic_gx = (s.gx or 0) ~= 0
                if hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts and (has_classic_gx or has_cas_gx) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local Rgx = (s.gx or 0) * (s.gx_proj and math.abs(dy_m) or L_phys) + (s.R_gx_cas or 0)
                    local Sgx = Rgx * (L_phys/2) + (s.S_gx_cas or 0)
                    if math.abs(Rgx) > 1e-4 then
                        local x_res = Sgx / Rgx
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        gc:setColorRGB(255, 150, 0)
                        local dir = Rgx > 0 and -1 or 1
                        drawArrow(gc, px_res + 40 * dir, py_res, px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(formatLabel(math.abs(Rgx)), px_res + 45 * dir + 5, py_res - 10)
                        if not glob_resultant_pts then glob_resultant_pts = {} end
                        table.insert(glob_resultant_pts, {x = knoten[s.k1].x + ux * x_res, y = knoten[s.k1].y + uy * x_res, is_virtual = false})
                    end
                elseif has_classic_gx or has_cas_gx then
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
                            local side_x = math.min(px1, px2) - 25; if ref_gx < 0 then side_x = math.max(px1, px2) + 25 end
                            gc:drawLine(px1, py1, side_x, py1); gc:drawLine(px2, py2, side_x, py2)
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gx_val = has_cas_gx and (s.gx_pts and s.gx_pts[j+1] or 0) or s.gx
                                local dir = gx_val > 0 and -1 or 1
                                local h_curr = math.abs(gx_val) * scale_gx * dir
                                local tailX, tailY = side_x + h_curr, py1 + dy*t
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, side_x, py1 + dy*t) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts); gc:drawLine(side_x, py1, side_x, py2)
                        else
                            local env_pts = {}
                            for j = 0, steps do
                                local t = j/steps; local gx_val = has_cas_gx and (s.gx_pts and s.gx_pts[j+1] or 0) or s.gx
                                local dir = gx_val > 0 and -1 or 1
                                local h_curr = math.abs(gx_val) * scale_gx * dir
                                local tailX, tailY = px1 + dx*t + h_curr, py1 + dy*t
                                table.insert(env_pts, tailX); table.insert(env_pts, tailY)
                                if math.abs(h_curr) > 0.5 then drawArrow(gc, tailX, tailY, px1 + dx*t, py1 + dy*t) end
                            end
                            gc:setPen("thin", "smooth"); gc:drawPolyLine(env_pts)
                        end
                    end
                end

                gc:setColorRGB(255, 50, 50)
                local has_classic_q = (s.q + s.q_A ~= 0) or (s.q + s.q_B ~= 0)
                local has_cas_q = (s.q_pts and #s.q_pts == 11)

                if hovered_ts and glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts and (has_classic_q or has_cas_q) then
                    local dx_m, dy_m = knoten[s.k2].x - knoten[s.k1].x, knoten[s.k2].y - knoten[s.k1].y
                    local L_phys = math.sqrt(dx_m^2 + dy_m^2)
                    local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                    local Rq = (qA + qB)/2 * L_phys + (s.R_q_cas or 0)
                    local Sq = (L_phys^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
                    if math.abs(Rq) > 1e-4 then
                        local x_res = Sq / Rq
                        local px_res = orig_px1 + ux * x_res * drawPxProMeter
                        local py_res = orig_py1 + uy * x_res * drawPxProMeter
                        drawArrow(gc, px_res - nx * 40 * (Rq > 0 and 1 or -1), py_res - ny * 40 * (Rq > 0 and 1 or -1), px_res, py_res)
                        gc:setFont("sansserif", "b", 8)
                        gc:drawString(formatLabel(math.abs(Rq)), px_res - nx * 45 * (Rq > 0 and 1 or -1) - 10, py_res - ny * 45 * (Rq > 0 and 1 or -1) - 10)
                        -- Let's also add the resultant point to a global so we can dimension it
                        if not glob_resultant_pts then glob_resultant_pts = {} end
                        table.insert(glob_resultant_pts, {x = knoten[s.k1].x + ux * x_res, y = knoten[s.k1].y + uy * x_res, is_virtual = false})
                    end
                elseif has_classic_q or has_cas_q then
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
                            local fx, fy = px1 + dx*t, py1 + dy*t
                            table.insert(pts_env, fx + nx*h_curr); table.insert(pts_env, fy + ny*h_curr)
                            if math.abs(h_curr) > 0.5 then drawArrow(gc, fx + nx*h_curr, fy + ny*h_curr, fx, fy) end
                        end
                        gc:setPen("thin", "smooth"); gc:drawPolyLine(pts_env)
                        gc:drawLine(px1, py1, pts_env[1], pts_env[2]); gc:drawLine(px2, py2, pts_env[#pts_env-1], pts_env[#pts_env])
                        
                    end
                end

                local has_classic_n = (s.n + s.n_A ~= 0) or (s.n + s.n_B ~= 0)
                local has_cas_n = (s.n_pts and #s.n_pts == 11)

                if has_classic_n or has_cas_n then
                    local combined_n = {}; local max_abs_n = 0
                    for j = 0, 10 do
                        local t = j / 10; local n_class = (s.n + s.n_A)*(1-t) + (s.n + s.n_B)*t
                        local n_c = (has_cas_n and s.n_pts[j+1]) or 0
                        local n_tot = n_class + n_c
                        table.insert(combined_n, n_tot)
                        if math.abs(n_tot) > max_abs_n then max_abs_n = math.abs(n_tot) end
                    end

                    if max_abs_n > 0 then
                        local dist = 14; gc:drawLine(px1 + nx*dist, py1 + ny*dist, px2 + nx*dist, py2 + ny*dist)
                        for j = 0, 10, 2 do
                            local t = j/10; local n_curr = combined_n[j+1]; local fx, fy = px1 + dx*t + nx*dist, py1 + dy*t + ny*dist
                            if math.abs(n_curr) > 0.5 then
                                local arr_len = (n_curr/max_abs_n)*12
                                drawArrow(gc, fx - (dx/L)*arr_len, fy - (dy/L)*arr_len, fx + (dx/L)*arr_len, fy + (dy/L)*arr_len)
                            end
                        end
                        
                    end
                end

                local has_classic_m = (s.m ~= 0)
                local has_cas_m = (s.m_pts and #s.m_pts == 11)

                if has_classic_m or has_cas_m then
                    local combined_m = {}; local max_abs_m = 0
                    for j = 0, 10 do
                        local m_class = s.m; local m_c = (has_cas_m and s.m_pts[j+1]) or 0; local m_tot = m_class + m_c
                        table.insert(combined_m, m_tot)
                        if math.abs(m_tot) > max_abs_m then max_abs_m = math.abs(m_tot) end
                    end
                    if max_abs_m > 0 then
                        for j = 1, 9, 2 do
                            local t = j/10; local m_curr = combined_m[j+1]; local fx, fy = px1 + dx*t, py1 + dy*t
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
                        elseif ansichtsModus == "N" then val = (pd_left.N + pd_right.N) / 2
                        elseif ansichtsModus == "Q" then val = (pd_left.Q + pd_right.Q) / 2 end
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
                    local v_end = (ansichtsModus == "N" and pd_last.N) or (ansichtsModus == "Q" and pd_last.Q) or (pd_last.M2)
                    
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
                    local function get_arc_val(idx)
                        local pd = s.arc_plot_data[idx]
                        if not pd then return 0 end
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
                            local t_m = best_idx / n_pts
                            local h_x = t_m * math.abs(s.bogen_alpha or 1) * math.abs(s.bogen_r or 1)
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
                        local EI = s.EI
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

                    if math.abs(val) < 1e-5 then val = 0 end
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
                    lbl = symbolischer_modus and (s.symb_N_start and fm(s.symb_N_start) or "S"..i) or "S_"..i
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
                offsetX_A = kn.last_x; offsetY_A = kn.last_y; offsetM_A = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_A = isSupp and kn.Rx_glob or 0; offsetRy_A = isSupp and kn.Ry_glob or 0; offsetRm_A = isSupp and kn.Rm_glob or 0
                if nodeA_in_ts then
                    loadApplied[s.k1] = true; drawExtA = true
                end
            elseif explodeA then
                local kn = knoten[s.k1]
                offsetX_A = kn.last_x; offsetY_A = kn.last_y; offsetM_A = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_A = isSupp and kn.Rx_glob or 0; offsetRy_A = isSupp and kn.Ry_glob or 0; offsetRm_A = isSupp and kn.Rm_glob or 0
            end

            local nodeB_in_ts = (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k2, hovered_ts))
            if explodeB and not loadApplied[s.k2] then
                local kn = knoten[s.k2]
                offsetX_B = kn.last_x; offsetY_B = kn.last_y; offsetM_B = kn.last_m
                local isSupp = kn.lager_x or kn.lager_y or kn.lager_m or kn.cx > 0 or kn.cy > 0 or kn.cm > 0
                offsetRx_B = isSupp and kn.Rx_glob or 0; offsetRy_B = isSupp and kn.Ry_glob or 0; offsetRm_B = isSupp and kn.Rm_glob or 0
                if nodeB_in_ts then
                    loadApplied[s.k2] = true; drawExtB = true
                end
            elseif explodeB then
                local kn = knoten[s.k2]
                offsetX_B = kn.last_x; offsetY_B = kn.last_y; offsetM_B = kn.last_m
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

            local function getNumTS(node_idx)
                local ang_count, rigid_count = 0, 0
                if knoten[node_idx].gelenk then
                    local count = 0
                    for _, ts in ipairs(staebe) do
                        if not ts.is_cut and (ts.k1 == node_idx or ts.k2 == node_idx) then count = count + 1 end
                    end
                    return count
                else
                    for _, ts in ipairs(staebe) do
                        if not ts.is_cut then
                            if ts.k1 == node_idx then
                                if ts.gelenk_A or ts.n_gelenk_A or ts.q_gelenk_A then ang_count = ang_count + 1 else rigid_count = rigid_count + 1 end
                            elseif ts.k2 == node_idx then
                                if ts.gelenk_B or ts.n_gelenk_B or ts.q_gelenk_B then ang_count = ang_count + 1 else rigid_count = rigid_count + 1 end
                            end
                        end
                    end
                    return ang_count + (rigid_count > 0 and 1 or 0)
                end
            end
            local lblSuffixA = getNumTS(s.k1) > 2 and ("s"..(s.ts_scheibe or i)) or ""
            local lblSuffixB = getNumTS(s.k2) > 2 and ("s"..(s.ts_scheibe or i)) or ""
            local function getFlipMultiplier(node_idx, s_idx)
                if knoten[node_idx].gelenk then
                    return 1
                end

                local r1
                local conn = {}
                for j, ts in ipairs(staebe) do
                    if ts.k1 == node_idx or ts.k2 == node_idx then table.insert(conn, j) end
                end
                
                for _, j in ipairs(conn) do
                    local ts = staebe[j]
                    if (ts.k1 == node_idx and (ts.gelenk_A or ts.n_gelenk_A or ts.q_gelenk_A)) or
                       (ts.k2 == node_idx and (ts.gelenk_B or ts.n_gelenk_B or ts.q_gelenk_B)) then
                        r1 = j
                        break
                    end
                end
                
                if not r1 or s_idx == r1 then
                    return 1
                end
                
                local r1_is_k1 = (staebe[r1].k1 == node_idx)
                local s_is_k1 = (staebe[s_idx].k1 == node_idx)
                
                if r1_is_k1 == s_is_k1 then
                    return -1
                else
                    return 1
                end
            end
            
            local flipA = getFlipMultiplier(s.k1, i)
            local flipB = getFlipMultiplier(s.k2, i)
            local isHingeA = s.n_gelenk_A or s.q_gelenk_A or s.gelenk_A or knoten[s.k1].gelenk
            local prefixN_A = (explosionPage == 2 and isHingeA) and ("Gn_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "N = "
            local prefixQ_A = (explosionPage == 2 and isHingeA) and ("Gq_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "Q = "
            local prefixM_A = (explosionPage == 2 and isHingeA) and ("Gm_"..getHingeNumber(s.k1)..lblSuffixA.." = ") or "M = "
            local isMHingeA = knoten[s.k1].gelenk or s.gelenk_A

            if explodeA and (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) or isRigidNodeInTS(s.k1, hovered_ts)) then
                local val_N, val_Q, val_h, val_v
                if not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) then
                    if useLocalA then
                        val_N = -N_a_proj; val_Q = -V_a_proj
                        if not s.n_gelenk_A then drawFBDArrow(gc, val_N, -ux, -uy, px1, py1, prefixN_A, nil, symbolischer_modus and fm(s.symb_N_start) or nil, explosionPage == 2) end
                        if not s.q_gelenk_A then drawFBDArrow(gc, val_Q, -nx, -ny, px1, py1, prefixQ_A, nil, symbolischer_modus and fm(s.symb_Q_start) or nil, explosionPage == 2) end
                    else
                        val_h = -Fx_a; val_v = -Fy_a
                        drawFBDArrow(gc, val_h, -1, 0, px1, py1, "h = ", "Gx_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fx_a) or nil, explosionPage == 2, flipA)
                        drawFBDArrow(gc, val_v, 0, -1, px1, py1, "v = ", "Gy_"..getHingeNumber(s.k1)..lblSuffixA, symbolischer_modus and fm(s_Fy_a) or nil, explosionPage == 2, flipA)
                    end

                    if not isMHingeA then
                        if math.abs(M_a_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px1, py1, 16, M_a_disp > 0)
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
                            if offsetX_A ~= 0 then local d = offsetX_A > 0 and 1 or -1; drawReactionArrow(gc, offsetX_A, 1, 0, px1, py1, "G"..s.k1.."_h", "G"..s.k1.."_h", symbolischer_modus and fm(knoten[s.k1].x_str) or nil) end
                            if offsetY_A ~= 0 then local d = offsetY_A > 0 and 1 or -1; drawReactionArrow(gc, offsetY_A, 0, 1, px1, py1, "G"..s.k1.."_v", "G"..s.k1.."_v", symbolischer_modus and fm(knoten[s.k1].y_str) or nil) end
                        end
                        if offsetM_A ~= 0 then drawMoment(gc, px1, py1, 24, offsetM_A < 0) end
                    end
                    local isSuppNode_A = knoten[s.k1].lager_x or knoten[s.k1].lager_y or knoten[s.k1].lager_m or (knoten[s.k1].cx and knoten[s.k1].cx > 0) or (knoten[s.k1].cy and knoten[s.k1].cy > 0) or (knoten[s.k1].cm and knoten[s.k1].cm > 0)
                    if math.abs(offsetRx_A) > 1e-4 or math.abs(offsetRy_A) > 1e-4 or math.abs(offsetRm_A) > 1e-4 or (explosionPage == 2 and isSuppNode_A) then
                        local kn = knoten[s.k1]
                        local r = math.rad(kn.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        if math.abs(kn.R_xi) > 1e-4 or (explosionPage == 2 and (kn.lager_x or (kn.cx and kn.cx > 0))) then drawReactionArrow(gc, kn.R_xi, cw, -sw, px1, py1, "H = ", string.char(64 + s.k1).."_h", symbolischer_modus and fm(kn.symb_R_xi) or nil, explosionPage == 2) end
                        if math.abs(kn.R_eta) > 1e-4 or (explosionPage == 2 and (kn.lager_y or (kn.cy and kn.cy > 0))) then drawReactionArrow(gc, kn.R_eta, -sw, -cw, px1, py1, "V = ", string.char(64 + s.k1).."_v", symbolischer_modus and fm(kn.symb_R_eta) or nil, explosionPage == 2) end
                        if math.abs(offsetRm_A) > 1e-4 or (explosionPage == 2 and (kn.lager_m or (kn.cm and kn.cm > 0))) then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px1, py1, 28, offsetRm_A < 0)
                            gc:setFont("sansserif", "r", 8); gc:drawString("M = " .. formatLabel(math.abs(offsetRm_A)), px1 + 22, py1 + 22)
                        end
                    end
                end

                local should_draw_A = false
                if not knoten[s.k1].gelenk then
                    if explodeA and not is_only_rod_A then
                        should_draw_A = (not hovered_ts or isRigidNodeInTS(s.k1, hovered_ts))
                    else
                        should_draw_A = (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts))
                    end
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
                            gc:setPen("thin", "smooth"); drawMoment(gc, draw_orig_px1, draw_orig_py1, 16, M_a_disp <= 0)
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
                if not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts) then
                    if useLocalB then
                        val_N = N_b_proj; val_Q = V_b_proj
                        if not s.n_gelenk_B then drawFBDArrow(gc, val_N, ux, uy, px2, py2, prefixN_B, nil, symbolischer_modus and fm(s.symb_N_end) or nil, explosionPage == 2) end
                        if not s.q_gelenk_B then drawFBDArrow(gc, val_Q, nx, ny, px2, py2, prefixQ_B, nil, symbolischer_modus and fm(s.symb_Q_end) or nil, explosionPage == 2) end
                    else
                        val_h = Fx_b; val_v = Fy_b
                        drawFBDArrow(gc, val_h, 1, 0, px2, py2, "h = ", "Gx_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fx_b) or nil, explosionPage == 2, flipB)
                        drawFBDArrow(gc, val_v, 0, 1, px2, py2, "v = ", "Gy_"..getHingeNumber(s.k2)..lblSuffixB, symbolischer_modus and fm(s_Fy_b) or nil, explosionPage == 2, flipB)
                    end

                    if not isMHingeB then
                        if math.abs(M_b_disp) > 1e-4 or explosionPage == 2 then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 150, 0) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px2, py2, 16, M_b_disp < 0)
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
                            if offsetX_B ~= 0 then local d = offsetX_B > 0 and 1 or -1; drawReactionArrow(gc, offsetX_B, 1, 0, px2, py2, "G"..s.k2.."_h", "G"..s.k2.."_h", symbolischer_modus and fm(knoten[s.k2].x_str) or nil) end
                            if offsetY_B ~= 0 then local d = offsetY_B > 0 and 1 or -1; drawReactionArrow(gc, offsetY_B, 0, 1, px2, py2, "G"..s.k2.."_v", "G"..s.k2.."_v", symbolischer_modus and fm(knoten[s.k2].y_str) or nil) end
                        end
                        if offsetM_B ~= 0 then drawMoment(gc, px2, py2, 24, offsetM_B < 0) end
                    end
                    local isSuppNode_B = knoten[s.k2].lager_x or knoten[s.k2].lager_y or knoten[s.k2].lager_m or (knoten[s.k2].cx and knoten[s.k2].cx > 0) or (knoten[s.k2].cy and knoten[s.k2].cy > 0) or (knoten[s.k2].cm and knoten[s.k2].cm > 0)
                    if math.abs(offsetRx_B) > 1e-4 or math.abs(offsetRy_B) > 1e-4 or math.abs(offsetRm_B) > 1e-4 or (explosionPage == 2 and isSuppNode_B) then
                        local kn = knoten[s.k2]
                        local r = math.rad(kn.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        if math.abs(kn.R_xi) > 1e-4 or (explosionPage == 2 and (kn.lager_x or (kn.cx and kn.cx > 0))) then drawReactionArrow(gc, kn.R_xi, cw, -sw, px2, py2, "H = ", string.char(64 + s.k2).."_h", symbolischer_modus and fm(kn.symb_R_xi) or nil, explosionPage == 2) end
                        if math.abs(kn.R_eta) > 1e-4 or (explosionPage == 2 and (kn.lager_y or (kn.cy and kn.cy > 0))) then drawReactionArrow(gc, kn.R_eta, -sw, -cw, px2, py2, "V = ", string.char(64 + s.k2).."_v", symbolischer_modus and fm(kn.symb_R_eta) or nil, explosionPage == 2) end
                        if math.abs(offsetRm_B) > 1e-4 or (explosionPage == 2 and (kn.lager_m or (kn.cm and kn.cm > 0))) then
                            if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                            gc:setPen("thin", "smooth"); drawMoment(gc, px2, py2, 28, offsetRm_B < 0)
                            gc:setFont("sansserif", "r", 8); gc:drawString("M = " .. formatLabel(math.abs(offsetRm_B)), px2 + 22, py2 + 22)
                        end
                    end
                end

                local should_draw_B = false
                if not knoten[s.k2].gelenk then
                    if explodeB and not is_only_rod_B then
                        should_draw_B = (not hovered_ts or isRigidNodeInTS(s.k2, hovered_ts))
                    else
                        should_draw_B = (not hovered_ts or (glob_ts_scheibe and glob_ts_scheibe[i] == hovered_ts))
                    end
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
                            gc:setPen("thin", "smooth"); drawMoment(gc, draw_orig_px2, draw_orig_py2, 16, M_b_disp >= 0)
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
                        local k_ux, k_uy = getKinematicDisp(i)
                        local anim_f = (0.5 * drawPxProMeter) / (kinematic_max_disp and kinematic_max_disp > 1e-6 and kinematic_max_disp or 1)
                        
                        local k_phi = getKinematicRot and getKinematicRot(i) or 0
                        local k_scheibe = kinematic_states and kinematic_states[i] and kinematic_states[i].scheibe or 1
                        local phi_abs = math.abs(k_phi)
                        local function formatDelta(lbl, val)
                            if phi_abs > 1e-4 then 
                                return string.format("%s = %.2f * φ_0", lbl, math.abs(val)/phi_abs)
                            else 
                                local real_lbl = (k_scheibe and kinematic_disk_states and kinematic_disk_states[k_scheibe] and kinematic_disk_states[k_scheibe].type == "trans") and string.format("δ_%d", k_scheibe) or lbl
                                return string.format("%s = %.2f", real_lbl, math.abs(val)) 
                            end
                        end
                        
                        if math.abs(fx * k_ux) > 1e-4 then
                            gc:setColorRGB(200, 0, 200)
                            local disp_px = k_ux * anim_f
                            drawArrow(gc, px - disp_px, py, px, py)
                            gc:setFont("sansserif", "r", 8)
                            gc:drawString(formatDelta("δ_x", k_ux), px - disp_px, py - 10)
                        end
                        if math.abs(fy * k_uy) > 1e-4 then
                            gc:setColorRGB(200, 0, 200)
                            local disp_py = k_uy * anim_f
                            drawArrow(gc, px, py - disp_py, px, py)
                            gc:setFont("sansserif", "r", 8)
                            gc:drawString(formatDelta("δ_y", k_uy), px + 5, py - disp_py - 10)
                        end
                        local r = math.rad(k.winkel or 0)
                        local cw, sw = math.cos(r), math.sin(r)
                        
                        local is_released_H = pvv_released_binding and pvv_released_binding.node == i and pvv_released_binding.type == "lager_x"
                        if is_released_H or (k.lager_x and math.abs(k.R_xi or 0) > 1e-4) then
                            local u_H = k_ux * cw - k_uy * sw
                            if is_released_H or math.abs(k.R_xi * u_H) > 1e-4 then
                                gc:setColorRGB(200, 0, 200)
                                local disp_H = u_H * anim_f
                                local dx, dy = cw * disp_H, -sw * disp_H
                                drawArrow(gc, px - dx, py - dy, px, py)
                                gc:setFont("sansserif", "r", 8)
                                gc:drawString(formatDelta("δ_H", u_H), px - dx, py - dy - 10)
                            end
                        end
                        
                        local is_released_V = pvv_released_binding and pvv_released_binding.node == i and pvv_released_binding.type == "lager_y"
                        if is_released_V or (k.lager_y and math.abs(k.R_eta or 0) > 1e-4) then
                            local u_V = k_ux * sw + k_uy * cw
                            if is_released_V or math.abs(k.R_eta * u_V) > 1e-4 then
                                gc:setColorRGB(200, 0, 200)
                                local disp_V = u_V * anim_f
                                local dx, dy = sw * disp_V, cw * disp_V
                                drawArrow(gc, px - dx, py - dy, px, py)
                                gc:setFont("sansserif", "r", 8)
                                gc:drawString(formatDelta("δ_V", u_V), px - dx, py - dy - 10)
                            end
                        end
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
                            if k.lager_x and (math.abs(k.R_xi or 0) > 1e-4 or explosionPage == 2) then drawReactionArrow(gc, k.R_xi or 0, cw, -sw, px, py, "H = ", getSuppLetter(i).."_h", symbolischer_modus and fm(k.symb_R_xi) or nil, explosionPage == 2) end
                            if k.lager_y and (math.abs(k.R_eta or 0) > 1e-4 or explosionPage == 2) then drawReactionArrow(gc, k.R_eta or 0, -sw, -cw, px, py, "V = ", getSuppLetter(i).."_v", symbolischer_modus and fm(k.symb_R_eta) or nil, explosionPage == 2) end
                            if k.lager_m and (math.abs(k.R_m or 0) > 1e-4 or explosionPage == 2) then
                                if autoKGV and KGV_Zustand > 0 then gc:setColorRGB(200, 0, 200) else gc:setColorRGB(0, 0, 255) end
                                gc:setPen("thin", "smooth")
                                drawMoment(gc, px, py, 28, k.R_m < 0)
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
                    
                    -- Displacement drawing (delta_N, delta_Q)
                    local ux_r = bind.endA and u1x or u2x
                    local uy_r = bind.endA and u1y or u2y
                    local delta_val = (ux_r - ux_n) * nx + (uy_r - uy_n) * ny
                    local lbl_disp = bind.type == "q_gelenk" and "δ_Q" or "δ_N"
                    
                    local s_disk = s.scheibe or 1
                    local d_state = kinematic_disk_states and kinematic_disk_states[s_disk]
                    local phi_abs = d_state and math.abs(d_state.phi) or 0
                    local disp_str = ""
                    local abstand = 0
                    local rot_part = 0
                    local trans_part = delta_val
                    
                    if d_state and d_state.type == "rot" and math.abs(phi_abs) > 1e-6 then
                        if bind.type == "n_gelenk" then
                            rot_part = 0
                            abstand = 0
                            trans_part = delta_val
                        else
                            local n_idx = bind.endA and s.k1 or s.k2
                            local kn = knoten[n_idx]
                            
                            local dy_pol = kn.y - d_state.cy
                            local dx_pol = kn.x - d_state.cx
                            
                            local ux_rot = -d_state.phi * dy_pol
                            local uy_rot = d_state.phi * dx_pol
                            
                            rot_part = ux_rot * nx + uy_rot * ny
                            abstand = rot_part / d_state.phi
                            trans_part = delta_val - rot_part
                        end
                    end
                    
                    local sign = delta_val < 0 and -1 or 1
                    local disp_abstand = abstand * sign
                    local disp_trans = trans_part * sign
                    
                    disp_str = lbl_disp .. " = "
                    if math.abs(disp_abstand) > 1e-4 and math.abs(disp_trans) > 1e-4 then
                        disp_str = disp_str .. string.format("%.2f * phi_%d %s %.2f", disp_abstand, s_disk, disp_trans > 0 and "+" or "-", math.abs(disp_trans))
                    elseif math.abs(disp_abstand) > 1e-4 then
                        disp_str = disp_str .. string.format("%.2f * phi_%d", disp_abstand, s_disk)
                    else
                        disp_str = disp_str .. formatLabel(math.abs(disp_trans))
                    end
                    
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
            
            if bind.type == "lager_x" then
                drawArrow(gc, nd_px, nd_py, nd_px + 20, nd_py)
                gc:setFont("sansserif", "b", 10)
                gc:drawString("H", nd_px + 25, nd_py - 5)
            elseif bind.type == "lager_y" then
                drawArrow(gc, nd_px, nd_py, nd_px, nd_py + 20)
                gc:setFont("sansserif", "b", 10)
                gc:drawString("V", nd_px + 5, nd_py + 25)
            elseif bind.type == "lager_m" then
                -- positive moment is mathematically CCW. On screen (y down), this visually goes from right (0) to UP (-90).
                -- let's draw a CCW arc of 270 degrees
                local startAng = 90
                local sweep = 270
                gc:drawArc(nd_px - 15, nd_py - 15, 30, 30, startAng, sweep)
                local eA = math.rad(startAng + sweep); local tA = math.rad(startAng + sweep - 15)
                drawArrow(gc, nd_px + 15*math.cos(tA), nd_py - 15*math.sin(tA), nd_px + 15*math.cos(eA), nd_py - 15*math.sin(eA))
                gc:setFont("sansserif", "b", 10)
                gc:drawString("M", nd_px + 20, nd_py - 15)
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
                    local txt = (kinematic_seed_info and kinematic_seed_info.disk == i) and "Φ_0 = 1" or string.format("Φ_%d", i)
                    local txt_w = gc:getStringWidth(txt)
                    local midAng = math.rad(angle_0 + v_phi / 2)
                    local r_txt = r_ref + 10
                    gc:drawString(txt, nd_rx + r_txt*math.cos(midAng) - txt_w/2, nd_ry - r_txt*math.sin(midAng) - 6)
                end
            end
        end
    end

    if warnungKinematisch then
        local boxW, boxH = math.min(b - 20, 180), 36; local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 0, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(255, 255, 255); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("System ist kinematisch!", boxX + 8, boxY + 12)
    elseif warnungStarrBestimmt then
        local boxW, boxH = math.min(b - 20, 240), 36; local boxX, boxY = math.floor((b - boxW) / 2), math.floor((h - boxH) / 2)
        gc:setColorRGB(255, 165, 0); gc:fillRect(boxX, boxY, boxW, boxH); gc:setColorRGB(0, 0, 0); gc:drawRect(boxX, boxY, boxW, boxH)
        gc:setFont("sansserif", "b", 10); gc:drawString("Starrmodus & statisch unbestimmt!", boxX + 8, boxY + 12)
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
                local k = knoten[menuIndex]
                local fx_str = (symbolischer_modus and k.last_x_str) and k.last_x_str or formatLabel(k.last_x or 0)
                local fy_str = (symbolischer_modus and k.last_y_str) and k.last_y_str or formatLabel(k.last_y or 0)
                local fm_str = (symbolischer_modus and k.last_m_str) and k.last_m_str or formatLabel(k.last_m or 0)
                local has_m_gelenk = false
                if pvv_released_binding and pvv_released_binding.node == menuIndex then
                    local bind = pvv_released_binding
                    if bind.type == "lager_x" then fx_str = "H" elseif bind.type == "lager_y" then fy_str = "V" elseif bind.type == "lager_m" then fm_str = "M" elseif bind.type == "knoten_gelenk" then has_m_gelenk = true end
                end
                local has_fx = fx_str ~= "0" and fx_str ~= "0.00"; local has_fy = fy_str ~= "0" and fy_str ~= "0.00"; local has_fm = fm_str ~= "0" and fm_str ~= "0.00"
                if has_fx or has_fy or has_fm or has_m_gelenk then
                    local cy = 40
                    if has_fx then cy = cy + 20 end; if has_fy then cy = cy + 20 end; if has_fm then cy = cy + 20 end
                    cy = cy + 10
                    if has_fx then cy = cy + 20 end; if has_fy then cy = cy + 20 end; if has_fm then cy = cy + 20 end
                    if has_m_gelenk then cy = cy + 20 end
                    menueHoehe = cy + 50
                else menueHoehe = 80 end
            else
                if menuSeite == 1 then menueHoehe = 160 elseif menuSeite == 2 then menueHoehe = 140 elseif menuSeite == 3 then menueHoehe = 120 elseif menuSeite == 4 then menueHoehe = 200 elseif menuSeite == 5 then menueHoehe = 160 else menueHoehe = 140 end
            end
        elseif menuTyp == "stab" then
            if isKinematic then
                local s = staebe[menuIndex]
                local cy = 60
                local has_load = (math.abs(s.q) + math.abs(s.q_A or 0) + math.abs(s.q_B or 0) + math.abs(s.n) + math.abs(s.n_A or 0) + math.abs(s.n_B or 0) + math.abs(s.gx or 0) + math.abs(s.gy or 0) + math.abs(s.m or 0)) > 1e-4
                if has_load then cy = cy + 40 end
                if s.q_gelenk_A or s.n_gelenk_A or (pvv_released_binding and pvv_released_binding.stab == menuIndex and pvv_released_binding.endA and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk" or pvv_released_binding.type == "m_gelenk")) then cy = cy + 40 end
                if s.q_gelenk_B or s.n_gelenk_B or (pvv_released_binding and pvv_released_binding.stab == menuIndex and not pvv_released_binding.endA and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk" or pvv_released_binding.type == "m_gelenk")) then cy = cy + 40 end
                
                local w_tot, w_str = getKinematicWork_Stab(menuIndex)
                local is_1last_stab = false; local is_1last_node = false
                if pvv_released_binding and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk" or pvv_released_binding.type == "m_gelenk") then
                    local nodeIdx = nil
                    if pvv_released_binding.stab then local b_stab = staebe[pvv_released_binding.stab]; nodeIdx = pvv_released_binding.endA and b_stab.k1 or b_stab.k2 end
                    if (pvv_released_binding.stab and menuIndex == pvv_released_binding.stab) or (s.k1 == nodeIdx or s.k2 == nodeIdx) then
                        if (pvv_released_binding.stab and menuIndex == pvv_released_binding.stab) then is_1last_stab = true else is_1last_node = true end
                    end
                end
                
                if has_load or is_1last_stab or is_1last_node then
                    cy = cy + 20
                    if type(w_str) == "table" then for _, term in ipairs(w_str) do cy = cy + 15 end end
                    if is_1last_stab then cy = cy + 15 end
                    if is_1last_node then cy = cy + 15 end
                    cy = cy + 20
                end
                menueHoehe = cy + 20
            else
                if menuSeite == 1 then menueHoehe = 160 elseif menuSeite == 2 then menueHoehe = 120 elseif menuSeite == 3 then menueHoehe = 200 elseif menuSeite == 6 then menueHoehe = 160 elseif menuSeite == 7 then menueHoehe = 180 else menueHoehe = 160 end
            end
        elseif menuTyp == "obermenue" then if menuSeite == 1 then menueHoehe = 220 elseif menuSeite == 2 then menueHoehe = 180 elseif menuSeite == 3 then menueHoehe = 240 else menueHoehe = 60 end
        elseif menuTyp == "pvv_knoten" then menueHoehe = 120
        elseif menuTyp == "pvv_stab" then menueHoehe = 160 end

        local mW = (menuTyp == "obermenue") and 210 or 155
        local mX = b - mW - 10
        gc:setColorRGB(240, 240, 240); gc:fillRect(mX, 10, mW, menueHoehe); gc:setColorRGB(0, 0, 0); gc:drawRect(mX, 10, mW, menueHoehe)
        
        if not (isKinematic and (menuTyp == "knoten" or menuTyp == "stab")) then
            gc:setColorRGB(200, 200, 255); gc:fillRect(mX + 2, 20 + (menuZeile * 20), mW - 4, 18)
        end
        gc:setColorRGB(0, 0, 0); gc:setFont("sansserif", "b", 9)

        if menuTyp == "knoten" then
            if isKinematic then
                gc:drawString("Knoten " .. menuIndex .. " (PvV-Modus)", b - 160, 15); gc:setFont("sansserif", "r", 9)
        local k_ux, k_uy = getKinematicDisp(menuIndex)
        local k_phi = getKinematicRot and getKinematicRot(menuIndex) or 0
        local k = knoten[menuIndex]
        local fx_str = (symbolischer_modus and k.last_x_str) and k.last_x_str or formatLabel(k.last_x or 0)
        local fy_str = (symbolischer_modus and k.last_y_str) and k.last_y_str or formatLabel(k.last_y or 0)
        local fm_str = (symbolischer_modus and k.last_m_str) and k.last_m_str or formatLabel(k.last_m or 0)

        local is_released_x = false; local is_released_y = false; local is_released_m = false
        local has_m_gelenk = false
        local m_gelenk_phi1, m_gelenk_phi2 = 0, 0

        if pvv_released_binding and pvv_released_binding.node == menuIndex then
            local bind = pvv_released_binding
            if bind.type == "lager_x" then fx_str = "H"; is_released_x = true
            elseif bind.type == "lager_y" then fy_str = "V"; is_released_y = true
            elseif bind.type == "lager_m" then fm_str = "M"; is_released_m = true
            elseif bind.type == "knoten_gelenk" then
                has_m_gelenk = true
                local m_gelenk_s1, m_gelenk_s2 = nil, nil
                for _, s in ipairs(staebe) do
                    if s.k1 == menuIndex or s.k2 == menuIndex then
                        if not m_gelenk_s1 then m_gelenk_s1 = s
                        elseif not m_gelenk_s2 then m_gelenk_s2 = s end
                    end
                end
                if m_gelenk_s1 then m_gelenk_phi1 = -(kinematic_disk_states and kinematic_disk_states[m_gelenk_s1.scheibe] and kinematic_disk_states[m_gelenk_s1.scheibe].type == "rot" and kinematic_disk_states[m_gelenk_s1.scheibe].phi or 0) end
                if m_gelenk_s2 then m_gelenk_phi2 = -(kinematic_disk_states and kinematic_disk_states[m_gelenk_s2.scheibe] and kinematic_disk_states[m_gelenk_s2.scheibe].type == "rot" and kinematic_disk_states[m_gelenk_s2.scheibe].phi or 0) end
            end
        end

        local has_fx = fx_str ~= "0" and fx_str ~= "0.00"
        local has_fy = fy_str ~= "0" and fy_str ~= "0.00"
        local has_fm = fm_str ~= "0" and fm_str ~= "0.00"

        local current_y = 40
        if has_fx or has_fy or has_fm or has_m_gelenk then
            if has_fx then
                gc:setColorRGB(0,0,0); gc:drawString("Starrk. u_x:", b - 160, current_y)
                gc:setColorRGB(0, 120, 0); gc:drawString(string.format("%.4f", k_ux), b - 70, current_y)
                current_y = current_y + 20
            end
            if has_fy then
                gc:setColorRGB(0,0,0); gc:drawString("Starrk. u_y:", b - 160, current_y)
                gc:setColorRGB(0, 120, 0); gc:drawString(string.format("%.4f", k_uy), b - 70, current_y)
                current_y = current_y + 20
            end
            if has_fm then
                gc:setColorRGB(0,0,0); gc:drawString("Starrk. phi:", b - 160, current_y)
                gc:setColorRGB(0, 120, 0); gc:drawString(string.format("%.4f", k_phi), b - 70, current_y)
                current_y = current_y + 20
            end

            local w_str_parts = {}
            local w_val_sum = 0
            if has_fx then
                gc:setColorRGB(0,0,0); gc:drawString("Arbeit W_x:", b - 160, current_y)
                local val = evalInput(fx_str) or 1
                if symbolischer_modus or is_released_x then
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f", fx_str, k_ux), b - 80, current_y)
                else
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f = %.2f", fx_str, k_ux, val * k_ux), b - 80, current_y)
                end
                table.insert(w_str_parts, string.format("%s*%.2f", fx_str, k_ux))
                if not is_released_x then w_val_sum = w_val_sum + val * k_ux end
                current_y = current_y + 20
            end
            if has_fy then
                gc:setColorRGB(0,0,0); gc:drawString("Arbeit W_y:", b - 160, current_y)
                local val = evalInput(fy_str) or 1
                if symbolischer_modus or is_released_y then
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f", fy_str, k_uy), b - 80, current_y)
                else
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f = %.2f", fy_str, k_uy, val * k_uy), b - 80, current_y)
                end
                table.insert(w_str_parts, string.format("%s*%.2f", fy_str, k_uy))
                if not is_released_y then w_val_sum = w_val_sum + val * k_uy end
                current_y = current_y + 20
            end
            if has_fm then
                gc:setColorRGB(0,0,0); gc:drawString("Arbeit W_phi:", b - 160, current_y)
                local val = evalInput(fm_str) or 1
                if symbolischer_modus or is_released_m then
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f", fm_str, k_phi), b - 80, current_y)
                else
                    gc:setColorRGB(200, 50, 50); gc:drawString(string.format("%s * %.2f = %.2f", fm_str, k_phi, val * k_phi), b - 80, current_y)
                end
                table.insert(w_str_parts, string.format("%s*%.2f", fm_str, k_phi))
                if not is_released_m then w_val_sum = w_val_sum + val * k_phi end
                current_y = current_y + 20
            end
            if has_m_gelenk then
                gc:setColorRGB(0,0,0); gc:drawString("Arbeit W_M:", b - 160, current_y)
                local dphi = m_gelenk_phi1 - m_gelenk_phi2
                gc:setColorRGB(200, 50, 50); gc:drawString(string.format("M * %.2f", dphi), b - 80, current_y)
                table.insert(w_str_parts, string.format("M*%.2f", dphi))
                current_y = current_y + 20
            end

            current_y = current_y + 5
            gc:setColorRGB(0,0,0)
            gc:drawLine(b - 160, current_y - 2, b - 10, current_y - 2)
            gc:drawString("Summe W:", b - 160, current_y + 5)
            gc:setFont("sansserif", "r", 8)
            local pvv_sum_str = table.concat(w_str_parts, " + ")
            gc:setColorRGB(200, 50, 50)
            gc:drawString(pvv_sum_str or "", b - 160, current_y + 20)
            gc:setFont("sansserif", "r", 9)

        else
            gc:setColorRGB(150, 150, 150)
            gc:drawString("Keine Lasten vorhanden", b - 160, current_y)
        end
            else
                local menueHoehe = 150
                if menuSeite == 1 then menueHoehe = 160 elseif menuSeite == 2 then menueHoehe = 140 elseif menuSeite == 3 then menueHoehe = 120 elseif menuSeite == 4 then menueHoehe = 200 else menueHoehe = 140 end
                
                gc:drawString("Knoten " .. menuIndex .. " < S." .. menuSeite .. "/4 >", b - 160, 15); gc:setFont("sansserif", "r", 9)
                local k = knoten[menuIndex]
                if menuSeite == 1 then
                    -- URSPRÜNGLICHE REIHENFOLGE WIEDERHERGESTELLT: 
                    -- Zeile 3 ist "Gelenkig", Zeilen 4-6 sind die Lager-Eigenschaften.
                    -- Dies stimmt jetzt wieder 100% mit der Logik in on.enterKey überein!
                    gc:drawString("X Koord:", b - 160, 40); gc:drawString("Y Koord:", b - 160, 60); gc:drawString("Gelenkig:", b - 160, 80); gc:drawString("Lager X:", b - 160, 100); gc:drawString("Lager Y:", b - 160, 120); gc:drawString("Lager M:", b - 160, 140)
                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 40) else gc:drawString(tostring(k.x), b - 65, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 60) else gc:drawString(tostring(k.y), b - 65, 60) end
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
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 40) else gc:drawString(symbolischer_modus and (k.cx_str or tostring(k.cx or 0)) or tostring(k.cx or 0), b - 65, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 60) else gc:drawString(symbolischer_modus and (k.cy_str or tostring(k.cy or 0)) or tostring(k.cy or 0), b - 65, 60) end
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 80) else gc:drawString(symbolischer_modus and (k.cm_str or tostring(k.cm or 0)) or tostring(k.cm or 0), b - 65, 80) end
                    if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 65, 100) else gc:drawString(tostring(k.f_winkel or 0), b - 65, 100) end
                elseif menuSeite == 4 then
                    gc:drawString("R_xi (Parallel):", b - 160, 40); gc:drawString("R_eta (Senkr.):", b - 160, 60); gc:drawString("R_m (Moment):", b - 160, 80)
                    gc:drawString("ü_x (WGV):", b - 160, 100); gc:drawString("ü_y (WGV):", b - 160, 120); gc:drawString("ü_ges (WGV):", b - 160, 140); gc:drawString("phi (WGV):", b - 160, 160)
                    gc:drawString("In TI speichern:", b - 160, 180)
                    
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
                        
                        gc:drawString(fm(s_Rx), b - 60, 40)
                        gc:drawString(fm(s_Ry), b - 60, 60)
                        gc:drawString(fm(s_Rm), b - 60, 80)
                    else
                        gc:drawString(formatLabel(k.R_xi or 0), b - 60, 40); gc:drawString(formatLabel(k.R_eta or 0), b - 60, 60); gc:drawString(formatLabel(k.R_m or 0), b - 60, 80)
                    end
                    
                    gc:setColorRGB(255, 120, 0)
                    gc:drawString(string.format("%.4f", ux), b - 60, 100); gc:drawString(string.format("%.4f", uy), b - 60, 120); gc:drawString(string.format("%.4f", u_ges), b - 60, 140); gc:drawString(string.format("%.4f", phi), b - 60, 160)
                    if menuZeile == 8 then gc:setColorRGB(200, 0, 0) else gc:setColorRGB(0, 0, 255) end
                            gc:drawString("Export", b - 60, 180)
                end
            end

        elseif menuTyp == "stab" then
            local s = staebe[menuIndex]
            if isKinematic then
                gc:drawString("Stab " .. menuIndex .. " (PvV-Modus)", b - 160, 15); gc:setFont("sansserif", "r", 9)
                
                gc:drawString("Verdrehung phi:", b - 160, 40)
                gc:setColorRGB(0, 120, 0)
                local s_phi = kinematic_disk_states and kinematic_disk_states[s.scheibe] and kinematic_disk_states[s.scheibe].type == "rot" and kinematic_disk_states[s.scheibe].phi or 0
                gc:drawString(string.format("%.4f", -s_phi), b - 60, 40)
                
                local w_tot, w_str = getKinematicWork_Stab(menuIndex)
                local current_y = 60
                
                local has_load = (math.abs(s.q) + math.abs(s.q_A or 0) + math.abs(s.q_B or 0) + math.abs(s.n) + math.abs(s.n_A or 0) + math.abs(s.n_B or 0) + math.abs(s.gx or 0) + math.abs(s.gy or 0) + math.abs(s.m or 0)) > 1e-4
                if has_load then
                    gc:setColorRGB(0,0,0)
                    gc:drawString("Lastangriff δ_x:", b - 160, current_y)
                    gc:drawString("Lastangriff δ_y:", b - 160, current_y + 20)
                    local k1, k2 = knoten[s.k1], knoten[s.k2]
                    local dx, dy = k2.x - k1.x, k2.y - k1.y
                    local L = math.sqrt(dx^2 + dy^2)
                    local cosA, sinA = dx/L, dy/L
                    
                    local qA = s.q + (s.q_A or 0); local qB = s.q + (s.q_B or 0)
                    local Rq = (qA + qB)/2 * L + (s.R_q_cas or 0)
                    local Sq = (L^2)/6 * (qA + 2*qB) + (s.S_q_cas or 0)
                    local nA = s.n + (s.n_A or 0); local nB = s.n + (s.n_B or 0)
                    local Rn = (nA + nB)/2 * L + (s.R_n_cas or 0)
                    local Sn = (L^2)/6 * (nA + 2*nB) + (s.S_n_cas or 0)
                    
                    local R_sum = math.abs(Rq) + math.abs(Rn) + math.abs(s.R_gx_cas or 0) + math.abs(s.R_gy_cas or 0)
                    local S_sum = math.abs(Sq) + math.abs(Sn) + math.abs(s.S_gx_cas or 0) + math.abs(s.S_gy_cas or 0)
                    
                    local xs = L/2
                    if R_sum > 1e-6 then xs = S_sum / R_sum end
                    local cx = k1.x + xs * cosA
                    local cy = k1.y + xs * sinA
                    
                    local ux, uy = getKinematicDisp_Point(s.scheibe, cx, cy)
                    gc:setColorRGB(0, 120, 0)
                    gc:drawString(string.format("%.4f", ux), b - 60, current_y)
                    gc:drawString(string.format("%.4f", uy), b - 60, current_y + 20)
                    current_y = current_y + 40
                end
                
                if s.q_gelenk_A or s.n_gelenk_A or (pvv_released_binding and pvv_released_binding.stab == menuIndex and pvv_released_binding.endA and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk")) then
                    gc:setColorRGB(0,0,0)
                    gc:drawString("Klaffung k1 δ_x:", b - 160, current_y)
                    gc:drawString("Klaffung k1 δ_y:", b - 160, current_y + 20)
                    local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(menuIndex)
                    local n_ux, n_uy = getKinematicDisp(s.k1)
                    gc:setColorRGB(0, 120, 0)
                    gc:drawString(string.format("%.4f", u1x - n_ux), b - 60, current_y)
                    gc:drawString(string.format("%.4f", u1y - n_uy), b - 60, current_y + 20)
                    current_y = current_y + 40
                end
                
                if s.q_gelenk_B or s.n_gelenk_B or (pvv_released_binding and pvv_released_binding.stab == menuIndex and not pvv_released_binding.endA and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk")) then
                    gc:setColorRGB(0,0,0)
                    gc:drawString("Klaffung k2 δ_x:", b - 160, current_y)
                    gc:drawString("Klaffung k2 δ_y:", b - 160, current_y + 20)
                    local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(menuIndex)
                    local n_ux, n_uy = getKinematicDisp(s.k2)
                    gc:setColorRGB(0, 120, 0)
                    gc:drawString(string.format("%.4f", u2x - n_ux), b - 60, current_y)
                    gc:drawString(string.format("%.4f", u2y - n_uy), b - 60, current_y + 20)
                    current_y = current_y + 40
                end
                
                local is_1last_stab = false
                local is_1last_node = false
                local w_1last_stab = 0
                local w_1last_node = 0
                local proj_1last_stab = 0
                local proj_1last_node = 0
                local force_type = ""
                
                if pvv_released_binding and (pvv_released_binding.type == "q_gelenk" or pvv_released_binding.type == "n_gelenk" or pvv_released_binding.type == "m_gelenk") then
                    local b_stab = staebe[pvv_released_binding.stab]
                    local nodeIdx = pvv_released_binding.endA and b_stab.k1 or b_stab.k2
                    
                    if menuIndex == pvv_released_binding.stab or (s.k1 == nodeIdx or s.k2 == nodeIdx) then
                        if pvv_released_binding.type == "m_gelenk" then
                            if menuIndex == pvv_released_binding.stab then
                                local s_phi = kinematic_disk_states and kinematic_disk_states[s.scheibe] and kinematic_disk_states[s.scheibe].type == "rot" and kinematic_disk_states[s.scheibe].phi or 0
                                proj_1last_stab = -s_phi
                                w_1last_stab = 1.0 * proj_1last_stab
                                is_1last_stab = true
                                force_type = "M"
                            elseif menuIndex ~= pvv_released_binding.stab then
                                local n_phi = getKinematicRot and getKinematicRot(nodeIdx) or 0
                                proj_1last_node = n_phi
                                w_1last_node = -1.0 * proj_1last_node
                                is_1last_node = true
                                force_type = "M"
                            end
                        else
                            local dx, dy = knoten[b_stab.k2].x - knoten[b_stab.k1].x, knoten[b_stab.k2].y - knoten[b_stab.k1].y
                            local L = math.sqrt(dx^2 + dy^2)
                            if L > 0 then
                                local nx, ny = dx/L, dy/L
                                if pvv_released_binding.type == "q_gelenk" then nx, ny = -ny, nx end
                                local dir = pvv_released_binding.endA and -1 or 1
                                local ax, ay = nx * dir, ny * dir
                                
                                if menuIndex == pvv_released_binding.stab then
                                    local u1x, u1y, u2x, u2y = getKinematicDisp_Stab(menuIndex)
                                    local rx = pvv_released_binding.endA and u1x or u2x
                                    local ry = pvv_released_binding.endA and u1y or u2y
                                    proj_1last_stab = ax * rx + ay * ry
                                    w_1last_stab = 1.0 * proj_1last_stab
                                    is_1last_stab = true
                                    force_type = (pvv_released_binding.type == "q_gelenk") and "Q" or "N"
                                elseif menuIndex ~= pvv_released_binding.stab then
                                    local n_ux, n_uy = getKinematicDisp(nodeIdx)
                                    proj_1last_node = ax * n_ux + ay * n_uy
                                    w_1last_node = -1.0 * proj_1last_node
                                    is_1last_node = true
                                    force_type = (pvv_released_binding.type == "q_gelenk") and "Q" or "N"
                                end
                            end
                        end
                    end
                end
                
                if has_load or is_1last_stab or is_1last_node then
                    gc:setColorRGB(0,0,0)
                    gc:drawString("Arbeit W_i:", b - 160, current_y)
                    gc:setColorRGB(200, 50, 50)
                    current_y = current_y + 20
                    local w_ges_parts = {}
                    if type(w_str) == "table" then
                        for _, term in ipairs(w_str) do
                            gc:drawString(term, b - 160, current_y)
                            local eq_part = term:gsub("^[^:]+:%s*", "")
                            table.insert(w_ges_parts, eq_part)
                            current_y = current_y + 15
                        end
                    end
                    if is_1last_stab then
                        gc:drawString(string.format("W_%s: %s * %.2f", force_type, force_type, proj_1last_stab), b - 160, current_y)
                        table.insert(w_ges_parts, string.format("%s*%.2f", force_type, proj_1last_stab))
                        current_y = current_y + 15
                    end
                    if is_1last_node then
                        gc:drawString(string.format("W_%s: %s * %.2f", force_type, force_type, proj_1last_node), b - 160, current_y)
                        table.insert(w_ges_parts, string.format("%s*%.2f", force_type, proj_1last_node))
                        current_y = current_y + 15
                    end
                    current_y = current_y + 5
                    gc:setColorRGB(0, 0, 0)
                    gc:drawLine(b - 160, current_y - 2, b - 10, current_y - 2)
                    gc:drawString("Summe W:", b - 160, current_y + 5)
                    gc:setFont("sansserif", "r", 8)
                    gc:setColorRGB(200, 50, 50)
                    gc:drawString(table.concat(w_ges_parts, " + "), b - 160, current_y + 20)
                    gc:setFont("sansserif", "r", 9)
                end
            else
                gc:drawString("Stab " .. menuIndex .. " < S." .. menuSeite .. "/7 >", b - 160, 15); gc:setFont("sansserif", "r", 9)
                if menuSeite == 1 then
                    gc:drawString("EI (kNm2):", b - 160, 40); gc:drawString("EA (kN):", b - 160, 60); gc:drawString("Last q(x):", b - 160, 80); gc:drawString("Last n(x):", b - 160, 100); gc:drawString("Momentenlast m:", b - 160, 120); gc:drawString("Bogen Radius R:", b - 160, 140)
                    gc:setColorRGB(0, 0, 255)
                    if menuZeile == 1 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 40) else gc:drawString(tostring(s.EI), b - 60, 40) end
                    if menuZeile == 2 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 60) else gc:drawString(tostring(s.EA), b - 60, 60) end
                    if menuZeile == 3 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 80) else gc:drawString(s.q_str or "0", b - 60, 80) end
                    if menuZeile == 4 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 100) else gc:drawString(s.n_str or "0", b - 60, 100) end
                    if menuZeile == 5 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 120) else gc:drawString(s.m_str or tostring(s.m), b - 60, 120) end
                    if menuZeile == 6 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 140) else gc:drawString(tostring(s.bogen_r or 0), b - 60, 140) end
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
                    if menuZeile == 5 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 120) else gc:drawString(tostring(s.To), b - 60, 120) end
                    if menuZeile == 6 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 140) else gc:drawString(tostring(s.Tu), b - 60, 140) end
                    if menuZeile == 7 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 160) else gc:drawString(tostring(s.alpha), b - 60, 160) end
                    if menuZeile == 8 and eingabeModus then gc:drawString(eingabeText .. "_", b - 60, 180) else gc:drawString(tostring(s.h), b - 60, 180) end
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
            elseif menuSeite == 3 then
                gc:drawString("CAS Bruch-Tol. (1E-x):", b - 200, 40)
                gc:drawString("Punkte/Stab (Graph):", b - 200, 60)
                gc:drawString("Zoom-Schritt Normal:", b - 200, 80)
                gc:drawString("Zoom-Schritt Expl.:", b - 200, 100)
                gc:drawString("Bemaßung zeigen:", b - 200, 120)
                gc:drawString("Bogen-Segmente:", b - 200, 140)
                gc:drawString("Zahlen-Format:", b - 200, 160)
                gc:drawString("Maximalwerte an/aus:", b - 200, 180)

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
            end
        end
    end
    ansichtsModus = orig_ansichtsModus
end