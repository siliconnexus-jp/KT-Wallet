# KT Wallet Alertmanager policy

`alertmanager.yml` is the receiver-neutral production baseline. It provides:

- severity-aware grouping and repeat intervals;
- a separate low-urgency route for anonymous, untrusted client trends;
- inhibition of lower-severity alerts while the same service/environment has
  a higher-severity incident;
- an Alertmanager inbox and silence API without exposing a public listener.

The checked-in file deliberately contains no notification destination or
credential. An empty receiver is valid Alertmanager configuration, but it does
not page a human. Production operators must maintain a root-owned overlay with
the chosen email, incident-management or webhook integration. Prefer the
integration's `*_file` credential option where supported. Never put its value
in Git, a process argument or an HTML report.

Run both checks before deployment:

```sh
sh ops/verify-alertmanager.sh
docker run --rm \
  --entrypoint /bin/amtool \
  -v "$PWD/ops/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager@sha256:51a825c2a40acc3e338fdd00d622e01ec090f72be2b3ea46be0839cd47a4d286 \
  check-config /etc/alertmanager/alertmanager.yml
```

The service must listen only on the monitoring host loopback interface. The
recommended immutable arguments are:

```text
--config.file=/etc/alertmanager/alertmanager.yml
--storage.path=/alertmanager
--data.retention=120h
--web.listen-address=127.0.0.1:9098
--cluster.listen-address=
--enable-feature=utf8-strict-mode
--silences.max-silences=1000
--silences.max-silence-size-bytes=65536
```

Prometheus should target `127.0.0.1:9098` through its `alerting.alertmanagers`
configuration. Keep the Alertmanager API and UI behind SSH or another
authenticated operator channel; do not publish port 9098.
