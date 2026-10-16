# Local SQL di FireDAC sopra il driver BDE (sperimentale)

([English version](LOCAL_SQL_ON_BDE.md))

Il Local SQL del BDE è limitato (vedi [LOCAL_SQL.it.md](LOCAL_SQL.it.md)). FireDAC ha un proprio
*Local SQL* (`TFDLocalSQL`): qualunque `TDataSet` viene esposto come **tabella virtuale** di SQLite,
quindi si può usare SQL SQLite completo (`CASE`, `COALESCE`, `LIMIT`, CTE, window function, viste,
join tra più sorgenti) sopra dataset aperti con questo driver.

```
TFDQuery (connessione SQLite :memory: con TFDLocalSQL)
   └─ tabelle virtuali  ←  OnGetDataSet  ←  TFDQuery su connessione BDE  →  TQuery  →  DBF / Paradox
```

Il driver non va modificato: un `TFDQuery` sul driver `BDE` è semplicemente un dataset.
L'esperimento è in `Demos\LocalSQLTest.dpr` (compilato da `build.bat`).

## Codice minimo

```pascal
uses FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteVDataSet, FireDAC.Stan.ExprFuncs;

procedure TDm.GetDS(ASender: TObject; const ASchemaName, AName: String;
  var ADataSet: TDataSet; var AOwned: Boolean);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := BdeConn;                       // DriverID=BDE
    Q.SQL.Text := 'select * from "' + FileFor(AName) + '"';   // es. "CLIENTI.DBF"
    Q.Open;
  except
    Q.Free;
    raise;
  end;
  ADataSet := Q;
  AOwned := True;                                  // lo libera FireDAC
end;

// impostazione
LiteConn.DriverName := 'SQLite';
LiteConn.Params.Database := ':memory:';
LiteConn.Connected := True;
LocalSQL.Connection := LiteConn;
LocalSQL.OnGetDataSet := DM.GetDS;
LocalSQL.Active := True;

// poi, su LiteConn:
//   select c.nome, coalesce(sum(o.importo), 0) from a c left join b o on ... group by ... limit 10
```

## Regole emerse dai test

1. **Registra ogni tabella virtuale con `TFDQuery.Open`**, ad esempio `select count(*) from a`.
   Se la prima richiesta passa da `ExecSQLScalar`, FireDAC dà l'errore -308 e lascia uno statement
   non finalizzato: poi `LiteConn.Close` fallisce ("unable to close due to unfinalized statements").
   Registrare tutto in anticipo con `TFDQuery.Open` evita entrambi i problemi.
2. **`OnGetDataSet` viene chiamato una volta per nome di tabella e per connessione SQLite.**
   Il dataset resta aperto ed è condiviso da tutti i riferimenti a quel nome (l'auto-join
   `a x join a y` funziona).
3. **Il dataset è un'istantanea.** Le modifiche fatte da altri (o direttamente sulla connessione BDE)
   non si vedono finché non si ricreano le sorgenti (commuta `LocalSQL.Active`, o chiudi la
   connessione). Le modifiche fatte *attraverso* la tabella virtuale si vedono.
4. **La scrittura funziona:** un `UPDATE` su una tabella virtuale arriva al file DBF/Paradox.
   Usa una chiave unica nel `WHERE`.
5. **L'annidamento funziona:** sottoquery, CTE, viste temporanee, e una query Local SQL registrata
   come sorgente di un'altra tabella virtuale. Preferisci sottoquery e viste: vengono pianificate come
   un unico statement.
6. **Libera tu le sorgenti "dataset su dataset"** (`AOwned := False`) e prima di chiudere la connessione.
7. **Le colonne memo perdono per default i fine riga finali.** Leggendo un memo dalla tabella virtuale con
   un `TFDQuery` si sono ottenuti 172 caratteri invece di 174: `FormatOptions.StrsTrim` (default `True`)
   toglie i CR LF finali. SQLite contiene il testo completo. Confermato su un memo dBase IV reale (62 contro 61 caratteri). Per le query che leggono memo imposta
   `Query.FormatOptions.StrsTrim := False` **prima** di `Open` (cambiarlo su una query già preparata non
   ha effetto). Impostarlo sulla connessione non è stato provato.
8. **Date e booleani sono mappati correttamente:** una colonna data dBase è vista come `Date` e una
   colonna logica come `Boolean`, e `WHERE campo_data = :parametro` con parametro `ftDate` trova le righe.

## Misure (Delphi 13.2, Win32, una esecuzione, tabelle reali su disco locale)

| Prova | Risultato |
|---|---|
| `count(*)` di una tabella Paradox da 13.898 righe | 12 ms (conteggi BDE e Local SQL uguali) |
| Join Paradox 13.898 righe x dBase 3.590 righe su un campo | 3.385 righe: **Local SQL FireDAC 187 ms**, Local SQL nativo BDE 249 ms (stesso risultato) |
| Auto-join della tabella da 13.898 righe sulla chiave unica | 124 ms |
| Auto-join di una tabella dBase IV da 3.590 righe | 3.590 righe: Local SQL FireDAC 63 ms, BDE nativo 57 ms (stesso risultato) |
| Auto-join su un campo non unico | 16,7 milioni di coppie in 2,1 s |
| `WHERE` selettivo sulla tabella principale + join | circa 10 ms |

Una query costa circa **un passaggio sulla sorgente più grande**, qualunque cosa selezioni il `WHERE` (vedi
le misure su tabelle grandi più sotto): la tabella virtuale non riceve né filtri né ricerche su indice. Il Local SQL è quindi
adatto a report e analisi su intere tabelle, non a leggere le poche righe di un singolo documento.

## Scelta della sorgente: `TFDQuery` sul driver o `TTable` del BDE

`OnGetDataSet` può restituire un `TFDQuery` sulla connessione `BDE` (come sopra) oppure un semplice
`TTable` del BDE (`DatabaseName` = cartella o alias, `TableName` = `"TAB.DBF"`). `LocalSQLTest ... ttable`
li confronta.

| Stessi dati, stessa macchina | `TFDQuery` sul driver | `TTable` del BDE |
|---|---|---|
| Apertura tabella Paradox da 13.898 righe | 21 ms | 15 ms |
| Apertura tabella dBase da 3.590 righe e 119 campi | 234 ms | 2 ms |
| `count(*)` della tabella da 13.898 righe | 13 ms | 191 ms |
| Join delle due tabelle (3.385 righe) | 189 ms | 541 ms |
| `WHERE` selettivo + join | 10 ms | 365 ms |
| 20 giri di join + vista | 409 ms | 14.400 ms |

Una `TQuery` paga all'apertura un costo che cresce con la quantità di dati (il BDE costruisce il
risultato), poi le query girano sul dataset tenuto in memoria. Un `TTable` si apre subito, ma la
tabella virtuale non riceve alcun filtro, quindi ogni query scorre tutta la tabella con la navigazione
del BDE (circa 26 µs per riga qui, anche se il `WHERE` non trova nulla). La spiegazione deriva dai tempi,
non dal codice di FireDAC.

Regola pratica: `TTable` per query singole su tabelle grandi o larghe; `TFDQuery` quando le stesse
tabelle sono interrogate più volte; per tabelle molto grandi riduci prima i dati dentro il BDE (una
query sorgente con `WHERE` su indice, non ancora provato) e usa il Local SQL per combinare gli insiemi ridotti.

### Tabelle master-detail grandi (22.323 testate, 452.873 righe, dBase IV)

| | `TFDQuery` sul driver | `TTable` del BDE |
|---|---|---|
| Apertura testate / righe | 908 ms / 3.430 ms | 17 ms / 1 ms |
| Join di tutte le righe (449.991) | 764 ms (BDE nativo: 1.968 ms) | 6.952 ms |
| Join per un solo documento (3 righe) | 456 ms (BDE nativo: 992 ms) | 6.685 ms |
| 20 giri di join + vista | 18 s | 268 s |
| Modifiche di altri utenti visibili | no (istantanea) | sì (dati vivi) |

Aprire la tabella delle righe con una `TQuery` costa 3,4 s; un `TTable` si apre subito. Come sorgente del
Local SQL, però, il `TTable` costa circa 6,7 s per query su questa tabella (un passaggio su 452.873 righe
con la navigazione del BDE). Lo stesso join per un solo documento richiede 992 ms nel Local SQL del BDE, quindi nemmeno il BDE usa
una ricerca su indice. Un semplice `select * from DocD00 where NUMERO = :k` attraverso il driver restituisce le 3 righe di un documento in 8 ms
(BDE nativo: 4 ms): per un WHERE semplice il BDE usa l'indice; solo l'apertura dell'intera tabella e i join costano un passaggio completo.
Per l'accesso a un singolo documento usa un percorso indicizzato (`TFDTable` con
`MasterSource`/`MasterFields`, oppure un `WHERE` su campo indicizzato dentro il BDE) e tieni il Local SQL per i
report su intere tabelle.

## Non ancora provato

Colonne memo/BLOB/data di Paradox attraverso le tabelle virtuali (memo, data e booleano sono stati
verificati solo su un esempio dBase III, con testo ASCII), testo accentato nei memo (il memo reale provato conteneva XML in UTF-8, non testo accentato), utenti concorrenti,
tabelle molto grandi, altre versioni di Delphi. Considera la funzione **sperimentale**.
