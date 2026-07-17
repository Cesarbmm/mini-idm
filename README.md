# Mini IdM — Infraestructura de Identidad Segura para la FIS

Proyecto individual de Computación Distribuida para diseñar, implementar y evaluar una infraestructura centralizada de identidad para la FIS. El sistema integra **OpenLDAP**, **MIT Kerberos**, **PKI con OpenSSL**, **TLS**, **alta disponibilidad**, **HAProxy**, un portal web con **SSO Kerberos** y monitoreo con **Prometheus y Grafana**.

Repositorio: https://github.com/Cesarbmm/mini-idm

## Objetivo

Centralizar las identidades de estudiantes, profesores y empleados, proteger las comunicaciones, autenticar usuarios mediante tickets Kerberos y mantener continuidad de servicio ante la caída de los servidores principales.

LDAP almacena los atributos de identidad y los grupos; Kerberos realiza la autenticación; la PKI permite validar los servidores y cifrar las comunicaciones; HAProxy y las réplicas proporcionan tolerancia a fallos.

## Arquitectura

```text
client
  │
  ├── Kerberos ───────────────► kdc1 / kdc2
  │
  ├── HTTPS + SPNEGO ─────────► edge / Apache
  │                                  │
  │                                  └── consulta LDAP
  │
  └── LDAPS ──────────────────► edge / HAProxy
                                      │
                                  ┌───┴───┐
                                  ▼       ▼
                                ldap1   ldap2

ca ── emite certificados para LDAP, Kerberos y el portal web
```

| Máquina | IP | Función |
|---|---:|---|
| `ca.fis.epn.ec` | `192.168.56.10` | Autoridad certificadora raíz |
| `idm1.fis.epn.ec` | `192.168.56.11` | LDAP proveedor y KDC primario |
| `idm2.fis.epn.ec` | `192.168.56.12` | LDAP réplica y KDC secundario |
| `edge.fis.epn.ec` | `192.168.56.20` | HAProxy, Apache, portal, Prometheus y Grafana |
| `client.fis.epn.ec` | `192.168.56.30` | Cliente de autenticación y pruebas |

Dominio interno: `fis.epn.ec`  
Raíz LDAP: `dc=fis,dc=epn,dc=ec`  
Realm Kerberos: `FIS.EPN.EC`

## Componentes implementados

### OpenLDAP

El directorio contiene:

```text
dc=fis,dc=epn,dc=ec
├── ou=People
├── ou=Groups
└── ou=Services
```

Se registraron usuarios, grupos POSIX, UID, GID, correo, directorio personal y shell. Las ACL limitan el acceso a contraseñas y separan las cuentas humanas de las cuentas de servicio.

### PKI y TLS

Se creó una CA raíz ECDSA con OpenSSL y se emitieron certificados para:

- `ldap1.fis.epn.ec`
- `ldap2.fis.epn.ec`
- `kdc1.fis.epn.ec`
- `kdc2.fis.epn.ec`
- `web.fis.epn.ec`

LDAP funciona mediante LDAPS y el portal mediante HTTPS. Los certificados de LDAP incluyen el alias `ldap.fis.epn.edu.ec` para mantener una validación TLS correcta durante el failover.

### Kerberos

Se configuró MIT Kerberos con:

- KDC primario en `kdc1.fis.epn.ec`;
- KDC secundario en `kdc2.fis.epn.ec`;
- principals para usuarios, hosts y servicios;
- principal `HTTP/web.fis.epn.ec@FIS.EPN.EC`;
- propagación periódica de la base mediante `kprop` y `kpropd`.

Los clientes pueden obtener tickets desde el KDC secundario cuando el primario está detenido.

### Integración LDAP–Kerberos

Las cuentas LDAP y los principals Kerberos utilizan el mismo identificador de usuario. Kerberos autentica al usuario y LDAP entrega sus atributos.

El flujo del portal es:

```text
Usuario → TGT Kerberos → ticket HTTP → Apache/GSSAPI
        → REMOTE_USER → consulta LDAP → atributos del usuario
```

### Alta disponibilidad LDAP

OpenLDAP utiliza replicación proveedor–consumidor:

```text
ldap1 → syncrepl sobre LDAPS → ldap2
```

`ldap1` es el servidor de escritura y `ldap2` funciona como réplica de lectura. HAProxy publica el endpoint:

```text
ldap.fis.epn.edu.ec:636
```

Cuando `ldap1` no responde, HAProxy dirige las conexiones nuevas hacia `ldap2`.

### Portal web protegido

Apache publica:

```text
https://web.fis.epn.ec/fis-idm
```

El acceso utiliza SPNEGO/GSSAPI y no autenticación Basic. Tras validar el ticket Kerberos, el portal consulta LDAP con una cuenta de servicio de solo lectura y presenta nombre, correo, UID, GID, grupos, home y shell.

### Monitoreo

Prometheus recopila métricas de:

- CPU, memoria, disco y red;
- servicios systemd;
- HAProxy;
- Apache;
- LDAP principal, réplica y alias HA;
- KDC primario y secundario;
- portal HTTPS/Kerberos.

Grafana muestra disponibilidad, latencia, recursos y alertas. Se definieron alertas para caída de LDAP, failover LDAP, caída del KDC, failover Kerberos, portal no disponible y consumo elevado de recursos.

## Pruebas realizadas

La campaña final incluye:

- retardo de replicación LDAP;
- latencia LDAP sin TLS, LDAPS directo y LDAPS por HAProxy;
- throughput LDAP y del portal;
- caída abrupta de `slapd` con `kill -9`;
- partición de red mediante `iptables`;
- detención del KDC primario;
- fallo combinado de LDAP y Kerberos primarios;
- validación de certificados ante una fecha futura;
- disponibilidad, latencia media, p95, fallos y recuperación.

Las evidencias y resultados se encuentran en:

```text
results/final/
results/phase7/
results/phase8/
results/phase9/
```

La corrida final registrada es:

```text
20260717T041159Z
```

## Estructura del repositorio

```text
inventory/          Inventario de máquinas
pki/                Certificados públicos, perfiles y CRL
ldap/               DIT, ACL, TLS y replicación
kerberos/           Realm, principals y propagación
haproxy/            Balanceo y failover LDAP
web/                Apache, CGI y plantillas del portal
monitoring/         Prometheus, Grafana, exportadores y alertas
tests/              Pruebas de HA y rendimiento
results/            Evidencias y resultados experimentales
Makefile            Validación y pruebas rápidas
```

## Requisitos

- VirtualBox
- Ubuntu 24.04 LTS
- OpenLDAP
- MIT Kerberos
- OpenSSL
- HAProxy
- Apache 2 con `mod_auth_gssapi`
- Prometheus, Alertmanager y Grafana
- Python 3 con `ldap3`

Las máquinas deben resolver correctamente los nombres definidos en `inventory/hosts.txt` y mantener sus relojes sincronizados.

## Uso del repositorio

```bash
git clone https://github.com/Cesarbmm/mini-idm.git
cd mini-idm
```

Las configuraciones se organizan por componente y deben instalarse en la máquina correspondiente. Los secretos reales no forman parte del repositorio.

En `edge`, con la infraestructura desplegada, se pueden ejecutar:

```bash
make validate
make secrets
make smoke
make test-analyzers
```

- `make validate`: valida HAProxy, Apache, Prometheus, alertas, dashboard y scripts.
- `make secrets`: comprueba que no se hayan versionado claves privadas o keytabs.
- `make smoke`: verifica LDAP, portal, Prometheus, Alertmanager y métricas de HAProxy.
- `make test-analyzers`: valida el analizador de resultados.

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

No se versionan:

- claves privadas;
- keytabs;
- contraseñas de cuentas de servicio;
- stash del KDC;
- bases Kerberos;
- base de Grafana;
- datos internos de Prometheus.

Se aplicaron TLS, validación de hostname, ACL LDAP, mínimo privilegio, firewall y separación entre cuentas humanas, administrativas y de servicio.

## Limitaciones

- `edge` sigue siendo un punto único de fallo para HAProxy, el portal y el monitoreo.
- `ldap2` es una réplica de lectura; las escrituras dependen de `ldap1`.
- La propagación Kerberos es periódica y puede existir un retraso antes de que un cambio llegue a `kdc2`.
- La CA no está replicada.

## Autor

**César Zapata**  
Escuela Politécnica Nacional — Facultad de Ingeniería de Sistemas

## Uso de ayuda externa

Se utilizó asistencia externa para revisar conceptos, planificar fases, depurar errores y mejorar la documentación. La instalación, configuración de las máquinas, ejecución de comandos, pruebas, recopilación de evidencias y validación final fueron realizadas de manera individual por el autor.
