# Service-Broker-Integration: Go-Referenz-Broker im Korifi-Marketplace

Stand: 24.08.2026 — vollständiger, verifizierter Weg vom Broker-Image bis zur
sichtbaren Service-Instanz.

## Ergebnis

```
cf marketplace
  offering          plans           description                                            broker
  example-service   free, premium   Example Service for OSB API Reference Implementation   go-reference-broker

cf create-service example-service free my-demo-db → create succeeded ✅
cf create-service-key → liefert Credentials aus VCAP_SERVICES-Format ✅
```

## Architektur

```
cf CLI ──► korifi-api ──► CFServiceBroker-CRD (ns cf)
                              │ korifi-controllers ruft auf:
                              ▼
              http://osb-broker-go.osb.svc.cluster.local/v2/catalog
                              │
                     osb-Broker-Pod (Go, Port 8080)
```

## Schritt für Schritt

### 1. Image bauen & in kind laden

```bash
cd ~/DEV/osb-broker-go
docker build -t osb-broker-go:v1 -f Dockerfile .
kind load docker-image osb-broker-go:v1 --name korifi
```

### 2. Broker deployen

```bash
kubectl apply -f deploy/k8s/broker.yaml     # ns osb, Deployment+Service
kubectl wait --for=condition=available deployment/osb-broker-go -n osb \
  --timeout=120s
```

In-cluster-Check:

```bash
kubectl run t --rm -i --restart=Never --image=curlimages/curl -n osb -- \
  curl -s http://osb-broker-go.osb.svc.cluster.local/healthz
# {"status":"ok"}
```

### 3. ⚠️ Die zentrale Falle: URL-Schema

Korifi ergänzt **kein Schema** und ruft ohne `http://` automatisch
**HTTPS auf Port 443** auf → `connection timed out`, CFServiceBroker bleibt
`Ready=False` (`GetCatalogFailed`).

**Richtig:** Schema explizit angeben:

```bash
cf create-service-broker go-reference-broker user secret123 \
  "http://osb-broker-go.osb.svc.cluster.local"
```

Der Broker-Pod selbst lauscht auf 8080; der ClusterIP-Service mappt 80→8080.
Port 443/TLS wäre nur nötig, wenn man kein `http://` angibt — dann bräuchte
der Broker TLS-Termination.

### 4. Registrierung prüfen

```bash
cf service-brokers
kubectl get cfservicebroker -n cf
# Status muss Ready=True sein (dauert ein paar Sekunden)
```

### 5. Service-Access freigeben

Korifi hält Offerings nach der Broker-Registrierung standardmäßig gesperrt:

```bash
cf service-access                       # zeigt access=none
cf enable-service-access example-service -b go-reference-broker
cf marketplace                          # Offering sichtbar ✅
```

### 6. Lifecycle-Test

```bash
cf target -o test -s dev                # Space-Kontext nötig
cf create-service example-service free my-demo-db
cf services                             # last operation: create succeeded

cf create-service-key my-demo-db demo-key
cf service-key my-demo-db demo-key      # Credentials im VCAP-Format

cf delete-service-key -f my-demo-db demo-key
cf delete-service -f my-demo-db
```

## Troubleshooting

| Symptom | Ursache | Fix |
|---------|---------|-----|
| CFServiceBroker `Ready=False`, Reason `CredentialsSecretNotAvailable` | normal kurz nach Registrierung | wenige Sekunden warten |
| `GetCatalogFailed ... :443: connection timed out` | URL ohne `http://`-Schema | `cf update-service-broker ... "http://..."` |
| Marketplace leer trotz Ready=True | Service-Access nicht enabled | `cf enable-service-access <offering> -b <broker>` |
| Job `service_broker.create~...` bleibt PROCESSING | Controller wartet auf Catalog-Fetch | Controller-Logs: `kubectl logs -n korifi deploy/korifi-controllers-controller-manager` |

## Grenzen des Referenz-Brokers

In-Memory-State (Pod-Restart = Instanzen weg), Fake-Credentials, keine Auth.
Nächster Schritt Richtung echter Services: CloudNativePG statt
`generateCredentials()` — siehe Skill `go-service-broker`.
