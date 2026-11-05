# Feature-Dokumentation: Tragwerks- und Statikmodul

Diese Datei beschreibt die aktuell sichtbaren und fachlich wichtigen Funktionen des Tragwerksmoduls. Das Modul besteht aus `AktuellerStand.lua` für Datenmodell, Berechnung und Interaktion sowie `Zeichnen.lua` für die grafische Darstellung.

## 0. Programmkonzept

Das Programm dient zur ebenen Berechnung und Darstellung von Stabtragwerken. Knoten und Stäbe werden grafisch eingegeben, an Knoten und Stäben können Lager, Gelenke und Lasten definiert werden. Die Berechnung basiert auf der Methode der finiten Elemente beziehungsweise auf einem aus Stabfreiheitsgraden aufgebauten globalen Gleichungssystem.

Das Modell unterstützt sowohl allgemeine Rahmen- und Balkensysteme als auch ebene Fachwerke. Zusätzlich gibt es Werkzeuge zur kinematischen Untersuchung, zum Polplan, zur virtuellen Verschiebung und zum Export von Rechenmatrizen und Ergebnisfunktionen an das TI-Nspire-CAS.

## 1. Typischer Arbeitsablauf

1. Im Zeichenfenster Knoten durch Klicks auf dem Raster anlegen.
2. Zwei Knoten nacheinander auswählen, um einen Stab zwischen ihnen zu erzeugen.
3. Knotenlager, Gelenke, Knotenlasten und Federn über Hover + Enter definieren.
4. Stabparameter, Streckenlasten, Endlasten, Momentenlasten, Bogenradius und Gelenke bearbeiten.
5. Bei Bedarf globale Einstellungen wie Raster, Standardwerte für $EA$ und $EI$, Fachwerkmodus oder automatische KGV-Ermittlung ändern.
6. Mit `b` das System berechnen.
7. Die Darstellung mit den Ansichtsmodi für $N$, $Q$, $M$, $U$, $W$, System, Explosion, Polplan oder Verschiebungszustand kontrollieren.
8. Ergebnisse und Funktionen bei Bedarf über das Einstellungsmenü an das TI-Nspire-CAS exportieren.

Das Programm zeigt einen roten Berechnungsstatus, wenn Stäbe vorhanden sind, aber das System nach einer Änderung noch nicht neu berechnet wurde.

## 1.1 Lokaler TI-Nspire-CAS-Test

Der Test-Runner und die Regressionstests (`Emulator/test_regression.lua`) reichen die im Lua-Modul verwendeten `math.eval`-Aufrufe über `Emulator/cas_bridge.lua` an einen SymPy-Server (`python_cas_server.py`, `python_cas.py`) weiter. Dadurch lassen sich numerische Ausdrücke, gespeicherte Funktionen, exakte Ausdrücke und bestimmte Integrale ohne angeschlossenen TI-Nspire prüfen.

Numerische CAS-Textrückgaben werden vor der Lua-Konvertierung normalisiert; dadurch bleiben Dezimalkommas gültig, ohne zusätzliche Rückgabewerte von String-Ersetzungen als Zahlenbasis zu interpretieren.

Die symbolische Biegelinienrekonstruktion verwendet die Last- und Randwertkonvention des Rechenmodells. Die exportierten Polynome werden aus Lastintegral und berechneten Hermite-Randwerten zusammengesetzt und nicht auf eine externe Musterlösung angepasst. Der Anfangswert der lokalen Biegelinie wird dabei mit $c_1=v_a EI$ und nicht mit umgekehrtem Vorzeichen eingesetzt.

**Grenzen:**

- Der Emulator deckt nur den von `Biegelinieneu.lua` verwendeten `math.eval`-Teilumfang ab.
- TI-Nspire-spezifische Formatierungen können von der SymPy-Textdarstellung abweichen.

## 2. Geometrie und Modellierung

### 2.1 Knoten

Knoten besitzen:

- kartesische Koordinaten $x$ und $y$ in Metern,
- ein optionales ideales Gelenk,
- Lagerbedingungen in globaler X-Richtung, globaler Y-Richtung und für die Rotation,
- Knotenkräfte $F_x$, $F_y$ und ein Knotenmoment,
- Federsteifigkeiten $c_x$, $c_y$ und $c_m$,
- einen Lagerwinkel und einen Winkel für die Kraftrichtung,
- berechnete Auflagerreaktionen und Verschiebungen.

Koordinaten werden beim Anklicken auf das eingestellte Raster gerundet. Bereits vorhandene Knoten werden wiederverwendet, wenn der neue Klick dieselben Rasterkoordinaten trifft.

### 2.2 Stäbe

Ein Stab verbindet zwei Knoten und besitzt unter anderem:

- $EA$ für die axiale Steifigkeit,
- $EI$ für die Biegesteifigkeit,
- einen optionalen Bogenradius,
- konstante oder veränderliche Streckenlasten $q(x)$ und $n(x)$,
- eine konstante oder veränderliche Momentenlast $m(x)$,
- globale Linienlasten $g_x(x)$ und $g_y(x)$,
- optionale Projektion globaler Linienlasten auf die Stabrichtung beziehungsweise Querrichtung,
- Endgelenke für Moment, Normalkraft oder Querkraft,
- Endgrößen für Schnittkräfte und Verformungen.

Für Vergleichsrechnungen mit der Musterlösung wird standardmäßig $EA=10^{10}$ verwendet. Dieser Wert ist eine numerische Näherung für axial unnachgiebige Stäbe; ein tatsächlich endlicher $EA$ verändert bei Rahmen die Knotenverschiebungen und damit auch die Biegelinien.

**Starre Stäbe:** Im Stabmenü, Seite 1, steht unter `EI` die Zeile `biegesteif` und unter `EA` die Zeile `dehnsteif` (Enter schaltet Ja/Nein). Ein biegesteifer Stab hat $EI \to \infty$, ein dehnsteifer $EA \to \infty$; die Eingabe von `EI` bzw. `EA` ist dann gesperrt (Anzeige `starr`). Beides wirkt überall:

- **FEM, Diagramme, Auflager:** exakt über Zwangsbedingungen zwischen den Stabend-Verschiebungen (dehnsteif: $u_B-u_A=\varepsilon_T L$; biegesteif: $\varphi_A=\varphi_B-\kappa_T L$, $w_B-w_A+L\varphi_A=-\kappa_T L^2/2$). Die Schnittgrößen starrer Stäbe folgen aus den Zwangskräften (Lagrange-Multiplikatoren), nicht aus einer großen Ersatzsteifigkeit; weiche Federn daneben bleiben genau.
- **Rand-LGS:** exakter Grenzwert, siehe 3.4.

Zusätzlich gibt es im Obermenü, Seite 1, `Standard-EA dehnstarr` (ab Werk aus): Dann sind alle Stäbe dehnsteif, deren $EA$ nicht im Stabmenü eingegeben wurde. Ein im Stabmenü eingegebenes $EA$ nimmt den Stab aus (Anzeige `dehnsteif: Nein`); `Alle EA setzen` im Obermenü macht alle Stäbe wieder zu Standard-Stäben. Ein symbolisches $EA$ (z. B. `EA`) bleibt immer dehnbar.

Ein Stab kann durch `F` umgedreht werden. Dabei werden nur Anfangs- und Endknoten vertauscht (`k1`, `k2`); alle anderen Stabwerte (Trapezlasten, Lastfunktionen, Gelenke A/B, Temperatur) bleiben unverändert und beziehen sich danach auf die neue Richtung. Das System gilt als geändert (`systemBerechnet = false`, rote Modus-Schrift), die Lasten werden neu aufbereitet.

### 2.3 Geradstäbe und Bögen

Gerade Stäbe werden mit der üblichen lokalen Stabachse ausgewertet. Ein Stab mit Bogenradius $|R| \ge L/2$ ist ein Kreisbogen (`istBogen`), das Vorzeichen von $R$ legt die Seite fest; ein kleinerer Radius wird ignoriert und der Stab gerade gerechnet.

Für die Rechnung wird der Bogen in `bogenSegmente` gerade Teilstäbe zerlegt (Obermenü Seite 3, Bogenauflösung, Standard 20; Geometrie in `bogenGeometrie`). Das erste und das letzte Teilstück liegen tangential und sind so lang wie Bogenlänge/n, die übrigen Teilungspunkte liegen auf dem Bogen bei gleichmäßig geteilter Sehne. Die Teilstäbe erben EA, EI, die Schalter biegesteif/dehnsteif, die Gelenke an den Bogenenden, die Temperatur und die Lasten des Bogens.

**Lasten auf dem Bogen** (`bogenLastWerte`, `bogenTeilLasten`, verteilt in `injectVirtualArcs`):

- `q` wirkt quer zum jeweiligen Teilstab, also radial, positiv in der lokalen Querrichtung wie beim geraden Stab (je nach Vorzeichen von $R$ zum Mittelpunkt hin oder von ihm weg). `n` wirkt längs, also tangential.
- Die Trapezanteile `q_A`/`q_B` und `n_A`/`n_B` laufen linear über die Bogenlänge.
- Globale Linienlasten `p_X`/`p_Y` wirken je Teilstab in ihrer globalen Richtung; projiziert je Grundriss- bzw. Höhenlänge des Teilstabs, sonst je Bogenlänge.
- Momentenlast `m` je Bogenlänge, Temperatur `To`, `Tu` (mit α und h) wie beim geraden Stab.
- **Lastfunktionen mit `x`:** `x` ist auf dem Bogen der **Winkel ab Stabanfang im Winkelmodus des Rechners** (RAD: 0 bis α in rad, DEG: 0 bis α in Grad), also dasselbe wie `p` in `M_bogen_i(p)`. Eine radiale Last `q = 2*cos(x)` stimmt so in jedem Winkelmodus. Ausgewertet wird an den Teilungspunkten (`bogenWinkelFaktor` erkennt den Modus über `cos(180)` bzw. `cos(200)`), zwischen zwei Punkten linear.
- Lasten je Bogenlänge (`p_X`, `p_Y` ohne Projektion, `m`) werden je Teilstab mit Bogenstück/Teilstablänge skaliert, damit die Summe exakt ist (Eigengewicht: $g R \alpha$). Konstante radiale und tangentiale Lasten brauchen das nicht, ihre Resultierende hängt nur von den Endpunkten ab und ist auf dem Polygon exakt.
- Kann das CAS eine Lastfunktion nicht auswerten, rechnet das Programm dort mit 0 und meldet es in der gelben Hinweisbox (13.2).

Der Bogen selbst bringt keinen Lastvektor mehr ein (`baueLastvektor`). Früher bekamen die Teilstäbe keine Lasten, und der Bogen trug sie als Sehnenlast, wovon der Anteil am festgehaltenen Knoten verloren ging (eingespannter Viertelkreis R = 2 mit q = 1: $R_\xi = -1$, $R_\eta = 1$ statt $-2$, $2$).

**Genauigkeit:** Exakt sind die Lagerkräfte und die Schnittgrößen an den Teilungspunkten auf dem Bogen bei konstanter radialer Last, die Gesamtlast bei Eigengewicht, projizierte Lasten und das Streckenmoment. Von der Teilung abhängig (Fehler etwa mit dem Quadrat des Teilwinkels, bei 20 Teilen um 1e-3) sind die Hebelarme von Eigengewicht und tangentialer Last, Lastfunktionen und alle Verformungen.

**Diagramme:** `arc_plot_data` hält je Teilstück die Werte am Anfang (`N`, `Q`, `M1`) und am Ende (`N2`, `Q2`, `M2`) sowie die Winkel `phi1`, `phi2`. Gezeichnet wird an den Teilungspunkten; an einem inneren Punkt für N und Q der Mittelwert aus Ende des linken und Anfang des rechten Teilstücks (mit Last auf dem Bogen sind beide verschieden). Die Lastsymbole stehen auf dem Bogen (q radial, n tangential, p_X/p_Y und m an Punkten des Bogens).

**Grenzen:**

- Kreisbögen bis zum Halbkreis (der kleinere Bogen zwischen den Knoten). Der Halbkreis mit $R = L/2$ geht (früher Division durch null bei der Tangente).
- Ergebnisse hängen von der Bogenauflösung ab. Bei großen Öffnungswinkeln liegen die Teilungspunkte an den Enden weit auseinander (gleich geteilte Sehne, beim Halbkreis bis etwa 37°), dort ist die Näherung am gröbsten: Bogenauflösung erhöhen.
- Kein symbolischer Modus und kein Rand-LGS mit Bögen (Abbruch mit Meldung).

### 2.4 Systeme speichern und öffnen (Obermenü Seite 3)

Obermenü `O`, Seite 3, Zeile 1 **„System speichern als:“** und Zeile 2 **„System öffnen:“**: `Enter`, Nummer eintippen (ganze Zahl ≥ 0), `Enter`. Gespeichert wird in die TI-Variable `system<Nr>` (z. B. `system3`) des Dokuments, als ein String:

`TWS1;G:feld=wert,…;K:feld=wert,…;S:feld=wert,…`

- `G`: Einstellungen `rasterMass`, `rasterMass_str`, `defEA`, `defEA_str`, `defEI`, `defEI_str`, `randDehnstarr`, `randStarrDirekt`, `fachwerkModus`, `pxProMeter`, `offsetX`, `offsetY` (immer alle).
- `K` je Knoten, `S` je Stab: alle Eingabefelder (`KNOTEN_EINGABEN`, `STAB_EINGABEN`: Koordinaten, Lager, Gelenke, Lasten, Federn, Steifigkeiten, starre Stäbe, Temperatur, jeweils mit Eingabetext), aber nur, wenn sie vom Standard eines neuen Knotens bzw. Stabes abweichen.
- Werte: `#Zahl` (verlustfrei), `'Text` (`% ; , = : "` und Zeilenumbruch als `%XX`), `T`/`F`, `~` für nil.

Öffnen ersetzt das aktuelle System (vorher `loescheAlles`), setzt zuerst die Einstellungen (der Standard neuer Stäbe hängt von `defEA`/`defEI` ab), dann Knoten und Stäbe, und rechnet beim nächsten Zeichnen neu. Rechenergebnisse und KGV-Zustände werden nicht gespeichert. Das Menü zeigt die zuletzt benutzte Nummer (`system3`), sonst „Nr. eingeben“.

**Grenzen:** Speichern unter einer vorhandenen Nummer überschreibt ohne Rückfrage. Die Variable ist eine normale Dokumentvariable (`DelVar system3` löscht sie; gespeichert ist sie erst mit dem Dokument). Unbekannte Feldnamen werden beim Öffnen ignoriert, Stäbe mit ungültigen Knotennummern verworfen. Getestet in `Emulator/tests/verschiebung.lua` (Rundlauf mit gleichem Fingerabdruck, Sonderzeichen, nil-Felder, Fehlerfälle).

## 3. Lager, Gelenke und Federn

### 3.1 Knotenlager

An jedem Knoten können unabhängig aktiviert werden:

- Lager X für eine horizontale beziehungsweise gedrehte X-Richtung,
- Lager Y für die zweite Lagerkomponente,
- Lager M für die Rotation.

Der Lagerwinkel erlaubt schräg orientierte Lagerbedingungen. Reaktionskräfte und Reaktionsmomente werden nach der Berechnung grafisch und numerisch angezeigt.

### 3.2 Stabgelenke

Stabgelenke können an Anfang und Ende getrennt definiert werden:

- M-Gelenk trennt die Momentenübertragung,
- N-Gelenk trennt die axiale Übertragung,
- Q-Gelenk trennt die Querübertragung.

Diese Gelenke beeinflussen sowohl das Gleichungssystem als auch die topologische Freiheitsgrad- und Kinematikprüfung. Aktive Federn in den drei Knotenfreiheitsgraden werden bei der topologischen Systemzahl zusätzlich als elastische Bindungen berücksichtigt; ein Freiheitsgrad mit idealem Lager wird dabei nicht doppelt gezählt.

Der Export der Längslinie berücksichtigt den axialen Streckenlastanteil über eine doppelte Integration. Für eine Lastfunktion `n(x)` wird der Verformungsanteil proportional zu `integral((x-t)*n(t),t,0,x)` gebildet; der globale Mehrstabexport verwendet dafür das globale axiale Rand-LGS und verwirft die Lastpolynomterme nicht mehr. Axiale Knotenfedern werden im Rand-LGS mit `ΣN+c_parallel*u=0` berücksichtigt.

### 3.3 Federn

Knotenfedern können für die drei Freiheitsgradtypen eingegeben werden:

- translatorische Feder $c_x$,
- translatorische Feder $c_y$,
- rotatorische Feder $c_m$.

Die Federwerte werden in das globale Gleichungssystem integriert. Ein Federwinkel kann für eine gedrehte Federorientierung hinterlegt werden.

### 3.4 Verformungslinien über das Rand-LGS (`wneu`, `uneu`, `randbed`)

Neben den Referenzexporten (`v_EI_stab_i`, `u_EA_stab_i` aus der FEM-Lösung) gibt es im Obermenü `O`, Seite 2, die Einträge `Neue Biegelinie (Rand-LGS)` und `Neue Längslinie (Rand-LGS)`. Beide rufen dieselbe Funktion (`neuRandLGS`): Für alle Stäbe wird der Ansatz `EI·w_i(x) = wp_i(x) + c1·x³/6 + c2·x²/2 + c3·x + c4` und `EA·u_i(x) = up_i(x) + C1·x + C2` gewählt; die 6 Konstanten je Stab folgen aus den Rand- und Übergangsbedingungen des ganzen Systems (Lager, auch gedrehte; Gelenke M/N/Q; Federn `cx`, `cy`, `cm`; Knotenlasten und -momente; Verträglichkeit der Stabenden an jedem Knoten). Das Gleichungssystem wird im CAS mit `simult` gelöst.

Exportiert werden je Stab `wneu_i(x) = EI·w_i(x)` und `uneu_i(x) = EA·u_i(x)` (lokale Koordinate `x_i` von 0 bis `L_i`, Zählrichtung vom ersten zum zweiten Knoten, `w` positiv in lokaler Querrichtung wie in den Diagrammen) sowie den Spaltenvektor `randbed` (`["…";"…"]`) mit allen verwendeten Bedingungen als lesbare Strings. Schnittgrößen werden dabei über die Ableitungen der Verformungen geschrieben: `-EIw'''` statt Q, `-EIw''` statt M, `EAu'` statt N, `-w'` statt φ (mit Temperatur `-EI(w''+κT)` bzw. `EA(u'-εT)`). Beispiele: `"w1(x1=0)=0"`, `"w1'(x1=0)=0"`, `"w1(x1=l)=w2(x2=0)"`, `"EIw2''(x2=0)=0"`, `"EIw1'''(x1=l)-EIw2'''(x2=0)+F=0"`, `"-EIw1''(x1=0)+cm*w1'(x1=0)=0"`. Die Funktionen sind exakt (keine Rundung); `approx(wneu1(x))` liefert Dezimalzahlen. Im symbolischen Modus erscheinen die Stablängen als Vielfache der Referenzlänge (`x1=l`, `x2=(2*l)`), Lasten und Steifigkeiten als Symbole.

**Lesbare Randbedingungen:** Vor dem Lösen werden alle Bedingungen ausgewertet, die nur noch eine Unbekannte enthalten (Lager, freie Enden, starre Stäbe); die betreffenden Größen stehen damit fest. In der Anzeige von `randbed` wird eine Größe, die *vor* dieser Bedingung schon feststand, durch ihren Wert ersetzt — wie in einer Handrechnung. Aus `"w1(x1=l)=u2(x2=3*l)"` wird `"w1(x1=l)=0"`, wenn Stab 2 dehnstarr und gehalten ist. Ersetzt wird nur chronologisch Vorheriges und nur, wenn der Wert kurz bleibt (bis 24 Zeichen); sonst steht weiter der Name da.

**Biegelinie und Längslinie getrennt:** Von den gesuchten Konstanten aus wird rückwärts verfolgt, welche Bedingungen die Biegelinie (alle `w`) und welche die Längslinie (alle `u`) braucht; eingesetzte Zahlenwerte trennen dabei nicht mehr. Sind beide unabhängig, steht `randbed` in zwei Gruppen mit Überschrift (`"--- nur Biegelinie w ---"`, `"--- nur Längslinie u ---"`). Genügt eine Gruppe für sich (typisch, wenn dehnstarre oder biegesteife Stäbe die Kopplung auflösen), heißt sie `"--- Biegelinie w: diese genuegen ---"`, der Rest folgt unter `"--- zusaetzlich fuer Laengslinie u ---"`. `randinfo` nennt den Fall. Bleiben beide gekoppelt, wird über dehnsteife Stäbe durchgereicht (`neuDurchreichen`): Bei der direkten Methode sind `u = C2` und `N = C1` eines dehnsteifen Stabes an beiden Enden dieselbe Unbekannte, ebenso die Knotenunbekannten `ux(K)`, `uy(K)`. Eine Bedingung mit nur einer solchen Unbekannten legt sie fest und wird in die übrigen eingesetzt, wie von Hand (Zweigelenkrahmen: aus `"u2(x2=0)=w1(x1=l)"`, `"u3(x3=0)=u2(x2=l)"`, `"w4(x4=0)=-u3(x3=l)"` wird `"w4(x4=0)=-w1(x1=l)"`, aus den Normalkräften des Riegels `"EIw1'''(x1=l)=-EIw4'''(x4=0)"`). Bleiben genau 4 Bedingungen je Stab nur mit Biegelinien-Konstanten übrig, stehen sie unter `"--- Biegelinie w: diese genuegen ---"`, die eingesetzten Bedingungen unter `"--- zusaetzlich fuer Laengslinie u ---"`; `randinfo` ergänzt „u und N der dehnsteifen Staebe eingesetzt“. Ungeteilt bleibt die Liste bei dehnbaren Stäben, die Normal- und Querkräfte koppeln (z. B. Zweigelenkrahmen mit endlichem EA der Stiele), und bei der Grenzwert-Methode. Lasten am Riegel (Horizontalkraft, Längslast n) wandern als Konstante mit, z. B. `"EIw1'''(x1=l)+EIw4'''(x4=0)+H=0"`; Symbole behalten dabei die Schreibweise der Eingabe. Getestet in `Emulator/tests/randbed.lua` (Fälle 5–8).

**Kleineres Gleichungssystem:** Die Vorelimination löst Zeilen mit einer Unbekannten auf, streicht Unbekannte, die nur in einer einzigen Zeile vorkommen (sie werden am Schluss aus dieser Zeile nachgerechnet), und ersetzt Zeilen der Form `x_j = f·x_m` mit reinem Zahlenfaktor — das tritt vor allem bei starren Stäben auf, deren Konstanten unmittelbar an denen des Nachbarstabs hängen. Für `simult` bleibt dadurch ein deutlich kleineres System (Klausur TM2 Aufgabe 4 mit Gelenken: 10 statt 15 Unbekannte, ohne Gelenke 14 statt 21; Export rund ein Drittel schneller). Bei der Grenzwertmethode wird nur gestrichen und nicht eingesetzt, weil die `rleps`-Ausdrücke sonst zu groß werden und mehr Zeit kosten, als das kleinere LGS spart. Die exportierten Funktionen sind in allen Fällen identisch. Was dann noch übrig ist, wird in unabhängige Blöcke zerlegt und Block für Block gelöst (Meldung „simult mit n Unbekannten (Block i von k)“); ein beidseitig eingespannter Träger mit Quer- und Längslast braucht so z. B. ein 6er- und ein 3er-System statt eines 9er-Systems.

**Starre Stäbe im Rand-LGS (biegesteif, dehnsteif, Standard-EA dehnstarr, siehe 2.2):** Obermenü `O`, Seite 3, `Starre Stäbe (Export)` wählt die Methode.

- **Auch in der FEM (Diagramme, Lagerkräfte):** Halten sich starre Teile gegenseitig statisch unbestimmt, wählt `loeseMitZwang` unter allen Gleichgewichtslösungen die mit minimaler Ergänzungsenergie gleich steifer starrer Stäbe (EA = EI = 1) – dieselbe Aufteilung wie der Grenzwert im Rand-LGS – und `sammleHinweise` meldet das. Getestet in `starr_direkt.lua` (Fall 10).
- `direkt` (ab Werk): Ein starrer Stab bewegt sich nur als Starrkörper, $w = w_0 + w'_0 x - \kappa_T x^2/2$ bzw. $u = u_0 + \varepsilon_T x$; seine Schnittgrößen folgen aus dem Gleichgewicht. Das LGS ist exakt und linear, ohne Hilfssymbol und ohne Grenzwert, und deutlich schneller (Klausur TM2 Aufgabe 4 mit starrem Balken: etwa halbe Zeit, `simult` rund 20-mal schneller). `wneu`/`uneu` starrer Stäbe sind hier immer die Verschiebung (wie `wv`/`uv`). Halten sich starre Teile gegenseitig statisch unbestimmt (z. B. zwei starre Stäbe zwischen zwei Festlagern), ist das direkte LGS singulär; dann wird automatisch mit dem Grenzwert gerechnet und das in `randinfo` vermerkt.
- `Grenzwert`: die bisherige Methode, siehe unten.

Bei der Grenzwert-Methode steht im LGS für starre Stäbe `EI = 1/rleps` bzw. `EA = 1/rleps`, danach wird jede Konstante mit `limit(…, rleps, 0)` bestimmt, wie in der Handrechnung mit starren Stäben. So verschwinden die EI/EA-Anteile (früher z. B. `ei*h*l/10000000000`), und Fälle, in denen sich Kräfte nach den Steifigkeiten verteilen (Horizontallast zwischen zwei Festlagern), bleiben lösbar; gleich starre Stäbe teilen dann gleichmäßig. `wneu_i(x)` bzw. `uneu_i(x)` bleiben `EI·w_i` bzw. `EA·u_i`, solange das endlich ist (z. B. Kragarm, Stütze mit gehaltenem Fuß). Bewegt sich ein starrer Stab als Ganzes (Riegel eines verschieblichen Rahmens, starrer Balken auf Federn) oder durch Temperatur, wird stattdessen die Verschiebung `w_i(x)` bzw. `u_i(x)` exportiert. Welche Stäbe starr sind und welche Funktionen Verschiebungen sind, steht im Spaltenvektor `randinfo`. Eine behinderte Temperaturverformung eines starren Stabes (unendliche Zwangskraft) führt zum Abbruch mit Meldung.

**Verschiebungen direkt:** Zusätzlich werden `wv_i(x) = w_i(x)` und `uv_i(x) = u_i(x)` exportiert (die Verschiebungen selbst, bei starren Stäben entsprechend). Damit lassen sich Klausurfragen wie „Bestimmen Sie $\Delta T$ so, dass sich Punkt A nicht verschiebt“ oder „… um 0,5 mm verschiebt“ direkt auf dem Rechner lösen, z. B. `solve(uv1(l)=0,dt)` oder `solve(wv2(2*l)=1/2,f)`. Voraussetzung ist, dass die gesuchte Größe als Symbol eingegeben wurde.

**Knotenverschiebungen (Knotenmenü Seite 4, Zeile 1 „Verschiebung“):** exportiert `ux_k<i>` (global x, nach rechts), `uy_k<i>` (global y, nach unten) und `phi_k<i>` (gegen den Uhrzeigersinn) für den Knoten, symbolisch wie das Rand-LGS. Gerechnet wird aus dem ersten Stabende am Knoten ohne N-/Q-Gelenk: `U = u·t + w·n` mit `t = (dx, dy)/L`, `n = (−dy, dx)/L` an `x = 0` bzw. `x = L`; hängen alle Stäbe über N-/Q-Gelenke am Knoten, werden die Knotenunbekannten `ux(K)`, `uy(K)` des LGS genommen. `phi = −w'` am ersten Stabende ohne M-Gelenk (starr: `κT·x − c3`); gibt es keins (Vollgelenk), bleibt `phi_k<i>` leer. Die gelbe Box („Knoten i: Verschiebung“) zeigt die drei Werte (gekürzt auf 40 Zeichen).

Das Rand-LGS wird dabei nur neu gelöst, wenn sich das System geändert hat: `randErgebnis` hält die Linien je Stab und die Referenzenden je Knoten zusammen mit einem Schlüssel (`randLGSCacheSchluessel`: Fingerabdruck aller Eingaben einschließlich Knoten- und Stabnummern, `randStarrDirekt`, symbolischer Modus mit Referenzlänge, KGV-Zustand, Zahlenformat, CAS-Toleranz). Gleicher Fingerabdruck heißt gleiches System: Ein gelöschter und identisch (mit denselben Nummern) neu gebauter Knoten oder ein erneut geöffnetes gleiches System löst kein neues LGS aus. Neu rechnen mit `B` ohne Änderung behält den Speicher. Bei geändertem System löscht das nächste Rand-LGS auch die alten `ux_k*`, `uy_k*`, `phi_k*`. Getestet in `Emulator/tests/verschiebung.lua` (Kragarm, Stiel, schräger Stab, Q-Gelenk-Knoten, starrer Stab auf Feder direkt/Grenzwert, Vollgelenk, symbolisch, Speicher).

**Temperatur symbolisch:** $T_{oben}$, $T_{unten}$, $\alpha_T$ und $h$ (Stabmenü, Seite 3) dürfen Symbole enthalten (z. B. `dt`, `t1`, `a`); das Menü zeigt den eingegebenen Text. Das Rand-LGS rechnet mit $\varepsilon_T = \alpha_T (T_o+T_u)/2$ und $\kappa_T = \alpha_T (T_u-T_o)/h$ exakt symbolisch. $h = 0$ bedeutet „kein Gradient“; eine gleichmäßige Erwärmung ($T_o = T_u$) braucht keine Höhe. Der Name `t` (auch `T`, der Rechner unterscheidet nicht) ist als Integrationsvariable reserviert, also z. B. `dt` verwenden; griechische Buchstaben werden nicht als Symbol erkannt (`a` statt `α`). Die symbolischen Diagrammbeschriftungen (Superposition) enthalten den Temperaturanteil nicht; darauf weist eine gelbe Box hin (ESC schließt sie, sie erscheint erst bei geänderten Temperatureingaben wieder).

Symbolische Eingaben werden in den grafischen Menüs wieder als eingegebener Ausdruck angezeigt. Das betrifft insbesondere Knotenfedern wie `EI/l^3` sowie die global gesetzten Stabwerte `EI` und `EA`.

**Grenzen:** Keine Bögen und keine KGV-Einheitszustände (Zustand 0 wählen). Mechanismen und Lasten in frei beweglichen Richtungen werden abgebrochen; die Meldung steht dann in `randbed` (`["Fehler: …"]`), alte `wneu`/`uneu` werden vorher gelöscht. Eingaben mit Dezimalkomma (`1,5`) und e-Notation (`1e8`) werden für das CAS umgeschrieben. Mit ausgeschaltetem dehnstarr entstehen bei numerisch großen Steifigkeiten (Standard `EI = 1e8`, `EA = 1e10`) exakte, aber lange Brüche aus dem EI/EA-Verhältnis. Die Rundungsfunktion `eval_cas_string(…, true)` ist dafür nicht geeignet (6 Stellen, absolute Schwelle 1e-6). Der Referenzexport `v_EI_stab_i` rundet Koeffizienten auf `casToleranz` Stellen (Standard 5), was bei großen `x` Abweichungen bis etwa `1e-5·x³` ergibt; das Rand-LGS rundet nicht.

## 4. Lasten

**Koordinaten und Vorzeichen:** Weltkoordinaten wie auf dem Bildschirm (`x` nach rechts, `y` nach unten). Lokale Stabrichtung vom ersten zum zweiten Knoten, lokale Querrichtung `n = (−dy, dx)/L`; `q`, `w` positiv in `n`, `φ = −w'`, `M' = Q − m`. Lagerwinkel `winkel` und Federwinkel `f_winkel` drehen die Achsen wie gezeichnet (Drehung um `−winkel`: Lagerachse `ξ = (cos w, −sin w)`, `η = (sin w, cos w)`; Federachse `cx = (cos f, −sin f)`). Knotenlasten `last_x`, `last_y` werden um `−last_w` gedreht; `last_m` und `cm` wirken im `φ`-Sinn. Ein konstantes Streckenmoment `m` geht als konsistente Stabendkräfte `Q_i = −m`, `Q_k = +m` in die FEM ein (wie der CAS-Pfad für `m(x)`), die Biegelinie enthält `+∫m(t)(x−t)²/2`.


### 4.1 Knotenlasten

Knotenlasten bestehen aus zwei Kraftkomponenten, einem Moment und einem Kraftrichtungswinkel. Sie werden im Modell gespeichert, in das globale Lastvektor-System übernommen und als Pfeile beziehungsweise Momentenpfeile gezeichnet.

### 4.2 Stablasten

Unterstützt werden:

- konstante oder funktionale Querlast $q(x)$,
- konstante oder funktionale Längslast $n(x)$,
- konstante oder funktionale Momentenlast $m(x)$,
- globale Linienlast $g_x(x)$,
- globale Linienlast $g_y(x)$,
- trapezförmige Anfangs- und Endwerte für $q$ und $n$,
- temperaturähnliche oder vorgegebene Dehnungs- und Krümmungsanteile über $T_{oben}$, $T_{unten}$, $\alpha_t$ und $h$.

Alle Stablasten gelten auch auf Bögen (siehe 2.3): `q` radial, `n` tangential, `x` in Lastfunktionen ist dort der Winkel ab Stabanfang.

Alle numerischen Eingabefelder akzeptieren mathematische Ausdrücke mit Dezimalkomma, Klammern, `+`, `-`, `*`, `/` und `^`; außerdem sind TI-Nspire-CAS-Funktionen wie `sqrt(...)` oder `sin(...)` möglich. Funktionale Eingaben können Variablen wie `x` enthalten. Wenn eine symbolische Eingabe erkannt wird, wechselt das Programm in den symbolischen Modus und versucht, die zugehörigen CAS-Ausdrücke zu erzeugen.

Die Zahlenfaktoren der Superposition werden wie im numerischen Modus aufbereitet (`smartToFracStr`): exakter Bruch, sonst — bei Zahlenformat „Wurzel/Bruch“ — die Wurzel eines Bruchs (z. B. `sqrt(2)` bei 45°-Fachwerkstäben), sonst eine Dezimalzahl. Das eingestellte Zahlenformat gilt damit auch für die symbolischen Beschriftungen; beim Umschalten im Obermenü wird neu gerechnet. (Früher wurde hier ein Näherungsbruch mit Toleranz 1e-5 gebildet: aus $\sqrt{2}/2$ wurde `169/239`, und `exact(...)` machte daraus im CAS Brüche wie `353553/500000`.)

Symbolische Trapezlasten (`q_A = 0`, `q_B = q`), Streckenlasten, Streckenmomente, Eigengewicht und Knotenlasten werden per Superposition exakt als Vielfache der Referenzlänge ausgegeben (Temperatur nur im Rand-LGS-Export, siehe 3.4). Referenzlänge ist das eine Längensymbol der Geometrie; enthält die Geometrie kein Symbol, gilt automatisch ein Rasterabstand als `l` und alle Stablängen werden als Vielfache von `l` ausgegeben (Raster 0,5 m: Stab 2 m = `4*l`). Fälle, die der symbolische Modus nicht korrekt abbilden kann, brechen die Berechnung mit einer roten Meldung ab: Temperatur oder Lastfunktionen mit `x` (z. B. `q/l*x`), Bögen, mehr als ein Längensymbol in der Geometrie und Koordinaten, die kein reines Vielfaches des Längensymbols sind (z. B. `a+2`), das Symbol `t` (Integrationsvariable). Eine Mischung aus symbolischer und numerischer Steifigkeit (z. B. Feder `3*EA*l` neben Stäben mit EA als Zahl) bricht **nicht** mehr ab: es wird gerechnet und exportiert; ein Hinweis erscheint nur, wenn der Zahlenwert das Ergebnis wirklich beeinflusst (siehe 13.2).

### 4.3 Projektion globaler Linienlasten

Globale X- und Y-Linienlasten können optional auf die lokale Stabnormale beziehungsweise Stabachse projiziert werden. Dadurch können Lasten unabhängig von der Staborientierung eingegeben werden.

**Grenzen:**

- Symbolische Ausdrücke benötigen eine kompatible TI-Nspire-CAS-Auswertung.
- Ungültige oder nicht auswertbare Eingaben werden teilweise zu Null beziehungsweise zu einem Dummywert zurückgeführt; Eingaben sollten daher nach der Berechnung kontrolliert werden.
- Lastvorzeichen beziehen sich auf die im Programm verwendete lokale beziehungsweise globale Richtung und müssen bei umgedrehten Stäben geprüft werden.

## 5. Berechnung des Tragwerks

### 5.1 Globales Gleichungssystem

Die Berechnung assembliert aus den lokalen Stabmatrizen ein globales Steifigkeitssystem. Je nach Modell werden translatorische und rotatorische Freiheitsgrade der Knoten sowie zusätzliche Stabendfreiheitsgrade berücksichtigt.

Aus dem System werden berechnet:

- globale Verschiebungen,
- Knotenrotationen,
- Stabendgrößen,
- Auflagerreaktionen,
- lokale Schnittgrößen,
- Biegelinien und Längsverformungen.

Die Gleichungen werden für Rahmen-/Balkensysteme und im Fachwerkmodus unterschiedlich aufgebaut.

### 5.2 Fachwerkmodus

Im Fachwerkmodus werden Knoten standardmäßig gelenkig behandelt. Das Gleichungssystem verwendet Stabnormalkräfte und Lagerreaktionen. Die grafische Darstellung kann Nullstäbe hervorheben.

Der Modus ist für ebene Fachwerke gedacht, bei denen die Stäbe im Wesentlichen Normalkräfte übertragen. Biege- und Momentenwirkungen sind dort nicht als allgemeine Rahmenwirkung zu interpretieren.

### 5.3 Starrmodus und statische Unbestimmtheit

Der Starrmodus setzt hohe Standardwerte für $EA$ und $EI$ und dient zur Modellierung beziehungsweise Anzeige eines nahezu starren Systems. Das ist keine exakte unendlich steife Formulierung; exakt starre Stäbe gibt es über `biegesteif`/`dehnsteif` im Stabmenü (siehe 2.2).

Das Programm warnt bei einem kinematischen System. Bei einem starren und gleichzeitig statisch unbestimmten System erscheint ebenfalls eine gesonderte Warnung.

### 5.4 Automatischer KGV-Solver

Der automatische KGV-Solver erkennt überzählige Bindungen beziehungsweise Freiheitsgrade und bildet Zustände für die überzähligen Größen. Ein Zustand $X_i=1$ kann über die Zifferntasten ausgewählt werden. Zusätzlich können KGV-Matrizen exportiert werden.

Wird ein Pendelstab als überzählige Größe gelöst, ist er im Hauptsystem **entfernt**; die Einheitskräfte greifen an seinen beiden Knoten an. Seine eigene Längenänderung $N L/(EA)$ steckt deshalb nicht in den Knotenverschiebungen und wird zu $\delta_{ii}$ addiert ($X_i = 1$ erzeugt im gelösten Stab $N = 1$, in den übrigen gelösten Stäben $N = 0$). Ohne diesen Anteil wäre das Verfahren nur für dehnstarre gelöste Stäbe richtig; bei einem Fachwerkfeld mit zwei Diagonalen lag der Fehler bei rund 11 %. Dehnsteife Stäbe liefern den Anteil 0. Gelöste Lager und eingefügte Gelenke brauchen keinen Zusatz, weil der Stab dort im System bleibt.

**Grenzen:**

- Die automatische Erkennung hängt von der gewählten Modellierung und den erkannten Bindungen ab.
- Bei ungünstig modellierten Gelenken, Federn oder Sonderfällen kann die automatische Auswahl der überzähligen Größen fachlich kontrolliert werden müssen.
- Der Starrmodus ersetzt keine exakte Starrkörper- oder Zwangsbedingungsanalyse.

## 6. Schnittgrößen und Verformungen

Die Ergebnisansichten zeigen entlang der Stäbe beziehungsweise Bogenabschnitte:

- `N`: Normalkraftverlauf,
- `Q`: Querkraftverlauf,
- `M`: Momentenverlauf,
- `U`: axiale beziehungsweise longitudinale Verschiebung,
- `W`: Biegelinie beziehungsweise transversale Verschiebung.

Abhängig von der Einstellung können Schnittgrößen am Anfang und Ende, am Hoverpunkt oder an Start- und Endposition angezeigt werden. Maximalwerte können ein- oder ausgeblendet werden.

Die Biegelinie wird aus Anfangsverschiebung, Anfangsverdrehung und partikulären Lastanteilen aufgebaut. Bei einem inneren Gelenk wird die lokale Biegelinie ohne zusätzliche starre Endkorrektur vom Gelenkende aus fortgesetzt; dadurch bleiben Verschiebungskontinuität und die getrennten Gelenkrotationen erhalten. Bei symbolischen Systemen wird die Endverschiebung `vb` mit der für die exportierte Randkorrektur erforderlichen Vorzeichenkonvention übernommen; insbesondere wird der vollständige Ausdruck aus Randwert und Lastintegral vor der Multiplikation mit der Hermite-Randfunktion geklammert und der symbolische Endwert nicht gegenüber `v_local[5]` gespiegelt. Für symbolische oder funktionale Lasten werden CAS-Stützwerte erzeugt und in die Darstellung einbezogen.

Symbolische Knotenfedersteifigkeiten `cx`, `cy` und `cm` werden beim Berechnungsstart über ihre gespeicherten Texte `cx_str`, `cy_str` und `cm_str` in Dummywerte für die numerische Zwischenrechnung überführt; der Originalausdruck bleibt für die symbolische Eingabe verfügbar.

**Grenzen:**

- Die grafischen Verläufe werden über eine einstellbare Punktzahl pro Stab abgetastet und sind daher keine beliebig fein aufgelöste Darstellung.
- Bei sehr großen Werten kann die gemeinsame Verlaufsskalierung die Detaildarstellung beeinflussen.
- Die Verschiebungsdarstellung ist zur Sichtbarkeit skaliert und nicht automatisch maßstäblich zur Geometrie.
- Die direkte Fortsetzung am inneren Gelenk setzt eine korrekt gelöste lokale Verschiebung und Verdrehung am Gelenkende voraus.

### 6.x Globale Linienlasten mit x

`p_X(x)`, `p_Y(x)` (Stabmenü Seite 2) dürfen von `x` abhängen (nur im Zahlenmodus). Projiziert läuft `x`
entlang der globalen Achse ab dem Stabanfang (`p_Y` waagerecht 0…|Δx|, `p_X` senkrecht 0…|Δy|), sonst
entlang der Stabachse 0…L (`globaleLinienlast`). Die FEM rechnet sie über den CAS-Pfad (früher fehlte die
Last, wenn nur sie von x abhing), ebenso Zeichnung, Resultierende, Arbeitssatz, Rand-LGS und LGS-Export.
Getestet in `Emulator/tests/globallast.lua`. Auf einem Bogen ist `x` auch hier der Winkel ab Stabanfang
(auch projiziert), siehe 2.3.

## 7. Explosion und Detailansichten

Mit `e` wird die Explosionsansicht geöffnet. Sie stellt Stabendgrößen und lokale Freiheitsgrade getrennt dar. Über `e` kann zwischen den Explosionsseiten gewechselt werden; `t` blendet die Detailbeschriftungen um.

In der Explosion werden unter anderem dargestellt:

- lokale Stabkräfte und Momente,
- Auflager- und Gelenkbeiträge,
- lokale Verschiebungen und Rotationen,
- Lastangriff und Reaktionsbeiträge,
- symbolische Bezeichnungen, wenn der symbolische Modus aktiv ist.

### 7.0 Seite 2 und LGS-Export

Seite 2 zeigt den Freischnitt als Ansatz: jede unbekannte Kraft mit Namen in ihrer **positiven** Richtung,
Momente mit festem positivem Drehsinn (Lager gegen den Uhrzeigersinn, Gelenkmomente wie positive
Schnittmomente). Der Export `LGS-Matrix` stellt genau zu diesem Bild die Handrechnung auf (je Teilsystem
Kräfte nach rechts, nach oben, Momente gegen den Uhrzeigersinn um P), mit denselben Namen und Richtungen;
die Lösung trifft die Werte von Seite 1. Gemeinsame Regeln im Code: `gelenkKnoten`, `gelenkRichtung`,
`lastStabKnoten`.

- Lager: `A_h` in Lagerrichtung ξ, `A_v` nach oben (−η), `M_A` gegen den Uhrzeigersinn; Buchstaben nach
  `getSuppLetter` (Reihenfolge der Lager, Federn zählen mit), auch an Gelenkknoten.
- Gelenke: am ersten Gelenkstab wie positive Schnittgrößen (Stabanfang −, Stabende +), Gegenseite
  entgegengesetzt – auch beim Vollgelenk, an dem zwei Stäbe mit dem Anfang hängen. Mehr als zwei
  Teilsysteme: je Gelenkstab eigene Größen (Suffix `s<TS>`), ohne biegesteifen Rest mit Gelenkbolzen.
  Hängt nur ein Stab am Gelenk, gibt es keine Gelenkgrößen.
- Lasten und Lager eines Gelenkknotens hängen am ersten Stab mit Gelenk dort; Knotenlasten mit ihrem
  Wert (früher stand dort die Koordinate) und um den Lastwinkel gedreht.
- Symbolischer Modus: das LGS steht symbolisch (Lastnamen, Längen als Vielfache von l).
- Fachwerk: Knotenschnittverfahren mit `S_i` (Zug positiv), Seite 2 beschriftet `S_i`.
- Geprüft in `Emulator/tests/lgs_seite2.lua`: Seite 2 wird beim Zeichnen protokolliert (`E2_PROTOKOLL`),
  jede Unbekannte muss dort mit Name und Richtung stehen, und die LGS-Lösung muss die FEM treffen.

### 7.1 Streckenlasten als Resultierende

Auf beiden Explosionsseiten wird jede Streckenlast durch ihre **Resultierende** ersetzt – also
genau das Bild, mit dem man das Gleichgewicht von Hand aufstellt:

- ein Pfeil auf der Wirkungslinie, beschriftet mit `R = …` (im symbolischen Modus der CAS-Term
  aus `processDistLoad_PvV`, sonst der Zahlenwert),
- die Lage folgt aus dem Flächenmoment der Last, $x_R = S/R$ vom Anfangsknoten aus gemessen,
- betroffen sind die Querlast `q`, die Längslast `n` und die globalen Linienlasten `gx`/`gy`
  (bei projizierten Lasten mit der projizierten Länge),
- ein Streckenmoment `m` wird zu einem Momentensymbol in Stabmitte mit `M = …`.

`lastResultierende` liefert $R$ und $S$: Für Lastfunktionen wie `q(x) = x^2` wird über die elf
gespeicherten Stützwerte mit der Simpson-Regel integriert – für lineare und quadratische Lasten
ist das exakt –, sonst gilt die Trapezformel aus den Endwerten plus dem im PvV vorbereiteten
CAS-Anteil.

**Bögen:** Je Lastart eine Resultierende in ihrer tatsächlichen Richtung (nicht quer zur Sehne), aus den
Teilstablasten wie in der FEM (`bogenLastResultierende`, zwischengespeichert in `s.bogen_res` durch
`updateAlleLasten`). Der Fußpunkt liegt dort, wo die Wirkungslinie den Bogen schneidet, sonst am Lot von der
Bogenmitte (`bogenWirkungspunkt`); ein Streckenmoment wird zum Momentensymbol in Bogenmitte. Beispiel:
konstante radiale Last auf dem Viertelkreis, Resultierende $q\cdot$Sehne durch Mittelpunkt und Bogenmitte.
Im LGS-Export geht die Summe aller Bogenlasten als Kraft am Stabanfang plus Moment um ihn ein (gleichwertig
für das Gleichgewicht des Teilsystems).

Die **Wirkungslinien werden bemaßt**: Die Angriffspunkte kommen zusammen mit den Knoten in die
globale Maßkette, sodass der Hebelarm direkt ablesbar ist. Das passiert auf der E-Seite
unabhängig vom Schalter *Bemaßung* im Obermenü, weil die Resultierende ohne ihre Lage nichts
nützt. Beim Hovern eines Teilsystems auf Seite 2 wird nur dieses Teilsystem bemaßt.

## 8. Kinematik, Polplan und Verschiebungszustände

### 8.1 Kinematische Prüfung

Mit `v` wird die kinematische Ansicht geöffnet. Das Programm prüft, ob das System stabil ist. Kinematische Systeme werden als solche markiert und können animiert dargestellt werden.

### 8.2 Polplan

Mit `p` wird der Polplan geöffnet. Er zeigt Starrkörperbereiche, Pole und Polstrahlen. In den Optionen kann zwischen notwendigen, keinen oder allen Polstrahlen gewählt werden.

Der Polplan unterstützt die qualitative Untersuchung von Bewegungszuständen und Scheibenrotationen. Rotierende Scheiben werden um ihre momentanen Pole visualisiert.

Gedrehte Rollenlager wirken im Polplan in derselben Richtung wie in der Berechnung und in der Zeichnung
(Lagerwinkel gegen den Uhrzeigersinn). Früher drehte der Polplan sie andersherum; bei Winkeln, die kein
Vielfaches von 90° sind, lag der Pol dadurch auf der falschen Geraden.

### 8.3 Prinzip der virtuellen Verschiebungen

Ist ein System starr, kann mit `Enter` der PvV-Modus gestartet werden. Danach kann ein Knoten oder Stab ausgewählt und eine Bindung temporär gelöst werden:

- Lager X, Lager Y oder Lagermoment am Knoten,
- Knoten-Gelenk bei geeigneten Knoten,
- M-, N- oder Q-Gelenk an einem Stabende.

Das System wird mit der gelösten Bindung als virtueller Bewegungszustand untersucht. Zeichnung und Menüs benutzen **dieselben Namen und Werte wie der Export** (8.4), sie kommen aus derselben Rechnung:

- An jedem Weg steht `Name = Wert` wie Spalte 3 von `pvv_kin`: Knotenlasten `δ_k<i>x`/`δ_k<i>y` (Pfeil in Lastrichtung, bei gedrehtem Lastsystem mitgedreht), Streckenlasten `δ_s<i>q`/`n`/`x`/`y`, gelöstes Lager `δ_H`/`δ_V`, gelöstes N-/Q-Gelenk `δ_G`, gelöstes Momentengelenk `φ_G`.
- Drehbögen der Scheiben: `φ_i = Faktor*φ_0`, Bezugsscheibe `φ_i = φ_0`; nur verschobene Scheiben `δ_i = …` an ihrem ersten Stab. Das gelöste Einspannmoment heißt `M_A`.
- Knoten- und Stabmenü im PvV-Modus: Wege (wie `pvv_kin`), Drehwinkel der beteiligten Scheiben und die Arbeitsanteile, also die Terme von `w_eq1`, die zu diesem Knoten bzw. Stab gehören.
- Nicht glatte Werte stehen in der Zeichnung auf vier Stellen gerundet, im Export als Zahl bzw. Bruch.

Die ursprünglichen Bindungen werden gesichert und beim Beenden wiederhergestellt.

### 8.4 Arbeitssatz exportieren (`w_eq1`, `pvv_kin`, `pvv_pol`, `w_eq2`, `pvvinfo`)

Der Menüpunkt *Arbeitssatz* schreibt die Gleichung $\sum F\,\delta + \sum M\,\varphi = 0$ in drei Ebenen ins CAS:

- `w_eq1`: reines Kraft mal Weg, jede Kraft mal ihr Weg (positiv in Richtung der eingegebenen
  Kraft), jedes Moment mal den Drehwinkel `φ_i` seiner Scheibe. Namen: `δ_k3x`/`δ_k3y` (Knoten 3,
  x- bzw. y-Last), `δ_s2q`/`δ_s2n`/`δ_s2x`/`δ_s2y` (Resultierende der Quer-, Längs- bzw. globalen
  Linienlast von Stab 2), `δ_H`, `δ_V` (gelöstes Lager), `φ_G`/`δ_G` (gelöstes Gelenk, gegenseitige
  Verdrehung bzw. Verschiebung). Lasten auf Scheiben, die sich nicht bewegen, fehlen.
- `pvv_kin` (Matrix): Weg | durch die eigene Scheibe (`hebel*φ_i` bzw. `Richtungskosinus*δ_i`) |
  durch `φ_0` (bzw. `δ_0`); darunter je bewegter Scheibe `φ_i | φ_i | Faktor*φ_0`.
- `pvv_pol` (Matrix): je Nebenpol zweier bewegter Scheiben (`polplan.poles[A][B]`, erster Pol)
  dieselbe Bewegung über beide Scheiben: endlich `δx_PAB` bzw. `δy_PAB` (die größere Komponente der
  Bewegung, y nach unten), im Unendlichen `φ_PAB | φ_A | φ_B` (gleiche Drehung) bzw. `δ_PAB` (zwei
  verschobene Scheiben, Komponente in Polrichtung).
- `w_eq2` drückt alles durch `φ_0` (bzw. `δ_0`) aus; nach der freigesetzten Größe aufgelöst ist das
  direkt das Ergebnis. Spalte 3 von `pvv_kin` in `w_eq1` eingesetzt ergibt `w_eq2`.
- `pvvinfo`: Legende aller Namen.
- **Vorzeichen:** Drehwinkel und Momente zählen gegen den Uhrzeigersinn positiv. Die freigesetzte
  Größe wirkt so, wie der PvV-Modus sie zeichnet: `H` und `V` in Lagerrichtung (ungedreht: `H` nach
  rechts, `V` nach unten; bei gedrehtem Lager mitgedreht), `M_A` gegen den Uhrzeigersinn (= das
  Einspannmoment der Berechnung), `M`, `N`, `Q` an Gelenken als **positive Schnittgrößen** – also mit
  demselben Vorzeichen wie in den Verläufen. Beim Knotengelenk gilt das Schnittmoment des ersten
  Stabes am Knoten.
- **Symbolischer Modus:** Knotenlasten stehen mit ihren Namen in der Gleichung (`F1`, `-F2`, …),
  Hebelarme als Vielfache des Längensymbols (`l` = Rasterabstand bzw. das Symbol der Geometrie, z. B.
  `a`). Schräge Lasten (Lastwinkel) werden wie in der Berechnung gegen den Uhrzeigersinn gedreht und
  als exakte Faktoren (z. B. $\sqrt{2}/2$) geschrieben – ohne `cos`/`sin`, damit der Winkelmodus des
  Rechners keine Rolle spielt.
- Lasten an einem Knoten mit N- oder Q-Gelenk gehören zu dem Stab **ohne** Gelenk an diesem Knoten
  (steht der fest, leisten sie keine Arbeit).
- **Bögen:** Alle Lasten eines Bogens zusammen wirken als ihre Resultierende auf der Wirkungslinie (auf der
  starren Scheibe dieselbe Arbeit), mit den Wegen `δ_s<i>x` und `δ_s<i>y`; die PvV-Ansicht zeichnet sie
  dort (`zeichneBogenPvv`). Ohne resultierende Kraft (nur Streckenmoment) bleibt ein Moment auf `φ_i`.

Geprüft wird das in `Emulator/tests/arbeitssatz.lua`: Für jede Löseart (H, V, M_A, Knotengelenk,
M-/N-/Q-Gelenk an Anfang und Ende, gedrehtes Lager, reine Verschiebung) muss die aus `w_eq2` und die
aus `w_eq1` mit `pvv_kin` (Spalte 3) bestimmte Größe mit der Auflagerreaktion bzw. Schnittgröße der
FEM-Rechnung übereinstimmen; zusätzlich passt in `pvv_kin` Spalte 2 zu Spalte 3 und in `pvv_pol`
liefern beide Scheiben dieselbe Bewegung. Außerdem steht jede Zeile von `pvv_kin` als `Name = Wert` in
der gezeichneten PvV-Ansicht (Wert gleich Spalte 3), die Ansicht beschriftet keinen Namen, den der
Export nicht kennt, und jeder Weg steht im Menü seines Knotens bzw. Stabes.

**Grenzen:**

- Streckenlasten, die von `x` abhängen, gehen im symbolischen Modus noch als konstante Last in den
  Arbeitssatz ein (im Zahlenmodus werden sie integriert).
- Der PvV-Modus ist eine qualitative und rechnerisch unterstützte Untersuchung einzelner gelöster Bindungen.
- Nur zulässige Bindungen können gelöst werden; ungeeignete Kombinationen werden zurückgewiesen.
- Die animierte Darstellung ist skaliert und stellt keine maßstäbliche reale Zeit- oder Verformungsbewegung dar.

## 9. Nullstäbe im Fachwerk

Der Nullstab-Algorithmus sucht iterativ nach unbelasteten Knoten und typischen Gleichgewichtsbedingungen:

- ein einzelner unbelasteter Stab ohne relevante äußere Bindung,
- zwei nicht kollineare Stäbe an einem unbelasteten Knoten,
- drei Stäbe mit zwei kollinearen Stäben,
- Sonderfälle mit Kraft oder Rollenlager in Stabrichtung.

Erkannte Nullstäbe werden für die Darstellung markiert. Der Algorithmus wiederholt die Prüfung, weil das Entfernen eines Nullstabs weitere Erkennungen ermöglichen kann.

## 10. Export zum TI-Nspire-CAS

Über das Einstellungsmenü können folgende Daten exportiert werden:

- alle Systemdaten,
- Biegelinien,
- Längsverformungslinien,
- KGV-Daten,
- Arbeitssatzdaten,
- Schnittkraftfunktionen,
- globale LGS-Matrix,
- Verformungslinien aus dem Rand-LGS (`wneu_i`, `uneu_i`, `randbed`),
- Knotenverschiebungen aus dem Rand-LGS (`ux_k<i>`, `uy_k<i>`, `phi_k<i>`; Knotenmenü Seite 4, Zeile 1).

Typische gespeicherte Variablen sind `sys_k`, `sys_f`, `sys_u`, `ggw_a`, `ggw_b`, `ggw_x`, `ggw_eqs` sowie stabspezifische Matrizen und Funktionen.

Für gerade Stäbe können analytische CAS-Funktionen für $N(x)$, $Q(x)$, $M(x)$, $v(x)$ und $u(x)$ erzeugt werden. Funktionale Lasten werden nach Möglichkeit als Integrale exportiert. Für Bögen gibt es winkelabhängige Schnittkraftfunktionen `N_bogen_i(p)`, `q_bogen_i(p)`, `M_bogen_i(p)` (p = Winkel ab Stabanfang, im Winkelmodus des Rechners); sie kommen mit *Nur Schnittgrößen* und *Alles exportieren*, die Meldung nennt den Winkelbereich je Bogen. Sie bauen auf den Kräften am Bogenanfang aus der FEM auf. Trägt der Bogen Lasten, kommt der Anteil der Last auf dem Bogenstück 0…p als Integral dazu (`bogenExportLast`, Gleichgewicht am exakten Kreisbogen, Integrationsvariable `t`, Bogenlänge $ds = R/u\,dt$ mit $u$ Winkeleinheiten je rad). Lastfunktionen mit `x` gehen mit `x = t` ein, projizierte Linienlasten mit $|\sin\vartheta|$ bzw. $|\cos\vartheta|$ der Tangente (`abs` nur, wenn das Vorzeichen im Bogen wechselt). Bei konstanter radialer Last ist das Ergebnis exakt, sonst trägt es den Teilungsfehler der Anfangswerte (bei 100 Teilen um 1e-4). *Nur Biegelinien* und *Nur Längslinien* lassen Bögen aus. Ob das System berechnet ist, prüfen die Exporte an allen Stäben (`exportBereit`), ein Bogen als Stab 1 blockiert also nichts mehr.

**Grenzen:**

- Der Export setzt eine verfügbare `var.store`- beziehungsweise TI-Nspire-CAS-Umgebung voraus.
- Die Exportfunktionen sind für bereits berechnete Systeme gedacht.
- Nicht jede Sonderform, insbesondere jede Kombination aus Bogen, Symbolik und Gelenken, erzeugt für alle Größen dieselbe analytische Darstellung.

## 11. Anzeige, Einstellungen und Bedienung

### Tastaturkürzel

- `b`: Tragwerk berechnen.
- `m`: Momentenverlauf anzeigen.
- `n`: Normalkraftverlauf anzeigen.
- `q`: Querkraftverlauf anzeigen.
- `u`: Längsverformung anzeigen.
- `w`: Biegelinie anzeigen.
- `s`: Systemansicht öffnen.
- `e`: Explosionsansicht öffnen beziehungsweise Seite wechseln.
- `t`: Beschriftungen in der Explosionsansicht ein-/ausblenden.
- `v`: Kinematik beziehungsweise Verschiebungszustand öffnen oder schließen.
- `p`: Polplan öffnen.
- `l`: globales LGS anzeigen.
- `o`: Einstellungsmenü öffnen.
- `h`: System automatisch in den sichtbaren Bereich einpassen.
- `f`: Richtung eines unter dem Cursor befindlichen Stabs umkehren.
- `+`/`-`: Zoom ändern.
- **Gelbe Hinweisbox** (nach der Berechnung, das Ergebnis ist gültig; ESC schließt sie, sie erscheint wieder, sobald sich am System etwas ändert, z. B. eine Steifigkeit, Last, Lagerung oder ein Gelenk; erneutes Rechnen ohne Änderung öffnet sie nicht):
  - Temperatur mit $T_o \ne T_u$, aber $h = 0$: Es wirkt nur die mittlere Erwärmung $(T_o+T_u)/2$, keine Krümmung.
  - Temperatur im symbolischen Modus: Die Diagrammbeschriftungen enthalten den Temperaturanteil nicht, der Export schon.
  - Symbolischer Modus: Ein Stab hat ein Zahlen-EI (bzw. -EA) und wird laut FEM tatsächlich auf Biegung (bzw. Normalkraft) beansprucht, und auch eine symbolische Steifigkeit wirkt tatsächlich mit (gebogener Stab mit symbolischem EI, Stab mit N ≠ 0 und symbolischem EA, symbolische Feder an einem bewegten Knoten, EI/EA in einem Lasttext). Symbolische Steifigkeiten von Stäben ohne Biegung bzw. Normalkraft zählen nicht, die Lösung hängt nicht von ihnen ab. Das Ergebnis mischt dann Zahl und Symbol (z. B. `3·l²·ea + 125000000`, wobei 125000000 aus EI = 10⁸ stammt). Abhilfe: Pendelstab mit Gelenken an beiden Enden, EI/EA symbolisch, biegesteif/dehnsteif bzw. Standard-EA dehnstarr.
- `Clear`: alles löschen. Vorher erscheint die Rückfrage **„Wirklich alles loeschen?“** – `Enter` löscht, `Esc` bricht ab (bei leerem System entfällt die Rückfrage).
- Alle Menüs (Obermenü, Knoten- und Stabmenü, PvV-Menüs) stehen am **linken** Bildschirmrand.
- `Esc`: Eingabe, Menü oder Sondermodus abbrechen. Warnhinweise („System ist kinematisch!“, „Starrmodus & statisch unbestimmt!“, Hinweisbox, „Symbolischer Modus nicht möglich“) schließt ein `Esc`, sofern kein Menü und keine Eingabe darüber liegt; eine neue Berechnung zeigt sie wieder. Beim symbolischen Modus bleibt die Sperre bestehen (Rand-LGS-Export bricht weiter ab), nur die Box verschwindet.
- Die Werte „Alle EA setzen“ / „Alle EI setzen“ im Obermenü gelten für alle vorhandenen Stäbe und als Vorgabe für neu gezeichnete Stäbe, auch als Symbol (z. B. `EA`).
- `Backspace`: Eingabe löschen oder das ausgewählte Element entfernen.

### Einstellungsgruppen

Die Einstellungen stehen auf fünf Seiten (Tabelle `OBERMENUE`, `←`/`→` blättert):

1. Einstellungen: Raster, Alle EI setzen, Alle EA setzen, Starr-Modus, Auto-KGV, Fachwerk-Modus, Standard-EA dehnstarr.
2. Exporte zum TI-Nspire-CAS (neun Zeilen, wie bisher).
3. System und Rechnung (9 Zeilen): System speichern als, System öffnen (siehe 2.4), Variablen löschen (Zeile 3: erstes Enter zeigt „Sicher? Enter“, das zweite ruft `loescheSkriptVariablen()` auf; Pfeiltaste oder Esc verwerfen die Nachfrage), CAS-Toleranz, Bogen-Segmente, Starre Stäbe (Export), Anzeige N, LGS wie Lösungsweg, Max. Teilgruppen. Gelöscht werden alle Namen aus `SKRIPT_VARIABLEN` (feste Namen wie `randbed`, `lgs`, `kgv_delta` und nummerierte wie `wneu#`, `stab#_k`, `ux_k#`) bis max(30, Stab-/Knotenzahl), mit `var.list` zusätzlich alle passenden Reste im Dokument; `system<Nr>` und eigene Variablen nie. Danach ist `randErgebnis` leer, das nächste Rand-LGS rechnet neu.
4. Ergebnisse: Zahlenformat, Schnittgrößen-Modus, Punkte/Stab, Maximalwerte, Rasterpunkte (Zeile 5, Enter schaltet `rasterPunkte` 1 Normal → 2 Dick → 0 Keine: 1×1- bzw. 2×2-Pixel oder gar keine Punkte; das Fangen am Raster bleibt), Verlauf-Skalierung, Polstrahlen.
5. Ansicht: Schriftgröße (Normal, Gross, Sehr gross, Riesig; siehe „Ergänzungen (Schriftgröße)“), Zoom-Schritt normal, Zoom-Schritt Explosionsansicht, Bemaßung.

**Biegelinie/Längslinie zeichnen:** Werte werden zur Rauschunterdrückung erst unter 1e-12 m auf null gesetzt (Kräfte unter 1e-5). Früher galt auch hier 1e-5 m = 0,01 mm, dadurch fehlte bei kleinen Verformungen ein Stück der Linie bzw. die ganze Linie. Die verbleibenden Pixeltreppen flacher Linien kommen vom Display (keine Kantenglättung).

## 12. Bekannte Grenzen und fachliche Hinweise

- Das Programm ist eine ebene lineare Stabwerksberechnung und keine allgemeine nichtlineare oder dreidimensionale Tragwerksanalyse.
- Materialnichtlinearität, Plastizität, Stabilitätsversagen, Kontakt und große Verformungen werden nicht als allgemeine Modelle gelöst.
- Die verwendeten $EA$- und $EI$-Werte sind Eingabeparameter; eine automatische Material- oder Querschnittsdatenbank ist nicht vorhanden.
- Kinematische und statisch unbestimmte Systeme sollten anhand der Warnungen und der Systemzahl fachlich kontrolliert werden.
- Symbolische Rechnungen und Exporte hängen von der Leistungsfähigkeit und Syntax des TI-Nspire-CAS ab.
- Das Programm speichert die Geometrie und Einstellungen nicht als allgemeine Projektdatei.
- Sehr lange Menüs, LGS-Ausgaben und Tabellen benötigen Scrollen und können die begrenzte Bildschirmgröße überschreiten.
- Eine Prüfung auf realer TI-Nspire-Hardware und eine unabhängige Vergleichsrechnung bleiben für wichtige Ergebnisse empfehlenswert.

## 13. Meldungen und Hinweise (Übersicht)

Alles, was der Rechner anzeigen soll, wird gezeichnet: `Disp` aus einem Lua-Skript zeigt der TI-Nspire nicht an, und `print` geht nur in die Konsole des Emulators. Sichtbar sind daher die Boxen in der Bildmitte; `Esc` schließt die oberste Box (erst Eingabe/Menü, dann Box, dann Modi und Auswahl).

### 13.1 Warnboxen (rot/orange)

| Meldung | Wann | Warum |
|---|---|---|
| **Symbolischer Modus nicht möglich:** + Grund | Symbolischer Modus mit einer Eingabe, die er nicht abbilden kann | Verhindert falsche Ergebnisse; Berechnung und Rand-LGS-Export bleiben gesperrt, auch nachdem die Box geschlossen wurde |
| **System ist kinematisch!** | Steifigkeitsmatrix singulär (Mechanismus) | Keine eindeutige Lösung |
| **Starrmodus & statisch unbestimmt!** | Statisch unbestimmtes System, alle Stäbe sehr steif (EA, EI ≥ 10⁷, auch die Standardwerte) oder Starr-Modus aktiv | In unbestimmten Systemen hängt die Kraftverteilung von den Steifigkeitsverhältnissen ab |
| **System ist starr! [Enter] für PvV-Modus** | PvV-Ansicht bei nicht kinematischem System | Für das Prinzip der virtuellen Verschiebungen muss erst eine Bindung gelöst werden |

Gründe für „Symbolischer Modus nicht möglich“:

| Grund | Wann | Warum |
|---|---|---|
| Nur ein Längensymbol erlaubt | Mehrere Symbole in den Koordinaten | Alle Längen werden als Vielfache einer Referenzlänge `l` ausgegeben |
| Knoten i: Koordinate kein Vielfaches von `l` | Koordinate wie `a+2` | wie oben |
| Symbol `t` ist reserviert | Eingabe enthält `t` bzw. `T` | `t` ist die Integrationsvariable des Exports; der Rechner unterscheidet Groß-/Kleinschreibung nicht |
| Stab i: Temperatur als Funktion von x nicht möglich | `x` in To, Tu, α oder h | Nicht vorgesehen |
| Stab i: Lastfunktion f(x) nicht symbolisch möglich | `x` in q, n, m, gx, gy | Die Superposition kennt nur konstante und trapezförmige Lasten |
| Stab i: Bögen nicht symbolisch möglich | Bogenradius ≠ 0 | Nicht vorgesehen |

### 13.2 Gelbe Hinweisbox (nach der Berechnung; erscheint nach jeder Systemänderung wieder)

| Hinweis | Wann | Warum |
|---|---|---|
| Stab i: To und Tu verschieden, aber h = 0 | h = 0 und To ≠ Tu | Sonst wirkt stillschweigend nur die mittlere Erwärmung (To+Tu)/2, ohne Krümmung |
| Temperatur symbolisch: Diagrammwerte ohne Temperaturanteil | Symbolischer Modus mit Temperatur | Die Diagrammbeschriftungen entstehen durch Superposition; der Temperaturanteil fehlt dort, im Export nicht |
| Stab i wird auf Biegung belastet, EI ist dort eine Zahl … | Symbolischer Modus: der Stab wird tatsächlich gebogen (Schnittgrößen ≠ 0, kein Pendelstab), EI numerisch, und eine symbolische Steifigkeit wirkt ebenfalls mit (siehe oben) | Nur dann beeinflusst der Zahlenwert das Ergebnis. Der Text nennt die Folge: statisch bestimmt → nur Biegelinie und Export mischen Zahl und Symbol; statisch unbestimmt → auch die Schnittgrößen können verfälscht sein (Symbole rechnen intern mit 1) |
| Stab i trägt Normalkraft, EA ist dort eine Zahl … | wie oben mit N ≠ 0 und numerischem EA | wie oben; Abhilfe: dehnsteif bzw. Standard-EA dehnstarr oder EA symbolisch |
| Stab i (Bogen): Lastfunktion q, … nicht auswertbar (x = Winkel ab Stabanfang im Winkelmodus). Dort mit 0 gerechnet. | Das CAS liefert für eine Lastfunktion auf einem Bogen an einem Teilungspunkt keine Zahl (z. B. Division durch null) | Sonst fehlte die Last still; `x` ist auf Bögen der Winkel, nicht die Länge (2.3) |

**Lange gelbe Boxen:** Passt der Text nicht auf den Bildschirm, zeigt die Box einen Ausschnitt. Pfeil hoch/runter blättert zeilenweise, oben rechts steht der Zeilenzähler (`a-b/n`), kleine Dreiecke am rechten Rand zeigen weiteren Text oben bzw. unten. Neuer Inhalt beginnt oben.

### 13.3 Export- und Rand-LGS-Meldungen (gelbe Box, Titel „Export“ bzw. „Export fehlgeschlagen“)

| Meldung | Wann |
|---|---|
| Rand-LGS: n Stäbe, m Bedingungen → wneu_i, uneu_i, wv_i, uv_i, randbed, bei starren Stäben mit Zusatz „Starr: wneu=w bei Stab …, uneu=u bei Stab … (siehe randinfo)“ | Erfolgreicher Rand-LGS-Export; der Zusatz nennt die Stäbe, bei denen `wneu`/`uneu` die Verschiebung selbst ist (direkte Methode bzw. bewegter starrer Stab) |
| Matrizen/Schnittgrößen/Biegelinien/Längslinien/Verschiebungslinien/KGV-Matrizen exportiert | Erfolgreicher Export aus dem Obermenü, Seite 2 |
| LGS exportiert: ggw_a, ggw_b, ggw_x, lgs (nummerierte Gleichungen), lgs_weg (Loesungsweg); ggf. „LGS nicht quadratisch“ | Export der Gleichgewichtsmatrix samt Lösungsweg; die Warnung zeigt ungleiche Anzahl Gleichungen und Unbekannte |
| Arbeitssatz exportiert: w_eq1, w_eq2, pvv_kin, pvv_pol, pvvinfo | Erfolgreicher Arbeitssatz-Export (PvV); `pvv_pol` nur, wenn es Nebenpole zwischen bewegten Scheiben gibt |
| Bitte zuerst das System berechnen (Taste B) | Export ohne vorherige Berechnung |
| KGV-Export: KGV nicht aktiv oder System statisch bestimmt | KGV-Export ohne Einheitszustände |
| Arbeitssatz: bitte zuerst in den PvV-Modus wechseln | Arbeitssatz-Export außerhalb des PvV-Modus |
| Dieser Export erfordert das CAS | Kein CAS verfügbar |
| ux_k<i> = …, uy_k<i> = …, phi_k<i> = … (Titel „Knoten i: Verschiebung“) | Knotenverschiebung exportiert; „Gelenk: keine Knotenverdrehung“ statt phi am Vollgelenk |
| Knoten i hängt an keinem Stab | Knotenverschiebung eines freien Knotens |
| System als system<n> gespeichert / system<n> geöffnet: … Knoten, … Stäbe | Obermenü Seite 3, Zeile 1 bzw. 2 |
| system<n> ist nicht vorhanden / keine gespeicherte Tragwerksdatei | Öffnen einer leeren bzw. fremden Variable |
| Kein System vorhanden / Bitte eine ganze Zahl eingeben | Leeres System speichern bzw. Eingabe ist keine ganze Zahl |

Fehler des Rand-LGS stehen zusätzlich auf dem Rechner in `randbed = ["Fehler: …"]`; die alten Funktionen `wneu`, `uneu`, `wv`, `uv` werden vorher gelöscht:

| Meldung | Wann |
|---|---|
| Keine Stäbe vorhanden / Kein gültiger Stab | Kein Stab bzw. nur Stäbe der Länge 0 |
| Symbolischer Modus: … | Symbol-Sperre aktiv |
| Rand-LGS nicht im KGV-Einheitszustand X_i | Ein KGV-Einheitszustand ist eingestellt; der Export gilt für Zustand 0 |
| Stab i: Bögen werden vom Rand-LGS nicht unterstützt | Bogen im System |
| Knoten k: Last in frei beweglicher Richtung (kinematisch) | Last auf einen Knoten, dessen Stabenden in dieser Richtung alle ein N- oder Q-Gelenk haben |
| Rand-LGS singulär / nicht lösbar: System kinematisch? | Mechanismus |
| Rand-LGS nicht quadratisch / unerwartete Lösung | Interne Kontrolle der Bedingungszahl bzw. der CAS-Antwort |
| Starrer Stab i: Grenzwert nicht bestimmbar | Grenzwert-Methode: `limit` scheitert |
| Starre Stäbe: unendliche Zwangskraft | Behinderte Temperaturverformung eines starren Stabes |
| Export wneu/uneu/wv/uv i fehlgeschlagen | Das CAS kann die Funktion nicht definieren |

`randinfo` ist kein Fehler, sondern die Legende des Exports: starre Stäbe, welche Funktionen Verschiebungen sind, verwendete Methode (auch der Rückfall auf den Grenzwert) und die Bedeutung von `wv`/`uv`.

## Ergänzungen (Einheitencheck, Anzeige, Löschen, Raster)

- **Einheitencheck im symbolischen Modus** (`einheit.pruefe`, Hinweis in der gelben Box): Jedes Feld hat eine Einheit aus Kraft, Länge, Temperatur (Koordinaten, Rastermaß, h: Länge; EI: Kraft·Länge²; EA, Knotenlasten, Streckenmoment m: Kraft; Knotenmoment, Drehfeder: Kraft·Länge; q, n, Trapez, p_X, p_Y, Federn cx/cy: Kraft/Länge; To/Tu: Temperatur; α_T: 1/Temperatur). Symbole bekommen ihre Einheit aus den Feldern, das Längensymbol (`l` bzw. das Geometriesymbol) ist eine Länge. Reihenfolge: Geometrie, Steifigkeiten, Knotenlasten, Stablasten, Federn, Temperatur; gemeldet wird das erste Feld, das nicht zu den vorherigen passt, z. B. `Einheiten: Knoten 2, Feder cy = EI/l^2 hat die Einheit Kraft, erwartet wird Kraft/Laenge.` Reine Zahlen werden übersprungen, Groß-/Kleinschreibung zählt nicht, `2l` ohne Malzeichen geht. Summanden mit verschiedenen Einheiten und Argumente von sin/exp/ln mit Einheit werden ebenfalls gemeldet. Gerechnet wird trotzdem. Test: `symbolisch.lua` Fall 14.
- **Verschiebungen als Zehnerpotenz:** Knotenmenü Seite 4 (ü_x, ü_y, ü_ges, phi aus dem WGV) und Stabmenü Seite 7 (Stabendverformungen) zeigen `1.234·10^-5` (`formatExp`); vorher `%.4f` (kleine Werte als 0.0000) bzw. `1,234e-05`.
- **Löschen bei offenem Menü:** `Del` auf einen Knoten oder Stab, während ein Knoten- oder Stabmenü offen ist, stürzt nicht mehr ab. Das Menü bleibt beim selben Element (neue Nummer) oder schließt, wenn genau dieses gelöscht wurde. Im PvV-Modus löscht `Del` nichts (Meldung). Test: `oberflaeche.lua` Fall 25.
- **Rasterpunkte:** Unter 5 Pixel Abstand (kleines Rastermaß, weit herausgezoomt) werden keine Punkte gezeichnet; vorher wurden es Hunderttausende, der Bildschirm wurde grau und der Rechner hing. Test: `oberflaeche.lua` Fall 20.

## Ergänzungen (Schriftgröße)

- **Obermenü Seite 5, Zeile 1 „Schriftgroesse“:** Enter schaltet Normal → Gross → Sehr gross → Riesig → Normal (Faktor 1; 1,25; 1,5; 2). Skaliert werden alle Schriften außer den Menüs (Knoten-, Stab-, Ober-, PvV-Menü) und den festen Warnkästen (kinematisch, starr, PvV-Frage, Löschfrage), weil deren Spalten fest stehen. Zeilenabstände wachsen mit in der Ansicht `l` (LGS, Lösungsweg, FEM-Warnung), in der gelben Box und im Kasten „Symbolischer Modus nicht moeglich“. Die Kopfzeile („Modus“, „n =“, Tipps, Hover „Teilsystem“) bleibt fest. Die Stufe wird über `on.save`/`on.restore` mit dem Dokument gespeichert. Test: `oberflaeche.lua` Fall 26.

## Ergänzungen (Lösungsweg zum Gleichgewichts-LGS)

- **Nummerierte Gleichungen:** `lgs` (und die Ansicht `l`) nummeriert alle Gleichungen: `(1) → TS 1`, `(2) ↑ TS 1`, `(3) ΣM P1 TS 1`; im Fachwerk `(1) → K1`, … Die Momentengleichung nennt Bezugspunkt und Teilsystem (`ΣM P<Knoten> TS <Nr>`).
- **`lgs_weg`:** Liste von Texten, von oben nach unten ein Schritt je Zeile, wie in der Handrechnung:
  - `(4): B_v = 5/2 kN`: Gleichung (4) hat nur noch diese eine Unbekannte.
  - Eine Gleichung, die nicht in `lgs` steht, bekommt die nächste freie Nummer und wird einmal ausgeschrieben, z. B. `(7) ΣM P1 Ges: 6*B_v = 15` (`Ges` = Gesamtsystem), danach ihr Ergebnis.
  - Block aus 2 Gleichungen: `(3): Gx_1 = -Gy_1-5` (aufgelöst), `(7) mit (3): Gy_1 = -2 kN` (eingesetzt), `(3): Gx_1 = -3 kN` (zurückeingesetzt). Bei 3 Gleichungen dieselbe Kette (`(8) mit (3), (5): …`), dann von hinten zurück.
  - Zur Auswahl: Gleichungen aus `lgs`, Momente eines Teilsystems um andere Knoten und um Schnittpunkte zweier Wirkungslinien (`ΣM S(A_h,B_v) …`), Kräfte quer zu einer schrägen Unbekannten (`ΣF quer zu B_h TS 2`), das Gesamtsystem und bei Rahmen zusammengefasste Teilsysteme (`TS 1+2`, höchstens `lgsMaxGruppen`). Momentenpunkte und Querrichtungen je Gruppe nur aus äußeren Kräften der Gruppe (nach dem Zusammenfassen nicht weggefallen): Knoten, durch die eine äußere Wirkungslinie geht, Schnittpunkte zweier äußerer Linien. Bevorzugt: Schritte mit einer Unbekannten, zuerst aus `lgs`, dann andere Momentenpunkte, Gesamtsystem, Zusammenfassungen/Schnittpunkte; danach 2er-, dann 3er-Blöcke, zuletzt der Rest als Block aus `lgs`-Gleichungen.
  - Fachwerk: nur Knotenschnitt plus Gesamtsystem (Lagerkräfte). Ritterschnitt bewusst nicht (Schnittführung in Klausuren meist vorgegeben).
  - Exakt mit dem CAS gerechnet; Brüche mit Zahlen ab 5 Ziffern (aus Dezimaleingaben) zeigt die Anzeige als Dezimalzahl mit 6 Stellen, symbolisch mit den Schreibweisen der Eingabe (`F` statt `f`) und ohne Einheit.
  - Ansicht `l`: „Loesungsweg:“ in Grün unter den Gleichungen. Nicht statisch bestimmt: nur ein Hinweis.
- **Pendelstäbe (Rahmen):** Ein unbelastetes Teilsystem mit genau zwei Anschlüssen, an denen nur Kräfte wirken (gerade oder geknickt, z. B. die unbelastete Hälfte eines Dreigelenkrahmens), liefert seine Achse als zusätzliche Wirkungslinie. Gleichungen um Punkte auf der Achse (z. B. `ΣM S(Pendel TS 2,A_h) Ges`; gleiche Gleichungen anderer Gruppen behalten den Namen mit dem Gesamtsystem) bzw. quer zur Achse enthalten die Pendelkraft nicht mehr; dafür steckt das Momentengleichgewicht des Pendelstabs darin, deshalb kommen sie nach allen übrigen Einzelschritten, aber vor Blöcken. Dreigelenkrahmen mit verschieden hohen Lagern und einer unbelasteten Hälfte brauchen damit keinen Block mehr. Test: `lgs_seite2.lua` Fall 9 und 10 (auch symbolisch).
- **Gegenprüfung LGS gegen FEM:** Nach dem Lösungsweg vergleicht das Programm jede Unbekannte mit dem FEM-Wert gleicher Richtung (Seite 1). Abweichung über 1e-4 des größten Wertes: rote Warnung in der Ansicht `l` und Zusatz in der Export-Meldung („Achtung: LGS und FEM weichen ab bei A_v (LGS …, FEM …)“). Nicht verglichen: System nicht berechnet, PvV-Modus (gelöste Bindung, FEM-Werte gehören zum ursprünglichen System). N-/Q-Gelenkgrößen an Bogenenden werden verglichen (LGS und FEM nehmen die Tangente). Symbolisch mit den Ersatzwerten der FEM. Test: `lgs_seite2.lua` (jeder Fall ohne Warnung) und Fall 11 (verfälschter FEM-Wert ergibt die Warnung).
- **Lagerkräfte zuerst:** Innerhalb derselben Stufe (Einzelschritt, 2er-Block, 3er-Block) gehen Lagergrößen vor: Einzelschritt für eine Lagergröße vor jedem anderen; sonst ein Einzelschritt, nach dem eine Lagergröße als Einzelschritt folgt (ein Schritt vorausgeschaut); unter gleich großen Blöcken der mit mehr Lagergrößen. Ein größerer Block entsteht dafür nie. Sobald alle Lagergrößen bestimmt sind und noch etwas folgt, steht im Weg die Zeile „Alle Auflagerkraefte bestimmt.“ (für Klausuren, die nur nach Lagerkräften fragen). Das exportierte LGS (`lgs`, `ggw_a`, `ggw_b`) bleibt unverändert die Handrechnung zu Seite 2; die Gleichungen des Gesamtsystems stehen nur im Weg mit eigener Nummer. Test: `lgs_seite2.lua` Fall 9 (`lagerZuerst`).
- **Option „LGS wie Lösungsweg“** (Obermenü Seite 3, Zeile 8, `lgsAusWeg`, ab Werk aus): Die abgeleiteten Gleichungen des Weges ersetzen in `lgs`, `ggw_a`, `ggw_b`, der Ansicht `l` und `ggw_eqs` je eine Zeile, die der Weg nicht benutzt (bevorzugt eine, aus der sie entsteht); der Weg nennt dann nur `lgs`-Nummern und schreibt keine Kopfzeilen mehr. Eindeutige Lösbarkeit: Die Weggleichungen sind in Schrittreihenfolge blockdreieckig mit regulären Diagonalblöcken; zusätzlich Rangprüfung, sonst bleibt `lgs` unverändert. Meldung „lgs wie Loesungsweg: n Gleichungen ersetzt“. `lgs_modell.A`/`b` bleiben die Handrechnung zu Seite 2, die ersetzten stehen in `lgs_modell.A_aus`/`b_aus`. Test: `lgs_seite2.lua`, jedes System in `pruefe` (gleiche Lösung, nur `lgs`-Nummern im Weg).
- **Max. Teilgruppen** (Obermenü Seite 3, Zeile 9, `lgsMaxGruppen`, ab Werk 30, 0 = keine): Grenze für zusammengefasste Teilsysteme im Rahmen (Breitensuche, kleine Gruppen zuerst, sortierte Reihenfolge). Ersetzt die feste Grenze „höchstens 8 Teilsysteme, 64 Gruppen“; Systeme mit mehr als 8 Teilsystemen bekommen damit auch Zusammenfassungen. Beide Werte werden mit dem Dokument gespeichert (`on.save`). Test: `lgs_seite2.lua` Fall 12.
- **Variablen löschen** kennt `lgs_weg`. Test: `lgs_seite2.lua` (jede Unbekannte genau einmal, Werte gleich der LGS-Lösung, Einzelschritte mit genau einer neuen Unbekannten; Fall 9 mit Dreigelenkrahmen gleich/verschieden hoch, Gerberträger, Fachwerk).

## Ergänzungen (Anmerkungen zur Anleitung, Oktober 2026)

- **`sys_dof`:** *Alles exportieren* legt zusätzlich die Legende der Freiheitsgrade ab (Liste von Texten in der Reihenfolge von `sys_k`, `sys_f`, `sys_u`, z. B. `"Knoten 2 u_x"`, `"Knoten 2 phi"`, `"Stab 3 phi_b"`; aus `glob_Legend`). Wird bei jedem `b` mit den Systemmatrizen gelöscht und steht in `SKRIPT_VARIABLEN`. Test: `starr.lua` Fall 7.
- **Referenzexporte bei starren Stäben:** `v_EI_stab_i` bzw. `u_EA_stab_i` enthalten bei biegesteifen bzw. dehnsteifen Stäben die Verschiebung w bzw. u selbst (Hermite aus den exakten Endwerten bzw. Gerade), wie `wneu` im Rand-LGS; vorher EI·w mit einer großen Ersatzsteifigkeit. Meldung „Starr: v_EI_stab = w bei Stab …“. Im symbolischen Modus werden starre Stäbe hier nicht exportiert (alte Funktion gelöscht, Hinweis aufs Rand-LGS). Die WGV-Rechnung selbst war und ist exakt (Zwangsbedingungen). Test: `starr.lua` Fall 7.
- **N-/Q-Gelenk am Bogenende:** Das LGS legt `Gn`/`Gq` in Richtung der Tangente am Bogenende (wie die FEM, deren erstes bzw. letztes Teilstück tangential liegt), die Explosionsansicht Seite 2 zeichnet die Pfeile ebenfalls tangential; die FEM-Gegenprüfung vergleicht diese Größen jetzt mit. Test: `lgs_seite2.lua` Fall 13.
- **Last und Lager am Knoten eines N-/Q-Gelenks:** `lastStabKnoten` ordnet sie dem biegesteifen Rest zu, wenn es einen gibt (so rechnet die FEM: die freigegebene Richtung trägt nur der Rest). Vorher gehörten sie zum Stab mit dem Gelenk; bei einem Q-Gelenk mit Querlast am Gelenkknoten wichen LGS und FEM dadurch voneinander ab (auch bei geraden Stäben). Bei reinen Momentengelenken unverändert (erster Stab mit Gelenk). Test: `lgs_seite2.lua` Fall 13 (gerader Träger mit Q-Gelenk und Knotenlast).
- **Arbeitssatz gegen FEM:** Beim Export *Arbeitssatz* (PvV mit gelöster Bindung) löst das Programm `w_eq2` selbst nach der freigesetzten Größe auf (linear: Auswertung bei 0 und 1, Bezugsgröße φ_0 bzw. δ_0 = 1, Symbole mit den Ersatzwerten der FEM) und vergleicht mit dem FEM-Wert des ursprünglichen Systems (die FEM-Ergebnisse an Knoten und Stäben stammen aus der Rechnung vor dem Lösen): H = R_xi, V = −R_eta, M_A = R_m, Gelenkgrößen M/N/Q = positive Schnittgröße am Stabende (Anfang −s_local[i], Ende s_local[i+3]), Knotengelenk am ersten Stab des Knotens. Abweichung über 1e-4 der größten Kraft- bzw. Momentenzahl im System: Zusatz in der Export-Meldung („Achtung: Arbeitssatz und FEM weichen ab bei N (Arbeitssatz …, FEM …)“). Kein Vergleich ohne Berechnung, ohne gelöste Bindung oder wenn ein Lastsymbol so heißt wie die Unbekannte. Test: `arbeitssatz.lua` (jede Freigabe in `pruefe` ohne Warnung, Fall 7 verfälschter Arbeitssatz ergibt die Warnung).
- **N-/Q-Gelenk am Bogenende im PvV:** Polplan (`buildPolplan`, Verschiebungsrichtung der Gelenkverbindung), Arbeitssatz (Richtung der freigesetzten Kraft N bzw. Q) und PvV-Zeichnung nehmen die Tangente am Bogenende (`stabEndAchse`), wie FEM und LGS. Vorher die Sehne: Die freigesetzte Größe war dann die Kraftkomponente längs bzw. quer zur Sehne, nicht N bzw. Q (gefunden über die neue Gegenprüfung). Test: `arbeitssatz.lua` Fall 7 (Kragbogen mit Riegel, Viertelkreis und schiefe Sehne mit R > 0 und R < 0, N-, Q- und M-Gelenk an beiden Bogenenden und am Riegel).
