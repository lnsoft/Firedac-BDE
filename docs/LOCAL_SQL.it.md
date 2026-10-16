# Local SQL: promemoria rapido (cosa accetta il BDE tramite questo driver)

([English version](LOCAL_SQL.md))

Il driver passa l'SQL al BDE, quindi il dialetto è il **Local SQL** del BDE.
Queste note riassumono i punti importanti per scrivere codice FireDAC su dati BDE.
Si basano sulla guida Local SQL curata da Niels Knabe
(<https://nknabe.dk/localsql/>) e sui test fatti con questo driver; per i dettagli consulta l'originale.

## Funzioni

| Esigenza | Local SQL | Escape FireDAC mappato dal driver |
|---|---|---|
| Maiuscolo / minuscolo | `UPPER(x)`, `LOWER(x)` | `{fn UCASE(x)}`, `{fn LCASE(x)}` |
| Sottostringa | `SUBSTRING(x FROM inizio [FOR lung])` (base 1) | `{fn SUBSTRING(x, inizio[, lung])}` |
| Trim | `TRIM([LEADING\|TRAILING\|BOTH] 'c' FROM x)` | `{fn LTRIM(x)}`, `{fn RTRIM(x)}` |
| Concatenazione | `a \|\| b` (il BDE accetta anche `a + b`) | `{fn CONCAT(a, b)}` |
| Conversione di tipo | `CAST(x AS tipo)` | `{fn CONVERT(x, tipo)}` (`INT`→`INTEGER`, `DATETIME`→`TIMESTAMP`, `CHAR`→`CHAR(254)`) |
| Parti di data | `EXTRACT(YEAR\|MONTH\|DAY\|HOUR\|MINUTE\|SECOND FROM x)` | `{fn YEAR(x)}`, `{fn MONTH(x)}`, `{fn DAYOFMONTH(x)}`, `{fn HOUR(x)}`, `{fn MINUTE(x)}`, `{fn SECOND(x)}` |
| Aggregati | `AVG`, `COUNT`, `MAX`, `MIN`, `SUM` | – |

Qualsiasi altra funzione escape genera un errore esplicito "unsupported escape".

`UPPER`, `LOWER`, `TRIM`, `SUBSTRING`, `CAST` e `||` **non** funzionano su colonne memo/BLOB.

## Non supportato (elementi SQL-92 assenti in Local SQL)

`CASE`, `COALESCE`, `NULLIF`, `LENGTH` (per testare una lunghezza usa `SUBSTRING(f FROM n) <> ''`),
`CURRENT_DATE/TIME/TIMESTAMP`, `CONVERT` (usa `CAST`), `CROSS JOIN`, join `NATURAL`/`USING`,
`EXCEPT`, `INTERSECT`, `CREATE VIEW`, `LIMIT`/`TOP`, vincoli `CHECK`/`FOREIGN KEY`.
`DISTINCT` non funziona con colonne memo/BLOB.

## Trappole

- **Apici.** I nomi con spazi o uguali a una parola riservata vanno tra apici
  **e** prefissati con il nome o alias della tabella (`SELECT t."Date" FROM t`).
  I nomi di tabella con estensione si scrivono tra doppi apici: `"CLIENTI.DBF"`.
- **`LIKE` distingue maiuscole/minuscole.** Per ricerche insensibili usa `UPPER(f) LIKE UPPER(:p)`.
- **Date.** I letterali dipendono dalle impostazioni di Windows (ordine US o europeo, tra apici).
  Usa i **parametri** per le date, non letterali o escape `{d '...'}`.
- **Booleani.** `TRUE`/`FALSE` (insensibili al maiuscolo) oppure `"T"`/`"F"` tra apici.
- **Stringhe.** `CHAR`/`VARCHAR` arrivano a 254 byte; la conversione maiuscolo/minuscolo dipende
  dal language driver della tabella.
- **Parole riservate** (elenco lungo, vedi `FKeywords` in `FireDAC.Phys.BDEMeta.pas`): non usabili
  come nomi di colonna senza apici. Il driver le comunica a FireDAC, che quota l'SQL generato.
- **Parametri memo.** Usa per i parametri memo un tipo memo (`ftMemo`/`ftWideMemo`), non stringa.
