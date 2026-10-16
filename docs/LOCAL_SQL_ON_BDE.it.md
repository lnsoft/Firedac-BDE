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

I tempi dell'auto-join sono troppo bassi per una scansione completa della tabella interna a ogni
riga esterna, quindi la ricerca nel join sembra efficiente; è un'inferenza dai tempi, non una
garanzia documentata. Un `WHERE` sulla tabella principale costa circa una scansione completa di essa.

## Non ancora provato

Colonne memo/BLOB/data di Paradox attraverso le tabelle virtuali (memo, data e booleano sono stati
verificati solo su un esempio dBase III, con testo ASCII), testo accentato nei memo (il memo reale provato conteneva XML in UTF-8, non testo accentato), utenti concorrenti,
tabelle molto grandi, altre versioni di Delphi. Considera la funzione **sperimentale**.
