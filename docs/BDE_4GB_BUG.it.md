# "Insufficient disk space" (bug dei 4 GB del BDE)

## Sintomo

Una query fallisce all'improvviso con un errore come

```
Insufficient disk space ... _QSQL000.DBF ... Table does not exist
```

anche se il disco ha molto spazio libero. Capita spesso aprendo un `TQuery` (il BDE scrive il risultato di ogni
query in una tabella di risposta nella cartella temporanea, che il driver tiene in `%TEMP%\FDBDE_<guid>`).
Va e viene: può sparire dopo un riavvio, o dopo aver cancellato dei file, e poi ripresentarsi.

## Causa

È un bug del BDE (`idapi32.dll`), non del driver. Per controllare lo spazio libero il BDE chiama l'API ANSI
`GetDiskFreeSpaceA` e ne interpreta male il risultato quando lo spazio libero del disco è vicino a un multiplo di
4 GB. La condizione dipende solo dallo spazio libero in quel momento, per questo l'errore sembra casuale. È il
noto "BDE 4 GB bug" (segnalazione 7089 su Quality Central).

## Verifica

`FreeSpaceInfo(Path)` della unit qui sotto restituisce lo spazio libero reale e lo stesso valore modulo 4 GB:

```pascal
ShowMessage(FreeSpaceInfo(TPath.GetTempPath));
```

Se il secondo valore è vicino a 0 o a 4 GB mentre compare l'errore, è questo bug.

## Rimedio

Aggiungi `Demos\FixBDE4GbBug.pas` al programma (serve a qualunque programma che usa il BDE, con o senza questo
driver) e mettila **per prima** nella `uses` del `.dpr`, prima di qualsiasi unit che possa caricare il BDE:

```pascal
program MioProgramma;

uses
  FixBDE4GbBug,   // deve essere la prima
  Vcl.Forms,
  ...
```

La unit reindirizza `kernel32!GetDiskFreeSpaceA` solo per il processo corrente: la sostituta usa
`GetDiskFreeSpaceExA` e restituisce lo spazio libero in una forma che il BDE gestisce. Non richiede nessuna DLL
(solo `kernel32.dll`), non modifica nulla su disco e ripristina il codice originale alla chiusura.

- Solo Win32 (il BDE è solo a 32 bit); per altri target la unit non compila.
- È il porting per Delphi con stringhe Unicode della unit del 2004 di Reinaldo Roberto Yañez Arrey. Intestazione
  dell'autore e licenza sono mantenute nel file.
- Modifica il processo, quindi non fa parte del driver e il driver non ne ha bisogno. Includerla è una scelta
  dell'applicazione.
- Verificato: l'errore ricomparso nei test su una tabella di 22.323 righe è sparito dopo aver aggiunto la unit.
