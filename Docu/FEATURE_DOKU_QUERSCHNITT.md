# Feature-Dokumentation: Statik Programm

Diese Datei dokumentiert alle funktionalen Features des Programms, ihre Möglichkeiten (Zweck) und aktuellen technischen Grenzen. Sie ist bei jeder Änderung an den Lua-Skripten zusammen mit der Funktionsdokumentation zu aktualisieren.

## 0. Programmkonzept und Arbeitsablauf
**Zweck:**
- Das Programm modelliert ebene Querschnitte für Aufgaben der technischen Mechanik und Statik.
- Massivflächen, dünnwandige Mittellinien, Kräfte und Berechnungseinstellungen werden in einem gemeinsamen Modell verwaltet.
- Die Eingabe erfolgt grafisch über das Zeichenfenster; numerische Korrekturen sind anschließend über den Element-Editor möglich.

**Typischer Arbeitsablauf:**
1. Koordinatensystem, Raster, Einheiten und Standarddicke in den Optionen einstellen.
2. Massiv- oder dünnwandige Geometrie zeichnen.
3. Überlappungen und Loch- beziehungsweise Additionsentscheidungen bestätigen.
4. Bei Bedarf Elemente und Punkte über Hover + Enter numerisch nachbearbeiten.
5. Kräfte platzieren und ihre Komponenten im Element-Editor eingeben.
6. Ergebnisse, Normalspannung, Schubspannung, Torsion oder Kernfläche über das Berechnungsmenü öffnen.
7. Bei Bedarf das KOS zum Schwerpunkt verschieben und die Ergebnisse erneut kontrollieren.

**Grenzen:**
- Das Programm ist eine interaktive Querschnitts- und Balkentheorie-Anwendung, keine allgemeine Finite-Elemente- oder 3D-Spannungsanalyse.
- Die Ergebnisse hängen von der gewählten Idealisierung, der Geometrieauflösung und den eingegebenen Vorzeichen ab.

## 1. Massiv-Querschnitte (Menü: M)
**Möglichkeiten:**
- Erstellung verschiedener Grundformen per Mausklick: Rechteck (2 Klicks), Kreis (2), Dreieck (3), Polygon/Trapez (n), Kreisausschnitt/Kreisabschnitt (3) und dicke Linie (2).
- Massivformen können positiv oder als Loch modelliert werden.
- **Loch-Erkennung:** Wird ein Element vollständig innerhalb eines anderen gezeichnet, wird es automatisch als Loch erkannt und die Fläche für die Querschnittswerte abgezogen.
- **Überlappungen:** Bei partieller Überlappung erscheint ein Dialog zur interaktiven Wahl: Abziehen (als Loch), Addieren (als Positivform) oder Verwerfen.
- Bei numerischer Addition wird die überlappende Geometrie rasterbasiert erfasst; das Programm kennzeichnet solche Systeme als numerisch berechnet.
- Die lokalen Flächenwerte, Schwerpunkte und Trägheitsmomente jedes Elements können in der Einzelwertetabelle geprüft werden.

**Grenzen:**
- Komplexe boolesche Operationen (Verschmelzen mehrerer sich überschneidender Positiv-Flächen zu einer einzelnen logischen Rand-Kontur) existieren nicht – Flächen und Trägheitsmomente werden bei "numerischer Addition" lediglich aufsummiert.
- Die automatische Loch- und Überlappungserkennung arbeitet mit Stichproben und kann sehr schmale Überlappungsbereiche übersehen.
- Selbstüberschneidende Polygone und entartete Formen mit nahezu verschwindender Fläche sind nicht zuverlässig auswertbar.

## 2. Dünnwandige Profile (Menü: D)
**Möglichkeiten:**
- Zeichnen von dünnwandigen Segmenten: Linienzüge (n Klicks), Kreise (2) und Kreisbögen (3). Kreise und Bögen sind Mittellinie mal Standarddicke ($A = 2\pi R t$ beim Vollkreis, $I = \pi R^3 t$); früher landeten sie bei den massiven Elementen (voller Kreis bzw. Bogen mit Fläche 0). Ein einzelner dünnwandiger Kreis ist ein Kreisrohr: Torsion nach Bredt ($I_T = 2\pi R^3 t$), Schubmittelpunkt im Mittelpunkt (Sonderweg, exakt). **Kreise und Bögen im Profilgraph:** Sie gehen als Kette kurzer Sehnen ein (höchstens 15° je Sehne, mindestens zwei je Bogenstück), geteilt an Bogenenden, an Endpunkten anderer Elemente auf dem Bogen, an Kreuzungen und Berührungen mit Geraden und anderen Bögen und an den Schwerachsen. Die Sehnen bestimmen nur Knoten, Zusammenhang, Zellen und Symmetrie; gerechnet wird auf dem Bogen: Länge = Bogenlänge, $A_m$ = Sehnenpolygon plus Kreissegment $\frac{R^2}{2}(\Delta\varphi - \sin\Delta\varphi)$ je Sehne, Stützstellen (16 je Sehne) auf dem Bogen mit Bogentangente und radialer Anzeige-Normale, statische Momente und $\int r_\perp\,ds$ geschlossen integriert. Damit laufen Schub (offen und einzellig), Symmetrieerkennung, Schubmittelpunkt, Torsion (Bredt) und Verwölbung auch mit Bögen, z. B. D-Profil, Halbkreis mit Steg, C-Profil mit runden Ecken, Rohr aus zwei Halbkreisen. Genauigkeit gegen Handrechnung etwa $10^{-9}$ (D-Profil: $A_m$, $I_T$, $v_M$; offener Halbkreis: $e = 4R/\pi$; U aus Halbkreis und Stegen; Kreisrohr); gegen eine Polygonnäherung mit 720 Geraden etwa $10^{-6}$ (deren eigener Fehler). Ein Bogenende, das über den Fangpunkt P3 angeschlossen ist, gilt auch dann als verbunden, wenn P3 nicht genau auf dem Radius liegt. Nebenbei behoben: Gerade Linien wurden auch am Schnitt mit der *Verlängerung* einer anderen Linie geteilt; bei feinen Polygonen fiel dadurch ein echter Schnittpunkt auf einen Scheinknoten daneben, und eine Zelle wurde nicht erkannt.
- Jedes Element erhält eine definierte Standarddicke $t$, die sich jederzeit global oder pro Element anpassen lässt.
- Ein Linienzug wird intern in einzelne Zwei-Punkt-Kanten zerlegt.
- Gemeinsame Punkte bleiben als topologisch verbundene Knoten erhalten; dadurch können Verzweigungen, T-Stöße und geschlossene Umläufe erkannt werden.
- Dünnwandige Elemente können gemeinsam mit Massivflächen in einem gemischten Querschnitt verwendet werden.

**Grenzen:**
- Für die Geometrieauswertung erfolgt keine echte Flächenverschneidung an Knotenpunkten; Flächen und Momente basieren auf der Mittellinien-Idealisierung.
- Schnittpunkte werden für die Schubfluss-Topologie atomar aufgeteilt, ändern aber nicht automatisch die ursprüngliche Geometrie zu einer exakten Randkontur.
- Die dünnwandige Näherung vernachlässigt bei geraden Linienelementen das lokale Eigenträgheitsmoment in Dickenrichtung.

## 3. Querschnittswerte & Ergebnisse
**Möglichkeiten:**
- Automatische Berechnung von: Fläche ($A$), Schwerpunkt ($y_s, z_s$), Flächenträgheitsmomenten ($I_y, I_z, I_{yz}$), Hauptträgheitsmomenten ($I_1, I_2$) und dem Hauptachsenwinkel $\alpha$.
- Visuelle Darstellung der Hauptachsen (rot gestrichelt) ausgehend vom Schwerpunkt.
- Anzeige der Trägheitswerte wahlweise bezogen auf den aktuellen Ursprung oder den Schwerpunkt.
- Torsionsflächenmomente ($I_T$) für offene dünnwandige Profile über die Näherung $\sum \frac{1}{3} b_i t_i^3$, mit einstellbarem Korrekturfaktor $\xi$.
- Berechnung für reine Massivquerschnitte, reine dünnwandige Profile und gemischte Querschnitte durch additive Beiträge.
- Ausgabe von Trägheitsradien und Widerstandsmomenten für die Hauptachsen beziehungsweise die resultierenden Querschnittsachsen.
- Anzeige der lokalen Hauptachsen und lokalen Trägheitswerte eines ausgewählten Elements.
- Automatische Aktualisierung der Systemwerte nach dem Zeichnen, Bearbeiten, Verschieben oder Löschen von Elementen.

**Einheiten und Vorzeichen:**
- Intern rechnet das Programm mit N, mm und Nmm; die Anzeige kann zwischen N/kN, mm/cm/dm/m sowie Nmm/Ncm/Nm/kNmm/kNcm/kNm umgeschaltet werden.
- Bei der σx-Eingabe wird die tatsächlich eingestellte Momenteneinheit im Eingabehinweis angezeigt. Der Eingabewert wird genau einmal in Nmm umgerechnet; die anschließende Spannungsberechnung verwendet diesen internen Nmm-Wert ohne weitere Skalierung.
- Bereits bestätigte Eingaben bleiben im Dialog in der eingestellten Einheit sichtbar; interne Nmm-Werte werden nur für die Berechnung verwendet.
- Flächen-, Volumen- und Trägheitseinheiten werden aus der gewählten Längeneinheit abgeleitet.
- Das Deviationsmoment $I_{yz}$ und die Hauptachsenrichtung sind vorzeichenabhängig; die Interpretation muss zusammen mit der aktuellen KOS-Orientierung erfolgen.
- Zahlen können als Dezimalzahl, Bruch oder Wurzel-Bruch angezeigt werden. Das Anzeigeformat ändert nicht die interne Berechnung.

**Grenzen:**
- Gemischte Querschnitte (Massiv + Dünnwandig gleichzeitig) werden rein additiv behandelt; spezielle schubweiche Interaktionen zwischen massiven und dünnwandigen Teilen werden nicht berücksichtigt.
- Bei nahezu verschwindender Gesamtfläche werden keine sinnvollen Systemwerte erzeugt.
- Die Torsionskonstante eines offenen Profils ist eine dünnwandige Näherung und keine allgemeine Saint-Venant-Lösung für beliebig dicke oder komplexe Querschnitte.

### 3a. Querschnittswerte manuell überschreiben (Optionen, Seite 3)
In Klausuren sind die angegebenen Werte für $A$, $I_y$, $I_z$, $I_{yz}$ oft nicht die exakten Werte
der Skizze – gerechnet werden soll aber mit den angegebenen. Deshalb gibt es im Optionsmenü (`o`,
mit Pfeil links/rechts auf Seite 3 „Querschnittswerte“) diese Punkte:

1. `A setzen`, 2. `I_y,S setzen`, 3. `I_z,S setzen`, 4. `I_yz,S setzen` – jeweils mit dem aktuellen
   Wert und dem Zusatz „manuell“, wenn er überschrieben ist; Eingabe im angezeigten KOS, in der
   eingestellten Längeneinheit, bezogen auf den **Schwerpunkt**,
5. `y_S setzen`, 6. `z_S setzen` – Lage des Schwerpunkts im angezeigten KOS und in der
   Längeneinheit; die jeweils andere Koordinate bleibt stehen,
7. `Berechnete Werte wiederherstellen`, 8. `< Zurueck`.

**Schwerpunkt (5, 6):** Gedacht für Aufgaben, die den Schwerpunkt anders angeben als die Skizze
(z. B. 2 cm statt der geometrischen 5/3 cm). Der gesetzte Schwerpunkt gilt für die Hebel der
Normalkräfte („M_y aus Normalkraeften“), σx samt Gleichungen und neutraler Faser, Kernfläche und die
Widerstandsmomente (Randabstände vom neuen Schwerpunkt). Schub, Schubmittelpunkt, Verwölbung und die
Einzelwerte-Tabelle bleiben beim Schwerpunkt der Geometrie, weil sie über die gezeichneten Wände
integrieren und das statische Moment nur um deren eigenen Schwerpunkt verschwindet. Die
Trägheitsmomente werden **nicht** per Steiner verschoben; gibt die Aufgabe einen anderen
Schwerpunkt vor, setzt man $I_y$, $I_z$ aus der Aufgabe mit. Gespeichert wird der Schwerpunkt
relativ zum ersten Punkt der Geometrie, er bleibt also beim KOS-Verschieben an derselben Stelle
des Querschnitts.

**Wirkung:** Die Werte ersetzen am Ende jeder Neuberechnung (`berechneSystem`) die berechneten, und
alles Abgeleitete wird daraus neu gebildet: $I_1$, $I_2$, Hauptachsenwinkel, Widerstandsmomente,
Trägheitsradien. Da alle Rechnungen auf diese Werte zugreifen, gelten sie für $\sigma_x$ (auch die
Gleichungen in der Tabelle), Schubspannung (die statischen Momente bleiben geometrisch),
Schubmittelpunkt, Kernfläche und Torsion aus Kräften. Das Ergebnisfeld markiert überschriebene
Werte mit „(manuell)“, die σx-Tabelle nennt sie in der ersten Zeile, die Einzelwerte-Tabelle weist
darauf hin, dass sie die Werte aus der Geometrie zeigt.

**Zurücksetzen:** Die manuellen Werte gelten, bis sich **der Querschnitt selbst** ändert (Element
hinzugefügt, gelöscht oder bearbeitet, Dicke, Loch). Erkannt wird das über eine Signatur aus
Elementtypen, Dicken, Markierungen und allen Punkten relativ zum ersten Punkt – KOS verschieben
oder drehen, Kräfte setzen und Optionen ändern lassen sie stehen. Nach einer echten Änderung kommt
einmal der Hinweis „Querschnitt geändert: … gerechnet wird wieder mit den berechneten Werten“.

**Prüfung der Eingabe:** $A$, $I_y$, $I_z$ müssen positiv sein und $I_y I_z - I_{yz}^2 > 0$ (sonst
wäre der Querschnitt nicht biegesteif); andernfalls wird die Eingabe mit Begründung abgelehnt.

## 4. Kräfte platzieren
**Möglichkeiten:**
- Einzelkräfte lassen sich mit einem Klick visuell auf dem Querschnitt platzieren.
- Bearbeitung per Element-Editor (Hover + Enter) zur Eingabe von Kräften in der Ebene (z.B. $F_y, F_z$) und aus der Ebene (z.B. $F_x$).
- Grafische Unterscheidung: Kräfte in der Ebene werden als Pfeile gezeichnet (Spitze zeigt auf den Angriffspunkt), Kräfte aus der Ebene als Kreis mit Punkt (heraus) oder Kreuz (hinein). Zusätzlich wird der Kraftangriffspunkt als sichtbarer Punkt markiert.
- Die drei Kraftkomponenten werden abhängig von der aktuellen KOS-Ebene als zwei Komponenten in der Querschnittsebene und eine Komponente senkrecht zur Ebene angezeigt.
- Aus den platzierten Kräften können Resultierende für Normalspannung, Querkräfte für Schubspannung und ein Torsionsmoment um den Schubmittelpunkt gebildet werden (ist der Schubmittelpunkt statisch unbestimmt, wird die Torsion aus Kräften nicht berechnet).

**Grenzen:**
- Für die Normalspannung wird die Kraftkomponente senkrecht zur Querschnittsebene als Normalkraft verwendet; ihre Exzentrizität liefert die Biegemomente.
- Für Schub und Torsion werden die Komponenten in der Querschnittsebene verwendet.
- Eine Kraft senkrecht zur Ebene erzeugt im aktuellen Modell keine zusätzliche Torsion aus einer Exzentrizitätskopplung.
- Die Orientierung der Kraftkomponenten und die Vorzeichen der Momente folgen dem aktuell gewählten Koordinatensystem.

## 5. Normalspannungsberechnung ($\sigma_x$)
**Möglichkeiten:**
- Berechnung der Normalspannung bei gegebener Längskraft ($N$) und Biegemomenten ($M_y, M_z$) nach der Formel für schiefe Biegung.
- Grafische Visualisierung der Spannungsverteilung als farbige Verlaufsschicht (Isolinien) direkt über dem Querschnitt.
- Darstellung der Nullspannungsgerade.
- Ausgabe einer Ergebnistabelle mit Minimal- und Maximalspannungen.
- Eine Eingabemaske: Berechnungsmenü → „σx-Berechnung“ fragt nacheinander $N$, $M_y$, $M_z$ und – bei eingezeichneten Querkräften – $\Delta x$ ab (kein Untermenü; gerade Biegung mit $M_z = 0$).
- Platzierte Kräfte werden immer zu den Eingaben addiert; σx nur aus den Kräften: $N$, $M_y$, $M_z$ mit 0 bestätigen.
- Berücksichtigung des Deviationsmoments $I_{yz}$ bei schiefer Biegung.
- Anzeige der verwendeten manuellen und aus Kräften resultierenden Schnittgrößen getrennt in der Ergebnistabelle.
- **Erweiterte Ergebnistabelle** (mit den Pfeiltasten hoch/runter scrollbar, begrenzt auf den Inhalt; der frühere $\sigma_x$-Verlauf über $z$ unter der Tabelle ist entfallen – die Verteilung zeigt die farbige Darstellung auf dem Querschnitt). Die Wertespalte beginnt hinter der breitesten Beschriftung, solange die breitesten Werte daneben passen; was dann noch zu breit ist, wird in Schrift 7 bzw. 6 gesetzt (Test 40 scrollt durch die ganze Tabelle und prüft, dass nichts überlappt oder über den Rand ragt):
  - Hauptachsensystem: Winkel $\varphi^*$ (von $y$ nach $\eta$), $I_\eta = I_1$, $I_\zeta = I_2$ und die **Momente um die Hauptachsen** $M_\eta = M_y\cos\varphi + M_z\sin\varphi$, $M_\zeta = -M_y\sin\varphi + M_z\cos\varphi$ (Formelsammlung 1.3).
  - **Biegenormalspannung in MPa** als lineare Gleichung im angezeigten KOS, $\sigma_x = c_0 + c_y\,y + c_z\,z$ ($y, z$ vom KOS-Ursprung in der aktuellen Längeneinheit; liegt der Ursprung nicht im Schwerpunkt, steht $y_S, z_S$ darunter), und im HAS, $\sigma_x = N/A + c_\eta\,\eta + c_\zeta\,\zeta$ mit dem Hinweis auf die Form $N/A + (M_\eta/I_\eta)\zeta - (M_\zeta/I_\zeta)\eta$.
  - **Neutrale Faser** ($\sigma_x = 0$) in beiden Systemen als $z = m\,y + n$ bzw. $\zeta = m\,\eta + n$ (bei senkrechter Faser $y = n$ bzw. $\eta = n$; ohne Biegung „keine“).
  - Grundlage ist dieselbe Spannungsebene, die auch Nulllinie und Extremwerte liefert; die HAS-Form entsteht durch Drehung des Gradienten. Test 37 prüft in allen vier KOS-Drehungen, dass die Koeffizienten mit $M_\eta/I_\eta$ und $-M_\zeta/I_\zeta$ übereinstimmen und die Gleichungen an den Extrempunkten $\sigma_{max}$ bzw. $\sigma_{min}$ liefern.
- **Versatz entlang der Stabachse ($\Delta x$ im $yz$-KOS):** Haben eingezeichnete Kräfte eine Komponente in der Querschnittsebene (Querkräfte), fragt die Eingabemaske zusätzlich den Abstand $\Delta x$ zwischen dem betrachteten Schnitt und der Kraftebene ab (als letztes Feld der Maske). Die Querkräfte erzeugen dann $M_y = -\Delta x\,F_z$ und $M_z = \Delta x\,F_y$, überlagert mit den eingegebenen Momenten und den Momenten der exzentrischen Normalkräfte. Das Ergebnis hängt nur vom **Abstand** ab, nicht davon, auf welcher Seite des Schnitts die Kräfte angreifen: für den positiven Teil gilt $\vec M = \vec r \times \vec F$ mit $r_x = +a$, für den negativen $\vec M = -\vec r \times \vec F$ mit $r_x = -a$ – der Querkraftanteil ist in beiden Fällen $M_y = -a F_z$, $M_z = a F_y$. Deshalb rechnet das Programm mit $|\Delta x|$; ein vorzeichenbehaftetes $x$ eingesetzt wäre auf einer Seite falsch. Die Ergebnistabelle zeigt $\Delta x$ und die Momente aus Querkräften in eigenen Zeilen. Die Maske passt mit vier Feldern und Hinweiszeile auf den Bildschirm.

**Grenzen:**
- Berechnungen basieren auf den integralen Querschnittswerten der Gesamtform, spezielle lokale Effekte (z.B. Spannungssingularitäten an scharfen Innenecken) werden nach der elementaren Balkentheorie vernachlässigt.
- Die Extremwertsuche prüft relevante Randpunkte; für stark konkave Geometrien können innere lokale Extremwerte außerhalb dieser Punktmenge liegen.
- Es gibt keine Materialgesetze, Plastizitätsgrenzen, Stabilitätsnachweise oder zeitabhängigen Lastfälle.

## 6. Schubspannungsberechnung ($\tau$) & Schubmittelpunkt
**Möglichkeiten:**
- Berechnung der Schubspannungen aus Querkräften ($V_y, V_z$ bzw. $Q_a, Q_b$) und Torsion ($M_T$).
- Topologie-aware Integration für dünnwandige Profile mit Verzweigungen, Schnittpunkten, offenen Enden und geschlossenen Profilzellen.
- Pfeile markieren die Integrationsrichtung entlang der dünnwandigen Elemente.
- Die Beschriftung "Start" erscheint nur am tatsächlichen Integrationsbeginn: bei offenen Profilen am freien Rand und bei geschlossenen Profilen am Symmetrieachsen-Start; bei Mischprofilen werden beide Arten angezeigt.
- Interaktive Wahl des Betrachtungsmodus ("V" drücken), um statische Momente ($S_y, S_z$), einzelne Schubspannungsanteile oder die resultierende Gesamtschubspannung ($\tau_{gesamt}$) zu visualisieren.
- Numerische Ausgabe der maximalen Schubspannung und deren Lage (z.B. $\tau_{max}$, $\tau_{gesamt,max}$).
- Automatische Berechnung und Anzeige des Schubmittelpunkts für offene, symmetrisch geschlossene und gemischte dünnwandige Profile.
- Die Schubspannungsansicht kann über zehn Darstellungen geprüft werden: zwei Momentendichten, zwei statische Momente, zwei Querlastanteile, Torsionsanteil, resultierende Schubspannung und Laufkoordinate $s$.
- Für Kontrollen stehen die integrierten Teilkräfte und Momentbeiträge je Element in einer Schubmomenttabelle bereit.
- Bei einer Last aus platzierten Kräften können die beiden Querkraftkomponenten automatisch aus den Kraftresultierenden übernommen werden.
- Offene Profile (auch unsymmetrisch, mit $I_{yz}$-Kopplung $\tau = -\frac{Q_z (I_y S_y + I_{yz} S_z)}{(I_y I_z - I_{yz}^2)\,t}$, für $Q_y$ analog) und Profile mit genau einer geschlossenen Zelle (auch mit offenen Ästen, z. B. Kasten mit überstehendem Gurt). Wirkt die Querkraft parallel zu einer Symmetrieachse, ist der Schubfluss antisymmetrisch und $q_0$ folgt wie in TM2 aus der Symmetrie; freie Äste werden vorher integriert.
- **Fehlt die Symmetrieachse parallel zur Querkraft** (unsymmetrische Zelle, Querkraft quer zur einzigen Achse, Symmetrie nicht erkannt), folgt $q_0$ aus der **Verträglichkeit**: Unter einer Querkraft im Schubmittelpunkt verdrillt sich die Zelle nicht, also $\oint q/(G t)\,ds = 0$. Weil die Matrix $\begin{pmatrix} I_y & I_{yz} \\ I_{yz} & I_z \end{pmatrix}$ regulär ist, zerfällt das in $\oint S_z/t\,ds = 0$ und $\oint S_y/t\,ds = 0$ – je eine Konstante für $S_z$ und $S_y$, unabhängig von $Q$ und von der Kopplung. Damit stimmen auch die angezeigten statischen Momente, und der Schubmittelpunkt ist für jede einzellige Zelle bestimmt (damit auch „Torsion aus Kräften“). Beim symmetrischen Profil liefert die Bedingung dieselbe Lösung wie die Spiegelung (Test 30 prüft das Stützstelle für Stützstelle). Die Warnungen zur fehlenden Symmetrie bleiben erhalten und sagen dazu, dass $S$ und $\tau$ trotzdem richtig sind; die Startmarke heißt dann **Schnitt (q0 aus Verträglichkeit)**.
- Nur **mehrzellige** Profile bleiben statisch unbestimmt: Die Rechnung bricht mit einer Meldung ab.
- Massive Querschnitte: $\tau = Q S/(I b)$ über waagerechte bzw. senkrechte Schnitte (auch für Sektor, Kreisabschnitt und dicke Linie), nur wenn $I_{yz} = 0$ ist. Gemischte massiv/dünnwandige Querschnitte werden nicht berechnet. Die Schnittbreite ist exakt (Kreisausschnitt/-abschnitt als Kreis mit Halbebenen, nicht mehr als 96-Eck); die etwa 160 Stützstellen liegen auf den Streifengrenzen, alle Knickstellen der Breite und die Schwerachse sind Grenzen. $S$ kommt aus 3-Punkt-Gauß je Streifen (an Knickstellen fein unterteilt) und ist an beiden Rändern genau 0, also auch $\tau = 0$ am Rand (Spitzen, Kreisscheitel: Grenzwert 0). An Breitensprüngen (Flansch/Steg, Lochrand) zwei Stützstellen mit der Breite darunter und darüber. Früher: $\tau$ an der Streifenmitte mit $S$ bis zur Streifenunterkante, oberster Wert nie 0 (Rechteck 2,5 %, Kreis 3,7 % von $\tau_{max}$), Rand nie als Stützstelle. Genauigkeit: Rechteck, I-Profil exakt; Kreis $4/3\,Q/A$ auf etwa $2\cdot 10^{-7}$, Dreieck $1{,}5\,Q/A$ auf etwa $10^{-5}$ (Maximum zwischen zwei Stützstellen). Die Verläufe 3/4 ($S$) zeigen jetzt auch bei massiven Querschnitten $S$.
- Eingegebene Querkräfte und Momente beziehen sich auf das angezeigte KOS und werden intern gedreht (auch bei KOS-Drehung 90°/270°).
- Die Schubmomententabelle verwendet die aktuell aktive Querschnitts-KOS und zeigt hinter jeder Lastspalte den zugehörigen effektiven Hebelarm $r=M/F$.
- Die Lastspalten zeigen die signierten Teilschubkräfte; kleine Werte unter $0{,}01$ werden exponentiell formatiert. Der Hebelarm bleibt signiert, damit $M=F\,r$ nachvollziehbar bleibt.
- Die Schubspannungsanteile werden aus dem statischen Moment mit der Vorzeichenkonvention $q=-Q S/I$ beziehungsweise $\tau=-Q S/(I t)$ berechnet.

**Grenzen:**
- Die exakte Visualisierung und Verteilung des Schubflusses ist primär auf dünnwandige Profile zugeschnitten. Bei rein massiven Vollquerschnitten basiert die Berechnung auf einer schichtweisen Integration, die bei komplexen Geometrien (z.B. sternförmig) an die Grenzen der 1D-Balkentheorie stößt.
- Mehrzellige Profile werden nicht berechnet (keine Mehrzellenrechnung).
- Liegen die Hauptachsen nicht parallel zu y/z ($I_{yz} \ne 0$, Winkel kein Vielfaches von 90°), erscheint bei dünnwandigem Schub ein gelber Hinweis mit dem Hauptachsenwinkel: Der Schubfluss wurde mit $I_{yz}$-Kopplung (schiefe Biegung) berechnet, nicht mit $\tau = QS/(It)$. Bei massiven Querschnitten wird der Schub in diesem Fall abgelehnt (rote Box mit Begründung). Das Ergebnisfeld zeigt grün „Hauptachsen parallel zu den Achsen“ bzw. orange „Hauptachsen nicht parallel zu den Achsen“.
- Die Stützstellendichte ist an das Zeichenraster gekoppelt (mindestens 64 Intervalle je Kante, gerade Anzahl). Die $S$-Werte an den Stützstellen sind davon unabhängig exakt (Mittelpunktsregel auf linearem Integranden); Umlauf- und Momentintegrale (Verträglichkeit, Schubmittelpunkt, Verwölbung) laufen mit Simpson je Kante und sind für die dort quadratischen bzw. kubischen Integranden ebenfalls exakt. Bogensehnen: 16 Intervalle je Sehne, $S$ geschlossen integriert, Simpson auf den glatten Integranden auf etwa $10^{-10}$ genau.
- Laufrichtungspfeile: auf Bögen einer je Bogenstück (auf der mittleren Sehne), nicht auf jeder Sehne. Beim Hover zeigt der Verlauf nur das Element; durchläuft ein Pfad es zweimal (aufgeschnittene Zelle), bleiben es zwei Abschnitte ohne Verbindungslinie.

**Zeichnen der Verläufe:** Die Rechnung war nie der Engpass, das Zeichnen schon – pro Frame wurden alle Stützstellen neu sortiert, mehrfach ausgewertet und einzeln als Linie gezeichnet. Jetzt baut `verlaufAbschnitte` die sortierten Abschnitte mit Werten und Pixelversatz einmal auf (ungültig bei neuem Ergebnis, Ansichtswechsel, Torsion, KOS-Drehung oder Hover), und `drawVerlauf` zeichnet je Frame nur noch **eine Polylinie je Abschnitt**, auf etwa einen Punkt je 1,5 px ausgedünnt. Min/Max und Endwerte kommen weiterhin aus allen Stützstellen. Die frühere Suche nach der nächsten Stützstelle bei jeder Mausbewegung (mit Neuzeichnen) ist entfallen – sie wurde nie angezeigt.
- Die Angaben zur Schubspannung werden in MPa dargestellt, sofern die internen Einheiten N und mm verwendet werden.

## 6a. Verwölbung dünnwandiger Profile (Menü: b → 7)
**Möglichkeiten:**
- Eigener Modus unter `b` → **7. Verwölbung**. Ein Dialog fragt das Torsionsmoment $M_T$ (vorbelegt mit dem Moment der platzierten Kräfte um den Schubmittelpunkt, sonst leer) und den Schubmodul $G$ in N/mm² (vorbelegt 81 000). Das hier eingegebene $M_T$ gilt **nur in dieser Ansicht** und wird nicht an die Torsion der Schubspannungsrechnung übergeben; `Esc` schließt die Ansicht und verwirft es.
- Formel der Formelsammlung (Kap. 6): $u_x(s) = \int \left[ \frac{M_T}{2 G A_m h(s)} - r_\perp \vartheta \right] ds + c$ mit $\vartheta = M_T/(G I_T)$ und $I_T = 4A_m^2/\oint ds/h$ (Bredt).
- **Pol** ist der Schubmittelpunkt (Drillruhepunkt). $r_\perp = (y-y_M)\,t_z - (z-z_M)\,t_y$ ist der vorzeichenbehaftete Abstand des Pols von der Kantentangente: positiv, wenn der Fahrstrahl vom Pol zum Laufpunkt in Laufrichtung im Sinn des positiven Torsionsmoments dreht – derselbe Umlaufsinn wie der Bredt-Schubfluss. Für eine konvexe Zelle mit Pol innen ist das überall der positive Abstand (Handrechnung); bei offenen Profilen mit Pol außerhalb (C-Profil) wechselt das Vorzeichen zwischen Steg und Flanschen.
- **Konstante $c$** aus $\int u_x\,h\,ds = 0$ (keine mittlere Längsverschiebung, $N = 0$). Bei symmetrischen Profilen ist die Verwölbung antisymmetrisch, $u_x$ auf der Achse also automatisch null – genau der Startpunkt der Handrechnung. Der Startknoten der Integration liegt wie der Zellschnitt möglichst auf einer Symmetrieachse; das Ergebnis hängt wegen $c$ nicht davon ab.
- $r_\perp$ ist auf geraden Kanten linear, $u_x$ quadratisch: beides wird geschlossen integriert, die Stützstellen dienen nur der Darstellung. Auf Bögen: $\int r_\perp\,ds = R[(y_C - y_M)(\sin\varphi - \sin\varphi_1) - (z_C - z_M)(\cos\varphi - \cos\varphi_1) + R(\varphi - \varphi_1)]$, ebenfalls geschlossen; der Verlauf wird je Bogenstück als ein Abschnitt (nach dem Winkel geordnet) gezeichnet. Ein Kreisrohr (auch aus zwei Halbkreisen) verwölbt sich nicht ($u_x \approx 10^{-17}$). Für die Zelle wird geprüft, dass der Umlauf schließt (`schluss` ≈ 0).
- **Offene Profile:** kein umlaufender Schubfluss, der Bredt-Term entfällt, $u_x = -\vartheta \int r_\perp\,ds + c$ mit $I_T = \sum \xi/3\,h^3 \ell$. Standardtheorie, aber nicht in der Formelsammlung – deshalb eine **Warnung** statt eines Fehlers.
- **Darstellung** wie die Schubverläufe (normal zur Wand, min/max, Endwerte) in Grün; $M_T$ wird als Drehpfeil um den Pol gezeichnet (gegen den Uhrzeigersinn für $M_T > 0$, wie der Bredt-Schubfluss), platzierte Kräfte werden in dieser Ansicht ausgeblendet. Das Ergebnisfeld (`e`) zeigt $M_T$, $G$, $I_T$, $A_m$, $\vartheta$, $u_{x,max}$ mit Lage und den Pol.
- **Prüfungen (Tests 32/33):** Quadratrohr wölbt nicht ($u_x \equiv 0$, das prüft nebenbei die Vorzeichenkonsistenz von Bredt-Term und $r_\perp$), Rechteckrohr $b \times h$ mit konstantem $t$: Eckwerte $|u| = \vartheta\,b h |b-h| / (4(b+h))$ alternierend, mittlere Verwölbung null; C-Profil: $|u| = \vartheta (h/2)(b-e)$ an den Flanschspitzen, $\vartheta\,e\,h/2$ an den Stegenden, null in Stegmitte.

**Grenzen:**
- Nur rein dünnwandige Profile (gerade Elemente, Kreise und Bögen); massiv, gemischt oder mehrzellig: Fehler mit Begründung.
- Reine Saint-Venant-Verwölbung; keine Wölbkrafttorsion, keine Wölbnormalspannungen.
- **Anzeige kleiner Werte:** $u_x$ im Verlauf sowie `u_x,max` und `theta` im Ergebnisfeld stehen unter 0,01 als Zehnerpotenz (`1.029·10^-4`, `formatKlein`). Vorher riet `formatLabel` einen Bruch und zeigte Werte wie 0,000012 als 0.

## 7. Kernfläche
**Möglichkeiten:**
- Berechnung der Kernfläche des Querschnitts zur Sicherstellung einer überdrückten/überzogenen Fuge.
- Anzeige sowohl der umhüllenden Geraden als auch der zugehörigen Kernpunkte.
- Umschalten zwischen der Darstellung der umhüllenden Geraden und dem Kernflächenpolygon über den Kernflächenmodus.
- Hover über einer umhüllenden Geraden: Schnittpunkte mit den Hauptachsen 1 (η) und 2 (ζ), beschriftet mit dem Abschnitt vom Schwerpunkt aus (vorzeichenrichtig in Richtung der gezeichneten Achsen); parallel zu einer Hauptachse: Pfeil „inf“. Damit gilt die Handformel $\eta_K = -i_\zeta^2/a_\eta$, $\zeta_K = -i_\eta^2/a_\zeta$. Früher lagen die Punkte auf Schwerachsen parallel zum KOS und waren mit KOS-Koordinaten beschriftet, das passte bei $I_{yz} \ne 0$ zu keiner Handrechnung.
- Hover über einem Kernpunkt (Seite 2): Koordinaten im gezeichneten KOS und im HAS (η, ζ vom Schwerpunkt aus), zweizeilig, am rechten Rand eingerückt.
- Die gestrichelten Hauptachsen 1 und 2 zeigen in Richtung η und ζ wie in der σx-Tabelle (φ* von der angezeigten y-Achse aus); bei gedrehtem KOS zeigten sie früher teils entgegengesetzt. Getestet in `Emulator/tests/querschnitt.lua` (Fälle 43 und 44: Handformel für alle Kanten eines Trapezes bei KOS 0°, 90°, 180°; Kerndrittel am Rechteck).
- Die Kernfläche kann als Kontrolle für die Lage einer Druckresultierenden relativ zum Schwerpunkt genutzt werden.

**Grenzen:**
- Die Aussagekraft hängt von der zugrunde liegenden Querschnittsmodellierung und den berücksichtigten Randkonturen ab.
- Die Konstruktion basiert auf der konvexen Hülle der gesammelten Rand- und Stützpunkte.
- Bei stark konkaven Querschnitten, Löchern oder grob abgetasteten Bögen kann die dargestellte Kernfläche eine Näherung sein.

## 8. Interaktives Koordinatensystem (KOS)
**Möglichkeiten:**
- Das Raster (Fangradius für Klicks) ist numerisch frei definierbar.
- **Fangpunkte:** Die Punkte, die Flächen und Elemente definieren, wirken wie zusätzliche Rasterpunkte – Eckpunkte von Rechteck, Dreieck und Polygon (beim Rechteck auch die beiden abgeleiteten Ecken), Mittel- und Randpunkte von Kreisen, Sektoren und Bögen, Endpunkte dünnwandiger Linien und dicker Linien sowie die schon geklickten Punkte des Elements, das gerade entsteht. Ein Klick landet auf dem nächsten Kandidaten, gleich ob Raster- oder Fangpunkt. So lassen sich auch Punkte treffen, die nach exakter Koordinateneingabe oder einer KOS-Verschiebung nicht mehr auf dem Raster liegen.
- Das KOS kann durchgeschaltet werden (Projektionen xy, yz, xz) und in 90°-Schritten rotiert werden.
- Alle Achsenbeschriftungen (z.B. in Tabellen, Menüs oder Kraft-Labels) passen sich dynamisch der aktuellen KOS-Wahl an.
- Die visuelle Größe des KOS-Kreuzes auf dem Bildschirm ist einstellbar.
- Das KOS kann zum Schwerpunkt verschoben werden; alle gemeinsamen Geometrie- und Kraftpunkte werden dabei nur einmal verschoben.
- Das KOS kann außerdem um einen eingegebenen Betrag **entlang der angezeigten Achsen** verschoben werden (Optionen Seite 2, Punkte 2 und 3, Eingabe in der aktuellen Längeneinheit). Positive Werte verschieben den Ursprung in positive Achsrichtung; die Koordinaten aller Punkte und Kräfte ändern sich um den negativen Betrag. Die Ansicht wird dabei mitgeführt: der Querschnitt bleibt auf dem Bildschirm stehen, sichtbar wandert das KOS (mit ihm das Raster). Die KOS-Drehung wird berücksichtigt.
- Die Drehung betrifft die Anzeigeorientierung in 90°-Schritten und wird bei Koordinaten, Beschriftungen, Kraftkomponenten und Momenten konsistent berücksichtigt.
- Das Raster dient sowohl zum Fangen von Eingabepunkten als auch als Einflussgröße für bestimmte numerische Integrationen.

**Grenzen:**
- Die KOS-Drehung ist auf vier Orientierungen (0°, 90°, 180°, 270°) beschränkt.
- Eine Verschiebung des KOS ist keine Rotation und verändert nicht die physikalische Geometrie; durch die Neuberechnung ändern sich jedoch die ursprungsbezogenen Darstellungwerte.
- Die Anzeigeeinheiten und das Zahlenformat beeinflussen nur Darstellung und Eingabeumrechnung, nicht die internen Basiseinheiten.
- Die Verlaeufe `z*h(z)`, `y*h(y)` sowie `S_y/S_z` verwenden fuer ihre Vorzeichen dieselbe Orientierung wie das gezeichnete Koordinatensystem; die numerischen Werte an den Verlaufenden werden ohne das zusaetzliche Praefix `Rand` angezeigt.

## 9. Element-Editor (Hover + Enter)
**Möglichkeiten:**
- Fährt der Mauszeiger über ein Element (Massiv, Dünnwandig, Kraft) und wird "Enter" gedrückt, öffnet sich ein kontextsensitives Bearbeitungsmenü.
- Manuelle und exakte numerische Nachkorrektur aller Stützpunktkoordinaten (P1, P2, ...).
- Umschalten der Eigenschaft "Positiv" vs. "Loch".
- Vertauschen von Start- und Endpunkten bei Bögen, um die Krümmungsrichtung umzukehren.
- Element Löschen (Rückgängig-Funktion).
- Bei dünnwandigen Elementen kann die Dicke $t$ individuell geändert werden.
- Bei Kräften können Angriffspunkt und alle drei Komponenten numerisch bearbeitet werden.
- Bei Bögen kann die Reihenfolge von Start- und Endpunkt getauscht werden, um die Umlaufrichtung zu ändern.

**Grenzen:**
- Der Editor bearbeitet einzelne gespeicherte Elemente; eine automatische Neuvernetzung oder geometrische Verschmelzung wird nicht durchgeführt.
- Nachträgliche Änderungen können die Einordnung als Loch, die Topologie oder die Symmetrie des Gesamtmodells beeinflussen und lösen deshalb eine Neuberechnung aus.

## 10. Berechnungs- und Anzeigeauswahl
**Möglichkeiten:**
- Aufruf der Berechnungsansicht über das Menü beziehungsweise den Tastaturkurzbefehl `b`.
- Umschaltung zwischen Ergebnis-, Spannungs- und Schubflussdarstellungen ohne Änderung der Geometrie.
- Interaktive Bearbeitung der Eingangsgrößen für Normalspannung, Schubspannung und Torsion.
- Die Ergebnisse können als Tabellenansicht, Normalspannungsverteilung, Schubspannungsverlauf oder Torsionsdarstellung betrachtet werden.
- Tabellen und Ergebnisbereiche unterstützen Scrollen, wenn die verfügbaren Zeilen oder Elemente die Bildschirmhöhe überschreiten.
- Die zentrale Ergebnisanzeige enthält unter anderem Fläche, Schwerpunkt, Trägheitswerte, Hauptträgheitswerte, Widerstandsmomente, Torsionswerte und verfügbare Schubspannungsresultate.

**Tastatur- und Bedienkürzel:**
- `m`: Massiv-Element zeichnen.
- `d`: Dünnwandiges Element zeichnen.
- `b`: Berechnungsmenü öffnen (1 Querschnittswerte, 2 Einzelwerte-Tabelle, 3 σx, 4 Kernfläche, 5 Schubspannung, 6 Schubmittelpunkt, 7 Verwölbung, 8 Schließen).
- `e`: Ergebnistabelle öffnen.
- `t`: Einzelwertetabelle öffnen.
- `v`: Schubverlaufs-Auswahl öffnen; Ziffern `0` bis `9` wählen die Darstellung.
- `k`: Kernflächenmodus weiterschalten.
- `o`: Optionen öffnen; Pfeil links/rechts blättert zwischen Seite 1 (`Optionen`), Seite 2 (`Weitere Optionen`) und Seite 3 (`Querschnittswerte`, manuelles Überschreiben von A, I_y, I_z, I_yz und Schwerpunkt y_S, z_S, siehe 3a). Seite 2 enthält `KOS in Schwerpunkt verschieben`, `KOS entlang y verschieben`, `KOS entlang z verschieben`, `FTM-Bezug`, `Rasterpunkte` (Zeile 5, Enter schaltet `rasterPunkte` Normal → Dick → Keine; 1×1- bzw. 2×2-Pixel oder keine Punkte, das Fangen am Raster bleibt; unter 5 Pixel Abstand werden keine Punkte gezeichnet) und `Bemassung` (Zeile 6, Enter schaltet `zeigeBemassung` An → mit Schwerpunkt → Aus; Zeile 7 zurück). **Bemaßung:** Maßketten unter und links neben dem Querschnitt wie im Tragwerksskript, zwischen allen Ecken, Linienendpunkten, Kreismittelpunkten und den äußersten Punkten von Kreisen und Bögen (dünnwandig: Mittellinie), Werte in der Längeneinheit; *mit Schwerpunkt* setzt den Schwerpunkt als violette Marke `S` in beide Ketten. In den Ansichten Schub, Verwölbung, σx und Kern aus. `h` (Zoom) lässt bei eingeschalteter Bemaßung unten und links 40 Pixel mehr Platz.`FTM-Bezug`: dieser Schalter legt fest, ob die angezeigten Flächenträgheitsmomente auf den **Schwerpunkt** (Standard) oder auf den **Ursprung des gezeichneten KOS** bezogen sind. Er wirkt auf die Ergebnisliste (`I_y,S` bzw. `I_y (KOS)`) und auf die Einzelwerte-Tabelle (Steiner-Anteile und Gesamtwerte, Überschrift nennt den Bezug).
- `h`: Geometrie automatisch einpassen.
- `+`/`-`: Zoom ändern.
- `Esc`: Aktuelle Eingabe oder Ansicht abbrechen. Ist eine Meldungsbox offen, schließt das erste `Esc` nur die Box.
- **Meldungsbox:** Gründe, warum etwas nicht berechnet wurde (Schub, Torsion, $\sigma_x$), ungültige Eingaben und Hinweise erscheinen als Box in der Bildmitte (rot: nicht berechnet bzw. Eingabefehler, gelb: Hinweis). Sie verschwindet mit `Esc`, beim Start einer neuen Berechnung oder wenn sich der Querschnitt ändert.
- `del` (auf dem Rechner `on.backspaceKey`, Entf der Computersoftware `on.deleteKey` gleich): löscht das Element unter dem Zeiger (Hover: Massivelement, Loch, dünnwandige Linie, Kreis, Bogen, Kraft) und rechnet neu; ein schon gerechneter Schubverlauf wird verworfen. Steht der Zeiger auf keinem Element, wird nichts gelöscht und ein Hinweis erscheint (kein Rückfall auf das zuletzt gezeichnete Element, damit nichts Unsichtbares verschwindet). Beim Linienzug nimmt `del` den letzten Punkt zurück, in einer Eingabemaske (σx, Schub, Torsion, Verwölbung, Menüwert) das letzte Zeichen. Bei offenem Menü, offener Tabelle oder in einem Zeichenmodus löscht `del` nichts (Hinweis). Liegt ein Loch nach dem Löschen in keinem Element mehr, erscheint ein Hinweis. Nach `Esc` und ohne Element unter dem Zeiger fragt `del` wie bisher, ob alles gelöscht werden soll.
- `c` beziehungsweise die Clear-Taste: alles löschen. Vorher erscheint die Rückfrage **„Wirklich alles loeschen?“** – `Enter` löscht, `Esc` bricht ab. Bei leerem Querschnitt entfällt die Rückfrage.
- Alle Menüs (Zeichnen, Optionen, Berechnungen, Element-Editor) und die Schubverlaufs-Auswahl stehen am **linken** Bildschirmrand; die Auswahl wird zuletzt gezeichnet und liegt damit über Kräften und Achsen.

**Grenzen:**
- Die Berechnung verwendet die im Programm hinterlegte Mittellinien- und Balkentheorie-Idealisierung; reale 3D-Effekte und lokale Spannungsspitzen werden nicht abgebildet.
- Das Modell besitzt keine persistenten Lastkombinationen, Materialdatenbank, Projektdatei-Verwaltung oder automatische Berichtserzeugung.

**Geschlossene Zellen und Symmetrie:** Bei genau einer geschlossenen Zelle folgt der konstante Umlaufschubfluss $q_0$ aus der Spiegelsymmetrie des Profils.

- **Erkennung:** Die Mittellinien werden abgetastet (jeder Punkt muss gespiegelt wieder auf einer Kante gleicher Dicke liegen); die Symmetrie wird also auch erkannt, wenn beide Hälften unterschiedlich in Segmente geteilt sind. Die Ergebnisliste zeigt bei geschlossenen Profilen schon vor der Schubrechnung `Zellsymmetrie: z, y-Achse`, `Zellsymmetrie: z-Achse` mit `  q0 fuer Q_y aus Vertraeglichkeit` bzw. `Zellsymmetrie: keine erkannt` mit `  q0 aus Vertraeglichkeit` (vorher „(q0 offen)“, das als „offenes Profil“ missverstanden wurde).
- **Schnitt auf der Symmetrieachse:** Dort ist der Schubfluss null, die Laufvariable beginnt also wie in der Handrechnung bei $S = 0$. Der nötige Knoten entsteht automatisch, weil die Elemente an den Schwerpunktachsen geteilt werden; bei zwei Querkraftkomponenten wird die Achse der größeren gewählt. Die Startmarke zeigt den Fall: **Start** am freien Ende, **Start (Symmetrieachse)** am Zellschnitt, **Schnitt (q0 aus Verträglichkeit)**, wenn $q_0$ für eine Richtung aus der Verträglichkeit kam.
- **Statische Momente:** Die $S$-Werte der Zelle werden auf diesen symmetrischen Schnitt bezogen. Die angezeigten $S$-Verläufe stimmen damit auch ohne eingegebene Querkraft mit der Handrechnung überein, nicht nur $\tau$.
- **Warnungen:** Ohne erkannte Symmetrie oder mit Querkraft quer zur einzigen Achse wird an beliebiger Stelle geschnitten und $q_0$ aus der Verträglichkeit bestimmt. Die Warnung bleibt bewusst erhalten (die Symmetrie fehlt), sagt aber, dass $S$ und $\tau$ trotzdem richtig sind, und nennt die erkannten Achsen; dasselbe gilt für die Warnung beim Wechsel auf einen Verlauf der Richtung ohne Achse. Schneidet die Achse die Zelle nicht (Schwerpunkt außerhalb), wird ebenfalls gewarnt.

## 11. Bekannte fachliche und technische Grenzen
**Geometrie:**
- Mehrzellige und unsymmetrische geschlossene dünnwandige Profile sind statisch unbestimmt und werden für Schub und Torsion abgelehnt.
- Torsion wird nur für rein dünnwandige Profile berechnet: offen $I_T = \sum \frac{\xi}{3} h t^3$, $\tau_{max} = M_T t_{max}/I_T$; einzellig geschlossen (Bredt) $I_T = 4A_m^2/\oint ds/t$, $\tau_{max} = M_T/(2A_m t_{min})$. Massive Querschnitte (Prandtl) werden nicht berechnet.
- Kreis- und Bogenelemente werden für bestimmte Prüfungen und die Kernfläche durch Stützpunkte angenähert.

**Berechnung:**
- Die verwendeten Formeln sind Querschnitts- und Balkentheorie-Näherungen. Lokale 3D-Effekte, Spannungssingularitäten und Verformungskompatibilität realer Bauteile sind nicht enthalten.
- Numerische Überlappungs- und Rasterverfahren sind auf die gewählte Geometrieauflösung angewiesen.
- Die Ergebnisse sollten bei kritischen Aufgaben mit einer unabhängigen Rechnung oder einem geeigneten Statikprogramm kontrolliert werden.

**Bedienung und Laufzeit:**
- Sehr lange Menüzeilen und große Tabellen können auf dem begrenzten TI-Nspire-Bildschirm nur durch Scrollen vollständig gelesen werden.
- Die TI-Nspire-Lua-Laufzeit besitzt eine Begrenzung für lokale Upvalues pro Funktion; größere Erweiterungen müssen diese technische Grenze berücksichtigen.
- Eine Prüfung auf realer TI-Nspire-Hardware ist zusätzlich zur Syntaxprüfung empfehlenswert.

## 12. Meldungen und Hinweise (Übersicht)

Meldungen erscheinen als Box in der Bildmitte: rot, wenn etwas nicht berechnet wurde oder eine Eingabe ungültig war, gelb bei Hinweisen. `Esc` schließt zuerst die Box, ebenso der Start einer neuen Berechnung oder eine Änderung am Querschnitt. Die interne Statuszeile (`status`) wird nicht gezeichnet; Aufforderungen wie „Q eingeben“ stehen in den Eingabemasken selbst.

| Titel / Meldung | Wann | Warum |
|---|---|---|
| **Schub nicht berechnet:** Kombination massiv und dünnwandig | Gemischter Querschnitt | Dafür gibt es keine TM2-Formel |
| … Hauptachsen nicht parallel zu y/z (Winkel) | Massiver Querschnitt mit $I_{yz} \ne 0$ | $\tau = QS/(Ib)$ gilt nur bei Hauptachsen parallel zu den Achsen |
| … Mehrzelliges Profil: statisch unbestimmt | Zwei oder mehr geschlossene Zellen | Nur statisch bestimmte Fälle werden gerechnet |
| **Warnung:** Geschlossene Zelle: für die Querkraft … fehlt die Symmetrieachse | Eine Zelle, Querkraft nicht parallel zu einer Symmetrieachse | $q_0$ kommt aus der Verträglichkeit, $S$ und $\tau$ sind trotzdem richtig |
| **Warnung:** Geschlossene Zelle ohne erkannte Symmetrie | Keine Spiegelachse durch den Schwerpunkt erkannt | $q_0$ aus der Verträglichkeit, $S$ und $\tau$ trotzdem richtig; Hinweis auf gleiche Dicken |
| **Warnung:** S bzw. τ setzt die Symmetrie zur …-Achse voraus | Ansicht 3–6 in einer Richtung ohne Achse | wie oben |
| … Trägheitsmomente singulär | $I_yI_z - I_{yz}^2 \approx 0$ | Division durch null |
| … Umlaufintegral der Zelle nicht auswertbar | Numerischer Sonderfall ($\oint ds/t = 0$) | Schutz vor falschem $q_0$ |
| **Verwölbung nicht berechnet:** nur rein dünnwandige Profile / Mehrzelliges Profil / I_T = 0 / Schubmittelpunkt nicht bestimmbar | Massiv oder gemischt, zwei Zellen, kein Torsionswiderstand | Keine TM2-Formel bzw. statisch unbestimmt |
| **Warnung:** Offenes Profil: … nicht in der Formelsammlung | Verwölbung eines offenen Profils | $u_x = -\vartheta \int r\,ds + c$ ist Standardtheorie, steht aber nicht in der Formelsammlung |
| **Hinweis:** V gehört zur Schubspannungsansicht | `v` in der Verwölbungsansicht | Bedienhinweis, `Esc` schließt die Verwölbung |
| **Hinweis:** Hauptachsen nicht parallel zu y/z (Winkel), I_yz-Kopplung | Dünnwandiges Profil mit $I_{yz} \ne 0$ | Der Schubfluss wird mit Kopplung gerechnet (schiefe Biegung), nicht mit $\tau = QS/(It)$ |
| **Torsion nicht berechnet:** nur rein dünnwandige Profile | Massiv oder gemischt | Keine Prandtl-Lösung in TM2 |
| … Mehrzelliges Profil | Zwei oder mehr Zellen | Statisch unbestimmt |
| … I_T = 0 | Kein Torsionswiderstand | Division durch null |
| … Torsion aus Kraeften: Schubmittelpunkt nicht bestimmbar (Grund) | Schubrechnung lehnt ab (mehrzellig) | Das Moment um den Schubmittelpunkt ist nicht bestimmbar; der Grund steht in Klammern |
| **Spannung nicht berechnet:** σx nicht berechenbar (Nenner 0) | Fläche oder $I_yI_z - I_{yz}^2$ gleich null | Division durch null |
| **Eingabe:** Ungültige Eingabe (Torsion, Schubkraft, σx, Menüwert) | Ausdruck nicht auswertbar | Rückmeldung statt stillem Abbruch |
| **Hinweis:** Offenes Profil, Profilbeiwert ξ = 1 – so gewollt? | Torsion eines offenen Profils (Schub aus Kräften mit Torsion, äußere Belastung mit $M_T$, Torsionsdialog, Verwölbung) bei ξ = 1 | Erinnerung an die Werte der Formelsammlung (L 0,99, C/T 1,12, I 1,31, IPB 1,29); wird an eine schon offene Box angehängt, nie doppelt |
| **Hinweis:** Alle dünnwandigen Elemente haben die Standarddicke | Taste `e` (bzw. Menü b → 1), alle dünnwandigen Elemente mit derselben Dicke = Standarddicke | Einmalig; erst wieder, wenn das ganze Profil gelöscht wurde (`c` oder alle Elemente einzeln entfernt) |
| **Hinweis:** Kein Querschnitt vorhanden | Berechnung, KOS-Verschiebung oder Kernfläche ohne Querschnitt | Rückmeldung |
| **Hinweis:** V nur im Schubspannungsmodus verfügbar | Taste `V` ohne Schubergebnis | Bedienhinweis |

Weitere Anzeigen außerhalb der Box:

| Anzeige | Wann | Warum |
|---|---|---|
| Überlappung erkannt (1 Abziehen, 2 Addieren, 3 Verwerfen) | Ein neues Massivelement überdeckt ein bestehendes wirklich (gemeinsame Kanten zählen nicht) | Entscheidung zwischen Lochabzug und numerischer Addition |
| Warnung: Numerisch berechnet! (Ergebnisfeld) | Ein Element wurde numerisch addiert | Die Werte sind eine Rasternäherung |
| Hauptachsen parallel zu den Achsen ($I_{yz} = 0$), grün | $I_{yz} \approx 0$ | Hinweis, dass die einfachen Formeln gelten |
| Hauptachsen nicht parallel zu den Achsen, orange | $I_{yz} \ne 0$ | Hinweis auf schiefe Biegung |
| Schubmittelpunkt: statisch unbestimmt | Mehrzelliges Profil | Es wird nur angegeben, was bestimmt ist |
| M o. D für Querschnitt | Leerer Bildschirm | Bedienhinweis zum Einstieg |

## Ergänzungen (Eingabe ^, HAS, Taste V, gedrehtes System)

- **Eingabe mit `^`:** `qsEingabeZeichen(c)` lässt in allen Zahlenfeldern `^` und die Sonderzeichen der Tasten x², EE, ×, ÷, √, π zu. Vorher filterte `on.charIn` `^` weg, `10^6` wurde stillschweigend zu `106`. `evaluate_input` setzt `1e6` → `1*10^(6)`, `10^-5` → `10^(-5)` und für den Lua-Ersatz die Sonderzeichen in ASCII um. Test: Fall 51.
- **HAS in fester Größe:** `drawAxes` zeichnet das Hauptachsensystem mit 35 % der KOS-Pfeillänge (wächst mit „KOS Groesse“), unabhängig vom Zoom. Test: Fall 52.
- **Taste V:** eine Meldung (`qsHinweis.vTaste()`) statt zwei: nennt je nach Zustand Esc (Verwölbungsansicht schließen), b, 5. Schubspannung, danach V. Test: Fall 53.
- **Schubmittelpunkt einer Zelle:** immer beide Koordinaten (q0 je Lastrichtung aus Symmetrie oder Verträglichkeit). Nicht bestimmbar nur bei Ablehnung der Schubrechnung (mehrzellig); `result.grund` steht in der Meldung „Torsion aus Kraeften“. Bögen lehnt der Schub nicht mehr ab (Sehnenkette im Profilgraph, Fall 59). Test: Fall 55.
- **Boegen im Schubgraph** (Fall 59): D-Profil, offener Halbkreis, U aus Halbkreis und Stegen, C mit Bogen-Ecken, Steg am Bogenscheitel, Rohr aus zwei Halbkreisen gegen den Sonderweg, Symmetrieerkennung, Kreuzung mit Gerade und mit Bogen, T-Stöße, Berührung, Fangpunkt P3, zwei Zellen, Pfeile und Hover.
- **Gedrehtes System** (b-Menü Punkt 8, Schließen jetzt 9): Abfrage φ in Grad (positiv von y nach z, gegen den Uhrzeigersinn), zeigt φ* der Hauptachse 1. Ergebnisblock im Ergebnisfeld unter `alpha`: `I_η`, `I_ζ`, `I_ηζ` mit Gross-Vorzeichen, Bezug wie FTM-Bezug (Schwerpunkt oder KOS-Ursprung); orange Achsen η, ζ in fester Größe. Esc in der Abfrage bricht ab, Esc danach beendet. Zahlen über `formatKlein` (ab 10^4 als Zehnerpotenz). Test: Fall 56 (Rechteck 90°, L-Profil 30° gegen Handrechnung, φ = φ*).
- **Meldungen über Eingabemasken:** `on.paint` zeichnet die Meldungsbox jetzt auch über offenen Masken (vorher war „Ungueltige Eingabe“ dort unsichtbar); Esc schließt erst die Box.
- **Verwölbung:** Das eingegebene M_T ersetzt das vorbelegte Moment aus den Kräften (keine Superposition); getippte Zeichen hängen sich an die Vorbelegung an.
- **σx-Einfärbung ohne Raster** (Fall 60): Bänder parallel zur Nulllinie, exakt am Umriss jedes Massivelements geschnitten (`qsFarbe`), statt 12 bis 60 Kacheln je Achse. Glatte Ränder, feiner Verlauf, weniger Zeichenbefehle.
- **Kräfte rot** (Fall 61): Kräfte immer rot, unter dem Zeiger bzw. mit offenem Menü violett und dicker (vorher blau, Hover violett, Auswahl rot).
- **Torsionsanteil offener Wände** (Fall 62): `torsionsTau` gibt für offene Wände immer +M_T t/I_T zurück, den Wert am rechten Rand in Laufrichtung (dort läuft τ für M_T > 0 in +s). Vorher hing das Vorzeichen an der Zeichenrichtung des Elements (`sample.direction`, Feld entfernt), dadurch wechselte es von Wand zu Wand. Zellen unverändert (Bredt, `cell_sign`). Kombinationen (Verlauf 9) nehmen bei offenen Wänden ohnehin Beträge.
- **Gesamtschubspannung mit Vorzeichen** (Fall 62): `gesamtTau(in_zelle, tau_q, tau_t)` für Verlauf 9 und `tau_total`. Zelle: Summe mit Vorzeichen (unverändert). Offene Wand: Betrag |τ_Q| + |τ_T| (Größtwert am ungünstigeren Rand) mit der Richtung von τ_Q, ohne Querkraft mit der von M_T; vorher nur der Betrag. Bei gleichem Vorzeichen von τ_Q und M_T liegt der Wert am rechten Rand in Laufrichtung, sonst am linken. `tau_gesamt,max` unverändert (Betrag).
