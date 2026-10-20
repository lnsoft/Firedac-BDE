# TableCursor – leggere tabelle grandi senza attese

Un `TQuery` del BDE copia tutto il risultato quando viene aperto, quindi un `select *` su una tabella con
centinaia di migliaia di righe impiega secondi prima di mostrare la prima riga. Una `TTable` del BDE è un cursore
vivo e si apre subito. Il parametro di connessione `TableCursor=True` fa usare al driver una `TTable` in sola
lettura per le query semplici che sa servire in modo esatto, e il solito `TQuery` per tutto il resto.
Il default è `False` (non cambia nulla).

```pascal
FDConnection1.Params.Values['TableCursor'] := 'True';
```

## Cosa viene servito da una TTable

| SQL (come arriva al driver)                                              | Cursore |
|--------------------------------------------------------------------------|---------|
| `select * from "TAB.DBF"` (anche `SELECT A.* FROM "TAB.DBF" A`, cioè ciò che manda `TFDTable.Open`) | TTable |
| `select c1, c2 from "TAB.DBF"` (campi semplici, senza virgolette)        | TTable |
| `... order by c1[, c2]` crescente, se esiste un indice che serve quell'ordine: i suoi primi campi sono quei campi, dopo gli eventuali campi in testa che il `WHERE` fissa con `=` (campi semplici; non espressione, non discendente, non insensibile alle maiuscole) | TTable su quell'indice |
| `... where c1 = :a [and c2 >= :b ...] order by ...` – uguaglianze sui primi campi di un indice (in qualunque ordine), al massimo un intervallo (`>`, `>=`, `<`, `<=`) sul campo successivo, poi i campi dell'`ORDER BY`; solo campi numerici, valore come parametro o numero | TTable + `SetRange` |
| tutto il resto: `desc`, `WHERE` senza `ORDER BY`, campi testo/data nel `WHERE`, join, funzioni, nomi di campo tra virgolette, parametri NULL o non numerici | TQuery (invariato) |

## Misure

Una tabella dBase (`DETAIL.DBF`, 452.873 righe, 32 campi), Delphi 13.2, disco locale:

| Operazione                                                        | TQuery   | TTable  |
|-------------------------------------------------------------------|----------|---------|
| `select *` (prime 5.000 righe identiche)                          | 3.574 ms | 7 ms    |
| `TFDTable.Open`                                                   | ~3,5 s   | 14 ms   |
| `order by NUMERO` (indicizzato)                                   | 2.323 ms | 16 ms   |
| `where NUMERO >= x and NUMERO <= y order by NUMERO` (292.998 righe) | 2.389 ms | 4 ms    |
| `where NUMERO > x order by NUMERO` (292.996 righe)                | 2.402 ms | 5 ms    |
| `where NUMERO < x order by NUMERO` (159.875 righe)                | 1.304 ms | 5 ms    |

Tabella Paradox (13.898 righe, chiave primaria di testo): l'`order by` sulla chiave usa la TTable
e restituisce tutti i campi identici al risultato del TQuery.

### Master-detail (300 testate, 2.625 righe di dettaglio, tabella di dettaglio da 452.873 righe)

| Componente di dettaglio                                        | Normale   | TableCursor |
|----------------------------------------------------------------|-----------|-------------|
| `TFDTable` con `MasterSource` / `MasterFields`                 | 12.948 ms | 5.037 ms    |
| `TFDQuery` con `where NUMERO = :NUMERO order by NUMERO` + `MasterSource` | 4.137 ms | **902 ms** |

Con un `TFDTable` come dettaglio FireDAC legge tutta la tabella di dettaglio e la filtra in memoria (il driver
vede solo `SELECT A.* FROM ... A`), quindi resta lento. Per il master-detail su tabelle grandi usa un
**dettaglio `TFDQuery` con parametro** e `TableCursor=True`: ogni testata costa circa 3 ms.

## Dove va il tempo quando si leggono tutte le righe

Leggere tutte le 452.873 righe x 32 campi della tabella di dettaglio richiede 3,3 s con FireDAC e `TableCursor`. Un ciclo grezzo su
una `TTable` del BDE impiega 0,25 s solo per scorrere il cursore e 2,5 s per leggere i 32 campi (lo stesso con
`Variant` o con accessi tipizzati): circa tre quarti del tempo è il BDE che legge i valori; FireDAC e il driver
aggiungono circa 0,8 s. Leggere solo i campi che servono (`select NUMERO, RIGA, QTA from ...`) riduce il costo in proporzione.

## Scegliere indice e intervallo dal programma: `OnBDEIndexNeeded`, `OnBDESetRange`

Con `TableCursor=True` il driver può chiederti due cose, con eventi opzionali a runtime sulla connessione.
**Se non ne assegni nessuno non cambia nulla**: decide il driver da solo con le regole sopra. Valgono solo per
`SELECT` su una sola tabella; join, funzioni e tutto ciò che il parser non riconosce vanno sempre al `TQuery`.

```pascal
procedure TForm1.FDConnection1AfterConnect(Sender: TObject);
begin
  FDConnection1.OnBDEIndexNeeded := IndexNeeded;   // dopo l'apertura della connessione
  FDConnection1.OnBDESetRange := SetRangeNeeded;
end;

procedure TForm1.IndexNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
  ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
begin
  // AIndexName è la proposta del driver ('' = nessuna); AAccept parte True solo se c'è una proposta
  if SameText(ATableName, 'ORDINI.DBF') and SameText(AFieldNames, 'CLIENTE;DATA') then begin
    AIndexName := 'CLIDATA';
    AAccept := True;
  end;
end;

procedure TForm1.SetRangeNeeded(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
begin
  // ADataSet è la TTable, già aperta su AIndexName
  if SameText(AConditions[0].Field, 'CLIENTE') and (AConditions[0].Op = '=') then begin
    TTable(ADataSet).SetRangeStart;
    TTable(ADataSet).FieldByName('CLIENTE').AsString := AConditions[0].Value;
    TTable(ADataSet).SetRangeEnd;
    TTable(ADataSet).FieldByName('CLIENTE').AsString := AConditions[0].Value;
    TTable(ADataSet).ApplyRange;
    AHandled := True;
  end;
end;
```

### `OnBDEIndexNeeded`

Chiamato in preparazione di una `SELECT` che richiede un indice:

| Argomento      | Significato |
|----------------|-------------|
| `ATableName`   | tabella del `FROM`, senza virgolette |
| `AFieldNames`  | i campi dell'`ORDER BY`, separati da `;`; se manca l'`ORDER BY`, i campi del `WHERE` (condizioni semplici unite da `AND`) |
| `ASQL`         | il testo della SELECT |
| `ADescending`  | `True` se l'`ORDER BY` è `DESC` (tutti i campi discendenti; direzioni miste non sono mai servite da una `TTable`) |
| `AIndexName`   | in ingresso: l'indice proposto dal driver, `''` se non ne ha; in uscita: l'indice da usare. `S_BDE_PrimaryIndex` (`'(primary)'`) è la chiave primaria Paradox |
| `AAccept`      | in ingresso: `True` se il driver ha una proposta, `False` se no; `True` per prendere in carico la query, `False` per farla eseguire al `TQuery` |

Il driver **non ha proposta** (`AIndexName` vuoto, `AAccept = False`) quando non sa servire la query da solo:
`ORDER BY ... DESC` senza indice discendente, `WHERE` con campi testo o data, e simili. Se non fai nulla la query
va al `TQuery` come sempre. Per prenderla in carico imposta l'indice **e** `AAccept := True`.

- **`WHERE` senza `ORDER BY`**: con l'indice che indichi, le condizioni sono servite con un `SetRange`. Le righe
  tornano nell'ordine dell'indice.
- **Un indice diverso da quello proposto**, anche espressione o insensibile alle maiuscole. Per un indice a campi
  semplici il driver controlla che l'indice serva l'`ORDER BY` (o abbia in testa i campi del `WHERE`, in qualunque
  ordine) e che il verso coincida; per un indice espressione (`ixExpression`) il controllo è tuo.

### `OnBDESetRange`

Chiamato all'apertura di una `SELECT` con `WHERE` servita da una `TTable`, dopo che la tabella è aperta
sull'indice in uso e prima del `SetRange` del driver. `AConditions` ha una voce per condizione (`Field`, `Op` =
`=`, `>`, `>=`, `<`, `<=`, e `Value`: il valore del parametro, `Null` se NULL, oppure il numero o il testo scritto
nella SQL).

- Imposta `AHandled := True` dopo aver chiamato tu `SetRangeStart` / `SetRangeEnd` / `ApplyRange`. Il driver non
  fa altro: **sei tu a garantire che l'intervallo equivalga al `WHERE`**. Così si servono anche condizioni su
  testo e date (attenzione: un `SetRange` su un campo testo ha semantica di prefisso, e le date vanno convertite).
- Lascia `AHandled := False` e vale il comportamento standard: il `SetRange` numerico del driver se le condizioni
  sono numeriche e adatte all'indice, altrimenti il `TQuery`.

Con `OnBDESetRange` assegnato il driver non scarta più in preparazione un `WHERE` su campi testo o data, né le
condizioni che il suo `SetRange` non sa esprimere; se non le gestisci, la query va al `TQuery` all'apertura.
Viene accettato anche un indice discendente o espressione con un `WHERE` (l'intervallo è tuo).

**Indici espressione dBase** (per esempio `ANNO+TIPODOC+NUMDOC`; `TIndexDef.Fields` è vuoto e il testo è in
`Expression`), misurati su una tabella da 22.323 righe:

- La `TTable` si apre su di essi e legge nell'ordine dell'indice.
- Una chiave fatta da **tutti** i campi, assegnati uno a uno (`SetRangeStart; FieldByName('ANNO').AsString := ...;
  ... ApplyRange`), trova la riga (1 riga, come il `TQuery`).
- Una chiave **parziale** (solo `ANNO`, oppure `ANNO` e `TIPODOC`) **non trova nessuna riga e non dà errore**: il BDE
  costruisce la chiave dall'intera espressione con i campi mancanti vuoti. Per questo il driver non usa mai il
  proprio `SetRange` su un indice espressione: senza `OnBDESetRange` (o con `AHandled := False`) la query va al
  `TQuery`.
- Una chiave parziale **funziona se la completi tu**: all'inizio dell'intervallo i campi mancanti vuoti, alla fine
  riempiti con `#255` per tutta la loro larghezza (misurato con `DocT00`: 1317 e 449 righe, uguali al `TQuery`).
  Vedi il gestore qui sotto.
- `SetRange([...])`, `FindKey` e `FindNearest` con gli array sono rifiutati da Delphi
  ("Cannot use array of Field values with Expression Indices").
- I campi di testo si confrontano come sono memorizzati: `NUMDOC` è allineato a destra con spazi iniziali, quindi il
  valore deve essere `'                   245/12'`; il `TQuery` si comporta uguale (`NUMDOC = '245/12'` non trova niente).

**Proposta ed evento.** Con `OnBDESetRange` assegnato, un `WHERE` senza `ORDER BY` sui primi campi di un indice
espressione fatto solo di campi di **testo** uniti da `+` (`ANNO+TIPODOC+NUMDOC`) viene servito dalla `TTable`: il
driver propone quell'indice (`Accept = True` in `OnBDEIndexNeeded`, che puoi cambiare o rifiutare) e chiama
`OnBDESetRange` con tutte le condizioni, qualunque siano (testo, chiave parziale, intervalli): la chiave la
costruisci tu. Senza `OnBDESetRange` non cambia nulla (`TQuery`). La proposta non c'è per le espressioni con
funzioni (`STR(N,5)+X`, `UPPER(A)`), per campi numerici (`+` sarebbe una somma) né insieme a un `ORDER BY` (l'ordine
di una chiave concatenata coincide con quello dei campi solo per i campi di testo: scegli tu l'indice in
`OnBDEIndexNeeded`). `BDEExpressionFields(ADef)` e la forma con `AExpressions` di `BDEFindIndex` espongono la stessa
logica.

Un gestore che accetta uguaglianze sui primi campi dell'indice, chiavi parziali comprese (il driver passa il nome
dell'indice e le condizioni; `BDEExpressionFields` restituisce i campi dell'espressione):

```pascal
procedure TForm1.BDESetRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
var
  T: TTable;
  aF: TArray<String>;
  sV: String;
  i: Integer;

  function CondValue(const AField: String; out AValue: String): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := 0 to High(AConditions) do
      if SameText(AConditions[j].Field, AField) then begin
        AValue := VarToStr(AConditions[j].Value);
        Exit(True);
      end;
  end;

  // la chiave: i campi con '=' al loro valore; gli altri vuoti (inizio) o #255 (fine)
  procedure Fill(AHigh: Boolean);
  var
    j: Integer;
    F: TField;
  begin
    for j := 0 to High(aF) do begin
      F := T.FieldByName(aF[j]);
      if CondValue(aF[j], sV) then
        F.AsString := sV
      else if AHigh then
        F.AsString := StringOfChar(#255, F.Size);
    end;
    T.KeyFieldCount := Length(aF);
  end;

begin
  T := TTable(ADataSet);
  for i := 0 to T.IndexDefs.Count - 1 do
    if SameText(T.IndexDefs[i].Name, AIndexName) then
      aF := BDEExpressionFields(T.IndexDefs[i]);   // ANNO, TIPODOC, NUMDOC
  if (Length(aF) = 0) or (Length(AConditions) > Length(aF)) then
    Exit;                                   // non e' il nostro caso: comportamento standard (TQuery)
  for i := 0 to High(AConditions) do
    if (AConditions[i].Op <> '=') or not SameText(AConditions[i].Field, aF[i]) then
      Exit;                                 // solo uguaglianze sui primi campi, in ordine
  T.SetRangeStart;
  Fill(False);
  T.SetRangeEnd;
  Fill(True);
  T.ApplyRange;
  AHandled := True;
end;
```

Misurato con un gestore così su una tabella da 22.323 righe (`WHERE` sui primi 1, 2 e 3 campi di
`ANNO+TIPODOC+NUMDOC`): 1317, 449 e 1 riga, sempre uguali al `TQuery`, in 43, 17 e 6 ms contro 177, 120 e 92 ms.
Vale per campi di testo a larghezza fissa; `#255` come limite alto è stato verificato solo con il language driver di
quella tabella.

### Cercare un indice nel proprio codice: `BDEFindIndex`

La funzione che il driver usa per la sua proposta è pubblica (`FireDAC.Phys.BDEDef`), quindi la può chiamare anche un
gestore. Lavora su un `TIndexDefs` (per esempio `TTable.IndexDefs` dopo `Update`) e considera solo gli indici a campi
semplici del verso richiesto (non espressione, non insensibili alle maiuscole).

```pascal
function BDEFindIndex(AIndexDefs: TIndexDefs; const AEquals, ARanges, AOrderBy: array of String;
  ADescending: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;
function BDEFindIndex(AIndexDefs: TIndexDefs; const AFields: array of String;
  ADescending, AAnyOrder: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;
function BDEIndexServesOrder(ADef: TIndexDef; const AEquals, AOrderBy: array of String): Boolean;
```

- **Forma completa** (`AEquals`, `ARanges`, `AOrderBy`): i campi con `=` possono stare in qualunque ordine, quindi
  `where A = 1 and B = 2` trova sia un indice su `(B, A)` sia uno su `(A, B)`. È come provare tutte le permutazioni
  dei campi del `WHERE`, senza generarle: per ogni indice si controllano una volta i suoi primi campi. Un campo con
  intervallo (`>`, `<`...) deve venire subito dopo le uguaglianze, e dopo ancora i campi dell'`ORDER BY`. L'ordine
  dell'`ORDER BY` conta, ma un campo fissato da `=` si può saltare: `where C = 1 order by A, B` usa un indice su
  `(C, A, B)`.
- **`AMatch.Level`**: `ilFull` = l'indice serve tutto, quindi si può usare il `SetRange` del driver; `ilCovers` =
  rispetta l'`ORDER BY` (o ha in testa i campi del `WHERE`) ma le condizioni richiedono il tuo `OnBDESetRange`;
  `ilNone` = niente. Vince il primo indice `ilFull`, altrimenti il primo `ilCovers`.
- **Forma a elenco** (`AFields`): `AAnyOrder = True` trova un indice che ha come primi campi quelli dell'elenco in
  qualunque ordine, `False` nello stesso ordine. Comoda con `AFieldNames.Split([';'])` dentro `OnBDEIndexNeeded`.

```pascal
// campi testo nel WHERE: il driver non ha proposta, cerco un indice su di essi (qualunque ordine)
if BDEFindIndex(FOrders.IndexDefs, AFieldNames.Split([';']), ADescending, True, oMatch) then begin
  AIndexName := oMatch.IndexName;
  AAccept := True;                 // le condizioni sul testo richiedono anche OnBDESetRange
end;
```

Nota: nelle tabelle dBase un indice su più campi è normalmente un indice espressione (`ixExpression`), che il driver
e `BDEFindIndex` lasciano a te; gli indici semplici su più campi sono tipici di Paradox. Guarda `IndexDefs` della
tua tabella per capire quale caso hai.

### Note

- Un'eccezione sollevata dai tuoi gestori **non** viene assorbita: arriva a chi ha aperto la query.
- Se `AAccept` è `False`, `AIndexName` è vuoto o sconosciuto, o l'indice non è adatto, la query va al `TQuery`
  come senza evento.
- La connessione fisica nasce a ogni `Connected := True`, quindi gli eventi vanno assegnati dopo la connessione
  (ad esempio in `AfterConnect`). Sono un class helper dichiarato in `FireDAC.Phys.BDEDef`.

## Differenze rispetto al TQuery

* La TTable è un cursore **vivo**: righe modificate da altri utenti durante la lettura possono comparire; il TQuery lavora su una copia.
* Righe con la **stessa chiave** possono uscire in ordine diverso rispetto al TQuery (l'ordine di chiavi uguali non è definito in SQL).
  Se l'ordine conta, aggiungi i campi mancanti all'`ORDER BY` (`order by NUMERO, RIGA`); usa l'indice solo se ne esiste uno che li copre.
* Un campo che è parola riservata del Local SQL (per esempio `AUTOINC`) funziona con la TTable, mentre il TQuery lo rifiuta.
* Se un parametro del `WHERE` è NULL o non numerico quando la query viene aperta, il driver passa al TQuery per quel comando.

## Limitare le righe: `RecsMax` e paginazione

Il Local SQL non ha `TOP`/`LIMIT`, quindi FireDAC applica `FetchOptions.RecsMax` e `RecsSkip` lato client.
Il costo dipende dal cursore (tabella dBase da 452.873 righe, `RecsMax = 50`):

| Query                              | Tempo per avere 50 righe |
|------------------------------------|--------------------------|
| `select *` con il `TQuery`         | 3.557 ms (il BDE copia prima tutto il risultato) |
| `select *` con `TableCursor=True`  | 7 ms |
| `... order by <campo indicizzato>` con `TableCursor=True` | 4 ms |

Quindi per elenchi e griglie su tabelle grandi, `TableCursor=True` con `RecsMax` (o il fetch `fmOnDemand`) mostra
subito le prime righe.

`RecsSkip` (paginazione) lo applica il driver con il solo cursore: scorre le righe da saltare senza leggerne i
campi e dice a FireDAC che non resta niente da saltare. Stessa tabella, 50 righe dopo lo skip:

| Righe saltate | ordine naturale | `order by` campo indicizzato | prima (skip fatto da FireDAC) |
|---------------|-----------------|------------------------------|-------------------------------|
| 4.528         | 4 ms            | 15 ms                        | 32 ms / 45 ms                 |
| 113.218       | 70 ms           | 369 ms                       | 824 ms / 1.189 ms             |
| 407.585       | 243 ms          | 1.325 ms                     | 3.031 ms / 4.339 ms           |

Il costo cresce ancora con le righe saltate, perché il BDE le scorre una per una (`MoveBy` è solo il 5-10% più
veloce di `Next`; su un indice i passi sono più lenti). Per la paginazione in profondità conviene **paginare per
chiave**: si chiedono le righe dopo l'ultima mostrata, con un campo chiave univoco, e non serve nessuno skip:

```sql
select * from DETAIL where CAMPOCHIAVE > :ultima order by CAMPOCHIAVE
```

con `RecsMax = 50` impiega 4 ms in qualunque posizione, perché la `TTable` va direttamente alla chiave con `SetRange`.

## Vedere le modifiche degli altri utenti

Un `TFDQuery` tiene in memoria le righe lette, quindi una modifica fatta da un altro processo o da un'altra
connessione non compare in un risultato già aperto: serve un aggiornamento. Misurato con uno scrittore in un
**processo separato** che modifica una riga e resta connesso (tabella dBase su disco locale), con e senza un
`DbiSaveChanges` da parte sua:

| Lettore                                   | Vede la modifica? |
|-------------------------------------------|-------------------|
| la stessa query aperta, senza fare nulla  | no (righe già lette) |
| la stessa query dopo `Refresh`            | sì |
| una query nuova sulla stessa connessione  | sì |
| una connessione nuova                     | sì |
| un normale `TQuery` (senza `TableCursor`) | sì |

Quindi il BDE non trattiene la modifica (non serve nessun flush lato scrittore): basta riaprire. Con
`TableCursor=True` la riapertura costa millisecondi (`TFDTable.Open` 12 ms; `select *` 7 ms invece di 3,4 s),
quindi il `Refresh` è praticamente gratuito; con il `TQuery` costa quanto la prima apertura. Per aggiornare una
sola riga usa `RefreshRecord` con `UpdateOptions.KeyFields` (servito dall'indice, circa 10 ms). Il BDE non ha
notifiche di modifica: se ti serve sapere quando aggiornare, controlla a intervalli la data di modifica del file
della tabella.

Le misure sono su disco locale; su una condivisione di rete la cache del client può ritardare la modifica.

## Verifica

`BDETest` ha un caso che esegue ogni forma qui sopra su una connessione normale e su una con `TableCursor=True`,
confronta chiavi e numero di righe e controlla quale cursore è stato usato; `LocalSQLTest ... md` esegue il test master-detail.
