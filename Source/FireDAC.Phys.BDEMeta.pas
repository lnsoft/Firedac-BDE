{*******************************************************}
{  FireDAC BDE driver (non ufficiale) - metadati        }
{  Modello: FireDAC.Phys.SQLiteMeta                     }
{*******************************************************}
{$I FireDAC.inc}

unit FireDAC.Phys.BDEMeta;

interface

uses
  System.Classes,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.Phys.Meta, FireDAC.Phys.SQLGenerator;

type
  TFDPhysBDEMetadata = class(TFDPhysConnectionMetadata)
  protected
    function GetKind: TFDRDBMSKind; override;
    function GetIsFileBased: Boolean; override;
    function GetTxSupported: Boolean; override;
    function GetTxNested: Boolean; override;
    function GetTxSavepoints: Boolean; override;
    function GetTxAutoCommit: Boolean; override;
    function GetParamNameMaxLength: Integer; override;
    function GetNameParts: TFDPhysNameParts; override;
    // Un nome che termina con .DB o .DBF (non quotato) e' UNA sola tabella
    function InternalDecodeObjName(const AName: String;
      out AParsedName: TFDPhysParsedName; const ACommand: IFDPhysCommand;
      ARaise: Boolean): Boolean; override;
    function GetNameQuoteChar(AQuote: TFDPhysNameQuoteLevel;
      ASide: TFDPhysNameQuoteSide): Char; override;
    function GetNameQuotedCaseSensParts: TFDPhysNameParts; override;
    function GetNameQuotedCaseSens(const AName: String;
      APart: TFDPhysNamePart): Boolean; override;
    function GetNameCaseSensParts: TFDPhysNameParts; override;
    function GetNameDefLowCaseParts: TFDPhysNameParts; override;
    function GetIdentityInsertSupported: Boolean; override;
    function GetNamedParamMark: TFDPhysParamMark; override;
    function GetPositionedParamMark: TFDPhysParamMark; override;
    function GetSelectOptions: TFDPhysSelectOptions; override;
    function GetAsyncAbortSupported: Boolean; override;
    function GetArrayExecMode: TFDPhysArrayExecMode; override;
    function GetLimitOptions: TFDPhysLimitOptions; override;
    function GetDefValuesSupported: TFDPhysDefaultValues; override;
    function GetColumnOriginProvided: Boolean; override;
    function GetInlineRefresh: Boolean; override;
    function GetTruncateSupported: Boolean; override;
    function InternalEscapeBoolean(const AStr: String): String; override;
    function InternalEscapeFunction(const ASeq: TFDPhysEscapeData): String; override;
  public
    constructor Create(const AConnection: TFDPhysConnection);
  end;

  TFDPhysBDECommandGenerator = class(TFDPhysCommandGenerator)
  protected
    // I metadati sono costruiti direttamente dal Command (nessun SQL di sistema)
    function GetSelectMetaInfo(AKind: TFDPhysMetaInfoKind;
      const ACatalog, ASchema, ABaseObject, AObject, AWildcard: String;
      AObjectScopes: TFDPhysObjectScopes; ATableKinds: TFDPhysTableKinds;
      AOverload: Word): String; override;
  end;

implementation

uses
  System.SysUtils,
  FireDAC.Stan.Consts, FireDAC.Stan.Util, FireDAC.Stan.Error;

{ TFDPhysBDEMetadata }

function IsBDETableFileName(const AName: String): Boolean;
var
  sUp: String;
begin
  sUp := UpperCase(Trim(AName));
  Result := (sUp <> '') and (Pos('"', sUp) = 0) and
    (sUp.EndsWith('.DB') or sUp.EndsWith('.DBF'));
end;

function TFDPhysBDEMetadata.InternalDecodeObjName(const AName: String;
  out AParsedName: TFDPhysParsedName; const ACommand: IFDPhysCommand;
  ARaise: Boolean): Boolean;
begin
  if IsBDETableFileName(AName) then begin
    AParsedName.FCatalog := '';
    AParsedName.FSchema := '';
    AParsedName.FBaseObject := '';
    AParsedName.FObject := Trim(AName);
    AParsedName.FLink := '';
    AParsedName.FOverload := '';
    Result := True;
  end
  else
    Result := inherited InternalDecodeObjName(AName, AParsedName, ACommand, ARaise);
end;

constructor TFDPhysBDEMetadata.Create(const AConnection: TFDPhysConnection);
begin
  inherited Create(AConnection, 0, 0, False);
  // Parole riservate del Local SQL (guida Local SQL, "Reserved words")
  FKeywords.CommaText :=
    'ACTIVE,ADD,ALL,AFTER,ALTER,AND,ANY,AS,ASC,ASCENDING,AT,AUTO,AUTOINC,' +
    'AVG,BASE_NAME,BEFORE,BEGIN,BETWEEN,BLOB,BOOLEAN,BOTH,BY,BYTES,CACHE,' +
    'CAST,CHAR,CHARACTER,CHECK,CHECK_POINT_LENGTH,COLLATE,COLUMN,COMMIT,' +
    'COMMITTED,COMPUTED,CONDITIONAL,CONSTRAINT,CONTAINING,COUNT,CREATE,' +
    'CSTRING,CURRENT,CURSOR,DATABASE,DATE,DAY,DEBUG,DEC,DECIMAL,DECLARE,' +
    'DEFAULT,DELETE,DESC,DESCENDING,DISTINCT,DO,DOMAIN,DOUBLE,DROP,ELSE,' +
    'END,ENTRY_POINT,ESCAPE,EXCEPTION,EXECUTE,EXISTS,EXIT,EXTERNAL,' +
    'EXTRACT,FILE,FILTER,FLOAT,FOR,FOREIGN,FROM,FULL,FUNCTION,GDSCODE,' +
    'GENERATOR,GEN_ID,GRANT,GROUP,GROUP_COMMIT_WAIT_TIME,HAVING,HOUR,IF,' +
    'IN,INT,INACTIVE,INDEX,INNER,INPUT_TYPE,INSERT,INTEGER,INTO,IS,' +
    'ISOLATION,JOIN,KEY,LONG,LENGTH,LOGFILE,LOWER,LEADING,LEFT,LEVEL,LIKE,' +
    'LOG_BUFFER_SIZE,MANUAL,MAX,MAXIMUM_SEGMENT,MERGE,MESSAGE,MIN,MINUTE,' +
    'MODULE_NAME,MONEY,MONTH,NAMES,NATIONAL,NATURAL,NCHAR,NO,NOT,NULL,' +
    'NUM_LOG_BUFFERS,NUMERIC,OF,ON,ONLY,OPTION,OR,ORDER,OUTER,OUTPUT_TYPE,' +
    'OVERFLOW,PAGE_SIZE,PAGE,PAGES,PARAMETER,PASSWORD,PLAN,POSITION,' +
    'POST_EVENT,PRECISION,PROCEDURE,PROTECTED,PRIMARY,PRIVILEGES,' +
    'RAW_PARTITIONS,READ,REAL,RECORD_VERSION,REFERENCES,RESERV,RESERVING,' +
    'RETAIN,RETURNING_VALUES,RETURNS,REVOKE,RIGHT,ROLLBACK,SECOND,SEGMENT,' +
    'SELECT,SET,SHARED,SHADOW,SCHEMA,SINGULAR,SIZE,SMALLINT,SNAPSHOT,SOME,' +
    'SORT,SQLCODE,STABILITY,STARTING,STARTS,STATISTICS,SUB_TYPE,SUBSTRING,' +
    'SUM,SUSPEND,TABLE,THEN,TIME,TIMESTAMP,TIMEZONE_HOUR,TIMEZONE_MINUTE,' +
    'TO,TRAILING,TRANSACTION,TRIGGER,TRIM,UNCOMMITTED,UNION,UNIQUE,UPDATE,' +
    'UPPER,USER,VALUE,VALUES,VARCHAR,VARIABLE,VARYING,VIEW,WAIT,WHEN,' +
    'WHERE,WHILE,WITH,WORK,WRITE,YEAR';
end;

function TFDPhysBDEMetadata.GetKind: TFDRDBMSKind;
begin
  // TODO: registrare un RDBMSKind dedicato; per ora "Other"
  Result := TFDRDBMSKinds.Other;
end;

function TFDPhysBDEMetadata.GetIsFileBased: Boolean;
begin
  Result := True;
end;

function TFDPhysBDEMetadata.GetTxSupported: Boolean;
begin
  Result := True;
end;

function TFDPhysBDEMetadata.GetTxNested: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetTxSavepoints: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetTxAutoCommit: Boolean;
begin
  // True: FireDAC NON avvia transazioni automatiche; StartTransaction resta esplicito.
  Result := True;
end;

function TFDPhysBDEMetadata.GetParamNameMaxLength: Integer;
begin
  Result := 64;
end;

function TFDPhysBDEMetadata.GetNameParts: TFDPhysNameParts;
begin
  Result := [npBaseObject, npObject];
end;

function TFDPhysBDEMetadata.GetNameQuoteChar(AQuote: TFDPhysNameQuoteLevel;
  ASide: TFDPhysNameQuoteSide): Char;
begin
  if AQuote = ncDefault then
    Result := '"'
  else
    Result := #0;
end;

function TFDPhysBDEMetadata.GetNameQuotedCaseSensParts: TFDPhysNameParts;
begin
  Result := [];
end;

function TFDPhysBDEMetadata.GetNameQuotedCaseSens(const AName: String;
  APart: TFDPhysNamePart): Boolean;
var
  i: Integer;
begin
  // quota i nomi con caratteri non alfanumerici (es. spazi, punti)
  Result := False;
  for i := 1 to Length(AName) do
    if not CharInSet(AName[i], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then begin
      Result := True;
      Break;
    end;
end;

function TFDPhysBDEMetadata.GetNameCaseSensParts: TFDPhysNameParts;
begin
  Result := [];
end;

function TFDPhysBDEMetadata.GetNameDefLowCaseParts: TFDPhysNameParts;
begin
  Result := [];
end;

function TFDPhysBDEMetadata.GetIdentityInsertSupported: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetNamedParamMark: TFDPhysParamMark;
begin
  Result := prName;
end;

function TFDPhysBDEMetadata.GetPositionedParamMark: TFDPhysParamMark;
begin
  // TQuery del BDE riconosce solo i parametri nominali (:nome): con '?' i
  // comandi generati da FireDAC (INSERT/UPDATE/DELETE) arriverebbero senza
  // parametri e il BDE darebbe "Parameter not set in query string".
  Result := prName;
end;

function TFDPhysBDEMetadata.GetSelectOptions: TFDPhysSelectOptions;
begin
  Result := [];
end;

function TFDPhysBDEMetadata.GetAsyncAbortSupported: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetArrayExecMode: TFDPhysArrayExecMode;
begin
  // FireDAC spezza l'array in blocchi; il Command esegue riga per riga
  Result := aeUpToFirstError;
end;

function TFDPhysBDEMetadata.GetLimitOptions: TFDPhysLimitOptions;
begin
  // Il Local SQL non ha LIMIT/TOP: skip e limite fatti da FireDAC lato client
  Result := [];
end;

function TFDPhysBDEMetadata.GetDefValuesSupported: TFDPhysDefaultValues;
begin
  Result := dvNone;
end;

function TFDPhysBDEMetadata.GetColumnOriginProvided: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetInlineRefresh: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.GetTruncateSupported: Boolean;
begin
  Result := False;
end;

function TFDPhysBDEMetadata.InternalEscapeBoolean(const AStr: String): String;
begin
  if CompareText(AStr, S_FD_True) = 0 then
    Result := 'TRUE'
  else
    Result := 'FALSE';
end;

function TFDPhysBDEMetadata.InternalEscapeFunction(const ASeq: TFDPhysEscapeData): String;
var
  A1, A2, A3: String;
begin
  if Length(ASeq.FArgs) >= 1 then A1 := ASeq.FArgs[0];
  if Length(ASeq.FArgs) >= 2 then A2 := ASeq.FArgs[1];
  if Length(ASeq.FArgs) >= 3 then A3 := ASeq.FArgs[2];
  // Solo funzioni documentate nel Local SQL; le altre -> errore esplicito
  case ASeq.FFunc of
  efUCASE:  Result := 'UPPER(' + A1 + ')';
  efLCASE:  Result := 'LOWER(' + A1 + ')';
  efLTRIM:  Result := 'TRIM(LEADING '' '' FROM ' + A1 + ')';
  efRTRIM:  Result := 'TRIM(TRAILING '' '' FROM ' + A1 + ')';
  efCONCAT: Result := '(' + A1 + ' || ' + A2 + ')';
  efSUBSTRING:
    if Length(ASeq.FArgs) >= 3 then
      Result := 'SUBSTRING(' + A1 + ' FROM ' + A2 + ' FOR ' + A3 + ')'
    else
      Result := 'SUBSTRING(' + A1 + ' FROM ' + A2 + ')';
  efCONVERT:
    begin
      A2 := UpperCase(Trim(A2));
      if A2 = 'INT' then
        A2 := 'INTEGER'
      else if (A2 = 'DATETIME') then
        A2 := 'TIMESTAMP'
      else if (A2 = 'CHAR') or (A2 = 'VARCHAR') or (A2 = 'CHARACTER') then
        A2 := 'CHAR(254)';   // il Local SQL vuole la lunghezza (1..254)
      Result := 'CAST(' + A1 + ' AS ' + A2 + ')';
    end;
  // data e ora: EXTRACT (Local SQL)
  efYEAR:       Result := 'EXTRACT(YEAR FROM ' + A1 + ')';
  efMONTH:      Result := 'EXTRACT(MONTH FROM ' + A1 + ')';
  efDAYOFMONTH: Result := 'EXTRACT(DAY FROM ' + A1 + ')';
  efHOUR:       Result := 'EXTRACT(HOUR FROM ' + A1 + ')';
  efMINUTE:     Result := 'EXTRACT(MINUTE FROM ' + A1 + ')';
  efSECOND:     Result := 'EXTRACT(SECOND FROM ' + A1 + ')';
  else
    UnsupportedEscape(ASeq);
  end;
end;

{ TFDPhysBDECommandGenerator }

function TFDPhysBDECommandGenerator.GetSelectMetaInfo(AKind: TFDPhysMetaInfoKind;
  const ACatalog, ASchema, ABaseObject, AObject, AWildcard: String;
  AObjectScopes: TFDPhysObjectScopes; ATableKinds: TFDPhysTableKinds;
  AOverload: Word): String;
begin
  Result := '';
end;

end.
