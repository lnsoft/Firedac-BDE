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
| `... order by c1[, c2]` crescente, se esiste un indice che inizia esattamente con quei campi (campi semplici; non espressione, non discendente, non insensibile alle maiuscole) | TTable su quell'indice |
| `... where c1 = :a [and c2 >= :b ...] order by c1, c2` – uguaglianze sui primi campi e al massimo un intervallo (`>`, `>=`, `<`, `<=`) sul successivo, solo campi numerici, valore come parametro o numero | TTable + `SetRange` |
| tutto il resto: `desc`, `WHERE` senza `ORDER BY`, campi testo/data nel `WHERE`, join, funzioni, nomi di campo tra virgolette, parametri NULL o non numerici | TQuery (invariato) |

## Misure

`DocD00.DBF`, 452.873 righe, Delphi 13.2, disco locale:

| Operazione                                                        | TQuery   | TTable  |
|-------------------------------------------------------------------|----------|---------|
| `select *` (prime 5.000 righe identiche)                          | 3.574 ms | 7 ms    |
| `TFDTable.Open`                                                   | ~3,5 s   | 14 ms   |
| `order by NUMERO` (indicizzato)                                   | 2.323 ms | 16 ms   |
| `where NUMERO >= x and NUMERO <= y order by NUMERO` (292.998 righe) | 2.389 ms | 4 ms    |
| `where NUMERO > x order by NUMERO` (292.996 righe)                | 2.402 ms | 5 ms    |
| `where NUMERO < x order by NUMERO` (159.875 righe)                | 1.304 ms | 5 ms    |

Tabella Paradox (`Scadenze.DB`, 13.898 righe, chiave primaria di testo): l'`order by` sulla chiave usa la TTable
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

Leggere tutte le 452.873 righe x 32 campi di `DocD00` richiede 3,3 s con FireDAC e `TableCursor`. Un ciclo grezzo su
una `TTable` del BDE impiega 0,25 s solo per scorrere il cursore e 2,5 s per leggere i 32 campi (lo stesso con
`Variant` o con accessi tipizzati): circa tre quarti del tempo è il BDE che legge i valori; FireDAC e il driver
aggiungono circa 0,8 s. Leggere solo i campi che servono (`select NUMERO, RIGA, QTA from ...`) riduce il costo in proporzione.

## Differenze rispetto al TQuery

* La TTable è un cursore **vivo**: righe modificate da altri utenti durante la lettura possono comparire; il TQuery lavora su una copia.
* Righe con la **stessa chiave** possono uscire in ordine diverso rispetto al TQuery (l'ordine di chiavi uguali non è definito in SQL).
  Se l'ordine conta, aggiungi i campi mancanti all'`ORDER BY` (`order by NUMERO, RIGA`); usa l'indice solo se ne esiste uno che li copre.
* Un campo che è parola riservata del Local SQL (per esempio `AUTOINC`) funziona con la TTable, mentre il TQuery lo rifiuta.
* Se un parametro del `WHERE` è NULL o non numerico quando la query viene aperta, il driver passa al TQuery per quel comando.

## Verifica

`BDETest` ha un caso che esegue ogni forma qui sopra su una connessione normale e su una con `TableCursor=True`,
confronta chiavi e numero di righe e controlla quale cursore è stato usato; `LocalSQLTest ... md` esegue il test master-detail.
