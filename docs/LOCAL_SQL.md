# Local SQL cheat sheet (what the BDE accepts through this driver)

The driver sends your SQL to the BDE, so the dialect is the BDE's **Local SQL**.
These notes summarise the points that matter when writing FireDAC code against it.
They are based on the Local SQL reference maintained by Niels Knabe
(<https://nknabe.dk/localsql/>) and on tests with this driver; consult the original for details.

## Functions

| Need | Local SQL | FireDAC escape mapped by the driver |
|---|---|---|
| Upper / lower case | `UPPER(x)`, `LOWER(x)` | `{fn UCASE(x)}`, `{fn LCASE(x)}` |
| Substring | `SUBSTRING(x FROM start [FOR len])` (1-based) | `{fn SUBSTRING(x, start[, len])}` |
| Trim | `TRIM([LEADING\|TRAILING\|BOTH] 'c' FROM x)` | `{fn LTRIM(x)}`, `{fn RTRIM(x)}` |
| Concatenate | `a \|\| b` (the BDE also accepts `a + b`) | `{fn CONCAT(a, b)}` |
| Convert type | `CAST(x AS type)` | `{fn CONVERT(x, type)}` (`INT`→`INTEGER`, `DATETIME`→`TIMESTAMP`, `CHAR`→`CHAR(254)`) |
| Date parts | `EXTRACT(YEAR\|MONTH\|DAY\|HOUR\|MINUTE\|SECOND FROM x)` | `{fn YEAR(x)}`, `{fn MONTH(x)}`, `{fn DAYOFMONTH(x)}`, `{fn HOUR(x)}`, `{fn MINUTE(x)}`, `{fn SECOND(x)}` |
| Aggregates | `AVG`, `COUNT`, `MAX`, `MIN`, `SUM` | – |

Any other escape function raises an explicit "unsupported escape" error.

`UPPER`, `LOWER`, `TRIM`, `SUBSTRING`, `CAST` and `||` do **not** work on memo/BLOB columns.
Apply them to non-character types only after `CAST(... AS CHAR(n))`.

## Not supported (SQL-92 elements missing in Local SQL)

`CASE`, `COALESCE`, `NULLIF`, `LENGTH` (use `SUBSTRING(f FROM n) <> ''` to test a length),
`CURRENT_DATE/TIME/TIMESTAMP`, `CONVERT` (use `CAST`), `CROSS JOIN`, `NATURAL`/`USING` joins,
`EXCEPT`, `INTERSECT`, `CREATE VIEW`, `LIMIT`/`TOP`, `CHECK`/`FOREIGN KEY` constraints.
`DISTINCT` doesn't work with memo/BLOB columns.

## Gotchas

- **Quoting.** Names with spaces or equal to a reserved word must be enclosed in quotes
  **and** prefixed with the table name or alias (`SELECT t."Date" FROM t`).
  Table names with an extension are double-quoted: `"CUSTOMERS.DBF"`.
- **`LIKE` is case-sensitive.** Use `UPPER(f) LIKE UPPER(:p)` for case-insensitive searches.
- **Dates.** Literals depend on the Windows date settings (US or European order,
  quoted). Use **parameters** for dates instead of literals or `{d '...'}` escapes.
- **Booleans.** `TRUE`/`FALSE` (case-insensitive) or `"T"`/`"F"` in quotes.
- **Strings.** `CHAR`/`VARCHAR` are at most 254 bytes; the case conversion depends on the
  table's language driver.
- **Reserved words** (a long list, see `FKeywords` in `FireDAC.Phys.BDEMeta.pas`) can't be used
  as unquoted column names. The driver tells FireDAC about them so generated SQL quotes them.
- **Memo parameters.** Give memo parameters a memo type (`ftMemo`/`ftWideMemo`), not a string.
