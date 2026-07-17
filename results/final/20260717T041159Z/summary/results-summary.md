# Resultados finales Mini IdM

**Corrida:** `20260717T041159Z`

| Experimento | Métrica principal | Resultado |
|---|---|---:|
| Replicación LDAP | Retardo de creación medio | Completar desde CSV |
| Replicación LDAP | Retardo de eliminación medio | Completar desde CSV |
| LDAP sin TLS | Latencia media | Completar |
| LDAPS directo | Latencia media | Completar |
| LDAPS por HAProxy | Latencia media | Completar |
| Overhead TLS | LDAPS menos LDAP plano | Completar |
| Balanceo LDAP | Throughput | Completar |
| Portal Kerberos | Latencia p95 | Completar |
| Portal Kerberos | Throughput | Completar |
| Crash de ldap1 | Disponibilidad | Completar |
| Crash de ldap1 | Recuperación observada | Completar |
| Partición hacia ldap1 | Disponibilidad | Completar |
| Failover KDC | Disponibilidad | Completar |
| Failover KDC | Latencia p95 | Completar |
| Fallo combinado | HTTP final | Completar |
| Fallo combinado | Tiempo autenticación + portal | Completar |

## Interpretación

- LDAP y Kerberos mantienen continuidad mediante sus réplicas.
- HAProxy dirige las lecturas hacia ldap2 cuando ldap1 no está disponible.
- Los clientes obtienen tickets desde kdc2 cuando kdc1 está detenido.
- El portal combina autenticación Kerberos con atributos almacenados en LDAP.
- TLS introduce una sobrecarga medible, pero protege confidencialidad e integridad.
- edge continúa siendo un punto único de fallo para el portal y el balanceador.
