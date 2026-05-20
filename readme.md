# ABAP MCP Server v2

Standalone MCP Server für agentives ABAP-Development — 50+ Tools via ADT REST API.

---

## Quickstart

**1. Abhängigkeiten installieren & bauen**
```bash
npm install
npm run build
```

**2. Konfiguration**
```bash
cp .env.example .env
# .env öffnen und SAP_URL, SAP_USER, SAP_PASSWORD eintragen
```

**3. Starten**
```bash
npm start
# oder direkt:
node dist/index.js
```

Wenn alles klappt, siehst du:
```
╔══════════════════════════════════════════╗
║   ABAP MCP Server v2.0 — Extended        ║
╚══════════════════════════════════════════╝
  System  : https://<SAP_SYSTEM>:<PORT>
  User    : <USERNAME>  Client: <CLIENT>  Lang: EN
  Write   : ❌ deaktiviert
  Delete  : ❌ deaktiviert
  Tools   : 13 initial (50 gesamt, deferred)
  Doku    : help.sap.com vlatest
  Prompts : 1 (abap_develop)
  ADT     : ✅ Verbunden
✅ MCP Server läuft auf stdio — bereit für Verbindungen
```

---

## MCP-Client Konfiguration

**Wichtig:** Den Server rufst du normalerweise **nicht manuell** auf — er wird vom MCP-Client (Claude Desktop, Claude Code usw.) automatisch gestartet. Du trägst ihn einmalig in die Config ein:

### Claude Desktop

`%APPDATA%\Claude\claude_desktop_config.json` (Windows):
```json
{
  "mcpServers": {
    "abap": {
      "command": "node",
      "args": ["/pfad/zum/abap-mcp-server/dist/index.js"],
      "env": {
        "SAP_URL": "https://<SAP_SYSTEM>:<PORT>",
        "SAP_USER": "<USERNAME>",
        "SAP_PASSWORD": "<PASSWORD>",
        "SAP_CLIENT": "<CLIENT>",
        "ALLOW_WRITE": "true"
      }
    }
  }
}
```

Dann Claude Desktop neu starten — der Server läuft im Hintergrund sobald du eine Konversation öffnest.

### Claude Code

Im Projektordner `.claude/mcp.json`:
```json
{
  "mcpServers": {
    "abap": {
      "command": "node",
      "args": ["/pfad/zum/abap-mcp-server/dist/index.js"]
    }
  }
}
```

### Cline (VS Code Extension)

In VS Code öffne die Cline Settings (Cline-Symbol → Settings) und gehe zu "MCP Server Configuration". Dort ergänze:

```json
{
  "mcpServers": {
    "ABAP Server": {
      "autoApprove": [
        "search_abap_objects",
        "read_abap_source",
        "where_used",
        "write_abap_source",
        "analyze_abap_context",
        "abap_develop"
      ],
      "disabled": false,
      "timeout": 60,
      "type": "stdio",
      "command": "node",
      "args": [
        "/pfad/zum/abap-mcp-server/dist/index.js"
      ],
      "env": {
        "SAP_URL": "https://<SAP_SYSTEM>:<PORT>",
        "SAP_USER": "<USERNAME>",
        "SAP_PASSWORD": "<PASSWORD>",
        "SAP_CLIENT": "<CLIENT>",
        "SAP_LANGUAGE": "EN",
        "ALLOW_WRITE": "true",
        "ALLOW_DELETE": "false",
        "ALLOW_EXECUTE": "true",
        "BLOCKED_PACKAGES": "SAP,SHD,SMOD",
        "DEFAULT_TRANSPORT": "",
        "SYNTAX_CHECK_BEFORE_ACTIVATE": "true",
        "SAP_ALLOW_UNAUTHORIZED": "true",
        "MAX_DUMPS": "20",
        "DEFER_TOOLS": "true",
        "SAP_ABAP_VERSION": "latest",
        "NODE_TLS_REJECT_UNAUTHORIZED": "0",
        "TAVILY_API_KEY": "<TAVILY_KEY>"
      }
    }
  }
}
```

**Hinweise:**
- `autoApprove` listet die Tools auf, die ohne Benutzerbestätigung ausgeführt werden dürfen. Erweitere die Liste nach Bedarf (z.B. `search_abap_syntax`, `validate_ddic_references`, `get_object_info`, `find_tools`).
- `timeout`: Maximale Laufzeit pro Tool-Aufruf in Sekunden (60 empfohlen für ATC-Checks u.ä.).
- `SAP_ALLOW_UNAUTHORIZED=true` / `NODE_TLS_REJECT_UNAUTHORIZED=0`: Nur bei Self-signed Zertifikaten (DEV-Systeme) setzen!
- `TAVILY_API_KEY`: Optional — wird nur für das `search_sap_web` Tool benötigt. API-Key von [tavily.com](https://tavily.com) beziehen.
- Alle `env`-Variablen können alternativ in einer `.env`-Datei im Server-Verzeichnis konfiguriert werden.

Nach dem Speichern: Cline neu starten oder die MCP-Verbindung neu laden.

---

## Credentials konfigurieren

Der Server lädt die Credentials aus der `.env`-Datei im Projekt:

```bash
# Pflicht
SAP_URL=https://<SAP_SYSTEM>:<PORT>
SAP_USER=<USERNAME>
SAP_PASSWORD=<PASSWORD>
SAP_CLIENT=<CLIENT>
SAP_LANGUAGE=EN

# Sicherheit (alle default-safe)
ALLOW_WRITE=false
ALLOW_DELETE=false
ALLOW_EXECUTE=false
BLOCKED_PACKAGES=SAP,SHD,SMOD

# Optionen
SYNTAX_CHECK_BEFORE_ACTIVATE=true
DEFER_TOOLS=true
SAP_ABAP_VERSION=latest
DEFAULT_TRANSPORT=
MAX_DUMPS=20

# Web Search (optional — für search_sap_web Tool)
TAVILY_API_KEY=
```

Du brauchst die Credentials **nicht** in der MCP-Config zu wiederholen — der Server lädt sie automatisch beim Start.

**Empfohlene Einstellungen pro Umgebung:**

| Variable | DEV | QAS/TEST | PROD |
|---|---|---|---|
| `ALLOW_WRITE` | `true` | `false` | `false` |
| `ALLOW_DELETE` | `false` | `false` | `false` |
| `ALLOW_EXECUTE` | `true` | `false` | `false` |

---

## Warum braucht der Server keinen Port?

Der ABAP MCP Server läuft im **stdio-Modus** (Standard Input/Output), nicht im HTTP-Modus:

- **stdio-Modus** (dieser Server) ✅
  - Der Server kommuniziert über stdin/stdout direkt mit dem Client
  - Kein HTTP-Server, kein TCP-Port nötig
  - Das ist der Standard für MCP (Model Context Protocol)
  - Wird vom Client automatisch gestartet, wenn benötigt
  - Perfekt für: Claude Desktop, Claude Code, Cline

- **HTTP-Modus** (optional, z.B. für externe Clients)
  - Server lauscht auf TCP-Port (z.B. 4847)
  - Clients verbinden sich via HTTP
  - Nötig wenn du mehrere Client-Prozesse hast oder externe Integration brauchst

**Kurz:** Du brauchst keinen Port, weil dein Client (Claude, Cline) den Server direkt startet und über stdio mit ihm spricht. Das ist schneller und sicherer.

---

## Netzwerk-Routing

Das ABAP-System muss vom Rechner, auf dem der MCP-Server läuft, erreichbar sein. Der Server unterstützt vier Routing-Modi — er probiert sie in dieser Reihenfolge und nimmt den **ersten konfigurierten**:

| Priorität | Modus | Wann sinnvoll |
|---|---|---|
| 1 | **BTP Connectivity Proxy** | Hybride CAP-Entwicklung; ABAP-System nur via Cloud Connector erreichbar |
| 2 | **SAProuter NI-Tunnel** | Klassische B2B-VPN, in denen nur Port 3299 von außen offen ist |
| 3 | **HTTP-CONNECT-Proxy** | Corporate-Proxy oder lokaler SSH-/socat-Tunnel |
| 4 | **Direkt HTTPS** | DNS und Firewall erlauben direkten Zugriff |

### Modus 1 — BTP Connectivity Proxy (empfohlen für CAP-Dev)

Routet HTTPS durch den vom BTP-Subaccount vertrauten Cloud Connector. Der MCP-Server piggybacked auf dem lokal weitergeleiteten Connectivity Proxy einer Cloud-Foundry-App, die das `connectivity`-Service gebunden hat.

**Einmalige Vorbereitung:**
```bash
# In separatem Terminal — solange aktiv lassen, wie der MCP läuft.
cf ssh <app> -N -L 20003:connectivityproxy.internal.cf.<region>.hana.ondemand.com:20003

# Im CAP-Projekt: connectivity-Service binden (einmalig)
cds bind --to <connectivity-instance> --credentials '{"onpremise_proxy_host":"localhost"}' --for hybrid
```

**MCP-Konfiguration (`.env` oder MCP-Client `env`):**
```env
SAP_URL=http://mdadneap1.example.com:44300        # http:// auf Port 20003!
SAP_BTP_CONNECTIVITY_PROXY=http://localhost:20003
SAP_BTP_CONNECTIVITY_LOCATION_ID=                  # leer = Default-CC; ggf. mit dem Diagnose-Tool ermitteln
SAP_BTP_CONNECTIVITY_CDS_BIND_FILE=/abs/path/<project>/.cdsrc-private.json
SAP_BTP_CONNECTIVITY_CDS_BIND_NAME=connectivity
SAP_BTP_CF_HOME=/abs/path/<project>                # optional, projekteigene cf-Session
```

Drei JWT-Quellen werden in dieser Reihenfolge probiert: `*_CREDS_FILE` → `*_CDS_BIND_FILE` + `*_CDS_BIND_NAME` → direkte `*_CLIENT_ID/_SECRET/_TOKEN_URL`. Details siehe [`.env.example`](.env.example).

**Hinweise zum Protokoll:**
- Connectivity Proxy auf Port **20003** ist ein HTTP-Forward-Proxy → `SAP_URL` muss `http://...` sein. Der Cloud Connector übernimmt die Backend-TLS.
- Auf Port **20004** spricht der Proxy CONNECT-Tunneling → `SAP_URL=https://...`.
- Der Cloud Connector muss `/sap/bc/adt/*` als Resource freigeben.

**Diagnose:**
```bash
npm run diag:btp-proxy           # End-to-End-Probe gegen SAP_URL/sap/bc/adt/discovery
npm run diag:btp-token           # XSUAA-JWT-Claims anzeigen (subaccount, audience, scope)
npm run diag:btp-destination -- --list             # alle Destinations auflisten
npm run diag:btp-destination -- <DESTINATION_NAME> # Location-ID + virtual host ermitteln
npm run diag:adt                                   # End-to-End-Test via getClient()
```

### Modus 2 — SAProuter NI-Tunnel

```env
SAP_URL=https://<target-host>:<port>
SAP_ROUTER=/H/saproutprd.example.com/S/3299        # oder kurz: host:port
# SAP_ROUTER_PASSWORD=                              # falls saprouttab Passwort verlangt
# SAP_ROUTER_DEBUG=true                             # NI-Frames auf stderr
```
Voraussetzung: der `saprouttab` muss eine Permit-Regel für (deine Quelle → target host:port) enthalten. Sonst antwortet der SAProuter mit `NI_RTERR`. Die Backend-Hosts müssen außerdem HTTPS auf dem genannten Port wirklich akzeptieren (Web Dispatcher oder ICM `icm/server_port`).

### Modus 3 — HTTP-CONNECT-Proxy

```env
SAP_PROXY_URL=http://proxy.corp.example.com:8080    # oder http://localhost:8443 (SSH-Tunnel)
```
Standard-Env-Variablen `HTTPS_PROXY` / `HTTP_PROXY` werden ebenfalls honoriert.

### Modus 4 — Direkt HTTPS

Keine zusätzlichen Variablen. Falls das Backend ein selbst signiertes Zertifikat hat, zusätzlich `SAP_ALLOW_UNAUTHORIZED=true` (nur DEV-Systeme).

### Was NICHT in `SAP_URL` gehört
- **SAProuter-Routes** (`/H/.../S/...`): SAProuter spricht SAP-NI-Binärprotokoll, nicht HTTP. Gehört in `SAP_ROUTER`.
- **Cloud-Connector-virtual-host-only-Pfade**: das ist die `SAP_URL`. Der Pfad-Präfix-Mapping macht der Cloud Connector.

---

## Troubleshooting

**"ADT Fehler: User ist currently editing..."**
- Der Server versucht, eine Datei zu sperren, die schon gesperrt ist (z.B. von einem vorherigen Fehler).
- Lösung: SAP Studio öffnen und die Lock-Session beenden, oder Server neu starten.

**Include-Aktivierungsfehler**
- Includes können nicht standalone aktiviert werden. Der Server erkennt das automatisch und aktiviert die Include im Kontext des Hauptprogramms. Falls nötig, `mainProgram`-Parameter beim Schreiben angeben.

**"SAP_URL, SAP_USER and SAP_PASSWORD must be set"**
- `.env`-Datei fehlt oder Server wurde aus dem falschen Verzeichnis gestartet. Bei Cline: `cwd`-Feld in der MCP-Config prüfen.

**Connection refused / `ENOTFOUND <host>`**
- VPN aktiv? SAP-System erreichbar? URL korrekt? `nslookup <host>` muss von dieser Maschine funktionieren — falls nicht, ist es kein Codeproblem, sondern DNS/VPN.

**BTP Connectivity Proxy: HTTP 503 "no SAP Cloud Connector matching the requested tunnel"**
- Falsche Subaccount-Audience im JWT (z.B. Service-Key aus anderem Subaccount) oder fehlende/falsche `SAP_BTP_CONNECTIVITY_LOCATION_ID`.
- `npm run diag:btp-token` zeigt die `zid` (Subaccount-ID) und `aud` des Tokens an.
- `npm run diag:btp-destination -- --list` zeigt alle in deinem Subaccount konfigurierten Location-IDs.

**BTP Connectivity Proxy: HTTP 405 "HTTPS proxying is not supported"**
- `SAP_URL` ist `https://...`, aber der Proxy läuft auf dem HTTP-Forward-Port (20003). Entweder `SAP_URL` auf `http://` umstellen oder die SSH-Weiterleitung auf Port 20004 setzen.

**`cf service-key` schlägt fehl (login expired / no org targeted)**
- Der Server gibt eine präzise Fehlermeldung mit `cf`-Befehl-Vorschlag aus. Üblicherweise reicht: `CF_HOME=<projekt> cf login --sso`.

**Self-signed Zertifikat (nur DEV)**
- `SAP_ALLOW_UNAUTHORIZED=true` setzen. Niemals in Produktion!
