# Mini IdM - Infraestructura de Identidad Segura para la FIS

Proyecto individual de Computación Distribuida para construir una infraestructura de identidad **segura, distribuida, observable y tolerante a fallos**. Se integraron OpenLDAP, MIT Kerberos, PKI con OpenSSL, TLS, HAProxy, Apache con SPNEGO, Prometheus y Grafana.

Repositorio: https://github.com/Cesarbmm/mini-idm

## Objetivo

Centralizar las identidades de estudiantes, profesores y empleados de la FIS, autenticar usuarios sin enviar continuamente sus contraseñas y mantener el servicio disponible cuando fallen los servidores principales.

La separación principal es:

```text
Kerberos -> autentica y entrega tickets
LDAP     -> conserva atributos, cuentas y grupos
PKI/TLS  -> cifra y verifica servidores
HAProxy  -> conmuta entre réplicas LDAP
Apache   -> convierte el ticket Kerberos en SSO web
Prometheus/Grafana -> detectan, registran y muestran el estado
```

## Arquitectura

```text
client
  |
  +-- Kerberos ------------------> kdc1 / kdc2
  |
  +-- HTTPS + SPNEGO ------------> edge / Apache
  |                                      |
  |                                      +-- consulta LDAP
  |
  +-- LDAPS ---------------------> edge / HAProxy
                                         |
                                     +---+---+
                                     |       |
                                   ldap1   ldap2

ca -> firma los certificados de LDAP, KDC y portal web
```

| Máquina | IP | Función |
|---|---:|---|
| `ca.fis.epn.ec` | `192.168.56.10` | Autoridad certificadora raíz |
| `idm1.fis.epn.ec` | `192.168.56.11` | LDAP proveedor y KDC primario |
| `idm2.fis.epn.ec` | `192.168.56.12` | LDAP réplica y KDC secundario |
| `edge.fis.epn.ec` | `192.168.56.20` | HAProxy, portal, Prometheus y Grafana |
| `client.fis.epn.ec` | `192.168.56.30` | Cliente de autenticación y pruebas |

- Dominio: `fis.epn.ec`
- Base LDAP: `dc=fis,dc=epn,dc=ec`
- Realm Kerberos: `FIS.EPN.EC`

## Componentes implementados

### PKI y TLS

Se creó una CA raíz ECDSA y se emitieron certificados para `ldap1`, `ldap2`, `kdc1`, `kdc2` y `web`. LDAP funciona mediante LDAPS y el portal mediante HTTPS. Los certificados LDAP incluyen el alias `ldap.fis.epn.edu.ec`, por lo que la validación TLS sigue siendo correcta al cambiar entre réplicas.

### OpenLDAP

El directorio se organizó así:

```text
dc=fis,dc=epn,dc=ec
+-- ou=People
+-- ou=Groups
+-- ou=Services
```

Se almacenan UID, nombre, correo, UID/GID POSIX, home, shell y grupos. Las ACL separan usuarios, administradores y cuentas de servicio.

### Replicación LDAP

`ldap1` funciona como proveedor de escritura y `ldap2` como consumidor de lectura:

```text
ldap1 -- syncrepl sobre LDAPS --> ldap2
```

La réplica conserva una copia actualizada del directorio, pero por sí sola no crea alta disponibilidad. HAProxy agrega el punto de acceso único y decide qué servidor puede responder.

### Kerberos

Se creó el realm `FIS.EPN.EC` con KDC primario y secundario. Existen principals para usuarios, hosts y servicios, incluido:

```text
HTTP/web.fis.epn.ec@FIS.EPN.EC
```

El usuario obtiene un TGT, luego un ticket para el servicio requerido. El KDC secundario puede emitir tickets cuando el primario está detenido. La base se copia periódicamente mediante `kprop` y `kpropd`; no es una replicación instantánea ni multi-master.

### HAProxy

HAProxy publica el endpoint:

```text
ldaps://ldap.fis.epn.edu.ec:636
```

`ldap1` es el backend principal y `ldap2` el respaldo. Los health checks validan TCP, TLS, certificado y respuesta LDAP. El usuario no necesita conocer qué servidor atiende cada conexión.

### Portal HTTPS con SSO

Apache publica:

```text
https://web.fis.epn.ec/fis-idm
```

El acceso usa SPNEGO/GSSAPI. Apache valida el ticket mediante el keytab HTTP, entrega `REMOTE_USER` a la aplicación y el CGI consulta LDAP con una cuenta de solo lectura.

```text
TGT -> ticket HTTP -> Apache/GSSAPI -> REMOTE_USER
    -> consulta LDAP -> nombre, correo, UID, GID y grupos
```

### Monitoreo

Prometheus recopila métricas de nodos, servicios systemd, HAProxy, Apache, LDAP, KDC y portal web. Grafana muestra disponibilidad, latencia, CPU, memoria, disco y alertas.

Se implementaron alertas para caída de LDAP, failover LDAP, caída del KDC, failover Kerberos, portal no disponible y consumo elevado de recursos.

## Resultados experimentales

Corrida final: `20260717T041159Z`

| Prueba | Resultado |
|---|---:|
| Replicación LDAP - creación | **18.4 ms** de media, rango 17-20 ms |
| Replicación LDAP - eliminación | **18.2 ms** de media, rango 17-20 ms |
| LDAP sin TLS | **18.455 ms** media, p95 **22.559 ms**, 100/100 |
| LDAPS directo | **32.949 ms** media, p95 **39.682 ms**, 100/100 |
| LDAPS por HAProxy | **32.043 ms** media, p95 **35.415 ms**, 100/100 |
| Overhead TLS | **+14.494 ms**, aproximadamente **78.5 %** frente a LDAP plano |
| Overhead de HAProxy | **-0.906 ms** frente a LDAPS directo; no fue medible en esta corrida |
| Throughput LDAP HA | **62.729 operaciones/s**, 300/300 exitosas |
| Portal Kerberos | **194.734 ms** media, p95 **217.523 ms**, 100/100 HTTP 200 |
| Throughput del portal | **12.834 solicitudes/s**, 200/200 exitosas |
| Crash de `ldap1` | **100 %** disponible, 107/107; p95 213.584 ms |
| Partición hacia `ldap1` | **100 %** disponible, 179/179; p95 221.335 ms |
| Failover del KDC | **100 %** exitoso, 55/55; p95 1026.439 ms |
| Fallo combinado LDAP + KDC primarios | El portal respondió **HTTP 200** |

### Lectura de los resultados

- La replicación LDAP se mantuvo alrededor de 18 ms en las cinco pruebas.
- TLS añadió cerca de 14.5 ms, pero permitió confidencialidad, integridad y validación del servidor.
- HAProxy no mostró una penalización apreciable; la diferencia menor que cero se considera variación experimental, no una mejora real del proxy.
- El portal es más costoso que una consulta LDAP simple porque combina HTTPS, SPNEGO, Kerberos, CGI y consulta al directorio.
- Durante el crash y la partición de `ldap1` no hubo respuestas fallidas. Sí aparecieron máximos de aproximadamente 2.2 s mientras HAProxy detectaba la caída y cambiaba a `ldap2`.
- El failover Kerberos tampoco produjo fallos. Los picos cercanos a 1 s corresponden al intento sobre `kdc1` antes de continuar con `kdc2`.
- Prometheus registró `LDAPEndpointUnavailable` y `LDAPPrimaryDownFailoverActive`, demostrando que detectó la caída del primario y la continuidad del endpoint HA.
- En el fallo combinado el portal devolvió HTTP 200. El CSV no guardó el tiempo final, por lo que no se reporta una latencia inventada.
- La validación del certificado a +400 días devolvió `OK`; el certificado aún seguía vigente en ese horizonte y esa prueba no llegó a simular su expiración.

Los datos completos están en:

```text
results/final/20260717T041159Z/
```

## Pruebas de fallos

La campaña incluyó:

- caída abrupta de `slapd` mediante `kill -9`;
- partición de red hacia `ldap1` con `iptables`;
- detención del KDC primario;
- obtención de tickets nuevos desde `kdc2`;
- fallo simultáneo de LDAP y KDC primarios;
- validación futura del certificado;
- medición de disponibilidad, latencia, p95 y throughput.

## Estructura del repositorio

```text
inventory/      Inventario de máquinas
pki/            Certificados públicos, perfiles y CRL
ldap/           DIT, ACL, TLS y replicación
kerberos/       Realm, principals y propagación
haproxy/        Balanceo y failover LDAP
web/            Apache, CGI y plantillas del portal
monitoring/     Prometheus, Grafana y alertas
tests/          Pruebas de disponibilidad y rendimiento
results/        Evidencias y métricas
Makefile        Validaciones y smoke tests
```

## Validación

Con la infraestructura desplegada en `edge`:

```bash
make validate
make secrets
make smoke
make test-analyzers
```

- `make validate`: valida HAProxy, Apache, Prometheus, reglas, dashboard y scripts.
- `make secrets`: busca claves privadas y keytabs versionados.
- `make smoke`: comprueba LDAP, portal y monitoreo.
- `make test-analyzers`: valida el analizador de CSV.

## Endpoints

| Servicio | Dirección |
|---|---|
| LDAP HA | `ldaps://ldap.fis.epn.edu.ec:636` |
| Portal | `https://web.fis.epn.ec/fis-idm` |
| Grafana | `http://monitor.fis.epn.ec:3000` |
| Prometheus | `http://monitor.fis.epn.ec:9090` |
| Alertmanager | `http://monitor.fis.epn.ec:9093` |

Los endpoints solo son accesibles dentro de la red privada del laboratorio.

## Seguridad

No se versionan claves privadas, keytabs, contraseñas de servicio, stash del KDC, bases Kerberos ni bases operativas de Prometheus/Grafana.

Se aplicaron TLS, validación de hostname, ACL LDAP, mínimo privilegio, firewall y separación entre cuentas humanas, administrativas y de servicio.

## Limitaciones

- `edge` sigue siendo un punto único de fallo para HAProxy, portal y monitoreo.
- `ldap2` es una réplica de lectura; las escrituras dependen de `ldap1`.
- La propagación Kerberos es periódica y puede retrasar cambios antes de llegar a `kdc2`.
- La CA no está replicada.

## Autor

**César Zapata**  
Escuela Politécnica Nacional - Facultad de Ingeniería de Sistemas

## Uso de ayuda externa

Se utilizó asistencia externa para revisar conceptos, planificar fases, depurar errores y mejorar la documentación. La instalación de las máquinas, configuración, ejecución de pruebas, recopilación de evidencias y validación final fueron realizadas individualmente por el autor.
