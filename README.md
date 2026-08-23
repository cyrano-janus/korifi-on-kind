# korifi-on-kind

Cloud Foundry (Korifi) lokal auf einem kind-Cluster betreiben — mit gefixtem
`deploy-on-kind.sh`, das mehrere Fehler im Upstream-Script behebt.

## Was ist hier anders als upstream?

Das offizielle [`scripts/deploy-on-kind.sh`](https://github.com/cloudfoundry/korifi/blob/main/scripts/deploy-on-kind.sh)
aus cloudfoundry/korifi hat mehrere Probleme, die frische Deployments scheitern
lassen. Diese Repo enthält:

| Datei | Inhalt |
|-------|--------|
| `deploy-on-kind.sh` | Gefixte Version des Scripts |
| `patches/deploy-on-kind-fix-series.patch` | Alle Fixes als Patch-Serie (`git am`-fähig) gegen upstream main |
| `start.sh` | Wrapper: komplettes Deployment in einem Befehl |
| `stop.sh` | Cluster löschen |

### Die 8 Fixes im Überblick

1. **chart_dir-Scope-Bug** — `helm upgrade` referenzierte `$chart_dir` auch bei
   `SKIP_DOCKER_BUILD=1`, obwohl es nur im Build-Zweig gesetzt wurde → Crash.
2. **VERSION-Robustheit** — `git describe` schlägt bei shallow clone/fehlenden Tags fehl → Fallback auf Short-SHA.
3. **Registry-Preflight** — Registry wird nach dem Helm-Deploy aus dem kind-Node heraus per curl geprüft; scheitert sie, gibt es sofort eine klare Fehlermeldung statt kryptischer kpack-EOFs später.
4. **API-FQDN konfigurierbar** (`API_SERVER_FQDN`) — speist Gateway-Listener,
   API-`externalFQDN` und Ingress-Cert-SAN. Default bleibt `localhost`.
5. **DNS-Preflight** — prüft, dass der gewählte FQDN auf dem Host auflöst (z.B.
   via `/etc/hosts`), sonst klare Anleitung statt connection EOF.
6. **Smoke-Test** — pollt `/v3/info` über den kind hostPort-Mapping und gibt die
   fertigen `cf api`/`cf auth`-Befehle aus.
7. **shellcheck SC2064** — Trap-Quoting korrigiert (Expansion zur Signalzeit).
8. **set -u + RETURN-trap** — Trap-Variable darf nicht `local` sein, sonst
   bricht das Script beim Cleanup ab.

Alle Fixes sind einzeln committet und in der Patch-Serie enthalten — geeignet
für spätere upstream-PRs.

## Quickstart

Voraussetzungen: docker, kind, kubectl, helm, cf CLI v8+.

```bash
# 1. Hosts-Eintrag (einmalig)
echo "127.0.0.1 api.korifi.local" | sudo tee -a /etc/hosts

# 2. Deployen (nutzt offizielle Images, kein lokaler Build nötig)
./start.sh

# 3. Verbinden
cf api https://api.korifi.local:443 --skip-ssl-validation
cf auth cf-admin admin
cf create-org test && cf target -o test
cf create-space dev && cf target -o test -s dev
```

### Mit eigenem FQDN

```bash
echo "127.0.0.1 cf.meine-firma.test" | sudo tee -a /etc/hosts
API_SERVER_FQDN=cf.meine-firma.test ./start.sh
```

## Wie es funktioniert

`start.sh` ruft das gefixte `deploy-on-kind.sh` aus einem lokalen Korifi-Klon
auf (Default: `../cfDev/korifi-fixes`, überschreibbar via `KORIFI_REPO`). Das
Script:

1. Erstellt den kind-Cluster (Ports 80/443/30050 gemappt)
2. Installiert die lokale Docker-Registry (NodePort 30050) und prüft sie
3. Installiert cert-manager, kpack, Contour (+ vendierte Calico-Policy)
4. Deployt Korifi via Helm (offizielle Images von Docker Hub)
5. Wartet auf den ClusterBuilder und konfiguriert Contour (GatewayClass)
6. Prüft DNS-Auflösung und macht einen API-Smoke-Test

## Troubleshooting

**`connection EOF` bei `cf api`:**
Hosts-Eintrag fehlt oder FQDN stimmt nicht mit `API_SERVER_FQDN` überein.
Der Preflight (Fix 5) fängt das jetzt mit klarer Meldung ab.

**`401 unauthorized` bei Builds:**
Die lokale Registry erwartet user/password — genau diese Credentials setzt
das Script automatisch. Wenn du eine eigene Registry nutzt, setze
`DOCKER_USERNAME`/`DOCKER_PASSWORD`.

**Smoke-Test schlägt fehl:**
Gateway-Listener-Hostname muss zum FQDN passen und die kind-PortMappings
(443→32443) müssen existieren. Details stehen in der Fehlermeldung des Tests.

## Status

Verifiziert am 23.08.2026 mit Korifi main (`273b857a`), kind v1.x,
Kubernetes 1.36: kompletter Workflow `deploy → cf auth → create-org/space`
grün, Script-Exit 0 inkl. Smoke-Test.

## Lizenz

Fixes unter derselben Lizenz wie cloudfoundry/korifi (Apache-2.0).
