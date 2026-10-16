# FireDAC-BDE

**Driver FireDAC per il BDE**

Un **driver fisico FireDAC (`DriverID=BDE`)** che permette al codice FireDAC
moderno di leggere e scrivere tabelle legacy **dBase III/IV (`.DBF`)** e
**Paradox 7+ (`.DB`)** tramite il Borland Database Engine (BDE).

Si continuano a usare `TFDConnection`, `TFDQuery`, `TFDTable`, transazioni e
parametri come con qualsiasi altro database FireDAC; il driver si occupa di
parlare con il BDE.

> Progetto non ufficiale, della community. Non affiliato né approvato da Embarcadero.
> Sviluppato e collaudato con **Delphi 13.2**, solo Windows a 32 bit (il BDE è a 32 bit).
> 🇬🇧 [English version](README.md)

## Perché

Passare un'applicazione da BDE a FireDAC è semplice; migrare i *dati* spesso no
(file DBF/Paradox condivisi con altri programmi legacy). Questo driver permette
al codice FireDAC nuovo di lavorare **direttamente sui file legacy** mentre i
vecchi programmi continuano a girare, senza infrastrutture ibride.

## Funzioni

- Connessione tramite alias BDE **oppure** percorso di una cartella (senza alias).
- Metadati: elenco tabelle, campi, indici, chiave primaria.
- `TFDQuery` / `TFDTable` / `TFDCommand` con parametri nominali; lettura di tutti i
  tipi di campo, compresi memo e BLOB.
- Modifiche con `Edit/Post`, `Append`, `Delete` e `UPDATE/INSERT/DELETE` diretti.
- Transazioni (`StartTransaction/Commit/Rollback`), collaudate con rollback su DBF e Paradox.
- Accesso condiviso con altre applicazioni; errori di record bloccato mappati su
  `ekRecordLocked`; attesa sul lock configurabile (`LockRetry`).
- File DBF e Paradox con lo **stesso nome base** nella stessa cartella.
- Package design-time (componente `TFDPhysBDEDriverLink`).

## Requisiti

- Delphi con FireDAC (sviluppato su 13.2; altre versioni non provate).
- **BDE** installato e funzionante (package `bdertl`). Il BDE è un prodotto legacy
  Embarcadero da ottenere secondo la propria licenza; qui non c'è nulla del BDE o dei sorgenti FireDAC.
- Piattaforma di compilazione: **Windows 32 bit**.

## Installazione

1. Clona il repository (`git clone https://github.com/<tuo-utente>/Firedac-BDE.git`) e apri `FDBDE_D132.groupproj` (piattaforma **Win32**).
2. Compila `FDBDERun` (package runtime, richiede `bdertl`).
3. Compila e **Installa** `FDBDEDesign` (package design-time).
4. Nei tuoi progetti aggiungi `FDBDERun` ai package runtime, oppure inserisci
   `FireDAC.Phys.BDEDef` e `FireDAC.Phys.BDE` in uno `uses`: il driver si registra da solo.

Da riga di comando (Windows, Delphi 13): `build.bat [Debug|Release]` compila i package e `BDETest`;
`test.bat` esegue `BDETest` su una copia dei dati di prova sintetici; `install-ide.bat` registra il
package design-time nell'IDE (chiudi prima RAD Studio); `clean.bat` rimuove i file generati.
Altre versioni di Delphi: `set BDSVER=<n>` oppure `set RSVARS=<percorso di rsvars.bat>`.

Se il compilatore non trova `FireDAC.inc`, aggiungi `$(BDS)\source\data\firedac` al
percorso di ricerca (non copiare il file nel repository: è di Embarcadero).

## Uso

```pascal
FDConnection1.DriverName := 'BDE';
FDConnection1.Params.Database := 'C:\Dati\Legacy';   // cartella con .DBF/.DB, oppure alias BDE
FDConnection1.Params.Values['LockRetry'] := '1';     // facoltativo
FDConnection1.Open;

// Il nome tabella vuole l'estensione e i doppi apici in SQL
FDQuery1.Open('select * from "CLIENTI.DBF" where ID = :id', [42]);

// Per aggiornare un DBF serve un campo chiave UNIVOCO (il DBF non ha chiave primaria)
FDQuery1.UpdateOptions.UpdateTableName := 'CLIENTI.DBF';
FDQuery1.UpdateOptions.KeyFields := 'ID';
FDQuery1.Edit;
FDQuery1.FieldByName('NOME').AsString := 'Nuovo nome';
FDQuery1.Post;
```

### Parametri di connessione

| Parametro    | Significato |
|--------------|-------------|
| `DriverID`   | `BDE` |
| `Database`   | Alias BDE, **oppure** cartella con i file DBF/Paradox |
| `BDEDriver`  | Driver BDE usato con un percorso. Default `STANDARD` (DBF + Paradox) |
| `NetFileDir` | Cartella di `PDOXUSRS.NET` per Paradox condiviso (uguale per tutti gli utenti) |
| `PrivateDir` | Cartella temporanea della sessione BDE. Default: cartella temporanea automatica, rimossa alla disconnessione |
| `LockRetry`  | Secondi di attesa su record bloccato. `0` = non attendere. Non impostato = default BDE (circa 6 s) |
| `Password`   | Password della tabella Paradox (`AddPassword`) |

## Limiti da conoscere

- **Solo Windows a 32 bit.**
- **Dialetto SQL = Local SQL del BDE**: niente `LIMIT/TOP`, `CASE`, `COALESCE`, `CURRENT_DATE`, `LENGTH`,
  poche funzioni, join e sottoquery limitati; `LIKE` distingue maiuscole e minuscole; per le date usa i parametri.
  Skip e limite li fa FireDAC lato client. Vedi [docs/LOCAL_SQL.it.md](docs/LOCAL_SQL.it.md).
  Per `CASE`, `COALESCE`, `LIMIT`, CTE o join tra sorgenti puoi usare il Local SQL di FireDAC
  (tabelle virtuali SQLite) sopra il driver: [docs/LOCAL_SQL_ON_BDE.it.md](docs/LOCAL_SQL_ON_BDE.it.md) (sperimentale).
- **Estensioni dei file.** Una cartella può contenere `CLIENTI.DB` e `CLIENTI.DBF`: usa sempre
  l'estensione e i doppi apici (`"CLIENTI.DBF"`); senza, il BDE sceglie Paradox.
- **Il DBF non ha chiave primaria.** Imposta `UpdateOptions.KeyFields` su un campo davvero univoco,
  altrimenti FireDAC segnala *"Exact update affected [N] rows"*.
- **Parametri memo.** Per scrivere un memo con SQL scritto a mano dai al parametro un tipo memo
  (`DataType := ftWideMemo; AsWideMemo := ...`). Un parametro stringa su una colonna memo, su Paradox,
  non dà errore ma non scrive nulla (vale anche su dBase). `Edit/Post` non è interessato.
- **Rollback di un memo vuoto (dBase III).** Annullare con rollback una transazione che ha dato un valore
  a un memo prima vuoto può lasciare il BDE in uno stato incoerente: la query successiva su quella riga
  fallisce con "BLOB already opened". Le righe con un memo già presente non sono interessate. Dopo un
  rollback del genere chiudi e riapri la connessione. (Comportamento del BDE, visto su dBase III;
  non visto su dBase IV.)
- **Lock.** L'attesa su un record bloccato dipende dal BDE: usa `LockRetry`. Nei test una riga modificata
  in una transazione aperta resta bloccata per le altre connessioni fino a commit/rollback, sia su DBF sia su Paradox.
- **Una sessione BDE per connessione**; il BDE non è pensato per un multi-threading spinto.
- Le stringhe sono Unicode; la conversione usa il language driver della tabella, quindi i caratteri
  fuori dalla codepage della tabella possono non sopravvivere.
- **Il testo dei memo è decodificato con la codepage ANSI di sistema.** Se un'applicazione ha salvato UTF-8
  dentro un memo (per esempio XML con BOM), si ottengono i byte UTF-8 come caratteri ANSI (`ï»¿<?xml ...`).
  La conversione è reversibile: ridecodifica nel tuo codice con
  `TEncoding.UTF8.GetString(TEncoding.ANSI.GetBytes(S))`.
- Non implementati: DDL (creazione/modifica tabelle via FireDAC), stored procedure, event alerter,
  ottimizzazione array DML (gli array sono eseguiti riga per riga).

## Cosa è stato provato

Tabelle dBase IV reali (≈3.600 righe, 119 campi, memo) e Paradox, Delphi 13.2, con `Demos\BDETest`:

| Area | DBF | Paradox |
|---|---|---|
| Connessione, tabelle, campi, indici | ✅ | ✅ |
| Select, count, fetch, parametri, `Locate` | ✅ | ✅ |
| Update / insert / delete con rollback | ✅ | ✅ |
| Memo in lettura e scrittura (dataset e parametro) | ✅ | ✅ |
| Accesso concorrente da due applicazioni | ✅ | ✅ |
| Lock di record tra due connessioni | ✅ | ✅ |
| Password sulla tabella | – | non provato |
| Campi BLOB / OLE / grafici | non provato | non provato |
| Altre versioni di Delphi | non provato | non provato |

## Provarlo

```
python Tools/make_sample_dbf.py            # crea Demos/Data/SAMPLE.DBF + .DBT (dati sintetici)
Demos\BDETest.exe Demos\Data SAMPLE.DBF ID NAME NOTES
```

`BDETest <cartella|alias> <TABELLA.DB|DBF> [campo chiave] [campo testo] [campo memo] [riga 1-5] [campo data]`

Con chiave, testo e memo il test esegue anche update, insert, delete e scrittura del memo dentro una
transazione annullata con rollback, più un test di lock con una seconda connessione.
**Esegui i test di scrittura su una copia dei dati.**
`BDETest` accetta un sesto parametro opzionale (riga 1-5 da usare come chiave); la riga 3 di `SAMPLE.DBF`
ha un memo, la riga 1 no.
Una tabella Paradox di prova si crea con `Tools\MakeSampleParadox.dpr` (non provato).

## Struttura

```
Source/      unit del driver (BDEDef, BDEMeta, BDE) + registrazione design-time (BDEReg)
Packages/    package Delphi (d132 = Delphi 13.2)
Demos/       programma console BDETest + dati di prova sintetici
Tools/       generatori di dati di prova
docs/        note sull'architettura
```

## Contributi

Segnalazioni di bug e risultati su altre versioni di Delphi o altri tipi di tabella sono benvenuti:
vedi [CONTRIBUTING.md](CONTRIBUTING.md).

## Licenza

[MIT](LICENSE). FireDAC, il BDE e Delphi sono prodotti di Embarcadero Technologies.
