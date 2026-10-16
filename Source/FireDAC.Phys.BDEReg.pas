{*******************************************************}
{  FireDAC BDE driver (non ufficiale) - registrazione   }
{  design-time del componente TFDPhysBDEDriverLink      }
{*******************************************************}
unit FireDAC.Phys.BDEReg;

interface

procedure Register;

implementation

uses
  System.Classes,
  FireDAC.Phys.BDE;

procedure Register;
begin
  RegisterComponents('FireDAC Links', [TFDPhysBDEDriverLink]);
end;

end.
