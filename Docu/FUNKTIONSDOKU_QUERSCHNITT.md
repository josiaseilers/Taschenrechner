# Funktionsdokumentation Querschnitt.lua

Diese Datei wird automatisch von der KI-Assistenz gepflegt (siehe `.github/copilot-instructions.md`). Sie gehoert zum Querschnittsmodul `Querschnitt.lua`.
Sie beschreibt zu jeder Funktion: **Zweck**, **Moeglichkeiten** und **Grenzen/bekannte Einschraenkungen**.

---

## 1. Eingabe, Formatierung & Einheiten

### `evaluate_input(expr)`
- **Zweck:** Wertet einen vom Nutzer eingegebenen Ausdruck numerisch aus.
- **Moeglichkeiten:** Dezimalkomma wird zu Punkt. Nutzt zuerst den TI-Nspire-CAS (`math.eval("approx(...)")`), sonst einen Lua-Ausdruck, der nur die `math`-Funktionen sieht (`sqrt(2)`, `pi`, `sin(...)` ohne `math.`-Praefix).
- **Grenzen:** Kein Fehlertext bei ungueltiger Eingabe (gibt `nil` zurueck); `NaN` wird ebenfalls als ungueltig behandelt.

### `floatToFrac_lua(value, tolerance, max_denominator)`
- **Zweck:** Nach Kettenbruch-Algorithmus die kuerzeste Bruchdarstellung einer Dezimalzahl finden.
- **Moeglichkeiten:** Liefert `"h/k"` oder ganze Zahl als String, begrenzt durch `max_denominator`.
- **Grenzen:** Irrationale/komplizierte Werte liefern `nil`, wenn keine Naeherung innerhalb der Toleranz gefunden wird.

### `smartToFracStr(value, tolerance)`
- **Zweck:** Zahl je nach `zahlenFormat` als Dezimalwert, Bruch oder Wurzel-Bruch darstellen.
- **Moeglichkeiten:** Erkennt einfache Wurzelausdruecke (`sqrt(n)`) durch Quadratzahl-Extraktion aus `value^2`.
- **Grenzen:** Wurzel-Erkennung nur fuer `zahlenFormat == 1` und `value^2 <= 10000`; sonst Dezimaldarstellung mit 4 Nachkommastellen.

### `formatLabel(value)`
- **Zweck:** Kurzform von `smartToFracStr` fuer Anzeige-Strings (z. B. Koordinatenbeschriftungen).
- **Moeglichkeiten:** Nutzt feste Toleranz `10^-casToleranz`.
- **Grenzen:** Nicht-numerische Werte liefern `"0"`.

### `point_to_line_dist(px, py, x1, y1, x2, y2)`
- **Zweck:** Kuerzester Abstand eines Punkts zu einer begrenzten Strecke (nicht zur unendlichen Geraden).
- **Moeglichkeiten:** Wird fuer Hover-Erkennung und Belegungspruefung (`occupied`) genutzt.
- **Grenzen:** Keine, robuste Standardformel inkl. Clamping auf `[0,1]`.

### `unit_factor(unit)`
- **Zweck:** Umrechnungsfaktor einer Einheit (Kraft/Laenge/Moment) auf die internen Basiseinheiten (N, mm, Nmm).
- **Grenzen:** Unbekannte Einheit liefert `1` (keine Fehlermeldung).

### `input_to_internal(value, unit)`
- **Zweck:** Nutzereingabe in interne Basiseinheit umrechnen (Multiplikation mit `unit_factor`).

### `cycle_unit(current, units)`
- **Zweck:** Naechste Einheit aus einer Liste zyklisch weiterschalten (fuer Menüoptionen wie Kraft-/Laengen-/Momenteinheit).

### `unit_label(power)`
- **Zweck:** Beschriftung fuer Laengen-Einheit hoch `power` (z. B. `mm^4`).
- **Grenzen:** Nur fuer Laengen-Einheiten gedacht (nicht fuer Kraft/Moment).

### `display_length/area/volume/inertia/moment/force(value)`
- **Zweck:** Interne SI-nahe Werte (mm, mm², mm³, mm⁴, Nmm, N) in die aktuell gewaehlte Anzeige-Einheit umrechnen.
- **Grenzen:** Reine Skalierung; keine Rundung, keine Format-Entscheidung (siehe `formatLabel`/`string.format` an den Aufrufstellen).

---

## 2. KOS, Anzeige-Transformation & Achsen

### `current_axes()` / `axes()`
- **Zweck:** Liefert die aktuellen Achsbezeichner (z. B. `"y","z"`) abhaengig von `plane` und `swapped`.
- **Grenzen:** Nur 3 Ebenen vorgesehen (`xy`, `yz`, `xz`); dritte Achse wird an anderen Stellen separat berechnet (`c_lbl` in `buildMenuItems`).

### `toScreen(u, v)` / `toScreenKOS(u, v)` / `fromScreen(x, y)`
- **Zweck:** Umrechnung zwischen internen Modellkoordinaten und Bildschirmpixeln, inkl. Rotation des angezeigten KOS (`rotation` 0/90/180/270°) fuer `toScreenKOS` (nur zum Zeichnen der Achsenpfeile, nicht fuer Elemente).
- **Grenzen:** `rotation` nur in 90°-Schritten unterstuetzt.

### `snap(x)`
- **Zweck:** Rundet eine Koordinate auf das aktuelle Raster (`raster`).
- **Grenzen:** Symmetrisches Runden um 0; kein adaptives Raster.

### `fange(u, v)`
- **Zweck:** `fange` sammelt alle `points` der Massiv- und Duennwand-Elemente, beim Rechteck zusaetzlich die beiden abgeleiteten Ecken, und die Punkte in `pending`. `fange` nimmt von Rasterpunkt (`snap`) und Fangpunkten den naechsten zum Klick; `on.mouseUp` benutzt `fange` statt `snap`.
- **Grenzen:** Keine Schnitt- oder Mittelpunkte von Kanten, keine Kraftpunkte; die Liste wird je Klick neu aufgebaut (bei den ueblichen Elementzahlen vernachlaessigbar).

### `coordinatesForDisplay(u, v)` / `coordinatesFromDisplay(u, v)`
- **Zweck:** Zentrale Vorzeichen-/Achsentransformation zwischen internen (u,v) und angezeigten Koordinaten je nach `rotation`.
- **Moeglichkeiten:** Wird fuer alle Anzeige-Texte, Kraftkomponenten, Momentendichten und den Schubmittelpunkt konsistent verwendet.
- **Zuordnung:** 0°: (u, v); 90°: (v, -u); 180°: (-u, -v); 270°: (-v, u). `coordinatesFromDisplay` ist die exakte Umkehrung (Rundtrip im Test geprueft).
- **Grenzen:** Muss als lokale Vorwaertsreferenz deklariert sein (`local coordinatesForDisplay` vor der Definition), da mehrere fruehere Funktionen (`displayedVector`) sie referenzieren, bevor sie definiert wird. Nur 4 Rotationsstufen abgedeckt.

### `inertiaForDisplay(Iy, Iz, Iyz)` / `alphaForDisplay(alpha)`
- **Zweck:** Flaechenmomente und Hauptachsenwinkel im angezeigten KOS. Bei 90°/270° werden `I_y` und `I_z` vertauscht und `I_yz` wechselt das Vorzeichen. Genutzt von Ergebnisfeld, Elementtabelle und Sigma-Rechnung.

### `forceComponentsForDisplay/FromDisplay(fu, fv)`
- **Zweck:** Wrapper um `coordinatesForDisplay/FromDisplay` speziell fuer Kraftkomponenten.

### `setDisplayedPointCoordinate(point, coordinate, value)`
- **Zweck:** Einzelne angezeigte Koordinate (u oder v) eines Punkts setzen, unter Beruecksichtigung der Rotation.
- **Grenzen:** Setzt immer beide internen Koordinaten neu (Rundtrip ueber Display-Koordinaten), auch wenn nur eine geaendert wird.

### `displayedCoordinateSigns()`
- **Zweck:** Liefert die Vorzeichen (+1/-1) fuer u/v-Achsen bei der aktuellen Rotation (Kurzform von `coordinatesForDisplay(1,1)`-Logik).
- **Grenzen:** Wird separat von `coordinatesForDisplay` gepflegt; muss bei neuen Rotationsstufen synchron gehalten werden.

### `displayedVector(u, v)`
- **Zweck:** Kurz-Alias fuer `coordinatesForDisplay`, genutzt in Momenten-/Schubmittelpunktberechnungen.

### `displayedMomentDensity(sample)`
- **Zweck:** Momentendichten (`moment_z_density`, `moment_y_density`) eines Schubfluss-Samples in Anzeigerichtung transformieren.
- **Grenzen:** Nutzt eigene Vorzeichentabelle statt `coordinatesForDisplay` direkt (Wartung an zwei Stellen noetig).

---

## 3. Geometrie-Grundformen (Flaeche, Schwerpunkt, Traegheitsmomente)

### `poly_props(pts)`
- **Zweck:** Flaeche, Schwerpunkt und Traegheitsmomente eines beliebigen (auch nicht konvexen) Polygons per Shoelace-Formel.
- **Moeglichkeiten:** Basis fuer Rechteck, Dreieck, Trapez/Polygon und dicke Linien (`massiv_linie`).
- **Grenzen:** Keine Selbstueberschneidungspruefung; bei entarteten Polygonen (`A ≈ 0`) werden Nullwerte zurueckgegeben.

### `sector_props(p1, p2, p3, is_segment)`
- **Zweck:** Flaeche/Schwerpunkt/Traegheitsmomente eines Kreisausschnitts (`is_segment=false`) oder Kreisabschnitts (`is_segment=true`).
- **Grenzen:** `p1` = Mittelpunkt, `p2`/`p3` definieren Start-/Endradius bzw. Sehne; Winkel wird immer im mathematisch positiven Sinn ab `p2` bestimmt. Kreisabschnitt = Sektor minus Dreieck (Mittelpunkt, p2, p3), auch fuer die Traegheitsmomente.

### `thin_line_props(p1, p2, t)`
- **Zweck:** Flaeche/Schwerpunkt/Traegheitsmomente eines geraden duennwandigen Linienelements der Dicke `t`.
- **Grenzen:** Vernachlaessigt das lokale `t^3/12`-Eigentraegheitsmoment (duennwandige Naeherung).

### `berechneLokaleWerte(elem)`
- **Zweck:** Dispatcher: berechnet A/ys/zs/Iy/Iz/Iyz eines Massiv-Elements je nach `elem.type` (rect, circle, triangle, trapezoid, sector, segment, massiv_linie).
- **Grenzen:** Loch-Elemente (`elem.is_hole`) liefern negierte Werte; unbekannter Typ liefert Nullwerte.

### `get_thin_props(elem)`
- **Zweck:** Dispatcher fuer duennwandige Elemente (`duenn_kreis`, `duenn_kreis_bogen` oder gerade Linie via `thin_line_props`). `finish_shape` legt Kreise und Boegen des Duennwandmenues jetzt in `duenn_elemente` (mit `t = default_t`) ab; vorher landeten sie in `massiv_elemente`.

### `duennKurve` (Tabelle)
- **Zweck:** Hilfen fuer duennwandige Kreise und Boegen: `gekruemmt`, `kreis` (Mittelpunkt, R, Startwinkel, Oeffnungswinkel), `abstand` (Hover), `punkte` (Polylinie fuer die sigma-Ansicht), `rohr` (genau ein Vollkreis = Kreisrohr), `verbunden` (Kreis/Bogen haengt an einem anderen Element).
- **Moeglichkeiten:** `find_closed_cells` liefert fuer das Kreisrohr A_m = pi R^2, Int ds/t = 2 pi R/t; `berechneSchubmittelpunkt` den Mittelpunkt; `berechneTorsionsResultat` lehnt Kreise neben anderen Elementen und angeschlossene Boegen ab.
- **Grenzen:** Kreisbogen-Traegheitsmomente ueber trigonometrische Integrale, keine geschlossene Fallback-Naeherung bei extrem kleinem Radius (`R < 1e-5` -> Nullwerte).

### `berechneNumerisch(elem, index_of_elem)`
- **Zweck:** Rasterbasierte numerische Naeherung von A/ys/zs/Iy/Iz/Iyz fuer Elemente ohne geschlossene Formel (z. B. nach "Addieren (Numerisch)" bei Ueberlappung).
- **Moeglichkeiten:** Beruecksichtigt bereits vorhandene ueberlappende/vorherige Elemente (Loch- und Additions-Logik).
- **Grenzen:** Feste Rasterung `40x40`; Genauigkeit sinkt bei sehr duennen/kleinen Elementen; markiert System als `is_numeric_system = true` (Warnhinweis in der UI).

---

## 4. Kollision, Loecher & Ueberlappung

### `is_point_inside(elem, u, v)`
- **Zweck:** Punkt-in-Element-Test fuer alle Massiv-/Duennwand-Typen (inkl. `massiv_linie`-Bandbereich, Kreisbogen-Winkeltest).
- **Grenzen:** Fuer `sector`/`segment`/`duenn_kreis_bogen` wird der Winkeltest ueber `atan2`-Differenzen gemacht; bei extrem kleinen Radien numerisch instabil.

### `getBoundingBox(elem)`
- **Zweck:** Achsparallele Bounding-Box eines Elements (fuer Zoom, numerische Integration, Kernflaechen-Punktesammlung).
- **Moeglichkeiten:** Sektor, Kreisabschnitt und duenner Kreisbogen: exakte Box aus Bogenendpunkten, den im Winkelbereich liegenden Kreispunkten bei 0/90/180/270 Grad und (nur Sektor) dem Mittelpunkt.

### `checkOverlapStatus(new_elem)`
- **Zweck:** Prueft, ob ein neues Massiv-Element ein bestehendes vollstaendig ueberdeckt (`"inside"`), teilweise ueberlappt (`"partial"`) oder frei steht (`"none"`).
- **Moeglichkeiten:** Steuert die Lochabzugs-/Additions-Abfrage (`mode = "overlap_prompt"`).
- **Moeglichkeiten:** Testpunkte in den Zellmitten eines 20x20-Rasters ueber der Bounding-Box. Ein Punkt zaehlt nur, wenn er samt kleiner Umgebung (`eps`) in beiden Formen liegt; gemeinsame Kanten oder Beruehrpunkte (z. B. Halbkreis auf Rechteck) sind daher keine Ueberlappung. `"inside"` ab 99,5 % der Testpunkte.
- **Grenzen:** Stichprobenbasiert; Ueberlappungen schmaler als etwa 1/20 der Elementgroesse koennen uebersehen werden.

---

## 5. Duennwand-Graph, Schubfluss & Torsion (Kernstueck)

Grundsatz: Es wird gerechnet, was nach TM2 bestimmt ist. Fuer eine geschlossene Zelle ohne passende
Symmetrieachse kommt q0 aus der Vertraeglichkeit (∮ q/(G t) ds = 0), also ohne Naeherung. Abgelehnt
werden nur mehrzellige Profile und die Torsion massiver Querschnitte.

### `duennGraph(achse_u, achse_v)`
- **Zweck:** Mittelliniengraph aller geraden `duenn_elemente`. Elemente werden an Schnitt- und Beruehrpunkten (T-Knoten, Kreuzungen, kollineare Ueberlappungen) und optional an den Achsen `u = achse_u`, `v = achse_v` geteilt. Doppelt gezeichnete Kanten werden zu einer Kante mit addierter Dicke zusammengelegt.
- **Grenzen:** Duennwandige Kreise/Boegen werden nicht als Kanten abgebildet (`nicht_gerade`); Schub wird dann abgelehnt.

### `duennZellen(nodes, edges)`
- **Zweck:** Schneidet freie Aeste ab und bestimmt die Zellenzahl `Kanten - Knoten + Komponenten` des Restgraphen. Bei genau einer Zelle: Umlauf mit `A_m`, `∮ds/t`, `t_min`, Umlaufsinn je Kante und `I_T = 4 A_m^2/∮ds/t` (Bredt).

### `duennSymmetrie(nodes, edges, ys, zs)`
- **Zweck:** Prueft Spiegelsymmetrie des Graphen inklusive Wanddicken zur senkrechten Achse `u = ys` (`sym_v`) und zur waagerechten Achse `v = zs` (`sym_h`). Ersetzt die fruehere Pruefung `|I_yz| < 1e-5`, die keine Symmetrie nachweist.
- **Verfahren:** Jede Kante wird in 13 Punkten abgetastet; der gespiegelte Punkt muss auf einer Kante gleicher Dicke liegen (Punkt-auf-Strecke, Toleranz `1e-6 * Ausdehnung`). Dadurch ist die Erkennung unabhaengig davon, wie die beiden Haelften in Segmente geteilt sind (frueher wurde Kante gegen Kante verglichen, eine anders unterteilte Haelfte galt als unsymmetrisch).

### Zellschnitt in `berechneDuenneSchubspannung` (`schnittAufAchse`)
- **Zweck:** Der Schnitt der geschlossenen Zelle wird auf die Symmetrieachse gelegt (Knoten mit `|u - ys| < tol` bzw. `|v - zs| < tol`, der durch die Kantenteilung in `duennGraph(ys, zs)` bereits existiert). Dort ist der Schubfluss null, die Laufvariable startet bei `S = 0`. Die Achse richtet sich nach der groesseren Querkraftkomponente. Erfolg steht in `info.schnitt_auf_achse`, der Pfad bekommt `start_kind = "cut_sym"` (Anzeige "Start (Symmetrieachse)"), sonst `"cut"`.
- **Grenzen:** Schneidet die Achse die Zelle nicht oder sind ihre Kanten schon verbraucht, wird wie frueher an beliebiger Stelle geschnitten; `berechneSchubspannungsResultate` warnt dann.

### Zellkorrektur in `berechneDuenneSchubspannung`
- **Zweck:** Die geschlossene Zelle wird an beliebiger Stelle aufgeschnitten; das statische Moment der Zelle darf danach um eine Konstante verschoben werden. Aus der Symmetrie folgt `S(P) + S(P') = 0` im Umlaufsinn (Schnitt auf der Symmetrieachse, dort ist `q = 0`). Korrigiert werden jetzt `Sz` (waagerechte Symmetrieachse, gehoert zu Q_a) und `Sy` (senkrechte Achse, Q_b); `tau_a`/`tau_b` werden anschliessend aus den korrigierten `S` neu gebildet. Frueher wurde nur `tau` korrigiert, die angezeigten `S`-Verlaeufe blieben auf den zufaelligen Schnitt bezogen.
- **Vertraeglichkeit (4b, `korrigiereVertraeglich`):** Fehlt die Symmetrieachse zu einer Richtung (oder wird kein Spiegelpartner gefunden), folgt die Konstante aus ∮ q/(G t) ds = 0. Mit q = -Q (I S + I_yz S')/det und regulaerer Matrix zerfaellt das in ∮ Sz/t ds = 0 und ∮ Sy/t ds = 0: `umlaufintegrale(key)` bildet ∮ S/t ds und ∮ 1/t ds mit Simpson je Kante (S ist dort quadratisch, exakt; darum jetzt gerade Intervallzahl je Kante), die Verschiebung ist `s0 = -∮S/t / ∮1/t`, angebracht mit `cell_sign`. Symmetrie hat Vorrang; der Testschalter `schub_immer_vertraeglich` erzwingt die Vertraeglichkeit auch bei Symmetrie (Gegenprobe, Test 30). Ergebnis in `info.zelle_s_korrigiert.vertraeglich`.
- **Grenzen:** Ist ∮ ds/t nicht auswertbar, meldet die Funktion "Umlaufintegral der Zelle nicht auswertbar". Ohne erkannte Symmetrie bzw. bei Querkraft quer zur einzigen Achse warnt `berechneSchubspannungsResultate` (mit dem Zusatz, dass S und tau trotzdem richtig sind).

### `find_closed_cells()`
- **Zweck:** Bredt fuer genau eine geschlossene Zelle (auch mit offenen Aesten und T-Knoten). Rueckgabe `I_T, A_m, Zellenzahl, Info`.
- **Grenzen:** Mehrzellige Profile liefern `I_T = 0, A_m = 0` und die Zellenzahl; Aufrufer lehnen sie ab.

### `berechneDuenneSchubspannung(Qa, Qb)`
- **Zweck:** Schubfluss im duennwandigen Profil (interne Querkraefte `Qa` in u-, `Qb` in v-Richtung).
- **Ablauf:** (1) von allen freien Enden (q = 0), (2) an Verzweigungen mit nur noch einem offenen Ast Start mit der Summe der angekommenen statischen Momente, (3) eine geschlossene Zelle an beliebiger Stelle aufschneiden, (4) Zellschubfluss `q0` je Komponente aus der Symmetrie: fuer eine Querkraft parallel zur Symmetrieachse ist q im Umlaufsinn antisymmetrisch, `q(P) + q(P') = 0` fuer Spiegelpunkte. Das erfuellt automatisch die Vertraeglichkeit `∮τ ds = 0` (im Test geprueft).
- **Formel:** mit `I_yz`-Kopplung `τ_a = -Q_a (I_y S_a + I_yz S_b)/((I_y I_z - I_yz^2) t)`, `τ_b = -Q_b (I_z S_b + I_yz S_a)/((I_y I_z - I_yz^2) t)` (Gross-Vorzeichen `I_yz = -∫uv dA`; fuer `I_yz = 0` die bekannte Form `τ = -Q S/(I t)`).
- **Rueckgabe:** `maximum, samples, paths, fehler, info`. Samples tragen zusaetzlich `in_cell`, `cell_sign` (Umlaufsinn), `edge_i`, `fwd`.
- **Grenzen:** mehrzellig: `nil` und Begruendung in `fehler`. Unsymmetrische Zellen und Querkraft quer zur einzigen Achse werden ueber die Vertraeglichkeit gerechnet (`info.erkannt` nennt die gefundenen Achsen fuer die Warnung).

### `berechneSchubmittelpunkt()`
- **Zweck:** Schubmittelpunkt aus dem Moment der Schubfluesse fuer Einheitsquerkraefte. Offene Profile und einzellige Zellen: beide Koordinaten (q0 aus Symmetrie oder Vertraeglichkeit); `known_u`/`known_v` bleiben nur bei mehrzelligen Profilen falsch. Das Moment wird je Kante mit Simpson gebildet (Hebelarm linear, q quadratisch, Produkt kubisch: exakt; das Trapez liess den Schubmittelpunkt um ~1e-5 wandern, was in der Verwoelbung sichtbar wurde). Ergebnis wird bis zur naechsten `berechneSystem()`-Rechnung zwischengespeichert (`shear_center_cache`).

### `berechneSchubMomentTabelle()`
- **Zweck:** Pro Element aufgeschluesselte resultierende Schubkraefte und Momentbeitraege fuer Einheitslasten, mit signiertem Hebelarm `r = M/F`.
- **Grenzen:** Statisch unbestimmte Lastrichtungen liefern keine Beitraege.

### `berechneTorsionsResultat(moment)`
- **Zweck:** Torsion nur fuer rein duennwandige Profile: offen `I_T = Σ ξ/3 h t^3`, `τ_max = M_T t_max/I_T`; einzellig geschlossen (Bredt) `τ_max = M_T/(2 A_m t_min)` mit `t_min` der Zellwaende.
- **Grenzen:** Massive oder gemischte Querschnitte (keine Prandtl-Loesung) und mehrzellige Profile: `nil` mit Meldung.

### `aktualisiereTorsionsverlauf(result)`, `torsionTauAtSample(sample)`, `combinedTauAtSample(sample)`
- **Zweck:** Torsionsanteil je Stuetzstelle: Zellwaende Bredt `q_T/t` im Umlaufsinn (`cell_sign`), offene Teile `M_T t/I_T`. Kombination: in der Zelle vorzeichenrichtig, in offenen Teilen als Betragssumme.

### `berechneKraftTorsion()`
- **Zweck:** Torsionsmoment der Kraefte in der Querschnittsebene um den **Schubmittelpunkt** (`M_x = Δu F_v - Δv F_u`), danach `berechneTorsionsResultat`.
- **Grenzen:** Ist die benoetigte Koordinate des Schubmittelpunkts statisch unbestimmt, wird nicht gerechnet (Meldung).

### `woelb.berechne(M, G)`
- **Zweck:** Verwoelbung u_x(s) duennwandiger Profile nach Formelsammlung Kap. 6: `u_x = Int [MT/(2 G A_m h) - r_perp theta] ds + c`, `theta = MT/(G I_T)`. Pol ist der Schubmittelpunkt; `r_perp = (u-u_M) t_v - (v-v_M) t_u` (Kreuzprodukt, positiv im Umlaufsinn des Bredt-Schubflusses, `ccw_dir`). Geschlossen: `I_T` nach Bredt und Bredt-Anteil `sign * qT/(G h)` je Zellkante; offen: `I_T = r.It` und kein Bredt-Anteil.
- **Ablauf:** Graph aus `duennGraph(ys, zs)`, Breitensuche ab einem Knoten auf einer Symmetrieachse (sonst Knoten 1); je Kante geschlossene Integration (`u(s) = u0 + bredt s - theta (r1 s + (r2-r1) s^2/(2L))`), Stuetzstellen wie beim Schub (gerade Intervallzahl), nicht zusammenhaengende Teile bekommen eigene Startknoten. `c` aus `Int u h ds = 0` mit Simpson je Kante. Rueckgabe u. a. `samples` (mit `ux`, `r_perp`), `paths`, `theta`, `It`, `Am`, `closed`, `pol`, `max_abs/max_u/max_v`, `schluss` (Probe: Umlauf der Zelle schliesst).
- **Grenzen:** `nil, fehler` fuer massiv/gemischt, Kreisboegen, mehrzellig, `I_T = 0`, unbestimmten Schubmittelpunkt. Keine Woelbkrafttorsion.

### `woelb.oeffnen()` / `woelb.eingabe()`
- **Zweck:** Dialog unter `b` -> 7: Schritt 1 `MT` in `moment_unit` (vorbelegt mit `berechneKraftTorsion().M`, falls Kraefte eingetragen sind), Schritt 2 `G` in N/mm^2 (vorbelegt 81000). Ergebnis in `woelb.results`, Ansicht `woelb.visible`; der Schubverlauf wird ausgeblendet. Offenes Profil: Warnung "nicht in der Formelsammlung".
- **Grenzen:** `woelb.M` wird bewusst nicht in `torsion_M`/`torsion_results` uebernommen; `Esc` schliesst Dialog bzw. Ansicht und verwirft `woelb.results`, `berechneSystem()` ebenfalls (Geometrie geaendert).

### `berechneSchubspannungsResultate(input_Qa, input_Qb)`
- **Zweck:** Gesamtfunktion Schub. Eingaben beziehen sich auf das angezeigte KOS und werden intern gedreht; eingetragene Kraefte kommen hinzu. Massiv: `τ = Q S/(I b)` ueber waagerechte/senkrechte Schnitte (Breiten auch fuer Sektor, Kreisabschnitt und dicke Linie ueber `massiv_outline_polygon`), nur bei `I_yz = 0`. Gemischt massiv/duennwandig: abgelehnt. Begruendungen landen in `schub_grund` bzw. `status`.

---

## 6. Systemberechnung, KOS-Verschiebung & Schnittgroessen aus Kraeften

### `berechneSystem()`
- **Zweck:** Zentrale Funktion, die nach jeder Geometrieaenderung aufgerufen wird: aggregiert alle Massiv- und Duennwand-Elemente zu `system_results` (Gesamtflaeche, Schwerpunkt `ys/zs`, `Iy/Iz/Iyz` bezogen auf den Schwerpunkt, Haupttraegheitsmomente `I1/I2` + Winkel, Widerstandsmomente `Wu/Wv`, offene/geschlossene Torsionskonstante).
- **Moeglichkeiten:** Speichert je Element zusaetzlich lokale Hauptachsen (`I_eta/I_zeta/alpha`) fuer die Einzelwerte-Tabelle. Ruft am Ende automatisch `berechneKraftTorsion()` und `kern_build()` (falls Kernflaechen-Modus aktiv) auf.
- **Grenzen:** `Iy/Iz/Iyz` in `system_results` sind **immer schwerpunktbezogen** (`IyS/IzS/IyzS`); die am aktuellen KOS-Ursprung dargestellten Werte in der Ergebnisspalte werden erst in `drawSpreadsheet` per Steiner-Rueckrechnung gebildet. Bei Flaeche `≈ 0` wird `system_results = nil` gesetzt (keine Teilergebnisse).

### `verschiebeKOS(du, dv)`
- **Zweck:** Verschiebt den KOS-Ursprung um `(du, dv)` im internen KOS: alle Element-, `pending`- und Kraftpunkte um `-(du, dv)` (gemeinsame Punkte nur einmal), dazu `ox, oy` um `(du*scale, -dv*scale)`, damit der Querschnitt auf dem Bildschirm stehen bleibt. Danach `berechneSystem()`. Aufgerufen aus dem Obermenue Seite 2, Zeilen 2/3 (Eingabe in `length_unit`, Richtung ueber `coordinatesFromDisplay`).
- **Grenzen:** Ohne Elemente und Kraefte nur ein Hinweis. `verschiebeKOSZumSchwerpunkt` fuehrt die Ansicht nicht mit (dort springt der Querschnitt zum KOS).

### `verschiebeKOSZumSchwerpunkt()`
- **Zweck:** Verschiebt alle Punkte, Kraefte und damit den Koordinatenursprung in den aktuellen Schwerpunkt.
- **Moeglichkeiten:** Verschiebt jeden gemeinsamen Knotenpunkt (z. B. bei verbundenen Duennwand-Elementen) nur **einmal** (`shifted_points`-Tabelle), damit topologisch verbundene Elemente zusammenhaengend bleiben.
- **Grenzen:** Reine Verschiebung, keine Rotation; muss nach Aufruf `berechneSystem()` erneut ausfuehren (macht die Funktion selbst).

### `berechneKraftResultanten()`
- **Zweck:** Resultierende Normalkraft `N` sowie Momente `Ma`/`Mb` aus allen platzierten Kraeften (nur `fc`-Komponente, senkrecht zur Querschnittsflaeche) um den Schwerpunkt.
- **Grenzen:** Vorzeichenkonvention haengt von `plane`/`swapped` ab (`orientation`-Tabelle); nur fuer die Sigma-x-Berechnung gedacht, nicht fuer Schubspannungen.

---

## 7. Sigma-x (Normal-/Schiefe Biegung) & Kernflaeche

### `berechneSigmaExtrema(N, My_Nmm, Mz_Nmm)`
 **Moeglichkeiten:** Verarbeitet Momente intern einheitlich in `Nmm`; die Eingabemaske rechnet den Wert genau einmal mit der aktuell angezeigten Momenteneinheit (`Nm`, `Nmm`, `kNm` usw.) um. Die Ergebnisanzeige rechnet den internen Wert anschließend in die gewählte Anzeigeeinheit zurück.

### `finishSigmaCalculation(Mz_Nmm)`
 **Moeglichkeiten:** Verwendet die bereits einmalig in `Nmm` umgerechneten Eingaben und addiert die aus äußeren Kräften berechneten Momente ebenfalls in `Nmm`, ohne eine zweite Einheitenumrechnung: Normalkraftanteil aus `berechneKraftResultanten`, Querkraftanteil aus `sigmaEingabe.querkraftMomente(sigmaEingabe.versatz)`. Speichert zusaetzlich `quer_Ma_Nmm`, `quer_Mb_Nmm`, `versatz`, `mit_querkraft` in `sigma_results`.

### `sigmaEingabe` (Tabelle) mit `querkraftMomente(e)`, `hatQuerkraefte()`, `stabachse()`, `aufforderung()`
- **Zweck:** Zustand der σx-Maske (`felder` = Liste aus `"N"`, `"Ma"`, `"Mb"`, `"x"`; `versatz` in mm) und ihre Hilfen. `querkraftMomente(e)`: `M_u = -|e| Σ F_v`, `M_v = |e| Σ F_u` (intern; im angezeigten KOS `My = -Δx Fz`, `Mz = Δx Fy`), unabhaengig von Drehung und Ebene, weil beide Seiten gleich gedreht werden. `hatQuerkraefte` entscheidet, ob das Feld `Δx` gefragt wird; `stabachse` liefert den Namen der Achse senkrecht zur Querschnittsebene (fuer `yz` also `x`).
- **Grenzen:** Ein Versatz fuer alle Kraefte (eine Kraftebene). Die Seite des Schnitts spielt fuer den Querkraftanteil keine Rolle (Beweis im Kommentar und in der Feature-Doku); Normalkraft- und Querkraftvorzeichen der Schubrechnung gehen weiter davon aus, dass die Kraefte am positiven Teil angreifen.

### `sigmaEingabe.kennwerte(sr)` / `lineareForm(...)` / `nulllinie(...)` / `zusatzzeilen(sr)`
- **Zweck:** Erweiterung der σx-Ergebnistabelle. `kennwerte` bildet aus der internen Spannungsebene (`s_u`, `s_v` wie in `drawSigmaOverlay`) den Gradienten im angezeigten KOS (`cy`, `cz` ueber `coordinatesForDisplay`), die Konstante `c0` am KOS-Ursprung, den Hauptachsenwinkel `phi = alphaForDisplay(alpha)`, `I_eta`/`I_zeta` (Formelsammlung 1.3), die Momente `M_eta`/`M_zeta` (wie Koordinaten gedreht) und den Gradienten im HAS (`c_eta`, `c_zeta`). `lineareForm` schreibt `a + b·x1 - c·x2` mit vier Stellen, `nulllinie` loest `a + b x1 + c x2 = 0` nach `x2` (oder `x1 = n`). `zusatzzeilen` liefert die Zeilen fuer die Tabelle (Zeilentypen `{Name, Wert}`, `{kopf = ...}`, `{voll = ...}`); Koeffizienten werden in die Laengeneinheit der Anzeige umgerechnet.
- **Grenzen:** Winkel `phi` gilt fuer `I_eta = I_1`; bei `I_1 = I_2` ist jede Richtung Hauptachse (dann `phi = 0`).

### `openSigmaInput(oblique)` / `enterSigmaInput()`
- **Zweck:** Mehrstufige Eingabemaske fuer `N`, `My`, `Mz`, bei eingezeichneten Querkraeften zuletzt `Δx` (Betrag). Berechnungsmenue Zeile 3 ruft sie direkt mit `oblique = true` auf; das fruehere Untermenue (Seite 7 mit „σx aus Kraeften“, `openSigmaFromForces`) war nicht erreichbar und ist entfernt. Platzierte Kraefte addiert `finishSigmaCalculation` immer; σx nur aus Kraeften heisst also `N`, `My`, `Mz` = 0. `drawSigmaInput` baut die Maske aus `sigmaEingabe.felder` (28 px Zeilenabstand, Hinweiszeile fuer `Δx`), damit auch vier Felder auf 212 px passen.
- **Moeglichkeiten:** Bereits bestaetigte Werte werden im Eingabedialog wieder in der aktuell eingestellten Anzeigeeinheit dargestellt; die interne Umrechnung in `N`/`Nmm` bleibt davon getrennt.
- **Grenzen:** Reine Texteingabe ueber `evaluate_input`; keine Bereichspruefung der eingegebenen Werte.

### `qsHinweis` (Tabelle) mit `melde(text)`, `xiNoetig(ergebnis)`, `xiText()`, `pruefeDicke()`
- **Zweck:** Hinweise, die man nicht uebersehen soll. `melde` haengt an eine schon offene Meldungsbox an (statt sie zu ueberschreiben) und nie doppelt. `xiNoetig` ist wahr fuer ein offenes Torsionsergebnis bei `torsion_xi = 1`; aufgerufen im Torsionsdialog, in `enterShearInput` (MT), in `berechneSchubspannungsResultate` (Kraft-Torsion, in die gesammelten Hinweise) und bei der Verwoelbung offener Profile -- nicht in `berechneSystem`. `pruefeDicke` (Taste `e`, Menue b -> 1) meldet einmalig, wenn alle duennwandigen Elemente die Standarddicke haben; der Merker `dicke_gezeigt` faellt in `loescheAllesQS` und in `berechneSystem` bei leerem Profil zurueck.

### σx-Tabelle scrollen (`on.arrowKey`)
- **Zweck:** Bei `showTable` mit `sigma_results` scrollen hoch/runter `sigma_scroll_y` in 20-px-Schritten, begrenzt auf `sigmaEingabe.inhaltHoehe` (Tabellenhoehe, beim Zeichnen gemerkt). Der fruehere Verlauf `drawSigmaDistribution` unter der Tabelle ist entfernt.

### `kern_dual(nu, nv, d)`
- **Zweck:** Dualitaetsbeziehung: wandelt eine neutrale Faser (Gerade `nu*(y-ys)+nv*(z-zs)=d`) in den zugehoerigen Kernpunkt um (Basis der Kernflaechen-Konstruktion).
- **Grenzen:** Setzt `system_results` mit gueltigem `A, Iy, Iz, Iyz` voraus; keine Pruefung auf `d ≈ 0` (Aufrufer filtern das).

### `kern_collect_points()`
- **Zweck:** Sammelt alle relevanten Randpunkte (inkl. Kreis-/Bogen-Stuetzstellen) aller **nicht-Loch**-Massiv- und aller Duennwand-Elemente fuer Kernflaechen- und Sigma-Extremwertberechnung.
- **Grenzen:** Bogen-Abtastung mit fester Schrittweite (~10° pro Stuetzpunkt); bei sehr kleinen Radien evtl. zu grob.

### `kernHAS.richtungen()` / `kernHAS.koordinaten(u, v)`
- **Zweck:** Hauptachsensystem wie in der σx-Tabelle (`sigmaEingabe.kennwerte`): Winkel `phi = alphaForDisplay(system_results.alpha)` von der angezeigten y-Achse, η = (cos φ, sin φ), ζ = (−sin φ, cos φ) im angezeigten KOS, über `coordinatesFromDisplay` in interne Einheitsvektoren umgerechnet. `koordinaten` projiziert einen internen Punkt relativ zum Schwerpunkt auf η und ζ.
- **Verwendung:** gezeichnete Hauptachsen 1/2 im KOS-Bild, Achsenabschnitte der umhuellenden Geraden (`drawKern`, Modus 1: `t = d / (n·e)` je Achse, sonst `drawInfArrow` entlang der Achse) und HAS-Koordinaten der Kernpunkte (Modus 2, zusammen mit den KOS-Koordinaten).
- **Grenzen:** Bei I_1 = I_2 ist jede Richtung Hauptachse; dann gilt `alpha = 0`, die Achsen liegen parallel zum KOS.

### `kern_build()`
- **Zweck:** Baut aus der konvexen Huelle der Randpunkte (Monotone-Chain-Algorithmus) die Kernflaechen-Geometrie: umhuellende Geraden (`kern_lines`) und Kernflaechen-Polygon (`kern_pts`/`kern_vertices`), inkl. Sonderfall Vollkreis und Bogenkanten.
- **Grenzen:** Basiert auf der konvexen Huelle der Randpunkte – bei stark konkaven Querschnitten (z. B. L-Profile) ist das nur eine Naeherung der wahren Kernflaeche, keine exakte Loesung fuer beliebige nicht-konvexe Raender.

---

## 8. Zeichnen / GUI (Canvas-Ausgabe)

### `drawAxes(gc)`
- **Zweck:** Zeichnet das grüne KOS-Kreuz (mit aktueller Rotation), den Schwerpunkt (rotes Kreuz) und die violett gestrichelten Hauptachsen 1/2.

### `drawGrid(gc, w, h)`
- **Zweck:** Zeichnet das Punktraster im sichtbaren Bereich.
- **Grenzen:** Feste Rasteranzahl (61x49 Punkte um den Ursprung), nicht dynamisch an Zoom/Fenstergroesse angepasst.

### `drawShapePath(gc, elem)`
- **Zweck:** Zeichnet die Grundflaeche eines Massiv-/Duennwand-Elements (fuer alle unterstuetzten Typen) inkl. Fuellung.

### `drawLocalAxes(gc, elem)`
- **Zweck:** Zeichnet die lokalen Hauptachsen (`eta`/`zeta`) eines einzelnen Elements bei Auswahl/Hover.

### `drawSpreadsheet(gc, w, h)`
- **Zweck:** Zeichnet die rechte Ergebnisspalte (Flaeche, Schwerpunktkoordinaten, `Iy/Iz/Iyz` am aktuellen KOS-Ursprung, Traegheitsradien, Widerstandsmomente, `I1,S/I2,S` schwerpunktbezogen, Torsionskonstanten, Schubspannungs-/Torsions-Zusatzwerte).
- **Grenzen:** Feste Spaltenbreite (`width = 210`); bei sehr vielen Zusatzzeilen (Schub+Torsion gleichzeitig) muss ggf. gescrollt werden (`results_scroll_y`).

### `drawSigmaInput/ drawShearInput / drawTorsionInput(gc, w, h)`
- **Zweck:** Zeichnen die jeweiligen mehrstufigen Texteingabemasken fuer σx-, Schub- und Torsionsberechnung.

### `verlaufAbschnitte(quelle)` / `drawVerlauf(gc, quelle)` / `drawLaufrichtung(gc, paths, hovered, korrigiert)`
- **Zweck:** Gemeinsame Verlaufsdarstellung fuer Schub und Verwoelbung. `quelle` = `{ id, key, samples, wert(sample), anzeige(wert), titel, hovered, maximum, farbe }`. `verlaufAbschnitte` gruppiert die Stuetzstellen nach `path_id:segment`, sortiert nach `s`, wertet `wert` je Stuetzstelle einmal aus und merkt den Pixelversatz normal zur Wand (`fx, fy`, 36 px fuer den betragsgroessten Wert); der Cache (`verlauf.cache`, Breite `verlauf.breite`) haengt an `id`, `key`, `rotation` und `hovered`. `drawVerlauf` rechnet je Frame nur `toScreen`, duennt auf etwa einen Punkt je 1,5 px aus und zeichnet **eine Polylinie je Abschnitt**, dazu Wandverbinder, Endwerte, min/max (aus allen Stuetzstellen). `drawLaufrichtung` zeichnet Startmarken (Start / Start (Symmetrieachse) / Schnitt / Schnitt (q0 aus Verträglichkeit) / Schnitt (q0 offen)) und Laufrichtungspfeile.
- **Grenzen:** Diagrammbreite ist ein fester Pixelwert; die Ausduennung betrifft nur die gezeichneten Punkte, nicht die Rechnung.

### `drawShearProfileLegacy(gc)` / `drawShearProfile(gc)`
- **Zweck:** Baut aus `shear_results` die `quelle` fuer `drawVerlauf` (Titel und `profile_value` je `shear_view_mode` 1–10, Anzeigeeinheit) und ruft `drawLaufrichtung`. `drawShearProfile` bleibt der Wrapper aus `on.paint`.
- **Grenzen:** `key` enthaelt `shear_view_mode`, `torsion_results` und `max_tau_total`, damit Torsionsaenderungen den Cache erneuern.

### `woelb.zeichneDialog(gc, w, h)` / `woelb.zeichne(gc)`
- **Zweck:** Eingabemaske (MT, G) und Verwoelbungsansicht: `drawVerlauf` mit `wert = ux` in Gruen, dazu der Pol (Schubmittelpunkt) mit MT als Drehpfeil (gegen den Uhrzeigersinn fuer MT > 0, wie der Bredt-Schubfluss) und eine Fusszeile mit der verwendeten Formel. Kraefte werden in dieser Ansicht nicht gezeichnet.
- **Grenzen:** Nur sichtbar, solange `woelb.visible`; `Esc` beendet die Ansicht.

### `drawShearSelector(gc, w, h)`
- **Zweck:** Zeigt das Auswahlmenue (Tasten 0–9) fuer die 10 verfuegbaren Schubspannungs-/Momentenverlaeufe, einspaltig untereinander, Kastengroesse passt sich automatisch an die Eintragsanzahl an.

### `drawSigmaResultsTable(gc, w, h)`
- **Zweck:** Tabellarische Detailausgabe aller σx-Zwischenwerte (`N`, `My`, `Mz`, `A`, `Iy/Iz/Iyz`, Extremstellen) mit Scroll-Unterstuetzung.
- **Spaltenbreite:** Die Wertespalte (`split`) steht hinter der breitesten Beschriftung (Schrift 8, `getStringWidth`), hoechstens so weit rechts, dass die breitesten Werte noch daneben passen; die lokale Hilfe `schreibe` setzt einzelne Texte, die trotzdem zu breit sind, in Schrift 7 bzw. 6. Volle Zeilen (`voll`) bekommen die ganze Tabellenbreite.

### `drawSigmaCrossSection(gc, w, h)`
- **Zweck:** Zweigeteilte Ansicht: eingefaerbter Querschnitt (Zug/Druck-Heatmap, feste 28x22-Rasterung) plus separates Spannungsverlaufs-Diagramm.
- **Grenzen:** Rasteraufloesung fest (28x22 Zellen), keine adaptive Verfeinerung an Elementraendern.

### `drawSigmaOverlay(gc, w, h)`
- **Zweck:** Alternative Vollbild-Overlay-Darstellung der σx-Verteilung direkt ueber der Zeichenflaeche (inkl. neutraler Faser, Hauptachsen, Extremwert-Markierungen), adaptive Rasterung je nach Zoomstufe.
- **Grenzen:** Rasterzellenzahl an `scale` gekoppelt (12–60 Zellen je Achse); bei sehr grossem Zoom kann die Heatmap grob wirken.

### `drawSigmaExtrema(gc)`
- **Zweck:** Zeichnet nur die beiden Extrempunkte (`σx,max`/`σx,min`) als farbige Punkte in der normalen Querschnittsansicht.

### `drawMenu(gc, w, h)` / `buildMenuItems()`
- **Zweck:** `buildMenuItems()` liefert die Textzeilen der aktuellen Menueseite (`menuPage`), `drawMenu` zeichnet sie inkl. Hervorhebung der aktiven Zeile und Inline-Eingabefeld.
- **Lage:** Der Kasten steht links (`left = 5`); ebenso die Schubverlaufs-Auswahl `drawShearSelector`, die in `on.paint` zuletzt gezeichnet wird und damit ueber Kraeften und Achsen liegt.
- **Grenzen:** Feste Kastenbreite (`220px`); bei sehr langen Zeilen (z. B. Elementbearbeitung mit vielen Punkten) kein Zeilenumbruch, nur Kuerzung durch Fensterbreite.

### `drawOverlapPrompt(gc, w, h)`
- **Zweck:** Zeigt den Abfrage-Dialog bei Flaechenueberlappung (Abziehen/Addieren/Verwerfen).

### `drawTable(gc, w, h)`
- **Zweck:** Scrollbare Einzelwerte-Tabelle je Element (A, Schwerpunkt, lokale und globale Traegheitsmomente inkl. Steiner-Anteilen).
- **Grenzen:** Spaltenbreite fest (`75px`), keine automatische Skalierung bei sehr vielen Elementen (nur horizontales/vertikales Scrollen ueber `table_scroll_x/y`).

### `drawShearMomentTable(gc, w, h)`
- **Zweck:** Zeigt die Tabelle aus `berechneSchubMomentTabelle()` (Teilkraefte je Element + Gesamtmoment) fuer die Schubmittelpunkt-Kontrolle.

### `drawInfArrow(gc, u0, v0, du, dv, label)`
- **Zweck:** Zeichnet einen "ins Unendliche" weisenden Pfeil (fuer Kernflaechen-Geraden parallel zu einer Achse, die die Achse nicht schneiden).

### `drawKern(gc, w, h)`
- **Zweck:** Zeichnet je nach `kernMode` (1 = umhuellende Geraden, 2 = Kernflaeche) die entsprechende Geometrie inkl. Hover-Hervorhebung und Schnittpunkt-Koordinatenanzeige.

---

## 9. Menü- & Interaktionslogik

### `qsWerte` (Tabelle) mit `aktiv()`, `signatur()`, `pruefe()`, `anwenden()`, `anzeige()`, `namen()`
- **Zweck:** Manuell ueberschriebene Schwerpunktwerte `A`, `Iy`, `Iz`, `Iyz` im internen KOS (Eingabe im Obermenue Seite 3 = `menuPage 10`, Umrechnung aus dem angezeigten KOS: bei Drehung 90/270 tauschen `Iy`/`Iz`, `Iyz` wechselt das Vorzeichen). `pruefe()` laeuft am Anfang von `berechneSystem`: weicht `signatur()` (Typen, Dicken, Marken, Punkte relativ zum ersten Punkt) von der gemerkten ab, fallen die Werte weg (einmaliger Hinweis). `anwenden()` laeuft nach dem Aufbau von `system_results`: setzt `A`, `Iy/IyS`, `Iz/IzS`, `Iyz/IyzS`, bildet `I1`, `I2`, `alpha`, `Wu`, `Wv` (mit den gespeicherten Randabstaenden `e_u`, `e_v`) neu, merkt die geometrischen Werte in `r.geo` (auch `ys`, `zs`). `anzeige()` liefert die Marken fuer die angezeigten Groessen (fuenfter Rueckgabewert: Schwerpunkt manuell), `namen()` die Liste fuer Hinweise.
- **Schwerpunkt (`ys`, `zs`):** Menue Seite 3, Zeilen 5/6 (Zeile 7 wiederherstellen ueber `loescheManuelleWerte()`, Zeile 8 zurueck). Eingabe im angezeigten KOS (`coordinatesFromDisplay`, `input_to_internal`), gespeichert relativ zu `qsWerte.bezugspunkt()` (erster Punkt des ersten massiven, sonst duennwandigen Elements), damit er beim KOS-Verschieben am Querschnitt haengen bleibt. `anwenden()` setzt `r.ys`, `r.zs` und bildet `e_u`, `e_v` aus `r.bbox` neu. Damit nehmen `berechneKraftResultanten` (Hebel der Normalkraefte), σx, Kernflaeche und `Wu`/`Wv` den gesetzten Schwerpunkt. `qsWerte.geoSicht(r)` liefert eine Sicht mit `r.geo.ys/zs` (Metatable auf `r`); sie wird in `displayedMomentDensity`, `berechneDuenneSchubspannung`, `berechneSchubmittelpunkt`, `woelb.berechne`, `berechneSchubspannungsResultate`, `berechneSchubMomentTabelle` und der Einzelwerte-Tabelle benutzt, weil dort ueber die gezeichneten Waende integriert wird und das statische Moment nur um deren eigenen Schwerpunkt null ist. Traegheitsmomente werden nicht verschoben (kein Steiner). Test: `querschnitt.lua` Fall 47.
- **Grenzen:** Der Schwerpunkt, die statischen Momente und `I_T` bleiben geometrisch. Eingaben muessen `A, I_y, I_z > 0` und `I_y I_z - I_yz^2 > 0` erfuellen.

### `ftm_bezug` (Obermenue Seite 2, Zeile 4 `FTM-Bezug`)
- **Zweck:** `"schwerpunkt"` (Standard) oder `"kos"`. Steuert die Ergebnisliste (`I_y,S` bzw. `I_y (KOS)` aus `IyS_d` bzw. `IyS_d + A*z_s^2`) und die Einzelwerte-Tabelle (Steiner-Anteile `delta = Element - Bezug`, Gesamtwerte, Ueberschrift). Umschalten ueber `menuPage 9, Zeile 2`.

### `loescheAllesQS()` / `on.clearKey()` / `qsLoeschFrage`
- **Zweck:** `on.clearKey` setzt nur `qsLoeschFrage` und zeichnet die Rueckfrage; `on.enterKey` ruft `loescheAllesQS()` (der bisherige Inhalt von `clearKey`), `on.escapeKey` bricht ab. Bei leerem Querschnitt wird ohne Rueckfrage geloescht. Der Weg `Esc` + `Backspace` (`escape_clear_pending`) laeuft ueber dieselbe Rueckfrage.

### `meldung(text, titel, fehler)` / `qsMeldung`
- **Zweck:** Meldung sichtbar machen: setzt `status` und die globale Box `qsMeldung = { titel, text, fehler, scroll = 0, scrollMax = 0 }`, die `on.paint` ueber `zeichneQsMeldung(gc, w, h)` in der Hauptansicht zeichnet (rot bei `fehler`, sonst gelb, Text umgebrochen). Ist der Text laenger als der Bildschirm, zeichnet `zeichneQsMeldung` nur die Zeilen ab `scroll`, setzt `scrollMax`, zeigt den Zeilenzaehler `a-b/n` und Dreiecke fuer weiteren Text; `on.arrowKey` verschiebt `scroll` mit hoch/runter (vor allen anderen Pfeiltastenfunktionen). `on.escapeKey` schliesst zuerst die Box; `berechneSystem` und die `open...Input`-Funktionen setzen sie zurueck.
- **Grenzen:** `status` selbst wird nirgends gezeichnet (es gibt keine Statuszeile); nur ueber `meldung` gesetzte Texte sind sichtbar. In den Eingabe- und Tabellenansichten (fruehe Rueckkehr aus `on.paint`) wird die Box nicht gezeichnet.

### `toggleCalculationMenu()`
- **Zweck:** Oeffnet/schliesst das Berechnungsmenue (`menuPage = 5`) bzw. bei bereits vorhandenem `shear_results` das Schubspannungs-Zusatzmenue (`menuPage = 8`).
- **Moeglichkeiten:** Erreichbar ueber `Strg+Menü` (`on.menuKey`/`on.contextMenu`) **und** die Taste `b`.
- **Grenzen:** Tut nichts, solange eine Text-Eingabemaske aktiv ist (`sigma_input_step ~= 0 or inputMode`).

### `finish_shape(type_name)` / `finish_thin_line()`
- **Zweck:** Schliessen einer Massiv-Form bzw. eines Duennwand-Linienzugs nach den noetigen Klicks; ruft `checkOverlapStatus`/`berechneSystem` auf.
- **Grenzen:** `finish_thin_line()` zerlegt einen Linienzug in einzelne 2-Punkt-Elemente (`duenn_elemente`), keine Mehrpunkt-Elemente.

### `zoomCenter(factor)` / `autoZoom()`
- **Zweck:** Zoomen um die Bildschirmmitte bzw. automatisches Einpassen aller Elemente in den sichtbaren Bereich.

### `enterMenuInput()`
- **Zweck:** Verarbeitet eine abgeschlossene Texteingabe im Menuekontext (Raster, Dicke, KOS-Groesse, `ξ`-Profilbeiwert, Element-/Kraft-Koordinaten, Elementdicke).
- **Grenzen:** Keine Einheiten-/Wertebereichspruefung ausser Mindestwerten (`math.max(..., 1e-5)` o. ae.).

### `enterMenuAction()`
- **Zweck:** Verarbeitet die Auswahl eines Menuepunkts (Seitenwechsel, Modus setzen, Aktionen wie KOS-Verschiebung, Element loeschen, Punkt-Tausch bei Bogenelementen).
- **Grenzen:** Sehr grosse Funktion (naeherungsweise an der TI-Lua-Grenze von 60 lokalen Upvalues); neue Menueoptionen sollten bevorzugt global gespeicherte Zustandsvariablen verwenden, wenn die Grenze erreicht wird.

### `on.charIn(c)`
- **Zweck:** Zentrale Tastatur-Dispatch-Funktion fuer Zeicheneingaben (Menues oeffnen `m`/`d`/`b`, Ergebnisse `e`, Tabelle `t`, Schubverlauf `v` + Ziffern, Zoom `+`/`-`, `c`=Clear, `h`=AutoZoom, `k`=Kernflaechen-Modus, `o`=Optionen, Ueberlappungs-Dialog `1/2/3`).
- **Grenzen:** Einzeltasten-basiert (kein Modifikator ausser dem separaten `on.menuKey`/`on.contextMenu`); Tastenkollisionen muessen manuell geprueft werden, bevor neue Kuerzel vergeben werden.

### `on.arrowKey(k)`
- **Zweck:** Kontextabhaengige Pfeiltastensteuerung: Tabellen-/Ergebnis-Scrollen, Menuezeilen-Navigation (inkl. Links/Rechts-Seitenwechsel nur zwischen Optionsseite `4` und KOS-Verschiebungsseite `9`), sonst Verschieben der Zeichenflaeche.

### `on.enterKey()` / `on.menuKey()` / `on.contextMenu()`
- **Zweck:** Bestaetigen der aktuellen Eingabe/Auswahl bzw. Oeffnen des Berechnungsmenues per Kontextmenue-Taste.

### `on.escapeKey()`
- **Zweck:** Bricht alle offenen Eingaben/Untermenues ab, setzt aber (im Gegensatz zu `on.clearKey()`) keine Geometrie zurueck.

### `on.clearKey()` / `on.backspaceKey()` / `on.deleteKey()`
- **Zweck:** `on.clearKey()` loescht das gesamte Modell (Geometrie, Kraefte, Ergebnisse) und setzt KOS-Einstellungen wie `plane/rotation` auf Standard zurueck. `on.backspaceKey()` loescht ohne aktive Eingabe das zuletzt erstellte Element bzw. bei doppeltem Escape+Backspace das gesamte Modell. `on.deleteKey()` ist ein Alias fuer `on.backspaceKey()`.
- **Moeglichkeiten:** Das Loeschen eines Massiv-Elements berechnet die Systemwerte direkt neu.
- **Grenzen:** Eine automatische Neueinstufung vorhandener Elemente als Loch erfolgt nach dem Loeschen nicht; die Lochkennzeichnung eines Elements wird beim Anlegen bestimmt.

### `on.mouseMove(x, y)` / `on.mouseUp(x, y)`
- **Zweck:** Hover-Erkennung (Kraefte vor Elementen priorisiert) bzw. Klickverarbeitung fuer Zeichenmodi, Elementauswahl und Kernflaechen-Hover.

### `on.paint(gc)`
- **Zweck:** Zentrale Zeichenroutine, die je nach aktuellem Zustand (Tabelle/Sigma/Schub/Torsion-Eingabe/Normalansicht) die passenden Unterfunktionen aufruft.
- **Grenzen:** Sehr grosse Funktion mit vielen Zustandsabfragen; neue Anzeigezustaende sollten moeglichst als fruehe `return`-Zweige ergaenzt werden, um die Komplexitaet nicht weiter zu erhoehen.

---

## 10. Bekannte projektweite Einschraenkungen (Kurzuebersicht)

- **Lua-Grenze von 200 lokalen Variablen im Hauptblock:** Neue Hilfsfunktionen werden deshalb in Tabellen gebuendelt (`sigmaEingabe.*`, `woelb.*`, `verlauf.*`) statt als eigene `local function`. Stand: 190 Top-Level-Locals.


- **Mehrzellige geschlossene Duennwandprofile:** nicht unterstuetzt (nur eine Zelle wird ausgewertet).
- **Unsymmetrische geschlossene Zellen:** Schubfluss-Konstante `q0` nicht exakt bestimmt; Schubmittelpunkt faellt auf Schwerpunkt-Naeherung zurueck.
- **TI-Nspire-Lua-Upvalue-Grenze:** max. 60 lokale Upvalues je Funktion; grosse Funktionen (`enterMenuAction`, `on.paint`) sind nahe am Limit.
