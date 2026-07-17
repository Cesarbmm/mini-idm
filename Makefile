.RECIPEPREFIX := >

.PHONY: help validate secrets smoke test-analyzers

help:
> @echo "Mini IdM"
> @echo "  make validate       Validar configuraciones"
> @echo "  make secrets        Buscar secretos versionados"
> @echo "  make smoke          Pruebas rápidas de disponibilidad"
> @echo "  make test-analyzers Validar scripts Python"

validate:
> sudo haproxy -c -f /etc/haproxy/haproxy.cfg
> sudo apache2ctl configtest
> sudo promtool check config /etc/prometheus/prometheus.yml
> sudo promtool check rules /etc/prometheus/rules/mini-idm-alerts.yml
> python3 -m json.tool monitoring/grafana/dashboards/mini-idm-overview.json >/dev/null
> python3 -m py_compile web/cgi/fis-idm.py
> bash -n tests/final/probe-ldap.sh
> bash -n tests/final/probe-web.sh
> bash -n tests/final/probe-kdc.sh
> bash -n tests/final/throughput.sh

secrets:
> @! git ls-files | grep -E '(\.keytab$$|\.key$$|/stash$$|web-reader\.json$$|replica_datatrans|principal\.dump)' || \
>   (echo "ERROR: archivo sensible versionado" && exit 1)
> @! git grep -nE 'BEGIN (EC |RSA |)PRIVATE KEY' || \
>   (echo "ERROR: clave privada encontrada" && exit 1)
> @echo "No se detectaron claves privadas ni keytabs versionados."

smoke:
> ldapwhoami -x -H ldaps://ldap.fis.epn.edu.ec
> test "$$(curl --silent --output /dev/null --write-out '%{http_code}' https://web.fis.epn.ec/fis-idm)" = "401"
> curl --fail --silent http://127.0.0.1:9090/-/ready >/dev/null
> curl --fail --silent http://127.0.0.1:9093/-/ready >/dev/null
> curl --fail --silent http://127.0.0.1:8404/metrics >/dev/null
> @echo "Smoke test correcto."

test-analyzers:
> python3 -m py_compile tests/final/analyze_csv.py
