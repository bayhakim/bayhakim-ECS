# ECS

ECS urun paneli; model, renk, beden, stok, fiyat, resim ve Nebim aciklama/ozellik notu akisini yonetmek icin hazirlandi.

## Calistirma

PowerShell:

```powershell
$env:KANKA_SQL_PASSWORD="ECD_SQL_SIFRESI"
$env:NEBIM_SQL_PASSWORD="NEBIM_SQL_SIFRESI"
$env:KANKA_PANEL_PORT="8827"
.\start-panel.ps1
```

Panel:

```text
http://127.0.0.1:8827/
```

## Ortam Degiskenleri

- `KANKA_SQL_HOST`
- `KANKA_SQL_PORT`
- `KANKA_SQL_USER`
- `KANKA_SQL_PASSWORD`
- `KANKA_PANEL_PORT`
- `NEBIM_SQL_SERVER`
- `NEBIM_SQL_DATABASE`
- `NEBIM_SQL_USER`
- `NEBIM_SQL_PASSWORD`

Sifreleri GitHub'a yazmayin; ortam degiskeni olarak verin.
