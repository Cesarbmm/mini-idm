# Resultados finales Mini IdM

**Corrida:** `20260717T041159Z`

| Experimento | Métrica principal | Resultado |
|---|---|---:|
| Replicación LDAP | Retardo de creación medio | **18.4 ms** (5 pruebas, rango 17-20 ms) |
| Replicación LDAP | Retardo de eliminación medio | **18.2 ms** (5 pruebas, rango 17-20 ms) |
| LDAP sin TLS | Latencia media / p95 | **18.455 ms / 22.559 ms** (100/100) |
| LDAPS directo | Latencia media / p95 | **32.949 ms / 39.682 ms** (100/100) |
| LDAPS por HAProxy | Latencia media / p95 | **32.043 ms / 35.415 ms** (100/100) |
| Overhead TLS | LDAPS directo menos LDAP plano | **+14.494 ms**, aproximadamente **78.5 %** |
| Overhead HAProxy | HAProxy menos LDAPS directo | **-0.906 ms**; no se observó penalización medible en esta corrida |
| Balanceo LDAP | Throughput | **62.729 operaciones/s**, 300/300 exitosas |
| Portal Kerberos | Latencia media / p95 | **194.734 ms / 217.523 ms** (100/100 HTTP 200) |
| Portal Kerberos | Throughput | **12.834 solicitudes/s**, 200/200 exitosas |
| Crash de `ldap1` | Disponibilidad | **100 %**, 107/107 solicitudes exitosas |
| Crash de `ldap1` | Latencia p95 / máxima | **213.584 ms / 2195.415 ms** |
| Partición hacia `ldap1` | Disponibilidad | **100 %**, 179/179 solicitudes exitosas |
| Partición hacia `ldap1` | Latencia p95 / máxima | **221.335 ms / 2160.151 ms** |
| Failover KDC | Disponibilidad | **100 %**, 55/55 tickets obtenidos |
| Failover KDC | Latencia media / p95 / máxima | **168.022 / 1026.439 / 1030.064 ms** |
| Fallo combinado | Resultado del portal | **HTTP 200** con los servicios primarios detenidos |
| Fallo combinado | Tiempo autenticación + portal | No quedó registrado en el CSV final; no se reporta una cifra inventada |
| Validación futura del certificado | Resultado a +400 días | **OK**; el certificado todavía estaba vigente en ese horizonte |

## Interpretación

- La replicación LDAP fue rápida y estable: los cambios aparecieron en la réplica en aproximadamente 18 ms.
- TLS añadió cerca de 14.5 ms frente a LDAP plano, a cambio de confidencialidad, integridad y validación del servidor.
- HAProxy no introdujo una penalización apreciable en esta corrida; su media fue ligeramente menor que la conexión LDAPS directa, diferencia atribuible a variación experimental.
- El portal fue más costoso que una consulta LDAP simple porque combina HTTPS, SPNEGO, validación Kerberos, CGI y consulta al directorio.
- Durante el crash y la partición de `ldap1` no se observaron respuestas fallidas. Sí aparecieron picos cercanos a 2.2 s mientras HAProxy detectaba la caída y conmutaba a `ldap2`.
- El KDC secundario mantuvo 100 % de éxito. Los picos de aproximadamente 1 s corresponden al intento sobre `kdc1` antes de continuar con `kdc2`.
- Prometheus registró las alertas `LDAPEndpointUnavailable` y `LDAPPrimaryDownFailoverActive`, demostrando que el sistema distinguió entre una caída del servidor principal y la continuidad del endpoint HA.
- El fallo combinado devolvió HTTP 200, por lo que `kdc2`, HAProxy y `ldap2` sostuvieron el flujo completo de autenticación e identidad.
- `edge` continúa siendo un punto único de fallo para el balanceador, el portal y el monitoreo.
