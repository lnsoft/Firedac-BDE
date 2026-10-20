program BDETest;

{ Test console del driver FireDAC BDE (solo Win32).

  Uso:
    BDETest <cartella o alias BDE> <tabella.DB|tabella.DBF> [campo chiave] [campo testo] [campo memo]

  La tabella va indicata CON l'estensione: in un alias possono coesistere
  CLIENTI.DB e CLIENTI.DBF. Nelle query SQL il nome con estensione va tra
  virgolette doppie (lo fa il test).

  - Senza campo chiave: test di connessione, metadati, select e TFDTable.
  - Con campo chiave: aggiunge il test con parametro e Locate.
  - Con campo testo: aggiunge il test di SCRITTURA (update + rollback).
  - Con campo chiave: aggiunge anche insert + delete (con rollback).
  - Con campo memo (5o parametro): aggiunge la scrittura di un memo lungo.
    Eseguirli SOLO su una COPIA dei dati.

  Esempio:
    BDETest .\Data SAMPLE.DBF ID NAME NOTES }

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Diagnostics, System.Variants,
  System.StrUtils, System.IOUtils,
  Data.DB, BDE, Bde.DBTables,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.DApt.Intf, FireDAC.DApt,
  FireDAC.UI.Intf, FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client, FireDAC.Comp.DataSet,
  FireDAC.Phys.BDEDef in '..\Source\FireDAC.Phys.BDEDef.pas',
  FireDAC.Phys.BDEMeta in '..\Source\FireDAC.Phys.BDEMeta.pas',
  FireDAC.Phys.BDE in '..\Source\FireDAC.Phys.BDE.pas';

var
  Conn: TFDConnection;
  Folder, TabName, SqlTab, KeyField, TextField, MemoField: String;
  FirstKey: Variant;
  DateField: String;
  KeyRow: Integer = 1;  // riga (1..5) da cui prendere la chiave: 6o parametro
  FailCount: Integer;

procedure Run(const AName: String; AProc: TProc);
begin
  Write(AName, ' ... ');
  try
    AProc();
    Writeln('OK');
  except
    on E: Exception do begin
      Inc(FailCount);
      Writeln('FALLITO');
      Writeln('    ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

function QuoteTab(const AName: String): String;
var
  i: Integer;
begin
  Result := AName;
  for i := 1 to Length(AName) do
    if not CharInSet(AName[i], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then begin
      Result := '"' + AName + '"';
      Break;
    end;
end;

procedure TestConnect;
begin
  Conn.Open;
end;

procedure TestTables;
var
  L: TStringList;
  i: Integer;
  lFound: Boolean;
begin
  L := TStringList.Create;
  try
    // AFullName = False: nomi grezzi, senza le virgolette che FireDAC
    // aggiunge ai nomi con il punto (es. "CLI00.DBF")
    Conn.GetTableNames('', '', '', L, [osMy], [tkTable], False);
    Writeln;
    Writeln('    ', L.Count, ' tabelle: ', Copy(L.CommaText, 1, 250));
    Write('    ');
    if L.Count = 0 then
      raise Exception.Create('Nessuna tabella trovata');
    lFound := False;
    for i := 0 to L.Count - 1 do
      if SameText(AnsiDequotedStr(L[i], '"'), TabName) then begin
        lFound := True;
        Break;
      end;
    if not lFound then
      raise Exception.Create('La tabella ' + TabName +
        ' non e'' nell''elenco: indicala con l''estensione (.DB o .DBF)');
  finally
    L.Free;
  end;
end;

procedure TestFields;
var
  L: TStringList;
  M: TFDMetaInfoQuery;
begin
  L := TStringList.Create;
  try
    Conn.GetFieldNames('', '', TabName, '', L);
    Write('(', L.Count, ' campi) ');
    M := TFDMetaInfoQuery.Create(nil);
    try
      M.Connection := Conn;
      M.MetaInfoKind := mkTableFields;
      M.ObjectName := TabName;
      M.Open;
      Writeln;
      while not M.Eof do begin
        Writeln('    ', M.FieldByName('COLUMN_NAME').AsString, ' : ',
          M.FieldByName('COLUMN_TYPENAME').AsString, ' (',
          M.FieldByName('COLUMN_LENGTH').AsString, ')');
        M.Next;
      end;
      Write('    ');
    finally
      M.Free;
    end;
    if L.Count = 0 then
      raise Exception.Create('Nessun campo per ' + TabName);
  finally
    L.Free;
  end;
end;

procedure TestIndexes;
var
  M: TFDMetaInfoQuery;
  s: String;
begin
  M := TFDMetaInfoQuery.Create(nil);
  try
    M.Connection := Conn;
    M.MetaInfoKind := mkIndexes;
    M.ObjectName := TabName;
    M.Open;
    s := '';
    while not M.Eof do begin
      s := s + M.FieldByName('INDEX_NAME').AsString + ' ';
      M.Next;
    end;
    Write('(indici: ', Trim(s), ') ');
  finally
    M.Free;
  end;
end;

procedure TestSelect;
var
  Q: TFDQuery;
  i, n, iMax: Integer;
  s: String;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Open('select * from ' + SqlTab);
    Writeln;
    s := '';
    for i := 0 to Q.FieldCount - 1 do
      s := s + Q.Fields[i].FieldName + ':' +
        FieldTypeNames[Q.Fields[i].DataType] + ' ';
    Writeln('    Campi: ', Copy(s, 1, 300));
    iMax := Q.FieldCount;
    if iMax > 4 then
      iMax := 4;
    n := 0;
    while (not Q.Eof) and (n < 5) do begin
      s := '';
      for i := 0 to iMax - 1 do
        s := s + Q.Fields[i].AsString + ' | ';
      Writeln('    ', s);
      if (n = KeyRow - 1) and (KeyField <> '') then
        FirstKey := Q.FieldByName(KeyField).Value;
      Inc(n);
      Q.Next;
    end;
    if n = 0 then
      raise Exception.Create('La tabella e'' vuota o non letta');
    Write('    ');
  finally
    Q.Free;
  end;
end;

procedure TestCount;
var
  Q: TFDQuery;
  iCount, iFetched: Integer;
  SW: TStopwatch;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Open('select count(*) from ' + SqlTab);
    iCount := Q.Fields[0].AsInteger;
    Q.Close;
    SW := TStopwatch.StartNew;
    Q.Open('select * from ' + SqlTab);
    Q.FetchAll;
    iFetched := Q.RecordCount;
    SW.Stop;
    Write('(count=', iCount, ', righe lette=', iFetched, ', ',
      SW.ElapsedMilliseconds, ' ms) ');
    if iCount <> iFetched then
      raise Exception.Create('count(*) e righe lette non coincidono');
  finally
    Q.Free;
  end;
end;

procedure TestTableCursor;
var
  C2: TFDConnection;
  QA, QB: TFDQuery;
  sF0, sF1: String;
  n, n0, n1: Integer;
  bTab: Boolean;
  vMin, vMax, vMid: Variant;
  oT: TFDTable;
  SWt: TStopwatch;

  // WHERE + ORDER BY sulla chiave: si confrontano le chiavi (l'ordine tra chiavi uguali
  // non e' definito) e il numero totale di righe
  procedure CmpKeys(const ASQL, ALabel: String; AExpectTable: Boolean;
    const A1, A2: Variant);
  var
    m0, m1, nA, nB: Integer;
    bT: Boolean;
    SW: TStopwatch;
    msA, msB: Int64;
  begin
    m0 := BDEStatTableCursorOpens;
    SW := TStopwatch.StartNew;
    if VarIsEmpty(A1) then QA.Open(ASQL)
    else if VarIsEmpty(A2) then QA.Open(ASQL, [A1])
    else QA.Open(ASQL, [A1, A2]);
    msA := SW.ElapsedMilliseconds;
    m1 := BDEStatTableCursorOpens;
    SW := TStopwatch.StartNew;
    if VarIsEmpty(A1) then QB.Open(ASQL)
    else if VarIsEmpty(A2) then QB.Open(ASQL, [A1])
    else QB.Open(ASQL, [A1, A2]);
    msB := SW.ElapsedMilliseconds;
    bT := BDEStatTableCursorOpens > m1;
    try
      if m1 <> m0 then
        raise Exception.Create(ALabel + ': senza TableCursor non deve usare la TTable');
      if bT <> AExpectTable then
        raise Exception.Create(ALabel + ': uso della TTable diverso dall''atteso (atteso ' +
          BoolToStr(AExpectTable, True) + ')');
      nA := 0;
      while (not QA.Eof) and (not QB.Eof) and (nA < 5000) do begin
        if QA.FieldByName(KeyField).AsString <> QB.FieldByName(KeyField).AsString then
          raise Exception.CreateFmt('%s: riga %d, chiave diversa (%s / %s)',
            [ALabel, nA + 1, QA.FieldByName(KeyField).AsString,
             QB.FieldByName(KeyField).AsString]);
        Inc(nA);
        QA.Next;
        QB.Next;
      end;
      nB := nA;
      while not QA.Eof do begin
        Inc(nA);
        QA.Next;
      end;
      while not QB.Eof do begin
        Inc(nB);
        QB.Next;
      end;
      if nA <> nB then
        raise Exception.CreateFmt('%s: righe diverse (TQuery %d, secondo percorso %d)',
          [ALabel, nA, nB]);
      Write('(', ALabel, ': ', nA, ' righe; TQuery ', msA, ' ms, ',
        IfThen(bT, 'TTable ', 'TQuery '), msB, ' ms) ');
    finally
      QA.Close;
      QB.Close;
    end;
  end;

  procedure Cmp(const ASQL, ALabel: String; AExpectTable: Boolean;
    const AParam: Variant);
  var
    SW: TStopwatch;
    j, n: Integer;
    msA, msB: Int64;
    n0, n1: Integer;
    bTable: Boolean;
  begin
    n0 := BDEStatTableCursorOpens;
    SW := TStopwatch.StartNew;
    if VarIsEmpty(AParam) then QA.Open(ASQL) else QA.Open(ASQL, [AParam]);
    msA := SW.ElapsedMilliseconds;
    n1 := BDEStatTableCursorOpens;
    SW := TStopwatch.StartNew;
    if VarIsEmpty(AParam) then QB.Open(ASQL) else QB.Open(ASQL, [AParam]);
    msB := SW.ElapsedMilliseconds;
    bTable := BDEStatTableCursorOpens > n1;
    try
      if n1 <> n0 then
        raise Exception.Create('Senza TableCursor la query non deve usare la TTable');
      if bTable <> AExpectTable then
        raise Exception.Create(ALabel + ': uso della TTable diverso dall''atteso (atteso ' +
          BoolToStr(AExpectTable, True) + ')');
      if QA.FieldCount <> QB.FieldCount then
        raise Exception.Create(ALabel + ': numero di campi diverso');
      n := 0;
      while (not QA.Eof) and (not QB.Eof) and (n < 5000) do begin
        for j := 0 to QA.FieldCount - 1 do
          if QA.Fields[j].AsString <> QB.Fields[j].AsString then
            raise Exception.CreateFmt('%s: riga %d, campo %s diverso (TQuery "%s" %s, TTable "%s" %s; campi TQuery: %s, TTable: %s)',
              [ALabel, n + 1, QA.Fields[j].FieldName,
               QA.Fields[j].AsString, FieldTypeNames[QA.Fields[j].DataType],
               QB.Fields[j].AsString, FieldTypeNames[QB.Fields[j].DataType],
               QA.Fields[0].FieldName + '/' + QA.Fields[QA.FieldCount - 1].FieldName,
               QB.Fields[0].FieldName + '/' + QB.Fields[QB.FieldCount - 1].FieldName]);
        Inc(n);
        QA.Next;
        QB.Next;
      end;
      if (n < 5000) and (QA.Eof <> QB.Eof) then
        raise Exception.Create(ALabel + ': numero di righe diverso');
      Write('(', ALabel, ': ', n, ' righe uguali; TQuery ', msA, ' ms, ',
        IfThen(bTable, 'TTable ', 'TQuery '), msB, ' ms) ');
    finally
      QA.Close;
      QB.Close;
    end;
  end;

begin
  bTab := False;
  C2 := TFDConnection.Create(nil);
  QA := TFDQuery.Create(nil);
  QB := TFDQuery.Create(nil);
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    QA.Connection := Conn;
    QB.Connection := C2;
    QA.Open('select * from ' + SqlTab);
    sF0 := QA.Fields[0].FieldName;
    sF1 := sF0;
    if QA.FieldCount > 1 then
      sF1 := QA.Fields[1].FieldName;
    QA.Close;
    Cmp('select * from ' + SqlTab, 'select *', True, Unassigned);
    try
      Cmp('SELECT ' + sF0 + ', ' + sF1 + ' FROM ' + SqlTab, 'campi', True, Unassigned);
    except
      on E: Exception do
        if Pos('keyword', E.Message) > 0 then
          Write('(campi: saltato, ', sF0, ' o ', sF1, ' e'' una parola riservata del Local SQL) ')
        else
          raise;
    end;
    // campo tra virgolette = stringa letterale nel Local SQL: deve restare al TQuery
    Cmp('select "' + sF0 + '" from ' + SqlTab, 'campo quotato (resta TQuery)', False, Unassigned);
    if (KeyField <> '') and not VarIsNull(FirstKey) and not VarIsEmpty(FirstKey) then
      Cmp('select * from ' + SqlTab + ' where ' + KeyField + ' = :k',
        'con WHERE (resta TQuery)', False, FirstKey);
    // TFDTable.Open genera 'SELECT A.* FROM "tab" A' (alias A): deve usare la TTable
    oT := TFDTable.Create(nil);
    try
      oT.Connection := C2;
      oT.TableName := TabName;
      n1 := BDEStatTableCursorOpens;
      SWt := TStopwatch.StartNew;
      oT.Open;
      if BDEStatTableCursorOpens = n1 then
        raise Exception.Create('TFDTable.Open non usa la TTable');
      Write('(TFDTable.Open con TTable: ', SWt.ElapsedMilliseconds, ' ms) ');
    finally
      oT.Free;
    end;
    // ORDER BY sulla chiave: con indice usa la TTable; l'ordine della chiave deve coincidere
    // (tra righe con la stessa chiave l'ordine non e' definito: si confronta solo la chiave)
    if KeyField <> '' then begin
      n0 := BDEStatTableCursorOpens;
      QA.Open('select * from ' + SqlTab + ' order by ' + KeyField);
      n1 := BDEStatTableCursorOpens;
      QB.Open('select * from ' + SqlTab + ' order by ' + KeyField);
      bTab := BDEStatTableCursorOpens > n1;
      try
        if n1 <> n0 then
          raise Exception.Create('order by: senza TableCursor non deve usare la TTable');
        n := 0;
        while (not QA.Eof) and (not QB.Eof) and (n < 5000) do begin
          if QA.FieldByName(KeyField).AsString <> QB.FieldByName(KeyField).AsString then
            raise Exception.CreateFmt('order by %s: riga %d, chiave diversa (%s / %s)',
              [KeyField, n + 1, QA.FieldByName(KeyField).AsString,
               QB.FieldByName(KeyField).AsString]);
          Inc(n);
          QA.Next;
          QB.Next;
        end;
        Write('(order by ', KeyField, ': ', n, ' chiavi uguali, ',
          IfThen(bTab, 'TTable', 'TQuery (nessun indice adatto)'), ') ');
      finally
        QA.Close;
        QB.Close;
      end;
      // DESC resta al TQuery
      n1 := BDEStatTableCursorOpens;
      QB.Open('select * from ' + SqlTab + ' order by ' + KeyField + ' desc');
      try
        if BDEStatTableCursorOpens <> n1 then
          raise Exception.Create('order by desc non deve usare la TTable');
        Write('(order by desc: resta TQuery) ');
      finally
        QB.Close;
      end;
    end;
    // WHERE + ORDER BY sullo stesso campo numerico: intervalli con SetRange sulla TTable
    if (KeyField <> '') and not VarIsNull(FirstKey) and not VarIsEmpty(FirstKey) and
       VarIsNumeric(FirstKey) then begin
      vMin := Conn.ExecSQLScalar('select min(' + KeyField + ') from ' + SqlTab);
      vMax := Conn.ExecSQLScalar('select max(' + KeyField + ') from ' + SqlTab);
      vMid := vMin + (vMax - vMin) / 2;
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' = :a order by ' + KeyField,
        'where = + order by', bTab, FirstKey, Unassigned);
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' >= :a and ' + KeyField +
        ' <= :b order by ' + KeyField, 'where >= e <=', bTab, vMid, vMax);
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' > :a order by ' + KeyField,
        'where >', bTab, vMid, Unassigned);
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' < :a order by ' + KeyField,
        'where <', bTab, vMid, Unassigned);
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' >= ' + FloatToStr(vMid, TFormatSettings.Invariant) +
        ' order by ' + KeyField, 'where >= numero letterale', bTab, Unassigned, Unassigned);
      // casi che devono restare al TQuery
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' >= :a order by ' + KeyField + ' desc',
        'where con order by desc (resta TQuery)', False, vMid, Unassigned);
      CmpKeys('select * from ' + SqlTab + ' where ' + KeyField + ' >= :a',
        'where senza order by (resta TQuery)', False, vMid, Unassigned);
    end;
    // scrittura nella stessa connessione mentre la TTable e' aperta
    if (TextField <> '') and (KeyField <> '') and not VarIsNull(FirstKey) then begin
      QB.Open('select * from ' + SqlTab);
      C2.StartTransaction;
      try
        C2.ExecSQL('update ' + SqlTab + ' set ' + TextField + ' = ' + TextField +
          ' where ' + KeyField + ' = :k', [FirstKey]);
        QB.Next;
        Write('(update con TTable aperta: ok) ');
      finally
        C2.Rollback;
        QB.Close;
      end;
    end;
  finally
    QB.Free;
    QA.Free;
    C2.Free;
  end;
end;

type
  // gestore di prova per OnBDEIndexNeeded
  TIdxProbe = class
  public
    Calls: Integer;
    Mode: Integer;            // 0 accetta la proposta, 1 rifiuta, 2 indice inesistente, 3 solleva un errore
    LastTable, LastFields: String;
    LastDesc: Boolean;
    LastProposed: String;
    LastAcceptIn: Boolean;
    RangeCalls: Integer;
    RangeMode: Integer;       // 0 non gestisce (comportamento standard), 1 imposta lui il SetRange
    RangeCondCount: Integer;
    RangeField, RangeOp: String;
    procedure OnRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
      const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
    procedure OnNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
      ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
  end;

procedure TIdxProbe.OnNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
  ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
begin
  Inc(Calls);
  LastAcceptIn := AAccept;
  LastTable := ATableName;
  LastFields := AFieldNames;
  LastDesc := ADescending;
  LastProposed := AIndexName;
  case Mode of
  1: AAccept := False;
  2: AIndexName := 'INDICE_CHE_NON_ESISTE';
  3: raise Exception.Create('errore di prova');
  end;
end;

procedure TIdxProbe.OnRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
var
  T: TTable;
begin
  Inc(RangeCalls);
  RangeCondCount := Length(AConditions);
  if RangeCondCount > 0 then begin
    RangeField := AConditions[0].Field;
    RangeOp := AConditions[0].Op;
  end;
  if (RangeMode = 1) and (RangeCondCount = 1) and (AConditions[0].Op = '=') then begin
    T := TTable(ADataSet);
    T.SetRangeStart;
    T.FieldByName(AConditions[0].Field).Value := AConditions[0].Value;
    T.SetRangeEnd;
    T.FieldByName(AConditions[0].Field).Value := AConditions[0].Value;
    T.ApplyRange;
    AHandled := True;
  end;
end;

// OnBDEIndexNeeded: il programma sceglie l'indice o rifiuta; senza gestore non cambia nulla
procedure TestIndexNeeded;
var
  C2: TFDConnection;
  QA, QB: TFDQuery;
  P: TIdxProbe;
  bNum, bRaised: Boolean;

  // esegue la query sulle due connessioni (Conn senza TableCursor, C2 con TableCursor e
  // gestore) e confronta le righe; torna True se C2 ha usato la TTable
  function RunBoth(const ASQL: String; const AParam: Variant; AOrdered: Boolean;
    const ALabel: String): Boolean;
  var
    m0, nA, nB: Integer;
  begin
    if VarIsEmpty(AParam) then QA.Open(ASQL) else QA.Open(ASQL, [AParam]);
    // la scelta dell'indice avviene in Prepare: con lo stesso testo SQL FireDAC non
    // ripreparerebbe il comando, quindi si parte sempre da non preparato
    QB.Unprepare;
    m0 := BDEStatTableCursorOpens;
    try
      if VarIsEmpty(AParam) then QB.Open(ASQL) else QB.Open(ASQL, [AParam]);
      Result := BDEStatTableCursorOpens > m0;
      nA := 0;
      nB := 0;
      while (not QA.Eof) and (not QB.Eof) do begin
        if AOrdered and (QA.FieldByName(KeyField).AsString <> QB.FieldByName(KeyField).AsString) then
          raise Exception.CreateFmt('%s: riga %d, chiave diversa', [ALabel, nA + 1]);
        Inc(nA);
        Inc(nB);
        QA.Next;
        QB.Next;
      end;
      while not QA.Eof do begin Inc(nA); QA.Next; end;
      while not QB.Eof do begin Inc(nB); QB.Next; end;
      if nA <> nB then
        raise Exception.CreateFmt('%s: righe diverse (%d / %d)', [ALabel, nA, nB]);
    finally
      QA.Close;
      QB.Close;
    end;
  end;

var
  m0: Integer;
  bTab: Boolean;
  sTxt: String;
begin
  C2 := TFDConnection.Create(nil);
  QA := TFDQuery.Create(nil);
  QB := TFDQuery.Create(nil);
  P := TIdxProbe.Create;
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    QA.Connection := Conn;
    QB.Connection := C2;
    bNum := (not VarIsNull(FirstKey)) and (not VarIsEmpty(FirstKey)) and VarIsNumeric(FirstKey);

    C2.OnBDEIndexNeeded := P.OnNeeded;
    if not Assigned(C2.OnBDEIndexNeeded) then
      raise Exception.Create('il gestore non e'' stato registrato');

    // 1) ORDER BY: il gestore e' chiamato con i campi e la proposta del driver
    P.Mode := 0;
    P.Calls := 0;
    bTab := RunBoth('select * from ' + SqlTab + ' order by ' + KeyField, Unassigned, True, 'order by');
    if P.Calls <> 1 then
      raise Exception.CreateFmt('order by: gestore chiamato %d volte (atteso 1)', [P.Calls]);
    if not SameText(P.LastFields, KeyField) then
      raise Exception.Create('order by: campi ricevuti ' + P.LastFields);
    if bTab <> (P.LastProposed <> '') then
      raise Exception.Create('order by: uso della TTable incoerente con la proposta');
    Write('(order by: proposta "', P.LastProposed, '", TTable ', BoolToStr(bTab, True), ') ');

    // 2) il gestore rifiuta: TQuery
    P.Mode := 1;
    P.Calls := 0;
    if RunBoth('select * from ' + SqlTab + ' order by ' + KeyField, Unassigned, True, 'rifiuto')
       or (P.Calls <> 1) then
      raise Exception.Create('rifiuto: la TTable non doveva essere usata');

    // 3) indice inesistente: TQuery, nessun errore
    P.Mode := 2;
    P.Calls := 0;
    if RunBoth('select * from ' + SqlTab + ' order by ' + KeyField, Unassigned, True, 'indice inesistente')
       or (P.Calls <> 1) then
      raise Exception.Create('indice inesistente: la TTable non doveva essere usata');

    // 4) ORDER BY discendente: il gestore e' chiamato con ADescending = True
    P.Mode := 0;
    P.Calls := 0;
    bTab := RunBoth('select * from ' + SqlTab + ' order by ' + KeyField + ' desc', Unassigned, True, 'desc');
    if (P.Calls <> 1) or not P.LastDesc then
      raise Exception.Create('desc: gestore non chiamato come atteso');
    Write('(desc: proposta "', P.LastProposed, '", TTable ', BoolToStr(bTab, True), ') ');

    // 5) WHERE senza ORDER BY: oggi resta al TQuery, con il gestore puo' usare un indice
    if bNum then begin
      P.Mode := 0;
      P.Calls := 0;
      bTab := RunBoth('select * from ' + SqlTab + ' where ' + KeyField + ' = :k', FirstKey, False, 'where');
      if (P.Calls <> 1) or not SameText(P.LastFields, KeyField) then
        raise Exception.Create('where: gestore non chiamato come atteso');
      if bTab <> (P.LastProposed <> '') then
        raise Exception.Create('where: uso della TTable incoerente con la proposta');
      Write('(where senza order by: proposta "', P.LastProposed, '", TTable ', BoolToStr(bTab, True), ') ');
    end;

    // 6) un errore del gestore si propaga (non viene scambiato per "query non gestita")
    P.Mode := 3;
    bRaised := False;
    QB.Unprepare;
    try
      QB.Open('select * from ' + SqlTab + ' order by ' + KeyField);
    except
      on E: Exception do
        bRaised := Pos('errore di prova', E.Message) > 0;
    end;
    QB.Close;
    if not bRaised then
      raise Exception.Create('l''errore del gestore non si e'' propagato');

    // 7) OnBDESetRange: il programma imposta l'intervallo, oppure lascia fare al driver
    if bNum then begin
      C2.OnBDESetRange := P.OnRange;
      if not Assigned(C2.OnBDESetRange) then
        raise Exception.Create('OnBDESetRange non registrato');
      P.Mode := 0;
      P.RangeMode := 1;
      P.RangeCalls := 0;
      bTab := RunBoth('select * from ' + SqlTab + ' where ' + KeyField + ' = :k order by ' + KeyField,
        FirstKey, True, 'setrange gestito');
      if bTab <> (P.RangeCalls = 1) then
        raise Exception.Create('setrange gestito: chiamate incoerenti con l''uso della TTable');
      if bTab and ((P.RangeCondCount <> 1) or (not SameText(P.RangeField, KeyField)) or (P.RangeOp <> '=')) then
        raise Exception.Create('setrange gestito: condizioni ricevute errate');
      Write('(setrange gestito: TTable ', BoolToStr(bTab, True), ') ');
      P.RangeMode := 0;
      P.RangeCalls := 0;
      bTab := RunBoth('select * from ' + SqlTab + ' where ' + KeyField + ' = :k order by ' + KeyField,
        FirstKey, True, 'setrange standard');
      if bTab <> (P.RangeCalls = 1) then
        raise Exception.Create('setrange standard: chiamate incoerenti con l''uso della TTable');
    end;

    // 8) WHERE su un campo testo: nessuna proposta e accettazione a False, quindi TQuery
    if TextField <> '' then begin
      QA.Open('select * from ' + SqlTab);
      sTxt := QA.FieldByName(TextField).AsString;
      QA.Close;
      P.Mode := 0;
      P.Calls := 0;
      P.RangeCalls := 0;
      bTab := RunBoth('select * from ' + SqlTab + ' where ' + TextField + ' = :t order by ' + TextField,
        sTxt, False, 'testo');
      if bTab or (P.RangeCalls <> 0) or (P.Calls <> 1) or P.LastAcceptIn or (P.LastProposed <> '') then
        raise Exception.Create('testo: l''evento doveva arrivare senza proposta e con accettazione False');
      Write('(testo: gestore chiamato senza proposta, TQuery) ');
    end;

    // 9) senza gestore: come prima (niente chiamate, nessuna TTable per desc / WHERE senza ORDER BY)
    C2.OnBDEIndexNeeded := nil;
    C2.OnBDESetRange := nil;
    P.Calls := 0;
    m0 := BDEStatTableCursorOpens;
    RunBoth('select * from ' + SqlTab + ' order by ' + KeyField + ' desc', Unassigned, True, 'desc senza gestore');
    if bNum then
      RunBoth('select * from ' + SqlTab + ' where ' + KeyField + ' = :k', FirstKey, False, 'where senza gestore');
    if (BDEStatTableCursorOpens <> m0) or (P.Calls <> 0) then
      raise Exception.Create('senza gestore: comportamento cambiato');
  finally
    P.Free;
    QB.Free;
    QA.Free;
    C2.Free;
  end;
end;

// Misura (non verifica): dove si potrebbe ancora guadagnare con TableCursor.
//  A) count(*): TQuery contro TTable.RecordCount (anche con un intervallo sulla chiave)
//  B) costo di Prepare: creare TTable + FieldDefs/IndexDefs, a mano e tramite il driver
//  C) master-detail: N aperture con parametro, TQuery contro driver con TableCursor contro
//     TTable BDE gia' aperta (solo SetRange) contro TTable chiusa e riaperta a ogni volta
procedure TestCostProbe;
const
  N = 300;
  SOME = 20;
var
  C2: TFDConnection;
  Q, QB: TFDQuery;
  T, T2: TTable;
  SW: TStopwatch;
  i, nQ, nT, nRows: Integer;
  msQ, msT, ms1, ms2, ms3, ms4, ms5, ms6: Int64;
  bNum: Boolean;

  function ReadSome(ADS: TDataSet): Integer;
  begin
    Result := 0;
    while (not ADS.Eof) and (Result < SOME) do begin
      Inc(Result);
      ADS.Next;
    end;
  end;

  procedure SetKeyRange(ATab: TTable; const AValue: Variant);
  begin
    ATab.SetRangeStart;
    ATab.FieldByName(KeyField).Value := AValue;
    ATab.SetRangeEnd;
    ATab.FieldByName(KeyField).Value := AValue;
    ATab.ApplyRange;
  end;

begin
  bNum := (not VarIsNull(FirstKey)) and (not VarIsEmpty(FirstKey)) and VarIsNumeric(FirstKey);
  C2 := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  QB := TFDQuery.Create(nil);
  T := TTable.Create(nil);
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    Q.Connection := Conn;
    QB.Connection := C2;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.IndexFieldNames := KeyField;

    // A) count(*) sull'intera tabella
    SW := TStopwatch.StartNew;
    Q.Open('select count(*) from ' + SqlTab);
    nQ := Q.Fields[0].AsInteger;
    Q.Close;
    msQ := SW.ElapsedMilliseconds;
    SW := TStopwatch.StartNew;
    T.Open;
    nT := T.RecordCount;
    msT := SW.ElapsedMilliseconds;
    Write('(count(*): TQuery ', msQ, ' ms = ', nQ, '; TTable.RecordCount ', msT, ' ms = ', nT,
      IfThen(nQ = nT, ', uguali', ', DIVERSI (record cancellati?)'), ') ');
    if bNum then begin
      // count(*) con intervallo sulla chiave (>=): TQuery contro SetRange + RecordCount
      SW := TStopwatch.StartNew;
      Q.Open('select count(*) from ' + SqlTab + ' where ' + KeyField + ' >= :k', [FirstKey]);
      nQ := Q.Fields[0].AsInteger;
      Q.Close;
      msQ := SW.ElapsedMilliseconds;
      SW := TStopwatch.StartNew;
      T.SetRangeStart;
      T.FieldByName(KeyField).Value := FirstKey;
      T.ApplyRange;
      nT := T.RecordCount;
      T.CancelRange;
      msT := SW.ElapsedMilliseconds;
      Write('(count(*) con ', KeyField, ' >= chiave: TQuery ', msQ, ' ms = ', nQ,
        '; TTable ', msT, ' ms = ', nT, IfThen(nQ = nT, ', uguali', ', DIVERSI'), ') ');
    end;
    T.Close;

    // B) costo di Prepare
    SW := TStopwatch.StartNew;
    for i := 1 to N do begin
      T2 := TTable.Create(nil);
      try
        T2.DatabaseName := Folder;
        T2.TableName := TabName;
        T2.ReadOnly := True;
        T2.FieldDefs.Update;
        T2.IndexDefs.Update;
      finally
        T2.Free;
      end;
    end;
    ms1 := SW.ElapsedMilliseconds;
    QB.SQL.Text := 'select * from ' + SqlTab + ' order by ' + KeyField;
    SW := TStopwatch.StartNew;
    for i := 1 to N do begin
      QB.Prepare;
      QB.Unprepare;
    end;
    ms2 := SW.ElapsedMilliseconds;
    Write('(', N, ' preparazioni: TTable+FieldDefs+IndexDefs a mano ', ms1, ' ms; Prepare del driver ',
      ms2, ' ms) ');

    // C) master-detail: N aperture con parametro
    if bNum then begin
      Q.SQL.Text := 'select * from ' + SqlTab + ' where ' + KeyField + ' = :k order by ' + KeyField;
      Q.Prepare;
      Q.Params[0].Value := FirstKey;
      SW := TStopwatch.StartNew;
      for i := 1 to N do begin
        Q.Open;
        ReadSome(Q);
        Q.Close;
      end;
      ms3 := SW.ElapsedMilliseconds;

      QB.SQL.Text := Q.SQL.Text;
      QB.Prepare;
      QB.Params[0].Value := FirstKey;
      SW := TStopwatch.StartNew;
      for i := 1 to N do begin
        QB.Open;
        ReadSome(QB);
        QB.Close;
      end;
      ms4 := SW.ElapsedMilliseconds;

      T.Open;
      SW := TStopwatch.StartNew;
      for i := 1 to N do begin
        SetKeyRange(T, FirstKey);
        T.First;
        nRows := ReadSome(T);
      end;
      ms5 := SW.ElapsedMilliseconds;
      T.Close;

      SW := TStopwatch.StartNew;
      for i := 1 to N do begin
        T.Close;
        T.Open;
        SetKeyRange(T, FirstKey);
        T.First;
        nRows := ReadSome(T);
      end;
      ms6 := SW.ElapsedMilliseconds;
      T.Close;
      Write('(', N, ' aperture con parametro, prime ', SOME, ' righe (', nRows, ' lette): TQuery ', ms3,
        ' ms; driver con TableCursor ', ms4, ' ms; TTable gia'' aperta + SetRange ', ms5,
        ' ms; TTable chiusa e riaperta ', ms6, ' ms) ');
    end;
  finally
    T.Free;
    QB.Free;
    Q.Free;
    C2.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Visibilita' delle modifiche tra processi. BDETest avvia una copia di se stesso come
// "scrittore" (--writer <file comandi>): aggiorna un valore, segnala di aver finito e resta
// CONNESSO finche' il lettore non ha guardato; poi ripristina il valore e termina.
// Lo scrittore usa sempre il driver; con flush=1 chiama anche DbiSaveChanges.
function VisPath(const AName: String): String;
begin
  Result := TPath.Combine(TPath.GetTempPath, AName);
end;

procedure RunWriter(const ACmdFile: String);
var
  L: TStringList;
  C: TFDConnection;
  T: TTable;
  sFolder, sTab, sSqlTab, sText, sKeyF, sNew, sOrig, sFlush: String;
  vKey: Double;
  i: Integer;
  bChanged: Boolean;
begin
  L := TStringList.Create;
  C := TFDConnection.Create(nil);
  bChanged := False;
  sSqlTab := '';
  sText := '';
  sKeyF := '';
  sOrig := '';
  vKey := 0;
  try
    try
      L.LoadFromFile(ACmdFile, TEncoding.UTF8);
      sFolder := L[0];
      sTab := L[1];
      sSqlTab := L[2];
      sText := L[3];
      sKeyF := L[4];
      vKey := StrToFloat(L[5], TFormatSettings.Invariant);
      sNew := L[6];
      sOrig := L[7];
      sFlush := L[8];
      C.DriverName := 'BDE';
      C.LoginPrompt := False;
      C.Params.Database := sFolder;
      C.Open;
      bChanged := True;
      C.ExecSQL('update ' + sSqlTab + ' set ' + sText + ' = :v where ' + sKeyF + ' = :k',
        [sNew, vKey]);
      if sFlush = '1' then begin
        T := TTable.Create(nil);
        try
          T.DatabaseName := TDatabase(C.CliObj).DatabaseName;
          T.SessionName := TDatabase(C.CliObj).SessionName;
          T.TableName := sTab;
          T.Open;
          Check(DbiSaveChanges(T.Handle));
          T.Close;
        finally
          T.Free;
        end;
      end;
      TFile.WriteAllText(VisPath('fdbde_vis_done.txt'), 'ok');
      for i := 1 to 1200 do
        if TFile.Exists(VisPath('fdbde_vis_stop.txt')) then
          Break
        else
          Sleep(50);
    except
      on E: Exception do
        TFile.WriteAllText(VisPath('fdbde_vis_error.txt'), E.Message);
    end;
  finally
    if bChanged then
      try
        C.ExecSQL('update ' + sSqlTab + ' set ' + sText + ' = :v where ' + sKeyF + ' = :k',
          [sOrig, vKey]);
      except
      end;
    C.Free;
    L.Free;
  end;
end;

procedure TestVisibility;
var
  RC, R2: TFDConnection;
  QR, QX, QT: TFDQuery;
  sSql, sOrig, sNew, sSame, sRef, sNewQ, sNewC, sTQ: String;
  vKey: Double;
  L: TStringList;
  SI: TStartupInfo;
  PI: TProcessInformation;
  sCmd: String;
  fl, i: Integer;
  bUp: Boolean;

  function First(AQ: TFDQuery): String;
  begin
    if AQ.Eof then
      Result := '(nessuna riga)'
    else
      Result := AQ.FieldByName(TextField).AsString;
  end;

  function Sees(const AValue: String): String;
  begin
    if Trim(AValue) = Trim(sNew) then
      Result := 'VEDE'
    else if Trim(AValue) = Trim(sOrig) then
      Result := 'non vede'
    else
      Result := 'valore inatteso "' + AValue + '"';
  end;

begin
  if not ((not VarIsNull(FirstKey)) and (not VarIsEmpty(FirstKey)) and VarIsNumeric(FirstKey)) then begin
    Write('(saltato: serve una chiave numerica) ');
    Exit;
  end;
  vKey := FirstKey;
  sSql := 'select * from ' + SqlTab + ' where ' + KeyField + ' = :k order by ' + KeyField;
  RC := TFDConnection.Create(nil);
  R2 := TFDConnection.Create(nil);
  QR := TFDQuery.Create(nil);
  QX := TFDQuery.Create(nil);
  QT := TFDQuery.Create(nil);
  L := TStringList.Create;
  try
    RC.DriverName := 'BDE';
    RC.LoginPrompt := False;
    RC.Params.Database := Folder;
    RC.Params.Values['TableCursor'] := 'True';
    RC.Open;
    QR.Connection := RC;
    QX.Connection := RC;
    QT.Connection := Conn;
    for fl := 0 to 1 do begin
      System.SysUtils.DeleteFile(VisPath('fdbde_vis_done.txt'));
      System.SysUtils.DeleteFile(VisPath('fdbde_vis_stop.txt'));
      System.SysUtils.DeleteFile(VisPath('fdbde_vis_error.txt'));
      QR.Close;
      QR.Open(sSql, [vKey]);
      sOrig := First(QR);
      if Length(Trim(sOrig)) > 0 then begin
        if sOrig[1] = '#' then
          sNew := '$' + Copy(sOrig, 2, Length(sOrig))
        else
          sNew := '#' + Copy(sOrig, 2, Length(sOrig));
      end
      else
        sNew := '#';
      L.Clear;
      L.Add(Folder);
      L.Add(TabName);
      L.Add(SqlTab);
      L.Add(TextField);
      L.Add(KeyField);
      L.Add(FloatToStr(vKey, TFormatSettings.Invariant));
      L.Add(sNew);
      L.Add(sOrig);
      L.Add(IntToStr(fl));
      L.SaveToFile(VisPath('fdbde_vis_cmd.txt'), TEncoding.UTF8);
      FillChar(SI, SizeOf(SI), 0);
      SI.cb := SizeOf(SI);
      sCmd := '"' + ParamStr(0) + '" --writer "' + VisPath('fdbde_vis_cmd.txt') + '"';
      UniqueString(sCmd);
      if not CreateProcess(nil, PChar(sCmd), nil, nil, False, 0, nil, nil, SI, PI) then
        RaiseLastOSError;
      try
        // attesa che lo scrittore abbia aggiornato (restando connesso)
        bUp := False;
        for i := 1 to 300 do begin
          if TFile.Exists(VisPath('fdbde_vis_done.txt')) then begin
            bUp := True;
            Break;
          end;
          if TFile.Exists(VisPath('fdbde_vis_error.txt')) or
             (WaitForSingleObject(PI.hProcess, 100) = WAIT_OBJECT_0) then
            Break;
        end;
        if not bUp then begin
          if TFile.Exists(VisPath('fdbde_vis_error.txt')) then
            raise Exception.Create('scrittore: ' + TFile.ReadAllText(VisPath('fdbde_vis_error.txt')))
          else
            raise Exception.Create('lo scrittore non ha completato l''aggiornamento');
        end;
        // il lettore guarda, con lo scrittore ancora connesso
        sSame := First(QR);                       // stessa query, senza fare nulla
        QR.Refresh;
        sRef := First(QR);                        // stessa query dopo Refresh
        QX.Close;
        QX.Open(sSql, [vKey]);
        sNewQ := First(QX);                       // query nuova, stessa connessione
        QX.Close;
        R2.DriverName := 'BDE';
        R2.LoginPrompt := False;
        R2.Params.Database := Folder;
        R2.Params.Values['TableCursor'] := 'True';
        R2.Open;
        QX.Connection := R2;
        QX.Open(sSql, [vKey]);
        sNewC := First(QX);                       // connessione nuova
        QX.Close;
        R2.Close;
        QX.Connection := RC;
        QT.Open(sSql, [vKey]);
        sTQ := First(QT);                         // TQuery (senza TableCursor)
        QT.Close;
        Write('(scrittore ', IfThen(fl = 0, 'senza flush', 'con DbiSaveChanges'), ', ancora connesso: ',
          'stessa query aperta ', Sees(sSame), '; dopo Refresh ', Sees(sRef),
          '; query nuova ', Sees(sNewQ), '; connessione nuova ', Sees(sNewC),
          '; TQuery ', Sees(sTQ), ') ');
      finally
        TFile.WriteAllText(VisPath('fdbde_vis_stop.txt'), 'stop');
        WaitForSingleObject(PI.hProcess, 30000);
        CloseHandle(PI.hProcess);
        CloseHandle(PI.hThread);
      end;
      // controllo del ripristino del valore originale
      QT.Open(sSql, [vKey]);
      try
        if Trim(First(QT)) <> Trim(sOrig) then begin
          Conn.ExecSQL('update ' + SqlTab + ' set ' + TextField + ' = :v where ' + KeyField + ' = :k',
            [sOrig, vKey]);
          raise Exception.Create('il valore non e'' stato ripristinato dallo scrittore (ripristinato dal test)');
        end;
      finally
        QT.Close;
      end;
    end;
  finally
    L.Free;
    QT.Free;
    QX.Free;
    QR.Free;
    R2.Free;
    RC.Free;
  end;
end;

// FetchOptions.RecsMax / RecsSkip (limite e paginazione): il Local SQL non ha TOP/LIMIT,
// quindi il limite deve essere applicato da FireDAC lato client.
// Se l'apertura fallisce stampa il testo SQL arrivato al BDE.
procedure TestRecsMax;
const
  C_Max = 50;
var
  C2: TFDConnection;
  Q: TFDQuery;
  n: Integer;
  k0, k1, k2: Variant;
  SW: TStopwatch;
  bOk: Boolean;

  procedure Try1(AConn: TFDConnection; const ALabel, ASQL: String);
  var
    ms: Int64;
  begin
    Q.Close;
    Q.Connection := AConn;
    Q.FetchOptions.RecsMax := C_Max;
    BDEStatLastSQL := '';
    try
      SW := TStopwatch.StartNew;
      Q.Open(ASQL);
      n := 0;
      while not Q.Eof do begin
        Inc(n);
        Q.Next;
      end;
      ms := SW.ElapsedMilliseconds;
      Q.Close;
      Write('(', ALabel, ': RecsMax=', C_Max, ' -> ', n, ' righe in ', ms, ' ms) ');
      if n <> C_Max then
        bOk := False;
    except
      on E: Exception do begin
        bOk := False;
        Write('(', ALabel, ': RecsMax=', C_Max, ' NON funziona: ', Copy(E.Message, 1, 70),
          ' | SQL inviato al BDE: ', BDEStatLastSQL, ') ');
      end;
    end;
    Q.FetchOptions.RecsMax := -1;
  end;

  procedure CheckSkip(AConn: TFDConnection; const ALabel, ASQL: String);
  begin
    Q.Close;
    Q.Connection := AConn;
    Q.FetchOptions.RecsMax := 5;   // bastano poche righe: non si legge l'intera tabella
    Q.FetchOptions.RecsSkip := -1;
    Q.Open(ASQL);
    k0 := Q.Fields[0].Value;
    Q.Next;
    k1 := Q.Fields[0].Value;
    Q.Next;
    k2 := Q.Fields[0].Value;
    Q.Close;
    Q.FetchOptions.RecsSkip := 2;
    try
      Q.Open(ASQL);
      if Q.Eof or (Q.Fields[0].Value <> k2) then begin
        bOk := False;
        Write('(RecsSkip=2 ', ALabel, ': prima riga diversa dalla terza della lettura normale) ');
      end
      else
        Write('(RecsSkip=2 ', ALabel, ': ok) ');
    except
      on E: Exception do begin
        bOk := False;
        Write('(RecsSkip=2 ', ALabel, ' NON funziona: ', Copy(E.Message, 1, 70), ') ');
      end;
    end;
    Q.Close;
    Q.FetchOptions.RecsSkip := -1;
    Q.FetchOptions.RecsMax := -1;
  end;

begin
  bOk := True;
  C2 := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    Try1(Conn, 'TQuery', 'select * from ' + SqlTab);
    Try1(C2, 'TableCursor', 'select * from ' + SqlTab);
    if KeyField <> '' then
      Try1(C2, 'TableCursor con order by', 'select * from ' + SqlTab + ' order by ' + KeyField);
    // RecsSkip: la prima riga dopo lo skip e' la terza riga della lettura normale
    // (il driver salta da solo col cursore: se FireDAC saltasse di nuovo si arriverebbe alla quinta)
    CheckSkip(Conn, 'TQuery', 'select * from ' + SqlTab);
    CheckSkip(C2, 'TableCursor', 'select * from ' + SqlTab);
    if KeyField <> '' then
      CheckSkip(C2, 'TableCursor con order by', 'select * from ' + SqlTab + ' order by ' + KeyField);
    // skip oltre la fine: nessuna riga e nessun errore
    Q.Connection := C2;
    Q.FetchOptions.RecsMax := -1;
    Q.FetchOptions.RecsSkip := MaxInt div 2;
    try
      Q.Open('select * from ' + SqlTab);
      Write('(RecsSkip oltre la fine: ', Q.RecordCount, ' righe) ');
      if Q.RecordCount <> 0 then
        bOk := False;
    except
      on E: Exception do begin
        bOk := False;
        Write('(RecsSkip oltre la fine NON funziona: ', Copy(E.Message, 1, 70), ') ');
      end;
    end;
    Q.Close;
    Q.FetchOptions.RecsSkip := -1;
    if not bOk then
      raise Exception.Create('RecsMax / RecsSkip non applicati correttamente');
  finally
    Q.Free;
    C2.Free;
  end;
end;

// Misura (non verifica): TTable.Filter del BDE contro il WHERE del TQuery.
//  A) condizione selettiva sul campo testo, senza indice: righe e tempi
//  B) intervallo sulla chiave (SetRange) + filtro sul testo
//  C) condizione poco selettiva: tempo per avere le prime righe (apertura + 50 righe)
procedure TestFilterProbe;
const
  FIRST_ROWS = 50;
var
  Q: TFDQuery;
  T: TTable;
  SW: TStopwatch;
  sTxt, sFlt: String;
  vKey: Double;
  nQ, nT, n: Integer;
  msQ, msT: Int64;

  function Lit(const AValue: String): String;
  begin
    Result := '''' + StringReplace(AValue, '''', '''''', [rfReplaceAll]) + '''';
  end;

begin
  if not ((not VarIsNull(FirstKey)) and (not VarIsEmpty(FirstKey)) and VarIsNumeric(FirstKey)) then begin
    Write('(saltato: serve una chiave numerica) ');
    Exit;
  end;
  vKey := FirstKey;
  Q := TFDQuery.Create(nil);
  T := TTable.Create(nil);
  try
    Q.Connection := Conn;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    // un valore di testo non vuoto preso dalle prime righe
    sTxt := '';
    Q.FetchOptions.Mode := fmOnDemand;
    Q.Open('select * from ' + SqlTab);
    n := 0;
    while (not Q.Eof) and (sTxt = '') and (n < 200) do begin
      sTxt := Trim(Q.FieldByName(TextField).AsString);
      Inc(n);
      Q.Next;
    end;
    Q.Close;
    Q.FetchOptions.Mode := fmAll;
    if sTxt = '' then begin
      Write('(saltato: nessun valore di testo non vuoto nelle prime righe) ');
      Exit;
    end;
    sFlt := TextField + ' = ' + Lit(sTxt);

    // A) condizione selettiva sul testo, senza indice
    SW := TStopwatch.StartNew;
    Q.Open('select * from ' + SqlTab + ' where ' + TextField + ' = :t', [sTxt]);
    nQ := 0;
    while not Q.Eof do begin Inc(nQ); Q.Next; end;
    Q.Close;
    msQ := SW.ElapsedMilliseconds;
    T.Filter := sFlt;
    T.Filtered := True;
    SW := TStopwatch.StartNew;
    T.Open;
    nT := 0;
    while not T.Eof do begin Inc(nT); T.Next; end;
    T.Close;
    msT := SW.ElapsedMilliseconds;
    Write('(A: ', TextField, ' = "', sTxt, '": TQuery ', msQ, ' ms = ', nQ, ' righe; TTable.Filter ',
      msT, ' ms = ', nT, ' righe', IfThen(nQ = nT, ', uguali', ', DIVERSE'), ') ');

    // B) SetRange sulla chiave + filtro sul testo
    SW := TStopwatch.StartNew;
    Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' >= :k and ' + TextField + ' = :t',
      [vKey, sTxt]);
    nQ := 0;
    while not Q.Eof do begin Inc(nQ); Q.Next; end;
    Q.Close;
    msQ := SW.ElapsedMilliseconds;
    T.IndexFieldNames := KeyField;
    T.Filter := sFlt;
    T.Filtered := True;
    SW := TStopwatch.StartNew;
    T.Open;
    T.SetRangeStart;
    T.FieldByName(KeyField).Value := vKey;
    T.ApplyRange;
    nT := 0;
    while not T.Eof do begin Inc(nT); T.Next; end;
    T.Close;
    msT := SW.ElapsedMilliseconds;
    Write('(B: ', KeyField, ' >= chiave e ', TextField, ' = ...: TQuery ', msQ, ' ms = ', nQ,
      ' righe; SetRange + Filter ', msT, ' ms = ', nT, ' righe', IfThen(nQ = nT, ', uguali', ', DIVERSE'), ') ');

    // C) condizione poco selettiva: tempo fino alle prime righe
    T.IndexFieldNames := '';
    T.Filter := TextField + ' <> ' + Lit(sTxt);
    T.Filtered := True;
    Q.FetchOptions.Mode := fmOnDemand;
    SW := TStopwatch.StartNew;
    Q.Open('select * from ' + SqlTab + ' where ' + TextField + ' <> :t', [sTxt]);
    n := 0;
    while (not Q.Eof) and (n < FIRST_ROWS) do begin Inc(n); Q.Next; end;
    Q.Close;
    msQ := SW.ElapsedMilliseconds;
    Q.FetchOptions.Mode := fmAll;
    SW := TStopwatch.StartNew;
    T.Open;
    nT := 0;
    while (not T.Eof) and (nT < FIRST_ROWS) do begin Inc(nT); T.Next; end;
    T.Close;
    msT := SW.ElapsedMilliseconds;
    Write('(C: prime ', FIRST_ROWS, ' righe di ', TextField, ' <> "', sTxt, '": TQuery (fmOnDemand) ', msQ,
      ' ms (', n, ' righe); TTable.Filter ', msT, ' ms (', nT, ' righe)) ');
  finally
    T.Free;
    Q.Free;
  end;
end;

// BDEFindIndex / BDEIndexServesOrder su indici costruiti a mano (non usa la tabella):
// uguaglianze in qualunque ordine, intervallo dopo le uguaglianze, ORDER BY con uguaglianze
// in testa, permutazioni di un elenco di campi, indici scartati (espressione, maiuscole
// indifferenti, verso diverso).
procedure TestFindIndex;
var
  D: TIndexDefs;
  M: TBDEIndexMatch;
  nBad: Integer;
  sBad: String;

  procedure Chk(const ALabel: String; AFound: Boolean; const AExp: String;
    ALevel: TBDEIndexLevel);
  begin
    if (AExp = '') and not AFound then
      Exit;
    if AFound and (AExp <> '') and (M.IndexName = AExp) and (M.Level = ALevel) then
      Exit;
    Inc(nBad);
    sBad := sBad + ' [' + ALabel + ': atteso "' + AExp + '", ' +
      IfThen(AFound, 'trovato "' + M.IndexName + '" livello ' + IntToStr(Ord(M.Level)), 'nessuno') + ']';
  end;

begin
  nBad := 0;
  sBad := '';
  D := TIndexDefs.Create(nil);
  try
    D.Add('IX_BA', 'B;A', []);
    D.Add('IX_AB', 'A;B', []);
    D.Add('IX_CAB', 'C;A;B', []);
    D.Add('IX_DESC', 'A;B', [ixDescending]);
    D.Add('IX_EXPR', 'UPPER(A)', [ixExpression]);
    D.Add('IX_CI', 'D', [ixCaseInsensitive]);
    D.Add('IX_D', 'D', []);
    // indici espressione dBase come li riporta il BDE: Fields vuoto, testo in Expression
    with D.AddIndexDef do begin
      Name := 'IX_EFG';
      Options := [ixExpression];
      Expression := 'E+F+G';
    end;
    with D.AddIndexDef do begin
      Name := 'IX_FUNC';
      Options := [ixExpression];
      Expression := 'STR(H,5)+I';
    end;

    // A=1 AND B>5: serve (A,B); (B,A) viene prima ma non va bene per il SetRange
    Chk('A=, B>', BDEFindIndex(D, ['A'], ['B'], [], False, M), 'IX_AB', ilFull);
    // A=1 AND B=2: l'ordine dei campi non conta, vale il primo indice
    Chk('A=, B=', BDEFindIndex(D, ['A', 'B'], [], [], False, M), 'IX_BA', ilFull);
    Chk('B=, A=', BDEFindIndex(D, ['B', 'A'], [], [], False, M), 'IX_BA', ilFull);
    // ORDER BY A, B
    Chk('order A,B', BDEFindIndex(D, [], [], ['A', 'B'], False, M), 'IX_AB', ilFull);
    // ORDER BY A, B WHERE C = 1: uguaglianza su un campo fuori dall'ORDER BY, in testa
    Chk('order A,B, C=', BDEFindIndex(D, ['C'], [], ['A', 'B'], False, M), 'IX_CAB', ilFull);
    // ORDER BY A WHERE B > 5: l'ordinamento e' servito da (A,B), ma non l'intervallo
    Chk('order A, B>', BDEFindIndex(D, [], ['B'], ['A'], False, M), 'IX_AB', ilCovers);
    // ORDER BY A, B WHERE A = 1 (campo uguale e anche nell'ORDER BY)
    Chk('order A,B, A=', BDEFindIndex(D, ['A'], [], ['A', 'B'], False, M), 'IX_AB', ilFull);
    // verso discendente: solo l'indice discendente
    Chk('desc A=', BDEFindIndex(D, ['A'], [], [], True, M), 'IX_DESC', ilFull);
    // indici espressione e maiuscole indifferenti scartati; D e' sull'indice normale
    Chk('D=', BDEFindIndex(D, ['D'], [], [], False, M), 'IX_D', ilFull);
    Chk('espressione', BDEFindIndex(D, ['UPPER(A)'], [], [], False, M), '', ilNone);
    // A = 1 AND A > 0, oppure due campi con intervallo: niente ilFull
    Chk('A= e A>', BDEFindIndex(D, ['A'], ['A'], [], False, M), 'IX_AB', ilCovers);
    Chk('due intervalli', BDEFindIndex(D, [], ['A', 'B'], [], False, M), 'IX_BA', ilCovers);
    // richiesta vuota
    Chk('vuota', BDEFindIndex(D, [], [], [], False, M), '', ilNone);
    // solo un elenco di campi: tutte le permutazioni, oppure nello stesso ordine
    Chk('elenco B,A qualunque', BDEFindIndex(D, ['B', 'A'], False, True, M), 'IX_BA', ilFull);
    Chk('elenco A,B qualunque', BDEFindIndex(D, ['A', 'B'], False, True, M), 'IX_BA', ilFull);
    Chk('elenco A,B ordinato', BDEFindIndex(D, ['A', 'B'], False, False, M), 'IX_AB', ilFull);
    Chk('elenco B,A ordinato', BDEFindIndex(D, ['B', 'A'], False, False, M), 'IX_BA', ilFull);
    Chk('elenco C,B qualunque', BDEFindIndex(D, ['C', 'B'], False, True, M), '', ilNone);
    // indici espressione fatti di soli campi (E+F+G): solo se richiesti (AExpressions) e senza ORDER BY
    Chk('expr non richiesti', BDEFindIndex(D, ['E'], [], [], False, False, M), '', ilNone);
    Chk('expr E=', BDEFindIndex(D, ['E'], [], [], False, True, M), 'IX_EFG', ilFull);
    if not M.IsExpression then begin
      Inc(nBad);
      sBad := sBad + ' [expr E=: IsExpression atteso True]';
    end;
    Chk('expr F= (non e'' il primo campo)', BDEFindIndex(D, ['F'], [], [], False, True, M), '', ilNone);
    Chk('expr G,F,E= qualunque ordine', BDEFindIndex(D, ['G', 'F', 'E'], [], [], False, True, M),
      'IX_EFG', ilFull);
    Chk('expr E=, F>', BDEFindIndex(D, ['E'], ['F'], [], False, True, M), 'IX_EFG', ilFull);
    // con ORDER BY l'indice espressione non si propone (nessun indice semplice serve ORDER BY F)
    Chk('expr con ORDER BY', BDEFindIndex(D, [], ['F'], ['F'], False, True, M), '', ilNone);
    Chk('expr con funzione (STR)', BDEFindIndex(D, ['H'], [], [], False, True, M), '', ilNone);
    Chk('expr discendente', BDEFindIndex(D, ['E'], [], [], True, True, M), '', ilNone);
    // un indice semplice ilFull vince sull'espressione
    Chk('expr: vince il semplice', BDEFindIndex(D, ['A', 'B'], [], [], False, True, M), 'IX_BA', ilFull);
    if M.IsExpression then begin
      Inc(nBad);
      sBad := sBad + ' [expr: indice semplice con IsExpression True]';
    end;
    if Length(BDEExpressionFields(D[7])) <> 3 then begin
      Inc(nBad);
      sBad := sBad + ' [BDEExpressionFields(E+F+G): attesi 3 campi]';
    end;
    if Length(BDEExpressionFields(D[8])) <> 0 then begin
      Inc(nBad);
      sBad := sBad + ' [BDEExpressionFields(STR(H,5)+I): atteso nessun campo]';
    end;
    // BDEIndexServesOrder: con C costante si salta C in testa all'indice (C,A,B)
    if not BDEIndexServesOrder(D[2], ['C'], ['A', 'B']) then begin
      Inc(nBad);
      sBad := sBad + ' [serves C=, order A,B: atteso True]';
    end;
    if BDEIndexServesOrder(D[2], ['C'], ['B']) then begin
      Inc(nBad);
      sBad := sBad + ' [serves C=, order B: atteso False]';
    end;
    if BDEIndexServesOrder(D[4], [], ['A']) then begin
      Inc(nBad);
      sBad := sBad + ' [serves indice espressione: atteso False]';
    end;
  finally
    D.Free;
  end;
  Write('(', 34, ' controlli) ');
  if nBad > 0 then
    raise Exception.Create(IntToStr(nBad) + ' controlli falliti:' + sBad);
end;

// Misura (sola lettura): indici ESPRESSIONE dBase fatti di campi uniti da '+' (per esempio
// ANNO+TIPODOC+NUMDOC) usati con una TTable. Per ogni indice scomponibile in campi prova,
// con prefissi di 1..N campi presi da una riga campione:
//  1) SetRange campo per campo (come fa il driver con gli indici a campi semplici)
//  2) SetRange([chiave]) con la chiave concatenata (campi di testo riempiti a spazi)
//  3) FindNearest([chiave])
// e confronta le righe con un count(*) del TQuery con le stesse uguaglianze.
procedure TestExprIndexProbe;
const
  C_MaxCount = 200000;
var
  T: TTable;
  Q: TFDQuery;
  i, j, n: Integer;
  oDef: TIndexDef;
  sExpr, sKey: String;
  aParts, aVal, aSql, aKey: TArray<String>;
  aKeyOk: TArray<Boolean>;
  bDecomp, bAllStr: Boolean;
  eT: TFieldType;
  iSize, iRef, nExpr, nTot: Integer;

  function OptText(AOpts: TIndexOptions): String;
  begin
    Result := '';
    if ixPrimary in AOpts then Result := Result + ' primary';
    if ixUnique in AOpts then Result := Result + ' unique';
    if ixDescending in AOpts then Result := Result + ' desc';
    if ixExpression in AOpts then Result := Result + ' expression';
    if ixCaseInsensitive in AOpts then Result := Result + ' nocase';
  end;

  function IsTextType(AType: TFieldType): Boolean;
  begin
    Result := AType in [ftString, ftFixedChar, ftWideString, ftFixedWideChar];
  end;

  function IsNumType(AType: TFieldType): Boolean;
  begin
    Result := AType in [ftSmallint, ftInteger, ftWord, ftFloat, ftCurrency, ftBCD, ftAutoInc,
      ftLargeint];
  end;

  // righe del TQuery con le uguaglianze sui primi AJ campi; -1 se non calcolabile
  function RefCount(AJ: Integer): Integer;
  var
    m: Integer;
    sW: String;
  begin
    Result := -1;
    sW := '';
    for m := 0 to AJ - 1 do begin
      if aSql[m] = '' then
        Exit;
      if sW <> '' then
        sW := sW + ' and ';
      sW := sW + aParts[m] + ' = ' + aSql[m];
    end;
    try
      Q.Close;
      Q.Open('select count(*) from ' + SqlTab + ' where ' + sW);
      Result := Q.Fields[0].AsInteger;
      Q.Close;
    except
      Result := -1;
    end;
  end;

  // AKind 0: nessun intervallo (solo apertura sull'indice e lettura); 1: SetRange campo per campo; 2: SetRange([chiave unica]); 3: FindNearest([chiave unica])
  // Ogni tentativo usa una TTable nuova e dice in quale passaggio e' avvenuto un errore.
  function Attempt(const AIndex: String; AKind, AJ, AExpected: Integer; ASwitch: Boolean): String;
  var
    Tx: TTable;
    n2, m: Integer;
    SW: TStopwatch;
    bSame: Boolean;
    sStage: String;
  begin
    sStage := 'creazione';
    Tx := TTable.Create(nil);
    try
      try
        Tx.DatabaseName := Folder;
        Tx.TableName := TabName;
        Tx.ReadOnly := True;
        if ASwitch then begin
          // prima si apre in ordine naturale, poi si passa all'indice a tabella aperta
          sStage := 'Open';
          Tx.Open;
          sStage := 'IndexName (a tabella aperta)';
          Tx.IndexName := AIndex;
        end
        else begin
          sStage := 'IndexName (a tabella chiusa)';
          Tx.IndexName := AIndex;
          sStage := 'Open';
          Tx.Open;
        end;
        sStage := 'intervallo';
        SW := TStopwatch.StartNew;
        case AKind of
        0:
          ;
        1:
          begin
            Tx.SetRangeStart;
            for m := 0 to AJ - 1 do
              Tx.FieldByName(aParts[m]).AsString := aVal[m];
            Tx.KeyFieldCount := AJ;
            Tx.SetRangeEnd;
            for m := 0 to AJ - 1 do
              Tx.FieldByName(aParts[m]).AsString := aVal[m];
            Tx.KeyFieldCount := AJ;
            sStage := 'ApplyRange';
            Tx.ApplyRange;
          end;
        2:
          Tx.SetRange([aKey[AJ - 1]], [aKey[AJ - 1]]);
        3:
          begin
            Tx.FindNearest([aKey[AJ - 1]]);
            bSame := not Tx.Eof;
            for m := 0 to AJ - 1 do
              if bSame and not SameText(TrimRight(Tx.FieldByName(aParts[m]).AsString), aVal[m]) then
                bSame := False;
            Result := 'riga ' + IfThen(bSame, 'con il prefisso atteso', 'con prefisso DIVERSO') +
              ' (' + IntToStr(SW.ElapsedMilliseconds) + ' ms)';
            Exit;
          end;
        end;
        sStage := 'lettura';
        n2 := 0;
        while (not Tx.Eof) and (n2 < C_MaxCount) do begin
          Inc(n2);
          Tx.Next;
        end;
        Result := IntToStr(n2) + ' righe in ' + IntToStr(SW.ElapsedMilliseconds) + ' ms';
        if AExpected >= 0 then
          Result := Result + IfThen(n2 = AExpected, ' = TQuery', ' DIVERSO dal TQuery (' +
            IntToStr(AExpected) + ')');
      except
        on E: Exception do
          Result := 'ERRORE in ' + sStage + ': ' + E.ClassName + ': ' + E.Message;
      end;
    finally
      Tx.Free;
    end;
  end;

  // ATTENZIONE: T.Open / T.Close ricostruiscono T.IndexDefs e liberano i TIndexDef esistenti,
  // quindi ADef va letto tutto all'inizio (nome ed espressione copiati in variabili locali).
  procedure ProbeOne(ADef: TIndexDef);
  var
    j2, m: Integer;
    sR0, sR0b, sName: String;
    bSw: Boolean;
  begin
    sName := ADef.Name;
    sExpr := Trim(ADef.Expression);
    if sExpr = '' then
      sExpr := Trim(ADef.Fields);
    aParts := sExpr.Split(['+']);
    bDecomp := Length(aParts) > 0;
    for m := 0 to High(aParts) do begin
      aParts[m] := Trim(aParts[m]);
      if T.FieldDefs.IndexOf(aParts[m]) < 0 then
        bDecomp := False;
    end;
    Writeln('    indice ', sName, ' = ', sExpr);
    if not bDecomp then begin
      Writeln('        non scomponibile in campi uniti da +');
      Exit;
    end;
    n := Length(aParts);
    for m := 0 to n - 1 do
      Writeln('        ', aParts[m], ': ', FieldTypeNames[T.FieldDefs[T.FieldDefs.IndexOf(aParts[m])].DataType],
        ', larghezza ', T.FieldDefs[T.FieldDefs.IndexOf(aParts[m])].Size);
    // riga campione: a meta' della tabella, in ordine naturale
    T.Close;
    T.IndexName := '';
    T.Open;
    T.MoveBy(T.RecordCount div 2);
    SetLength(aVal, n);
    SetLength(aSql, n);
    SetLength(aKey, n);
    SetLength(aKeyOk, n);
    bAllStr := True;
    sKey := '';
    for m := 0 to n - 1 do begin
      eT := T.FieldDefs[T.FieldDefs.IndexOf(aParts[m])].DataType;
      iSize := T.FieldDefs[T.FieldDefs.IndexOf(aParts[m])].Size;
      aVal[m] := TrimRight(T.FieldByName(aParts[m]).AsString);   // gli spazi iniziali contano
      if IsTextType(eT) then begin
        aSql[m] := '''' + StringReplace(aVal[m], '''', '''''', [rfReplaceAll]) + '''';
        sKey := sKey + aVal[m];
        if iSize > Length(aVal[m]) then
          sKey := sKey + StringOfChar(' ', iSize - Length(aVal[m]));
      end
      else begin
        bAllStr := False;
        if IsNumType(eT) then
          aSql[m] := FloatToStr(T.FieldByName(aParts[m]).AsFloat, TFormatSettings.Invariant)
        else
          aSql[m] := '';
      end;
      aKey[m] := sKey;
      aKeyOk[m] := bAllStr;
      Writeln('        riga campione ', aParts[m], ' = "', aVal[m], '" (', Length(aVal[m]), ' caratteri)');
    end;
    T.Close;
    for j2 := 1 to n do begin
      iRef := RefCount(j2);
      Writeln('        prefisso di ', j2, ' campi: TQuery ', iRef, ' righe');
      if j2 = 1 then begin
        sR0 := Attempt(sName, 0, 0, -1, False);
        Writeln('            0a) IndexName e poi Open    : ', sR0);
        sR0b := Attempt(sName, 0, 0, -1, True);
        Writeln('            0b) Open e poi IndexName    : ', sR0b);
        bSw := Pos('ERRORE', sR0) = 1;
        if bSw and (Pos('ERRORE', sR0b) = 1) then begin
          Writeln('        l''indice non e'' utilizzabile con la TTable: salto i tentativi');
          Exit;
        end;
      end;
      Writeln('            1) SetRange campo per campo : ', Attempt(sName, 1, j2, iRef, bSw));
      if aKeyOk[j2 - 1] then begin
        Writeln('            2) SetRange([chiave unica]) : ', Attempt(sName, 2, j2, iRef, bSw));
        Writeln('            3) FindNearest([chiave])    : ', Attempt(sName, 3, j2, iRef, bSw));
      end
      else
        Writeln('            2) e 3) saltati: un campo non e'' di testo');
    end;
  end;

begin
  T := TTable.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.FieldDefs.Update;
    T.IndexDefs.Update;
    Writeln;
    nExpr := 0;
    nTot := T.IndexDefs.Count;
    for i := 0 to nTot - 1 do begin
      oDef := T.IndexDefs[i];
      Writeln('    ', IfThen(oDef.Name = '', '(primary)', oDef.Name), ': campi "', oDef.Fields,
        '" espressione "', oDef.Expression, '"', OptText(oDef.Options));
      if ixExpression in oDef.Options then
        Inc(nExpr);
    end;
    if nExpr = 0 then
      Write('(nessun indice espressione) ')
    else
      for j := 0 to nTot - 1 do begin
        T.IndexDefs.Update;     // ProbeOne apre e chiude T: gli IndexDefs vanno riletti
        if ixExpression in T.IndexDefs[j].Options then
          ProbeOne(T.IndexDefs[j]);
      end;
  finally
    Q.Free;
    T.Free;
  end;
end;

type
  // gestori di prova per un indice espressione di campi di testo (ANNO+TIPODOC+NUMDOC):
  // OnBDEIndexNeeded registra la proposta del driver, OnBDESetRange costruisce la chiave
  TExprProbe = class
  public
    IdxCalls, RangeCalls, CondCount: Integer;
    LastProposed, LastIndex: String;
    LastAcceptIn: Boolean;
    FNames: TArray<String>;       // campi dell'espressione, nell'ordine dell'indice
    FSizes: TArray<Integer>;      // larghezza dei campi
    Mode: Integer;                // 0 non gestisce (TQuery), 1 imposta la chiave con riempimento
    procedure OnNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
      ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
    procedure OnRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
      const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
  end;

procedure TExprProbe.OnNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
  ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
begin
  Inc(IdxCalls);
  LastAcceptIn := AAccept;
  LastProposed := AIndexName;
end;

procedure TExprProbe.OnRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
var
  T: TTable;

  function CondValue(const AField: String; out AValue: String): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := 0 to High(AConditions) do
      if SameText(AConditions[j].Field, AField) and (AConditions[j].Op = '=') then begin
        AValue := VarToStr(AConditions[j].Value);
        Result := True;
        Exit;
      end;
  end;

  // chiave: campi con '=' al loro valore; gli altri vuoti (inizio) o pieni di #255 (fine)
  procedure Fill(AHigh: Boolean);
  var
    j: Integer;
    sV: String;
  begin
    for j := 0 to High(FNames) do
      if CondValue(FNames[j], sV) then
        T.FieldByName(FNames[j]).AsString := sV
      else if AHigh then
        T.FieldByName(FNames[j]).AsString := StringOfChar(#255, FSizes[j]);
    T.KeyFieldCount := Length(FNames);
  end;

begin
  Inc(RangeCalls);
  LastIndex := AIndexName;
  CondCount := Length(AConditions);
  if Mode = 0 then
    Exit;
  T := TTable(ADataSet);
  T.SetRangeStart;
  Fill(False);
  T.SetRangeEnd;
  Fill(True);
  T.ApplyRange;
  AHandled := True;
end;

// Proposta del driver per un indice ESPRESSIONE di soli campi di testo, con un WHERE reale:
//  1) solo OnBDESetRange: il WHERE sui primi k campi dell'indice va alla TTable, l'evento
//     riceve l'indice e le k condizioni (controlli)
//  2) l'evento non gestisce: stesso risultato del TQuery (controllo)
//  3) con anche OnBDEIndexNeeded: la proposta arriva con Accept = True (controllo)
// Con la chiave completa le righe devono essere quelle del TQuery (controllo); con una chiave
// parziale il gestore completa la chiave (campi vuoti all'inizio, #255 alla fine) e il
// risultato e' una MISURA, non un controllo. Senza indice del genere il test e' saltato.
procedure TestExprDriver;
var
  T: TTable;
  C2: TFDConnection;
  QA, QB: TFDQuery;
  P: TExprProbe;
  aF, aVal: TArray<String>;
  sIdx, sSql, sOut: String;
  i, j, k, n, m0, nA, nB: Integer;
  bOk, bTab: Boolean;
  msA, msB: Int64;

  // righe di AQ per il WHERE sui primi AK campi (uguaglianze)
  function CountRows(AQ: TFDQuery; AK: Integer; out AMs: Int64): Integer;
  var
    jj: Integer;
    SW: TStopwatch;
  begin
    AQ.Close;
    sSql := 'select * from ' + SqlTab + ' where ';
    for jj := 0 to AK - 1 do begin
      if jj > 0 then
        sSql := sSql + ' and ';
      sSql := sSql + aF[jj] + ' = :p' + IntToStr(jj);
    end;
    AQ.SQL.Text := sSql;
    AQ.Unprepare;           // la scelta dell'indice avviene in Prepare
    for jj := 0 to AK - 1 do
      AQ.ParamByName('p' + IntToStr(jj)).AsString := aVal[jj];
    SW := TStopwatch.StartNew;
    AQ.Open;
    Result := 0;
    while not AQ.Eof do begin
      Inc(Result);
      AQ.Next;
    end;
    AMs := SW.ElapsedMilliseconds;
    AQ.Close;
  end;

begin
  P := TExprProbe.Create;
  T := TTable.Create(nil);
  try
    // 1) primo indice espressione fatto di soli campi di testo, e una riga campione
    sIdx := '';
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.IndexDefs.Update;
    T.FieldDefs.Update;
    for i := 0 to T.IndexDefs.Count - 1 do begin
      aF := BDEExpressionFields(T.IndexDefs[i]);
      if Length(aF) < 2 then
        Continue;
      bOk := True;
      SetLength(P.FSizes, Length(aF));
      for j := 0 to High(aF) do begin
        k := T.FieldDefs.IndexOf(aF[j]);
        if (k < 0) or not (T.FieldDefs[k].DataType in [ftString, ftFixedChar, ftWideString]) then
          bOk := False
        else
          P.FSizes[j] := T.FieldDefs[k].Size;
      end;
      if bOk then begin
        if T.IndexDefs[i].Name = '' then
          sIdx := S_BDE_PrimaryIndex
        else
          sIdx := T.IndexDefs[i].Name;
        Break;
      end;
    end;
    if sIdx = '' then begin
      Write('(nessun indice espressione di soli campi di testo: saltato) ');
      Exit;
    end;
    P.FNames := aF;
    n := Length(aF);
    T.Open;
    if T.RecordCount > 1 then
      T.MoveBy(T.RecordCount div 2);
    SetLength(aVal, n);
    bOk := False;
    for k := 1 to 1000 do begin
      bOk := True;
      for j := 0 to n - 1 do begin
        aVal[j] := TrimRight(T.FieldByName(aF[j]).AsString);
        if Trim(aVal[j]) = '' then
          bOk := False;
      end;
      if bOk or T.Eof then
        Break;
      T.Next;
    end;
    T.Close;
    if not bOk then begin
      Write('(nessuna riga con tutti i campi dell''indice valorizzati: saltato) ');
      Exit;
    end;
    sOut := '(indice ' + sIdx + ' = ' + string.Join('+', aF) + ') ';

    C2 := TFDConnection.Create(nil);
    QA := TFDQuery.Create(nil);
    QB := TFDQuery.Create(nil);
    try
      C2.DriverName := 'BDE';
      C2.LoginPrompt := False;
      C2.Params.Database := Folder;
      C2.Params.Values['TableCursor'] := 'True';
      C2.Open;
      QA.Connection := Conn;           // senza TableCursor: il riferimento
      QB.Connection := C2;

      // 1) solo OnBDESetRange, nessuna proposta da parte del programma
      C2.OnBDESetRange := P.OnRange;
      P.Mode := 1;
      for k := 1 to n do begin
        P.RangeCalls := 0;
        nA := CountRows(QA, k, msA);
        m0 := BDEStatTableCursorOpens;
        nB := CountRows(QB, k, msB);
        bTab := BDEStatTableCursorOpens > m0;
        if not bTab then
          raise Exception.CreateFmt('%d campi: la TTable non e'' stata usata (nessuna proposta)', [k]);
        if (P.RangeCalls <> 1) or (P.CondCount <> k) or not SameText(P.LastIndex, sIdx) then
          raise Exception.CreateFmt('%d campi: OnBDESetRange chiamato %d volte, %d condizioni, indice "%s"',
            [k, P.RangeCalls, P.CondCount, P.LastIndex]);
        sOut := sOut + '(' + IntToStr(k) + ' campi: ' + IntToStr(nB) + ' righe, TTable ' +
          IntToStr(msB) + ' ms, TQuery ' + IntToStr(msA) + ' ms';
        if nA = nB then
          sOut := sOut + ', = TQuery) '
        else if k = n then
          raise Exception.CreateFmt('chiave completa: %d righe contro %d del TQuery', [nB, nA])
        else
          sOut := sOut + ', MISURA: DIVERSO dal TQuery (' + IntToStr(nA) + ')) ';
      end;

      // 2) l'evento non gestisce: stesso risultato del TQuery
      P.Mode := 0;
      P.RangeCalls := 0;
      nA := CountRows(QA, n, msA);
      m0 := BDEStatTableCursorOpens;
      nB := CountRows(QB, n, msB);
      if (BDEStatTableCursorOpens > m0) or (P.RangeCalls <> 1) or (nA <> nB) then
        raise Exception.CreateFmt('non gestito: TTable %s, chiamate %d, righe %d / %d',
          [BoolToStr(BDEStatTableCursorOpens > m0, True), P.RangeCalls, nB, nA]);
      sOut := sOut + '(non gestito: TQuery, ' + IntToStr(nB) + ' righe) ';

      // 3) con anche OnBDEIndexNeeded: la proposta arriva con Accept = True
      C2.OnBDEIndexNeeded := P.OnNeeded;
      P.Mode := 1;
      P.IdxCalls := 0;
      P.RangeCalls := 0;
      m0 := BDEStatTableCursorOpens;
      nB := CountRows(QB, 1, msB);
      if (P.IdxCalls <> 1) or not P.LastAcceptIn or not SameText(P.LastProposed, sIdx) or
         (BDEStatTableCursorOpens <= m0) or (P.RangeCalls <> 1) then
        raise Exception.CreateFmt('con OnBDEIndexNeeded: chiamate %d, Accept %s, proposta "%s", ' +
          'TTable %s, OnBDESetRange %d', [P.IdxCalls, BoolToStr(P.LastAcceptIn, True), P.LastProposed,
          BoolToStr(BDEStatTableCursorOpens > m0, True), P.RangeCalls]);
      sOut := sOut + '(proposta "' + P.LastProposed + '" con Accept = True) ';
    finally
      C2.OnBDEIndexNeeded := nil;
      C2.OnBDESetRange := nil;
      QB.Free;
      QA.Free;
      C2.Free;
    end;
    Write(sOut);
  finally
    T.Free;
    P.Free;
  end;
end;

// Misura (non verifica il driver): costo di FetchOptions.RecsSkip con TableCursor e,
// su una TTable pura, confronto tra Next ripetuto, MoveBy e RecNo per saltare N righe.
// Serve a decidere se il driver deve gestire lo skip da solo (MoveBy) invece di far
// leggere e scartare le righe a FireDAC. Gli skip sono percentuali della tabella
// (0, 1%, 25%, 90%); il confronto dei valori verifica che si arrivi alla stessa riga.
procedure TestSkipProbe;
const
  C_Max = 50;
var
  C2: TFDConnection;
  Q: TFDQuery;
  T: TTable;
  SW: TStopwatch;
  iTot, i, n: Integer;
  aSkip: TArray<Integer>;
  aRefNat, aRefKey: TArray<String>;
  msN, msM, msR, ms: Int64;
  vN, vM, vR: String;
  bOk: Boolean;

  function OpenSkip(const ASQL: String; ASkip: Integer; out AFirst: String): Int64;
  begin
    Q.Close;
    Q.FetchOptions.RecsMax := C_Max;
    if ASkip > 0 then
      Q.FetchOptions.RecsSkip := ASkip
    else
      Q.FetchOptions.RecsSkip := -1;
    SW := TStopwatch.StartNew;
    Q.Open(ASQL);
    n := 0;
    AFirst := '';
    if not Q.Eof then
      AFirst := Q.Fields[0].AsString;
    while not Q.Eof do begin
      Inc(n);
      Q.Next;
    end;
    Result := SW.ElapsedMilliseconds;
    Q.Close;
  end;

  // TTable pura: salta aSkip[i] righe in tre modi e confronta la riga raggiunta
  procedure RawSkip(const ALabel: String; const ARef: TArray<String>);
  var
    j, k: Integer;
  begin
    for j := 1 to High(aSkip) do begin
      T.First;
      SW := TStopwatch.StartNew;
      for k := 1 to aSkip[j] do
        T.Next;
      msN := SW.ElapsedMilliseconds;
      vN := T.Fields[0].AsString;

      T.First;
      SW := TStopwatch.StartNew;
      T.MoveBy(aSkip[j]);
      msM := SW.ElapsedMilliseconds;
      vM := T.Fields[0].AsString;

      T.First;
      try
        SW := TStopwatch.StartNew;
        T.RecNo := aSkip[j] + 1;
        msR := SW.ElapsedMilliseconds;
        vR := T.Fields[0].AsString;
      except
        on E: Exception do begin
          msR := -1;
          vR := '(' + Copy(E.Message, 1, 40) + ')';
        end;
      end;
      Writeln('    ', ALabel, ' skip ', aSkip[j], ': Next x N ', msN, ' ms, MoveBy ', msM,
        ' ms, RecNo ', IfThen(msR < 0, 'non supportato', IntToStr(msR) + ' ms'), ' | stessa riga Next/MoveBy: ',
        IfThen(vN = vM, 'si', 'NO'), ', RecNo: ', IfThen(vR = vN, 'si', 'no'),
        ', come FireDAC: ', IfThen(vN = ARef[j], 'si', 'NO (' + vN + ' contro ' + ARef[j] + ')'));
      if vN <> vM then
        bOk := False;
    end;
  end;

begin
  bOk := True;
  C2 := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  T := TTable.Create(nil);
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    Q.Connection := C2;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.Open;
    iTot := T.RecordCount;
    T.Close;
    if iTot < 200 then begin
      Write('(saltato: servono almeno 200 righe) ');
      Exit;
    end;
    aSkip := [0, iTot div 100, iTot div 4, (iTot * 9) div 10];
    SetLength(aRefNat, Length(aSkip));
    SetLength(aRefKey, Length(aSkip));
    Writeln;
    Writeln('    righe nella tabella: ', iTot, ', RecsMax=', C_Max);

    // 1) FireDAC + TableCursor, ordine naturale
    for i := 0 to High(aSkip) do begin
      ms := OpenSkip('select * from ' + SqlTab, aSkip[i], aRefNat[i]);
      Writeln('    FireDAC TableCursor, RecsSkip=', aSkip[i], ': ', ms, ' ms (', n, ' righe)');
    end;
    // 2) FireDAC + TableCursor, ORDER BY sulla chiave
    if KeyField <> '' then
      for i := 0 to High(aSkip) do begin
        ms := OpenSkip('select * from ' + SqlTab + ' order by ' + KeyField, aSkip[i], aRefKey[i]);
        Writeln('    FireDAC TableCursor + order by ', KeyField, ', RecsSkip=', aSkip[i], ': ', ms,
          ' ms (', n, ' righe)');
      end;

    // 3) TTable pura, ordine naturale
    T.IndexFieldNames := '';
    T.Open;
    RawSkip('TTable naturale  ', aRefNat);
    T.Close;
    // 4) TTable pura, sull'indice della chiave
    if KeyField <> '' then begin
      T.IndexFieldNames := KeyField;
      T.Open;
      RawSkip('TTable su ' + KeyField, aRefKey);
      T.Close;
    end;
    if not bOk then
      raise Exception.Create('Next e MoveBy arrivano a righe diverse');
  finally
    T.Free;
    Q.Free;
    C2.Free;
  end;
end;

// Misura: ORDER BY sul campo chiave con TQuery (via driver) contro una TTable del BDE
// con IndexFieldNames. Serve a decidere se vale la pena usare la TTable per gli ORDER BY.
procedure TestOrderBy;
var
  QA: TFDQuery;
  T: TTable;
  SW: TStopwatch;
  msA, msB: Int64;
  n, j, nKey, nRow: Integer;
  sFld: String;
begin
  QA := TFDQuery.Create(nil);
  T := TTable.Create(nil);
  try
    QA.Connection := Conn;
    SW := TStopwatch.StartNew;
    QA.Open('select * from ' + SqlTab + ' order by ' + KeyField);
    msA := SW.ElapsedMilliseconds;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.IndexFieldNames := KeyField;
    SW := TStopwatch.StartNew;
    try
      T.Open;
    except
      on E: EDBEngineError do begin
        Write('(order by ', KeyField, ': TQuery ', msA, ' ms; TTable non applicabile: ',
          Copy(E.Message, 1, 80), ') ');
        Exit;
      end;
    end;
    msB := SW.ElapsedMilliseconds;
    n := 0;
    nKey := 0;
    nRow := 0;
    while (not QA.Eof) and (not T.Eof) and (n < 5000) do begin
      if QA.FieldByName(KeyField).AsString <> T.FieldByName(KeyField).AsString then
        Inc(nKey);
      for j := 0 to QA.FieldCount - 1 do begin
        sFld := QA.Fields[j].FieldName;
        if QA.Fields[j].AsString <> T.FieldByName(sFld).AsString then begin
          Inc(nRow);
          Break;
        end;
      end;
      Inc(n);
      QA.Next;
      T.Next;
    end;
    Write('(order by ', KeyField, ': TQuery ', msA, ' ms, TTable ', msB, ' ms; prime ', n,
      ' righe: chiave diversa ', nKey, ', riga diversa ', nRow, ') ');
    if nKey > 0 then
      raise Exception.Create('Ordine diverso tra TQuery e TTable');
  finally
    T.Free;
    QA.Free;
  end;
end;

// Misura: WHERE su un intervallo del campo chiave (numerico) con TQuery contro
// TTable + IndexFieldNames + SetRange. Serve a decidere se estendere TableCursor ai WHERE.
procedure TestWhereRange;
var
  QA: TFDQuery;
  T: TTable;
  SW: TStopwatch;
  msA, msB, msC: Int64;
  vMin, vMax, vMid: Variant;
  nCnt, nT, n: Integer;
begin
  vMin := Conn.ExecSQLScalar('select min(' + KeyField + ') from ' + SqlTab);
  vMax := Conn.ExecSQLScalar('select max(' + KeyField + ') from ' + SqlTab);
  if VarIsNull(vMin) or VarIsNull(vMax) or not VarIsNumeric(vMin) then begin
    Write('(chiave vuota o non numerica: saltato) ');
    Exit;
  end;
  vMid := vMin + (vMax - vMin) / 2;
  nCnt := Conn.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' + KeyField +
    ' >= :a and ' + KeyField + ' <= :b', [vMid, vMax]);
  QA := TFDQuery.Create(nil);
  T := TTable.Create(nil);
  try
    QA.Connection := Conn;
    SW := TStopwatch.StartNew;
    QA.Open('select * from ' + SqlTab + ' where ' + KeyField + ' >= :a and ' + KeyField +
      ' <= :b order by ' + KeyField, [vMid, vMax]);
    msA := SW.ElapsedMilliseconds;
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    T.IndexFieldNames := KeyField;
    SW := TStopwatch.StartNew;
    try
      T.Open;
      T.SetRange([vMid], [vMax]);
    except
      on E: EDBEngineError do begin
        Write('(where ', KeyField, ' >= ', VarToStr(vMid), ': TQuery ', msA,
          ' ms; TTable non applicabile: ', Copy(E.Message, 1, 80), ') ');
        Exit;
      end;
    end;
    msB := SW.ElapsedMilliseconds;
    n := 0;
    while (not QA.Eof) and (not T.Eof) and (n < 5000) do begin
      if QA.FieldByName(KeyField).AsString <> T.FieldByName(KeyField).AsString then
        raise Exception.CreateFmt('Chiave diversa alla riga %d', [n + 1]);
      Inc(n);
      QA.Next;
      T.Next;
    end;
    SW := TStopwatch.StartNew;
    nT := n;
    while not T.Eof do begin
      Inc(nT);
      T.Next;
    end;
    msC := SW.ElapsedMilliseconds;
    Write('(where ', KeyField, ' >= ', VarToStr(vMid), ': ', nCnt, ' righe; TQuery apertura ', msA,
      ' ms, TTable+SetRange apertura ', msB, ' ms, lettura completa TTable ', msC, ' ms; prime ',
      n, ' chiavi uguali) ');
    if nT <> nCnt then
      raise Exception.CreateFmt('Righe diverse: count(*)=%d, TTable=%d', [nCnt, nT]);
  finally
    T.Free;
    QA.Free;
  end;
end;

// Misura il costo della lettura riga per riga: BDE grezzo (TTable: solo cursore, campi letti con
// Variant, campi letti con accessi tipizzati) contro FireDAC (TFDQuery + TableCursor, FetchAll).
// La differenza dice quanto costano FireDAC e il driver rispetto al BDE stesso.
procedure TestFetchCost;
const
  C_NoRead = [ftMemo, ftWideMemo, ftFmtMemo, ftBlob, ftGraphic, ftTypedBinary, ftBytes, ftVarBytes];
var
  C2: TFDConnection;
  Q: TFDQuery;
  T: TTable;
  SW: TStopwatch;
  msCur, msVar, msTyp, msFD: Int64;
  n, nFD, i, k: Integer;
  v: Variant;
  f, dSink: Double;
  sv: String;
  fld: TField;
begin
  dSink := 0;
  T := TTable.Create(nil);
  try
    T.DatabaseName := Folder;
    T.TableName := TabName;
    T.ReadOnly := True;
    // 1. solo il cursore
    T.Open;
    SW := TStopwatch.StartNew;
    n := 0;
    while not T.Eof do begin
      Inc(n);
      T.Next;
    end;
    msCur := SW.ElapsedMilliseconds;
    T.Close;
    // 2. tutti i campi con Value (Variant), come fa oggi il driver
    T.Open;
    SW := TStopwatch.StartNew;
    while not T.Eof do begin
      for i := 0 to T.FieldCount - 1 do begin
        fld := T.Fields[i];
        if (not (fld.DataType in C_NoRead)) and (not fld.IsNull) then begin
          v := fld.Value;
          if VarIsNumeric(v) then
            dSink := dSink + 1;
        end;
      end;
      T.Next;
    end;
    msVar := SW.ElapsedMilliseconds;
    T.Close;
    // 3. tutti i campi con accessi tipizzati
    T.Open;
    SW := TStopwatch.StartNew;
    while not T.Eof do begin
      for i := 0 to T.FieldCount - 1 do begin
        fld := T.Fields[i];
        if (not (fld.DataType in C_NoRead)) and (not fld.IsNull) then
          case fld.DataType of
          ftFloat, ftCurrency, ftBCD: begin f := fld.AsFloat; dSink := dSink + f; end;
          ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint: begin k := fld.AsInteger; dSink := dSink + k; end;
          ftString, ftWideString, ftFixedChar, ftFixedWideChar: begin sv := fld.AsString; dSink := dSink + Length(sv); end;
          ftBoolean: if fld.AsBoolean then dSink := dSink + 1;
          ftDate, ftTime, ftDateTime, ftTimeStamp: dSink := dSink + fld.AsDateTime;
          end;
      end;
      T.Next;
    end;
    msTyp := SW.ElapsedMilliseconds;
    T.Close;
  finally
    T.Free;
  end;
  // 4. FireDAC con TableCursor (cursore TTable + conversione in FireDAC)
  C2 := TFDConnection.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    C2.DriverName := 'BDE';
    C2.LoginPrompt := False;
    C2.Params.Database := Folder;
    C2.Params.Values['TableCursor'] := 'True';
    C2.Open;
    Q.Connection := C2;
    SW := TStopwatch.StartNew;
    Q.Open('select * from ' + SqlTab);
    Q.FetchAll;
    nFD := Q.RecordCount;
    msFD := SW.ElapsedMilliseconds;
  finally
    Q.Free;
    C2.Free;
  end;
  Write('(', n, ' righe; BDE grezzo: solo cursore ', msCur, ' ms, campi con Variant ', msVar,
    ' ms, campi tipizzati ', msTyp, ' ms; FireDAC FetchAll con TableCursor ', msFD, ' ms)');
  if dSink < 0 then
    Write(' ');
  if nFD <> n then
    raise Exception.CreateFmt('Righe diverse: BDE %d, FireDAC %d', [n, nFD]);
end;

procedure TestEscapes;
var
  sW: String;
  iBad: Integer;

  procedure Chk(const AExpr: String);
  var
    v: Variant;
  begin
    try
      v := Conn.ExecSQLScalar('select ' + AExpr + ' from ' + SqlTab + sW,
        [FirstKey]);
      Write('(', AExpr, ' = ', VarToStr(v), ') ');
    except
      on E: Exception do begin
        Inc(iBad);
        Write('(ERRORE ', AExpr, ': ', Copy(E.Message, 1, 80), ') ');
      end;
    end;
  end;

begin
  if (KeyField = '') or (TextField = '') or
     VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: servono campo chiave e campo testo) ');
    Exit;
  end;
  iBad := 0;
  sW := ' where ' + KeyField + ' = :k';
  Chk('{fn UCASE(' + TextField + ')}');
  Chk('{fn LCASE(' + TextField + ')}');
  Chk('{fn LTRIM(' + TextField + ')}');
  Chk('{fn RTRIM(' + TextField + ')}');
  Chk('{fn SUBSTRING(' + TextField + ', 1, 4)}');
  Chk('{fn CONCAT(' + TextField + ', ''-x'')}');
  Chk('{fn CONVERT(' + KeyField + ', CHAR)}');
  Chk('{fn CONVERT(' + KeyField + ', INT)}');
  if DateField <> '' then begin
    Chk('{fn YEAR(' + DateField + ')}');
    Chk('{fn MONTH(' + DateField + ')}');
    Chk('{fn DAYOFMONTH(' + DateField + ')}');
  end;
  if iBad > 0 then
    raise Exception.Create(IntToStr(iBad) + ' escape non funzionanti');
end;

procedure TestParam;
var
  Q: TFDQuery;
begin
  if (KeyField = '') or VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: serve il campo chiave) ');
    Exit;
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' = :k',
      [FirstKey]);
    Write('(righe trovate=', Q.RecordCount, ') ');
    if Q.RecordCount < 1 then
      raise Exception.Create('Nessuna riga con la chiave ' + VarToStr(FirstKey));
  finally
    Q.Free;
  end;
end;

procedure TestTable;
var
  T: TFDTable;
begin
  T := TFDTable.Create(nil);
  try
    T.Connection := Conn;
    T.TableName := TabName;
    T.Open;
    Write('(righe=', T.RecordCount, ') ');
    if KeyField <> '' then begin
      T.IndexFieldNames := KeyField;
      T.First;
      if not VarIsNull(FirstKey) and not VarIsEmpty(FirstKey) then
        if not T.Locate(KeyField, FirstKey, []) then
          raise Exception.Create('Locate non ha trovato la chiave');
    end;
  finally
    T.Free;
  end;
end;

procedure TestWrite;
var
  Q: TFDQuery;
  sOld, sNew, sRead: String;
  iCnt, iUpd: Integer;
begin
  if (KeyField = '') or (TextField = '') or
     VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: servono campo chiave e campo testo) ');
    Exit;
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.UpdateOptions.UpdateTableName := TabName;
    Q.UpdateOptions.KeyFields := KeyField;
    Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' = :k',
      [FirstKey]);
    sOld := Q.FieldByName(TextField).AsString;
    // FireDAC aggiorna con WHERE sul solo campo chiave e pretende ESATTAMENTE
    // 1 riga: se la chiave non e' univoca l'update colpisce piu' righe
    iCnt := Conn.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' +
      KeyField + ' = :k', [FirstKey]);
    Write('(righe con la chiave ', VarToStr(FirstKey), ': ', iCnt, ') ');
    if iCnt <> 1 then begin
      Write('SALTATO: ' + KeyField + ' non e'' univoca, scegli un altro campo chiave ');
      Exit;
    end;
    if sOld = '' then
      sNew := '#'
    else
      sNew := Copy(sOld, 1, Length(sOld) - 1) + '#';
    Conn.StartTransaction;
    try
      // update diretto: mostra quante righe il BDE dichiara di aver toccato
      iUpd := Conn.ExecSQL('update ' + SqlTab + ' set ' + TextField + ' = ' +
        TextField + ' where ' + KeyField + ' = :k', [FirstKey]);
      Write('(update diretto: ', iUpd, ' righe) ');
      Q.Edit;
      Q.FieldByName(TextField).AsString := sNew;
      Q.Post;
      Q.Close;
      Q.Open;
      sRead := Q.FieldByName(TextField).AsString;
      if sRead <> sNew then
        raise Exception.Create('Valore dopo l''update diverso dal previsto');
    finally
      Conn.Rollback;
    end;
    Q.Close;
    Q.Open;
    sRead := Q.FieldByName(TextField).AsString;
    if sRead = sOld then
      Write('(update ok, rollback ok) ')
    else
      Write('(update ok, ma il ROLLBACK non ha ripristinato il valore) ');
  finally
    Q.Free;
  end;
end;

procedure TestInsertDelete;
var
  Q: TFDQuery;
  vNew: Variant;
  iCnt: Integer;
  oKey: TField;
begin
  if (KeyField = '') or VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: serve il campo chiave) ');
    Exit;
  end;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.UpdateOptions.UpdateTableName := TabName;
    Q.UpdateOptions.KeyFields := KeyField;
    Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' = :k', [FirstKey]);
    oKey := Q.FieldByName(KeyField);
    if oKey.DataType in [ftString, ftWideString, ftFixedChar] then
      vNew := Copy('~BDETST', 1, oKey.Size)
    else
      vNew := Conn.ExecSQLScalar('select max(' + KeyField + ') from ' + SqlTab) + 1000;
    Conn.StartTransaction;
    try
      Q.Append;
      oKey.Value := vNew;
      Q.Post;
      iCnt := Conn.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' +
        KeyField + ' = :k', [vNew]);
      Write('(dopo insert: ', iCnt, ') ');
      if iCnt <> 1 then
        raise Exception.Create('Insert non visibile');
      // delete della riga appena inserita
      Q.Close;
      Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' = :k', [vNew]);
      if Q.RecordCount <> 1 then
        raise Exception.Create('Riga inserita non trovata per la delete');
      Q.Delete;
      iCnt := Conn.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' +
        KeyField + ' = :k', [vNew]);
      Write('(dopo delete: ', iCnt, ') ');
      if iCnt <> 0 then
        raise Exception.Create('Delete non eseguita');
    finally
      Conn.Rollback;
    end;
    iCnt := Conn.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' +
      KeyField + ' = :k', [vNew]);
    if iCnt <> 0 then
      Write('(attenzione: dopo il rollback la riga di prova e'' ancora presente) ')
    else
      Write('(rollback ok) ');
  finally
    Q.Free;
  end;
end;

procedure TestMemoWrite;
var
  Q, U: TFDQuery;
  sOld, sNew, sRead, sPar: String;
  i: Integer;
begin
  if (KeyField = '') or (MemoField = '') or
     VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: servono campo chiave e campo memo) ');
    Exit;
  end;
  sNew := '';
  for i := 1 to 40 do
    sNew := sNew + 'Riga ' + IntToStr(i) + ': perche'' lunedi'' citta'' e'' ' +
      #$00E0#$00E8#$00EC#$00F2#$00F9 + ' prova memo lungo' + #13#10;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.UpdateOptions.UpdateTableName := TabName;
    Q.UpdateOptions.KeyFields := KeyField;
    Q.Open('select * from ' + SqlTab + ' where ' + KeyField + ' = :k', [FirstKey]);
    sOld := Q.FieldByName(MemoField).AsString;
    Conn.StartTransaction;
    try
      // 1) via dataset
      Q.Edit;
      Q.FieldByName(MemoField).AsString := sNew;
      Q.Post;
      Q.Close;
      Q.Open;
      sRead := Q.FieldByName(MemoField).AsString;
      Write('(dataset: ', Length(sNew), '->', Length(sRead), ') ');
      if sRead <> sNew then
        raise Exception.Create('Memo scritto via dataset diverso da quello letto');
      // 2) via parametro: prima stringa normale, poi parametro di tipo memo
      for i := 1 to 2 do begin
        U := TFDQuery.Create(nil);
        try
          U.Connection := Conn;
          U.SQL.Text := 'update ' + SqlTab + ' set ' + MemoField +
            ' = :m where ' + KeyField + ' = :k';
          if i = 1 then begin
            sPar := 'prova breve';
            U.ParamByName('m').DataType := ftWideString;
            U.ParamByName('m').AsWideString := sPar;
          end
          else begin
            sPar := sNew;
            U.ParamByName('m').DataType := ftWideMemo;
            U.ParamByName('m').AsWideMemo := sPar;
          end;
          U.ParamByName('k').Value := FirstKey;
          try
            U.ExecSQL;
          except
            on E: Exception do begin
              Write('(param ', i, ' errore: ', E.Message, ') ');
              Continue;
            end;
          end;
        finally
          U.Free;
        end;
        Q.Close;
        Q.Open;
        sRead := Q.FieldByName(MemoField).AsString;
        if sRead = sPar then
          Write('(param ', i, ' ok) ')
        else
          Write('(param ', i, ' DIVERSO: scritti ', Length(sPar), ', letti ',
            Length(sRead), ', inizio="', Copy(sRead, 1, 30), '") ');
      end;
    finally
      Write('(sOld=', Length(sOld), ' car.) ');
      try
        Conn.Rollback;
      except
        on E: Exception do begin
          Write('(ERRORE in ROLLBACK) ');
          raise;
        end;
      end;
    end;
    try
      Q.Close;
      Q.Open;
    except
      on E: Exception do begin
        Write('(ERRORE nella riapertura dopo rollback) ');
        raise;
      end;
    end;
    if Q.FieldByName(MemoField).AsString = sOld then
      Write('(rollback ok) ')
    else
      Write('(il ROLLBACK non ha ripristinato il memo) ');
  finally
    Q.Free;
  end;
end;

procedure TestLock;
var
  Conn2: TFDConnection;
  SW: TStopwatch;
  lLocked: Boolean;
  sSql: String;
  iRows: Integer;
begin
  if (KeyField = '') or (TextField = '') or
     VarIsNull(FirstKey) or VarIsEmpty(FirstKey) then begin
    Write('(saltato: servono campo chiave e campo testo) ');
    Exit;
  end;
  sSql := 'update ' + SqlTab + ' set ' + TextField + ' = ' + TextField +
    ' where ' + KeyField + ' = :k';
  Conn2 := TFDConnection.Create(nil);
  try
    Conn2.DriverName := 'BDE';
    Conn2.LoginPrompt := False;
    Conn2.Params.Database := Folder;
    Conn2.Params.Values['LockRetry'] := '1';  // attesa lock: 1 s invece del default BDE
    Conn2.Open;
    // connessione 1: transazione aperta con la riga modificata
    Conn.StartTransaction;
    try
      Conn.ExecSQL(sSql, [FirstKey]);
      // connessione 2: lettura della stessa riga
      iRows := Conn2.ExecSQLScalar('select count(*) from ' + SqlTab + ' where ' +
        KeyField + ' = :k', [FirstKey]);
      Write('(lettura da conn2: ', iRows, ') ');
      // connessione 2: scrittura sulla stessa riga
      lLocked := False;
      SW := TStopwatch.StartNew;
      try
        Conn2.ExecSQL(sSql, [FirstKey]);
        Write('(conn2 ha scritto: NESSUN lock sulla riga dopo ', SW.ElapsedMilliseconds, ' ms) ');
      except
        on E: EFDDBEngineException do begin
          lLocked := True;
          Write('(conn2 bloccata dopo ', SW.ElapsedMilliseconds, ' ms, kind=');
          case E.Kind of
            ekRecordLocked: Write('ekRecordLocked');
            ekUKViolated:   Write('ekUKViolated');
            ekOther:        Write('ekOther');
          else
            Write(Ord(E.Kind));
          end;
          Write(': ', Copy(E.Message, 1, 120), ') ');
        end;
      end;
    finally
      Conn.Rollback;
    end;
    // dopo il rollback la riga deve essere di nuovo scrivibile da conn2
    try
      Conn2.ExecSQL(sSql, [FirstKey]);
      Write('(dopo rollback conn2 scrive: ok) ');
    except
      on E: Exception do
        raise Exception.Create('Dopo il rollback conn2 non riesce a scrivere: ' + E.Message);
    end;
    if lLocked then
      Write('(lock rilevato) ');
  finally
    Conn2.Free;
  end;
end;

begin
  // processo "scrittore" avviato da TestVisibility
  if (ParamCount >= 2) and SameText(ParamStr(1), '--writer') then begin
    RunWriter(ParamStr(2));
    Halt(0);
  end;
  if ParamCount < 2 then begin
    Writeln('Uso: BDETest <cartella o alias BDE> <tabella> [campo chiave] [campo testo] [campo memo]');
    Halt(1);
  end;
  Folder := ParamStr(1);
  TabName := ParamStr(2);
  SqlTab := QuoteTab(TabName);
  KeyField := '';
  TextField := '';
  if ParamCount >= 3 then
    KeyField := ParamStr(3);
  if ParamCount >= 4 then
    TextField := ParamStr(4);
  MemoField := '';
  if ParamCount >= 5 then
    MemoField := ParamStr(5);
  if ParamCount >= 6 then
    KeyRow := StrToIntDef(ParamStr(6), 1);
  DateField := '';
  if ParamCount >= 7 then
    DateField := ParamStr(7);
  FirstKey := Null;
  FailCount := 0;

  Conn := TFDConnection.Create(nil);
  try
    Conn.DriverName := 'BDE';
    Conn.LoginPrompt := False;
    Conn.Params.Database := Folder;

    Run('Connessione', TestConnect);
    if Conn.Connected then begin
      Run('Elenco tabelle', TestTables);
      Run('Campi della tabella', TestFields);
      Run('Indici', TestIndexes);
      Run('Select e tipi', TestSelect);
      Run('Count e fetch completo', TestCount);
      Run('Query con parametro', TestParam);
      Run('TFDTable e Locate', TestTable);
      Run('Funzioni escape Local SQL', TestEscapes);
      Run('Parametro TableCursor (select semplici con TTable)', TestTableCursor);
      Run('Costo di lettura: BDE grezzo contro FireDAC', TestFetchCost);
      Run('Ricerca dell''indice: BDEFindIndex (indici sintetici)', TestFindIndex);
      if KeyField <> '' then
        Run('Evento OnBDEIndexNeeded (scelta dell''indice)', TestIndexNeeded);
      if KeyField <> '' then
        Run('Misura costi: count(*), Prepare, riapertura nel master-detail', TestCostProbe);
      if (KeyField <> '') and (TextField <> '') then
        Run('Visibilita'' delle modifiche tra processi (scrive: usare una COPIA)', TestVisibility);
      if (KeyField <> '') and (TextField <> '') then
        Run('Misura: TTable.Filter contro WHERE del TQuery', TestFilterProbe);
      Run('Diagnostica: RecsMax (limite di righe) con il driver', TestRecsMax);
      Run('Misura: RecsSkip con TableCursor, Next contro MoveBy contro RecNo', TestSkipProbe);
      Run('Misura: indici espressione (campi uniti da +) con SetRange / FindNearest', TestExprIndexProbe);
      Run('Indice espressione: proposta del driver e OnBDESetRange (WHERE reale)', TestExprDriver);
      if KeyField <> '' then
        Run('Misura ORDER BY: TQuery contro TTable con indice', TestOrderBy);
      if KeyField <> '' then
        Run('Misura WHERE su intervallo di chiave: TQuery contro TTable', TestWhereRange);
      if TextField <> '' then
        Run('Scrittura con rollback', TestWrite);
      if KeyField <> '' then
        Run('Insert e delete con rollback', TestInsertDelete);
      if MemoField <> '' then
        Run('Scrittura memo con rollback', TestMemoWrite);
      if TextField <> '' then
        Run('Lock tra due connessioni', TestLock);
      Conn.Close;
    end;
  finally
    Conn.Free;
  end;

  Writeln;
  Writeln('Test falliti: ', FailCount);
  Readln;
end.
