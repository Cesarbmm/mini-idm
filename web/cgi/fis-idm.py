#!/usr/bin/env python3

from __future__ import annotations

import html
import json
import os
import re
import ssl
import sys
from pathlib import Path

from ldap3 import Connection, NONE, SUBTREE, Server, Tls
from ldap3.utils.conv import escape_filter_chars


CONFIG_PATH = Path("/etc/mini-idm/web-reader.json")


def send_html(status: str, content: str) -> None:
    print(f"Status: {status}")
    print("Content-Type: text/html; charset=utf-8")
    print("Cache-Control: no-store")
    print()
    print(content)


def clean(value: object, default: str = "—") -> str:
    if value is None:
        return default

    if isinstance(value, (list, tuple)):
        text = ", ".join(str(item) for item in value)
    else:
        text = str(value)

    return html.escape(text) if text else default


def attribute(entry: object, name: str) -> object:
    try:
        value = entry[name].value
    except (KeyError, TypeError):
        return None

    return value


def page(
    principal: str,
    uid: str,
    user_entry: object,
    groups: list[str],
) -> str:
    full_name = attribute(user_entry, "cn")
    email = attribute(user_entry, "mail")
    uid_number = attribute(user_entry, "uidNumber")
    gid_number = attribute(user_entry, "gidNumber")
    home = attribute(user_entry, "homeDirectory")
    shell = attribute(user_entry, "loginShell")

    role = ", ".join(groups) if groups else "Sin grupo asignado"

    return f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Identidad FIS</title>
  <style>
    :root {{
      color-scheme: light;
      font-family: Inter, system-ui, sans-serif;
      background: #eef1f5;
      color: #18202b;
    }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
    }}
    main {{
      width: min(760px, calc(100% - 40px));
      background: white;
      border-radius: 18px;
      padding: 32px;
      box-shadow: 0 18px 50px rgba(20, 30, 45, .13);
    }}
    h1 {{
      margin: 0 0 6px;
      font-size: 1.8rem;
    }}
    .subtitle {{
      margin: 0 0 26px;
      color: #5b6574;
    }}
    .status {{
      display: inline-block;
      margin-bottom: 24px;
      padding: 7px 12px;
      border-radius: 999px;
      background: #e8f6ed;
      color: #176638;
      font-weight: 700;
    }}
    dl {{
      display: grid;
      grid-template-columns: 190px 1fr;
      gap: 12px 18px;
      margin: 0;
    }}
    dt {{
      color: #66717f;
      font-weight: 650;
    }}
    dd {{
      margin: 0;
      overflow-wrap: anywhere;
    }}
    footer {{
      margin-top: 28px;
      padding-top: 18px;
      border-top: 1px solid #e4e8ed;
      color: #687381;
      font-size: .9rem;
    }}
    code {{
      background: #f1f3f6;
      padding: 2px 6px;
      border-radius: 5px;
    }}
  </style>
</head>
<body>
<main>
  <div class="status">Autenticación Kerberos válida</div>
  <h1>Portal de identidad FIS</h1>
  <p class="subtitle">
    Datos obtenidos desde el directorio LDAP de alta disponibilidad.
  </p>

  <dl>
    <dt>Principal Kerberos</dt>
    <dd><code>{clean(principal)}</code></dd>

    <dt>UID LDAP</dt>
    <dd>{clean(uid)}</dd>

    <dt>Nombre</dt>
    <dd>{clean(full_name)}</dd>

    <dt>Correo</dt>
    <dd>{clean(email)}</dd>

    <dt>Grupos o rol</dt>
    <dd>{clean(role)}</dd>

    <dt>UID numérico</dt>
    <dd>{clean(uid_number)}</dd>

    <dt>GID numérico</dt>
    <dd>{clean(gid_number)}</dd>

    <dt>Directorio personal</dt>
    <dd>{clean(home)}</dd>

    <dt>Shell</dt>
    <dd>{clean(shell)}</dd>
  </dl>

  <footer>
    HTTPS + Kerberos/SPNEGO + OpenLDAP + HAProxy
  </footer>
</main>
</body>
</html>"""


def main() -> None:
    principal = os.environ.get("REMOTE_USER", "").strip()

    if not principal:
        send_html(
            "401 Unauthorized",
            "<h1>No se recibió una identidad Kerberos.</h1>",
        )
        return

    uid = principal.split("@", 1)[0]

    if "/" in uid or not re.fullmatch(r"[A-Za-z0-9._-]+", uid):
        send_html(
            "403 Forbidden",
            "<h1>El principal no corresponde a un usuario humano.</h1>",
        )
        return

    try:
        config = json.loads(
            CONFIG_PATH.read_text(encoding="utf-8")
        )

        tls = Tls(
            validate=ssl.CERT_REQUIRED,
            version=ssl.PROTOCOL_TLS_CLIENT,
            ca_certs_file=config["ca_file"],
            valid_names=[config["ldap_host"]],
        )

        server = Server(
            config["ldap_host"],
            port=int(config["ldap_port"]),
            use_ssl=True,
            tls=tls,
            get_info=NONE,
            connect_timeout=4,
        )

        connection = Connection(
            server,
            user=config["bind_dn"],
            password=config["password"],
            auto_bind=True,
            raise_exceptions=True,
            receive_timeout=5,
        )

        escaped_uid = escape_filter_chars(uid)

        connection.search(
            search_base=config["people_base"],
            search_filter=(
                f"(&(objectClass=posixAccount)"
                f"(uid={escaped_uid}))"
            ),
            search_scope=SUBTREE,
            attributes=[
                "uid",
                "cn",
                "mail",
                "uidNumber",
                "gidNumber",
                "homeDirectory",
                "loginShell",
            ],
            size_limit=2,
        )

        if len(connection.entries) != 1:
            connection.unbind()
            send_html(
                "404 Not Found",
                "<h1>El principal Kerberos no tiene una identidad LDAP única.</h1>",
            )
            return

        user_entry = connection.entries[0]

        connection.search(
            search_base=config["groups_base"],
            search_filter=(
                f"(&(objectClass=posixGroup)"
                f"(memberUid={escaped_uid}))"
            ),
            search_scope=SUBTREE,
            attributes=["cn"],
        )

        groups = sorted(
            str(entry["cn"].value)
            for entry in connection.entries
            if entry["cn"].value
        )

        connection.unbind()

        send_html(
            "200 OK",
            page(principal, uid, user_entry, groups),
        )

    except Exception as error:
        print(
            f"fis-idm LDAP error: {error}",
            file=sys.stderr,
        )

        send_html(
            "503 Service Unavailable",
            "<h1>No fue posible consultar el directorio de identidad.</h1>",
        )


if __name__ == "__main__":
    main()
