{*******************************************************}
{  FireDAC BDE driver (non ufficiale)                   }
{  Modello: FireDAC.Phys.SQLite / FireDAC.Phys.ODBC     }
{                                                       }
{  Solo Win32 (il BDE e' a 32 bit).                     }
{  Usa TSession/TDatabase/TQuery di DBTables come       }
{  "client library" interna.                            }
{                                                       }
{  Sviluppato e collaudato con Delphi 13.2 su tabelle }
{  dBase III/IV e Paradox 7. Licenza: vedi LICENSE.    }
{  Non e' un prodotto Embarcadero.                     }
{*******************************************************}
{$I FireDAC.inc}
{$HPPEMIT LINKUNIT}

{$IFNDEF WIN32}
  {$MESSAGE ERROR 'Il BDE e'' solo a 32 bit: compilare per Win32'}
{$ENDIF}

unit FireDAC.Phys.BDE;

interface

uses
  System.Classes,
  FireDAC.Stan.Intf, FireDAC.Phys, FireDAC.Phys.BDEDef;

type
  [ComponentPlatformsAttribute(pidWin32)]
  TFDPhysBDEDriverLink = class(TFDPhysDriverLink)
  protected
    function GetBaseDriverID: String; override;
  end;

implementation

uses
  System.SysUtils, System.Variants, System.Generics.Collections, System.IOUtils,
  System.RegularExpressions, Data.DB,
  BDE, Bde.DBTables,
  FireDAC.Stan.Consts, FireDAC.Stan.Util, FireDAC.Stan.Error, FireDAC.Stan.Option,
  FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.Phys.SQLGenerator, FireDAC.Phys.Meta,
  FireDAC.Phys.BDEMeta;

type
  TFDPhysBDEDriver = class;
  TFDPhysBDEConnection = class;
  TFDPhysBDETransaction = class;
  TFDPhysBDECommand = class;

  // ---------------------------------------------------------------------------
  // Eccezione nativa: converte EDBEngineError in EFDDBEngineException
  EFDBDENativeException = class(EFDDBEngineException)
  public
    constructor Create(AErr: EDBEngineError); overload;
  end;

  TFDPhysBDEDriver = class(TFDPhysDriver)
  protected
    class function GetBaseDriverID: String; override;
    class function GetBaseDriverDesc: String; override;
    class function GetRDBMSKind: TFDRDBMSKind; override;
    class function GetConnectionDefParamsClass: TFDConnectionDefParamsClass; override;
    procedure InternalLoad; override;
    procedure InternalUnload; override;
    function InternalCreateConnection(AConnHost: TFDPhysConnectionHost): TFDPhysConnection; override;
    function GetConnParams(AKeys: TStrings; AParams: TFDDatSTable): TFDDatSTable; override;
  end;

  TFDPhysBDEConnection = class(TFDPhysConnection, IFDPhysBDEHooks)
  private
    FSession: TSession;
    FOwnPrivateDir: String;
    FDatabase: TDatabase;
    FTableCursor: Boolean;
    FOnIndexNeeded: TBDEIndexNeededEvent;
    FOnSetRange: TBDESetRangeEvent;
    function GetOnIndexNeeded: TBDEIndexNeededEvent;
    procedure SetOnIndexNeeded(const AValue: TBDEIndexNeededEvent);
    function GetOnSetRange: TBDESetRangeEvent;
    procedure SetOnSetRange(const AValue: TBDESetRangeEvent);
  protected
    procedure InternalConnect; override;
    procedure InternalDisconnect; override;
    function InternalCreateTransaction: TFDPhysTransaction; override;
    function InternalCreateCommand: TFDPhysCommand; override;
    function InternalCreateMetadata: TObject; override;
    function InternalCreateCommandGenerator(
      const ACommand: IFDPhysCommand): TFDPhysCommandGenerator; override;
    procedure InternalExecuteDirect(const ASQL: String;
      ATransaction: TFDPhysTransaction); override;
    function GetCliObj: Pointer; override;
  public
    destructor Destroy; override;
    property BDESession: TSession read FSession;
    property BDEDatabase: TDatabase read FDatabase;
  end;

  TFDPhysBDETransaction = class(TFDPhysTransaction)
  protected
    procedure InternalStartTransaction(ATxID: LongWord); override;
    procedure InternalCommit(ATxID: LongWord); override;
    procedure InternalRollback(ATxID: LongWord); override;
  end;

  // condizione di WHERE ammessa per l'apertura con TTable + SetRange
  TBDERangeCond = record
    Field: String;
    Op: String;       // '=', '>=', '<=', '>', '<'
    Param: String;    // nome del parametro, oppure '' se e' un numero letterale
    Literal: Variant;
    Pos: Integer;     // posizione del campo nell'elenco ORDER BY
  end;

  TFDPhysBDECommand = class(TFDPhysCommand)
  private
    FQuery: TQuery;
    FTable: TTable;           // cursore per le select semplici (TableCursor=True)
    FData: TDataSet;          // sorgente attiva: FQuery oppure FTable
    FFields: TList<TField>;   // campi esposti, nell'ordine delle colonne
    FColNames: TArray<String>;
    FConds: TArray<TBDERangeCond>;   // WHERE per SetRange (con ORDER BY)
    FOrderFields: TArray<String>;
    FUserExc: Exception;             // eccezione sollevata da OnBDEIndexNeeded
    FStdRange: Boolean;              // le condizioni sono servibili dal SetRange standard
    FIndexName: String;              // indice in uso (nome per gli eventi)
    FEqIdx: TArray<Integer>;         // indici in FConds delle uguaglianze, per posizione
    FLoIdx, FHiIdx: Integer;         // limite inferiore / superiore (-1 = nessuno)
    FColumnIndex: Integer;
    FSkipFromSQL: Integer;           // skip dell'escape {LIMIT} letto al Prepare (-1 = nessuno)
    FMeta: TList<TArray<Variant>>;
    FMetaPos: Integer;
    function GetBDEConnection: TFDPhysBDEConnection;
    procedure SkipRows;
    procedure BindParams(AIndex: Integer);
    procedure BuildMeta;
    procedure AddMetaRow(const AValues: array of Variant);
    function OpenTable(const AName: String): TTable;
    procedure FetchQueryRows(ATable: TFDDatSTable; ARowsetSize: LongWord;
      var AResult: LongWord);
    procedure ClearMeta;
    function TryPrepareTable: Boolean;
    procedure BuildFields;
    procedure CreateQuery;
    procedure SwitchToQuery;
    function CondValue(AIdx: Integer; out AValue: Variant): Boolean;
    function SetupTableRange: Boolean;
  protected
    procedure InternalPrepare; override;
    procedure InternalUnprepare; override;
    function InternalOpen(var ACount: TFDCounter): Boolean; override;
    function InternalNextRecordSet: Boolean; override;
    procedure InternalClose; override;
    procedure InternalExecute(ATimes, AOffset: Integer;
      var ACount: TFDCounter); override;
    function InternalColInfoStart(var ATabInfo: TFDPhysDataTableInfo): Boolean; override;
    function InternalColInfoGet(var AColInfo: TFDPhysDataColumnInfo): Boolean; override;
    function InternalFetchRowSet(ATable: TFDDatSTable; AParentRow: TFDDatSRow;
      ARowsetSize: LongWord): LongWord; override;
    function GetCliObj: Pointer; override;
  public
    property BDEConnection: TFDPhysBDEConnection read GetBDEConnection;
  end;

{-------------------------------------------------------------------------------}
{ Utilita'                                                                      }
{-------------------------------------------------------------------------------}
// Riconosce SOLO 'SELECT * FROM tab' e 'SELECT campo[, campo] FROM tab'
// (campi NON tra virgolette: nel Local SQL del BDE "x" e' una stringa letterale;
// tabella semplice o tra virgolette, una sola).
// Qualsiasi altra cosa (WHERE, ORDER BY, JOIN, alias, funzioni, parametri...) non
// corrisponde e resta al TQuery.
function ParseSimpleSelect(const ASQL: String; out ATable: String;
  out ACols, AOrder: TArray<String>; out AConds: TArray<TBDERangeCond>;
  out ADesc: Boolean): Boolean;
const
  C_Cond = '\w+\s*(?:>=|<=|=|>|<)\s*(?::\w+|-?\d+(?:\.\d+)?|''[^'']*'')';
  C_Col = '(?:\w+\.)?(?:\w+|\*)';
  C_Pattern = '^\s*SELECT\s+(' + C_Col + '(?:\s*,\s*' + C_Col + ')*)\s+FROM\s+("[^"]+"|[\w$.]+)' +
    '(?:\s+(?:AS\s+)?(?!WHERE\b|ORDER\b)(\w+))?' +
    '(?:\s+WHERE\s+(' + C_Cond + '(?:\s+AND\s+' + C_Cond + ')*))?' +
    '(?:\s+ORDER\s+BY\s+(\w+(?:\s+(?:ASC|DESC))?(?:\s*,\s*\w+(?:\s+(?:ASC|DESC))?)*))?\s*;?\s*$';
  C_CondParse = '(\w+)\s*(>=|<=|=|>|<)\s*(?::(\w+)|(-?\d+(?:\.\d+)?)|''([^'']*)'')';
var
  oM: TMatch;
  oMC: TMatchCollection;
  oI: TMatch;
  i: Integer;
  s, sAlias: String;
  aItems: TArray<String>;
  nAsc, nDesc: Integer;
begin
  Result := False;
  ADesc := False;
  nAsc := 0;
  nDesc := 0;
  ATable := '';
  SetLength(ACols, 0);
  SetLength(AOrder, 0);
  SetLength(AConds, 0);
  oM := TRegEx.Match(ASQL, C_Pattern, [roIgnoreCase]);
  if not oM.Success then
    Exit;
  ATable := oM.Groups[2].Value;
  if (Length(ATable) > 1) and (ATable[1] = '"') then
    ATable := Copy(ATable, 2, Length(ATable) - 2);
  sAlias := '';
  if (oM.Groups.Count > 3) and (oM.Groups[3].Value <> '') then
    sAlias := oM.Groups[3].Value;
  // elenco campi: '*', 'A.*' (da solo) oppure campi semplici, con prefisso alias facoltativo
  aItems := oM.Groups[1].Value.Split([',']);
  SetLength(ACols, Length(aItems));
  for i := 0 to High(aItems) do begin
    oI := TRegEx.Match(Trim(aItems[i]), '^(?:(\w+)\.)?(\w+|\*)$');
    if not oI.Success then
      Exit;
    if (oI.Groups[1].Value <> '') and not SameText(oI.Groups[1].Value, sAlias) then
      Exit;
    ACols[i] := oI.Groups[2].Value;
    if ACols[i] = '*' then begin
      if Length(aItems) > 1 then
        Exit;
      SetLength(ACols, 0);
    end;
  end;
  // ORDER BY: tutti i campi crescenti oppure tutti discendenti (misti: restano al TQuery)
  if (oM.Groups.Count > 4) and (oM.Groups[4].Value <> '') then begin
    // WHERE: condizioni semplici unite da AND (campo, operatore, :parametro o numero)
    oMC := TRegEx.Matches(oM.Groups[4].Value, C_CondParse, [roIgnoreCase]);
    SetLength(AConds, oMC.Count);
    for i := 0 to oMC.Count - 1 do begin
      AConds[i].Field := oMC[i].Groups[1].Value;
      AConds[i].Op := oMC[i].Groups[2].Value;
      AConds[i].Param := '';
      AConds[i].Literal := Null;
      AConds[i].Pos := -1;
      // un gruppo non partecipante puo' risultare 'Success' con testo vuoto: si guarda il testo
      if oMC[i].Groups[3].Value <> '' then
        AConds[i].Param := oMC[i].Groups[3].Value
      else if (oMC[i].Groups.Count > 4) and (oMC[i].Groups[4].Value <> '') then
        AConds[i].Literal := StrToFloat(oMC[i].Groups[4].Value, TFormatSettings.Invariant)
      else if (oMC[i].Groups.Count > 5) and (Pos('''', oMC[i].Value) > 0) then
        AConds[i].Literal := oMC[i].Groups[5].Value    // testo (anche vuoto)
      else
        Exit;
    end;
  end;
  if (oM.Groups.Count > 5) and (oM.Groups[5].Value <> '') then begin
    aItems := oM.Groups[5].Value.Split([',']);
    SetLength(AOrder, Length(aItems));
    for i := 0 to High(aItems) do begin
      oI := TRegEx.Match(Trim(aItems[i]), '^(\w+)(?:\s+(ASC|DESC))?$', [roIgnoreCase]);
      if not oI.Success then
        Exit;
      AOrder[i] := oI.Groups[1].Value;
      if (oI.Groups.Count > 2) and SameText(oI.Groups[2].Value, 'DESC') then
        Inc(nDesc)
      else
        Inc(nAsc);
    end;
    if (nAsc > 0) and (nDesc > 0) then
      Exit;
    ADesc := nDesc > 0;
  end;
  Result := True;
end;

// --- scelta dell'indice per il percorso TTable ---------------------------------
// I primi campi dell'indice sono AFields (nello stesso ordine; con ASet: gli stessi, in
// qualunque ordine)
function IndexLeads(ADef: TIndexDef; const AFields: TArray<String>; ASet: Boolean): Boolean;
var
  aF: TArray<String>;
  i, k: Integer;
  bHit: Boolean;
begin
  Result := False;
  aF := BDEIndexFieldList(ADef);
  if Length(aF) < Length(AFields) then
    Exit;
  for i := 0 to High(AFields) do
    if ASet then begin
      bHit := False;
      for k := 0 to High(AFields) do
        if SameText(aF[k], AFields[i]) then begin
          bHit := True;
          Break;
        end;
      if not bHit then
        Exit;
    end
    else if not SameText(aF[i], AFields[i]) then
      Exit;
  Result := True;
end;

function IsNumericFieldType(AType: TFieldType): Boolean;
begin
  Result := AType in [ftSmallint, ftInteger, ftWord, ftFloat, ftCurrency, ftBCD, ftAutoInc,
    ftLargeint];
end;

function IndexEventName(ADef: TIndexDef): String;
begin
  if ADef.Name = '' then
    Result := S_BDE_PrimaryIndex
  else
    Result := ADef.Name;
end;

function FindIndexByName(ATab: TTable; const AName: String): TIndexDef;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to ATab.IndexDefs.Count - 1 do
    if ((AName = S_BDE_PrimaryIndex) and (ATab.IndexDefs[i].Name = '')) or
       ((ATab.IndexDefs[i].Name <> '') and SameText(ATab.IndexDefs[i].Name, AName)) then begin
      Result := ATab.IndexDefs[i];
      Exit;
    end;
end;

procedure BDEError(AOwner: TObject; E: EDBEngineError; ARow: Integer = -1);
var
  oExc: EFDBDENativeException;
begin
  oExc := EFDBDENativeException.Create(E);
  if (ARow >= 0) and (oExc.ErrorCount > 0) then
    oExc[0].RowIndex := ARow;
  FDException(AOwner, oExc {$IFDEF FireDAC_MONITOR}, False {$ENDIF});
end;

// Mappa un campo BDE su un tipo FireDAC.
// Strings in Unicode (il BDE converte dal language driver della tabella).
procedure MapBDEType(ADataType: TFieldType; ASize, APrec: Integer;
  out AType: TFDDataType; out ALen: LongWord; out APrecision, AScale: Integer;
  var AAttrs: TFDDataAttributes);
begin
  ALen := 0;
  APrecision := 0;
  AScale := 0;
  case ADataType of
  ftString, ftFixedChar:
    begin
      AType := dtWideString;
      ALen := ASize;
      if ADataType = ftFixedChar then
        Include(AAttrs, caFixedLen);
    end;
  ftSmallint:   AType := dtInt16;
  ftWord:       AType := dtUInt16;
  ftInteger:    AType := dtInt32;
  ftLargeint:   AType := dtInt64;
  ftAutoInc:
    begin
      AType := dtInt32;
      AAttrs := AAttrs + [caAutoInc, caReadOnly];
    end;
  ftFloat:      AType := dtDouble;
  ftCurrency:   AType := dtCurrency;
  ftBCD:
    begin
      AType := dtBCD;
      if APrec <= 0 then
        APrecision := 32
      else
        APrecision := APrec;
      AScale := ASize;
    end;
  ftBoolean:    AType := dtBoolean;
  ftDate:       AType := dtDate;
  ftTime:       AType := dtTime;
  ftDateTime, ftTimeStamp:
                AType := dtDateTime;
  ftBytes, ftVarBytes:
    begin
      AType := dtByteString;
      ALen := ASize;
    end;
  ftMemo:
    begin
      AType := dtWideMemo;
      Include(AAttrs, caBlobData);
    end;
  ftBlob, ftGraphic, ftTypedBinary, ftFmtMemo, ftParadoxOle, ftDBaseOle:
    begin
      AType := dtBlob;
      Include(AAttrs, caBlobData);
    end;
  else
    AType := dtUnknown;
  end;
end;

{-------------------------------------------------------------------------------}
{ EFDBDENativeException                                                         }
{-------------------------------------------------------------------------------}
constructor EFDBDENativeException.Create(AErr: EDBEngineError);
var
  i: Integer;
  eKind: TFDCommandExceptionKind;
begin
  inherited Create(1, FDExceptionLayers([S_FD_LPhys, S_FD_BDEId]) + ' ERROR: ' + AErr.Message);
  for i := 0 to AErr.ErrorCount - 1 do begin
    eKind := ekOther;
    // Costanti DBIERR_* da BDE.pas
    case AErr.Errors[i].ErrorCode of
    DBIERR_KEYVIOL:    eKind := ekUKViolated;
    DBIERR_LOCKED,
    DBIERR_FILELOCKED,
    DBIERR_RECLOCKFAILED: eKind := ekRecordLocked;
    end;
    AppendError(i + 1, AErr.Errors[i].ErrorCode, AErr.Errors[i].Message, '', eKind, -1, -1);
  end;
  if AErr.ErrorCount = 0 then
    AppendError(1, 0, AErr.Message, '', ekOther, -1, -1);
end;

{-------------------------------------------------------------------------------}
{ TFDPhysBDEDriverLink                                                          }
{-------------------------------------------------------------------------------}
function TFDPhysBDEDriverLink.GetBaseDriverID: String;
begin
  Result := S_FD_BDEId;
end;

{-------------------------------------------------------------------------------}
{ TFDPhysBDEDriver                                                              }
{-------------------------------------------------------------------------------}
class function TFDPhysBDEDriver.GetBaseDriverID: String;
begin
  Result := S_FD_BDEId;
end;

class function TFDPhysBDEDriver.GetBaseDriverDesc: String;
begin
  Result := 'Borland Database Engine (DBF / Paradox)';
end;

class function TFDPhysBDEDriver.GetRDBMSKind: TFDRDBMSKind;
begin
  Result := TFDRDBMSKinds.Other;
end;

class function TFDPhysBDEDriver.GetConnectionDefParamsClass: TFDConnectionDefParamsClass;
begin
  Result := TFDPhysBDEConnectionDefParams;
end;

procedure TFDPhysBDEDriver.InternalLoad;
begin
  // Inizializza il BDE (DbiInit) con la sessione di default
  try
    Session.Open;
  except
    on E: EDBEngineError do
      BDEError(Self, E);
  end;
end;

procedure TFDPhysBDEDriver.InternalUnload;
begin
  // niente: il BDE si chiude con il processo
end;

function TFDPhysBDEDriver.InternalCreateConnection(
  AConnHost: TFDPhysConnectionHost): TFDPhysConnection;
begin
  Result := TFDPhysBDEConnection.Create(Self, AConnHost);
end;

function TFDPhysBDEDriver.GetConnParams(AKeys: TStrings;
  AParams: TFDDatSTable): TFDDatSTable;
begin
  Result := inherited GetConnParams(AKeys, AParams);
  Result.Rows.Add([Unassigned, S_FD_ConnParam_BDE_BDEDriver, '@S', 'STANDARD',
    S_FD_ConnParam_BDE_BDEDriver, -1]);
  Result.Rows.Add([Unassigned, S_FD_ConnParam_BDE_NetFileDir, '@S', '',
    S_FD_ConnParam_BDE_NetFileDir, -1]);
  Result.Rows.Add([Unassigned, S_FD_ConnParam_BDE_PrivateDir, '@S', '',
    S_FD_ConnParam_BDE_PrivateDir, -1]);
  Result.Rows.Add([Unassigned, S_FD_ConnParam_BDE_LockRetry, '@I', '',
    S_FD_ConnParam_BDE_LockRetry, -1]);
  Result.Rows.Add([Unassigned, S_FD_ConnParam_BDE_TableCursor, '@L', 'False',
    S_FD_ConnParam_BDE_TableCursor, -1]);
end;

{-------------------------------------------------------------------------------}
{ TFDPhysBDEConnection                                                          }
{-------------------------------------------------------------------------------}
function TFDPhysBDEConnection.GetOnIndexNeeded: TBDEIndexNeededEvent;
begin
  Result := FOnIndexNeeded;
end;

procedure TFDPhysBDEConnection.SetOnIndexNeeded(const AValue: TBDEIndexNeededEvent);
begin
  FOnIndexNeeded := AValue;
end;

function TFDPhysBDEConnection.GetOnSetRange: TBDESetRangeEvent;
begin
  Result := FOnSetRange;
end;

procedure TFDPhysBDEConnection.SetOnSetRange(const AValue: TBDESetRangeEvent);
begin
  FOnSetRange := AValue;
end;

destructor TFDPhysBDEConnection.Destroy;
begin
  inherited Destroy;
end;

function TFDPhysBDEConnection.GetCliObj: Pointer;
begin
  Result := FDatabase;
end;

function TFDPhysBDEConnection.InternalCreateTransaction: TFDPhysTransaction;
begin
  Result := TFDPhysBDETransaction.Create(Self);
end;

function TFDPhysBDEConnection.InternalCreateCommand: TFDPhysCommand;
begin
  Result := TFDPhysBDECommand.Create(Self);
end;

function TFDPhysBDEConnection.InternalCreateMetadata: TObject;
begin
  Result := TFDPhysBDEMetadata.Create(Self);
end;

function TFDPhysBDEConnection.InternalCreateCommandGenerator(
  const ACommand: IFDPhysCommand): TFDPhysCommandGenerator;
begin
  if ACommand <> nil then
    Result := TFDPhysBDECommandGenerator.Create(ACommand)
  else
    Result := TFDPhysBDECommandGenerator.Create(Self);
end;

procedure TFDPhysBDEConnection.InternalConnect;
var
  oParams: TFDPhysBDEConnectionDefParams;
  sDB: String;
begin
  oParams := ConnectionDef.Params as TFDPhysBDEConnectionDefParams;
  sDB := oParams.ExpandedDatabase;
  try
    // Una sessione BDE privata per connessione (il BDE e' per-thread/sessione)
    FSession := TSession.Create(nil);
    FSession.AutoSessionName := True;
    if oParams.NetFileDir <> '' then
      FSession.NetFileDir := FDExpandStr(oParams.NetFileDir);
    if oParams.PrivateDir <> '' then
      FSession.PrivateDir := FDExpandStr(oParams.PrivateDir)
    else begin
      // cartella temporanea propria della connessione: evita che il Local SQL
      // lasci i file _QSQLxxx.DBF nella cartella dati
      FOwnPrivateDir := TPath.Combine(TPath.GetTempPath,
        'FDBDE_' + GUIDToString(TGUID.NewGuid).Replace('{', '').Replace('}', ''));
      ForceDirectories(FOwnPrivateDir);
      FSession.PrivateDir := FOwnPrivateDir;
    end;
    FTableCursor := oParams.TableCursor;
    FSession.Open;
    // attesa sui record bloccati (default BDE ~6 s): vale per la sessione
    if oParams.LockRetry >= 0 then begin
      DbiSetCurrSession(FSession.Handle);
      DbiSetLockRetry(oParams.LockRetry);
    end;
    if oParams.Password <> '' then
      FSession.AddPassword(oParams.Password);  // password Paradox

    FDatabase := TDatabase.Create(nil);
    FDatabase.SessionName := FSession.SessionName;
    FDatabase.DatabaseName := 'FDBDE' + IntToHex(NativeUInt(Self), 8);
    FDatabase.LoginPrompt := False;
    FDatabase.KeepConnection := True;
    // alias oppure percorso
    if (Pos('\', sDB) > 0) or (Pos('/', sDB) > 0) or (Pos(':', sDB) > 0) then begin
      FDatabase.DriverName := oParams.BDEDriver;
      // il BDE vuole un percorso assoluto
      FDatabase.Params.Add('PATH=' + ExpandFileName(sDB));
    end
    else
      FDatabase.AliasName := sDB;
    // Le tabelle locali supportano solo l'isolamento dirty read
    FDatabase.TransIsolation := tiDirtyRead;
    FDatabase.Connected := True;
  except
    on E: EDBEngineError do begin
      InternalDisconnect;
      BDEError(Self, E);
    end;
  end;
end;

procedure TFDPhysBDEConnection.InternalDisconnect;
begin
  try
    if FDatabase <> nil then
      FDatabase.Close;
  finally
    FDFreeAndNil(FDatabase);
    FDFreeAndNil(FSession);
    if FOwnPrivateDir <> '' then begin
      try
        TDirectory.Delete(FOwnPrivateDir, True);
      except
        // file ancora in uso: non e' un errore
      end;
      FOwnPrivateDir := '';
    end;
  end;
end;

procedure TFDPhysBDEConnection.InternalExecuteDirect(const ASQL: String;
  ATransaction: TFDPhysTransaction);
var
  oQry: TQuery;
begin
  oQry := TQuery.Create(nil);
  try
    try
      oQry.DatabaseName := FDatabase.DatabaseName;
      oQry.SessionName := FSession.SessionName;
      oQry.SQL.Text := ASQL;
      oQry.ExecSQL;
    except
      on E: EDBEngineError do
        BDEError(Self, E);
    end;
  finally
    FDFree(oQry);
  end;
end;

{-------------------------------------------------------------------------------}
{ TFDPhysBDETransaction                                                         }
{-------------------------------------------------------------------------------}
procedure TFDPhysBDETransaction.InternalStartTransaction(ATxID: LongWord);
begin
  try
    TFDPhysBDEConnection(ConnectionObj).FDatabase.StartTransaction;
  except
    on E: EDBEngineError do
      BDEError(ConnectionObj, E);
  end;
end;

procedure TFDPhysBDETransaction.InternalCommit(ATxID: LongWord);
begin
  try
    TFDPhysBDEConnection(ConnectionObj).FDatabase.Commit;
  except
    on E: EDBEngineError do
      BDEError(ConnectionObj, E);
  end;
end;

procedure TFDPhysBDETransaction.InternalRollback(ATxID: LongWord);
begin
  try
    TFDPhysBDEConnection(ConnectionObj).FDatabase.Rollback;
  except
    on E: EDBEngineError do
      BDEError(ConnectionObj, E);
  end;
end;

{-------------------------------------------------------------------------------}
{ TFDPhysBDECommand                                                             }
{-------------------------------------------------------------------------------}
function TFDPhysBDECommand.GetBDEConnection: TFDPhysBDEConnection;
begin
  Result := TFDPhysBDEConnection(FConnectionObj);
end;

function TFDPhysBDECommand.GetCliObj: Pointer;
begin
  Result := FData;
end;

procedure TFDPhysBDECommand.ClearMeta;
begin
  FDFreeAndNil(FMeta);
  FMetaPos := 0;
end;

function TFDPhysBDECommand.TryPrepareTable: Boolean;
var
  sTab, sIdx: String;
  aCols, aOrder, aF, aEqN, aRngN, aSeq: TArray<String>;
  aConds: TArray<TBDERangeCond>;
  oMatch: TBDEIndexMatch;
  aEqIdx: TArray<Integer>;
  aKey: TArray<String>;
  oTab: TTable;
  oDef: TIndexDef;
  oUserExc: Exception;
  i, k, p, iEq, iLo, iHi, nEq, nOth: Integer;
  bOk, bDesc, bHook, bSet, bAccept, bRangeHook, bNonNum, bStd: Boolean;
begin
  Result := False;
  if GetCommandKind <> skSelect then
    Exit;
  if not ParseSimpleSelect(FDbCommandText, sTab, aCols, aOrder, aConds, bDesc) then
    Exit;
  FUserExc := nil;
  FIndexName := '';
  FStdRange := True;
  oTab := TTable.Create(nil);
  try
    try
      oTab.DatabaseName := BDEConnection.FDatabase.DatabaseName;
      oTab.SessionName := BDEConnection.FSession.SessionName;
      oTab.TableName := sTab;
      oTab.ReadOnly := True;
      oTab.FieldDefs.Update;            // la tabella deve esistere
      for i := 0 to High(aCols) do      // e contenere i campi richiesti
        if oTab.FieldDefs.IndexOf(aCols[i]) < 0 then
          raise Exception.Create('campo non trovato: ' + aCols[i]);
      // Indice: per l'ORDER BY, oppure (solo con OnBDEIndexNeeded) per un WHERE senza ORDER BY
      bHook := Assigned(BDEConnection.FOnIndexNeeded);
      bRangeHook := Assigned(BDEConnection.FOnSetRange);
      bSet := False;
      SetLength(aSeq, 0);
      aKey := aOrder;
      if (Length(aOrder) = 0) and (Length(aConds) > 0) then begin
        if not bHook then
          raise Exception.Create('WHERE senza ORDER BY');
        bSet := True;
        SetLength(aKey, 0);
        for i := 0 to High(aConds) do begin
          bOk := False;
          for k := 0 to High(aKey) do
            if SameText(aKey[k], aConds[i].Field) then
              bOk := True;
          if not bOk then begin
            SetLength(aKey, Length(aKey) + 1);
            aKey[High(aKey)] := aConds[i].Field;
          end;
        end;
      end;
      if bDesc and not bHook then
        raise Exception.Create('ORDER BY discendente');
      if Length(aKey) > 0 then begin
        for i := 0 to High(aKey) do
          if oTab.FieldDefs.IndexOf(aKey[i]) < 0 then
            raise Exception.Create('campo non trovato: ' + aKey[i]);
        oTab.IndexDefs.Update;
        // campi del WHERE non numerici (testo, date): il driver non sa servirli da solo
        bNonNum := False;
        for i := 0 to High(aConds) do begin
          k := oTab.FieldDefs.IndexOf(aConds[i].Field);
          if (k >= 0) and not IsNumericFieldType(oTab.FieldDefs[k].DataType) then
            bNonNum := True;
        end;
        // proposta del driver (BDEFindIndex): uguaglianze del WHERE sui primi campi dell'indice
        // in qualunque ordine, poi l'eventuale intervallo, poi l'ORDER BY; altrimenti il primo
        // indice che rispetta l'ORDER BY (o copre i campi del WHERE)
        SetLength(aEqN, 0);
        SetLength(aRngN, 0);
        for i := 0 to High(aConds) do
          if aConds[i].Op = '=' then begin
            SetLength(aEqN, Length(aEqN) + 1);
            aEqN[High(aEqN)] := aConds[i].Field;
          end
          else begin
            SetLength(aRngN, Length(aRngN) + 1);
            aRngN[High(aRngN)] := aConds[i].Field;
          end;
        oDef := nil;
        if BDEFindIndex(oTab.IndexDefs, aEqN, aRngN, aOrder, bDesc, oMatch) then
          oDef := FindIndexByName(oTab, oMatch.IndexName);
        if bHook then begin
          // il programma puo' cambiare l'indice o rifiutare; senza proposta (anche per i campi
          // non numerici) l'accettazione parte da False: il comportamento standard
          if bNonNum then
            oDef := nil;
          sIdx := '';
          if oDef <> nil then
            sIdx := IndexEventName(oDef);
          bAccept := oDef <> nil;
          try
            BDEConnection.FOnIndexNeeded(BDEConnection, sTab, string.Join(';', aKey),
              FDbCommandText, bDesc, sIdx, bAccept);
          except
            FUserExc := Exception(AcquireExceptionObject);   // riproposta dopo la pulizia
            raise Exception.Create('errore dell''evento');
          end;
          if (not bAccept) or (sIdx = '') then
            raise Exception.Create('indice rifiutato');
          oDef := FindIndexByName(oTab, sIdx);
          if oDef = nil then
            raise Exception.Create('indice non trovato: ' + sIdx);
          if not (ixExpression in oDef.Options) then begin
            // indice a campi: si controllano campi e verso (un indice-espressione e'
            // responsabilita' del programma)
            if (ixDescending in oDef.Options) <> bDesc then
              raise Exception.Create('verso dell''indice diverso dall''ORDER BY');
            if bSet then
              bOk := IndexLeads(oDef, aKey, True)
            else
              bOk := BDEIndexServesOrder(oDef, aEqN, aKey);
            if not bOk then
              raise Exception.Create('l''indice non corrisponde ai campi');
          end
          else if ((Length(aConds) > 0) or bSet) and not bRangeHook then
            raise Exception.Create('indice-espressione con WHERE');
          // con un indice discendente il SetRange standard non e' usato: serve OnBDESetRange
          if (ixDescending in oDef.Options) and (Length(aConds) > 0) and not bRangeHook then
            raise Exception.Create('WHERE con indice discendente');
        end
        else if oDef = nil then
          raise Exception.Create('nessun indice per l''ORDER BY');
        // campi chiave per il SetRange: i primi campi dell'indice che compaiono nel WHERE
        // (uguaglianze, poi l'intervallo); per un indice-espressione quelli richiesti
        if ixExpression in oDef.Options then
          aSeq := Copy(aKey)
        else begin
          aF := BDEIndexFieldList(oDef);
          k := 0;
          while k < Length(aF) do begin
            bOk := False;
            for i := 0 to High(aConds) do
              if SameText(aConds[i].Field, aF[k]) then
                bOk := True;
            if not bOk then
              Break;
            Inc(k);
          end;
          aSeq := Copy(aF, 0, k);
        end;
        FIndexName := IndexEventName(oDef);
        oTab.IndexName := oDef.Name;
      end;
      iEq := 0;
      iLo := -1;
      iHi := -1;
      bStd := True;
      if Length(aConds) > 0 then
      try
        // WHERE: su campi numerici dei campi chiave dell'indice:
        // uguaglianze sui primi campi, poi al piu' un intervallo sul campo successivo
        if Length(aSeq) = 0 then
          raise Exception.Create('nessun campo chiave per il WHERE');
        for i := 0 to High(aConds) do begin
          p := -1;
          for k := 0 to High(aSeq) do
            if SameText(aConds[i].Field, aSeq[k]) then begin
              p := k;
              Break;
            end;
          if p < 0 then
            raise Exception.Create('campo del WHERE fuori dai campi chiave');
          aConds[i].Pos := p;
          if not IsNumericFieldType(oTab.FieldDefs[oTab.FieldDefs.IndexOf(aSeq[p])].DataType) then
            raise Exception.Create('campo non numerico nel WHERE');
        end;
        SetLength(aEqIdx, 0);
        while iEq < Length(aSeq) do begin
          nEq := 0;
          nOth := 0;
          p := -1;
          for i := 0 to High(aConds) do
            if aConds[i].Pos = iEq then
              if aConds[i].Op = '=' then begin
                Inc(nEq);
                p := i;
              end
              else
                Inc(nOth);
          if (nEq = 1) and (nOth = 0) then begin
            SetLength(aEqIdx, Length(aEqIdx) + 1);
            aEqIdx[High(aEqIdx)] := p;
            Inc(iEq);
          end
          else
            Break;
        end;
        nOth := Length(aEqIdx);
        if iEq < Length(aSeq) then
          for i := 0 to High(aConds) do
            if aConds[i].Pos = iEq then begin
              if (aConds[i].Op = '>=') or (aConds[i].Op = '>') then begin
                if iLo >= 0 then
                  raise Exception.Create('due limiti inferiori');
                iLo := i;
                Inc(nOth);
              end
              else if (aConds[i].Op = '<=') or (aConds[i].Op = '<') then begin
                if iHi >= 0 then
                  raise Exception.Create('due limiti superiori');
                iHi := i;
                Inc(nOth);
              end
              else
                raise Exception.Create('condizione non gestita');
            end;
        if nOth <> Length(aConds) then
          raise Exception.Create('condizioni non gestite');
      except
        // il SetRange standard non puo' servire queste condizioni: serve OnBDESetRange
        bStd := False;
        iEq := 0;
        iLo := -1;
        iHi := -1;
        SetLength(aEqIdx, 0);
      end;
      if not bStd and not bRangeHook then
        raise Exception.Create('condizioni non gestite');
    except
      // qualsiasi dubbio: si torna al TQuery, che riporta l'errore corretto
      FDFreeAndNil(oTab);
      if FUserExc <> nil then begin
        // ...tranne un errore sollevato dall'evento del programma: quello si propaga
        oUserExc := FUserExc;
        FUserExc := nil;
        raise oUserExc;
      end;
      Exit;
    end;
    FTable := oTab;
    FData := oTab;
    FColNames := aCols;
    FConds := aConds;
    FOrderFields := aSeq;
    FEqIdx := aEqIdx;
    FLoIdx := iLo;
    FHiIdx := iHi;
    FStdRange := bStd;
    Result := True;
  except
    FDFree(oTab);
    raise;
  end;
end;

procedure TFDPhysBDECommand.BuildFields;
var
  i: Integer;
begin
  if FFields = nil then
    FFields := TList<TField>.Create
  else
    FFields.Clear;
  if (FTable <> nil) and (Length(FColNames) > 0) then
    for i := 0 to High(FColNames) do
      FFields.Add(FTable.FieldByName(FColNames[i]))
  else
    for i := 0 to FData.FieldCount - 1 do
      FFields.Add(FData.Fields[i]);
end;

procedure TFDPhysBDECommand.CreateQuery;
begin
  FQuery := TQuery.Create(nil);
  FData := FQuery;
  try
    FQuery.DatabaseName := BDEConnection.FDatabase.DatabaseName;
    FQuery.SessionName := BDEConnection.FSession.SessionName;
    FQuery.Unidirectional := True;
    FQuery.SQL.Text := FDbCommandText;
    BDEStatLastSQL := FDbCommandText;
    FQuery.Prepare;
  except
    on E: EDBEngineError do begin
      FData := nil;
      FDFreeAndNil(FQuery);
      BDEError(Self, E);
    end;
  end;
end;

// i valori dei parametri non permettono la TTable (nulli, non numerici): si usa il TQuery
procedure TFDPhysBDECommand.SwitchToQuery;
begin
  FData := nil;
  FDFreeAndNil(FTable);
  SetLength(FColNames, 0);
  SetLength(FConds, 0);
  CreateQuery;
end;

function TFDPhysBDECommand.CondValue(AIdx: Integer; out AValue: Variant): Boolean;
var
  oFP: TFDParam;
begin
  Result := False;
  AValue := Null;
  if FConds[AIdx].Param <> '' then begin
    if GetParams = nil then
      Exit;
    oFP := GetParams.FindParam(FConds[AIdx].Param);
    if (oFP = nil) or oFP.IsNulls[0] then
      Exit;
    AValue := oFP.Values[0];
  end
  else
    AValue := FConds[AIdx].Literal;
  Result := VarIsNumeric(AValue);
end;

// Apre la TTable e applica l'intervallo del WHERE. False se i valori non sono utilizzabili
// (la tabella non viene aperta).
function TFDPhysBDECommand.SetupTableRange: Boolean;
var
  aEq: TArray<Variant>;
  aCnd: TArray<TBDECondition>;
  vLo, vHi, vTmp: Variant;
  i, n: Integer;
  bHandled: Boolean;
begin
  Result := False;
  if Assigned(BDEConnection.FOnSetRange) then begin
    // il programma puo' impostare l'intervallo da se' (tabella aperta sull'indice in uso)
    FTable.Close;
    FTable.Open;
    SetLength(aCnd, Length(FConds));
    for i := 0 to High(FConds) do begin
      aCnd[i].Field := FConds[i].Field;
      aCnd[i].Op := FConds[i].Op;
      CondValue(i, vTmp);            // il valore resta anche se non e' numerico
      aCnd[i].Value := vTmp;
    end;
    bHandled := False;
    BDEConnection.FOnSetRange(BDEConnection, FTable, FIndexName, aCnd, bHandled);
    if bHandled then begin
      Result := True;
      Exit;
    end;
  end;
  if not FStdRange then
    Exit;
  SetLength(aEq, Length(FEqIdx));
  for i := 0 to High(FEqIdx) do
    if not CondValue(FEqIdx[i], aEq[i]) then
      Exit;
  if (FLoIdx >= 0) and not CondValue(FLoIdx, vLo) then
    Exit;
  if (FHiIdx >= 0) and not CondValue(FHiIdx, vHi) then
    Exit;
  Result := True;
  FTable.Close;
  FTable.Open;
  n := Length(aEq);
  if (n > 0) or (FLoIdx >= 0) then begin
    FTable.SetRangeStart;
    for i := 0 to n - 1 do
      FTable.FieldByName(FOrderFields[i]).Value := aEq[i];
    if FLoIdx >= 0 then
      FTable.FieldByName(FOrderFields[n]).Value := vLo;
    FTable.KeyFieldCount := n + Ord(FLoIdx >= 0);
    FTable.KeyExclusive := (FLoIdx >= 0) and (FConds[FLoIdx].Op = '>');
  end;
  if (n > 0) or (FHiIdx >= 0) then begin
    FTable.SetRangeEnd;
    for i := 0 to n - 1 do
      FTable.FieldByName(FOrderFields[i]).Value := aEq[i];
    if FHiIdx >= 0 then
      FTable.FieldByName(FOrderFields[n]).Value := vHi;
    FTable.KeyFieldCount := n + Ord(FHiIdx >= 0);
    FTable.KeyExclusive := (FHiIdx >= 0) and (FConds[FHiIdx].Op = '<');
  end;
  if (n > 0) or (FLoIdx >= 0) or (FHiIdx >= 0) then
    FTable.ApplyRange;
end;

// RecsSkip (e lo skip dell'escape {LIMIT}) applicato dal driver con il solo cursore.
// In TFDPhysCommand.FetchRowSet FireDAC salta le righe sul client, leggendole e
// convertendole una a una, solo se loSkip non e' tra FLimitOptions; in quel caso usa
// FSQLLimitSkip quando e' >= 0 e altrimenti RecsSkip. Qui si salta con Next senza
// toccare i campi e si imposta FSQLLimitSkip := 0, cosi' FireDAC non salta di nuovo.
// FSQLLimitSkip viene riportato a -1 solo da Prepare, quindi va riscritto a ogni apertura.
procedure TFDPhysBDECommand.SkipRows;
var
  iSkip: Integer;
begin
  if (GetCommandKind <> skSelect) or (FData = nil) then
    Exit;
  if FSkipFromSQL >= 0 then
    iSkip := FSkipFromSQL
  else
    iSkip := GetOptions.FetchOptions.RecsSkip;
  FSQLLimitSkip := 0;
  while (iSkip > 0) and not FData.Eof do begin
    FData.Next;
    Dec(iSkip);
  end;
end;

procedure TFDPhysBDECommand.InternalPrepare;
begin
  FMetaPos := 0;
  FSkipFromSQL := FSQLLimitSkip;
  if GetMetaInfoKind <> mkNone then begin
    // i metadati sono costruiti in InternalOpen
    Exit;
  end;
  if GetCommandKind in [skStoredProc, skStoredProcWithCrs, skStoredProcNoCrs] then
    FDCapabilityNotSupported(Self, [S_FD_LPhys, S_FD_BDEId]);

  // Niente GenerateLimitSelect: il Local SQL non ha TOP/LIMIT (FireDAC genererebbe
  // 'SELECT TOP n * FROM (...)', rifiutato dal BDE). RecsMax e RecsSkip li applica FireDAC
  // lato client; con il cursore TTable le righe oltre il limite non vengono nemmeno lette.
  GenerateParamMarkers();

  if BDEConnection.FTableCursor then begin
    if TryPrepareTable then
      Exit;
    if (GetCommandKind = skSelect) and (Length(BDEStatRejectedSelects) < 4000) then
      BDEStatRejectedSelects := BDEStatRejectedSelects + FDbCommandText + sLineBreak;
  end;

  CreateQuery;
end;

procedure TFDPhysBDECommand.InternalUnprepare;
begin
  ClearMeta;
  FData := nil;
  FDFreeAndNil(FFields);
  SetLength(FColNames, 0);
  SetLength(FConds, 0);
  SetLength(FEqIdx, 0);
  SetLength(FOrderFields, 0);
  FDFreeAndNil(FTable);
  FDFreeAndNil(FQuery);
end;

procedure TFDPhysBDECommand.BindParams(AIndex: Integer);
var
  i: Integer;
  oQP: TParam;
  oFP: TFDParam;
begin
  if FQuery = nil then
    Exit;
  for i := 0 to FQuery.ParamCount - 1 do begin
    oQP := FQuery.Params[i];
    oFP := GetParams.FindParam(oQP.Name);
    if oFP = nil then
      Continue;
    if oFP.DataType = ftUnknown then
      ParTypeUnknownError(oFP);
    case oFP.DataType of
    ftString, ftFixedChar, ftWideString, ftFixedWideChar:
      begin
        // il BDE converte lui la stringa in ANSI (language driver)
        oQP.DataType := ftString;
        if oFP.IsNulls[AIndex] then
          oQP.Clear
        else
          oQP.AsString := VarToStr(oFP.Values[AIndex]);
      end;
    ftMemo, ftWideMemo, ftFmtMemo:
      begin
        // parametro BLOB testuale (oltre 255 caratteri)
        oQP.DataType := ftMemo;
        if oFP.IsNulls[AIndex] then
          oQP.Clear
        else
          oQP.Value := VarToStr(oFP.Values[AIndex]);
      end;
    else
      begin
        oQP.DataType := oFP.DataType;
        if oFP.IsNulls[AIndex] then
          oQP.Clear
        else
          oQP.Value := oFP.Values[AIndex];
      end;
    end;
  end;
end;

function TFDPhysBDECommand.InternalOpen(var ACount: TFDCounter): Boolean;
begin
  Result := False;
  ACount := 0;
  if GetMetaInfoKind <> mkNone then begin
    BuildMeta;
    Result := True;
    Exit;
  end;
  try
    if FTable <> nil then begin
      if Length(FConds) = 0 then begin
        FTable.Close;
        FTable.Open;
        AtomicIncrement(BDEStatTableCursorOpens);
      end
      else if SetupTableRange then
        AtomicIncrement(BDEStatTableCursorOpens)
      else
        SwitchToQuery;
    end;
    if FTable = nil then begin
      FQuery.Close;
      BindParams(0);
      FQuery.Open;
    end;
    BuildFields;
    SkipRows;
    Result := True;
  except
    on E: EDBEngineError do
      BDEError(Self, E);
  end;
end;

function TFDPhysBDECommand.InternalNextRecordSet: Boolean;
begin
  Result := False;
end;

procedure TFDPhysBDECommand.InternalClose;
begin
  if FData <> nil then
    FData.Close;
  ClearMeta;
end;

procedure TFDPhysBDECommand.InternalExecute(ATimes, AOffset: Integer;
  var ACount: TFDCounter);
var
  i: Integer;
begin
  ACount := 0;
  for i := AOffset to ATimes - 1 do
    try
      BindParams(i);
      FQuery.ExecSQL;
      if FQuery.RowsAffected > 0 then
        Inc(ACount, FQuery.RowsAffected);
    except
      on E: EDBEngineError do
        BDEError(Self, E, i);
    end;
end;

{-------------------------------------------------------------------------------}
{ Descrizione colonne                                                           }
{-------------------------------------------------------------------------------}
function TFDPhysBDECommand.InternalColInfoStart(var ATabInfo: TFDPhysDataTableInfo): Boolean;
begin
  Result := OpenBlocked;
  if ATabInfo.FSourceID = -1 then begin
    ATabInfo.FSourceName := GetCommandText;
    ATabInfo.FSourceID := 1;
    FColumnIndex := 0;
  end;
end;

function TFDPhysBDECommand.InternalColInfoGet(var AColInfo: TFDPhysDataColumnInfo): Boolean;
var
  oFld: TField;
  iPrec: Integer;
begin
  Result := (FFields <> nil) and (FColumnIndex < FFields.Count);
  if not Result then
    Exit;
  oFld := FFields[FColumnIndex];
  if oFld is TBCDField then
    iPrec := TBCDField(oFld).Precision
  else
    iPrec := 0;
  AColInfo.FAttrs := [caAllowNull, caSearchable];
  MapBDEType(oFld.DataType, oFld.Size, iPrec, AColInfo.FType, AColInfo.FLen,
    AColInfo.FPrec, AColInfo.FScale, AColInfo.FAttrs);
  AColInfo.FSourceName := oFld.FieldName;
  AColInfo.FSourceID := FColumnIndex + 1;
  AColInfo.FSourceType := AColInfo.FType;
  AColInfo.FSourceTypeName := FieldTypeNames[oFld.DataType];
  AColInfo.FOriginTabName.FCatalog := '';
  AColInfo.FOriginTabName.FSchema := '';
  AColInfo.FOriginTabName.FBaseObject := '';
  AColInfo.FOriginTabName.FObject := '';
  AColInfo.FOriginColName := oFld.FieldName;
  AColInfo.FForceAddOpts := [];
  AColInfo.FForceRemOpts := [];
  Inc(FColumnIndex);
end;

{-------------------------------------------------------------------------------}
{ Fetch                                                                         }
{-------------------------------------------------------------------------------}
procedure TFDPhysBDECommand.FetchQueryRows(ATable: TFDDatSTable;
  ARowsetSize: LongWord; var AResult: LongWord);
var
  i: LongWord;
  j: Integer;
  oRow: TFDDatSRow;
  oCol: TFDDatSColumn;
  oFld: TField;
  oStr: TStream;
  aBuf: TBytes;
  iSize: Integer;
  sMemo: String;
begin
  for i := 1 to ARowsetSize do begin
    if FData.Eof then
      Break;
    oRow := ATable.NewRow(False);
    try
      for j := 0 to ATable.Columns.Count - 1 do begin
        oCol := ATable.Columns[j];
        if (oCol.SourceID > 0) and
           CheckFetchColumn(oCol.SourceDataType, oCol.Attributes) then begin
          oFld := FFields[oCol.SourceID - 1];
          if oFld.IsNull then
            oRow.SetData(j, nil, 0)
          else
            case oCol.DataType of
            dtBlob:
              begin
                oStr := FData.CreateBlobStream(oFld, bmRead);
                try
                  iSize := oStr.Size;
                  SetLength(aBuf, iSize);
                  if iSize > 0 then
                    oStr.ReadBuffer(aBuf[0], iSize);
                finally
                  oStr.Free;
                end;
                if iSize > 0 then
                  oRow.SetData(j, @aBuf[0], iSize)
                else
                  oRow.SetData(j, nil, 0);
              end;
            dtWideMemo, dtMemo:
              begin
                // lettura via stream (come i BLOB) e decodifica ANSI esplicita
                oStr := FData.CreateBlobStream(oFld, bmRead);
                try
                  iSize := oStr.Size;
                  SetLength(aBuf, iSize);
                  if iSize > 0 then
                    oStr.ReadBuffer(aBuf[0], iSize);
                finally
                  oStr.Free;
                end;
                if iSize > 0 then begin
                  sMemo := TEncoding.ANSI.GetString(aBuf, 0, iSize);
                  if sMemo <> '' then
                    // via Variant: FireDAC converte la stringa nel tipo memo
                    // della colonna (il puntatore grezzo mandava in AV
                    // sulla prima riga con memo non vuoto)
                    oRow.SetData(j, sMemo)
                  else
                    oRow.SetData(j, nil, 0);
                end
                else
                  oRow.SetData(j, nil, 0);
              end;
            dtByteString:
              begin
                aBuf := oFld.AsBytes;
                if Length(aBuf) > 0 then
                  oRow.SetData(j, @aBuf[0], Length(aBuf))
                else
                  oRow.SetData(j, nil, 0);
              end;
            else
              // FireDAC converte il Variant nel tipo della colonna
              oRow.SetData(j, oFld.Value);
            end;
        end;
      end;
      ATable.Rows.Add(oRow);
    except
      FDFree(oRow);
      raise;
    end;
    FData.Next;
    Inc(AResult);
  end;
end;

function TFDPhysBDECommand.InternalFetchRowSet(ATable: TFDDatSTable;
  AParentRow: TFDDatSRow; ARowsetSize: LongWord): LongWord;
var
  i: LongWord;
  j: Integer;
  oRow: TFDDatSRow;
  aRow: TArray<Variant>;
begin
  Result := 0;
  try
    if GetMetaInfoKind = mkNone then
      FetchQueryRows(ATable, ARowsetSize, Result)
    else
      for i := 1 to ARowsetSize do begin
        if (FMeta = nil) or (FMetaPos >= FMeta.Count) then
          Break;
        aRow := FMeta[FMetaPos];
        oRow := ATable.NewRow(False);
        try
          for j := 0 to Length(aRow) - 1 do
            oRow.SetData(j, aRow[j]);
        except
          FDFree(oRow);
          raise;
        end;
        ATable.Rows.Add(oRow);
        Inc(FMetaPos);
        Inc(Result);
      end;
  except
    on E: EDBEngineError do
      BDEError(Self, E);
  end;
end;

{-------------------------------------------------------------------------------}
{ Metadati (costruiti con TSession/TTable, layout come FetchMetaRow di SQLite)  }
{-------------------------------------------------------------------------------}
procedure TFDPhysBDECommand.AddMetaRow(const AValues: array of Variant);
var
  aRow: TArray<Variant>;
  i: Integer;
begin
  SetLength(aRow, Length(AValues));
  for i := 0 to High(AValues) do
    aRow[i] := AValues[i];
  FMeta.Add(aRow);
end;

function TFDPhysBDECommand.OpenTable(const AName: String): TTable;
begin
  Result := TTable.Create(nil);
  try
    Result.DatabaseName := BDEConnection.FDatabase.DatabaseName;
    Result.SessionName := BDEConnection.FSession.SessionName;
    Result.TableName := AName;
    Result.FieldDefs.Update;
    Result.IndexDefs.Update;
  except
    Result.Free;
    raise;
  end;
end;

procedure TFDPhysBDECommand.BuildMeta;
var
  rName: TFDPhysParsedName;
  oList: TStringList;
  oTab: TTable;
  oFD: TFieldDef;
  oID: TIndexDef;
  eType: TFDDataType;
  eAttrs: TFDDataAttributes;
  iLen: LongWord;
  iPrec, iScale, i, j, n: Integer;
  sWild, sIdx, sCol, sExt: String;
  oCols: TStringList;
begin
  ClearMeta;
  FMeta := TList<TArray<Variant>>.Create;
  GetSelectMetaInfoParams(rName);
  sWild := GetWildcard;
  try
    case GetMetaInfoKind of
    mkCatalogs:
      AddMetaRow([1, BDEConnection.FDatabase.DatabaseName]);

    mkTables:
      if (tkTable in GetTableKinds) and (osMy in GetObjectScopes) then begin
        oList := TStringList.Create;
        try
          oList.Sorted := True;
          oList.Duplicates := dupIgnore;
          // Con le estensioni: in un alias possono coesistere CLIENTI.DB e
          // CLIENTI.DBF e il BDE, senza estensione, aprirebbe sempre il Paradox
          BDEConnection.FSession.GetTableNames(
            BDEConnection.FDatabase.DatabaseName, '', True, False, oList);
          n := 0;
          for i := 0 to oList.Count - 1 do begin
            sExt := UpperCase(ExtractFileExt(oList[i]));
            if (sExt <> '.DB') and (sExt <> '.DBF') then
              Continue;
            // risultati temporanei del Local SQL
            if SameText(Copy(oList[i], 1, 5), '_QSQL') then
              Continue;
            if (sWild = '') or FDStrLike(oList[i], sWild, True) then begin
              Inc(n);
              AddMetaRow([n, Null, Null, oList[i], Smallint(tkTable), Smallint(osMy)]);
            end;
          end;
        finally
          oList.Free;
        end;
      end;

    mkTableFields:
      begin
        oTab := OpenTable(rName.FObject);
        try
          n := 0;
          for i := 0 to oTab.FieldDefs.Count - 1 do begin
            oFD := oTab.FieldDefs[i];
            if (sWild <> '') and not FDStrLike(oFD.Name, sWild, True) then
              Continue;
            eAttrs := [caBase];
            if not oFD.Required then
              Include(eAttrs, caAllowNull);
            MapBDEType(oFD.DataType, oFD.Size, oFD.Precision, eType, iLen, iPrec,
              iScale, eAttrs);
            Inc(n);
            AddMetaRow([n, Null, Null, rName.FObject, oFD.Name, oFD.FieldNo,
              Smallint(eType), FieldTypeNames[oFD.DataType], PWord(@eAttrs)^,
              iPrec, iScale, Integer(iLen)]);
          end;
        finally
          oTab.Free;
        end;
      end;

    mkIndexes:
      begin
        oTab := OpenTable(rName.FObject);
        try
          n := 0;
          for i := 0 to oTab.IndexDefs.Count - 1 do begin
            oID := oTab.IndexDefs[i];
            // l'indice primario Paradox ha nome vuoto
            if ixPrimary in oID.Options then
              sIdx := 'PRIMARY'
            else
              sIdx := oID.Name;
            if (sWild <> '') and not FDStrLike(sIdx, sWild, True) then
              Continue;
            Inc(n);
            if ixPrimary in oID.Options then
              AddMetaRow([n, Null, Null, rName.FObject, sIdx, Null, Smallint(ikPrimaryKey)])
            else if ixUnique in oID.Options then
              AddMetaRow([n, Null, Null, rName.FObject, sIdx, Null, Smallint(ikUnique)])
            else
              AddMetaRow([n, Null, Null, rName.FObject, sIdx, Null, Smallint(ikNonUnique)]);
          end;
        finally
          oTab.Free;
        end;
      end;

    mkIndexFields,
    mkPrimaryKeyFields:
      begin
        oTab := OpenTable(rName.FBaseObject);
        oCols := TStringList.Create;
        try
          oCols.Delimiter := ';';
          oCols.StrictDelimiter := True;
          n := 0;
          for i := 0 to oTab.IndexDefs.Count - 1 do begin
            oID := oTab.IndexDefs[i];
            if ixPrimary in oID.Options then
              sIdx := 'PRIMARY'
            else
              sIdx := oID.Name;
            if GetMetaInfoKind = mkPrimaryKeyFields then begin
              if not (ixPrimary in oID.Options) then
                Continue;
            end
            else if not SameText(sIdx, rName.FObject) then
              Continue;
            oCols.DelimitedText := oID.Fields;
            for j := 0 to oCols.Count - 1 do begin
              sCol := Trim(oCols[j]);
              if sCol = '' then
                Continue;
              Inc(n);
              if (ixDescending in oID.Options) or
                 (Pos(sCol, oID.DescFields) > 0) then
                AddMetaRow([n, Null, Null, rName.FBaseObject, sIdx, sCol, j + 1, 'D', Null])
              else
                AddMetaRow([n, Null, Null, rName.FBaseObject, sIdx, sCol, j + 1, 'A', Null]);
            end;
          end;
        finally
          oCols.Free;
          oTab.Free;
        end;
      end;

    mkPrimaryKey:
      begin
        oTab := OpenTable(rName.FObject);
        try
          for i := 0 to oTab.IndexDefs.Count - 1 do
            if ixPrimary in oTab.IndexDefs[i].Options then begin
              AddMetaRow([1, Null, Null, rName.FObject, 'PRIMARY', 'PRIMARY',
                Smallint(ikPrimaryKey)]);
              Break;
            end;
        finally
          oTab.Free;
        end;
      end;

    // mkSchemas, mkForeignKeys*, mkPackages, mkProcs*, mkGenerators, ... : nessuna riga
    end;
  except
    on E: EDBEngineError do
      BDEError(Self, E);
  end;
  FMetaPos := 0;
end;

initialization
  FDRegisterDriverClass(TFDPhysBDEDriver);

finalization
  FDUnregisterDriverClass(TFDPhysBDEDriver);

end.
