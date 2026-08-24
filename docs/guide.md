# Korifi auf kind — Deployment- & Nutzungsanleitung

Vollständige Anleitung: Cloud Foundry (Korifi) lokal auf kind deployen und als
Entwickler nutzen. Alle Schritte entspringen dem verifizierten Stand vom
23.08.2026 (Kubernetes 1.36, Korifi main `273b857a`, gefixtes Deploy-Script).

---

## 1. Architektur — was läuft wo?

```
┌────────────────────────── Linux Host ──────────────────────────┐
│                                                                │
│  /etc/hosts: 127.0.0.1 api.korifi.local                        │
│                                                                │
│  ┌───────────────────── kind cluster "korifi" ──────────────┐  │
│  │                                                          │  │
│  │  Host-Port-Mapping (kind-config):                        │  │
│  │    80   → 32080   (HTTP Apps)                            │  │
│  │    443  → 32443   (HTTPS API + Apps)                     │  │
│  │    30050→ 30050   (Docker Registry)                      │  │
│  │                                                          │  │
│  │  Namespaces & Komponenten:                               │  │
│  │  ├─ korifi-gateway : Contour Gateway + Envoy             │  │
│  │  ├─ korifi         : korifi-api (CF API v3), controllers │  │
│  │  ├─ cf             : Workloads (Orgs/Spaces/Apps),       │  │
│  │  │                   kpack Builds, Droplets              │  │
│  │  ├─ default        : localregistry-docker-registry       │  │
│  │  ├─ kpack          : kpack Controller                    │  │
│  │  └─ cert-manager   : Zertifikate (API, Ingress, Apps)    │  │
│  │                                                          │  │
│  │  Routing:                                                │  │
│  │   api.korifi.local  → Gateway(TLS-Passthrough)           │  │
│  │                      → TLSRoute → korifi-api-svc:443     │  │
│  │   *.apps-127-0-0-1.nip.io → Gateway(TLS-Terminate)       │  │
│  │                      → HTTPRoute → App-Pod               │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

**Wichtige Namen:** Cluster `korifi` · Helm-Release `korifi` · Admin-User
`cf-admin` · Default-Domain `apps-127-0-0-1.nip.io` · ClusterBuilder
`kind-builder` · Registry-Credentials `user`/`password`

---

## 2. Voraussetzungen

| Tool | Geprüft mit | Zweck |
|------|-------------|-------|
| docker + compose | Docker Engine | kind-Nodes, Image-Builds |
| kind | ≥ 0.20 | lokales Kubernetes |
| kubectl | ≥ 1.30 | Cluster-Steuerung |
| helm | ≥ 3.14 | Korifi-Deployment |
| cf CLI | **v8** (`cf version`) | Cloud-Foundry-Client |
| go | ≥ 1.25 | nur fürs Bauen von bin/yq (Script macht das selbst) |

Einmalig einrichten:

```bash
# DNS für die API
echo "127.0.0.1 api.korifi.local" | sudo tee -a /etc/hosts

# cf CLI v8 (Debian/Ubuntu)
wget -qO- https://packages.cloudfoundry.org/debian/cli.cloudfoundry.org.key | sudo gpg --dearmor -o /usr/share/keyrings/cli.cloudfoundry.org.gpg
echo "deb [signed-by=/usr/share/keyrings/cli.cloudfoundry.org.gpg] https://packages.cloudfoundry.org/debian stable main" | sudo tee /etc/apt/sources.list.d/cloudfoundry-cli.list
sudo apt-get update && sudo apt-get install -y cf8-cli
```

---

## 3. Deployment

### 3.1 Der Standardweg

```bash
cd ~/DEV/korifi-on-kind
./start.sh
```

`start.sh` ruft das gefixte `deploy-on-kind.sh` im Korifi-Arbeitsrepo auf
(Default `~/DEV/cfDev/korifi-fixes`, überschreibbar via `KORIFI_REPO=...`)
und erledigt in dieser Reihenfolge:

1. kind-Cluster erstellen (idempotent — existiert er, wird er genutzt)
2. Lokale Registry installieren + **Preflight-Check** (curl aus dem Node,
   Credentials user/password)
3. Dependencies: cert-manager, kpack, Contour, vendierte Calico-Policy
4. Namespaces `cf`, `korifi`, `korifi-gateway`
5. Registry-Secret `image-registry-credentials` im Namespace `cf`
6. Korifi via Helm (offizielle Images von Docker Hub, kein lokaler Build)
7. ClusterBuilder `kind-builder` anlegen und auf Ready warten
8. Contour GatewayClass/NodePort-Params konfigurieren
9. **DNS-Preflight**: prüft, dass `API_SERVER_FQDN` auflöst
10. **Smoke-Test**: pollt `https://<fqdn>:443/v3/info` und gibt die fertigen
    `cf api`/`cf auth`-Befehle aus

Dauer: Erstdeploy ~10–15 min (Image-Pulls dominieren), Folgelaufsätze
~2–3 min. Das Script ist **idempotent** — erneutes Ausführen aktualisiert.

### 3.2 Konfiguration über Umgebungsvariablen

| Variable | Default | Wirkung |
|----------|---------|---------|
| `API_SERVER_FQDN` | `localhost` | FQDN der API; speist Gateway-Listener, externalFQDN und Cert-SAN. Für `api.korifi.local` setzen! |
| `SKIP_DOCKER_BUILD` | *(leer = bauen)* | `=1`: offizielle Images nutzen, kbld/kind-load überspringen (schnellster Weg) |
| `CLUSTER_NAME` | `korifi` | Name des kind-Clusters |
| `KORIFI_REPO` | `../cfDev/korifi-fixes` | Pfad zum Korifi-Klon mit den Fixes |
| `DOCKER_SERVER/USERNAME/PASSWORD` | lokale Registry | eigene externe Registry statt lokal |
| `API_SERVER_PORT` | `443` | Host-Port der API (nur Smoke-Test/Ausgabe) |

Beispiel mit eigenem FQDN:

```bash
echo "127.0.0.1 cf.meine-firma.test" | sudo tee -a /etc/hosts
API_SERVER_FQDN=cf.meine-firma.test ./start.sh
```

### 3.3 Stoppen / Aufräumen

```bash
./stop.sh                 # löscht den kompletten Cluster
./start.sh                # ... und baut ihn identisch wieder auf
```

Alle Daten (Apps, Droplets, Registry-Inhalte) leben im Cluster bzw. in dessen
Volumes und sind mit dem Cluster weg. Ein Neuaufbau dauert ~15 min.

---

## 4. Cloud Foundry nutzen

### 4.1 Verbinden

```bash
cf api https://api.korifi.local:443 --skip-ssl-validation
cf auth cf-admin admin          # Passwort wird ignoriert (K8s-Auth)
```

### 4.2 Orgs & Spaces

```bash
cf create-org test
cf target -o test
cf create-space dev
cf target -o test -s dev
```

Jeder Space ist intern ein Kubernetes-Namespace unter `cf`. Rollen:

```bash
cf set-org-role <user> <org> OrgManager
cf set-space-role <user> <org> <space> SpaceDeveloper
```

### 4.3 Erste App deployen

Minimal-App (Go, eine Datei):

```bash
mkdir -p ~/apps/hello && cd ~/apps/hello
cat > main.go <<'EOF'
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello von Korifi!")
	})
	panic(http.ListenAndServe(":"+port, nil))
}
EOF
cat > go.mod <<'EOF'
module hello

go 1.23
EOF

cf push hello
```

Was dabei passiert:

```
cf push
 ├─ Source hochladen → API
 ├─ kpack Build      → Paketo Go-Buildpack kompiliert im Cluster
 ├─ Droplet          → OCI-Image in die lokale Registry (Port 30050)
 ├─ Pod startet      → StatefulSetRunner/Process
 └─ Route            → hello.apps-127-0-0-1.nip.io (automatisch)
```

Verify:

```bash
cf apps                       # Status started, 1/1 Instanzen
curl http://hello.apps-127-0-0-1.nip.io
```

> Die Domain `*.apps-127-0-0-1.nip.io` löst automatisch auf 127.0.0.1 auf
> (nip.io-Service) — kein /etc/hosts-Eintrag pro App nötig.

### 4.4 Manifest-basiert (wiederholbar)

```yaml
# manifest.yml
applications:
- name: hello
  memory: 256M
  instances: 1
  buildpacks: [paketo-buildpacks/go]
  command: ./hello
  env:
    GOVERSION: go1.23.x
```

```bash
cf push   # liest manifest.yml aus dem cwd
```

Buildpack-Auswahl: ohne Angabe erkennt `kind-builder` automatisch
(Go, Java, Node.js, Ruby, Procfile). Mit `command:` + leerem Procfile-File
läuft praktisch jede statisch gelinkte Binary:

```bash
CGO_ENABLED=0 go build -o app .
echo "app" > Procfile
cf push my-static-app
```

### 4.5 Alltagskommandos

```bash
cf app hello            # Zustand, Routen, letzte Events
cf logs hello --recent  # Log-Historie
cf logs hello           # live streamen (Ctrl-C beendet)
cf scale hello -i 2     # 2 Instanzen
cf scale hello -m 512M  # Memory-Limit
cf restart hello
cf restage hello        # neu bauen (nach Buildpack-Updates)
cf delete hello -f
cf routes               # alle Routen im Space
cf map-route hello meine-domain.test --hostname app   # zusätzliche Route*
cf events hello         # Push/Scale/Restart-Historie
```

\* Eigene Domains brauchen zusätzlich einen `/etc/hosts`- oder DNS-Eintrag
auf 127.0.0.1 und funktionieren nur für HTTP (Port 80), da das Gateway die
HTTPS-Zertifikate pro Default-Domain terminiert.

### 4.6 Environment-Variablen & Health

```bash
cf set-env hello GREETING="Hallo Welt"
cf restart hello
cf curl /v3/apps/<guid>/env    # alle ENV inkl. VCAP_*
```

Health-Check (Default: port-based):

```bash
cf set-health-check hello http --health-check-endpoint /health
cf set-health-check hello process   # nur "Prozess lebt"
```

---

## 5. Troubleshooting — die bekannten Fallstricke

| Symptom | Ursache | Lösung |
|---------|---------|--------|
| `cf api` → `connection EOF` | FQDN löst nicht, oder SNI passt nicht zum Gateway-Listener | Hosts-Eintrag setzen; Script-Fix 7 prüft das vorab (`getent hosts api.korifi.local`) |
| Smoke-Test rot, Pods grün | Gateway-Listener-Hostname ≠ FQDN | `kubectl get gateway korifi -n korifi-gateway -o yaml` → Listener `https-api` muss den FQDN tragen (passiert automatisch bei korrektem `API_SERVER_FQDN`) |
| Build hängt in `staging` | ClusterBuilder nicht ready oder Registry nicht erreichbar | `kubectl get clusterbuilder`; Registry-Check: `docker exec korifi-control-plane curl -u user:password -fsS http://127.0.0.1:30050/v2/` |
| Build-Fehler `401 unauthorized` beim Push | Registry-Credentials falsch | Secret `image-registry-credentials` im Namespace `cf` löschen und Script neu laufen lassen |
| `cf push` hängt bei "Waiting for app to start" | App crasht in der App (nicht Plattform) | `cf logs APP --recent` — meist falscher Port (App MUSS auf `$PORT` hören) |
| Disk läuft voll nach vielen Pushes | Registry sammelt Layer/Droplets | `kubectl exec -n default deploy/localregistry-docker-registry -- /bin/registry garbage-collect /etc/docker/registry/config.yml` (App vorher stoppen); langfristig: GC-Cronjob einplanen |
| Pods CrashLoopBackOff im Namespace korifi | ConfigMap `korifi-api-config` beschädigt (manuelles Editieren) | Nie manuell patchen — Helm-Values nutzen, Release neu deployen |

Diagnose-Griffkasten:

```bash
kubectl get pods -A                          # alles Running?
kubectl get clusterbuilder kind-builder      # Ready True?
kubectl get gateway,httproute,tlsroute -A    # Routing-Objekte
kubectl events -A --for-recent 10m           # frische Warnungen
kubectl logs -n korifi deploy/korifi-api-deployment --tail=50
helm history korifi -n korifi                # Release-Versionen
helm rollback korifi <rev> -n korifi         # zurückrollen
```

---

## 6. Grenzen dieses Setups (bewusst so)

- **Ein Knoten**, keine HA — kind ist eine Entwicklungsumgebung
- `--skip-ssl-validation` nötig, weil selbstsignierte Certs
- Managed Services/Security Groups sind experimental im Chart aktiviert,
  aber hier nicht Teil der Doku
- Kein Monitoring-Stack; Logs nur via `cf logs`/`kubectl logs`

---

## 7. Weiterführend

- Offizielle Doku: https://github.com/cloudfoundry/korifi/tree/main/docs
- CF CLI v8 Referenz: https://docs.cloudfoundry.org/cf-cli/
- Buildpacks: https://paketo.io
- Unsere Fixes: siehe `README.md` und
  `patches/deploy-on-kind-fix-series.patch`
