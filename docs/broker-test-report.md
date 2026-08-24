# OSB Broker Test — Ergebnis-Report (23.08.2026)

## Testumgebung

| Aspekt | Wert |
|--------|------|
| Repo | github.com/cyrano-janus/osb-broker-go (`main @ 48ae489`) |
| Go | 1.26.0 |
| Build | ✅ `go build` erfolgreich, Binary `broker` |
| Tests | ✅ `go test ./internal/broker/` → ok (Broker-Logik) |

## Funktions-Test: alle OSB-Endpunkte lokal durchgetestet

| Endpunkt | Test | Ergebnis |
|----------|------|----------|
| `GET /v2/catalog` | Katalog abrufen | ✅ 200 — Service `example-service`, Plans `free`/`premium` |
| `PUT /v2/service_instances/{id}` | Provision | ✅ 200 + `dashboard_url` |
| `PUT /v2/service_instances/{id}/service_bindings/{bid}` | Bind | ✅ 200 + Credentials (uri/username/password/host/port/database) |
| `GET .../last_operation` | Statusabfrage | ✅ 200 — `succeeded` |
| `DELETE .../service_bindings/{bid}` | Unbind | ✅ 200 `{}` |
| `DELETE /v2/service_instances/{id}` | Deprovision mit Bindings | ✅ korrekt blockiert: `"instance has existing bindings"` (Gone) |
| `DELETE /v2/service_instances/{id}` | Deprovision nach Unbind | ✅ 200 `{}` |
| `GET /healthz` | Health-Check | ❌ **404 — Endpoint fehlt** |

## Befunde

### Was funktioniert
1. **Vollständiger OSB-Lebenszyklus** provision → bind → unbind → deprovision
2. **Idempotenz**: erneutes Provision/Bind liefert bestehende Ressourcen zurück
3. **Schutz vor verwaisten Bindings**: Deprovision mit offenen Bindings wird
   sauber abgelehnt (410 Gone)
4. **Sync-Modus** (`accepts_incomplete=true` akzeptiert, antwortet synchron)

### Lücken für den Korifi-Einsatz

| # | Problem | Auswirkung auf Korifi |
|---|---------|----------------------|
| 1 | **Kein `/healthz`** | Kubernetes-Liveness/Readiness-Probe schlägt fehl → Pod wird nie Ready |
| 2 | **Keine Basic-Auth** | Korifi sendet Broker-Credentials; ohne Prüfung ist der Broker offen. Fürs lokale Setup ok, aber unsauber |
| 3 | **In-Memory-State** | Bei Pod-Restart sind alle Instanzen/Bindings weg → Korifi sieht Geister-Bindings. Für Demo ok |
| 4 | **Statischer Fake-Katalog + Fake-Credentials** | `example-service` liefert Dummy-Daten; keine echte DB dahinter. Genau das war als Referenz gedacht |
| 5 | **Keine OriginatingIdentity-Auswertung** | Multi-Tenant-Zuordnung fehlt (für lokalen Single-User irrelevant) |
| 6 | **go vet schlägt fehl** | `handlers_test.go` referenziert `b.instances` — Test-Code driftete vom Refactoring ab. Blockt CI |
| 7 | Modul-Pfad `github.com/example/osb-broker` | Sollte auf `github.com/cyrano-janus/osb-broker-go` umgestellt werden |

## Empfohlene Schritte Richtung Korifi-Integration

```
Prio 1 – Deploybar machen:
  [ ] /healthz Endpoint ergänzen (3 Zeilen in main.go/handlers.go)
  [ ] go vet fixen (Test an neues Broker-Struct anpassen)
  [ ] Dockerfile (multi-stage, distroless/alpine)
  [ ] Image bauen + in kind laden

Prio 2 – An Korifi anbinden:
  [ ] Cluster neu aufbauen (./start.sh)
  [ ] Broker als Deployment+Service ins Cluster (Namespace z.B. osb-broker)
  [ ] cf create-service-broker mit Basic-Auth-Credentials
      (--set trustInsecureBrokers=true ist schon aktiviert)
  [ ] cf enable-service-access und cf marketplace zeigen den Katalog

Prio 3 – E2E:
  [ ] cf create-service example-service free mydb
  [ ] cf bind-service app mydb → VCAP_SERVICES prüfen
  [ ] App liest Credentials aus VCAP_SERVICES

Prio 4 – Realität:
  [ ] Statt generateCredentials(): CloudNativePG-Cluster provisionieren
      und dessen Secret lesen (siehe Skill go-service-broker)
```

## Fazit

Der Broker ist als **Referenz-/Demo-Implementierung bereits voll funktionsfähig**
— der komplette OSB-2.17-Zyklus läuft inklusive sinnvoller Fehlerfälle.
Für den Korifi-Einsatz fehlen nur kleine Deploy-Details (`/healthz`, vet-Fix,
Containerimage). Die echte CNPG-Anbindung ist der logische nächste Schritt.
