# Funktionsdokumentation: Tragwerks- und Statikmodul

Diese Datei dokumentiert die wichtigsten Funktionen des gemeinsamen Tragwerksmoduls aus `AktuellerStand.lua` und `Zeichnen.lua`. Funktionen in `AktuellerStand.lua` bilden Datenmodell, Eingabe, Berechnung, Kinematik und Export; Funktionen in `Zeichnen.lua` stellen diese Zustände grafisch dar.

## 1. Zustände und Datenmodell

### `math.eval`-Brücke: `cas_bridge.lua` / `python_cas_server.py` / `python_cas.py`

- **Zweck:** Emuliert den TI-Nspire-CAS-Aufruf `math.eval` über einen dauerhaft laufenden Python/SymPy-Server, damit `test_runner.lua` und `test_regression.lua` ohne Taschenrechner laufen.
- **Aufruf:** `luajit Emulator/test_regression.lua` bzw. `luajit Emulator/test_runner.lua [last]` aus beliebigem Ordner. `BIEGELINIE=<pfad>` testet eine andere Skriptversion, `CAS_VERBOSE=1` protokolliert jede Anfrage, `CAS_TIMEOUT=<s>` setzt die Wartezeit pro Anfrage (Standard 120 s).
- **Möglichkeiten:** TI-Semantik: Namen ohne Groß-/Kleinschreibung, `EI`, `lnc1`, `q_A` bleiben je ein Symbol, `log` = Zehnerlogarithmus. Unterstützt `f(x):=…`, `name:=…`, `DelVar`, `Disp`, `exact`, `approx`, `expand`, `string`, `integral` (bestimmt und unbestimmt), Matrizen `[[a,b][c,d]]`, `[a,b]`, `[a;b]`, 1-basierte Indizes `m[i,j]` (auch in Funktionsdefinitionen), `colAugment`, Matrixinverse. Jede Definition wird nur einmal eingelesen und integriert; ein kompletter Testlauf dauert wenige Sekunden.
- **Protokoll:** Nummerierte Anfrage-/Antwortdateien in `%TEMP%`, atomar geschrieben. Ergebnisse von `string(…)` bleiben in Lua immer Strings. Der Server beendet sich bei `cas.stop()` oder nach 120 s ohne Anfrage.
- **Grenzen:** Kein vollständiger TI-Nspire-CAS-Ersatz. Ausgaben folgen der SymPy-Normalform (z. B. `41*l^4*q/24`) und können sich in der Form, nicht im Wert, vom TI unterscheiden. Winkelfunktionen rechnen im Bogenmaß.

### Testsammlung `Emulator/tests/`

- **Aufruf:** `luajit Emulator/tests/alle.lua` führt alle Testreihen nacheinander aus (je ein Prozess mit eigenem CAS-Server) und gibt nur Fehler und eine Zusammenfassung aus; `-v` zeigt alles. Einzelne Reihen: `luajit Emulator/tests/<datei>.lua [Filter]`, mit `TEST_VERBOSE=1` jede Prüfung.
- **Reihen:** `test_regression.lua` (behobene Fehler, symbolischer Modus, Rand-LGS-Befunde), `test_runner.lua` (Originaltestfälle), `balken_hand.lua` (12 Balkensysteme gegen Lehrbuchformeln: w, φ, M, Q, u, N), `rahmen_hand.lua` (9 Rahmen gegen Handrechnung bzw. Kraftgrößenverfahren), `symbolisch.lua` (geschlossene Formeln und erwartete Abbrüche), `randlgs_fem.lua` (Rand-LGS gegen die FEM-Lösung, Stabenden exakt, Stabinneres gegen den gerundeten Referenzexport), `dehnstarr.lua` (Grenzwert EA → ∞ gegen Handrechnung mit dehnstarren Stäben, Abbruch bei Zwang), `oberflaeche.lua` (Warnhinweise mit ESC, Obermenü-Vorgaben für neue Stäbe, Umbruch der Fehlerbox, Stabmenü biegesteif/dehnsteif; `on.paint` mit Zeichen-Attrappe), `starr.lua` (biegesteife/dehnsteife Stäbe: Rand-LGS gegen Handrechnung, FEM-Verschiebungen und -Schnittkräfte exakt, Temperatur, symbolischer Modus), `kgv.lua` (KGV-Matrizen: X aus delta gegen die FEM, gelöster Pendelstab mit und ohne Eigenanteil), `starr_direkt.lua` (direkte Methode gegen Grenzwert-Methode an 12 Systemen einschließlich Klausur TM2 Aufgabe 4, Rückfall bei starr gegen starr), `randbed.lua` (Lesbarkeit der Randbedingungen: eingesetzte bekannte Werte, Gruppierung nach Biege- und Längslinie, Durchreichen über dehnsteife Stäbe am Zweigelenkrahmen, Ergebnisse gegen die FEM), `temperatur.lua` (symbolische Temperatur, Klausurtyp „ΔT so, dass u = 0“ mit Probe, starre Scheibe, symbolisch gegen numerisch am unbestimmten Rahmen, h = 0, Hinweisbox), `verschiebung.lua` (Knotenverschiebung aus dem Rand-LGS gegen Handrechnung, Speicher des Rand-LGS, Knotenmenü Seite 4, Systeme speichern/öffnen), `bogenlast.lua` (Lasten auf Bögen gegen Handrechnung: eingespannter Viertelkreis mit radialer Gleichlast, Eigengewicht, projizierten und tangentialen Lasten, Streckenmoment, Trapez, `x` = Winkel auch im Gradmodus, Dreigelenkbogen unter Eigengewicht, Temperatur, Hinweis, Export `M_bogen_i` gegen Hand und FEM, Zeichnen aller Ansichten), `querschnitt.lua` (Querschnittsmodul). Belastete Bögen prüfen außerdem `lgs_seite2.lua` Fall 8 (LGS-Export) und `arbeitssatz.lua` Fall 6 (Arbeitssatz, PvV-Ansicht). Die übrigen Reihen rechnen mit `randDehnstarr = false` (endliches EA wie die FEM).
- **Eigene Tests:** `common.lua` stellt Bausteine bereit (`node`, `bar`, `fixed`, `pinned`, `roller`, `rechne`, `randLGS`, `pruef`, `zahl`, `ev`, `evs`, `fall`, `ende`); der Hook macht außerdem `systemFingerabdruck` und `setHover(typ, obj)` (Hover wie mit dem Cursor, für `on.backspaceKey`) erreichbar.
- **Grenzen:** Alles läuft gegen den SymPy-Emulator, nicht gegen den TI-Nspire. Ableitungen (`d()`) kennt der Emulator nicht; die Handrechnungs-Tests interpolieren die Polynome exakt und leiten die Koeffizienten ab.

### `erstelleKnoten(lx, ly)`

- **Zweck:** Erzeugt einen Knoten mit Koordinaten, Lager-, Gelenk-, Last-, Feder-, Reaktions- und Ergebnisfeldern.
- **Möglichkeiten:** Initialisiert alle Freiheitsgrade und Ergebniswerte mit neutralen Standardwerten.
- **Grenzen:** Erstellt nur das Datenobjekt; die Einbindung in das Modell erfolgt durch die Zeichen- und Klicklogik.

### `erstelleStab(k1_idx, k2_idx)`

- **Zweck:** Erzeugt ein Stabobjekt zwischen zwei Knotenindizes.
- **Möglichkeiten:** Initialisiert $EA$, $EI$ samt Eingabetext (`EA_str = defEA_str`, `EI_str = defEI_str` aus dem Obermenü, damit ein symbolisches `EA` auch für später gezeichnete Stäbe gilt), Bogenradius, Lastausdrücke, Endlasten, Gelenke, Schnittgrößen und lokale Freiheitsgrade. Der aktuelle Standardwert für $EA$ beträgt $10^{10}$ und bildet für Vergleichsrechnungen ein nahezu axial starres Stabmodell ab.
- **Grenzen:** Prüft nicht selbst, ob die Knoten existieren oder identisch sind; solche Prüfungen müssen beim Erzeugen beziehungsweise Berechnen erfolgen.

### `pvvBackupSystem()` / `pvvRestoreSystem()`

- **Zweck:** Sichern und Wiederherstellen von Lagern, Gelenken und Stabendgelenken für den Prinzip-der-virtuellen-Verschiebungen-Modus.
- **Möglichkeiten:** Temporäres Lösen einer Bindung ohne dauerhafte Änderung des eigentlichen Tragwerks.
- **Grenzen:** Sichert die für PvV relevanten Bindungszustände, nicht beliebige neu hinzukommende Modellfelder.

## 2. Eingabe, Ausdrücke und Zahlenformat

### `evalInput(text, keep_str)`

- **Zweck:** Wertet numerische, CAS-kompatible oder symbolische Eingaben aus.
- **Möglichkeiten:** Akzeptiert Dezimalkomma, direkte Zahlen, Klammern, `+`, `-`, `*`, `/`, `^`, TI-Nspire-CAS-Funktionen und symbolische Variablen. Der Ausdruck wird in allen numerischen Eingabefeldern über denselben Parser ausgewertet; dazu gehören auch die Knotenfedersteifigkeiten `cx`, `cy` und `cm`. Auf Wunsch wird der Originaltext für die spätere symbolische Anzeige zurückgegeben.
- Symbolische Ausdrücke bleiben nach der Eingabe in den jeweiligen `*_str`-Feldern erhalten und werden in den Knoten-, Feder-, Stab- und globalen Einstellungsmenüs angezeigt; numerische Dummywerte werden nur intern für die Berechnung verwendet.
- CAS-Ergebnisse aus numerischen Zwischenberechnungen werden über eine eigene Konvertierung auf den ersten Rückgabewert begrenzt; dadurch bleiben symbolische Lastfunktionen wie `q/l*x` auch bei TI-Nspire-CAS-Rückgaben als Text stabil.
- Symbolische Anfangs- und Endwerte der Trapezlast werden mit der Stablänge in die Funktion `q(x)` eingebaut; bei einer funktionalen q-Last verwendet die Darstellung die vollständige CAS-Stützstellenkurve ohne zusätzlichen Dummy-Grundwert.
- Für grafische und numerische Zwischenwerte werden freie Symbole über ihre Dummywerte eingesetzt, während der ursprüngliche symbolische Ausdruck für Export und symbolische Ergebnisse erhalten bleibt.
- In der Elementlastbildung werden funktionale Lasten über CAS integriert.
- **Grenzen:** Bei nicht auswertbaren Ausdrücken wird `nil` beziehungsweise ein Dummywert aus dem symbolischen Modus verwendet. Eingaben sollten nach der Berechnung geprüft werden.

### `casToNumber(value)`

- **Zweck:** Wandelt numerische Rückgaben des TI-Nspire-CAS beziehungsweise des lokalen SymPy-Emulators sicher in Lua-Zahlen um.
- **Möglichkeiten:** Akzeptiert bereits numerische Werte und normalisiert Dezimalkommas in Textwerten.
- **Grenzen:** Symbolische oder nicht numerische Texte liefern `nil`.

### `getDummyNumeric(text)`

- **Zweck:** Ermittelt für symbolische Ausdrücke einen numerischen Ersatzwert, damit numerische Systempfade weiterlaufen können.
- **Möglichkeiten:** Erkennt Variablennamen, legt Dummywerte in `sym_vars` an und markiert den symbolischen Modus.
- **Grenzen:** Der Ersatzwert ist keine symbolische Lösung und darf nicht mit dem exakten CAS-Ergebnis verwechselt werden.

### `smartToFracStr(v, tol)` / `floatToFrac_lua(val, tol, max_denom)`

- **Zweck:** Formatiert numerische Ergebnisse als Dezimalzahl, Bruch oder einfachen Wurzelbruch; der quadrierte Wert wird vor seiner Bereichsprüfung berechnet.
- **Möglichkeiten:** Begrenzung des Nenners, Toleranzsteuerung und Anzeigeformat über `zahlenFormat`.
- **Grenzen:** Komplexe irrationale Werte werden nur angenähert oder dezimal angezeigt.

### `fN_export(n)`

- **Zweck:** Formatiert numerische Werte für den TI-Nspire-CAS-Export.
- **Möglichkeiten:** Rundet nach `casToleranz`, wandelt wissenschaftliche Schreibweise in CAS-Syntax und versucht Brüche zu erzeugen.
- **Grenzen:** Das Ergebnis hängt von `math.eval` und der CAS-Funktion `approxFraction` ab.

### `exportBiegelinienToTI(stab_index)`

- **Zweck:** Erzeugt die symbolischen Biegelinien $EI\,w(x)$ aus Lastpartikulärlösung und Hermite-Randwerten.
- **Möglichkeiten:** Setzt die Lastpartikulärlösung und die vier Hermite-Randwerte aus dem berechneten Stabzustand zusammen; der Anfangs-Biegeversatz wird mit seinem lokalen Vorzeichen als $c_1=v_a EI$ übernommen. Symbolische Lasten werden als CAS-Integrale exportiert.
- **Grenzen:** Die Vorzeichenkonvention folgt den lokalen Stabgrößen des Rechenmodells. Eine externe Musterlösung mit anderer Last- oder Koordinatenkonvention kann deshalb abweichende Polynome liefern.

### `exportBiegelinienNeuToTI()` / `exportULinienNeuToTI()` (Rand-LGS, `neuRandLGS`)

- **Zweck:** Stellt für das ganze System alle Rand- und Übergangsbedingungen auf, löst sie im CAS und exportiert je Stab `wneu_i(x) = EI·w_i(x)`, `uneu_i(x) = EA·u_i(x)` sowie die Bedingungen `randbed` als Spaltenvektor aus Strings (`["w1(x1=l)=w2(x2=0)";"EIw2''(x2=0)=0";…]`; Schnittgrößen als Ableitungen: Q = `-EIw'''`, M = `-EIw''`, N = `EAu'`). Beide Menüpunkte rufen dieselbe Funktion; sie braucht keine vorherige FEM-Berechnung.
- **Ansatz:** je Stab `EI·w = wp + c1·x³/6 + c2·x²/2 + c3·x + c4` und `EA·u = up + C1·x + C2` mit `wp = ∫q(t)(x−t)³/6 + ∫m(t)(x−t)²/2 − EI·κT·x²/2`, `up = −∫n(t)(x−t) + EA·εT·x`; daraus `Q = −c1 − ∫q`, `M = −(wp'' + c1·x + c2)`, `N = C1 − ∫n`, `φ = −w'`. Konventionen wie im Rechenmodell (`n = (−dy, dx)/L`, `M' = Q − m`).
- **Bedingungen je Knoten:** Verträglichkeit von `u`, `w`, `φ` aller Stabenden (über ein Referenzende, bei Bedarf globale Knotenunbekannte `ux(K)`, `uy(K)`), `N=0`/`Q=0`/`M=0` an N-/Q-/M-Gelenken, Lagerbedingung in den (gedrehten) Lagerrichtungen oder Gleichgewicht aus Stabendkräften, Knotenlasten (`last_x`, `last_y`, `last_w`, `last_m`) und Federn (`cx`, `cy`, `f_winkel`, `cm`).
- **Lösung (`neuVorElimination(rows, mitAlias)`):** drei Stufen, alle ohne CAS-Aufruf. (1) Zeilen mit nur einer Unbekannten liefern deren Wert; `wannBekannt[j]` merkt den Schritt (für die Anzeige), `r.quelle` die gelieferte Unbekannte. (2) Unbekannte, die nur in einer einzigen Zeile vorkommen, fallen mit dieser Zeile aus dem LGS und werden am Schluss daraus nachgerechnet (kein Einsetzen, keine längeren Ausdrücke). (3) Zeilen mit zwei Unbekannten und reinem Zahlenverhältnis ohne Konstante (`x_j = f·x_m`) werden überall eingesetzt; ein kleiner Zahlenparser (`num`) erkennt Zahlenkoeffizienten wie `-(1)` oder `(1/2)*(2)`. Stufe (3) läuft nicht bei der Grenzwertmethode (`rleps`), weil die Ausdrücke dort zu groß werden. Rückgabe: `values`, verbleibende Zeilen, Liste der vorab eliminierten Unbekannten mit ihrer Zeile, `wannBekannt` und die Kopplungen. Der Rest wird in unabhängige Blöcke zerlegt (Union-Find über die Unbekannten der verbleibenden Zeilen) und Block für Block mit `exact(simult(A,b))` gelöst; passen Zeilen- und Unbekanntenzahl eines Blocks nicht zusammen, wird alles zusammen gelöst. Danach werden die vorab eliminierten Werte rückwärts nachgerechnet (lange Ausdrücke einmal mit `exact` vereinfacht). Zahlen gehen exakt ein (`neuZahl`). Die exportierten Funktionen sind exakt (keine Rundung); auf dem Rechner bei Bedarf `approx(wneu1(x))`.
- **Anzeige der Bedingungen (`rlBedText(cond, wert)`):** Die Texte entstehen erst nach der Vorelimination. `wert(q)` liefert den Wert einer Größe, wenn alle ihre Konstanten *vor* dieser Bedingung feststanden (chronologisch wie in einer Handrechnung) und der Wert kurz ist (≤ 24 Zeichen, bei `rleps` über `limit`); solche Größen werden durch ihren Wert ersetzt und wandern in den konstanten Teil. So wird aus `"w1(x1=l)=u2(x2=3*l)"` bei dehnstarrem, gehaltenem Stab 2 `"w1(x1=l)=0"`. Bleibt keine Größe übrig, wird der unveränderte Text genommen. `rlBedText` liefert zusätzlich die Zahl der noch offenen Größen.
- **Trennung Biegelinie/Längslinie:** `typVon(j)` ordnet jede Unbekannte einem Stab-`w` (c1..c4) oder `u` (C1, C2) zu; Knotenunbekannte zählen zu beiden. `huelle(typ)` verfolgt von allen Konstanten dieses Typs aus rückwärts, welche Zeilen sie bestimmen (`bestimmt[j]`: Zeilennummer oder `"block"` für das simult-System), und meldet, ob dabei nur Größen des eigenen Typs auftauchen; vorab bestimmte Größen zählen als Zahlen, weil sie im Text eingesetzt sind. Ergebnis: `randbed` wird in zwei Gruppen mit Überschrift ausgegeben (beide unabhängig, oder eine Gruppe genügt für sich), `randinfo` nennt den Fall.
- **`neuDurchreichen(conds, typVon, nW)`** (global, wird nur aufgerufen, wenn `huelle` weder für `w` noch für `u` trennt): u-Unbekannte (`C1`, `C2`, Knotenunbekannte) gelten als durchreichbar, wenn jede Größe, in der sie vorkommt, nur von ihr abhängt (Zahlenkoeffizient, z. B. `u_A = u_B = C2` beim dehnsteifen Stab in der direkten Methode) und mit Zahlenfaktor in der Bedingung steht (keine symbolische Feder). Dann wiederholt: erst Bedingungen nur mit einer solchen Unbekannten, dann solche mit einer davon und w-Größen; die Unbekannte wird aufgelöst und auf Ebene der Größen (Namen) in alle anderen Bedingungen eingesetzt (Faktoren als Zahlen, Konstanten als CAS-Text, gleiche Größen zusammengefasst). Übrig müssen genau `nW = 4·Stäbe` Bedingungen nur mit w-Konstanten bleiben, sonst `nil`. Rückgabe `{ w = {{i, text}}, u = {i} }`; geänderte Bedingungen bekommen einen neuen Text über `rlBedText`, unveränderte behalten den Anzeigetext mit eingesetzten Werten. Die Lösung selbst (simult) bleibt unverändert.
- **Temperatur (`neuTemperatur`):** εT und κT als exakte CAS-Texte aus `To_str`/`Tu_str`/`alpha_str`/`h_str` (sonst Zahlen), damit auch symbolisch; nil, wenn der Anteil 0 ist. Aktiv, sobald To oder Tu gesetzt ist; κT nur mit h ≠ 0. Die Entscheidung läuft über die Texte, weil alle Symbole im symbolischen Modus den Platzhalterwert 1 haben.
- **Verschiebungen `wv_i`, `uv_i`:** `wneu_i/EI` bzw. `uneu_i/EA`; bei starren Stäben die exportierte Verschiebung bzw. 0. Gedacht für `solve(uv1(l)=0,dt)` auf dem Rechner. Werden wie `wneu`/`uneu` vorher gelöscht.
- **Methode für starre Stäbe (`randStarrDirekt`, Obermenü Seite 4):** `neuRandLGS` prüft und löscht, `neuRandLGSLoesen(direkt)` stellt auf, löst und exportiert. Direkt (Standard): `neuStabDaten(..., direkt)` setzt für biegesteife Stäbe `w = c4 + c3·x − κT·x²/2` (c3 = w'(0), c4 = w(0)) und für dehnsteife `u = C2 + εT·x`; Schnittgrößen wie sonst über c1, c2, C1. Ist das LGS singulär (starre Teile gegenseitig statisch unbestimmt), wiederholt `neuRandLGS` mit der Grenzwert-Methode. Lasttexte, die nur aus Zahlen bestehen und 0 ergeben (`neuIstNull`), werden nicht integriert; die Konstanten werden erst im Export vereinfacht.
- **Starre Stäbe, Grenzwert-Methode (`stabDehnsteif`, `stabBiegesteif`):** Diese Stäbe bekommen im LGS `EA = 1/rleps` bzw. `EI = 1/rleps`. Nach `simult` bestimmt `neuGrenzwert` jede Konstante als `limit(…, rleps, 0)` (nil bei `undef`, ∞ oder CAS-Fehler). Für die Starrkörperanteile (`C2 = EA·u(0)` bzw. `c3`, `c4`) wird zuerst `limit(rleps·Konstante)` gebildet: sind sie 0 und εT bzw. κT = 0, bleibt `uneu_i = EA·u_i` bzw. `wneu_i = EI·w_i`; sonst werden `uneu_i(x) = εT·x + u(0)` bzw. `wneu_i(x) = −κT·x²/2 + w'(0)·x + w(0)` exportiert. `randinfo` (Spaltenvektor aus Strings) nennt die starren Stäbe und die Funktionen, die Verschiebungen sind. Unendliche Grenzwerte (behinderte Temperaturverformung) brechen mit Meldung ab.
- **Grenzen:** Keine Bögen (Abbruch mit Meldung), keine Stäbe mit `is_cut`, keine KGV-Einheitszustände. Fehler werden zusätzlich als `randbed = ["Fehler: …"]` abgelegt; vorher werden `randbed`, `randinfo`, `rleps`, `wneu1..` und `uneu1..` gelöscht. Knoten, an denen alle Stabenden N- bzw. Q-Gelenke haben, bekommen ohne Last die Bedingung `U=0` in der freien Richtung, mit Last wird abgebrochen. Mechanismen führen zu `Rand-LGS singulär`. Ein Moment an einem Vollgelenkknoten wird wie im FEM ignoriert. Ein singuläres oder nicht quadratisches System wird gemeldet, nicht still ausgegeben. Im symbolischen Modus gelten dessen Grenzen (`symbolFehler`).

### `exportKnotenVerschiebungToTI(kidx)` / `randErgebnis` / `randLGSCacheSchluessel()`

- **Zweck:** Knotenmenü Seite 4, Zeile 1: Verschiebung des Knotens aus dem Rand-LGS als `ux_k<i>` (global x, rechts), `uy_k<i>` (global y, unten), `phi_k<i>` (gegen den Uhrzeigersinn).
- **Speicher:** `neuRandLGSLoesen` legt am Ende `randErgebnis = { stab, ende, knoten }` an: je Stab die exportierten Texte `wv`, `uv` (vereinfacht), `phi = −w'` (unvereinfacht; `wp1` aus `neuStabDaten`, starr `κT·x − c3`, starr ohne Bewegung `0`), `Ls`, `tx`, `ty`, `nx`, `ny`; je Knoten das Referenzende für die Verschiebung (erstes Ende ohne N-/Q-Gelenk) und die Verdrehung (erstes ohne M-Gelenk) wie in `neuKnotenBedingungen`, sonst die Werte der Knotenunbekannten (`extra.knoten[kidx] = {jx, jy}`). `neuRandLGS` setzt `randErgebnis.schluessel = randLGSCacheSchluessel()` nach Erfolg, bei Fehlern `nil`.
- **Schlüssel:** `systemFingerabdruck()` (Eingabefelder, jetzt einschließlich `last_w_str`),  `randStarrDirekt`, `symbolischer_modus`, `symbLSym`, `symbLDummy`, `KGV_Zustand`, `zahlenFormat`, `casToleranz`.
- **Ablauf:** Schlüssel gleich → nur Meldung „Rand-LGS aus dem Speicher“; sonst `neuRandLGS()`. Dann einmal je Knoten `U = u·t + w·n` (`amEnde`: `subx` mit `0` bzw. `(Ls)`, Richtungsfaktoren über `neuZahl` exakt) und `phi`, jeweils `neuExakt`; Ergebnis in `randErgebnis.knoten[kidx]`. Speichern mit `DelVar` und `neuCasEval`; Meldung mit `\n`-Zeilenumbrüchen (die gelbe Box bricht jetzt auch an `\n` um).
- **Löschen:** `neuRandLGS` löscht `ux_k*`, `uy_k*`, `phi_k*` (bis `max(30, #knoten)`) nur, wenn der Schlüssel nicht zum letzten Ergebnis passt.
- **Grenzen:** wie das Rand-LGS (keine Bögen, kein KGV-Einheitszustand). Freie Knoten ohne Stab: Meldung. Ein Vollgelenk hat keine Knotenverdrehung (`phi_k` bleibt gelöscht).

## 3. Geometrie, Anzeige und Mausposition

### `loescheAlles()` / `on.clearKey()` / `loeschFrage`
- **Zweck:** `on.clearKey` setzt nur `loeschFrage` und zeichnet die Rueckfrage "Wirklich alles loeschen?"; `on.enterKey` ruft `loescheAlles()` (der bisherige Inhalt von `clearKey`: Knoten, Staebe, Auswahl, Modi), `on.escapeKey` bricht ab. Beide Handler pruefen die Frage als Erstes, die Box wird in `on.paint` zuletzt gezeichnet. Bei leerem System wird ohne Rueckfrage geloescht.

### Menueposition
- **Zweck:** Alle Menuekaesten (Obermenue, Knoten, Stab, PvV) stehen links. Die Zeichenbefehle im Menueblock sind relativ zur Fensterbreite `b` geschrieben (`b - 160` usw.); statt jede Position zu aendern, wird im Block ein eigener Bezugswert `local b = mW + 20` gesetzt. Der Kasten liegt damit bei `x = 10`, die innere Aufteilung bleibt unveraendert.

### `pixelZuMeterX(px)` / `pixelZuMeterY(py)`

- **Zweck:** Wandelt Bildschirmkoordinaten in gerasterte Modellkoordinaten um.
- **Möglichkeiten:** Berücksichtigt Zoom, Ursprungsoffset und `rasterMass`.
- **Grenzen:** Rundet immer auf das aktuelle Raster; frei liegende Zwischenkoordinaten können dadurch nicht direkt angelegt werden.

### `abstand(x1, y1, x2, y2)` / `abstandZurLinie(...)`

- **Zweck:** Berechnet Punkt- und Punkt-zu-Strecken-Abstände für Hover- und Auswahltests.
- **Möglichkeiten:** Clamping auf das endliche Streckenintervall verhindert Auswahl außerhalb eines Stabs.
- **Grenzen:** Die Auswahlgenauigkeit hängt vom festgelegten Bildschirmabstand ab.

### `drawRotatedPolygon(gc, pts, cx, cy, angle)`

- **Zweck:** Zeichnet ein Polygon um einen Mittelpunkt gedreht.
- **Möglichkeiten:** Wird für gedrehte grafische Symbole und Lastdarstellungen verwendet.
- **Grenzen:** Nur Darstellung; verändert keine Modellkoordinaten.

### `drawArrow(gc, x1, y1, x2, y2, kopf)`

- **Zweck:** Zeichnet einen Linienpfeil mit Pfeilspitze.
- **Möglichkeiten:** Gemeinsame Darstellung für Lasten, Reaktionen, PvV-Beiträge und kinematische Bewegungen. `kopf` skaliert die Spitze; die Lastflächen der Streckenlasten zeichnen mit `LASTPFEIL_KOPF` (1.4) etwas größere Spitzen als der Rest.
- **Grenzen:** Pfeillänge und Spitzengeometrie sind grafische Bildschirmwerte.

### `lastResultierende(pts, L, wA, wB, R_cas, S_cas, faktor)`

- **Zweck:** Resultierende `R` und statisches Moment `S` (um den Anfangsknoten) einer Streckenlast.
- **Möglichkeiten:** Liegen elf CAS-Stützwerte vor, wird mit der Simpson-Regel integriert (exakt bis zur dritten Ordnung); sonst Trapezformel aus den Endwerten plus vorbereitetem CAS-Anteil. `faktor` bildet projizierte Lasten ab.
- **Grenzen:** Bei nicht polynomialen Lastfunktionen ist die Stützwert-Integration eine Näherung; ohne berechnetes System fehlen die Stützwerte.

### `resultierendenLabel(L_phys, L_eff, qs, qa, qb, R_cas, S_cas, R_num, S_num, typ)`

- **Zweck:** Beschriftung `R = …` für die Resultierende einer Streckenlast in der Explosionsansicht.
- **Möglichkeiten:** Im symbolischen Modus liefert `processDistLoad_PvV` den CAS-Term, sonst wird der Betrag als Zahl gesetzt; die Richtung zeigt der Pfeil.
- **Grenzen:** Reine Beschriftung; der Wert selbst wird an der Aufrufstelle aus Last und Länge gebildet.

### `merkeResultierende(x, y)`

- **Zweck:** Merkt den Angriffspunkt einer Resultierenden in `glob_resultant_pts`.
- **Möglichkeiten:** `drawBemassung` nimmt diese Punkte zusammen mit den Knoten in die globale Maßkette auf, sodass der Hebelarm ablesbar ist.
- **Grenzen:** Die Liste wird zu Beginn jedes `on.paint` geleert und gilt nur für den aktuellen Frame.

## 4. CAS- und Ergebnisexport

### `speichereMatrix(name, mat)`

- **Zweck:** Speichert eine Matrix oder einen Vektor im TI-Nspire-Variablenbereich.
- **Möglichkeiten:** Nutzt `var.store`, sofern vorhanden; meldet sonst, dass Speichern nicht möglich ist.
- **Grenzen:** Funktioniert nur in einer Umgebung mit verfügbarer Variablenschnittstelle.

### `speichereSystem(nr)` / `oeffneSystem(nr)` / `systemAlsText()` / `systemAusText(text)`

- **Zweck:** Obermenü Seite 4, Zeilen 5/6: System als String in `system<nr>` speichern bzw. daraus öffnen.
- **Format:** `TWS1;G:…;K:…;S:…`; Werte über `systemWertText(v)` / `systemTextWert(t)`: `#` Zahl (`%.15g`, sonst `%.17g`, verlustfrei), `'` Text mit `%XX` für `% ; , = : "` und Zeilenumbruch, `T`/`F`, `~` nil. `G` enthält immer alle `SYSTEM_GLOBALE`; `K`/`S` nur Felder aus `KNOTEN_EINGABEN`/`STAB_EINGABEN`, die von `erstelleKnoten(0, 0)` bzw. `erstelleStab(0, 0)` abweichen. Virtuelle Knoten/Stäbe (Bogensegmente) werden übersprungen, Stabknoten neu nummeriert.
- **Speichern:** `var.store`, danach Kontrolle mit `var.recall` (Gleichheit des Strings); `letzteSystemNr` für die Anzeige.
- **Öffnen:** `var.recall`, `systemAusText` (nil + Grund bei fremdem Inhalt), `loescheAlles()`, erst die Globalen, dann Knoten und Stäbe über `erstelleKnoten`/`erstelleStab` plus gespeicherte Felder (nur bekannte Namen; Stäbe mit ungültigen Knoten fallen weg), `updateAlleLasten()`, `systemBerechnet = false`. Das Rand-LGS-Ergebnis bleibt: Ist das geöffnete System dasselbe (gleicher Fingerabdruck), wird es wiederverwendet.
- **Grenzen:** Rechenergebnisse und KGV-Zustände werden nicht gespeichert; Überschreiben ohne Rückfrage.

### `exportStabToTI(i)` / `exportKnotenToTI(i)`

- **Zweck:** Exportiert bereits berechnete lokale Stab- beziehungsweise Knotenmatrizen.
- **Möglichkeiten:** Schreibt stabspezifische Matrizen wie `stab1_k`, `stab1_p`, `stab1_v` und Knotenmatrizen wie `knot1_pv`.
- **Grenzen:** Ohne vorherige Berechnung oder ohne gespeicherte Matrizen erfolgt kein sinnvoller Export. Im Knotenmenü sitzt `exportKnotenToTI` jetzt in Zeile 9 von Seite 4 („In TI speichern“, vorher reagierte fälschlich Zeile 4); Zeile 1 ist `exportKnotenVerschiebungToTI`.

### `exportAllToTI()`

- **Zweck:** Exportiert alle vorhandenen lokalen Matrizen, Knotenmatrizen sowie globale Systemmatrizen.
- **Möglichkeiten:** Erzeugt unter anderem `sys_k`, `sys_f` und `sys_u`.
- **Grenzen:** Bricht ohne berechnete Stäbe ab.

### `exportSchnittkraefteToTI(stab_index)`

- **Zweck:** Erzeugt CAS-Funktionen für Normalkraft-, Quer- und Momentenverläufe.
- **Möglichkeiten:** Unterstützt konstante, trapezförmige, globale und funktionale Lastanteile; kann einen einzelnen Stab oder alle Stäbe exportieren.
- **Bögen:** `istBogen(s)` (Radius mindestens halbe Sehne, sonst wird der Stab gerade gerechnet) entscheidet; Bögen gehen an `exportBogenSchnittkraefteToTI(i)`, das `M_bogen_i(p)`, `N_bogen_i(p)`, `q_bogen_i(p)` aus `arc_N_A`, `arc_V_A`, `arc_M_A` (Kräfte im ersten, tangential liegenden Teilstück) bildet und den Öffnungswinkel zurückgibt; die Meldung nennt ihn je Bogen. Mit Last auf dem Bogen kommen die Anteile aus `bogenExportLast(s)` dazu.
- **`bogenExportLast(s)`:** CAS-Texte `dN`, `dQ`, `dM` (nil ohne Last, `bogenHatLast`) für den Schnitt bei `p`: Gleichgewicht des Bogenstücks 0…p am exakten Kreisbogen, Integral über `t` mit $ds = R/u\,dt$ ($u$ aus `bogenWinkelFaktor`, `p` und `t` im Winkelmodus des Rechners). Mit $\kappa = -\mathrm{sgn}$ (Drehsinn der Tangente), Tangentenwinkel $\vartheta$:
  $dN = -\tfrac{R}{u}\int_0^p \big(\kappa q\sin(p-t) + n\cos(p-t) + G_x\cos\vartheta_p + G_y\sin\vartheta_p\big)\,dt$,
  $dQ = -\tfrac{R}{u}\int_0^p \big(q\cos(p-t) - \kappa n\sin(p-t) - G_x\sin\vartheta_p + G_y\cos\vartheta_p\big)\,dt$,
  $dM = -\tfrac{R}{u}\int_0^p \big(Rq\sin(p-t) - \kappa R n(1-\cos(p-t)) - \kappa R((\sin\vartheta_t-\sin\vartheta_p)G_y + (\cos\vartheta_t-\cos\vartheta_p)G_x) + m\big)\,dt$.
  `q`, `n` je Bogenlänge mit Trapez linear in `t` und Lastfunktion mit `x = t`; $G_x$, $G_y$ global, projiziert mal $|\sin\vartheta_t|$ bzw. $|\cos\vartheta_t|$ (`abs` nur bei Vorzeichenwechsel im Bogen); $\cos\vartheta$, $\sin\vartheta$ über die Anfangstangente (`cA`, `sA`), damit nur Winkelfunktionen von `p` und `t` vorkommen. Die Formeln ohne Last sind dieselben wie vorher (Vorzeichen geprüft: $\kappa = -\mathrm{sgn}$ reproduziert sie).
- **Grenzen:** Die CAS-Syntax muss kompatibel sein. Die Werte am Bogenanfang stammen aus der FEM mit Teilstäben (bei konstanter radialer Last exakt, sonst Teilungsfehler). Tests: `Emulator/tests/oberflaeche.lua` Fall 24 (Viertelkreis ohne Last, Bogen als Stab 1), `bogenlast.lua` (mit Last gegen Hand und FEM).

### `exportBereit()`

- **Zweck:** Wache der Exporte (Alles, Biegelinien, Längslinien, Schnittgrößen, Verschiebungen): wahr, sobald irgendein Stab ein Ergebnis hat (`mat_k`, bei Bögen `arc_plot_data`). Vorher wurde nur `staebe[1].mat_k` geprüft; Bögen haben nach der Rechnung kein eigenes `mat_k`, ein Bogen als Stab 1 blockierte deshalb alle Exporte. Nicht verwechseln mit dem Merker `systemBerechnet` (true nach der Rechnung, false nach jeder Änderung).

### `exportBiegelinienToTI(stab_index)`

- **Zweck:** Exportiert Biegelinien beziehungsweise $v(x)\cdot EI$.
- **Möglichkeiten:** Kombiniert Anfangsverschiebung und Anfangsverdrehung mit partikulären Quer- und Momentenlasten sowie funktionalen CAS-Integralen. Bei Stäben an einem inneren Gelenk wird die Biegelinie direkt vom Gelenkende aus fortgesetzt, sodass keine zusätzliche Endkorrektur die Gelenkkinematik verfälscht. In der symbolischen Superposition wird der Endverschiebungsbeitrag `vb` mit dem Vorzeichen der exportierten Randkorrektur übernommen; die vollständigen Differenzen aus Randwert und Lastintegral werden vor der Multiplikation mit der Hermite-Randfunktion geklammert. Dadurch bleiben Endwerte, lokale Verschiebung und symbolische Referenzlösung konsistent.
- **Grenzen:** Der Export ist auf berechnete Stäbe und gültige Steifigkeiten angewiesen; bei symbolischen Gelenksystemen bleibt die Darstellung auf den verfügbaren CAS-Ausdrücken und Randwerten aufgebaut.

### `exportULinienToTI(stab_index)`

- **Zweck:** Exportiert axiale Verformungslinien beziehungsweise $u(x)\cdot EA$.
- **Möglichkeiten:** Verarbeitet konstante und funktionale Normallasten.
- **Grenzen:** Für ungültige oder verschwindende Stablängen ist keine sinnvolle Funktion möglich.

### `exportKGVToTI()`

- **Zweck:** Exportiert die Einflussmatrizen des Kraftgrößenverfahrens.
- **Möglichkeiten:** Berechnet `kgv_delta` und `kgv_delta0` durch wiederholte Berechnung des Grund- und Einheitszustands. `getGap` liefert die Klaffung der jeweiligen Bindung aus den Knotenverschiebungen (Lager: direkt der Freiheitsgrad `u_ξ` bzw. `u_η`, weil die Knotenfreiheitsgrade schon im Lagersystem liegen; Pendelstab: Knotenverschiebungen erst zurück ins globale System gedreht, die Einheitskräfte `x_nA` in `baueLastvektor` ins Lagersystem des Knotens zerlegt); für einen gelösten Pendelstab (`typ = "pendel_n"`, Stab ist `is_cut`) kommt über `eigenNachgiebigkeit` seine eigene Nachgiebigkeit `L/EA` zu `delta_ii` dazu (dehnsteif: 0). Geprüft in `Emulator/tests/kgv.lua` gegen die FEM-Lösung.
- **Grenzen:** Nur aktiv, wenn der automatische KGV-Solver überzählige Größen gefunden hat. Der Automatismus wählt nur unbelastete Stäbe (auch ohne Temperatur), daher braucht `kgv_delta0` keinen Zusatzterm.

### `gelenkKnoten(k)`, `gelenkRichtung(k, j, info)`, `lastStabKnoten(k)`

- **Zweck:** Gemeinsame Regeln für Seite 2 der Explosionszeichnung und den LGS-Export. `gelenkKnoten` liefert die Stäbe mit Gelenk (`H`) bzw. biegesteif (`R`) am Knoten, `numTS` und den ersten Gelenkstab `r1`. `gelenkRichtung` ist die positive Richtung der Gelenkgrößen am Stab `j` (r1: −1 am Stabanfang, +1 am Stabende; alle anderen entgegengesetzt). `lastStabKnoten` ist der Stab, an dem Lasten und Lager eines Knotens hängen (erster Gelenkstab, sonst erster Stab).

### `exportLGSMatrixToTI(only_build)` / `buildLGS()`

- **Zweck:** Handrechnung zu Seite 2 als LGS: je Teilsystem Kräfte nach rechts, nach oben (Zeile „↑“ wirklich nach oben positiv) und Momente gegen den Uhrzeigersinn um den Bezugspunkt aus `assignTeilsysteme`; Fachwerk: Knotenschnittverfahren mit `S_i`.
- **Möglichkeiten:** Unbekannte mit Namen und Richtung wie auf Seite 2 (Lager ξ / nach oben / gegen den Uhrzeigersinn, Buchstaben nach `getSuppLetter`, Federn als Lager; Gelenkgrößen nach `gelenkRichtung`; mehr als zwei Teilsysteme mit Suffix `s<TS>` und ggf. Gelenkbolzen). Knotenlasten um `-last_w` gedreht, Momente gegen den Uhrzeigersinn, Streckenlasten über R und S (auch x-abhängig per CAS-Integral). Symbolisch: Zellen als CAS-Texte (Lastnamen, `pvvLaenge`). `lgs_modell` (A, b, x, Unbekannte mit Einträgen und Herkunft) dient den Tests.
- **Bögen:** Die Lasten eines Bogens gehen in `streckenlasten` als Summe aus `bogenLastResultierende` ein: Kraft am Stabanfang (`R`, `S = 0`, Richtung x bzw. y) plus Moment um ihn, verteilt wie in der FEM, daher trifft die Lösung die FEM genau (`lgs_seite2.lua` Fall 8).
- **Grenzen:** Gedacht für statisch bestimmte Systeme (sonst mehr Unbekannte als Gleichungen, Meldung „nicht quadratisch“). N- und Q-Gelenkgrößen an einem Bogenende zeigen in Sehnenrichtung, die FEM rechnet dort tangential (erstes bzw. letztes Teilstück); Vollgelenke und Lager sind davon nicht betroffen.

## 5. Lokale Lasten und Systemgrößen

### `globaleLinienlast(s, typ)`

- **Zweck:** Text der globalen Linienlast `gx` bzw. `gy` in der Stabkoordinate `x` und Projektionsfaktor `f` (Kraft je Stablänge = Last · f). Projiziert wird `x` durch `x·f` ersetzt (Laufvariable entlang der globalen Achse ab dem Stabanfang), sonst bleibt `x` die Stabkoordinate.
- **Möglichkeiten:** Benutzt von `getEqQ`/`getEqN` (FEM-CAS-Pfad, Rand-LGS), `updateAlleLasten` (Stützwerte für Zeichnung und Resultierende), `pvvPrepareCAS` (R, S inkl. f) und dem LGS-Export. `getFesteinspannkraefte` nimmt den CAS-Pfad jetzt auch, wenn nur `gx`/`gy` von x abhängen.

### `getEqQ(s, L, fN)` / `getEqN(s, L, fN)`

- **Zweck:** Bauen die lokalen beziehungsweise projizierten Lastausdrücke für Quer- und Normallast auf.
- **Möglichkeiten:** Kombinieren Stablasten mit globalen Linienlasten und deren Projektion.
- **Grenzen:** Die Richtungs- und Vorzeichenkonventionen sind an die lokale Staborientierung gekoppelt.

### `updateAlleLasten()`

- **Zweck:** Berechnet CAS-Stützwerte und partikuläre Lastanteile für alle Stäbe neu.
- **Möglichkeiten:** Verarbeitet funktionale $q$, $n$, $m$, $g_x$ und $g_y$, erzeugt Verlaufspunkte und Zwischenwerte für Schnittgrößen und Verformungen. Bögen: nur die Stützwerte der Lastzeichnung über den Winkel (`bogenLastPunkte`) und die Resultierende je Lastart für E-Seite, Teilsystem-Hover und PvV-Ansicht (`s.bogen_res` aus `bogenLastResultierende`), keine Integral-Stützwerte gerader Stäbe.
- **Grenzen:** Benötigt für funktionale Eingaben `math.eval`; die Genauigkeit der grafischen Stützwerte hängt von `ptsBiegelinie` ab.

### Bögen: `istBogen`, `bogenGeometrie`, `bogenPunkt`, `bogenWinkelFaktor`, `bogenLastWerte`, `bogenTeilLasten`, `bogenHatLast`, `bogenLastResultierende`, `bogenLastPunkte`, `bogenWirkungspunkt`

- **Zweck:** Gemeinsame Geometrie und Lastverteilung für Rechnung, Zeichnung und Exporte (alle global wegen der 200-Locals-Grenze im Hauptteil).
- **`bogenGeometrie(s, n)`:** nil ohne Bogen; sonst `R`, `L`, `sgn`, `kappa = -sgn`, `alpha` (Öffnungswinkel, rad), `d`, Sehnenmitte `mx`, `my`, Sehnenrichtung `ex`, `ey`, Anfangstangente `cA`, `sA` und die Teilungspunkte `pts[0..n] = { x, y, phi }` wie in `injectVirtualArcs` (Punkt 1 und n-1 tangential im Abstand Bogenlänge/n, die übrigen auf dem Bogen bei gleich geteilter Sehne; `phi` = Winkel ab Stabanfang). Die Tangente kommt aus dem Winkel, nicht aus `(L/2)/d`, deshalb geht auch der Halbkreis (`d = 0`).
- **`bogenPunkt(g, phi)`:** Punkt und Tangente auf dem Bogen beim Winkel `phi`; mit `bogenBildGeometrie(s, px1, py1, px2, py2, skala)` auch in Bildschirmkoordinaten (wie gezeichnet, auch mit Gelenkabständen).
- **`bogenWinkelFaktor()`:** Winkeleinheiten je rad und CAS-Text: `cos(180) = -1` heißt DEG (`(180/pi)`), `cos(200) = -1` GRAD, sonst RAD (`1`).
- **`bogenLastWerte(s, g)`:** Werte je Teilungspunkt: `q`, `n` (mit Trapez linear in `phi/alpha`), `m`, `gx`, `gy`; Lasttexte mit `x` werden beim Winkel `phi * Faktor` im CAS ausgewertet, `w.fehler[feld]` merkt nicht auswertbare Texte (Wert 0).
- **`bogenTeilLasten(s, g, w)`:** je Teilstab `qa, qb, na, nb, m` (Summe) und `arten[q|n|gx|gy] = { qa, qb, na, nb }`: `q` quer, `n` längs, `gx`/`gy` wie `getEqQ`/`getEqN` mit `c_val`, `s_val` des Teilstabs zerlegt, projiziert mit `|s_val|` bzw. `|c_val|`, sonst wie `m` mit Bogenstück/Teilstablänge skaliert.
- **`bogenHatLast(s)`:** Strecken-, Trapez-, Linien- oder Momentenlast vorhanden (Temperatur zählt nicht).
- **`bogenLastResultierende(s)`:** `{ Fx, Fy, M }` je Lastart und `summe` (global, y nach unten; M um den Stabanfang gegen den Uhrzeigersinn) aus den Teilstablasten, also genau wie in der FEM.
- **`bogenLastPunkte(s, g)`:** 11 Stützwerte bei `j/10*alpha` für die Lastzeichnung (`q_pts` mit Trapez, sonst nur der Funktionsanteil wie bei geraden Stäben).
- **`bogenWirkungspunkt(s, Fx, Fy, M)`:** Punkt der Wirkungslinie auf dem Bogen (Schnitt, der Bogenmitte nächster), sonst Lotfußpunkt von der Bogenmitte.

### `injectVirtualArcs()` / `cleanupVirtualArcs()`

- **Zweck:** Bögen für die Rechnung in Teilstäbe zerlegen und danach wieder entfernen.
- **Möglichkeiten:** `injectVirtualArcs` legt die Teilungspunkte als virtuelle Knoten an und je Teilstück einen virtuellen Stab mit EA/EI, starr-Schaltern, Gelenken an den Bogenenden, Temperatur (`To`, `Tu`, `alpha`, `h` samt Texten) und den Lasten aus `bogenTeilLasten` (als `q_A/q_B`, `n_A/n_B`, `m`); merkt `virt_anzahl`, `bogen_alpha`, `bogen_phi1/2` und nicht auswertbare Lastfunktionen in `bogen_last_fehler` (Hinweis in `sammleHinweise`). Der Bogen selbst bekommt in `baueLastvektor` keinen Lastvektor. `cleanupVirtualArcs` schreibt je Teilstück `N, Q, M1` (Anfang), `N2, Q2, M2` (Ende), `phi1, phi2` und die Verschiebungen in `arc_plot_data`, die Kräfte am Bogenanfang in `arc_N_A`, `arc_V_A`, `arc_M_A`.
- **Grenzen:** Ergebnisse hängen von `bogenSegmente` ab (siehe FEATURE_DOKU 2.3).

### `getTopologicalN()`

- **Zweck:** Bestimmt eine topologische Systemzahl aus Knoten, Stäben, Lagern, Federn und Gelenken.
- **Möglichkeiten:** Berücksichtigt jede aktive translatorische oder rotatorische Feder als eine zusätzliche elastische Bindung, sofern am gleichen Freiheitsgrad kein ideales Lager sitzt. Grundlage für die Anzeige von `n` und die Stabilitäts-/Bestimmtheitskontrolle.
- **Grenzen:** Die Zahl ist eine Modellierungsdiagnose; Federsteifigkeiten müssen positiv sein, und die Zählung ersetzt keine vollständige fachliche Prüfung von Sonderfällen oder der tatsächlichen Matrixrangprüfung.

### Längslinienexport (`exportULinienToTI`)

- **Zweck:** Erzeugt die axiale Verformungslinie `u_EA_stab_i` aus den axialen Endverschiebungen der FEM-Lösung und der axialen Streckenlast.
- **Möglichkeiten:** Konstante, linear veränderliche und CAS-auswertbare Lastfunktionen `n(x)`; der Lastanteil wird über `integral((x-t)*n(t),t,0,x)` doppelt integriert.
- **Grenzen:** Konzentrierte axiale Einzelkräfte innerhalb eines Stabes benötigen eine stückweise Darstellung. Die global gekoppelte Variante ist `exportULinienNeuToTI` (Rand-LGS, `uneu_i = EA·u_i`).

### `findZeroForceMembers()`

- **Zweck:** Findet Nullstäbe in Fachwerken durch wiederholte lokale Gleichgewichtsregeln.
- **Möglichkeiten:** Erkennt unbelastete Ein-, Zwei- und Drei-Stab-Knoten sowie Fälle mit Kraft- oder Rollenlagerrichtung.
- **Grenzen:** Funktioniert auf Basis idealisierter Fachwerkbedingungen; Rahmenwirkungen und nichtstandardisierte Lastfälle können die Interpretation einschränken.

## 6. Systemberechnung

### `starteBerechnung()`

- **Zweck:** Zentraler Startpunkt für eine vollständige Tragwerksanalyse.
- **Möglichkeiten:** Löscht alte CAS-Variablen, prüft symbolische Eingaben, bereitet KGV-Zustände vor, sichert das System, berechnet numerisch und symbolisch, stellt den numerischen Grundzustand wieder her und bereitet Beschriftungen vor.
- **Grenzen:** Bei kinematischen, singulären oder nicht auswertbaren Systemen können nur Warnungen beziehungsweise unvollständige Ergebnisse entstehen.

### Starre Stäbe: `stabDehnsteif(s)`, `stabBiegesteif(s)`, `stabEA_K`/`stabEI_K`, `stabEA`/`stabEI`

- **Zweck:** `stabBiegesteif` = Schalter `s.biegesteif`; `stabDehnsteif` = `s.dehnsteif` oder (`randDehnstarr` und EA weder im Stabmenü eingegeben (`s.EA_manuell`) noch symbolisch). `stabEA_K`/`stabEI_K` liefern die Steifigkeit für die Steifigkeitsmatrix (starrer Anteil 0, außer im PvV-Modus). `stabEA`/`stabEI` liefern für Zeichnung und Referenzexporte einen sehr großen Ersatzwert (`STARR_FAKTOR`·größte Steifigkeit der nicht starren Stäbe).
- **Grenzen:** Mehrere starre Stäbe, die sich gegenseitig statisch unbestimmt halten, haben keine eindeutige Kraftverteilung; FEM und Rand-LGS nehmen beide die Verteilung gleicher Starrheit (EA = EI).

### `baueZwangsbedingungen(ids)`, `faktorisiereMitZwang(K, zeilen)`, `loeseMitZwang(zf, F)`

- **Zweck:** Starre Stäbe in der FEM exakt: Zwangsbedingungen `C·u = g` (dehnsteif: `u_B − u_A = εT·L`, ohne N-Gelenk; biegesteif: `φ_A − φ_B = −κT·L` und, ohne Q-Gelenk, `w_B − w_A + L·φ_A = −κT·L²/2`) in globalen Freiheitsgraden (über `T·TKᵀ`, auch bei gedrehten Lagern). `faktorisiereMitZwang` eliminiert sie (reduzierte Stufenform, redundante Zeilen werden verworfen) zu `u = Tz·u_r + u0` und faktorisiert `Tzᵀ K Tz`. `loeseMitZwang` löst, bestimmt die Lagrange-Multiplikatoren aus `(C Cᵀ) λ = C (F − K u)` und legt je Stab die lokalen Zusatz-Endkräfte `clᵀ λ` in `glob_zwang` ab; `berechneAlleSchnittgroessen` addiert sie zu `s_local`. Abhängige Zeilen verwirft die Elimination nicht mehr stillschweigend: Sie liefert Nullvektoren `μ` von `Cᵀ` (Herkunft `h` jeder Stufenzeile), und `λ` wird auf diesen Richtungen mit minimaler Ergänzungsenergie `½ λᵀ W λ` gewählt (`zwangsNachgiebigkeit`: Nachgiebigkeit der starren Stäbe mit EA = EI = 1). `glob_zwang_info` (`unbestimmt`, `widerspruch`) steuert die Hinweise.
- **Grenzen:** Zeilen, die nur festgehaltene Freiheitsgrade betreffen, entfallen (z. B. starrer Stab zwischen zwei Einspannungen: Kräfte aus den Festeinspannkräften). Im PvV-Modus gibt es keine Zwangsbedingungen. `exportLGSMatrixToTI` exportiert weiter die unreduzierte Matrix.

### `sammleHinweise()`

- **Anzeige:** `zeichneHinweisBox(gc, b, h, liste, titel)` zeichnet die gelbe Box (Hinweise und `meldungText`). Ist sie länger als der Bildschirm, zeigt sie die Zeilen ab `hinweisScroll`, setzt `hinweisScrollMax` und `hinweisBoxScrollbar`, dazu Zeilenzähler `a-b/n` und Dreiecke; neuer Inhalt (`hinweisScrollInhalt`) setzt `hinweisScroll = 0`. `on.paint` setzt `hinweisBoxScrollbar = false` vor den Warnboxen, `on.arrowKey` blättert mit hoch/runter, solange `hinweisBoxScrollbar` gilt und weder Menü noch Eingabe offen sind.
- **Zweck:** Nach jeder Berechnung Hinweise für die gelbe Box sammeln (`hinweisListe`, `hinweisOffen`; ESC setzt `hinweisQuittiert`; die Signatur enthält `systemFingerabdruck()` aus allen Eingabefeldern von Knoten und Stäben (`KNOTEN_EINGABEN`, `STAB_EINGABEN`) sowie Schaltern, daher erscheinen die Hinweise nach jeder Systemänderung wieder): Temperatur mit To ≠ Tu bei h = 0; Temperatur im symbolischen Modus; Starre Stäbe gegenseitig statisch unbestimmt nur bei `glob_zwang_info.relevant ~= false`: `loeseMitZwang` setzt `relevant`, wenn `lambda_p` auf einer Zeile ≠ 0 ist, die über `W` mit einem Eigenspannungszustand `mu_i` gekoppelt ist (sonst ist `t = 0` für jede Steifigkeitsannahme, z. B. Längskraft einer starren Platte zwischen zwei Loslagern); im symbolischen Modus Zahl-EI (bzw. -EA) eines nicht starren Stabes ohne beidseitige Gelenke, dessen FEM-Endkräfte Biegung (bzw. Normalkraft) zeigen, wenn zugleich eine symbolische Steifigkeit mitwirkt (`symAktiv`): Stab mit symbolischem EI und Biegung, mit symbolischem EA und Normalkraft (Toleranz `1e-9·maxK`), symbolische Feder an einem Knoten mit Verschiebung (`mat_pv`, Toleranz `1e-9·maxU`) oder das Wort EI/EA in einem Lasttext (`nenntEIEA`; nicht `sym_vars`, das enthält auch die Steifigkeitsfelder). Ein Stab ohne Biegung bzw. Normalkraft hängt nicht von seinem EI bzw. EA ab, die Lösung erfüllt dann jeden Wert.
- **Grenzen:** Die Beanspruchung wird an den FEM-Endkräften mit Platzhalterwerten gemessen (relativ 1e-9 zur größten Endkraft); bei kinematischem System keine Steifigkeitshinweise.
- **Weitere Hinweise:** starre Stäbe gegenseitig statisch unbestimmt (Aufteilung wie gleich steife starre Stäbe) und Temperatur in solchen Stäben (unendliche Zwangskraft), beide aus `glob_zwang_info`; Lastfunktion auf einem Bogen nicht auswertbar (`s.bogen_last_fehler` aus `injectVirtualArcs`).

### `berechneSystemGleichungen(...)` / `rechneAktuellesSystem()`

- **Zweck:** Erzeugen und lösen die globalen Gleichungen beziehungsweise schreiben die gelösten Freiheitsgrade zurück in Knoten und Stäbe.
- **Möglichkeiten:** Berücksichtigen Lager, Federn, Gelenke, Knotenlasten, Stablasten und lokale Steifigkeitsbeiträge.
- **Grenzen:** Die exakte Signatur und interne Aufteilung ist eng an den aktuellen Solverzustand gekoppelt; neue Freiheitsgrade müssen in allen Assemblierungsstufen ergänzt werden.

### `berechneSystemGleichungen(...)` im Fachwerkmodus

- **Zweck:** Assemblierung von Stabnormalkräften und Lagerreaktionen für ein ebenes Fachwerk.
- **Möglichkeiten:** Baut je Knoten Gleichgewichtszeilen in X- und Y-Richtung.
- **Grenzen:** Fachwerkannahmen schließen allgemeine Momenten- und Biegesteifigkeitswirkungen aus.

### `getSuppLetter(nodeIndex)` / `getHingeNumber(nodeIndex)`

- **Zweck:** Erzeugt stabile Bezeichner für Lager und Gelenke in Anzeigen und LGS-Exporten.
- **Möglichkeiten:** Nummeriert nur relevante beziehungsweise erkannte Lager-/Gelenkobjekte.
- **Grenzen:** Die Bezeichnung ist eine Anzeige- und Exportkennung, keine dauerhaft gespeicherte Objekt-ID.

## 7. Kinematik und Polplan

### `buildPolplan()`

- **Zweck:** Baut aus Knoten, Stäben und Bindungen den Polplan beziehungsweise die Starrkörperscheiben auf.
- **Möglichkeiten:** Ermittelt Pole, Polstrahlen, feste Scheiben und Widersprüche. Ein Lager mit nur einer Kraftrichtung sperrt bei Lagerwinkel `w` die Richtung `xi = (cos w, -sin w)` (Lager X) bzw. `eta = (sin w, cos w)` (Lager Y) – wie `berechneAuflagerkraefte` und `drawSupport` (y nach unten, gegen den Uhrzeigersinn gedreht).
- **Grenzen:** Die geometrische Polplananalyse setzt ein sinnvoll verbundenes ebenes System voraus.

### `calcKinematicStates()`

- **Zweck:** Berechnet Verschiebungs- und Rotationszustände kinematischer Scheiben.
- **Möglichkeiten:** Liefert Zustände für Animation, PvV-Auswertung und kinematische Beschriftungen. `kinematic_disk_states[i]` ist `{type="rot", cx, cy, phi}` (intern `phi` im Uhrzeigersinn positiv: `u = (-phi (y - cy), phi (x - cx))`) oder `{type="trans", vx, vy}`; `kinematic_seed_info.disk` ist die Startscheibe. Ein Knoten macht die Bewegung eines Stabes ohne Gelenk an diesem Knoten mit; hängt er so an einer festen Scheibe, bewegt er sich nicht (auch wenn ein anderer Stab über ein N- oder Q-Gelenk angeschlossen ist).
- **Grenzen:** Die Zustände sind relativ beziehungsweise normiert und keine reale elastische Lösung.

### `getKinematicDisp(nodeIndex)` / `getKinematicRot(nodeIndex)`

- **Zweck:** Liefert die kinematische Verschiebung beziehungsweise Rotation eines Knotens.
- **Möglichkeiten:** Wird von Animation, PvV und grafischen Detailanzeigen genutzt.
- **Grenzen:** Nur verfügbar, wenn zuvor gültige kinematische Zustände erzeugt wurden.

### `exportArbeitssatzToTI(nurTerme)`

- **Zweck:** Arbeitssatz des PvV-Modus als `w_eq1` (ein Drehwinkel `φ_i` bzw. eine Verschiebung `δ_i` je bewegter Scheibe) und `w_eq2` (alles durch die Bezugsscheibe `φ_0`/`δ_0` ausgedrückt) ins CAS schreiben. `nurTerme = true` gibt nur die beiden linken Seiten zurück (Tests). `nurTerme = "anzeige"` liefert stattdessen die Daten für Zeichnung und Menüs (ohne CAS und ohne `print`): `wege[name]`/`reihe` mit `num` (Weg je Bezugsgröße, Spalte 3 als Zahl, aufsummiert in `addTerm` aus dem Hebel `h_num`), `dim` (Längendimension), `text` (`pvvAnzeigeWert`), `kraftText`, Ort und Richtung `px, py, ex, ey` (aus `processForce`) und Besitzer `knoten`/`stab`; `scheiben[i]` mit `var`, `num`, `text`; `momente` (Momentterme von `w_eq1` mit Scheibe und Besitzer).
- **Möglichkeiten:** Jede Last leistet `F·δu` bzw. `M·φ` (Drehwinkel gegen den Uhrzeigersinn positiv, intern `-phi`). Bezugsgröße: Drehwinkel der Startscheibe, bei einer nur verschobenen Startscheibe deren Verschiebungsbetrag (dann Drehwinkel anderer Scheiben „pro Länge“). Knotenlasten im symbolischen Modus mit `last_x_str`/`last_y_str`/`last_m_str`, gedreht um `-last_w` mit exakten Zahlfaktoren (kein `cos`/`sin` im CAS-Text). Die Knotenscheibe ist die eines Stabes ohne Gelenk am Knoten. Freigesetzte Größen: `H`/`V` in Lagerrichtung `xi`/`eta`, `M_A` gegen den Uhrzeigersinn, `M`/`N`/`Q` als positive Schnittgrößen (Stabanfang: Moment im Uhrzeigersinn, Kraft entgegen Stabachse bzw. `z = (-sinA, cosA)`; Stabende umgekehrt; Gegenseite entgegengesetzt), Knotengelenk als Schnittmoment des ersten Stabes. Längen über `pvvLaenge`.
- **Bögen:** Alle Lasten eines Bogens zusammen (`bogenLastResultierende`, Summe) wirken als Kraft auf der Wirkungslinie (`bogenWirkungspunkt`) mit den Wegen `δ_s<i>x`, `δ_s<i>y` über `processForce`; ohne resultierende Kraft als Moment (`processMoment`). Die PvV-Ansicht zeichnet das mit `zeichneBogenPvv` (aus `s.bogen_res`).
- **Grenzen:** Von `x` abhängige Streckenlasten gehen im symbolischen Modus als konstante Intensität ein (`R_q_cas_str` usw. werden nicht belegt).

### `pvvLaenge(zahl, potenz)`

- **Zweck:** Länge (Modelleinheiten) als Text für PvV-Terme: im symbolischen Modus `zahl/symbLDummy^potenz` mal `symbLSym^potenz` (`l` = Rasterabstand oder Geometriesymbol), sonst die Zahl. `potenz` 1 Länge, 2 Fläche, -1 pro Länge, 0 ohne Dimension.
- **Möglichkeiten:** Wird von `exportArbeitssatzToTI` (Hebelarme, Verhältnisse der Scheiben) und `processDistLoad_PvV` (Resultierende und statische Momente der Streckenlasten, auch für die Beschriftungen) benutzt; vorher stand dort fest `L` ohne Skalierung mit dem Rastermaß.

### `pvvPrepareCAS()`

- **Zweck:** Bereitet die CAS-Konstanten (Resultierende `R_*_cas`, statisches Moment `S_*_cas`) x-abhängiger Streckenlasten für den PvV-Modus vor, damit im Zeichnen kein CAS-Aufruf nötig ist.

### `pvvAnzeige()`, `pvvLabel(name)`, `pvvScheibenText(i)`, `pvvAnzeigeWert(zahl, potenz, ref)`

- **Zweck:** Gemeinsame Quelle für Zeichnung und Menüs des PvV-Modus. `pvvAnzeige()` ruft `exportArbeitssatzToTI("anzeige")` und merkt sich das Ergebnis in `pvvAnzeigeCache`, solange `kinematic_disk_states`, `pvv_released_binding`, `symbolischer_modus` und `zahlenFormat` gleich bleiben (`calcKinematicStates` legt bei jeder Änderung neue Tabellen an). `pvvLabel` liefert `"Name = Wert"` eines Weges oder `nil`, wenn der Export ihn nicht hat; `pvvScheibenText` die Beschriftung einer Scheibe. `pvvAnzeigeWert` schreibt eine Zahl je Bezugsgröße wie der Rechner (`-2*l*φ_0`, `-sqrt(2)*l*φ_0`, `φ_0`), nicht glatte Zahlen mit vier Stellen.
- **Zeichnen:** `pvvZeichneKnotenWege` (Knotenlasten in Lastrichtung, `δ_H`/`δ_V`), `pvvZeichneGelenkWinkel` (`φ_G`), `pvvZeichneVerschiebung` (nur verschobene Scheiben); Streckenlasten und `δ_G` beschriftet `on.paint` mit `pvvLabel`. Menüs: `pvvMenueZeilen`, `pvvMenueHoehe`, `pvvZeichneMenue`.
- **Tests:** `Emulator/tests/arbeitssatz.lua` (`anzeigePasst`) für jede gelöste Bindung aller Testsysteme.

## 8. Knoten-, Stab- und Menüsteuerung

### `on.mouseMove(x, y)`

- **Zweck:** Aktualisiert Mausposition, Hoverobjekt und Bildschirmdarstellung.
- **Möglichkeiten:** Erkennt Knoten und Stäbe und ermöglicht kontextabhängige Bearbeitung.
- **Grenzen:** Hover hängt von Bildschirmmaßstab und Auswahlabstand ab.

### `on.mouseUp(x, y)`

- **Zweck:** Verarbeitet Knoten-, Stab- und Messpunktklicks.
- **Möglichkeiten:** Legt neue Knoten an, verbindet ausgewählte Knoten zu Stäben, öffnet PvV-Auswahl und setzt Messpunkte für Hover-Schnittgrößen.
- **Grenzen:** Die Eingabe ist rastergebunden; ein Klick in ein bestehendes Objekt wird als Auswahl statt als neuer Punkt interpretiert.

### `on.charIn(char)`

- **Zweck:** Zentrale Tastaturverteilung.
- **Möglichkeiten:** Steuert Berechnung, Ansichtsmodi, Export-/LGS-Ansicht, Optionen, Kinematik, Polplan, Zoom, AutoZoom, Stabrichtung und Löschfunktion.
- **Grenzen:** Einzelzeichenkürzel benötigen eindeutige Belegung. Nicht auswertbare oder unvollständige Ausdrücke werden beim Bestätigen nicht übernommen.

### `on.enterKey()`

- **Zweck:** Bestätigt Menüs, Eingabefelder, Modelländerungen und PvV-Aktionen.
- **Möglichkeiten:** Bearbeitet Knotenkoordinaten, Lager, Lasten, Federn, Stabparameter, Linienlasten, Gelenke und Exporte.
- **Grenzen:** Die Bedeutung der Eingabetaste hängt von Menütyp, Menüseite, Zeile und Kinematikmodus ab.

### `on.arrowKey(key)`

- **Zweck:** Navigiert Menüseiten und verschiebt Ansicht oder Ergebnisdarstellungen.
- **Möglichkeiten:** Scrollt LGS, wechselt Menüseiten und bewegt das Zeichenfenster.
- **Grenzen:** Während Texteingaben sind Pfeiltasten nicht allgemeine Navigationsbefehle.

### `on.clearKey()` / `on.backspaceKey()` / `on.escapeKey()`

- **Zweck:** Löschen beziehungsweise Abbrechen von Eingaben und Zuständen.
- **Möglichkeiten:** `clear` setzt das komplette Modell zurück, `backspace` entfernt das ausgewählte Objekt, `escape` arbeitet von oben nach unten: offene Eingabe/Menü, dann Warnhinweise (`warnungKinematisch`, `warnungStarrBestimmt`, Box zu `symbolFehler` über `symbolFehlerOffen`; ein ESC schließt alle und tut sonst nichts), dann Sondermodi und PvV-Bindungen, zuletzt die Auswahl. `symbolFehler` selbst bleibt gesetzt, bis die nächste Berechnung ihn neu prüft.
- **Grenzen:** Ein vollständiges Löschen ist nicht dasselbe wie das Entfernen eines einzelnen Knotens; beim Knotenlöschen müssen Stabindizes angepasst werden.

## 9. Zeichnen und Ergebnisdarstellung in `Zeichnen.lua`

### `on.paint(gc)`

- **Zweck:** Zentrale Zeichenroutine des Tragwerksmoduls.
- **Möglichkeiten:** Zeichnet Raster, Achsen, Knoten, Stäbe, Lager, Lasten, Reaktionen, Schnittkraftverläufe, Verformungen, Explosion, Polplan, Kinematik, PvV und Menüs.
- **Grenzen:** Die Routine ist zustandsabhängig und groß; neue Ansichten müssen frühzeitig in die bestehende Moduslogik integriert werden.

### `drawExplosionArrow(...)` / `drawReactionArrow(...)` / `drawFBDArrow(...)`

- **Zweck:** Zeichnen gerichtete Last-, Reaktions- und Freikörperpfeile.
- **Möglichkeiten:** Berücksichtigen Vorzeichen, KGV-Zustand, Beschriftung und symbolische beziehungsweise numerische Werte.
- **Grenzen:** Pfeile sind für Bildschirmlesbarkeit skaliert und nicht maßstäbliche Kraftvektoren.

### `get_u_val(s, x, L_m, j, nA, nB)`

- **Zweck:** Berechnet die axiale Verformung an einer Stabposition.
- **Möglichkeiten:** Kombiniert homogene Endverschiebungen mit klassischem und CAS-basiertem Lastanteil.
- **Grenzen:** Nutzt die im Stab gespeicherten Verformungs- und Steifigkeitswerte; bei ungültigem $EA$ ist keine physikalisch sinnvolle Darstellung möglich.

### Schnittgrößen- und Verlaufspfad in `on.paint`

- **Zweck:** Berechnet und zeichnet $N$, $Q$, $M$, $U$ und $W$ entlang gerader Stäbe und segmentierter Bögen.
- **Möglichkeiten:** Berücksichtigt Endgrößen, Streckenlasten, Linienlastprojektionen, CAS-Stützwerte und Verlaufsskalierung. Bögen: N und Q an einem inneren Teilungspunkt als Mittel aus `N2`/`Q2` des linken und `N`/`Q` des rechten Teilstücks, am Bogenende `N2`/`Q2`. Lastsymbole auf Bögen über `achse(t)` (Punkt, Tangente, Normale auf dem gezeichneten Bogen, `t` = Winkelanteil); auf der E-Seite und beim Teilsystem-Hover zeichnet `zeichneBogenResultierende` je Lastart die Resultierende (statt der Sehnen-Resultierenden gerader Stäbe).
- **Grenzen:** Die Darstellung ist punktweise abgetastet und dient der Visualisierung, nicht als Ersatz für eine unabhängige kontinuierliche Auswertung.

### Kinematik- und PvV-Darstellung in `on.paint`

- **Zweck:** Visualisiert virtuelle Bindungslösungen, Verschiebungen, Rotationen, Klaffungen, Arbeitsanteile, Pole und rotierende Scheiben.
- **Möglichkeiten:** Animierte Pfeile und Bögen; alle Beschriftungen von Wegen und Scheiben kommen aus `pvvAnzeige()` und stimmen 1:1 mit `w_eq1`/`pvv_kin` überein (Namen und Spalte 3).
- **Grenzen:** Die Animation ist eine überhöhte qualitative Darstellung.

## 10. Projektweite technische Grenzen

- Das Skript ist für die TI-Nspire-Lua-Umgebung mit verfügbarer `platform.window`, `timer`, `var` und optional `math.eval` ausgelegt.
- Die Bildschirmdarstellung und Menüs sind auf die begrenzten Abmessungen des TI-Nspire-Fensters zugeschnitten.
- Große Systeme, viele Stäbe, symbolische Lasten und umfangreiche CAS-Exporte können Rechenzeit, Speicher und Bildschirmdarstellung belasten.
- Die TI-Nspire-Lua-Grenze von maximal etwa 60 lokalen Upvalues pro Funktion ist bei großen Funktionen wie `on.paint` und `on.enterKey` zu berücksichtigen.
- Die Funktionsnamen und Zustandsfelder bilden eine gekoppelte interne Schnittstelle; Änderungen an Freiheitsgraden, Gelenken oder Lasten müssen Solver, Export und Darstellung gemeinsam berücksichtigen.
