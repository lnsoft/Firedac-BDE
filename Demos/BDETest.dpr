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
  System.SysUtils, System.Classes, System.Diagnostics, System.Variants,
  Data.DB,
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
