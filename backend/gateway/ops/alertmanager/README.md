# KT Wallet Alertmanager policy

`alertmanager.yml` is the receiver-neutral production baseline. It provides:

- severity-aware grouping and repeat intervals;
- a separate low-urgency route for anonymous, untrusted client trends;
- inhibition of lower-severity alerts while the same service/environment has
  a higher-severity incident;
- an Alertmanager inbox and silence API without exposing a public listener.

The checked-in file deliberately contains no notification destination or
credential. An empty receiver is valid Alertmanager configuration, but it does
not page a human. Never put a destination URL or credential in Git, a process
argument or an HTML report.

## External webhook candidate

The repository now provides a deterministic external-webhook renderer instead
of asking an operator to hand-edit a drifting overlay. It keeps `default` and
anonymous `untrusted-client-report` alerts in the local inbox, while routing
`critical` and `warning` alerts to two external receivers backed by the same
root-owned URL file. The generated receivers:

- use Alertmanager's official `webhook_configs.url_file` boundary;
- send both firing and resolved notifications;
- disable redirects so a credential-bearing URL cannot be redirected to a
  different origin;
- cap each notification at 20 alerts and each attempt at 10 seconds;
- preserve the baseline grouping, inhibition and repeat intervals.

The URL file must be an absolute, canonical, non-symlink regular file with no
world permissions: `0400`, `0440`, `0600` or `0640`. It must contain exactly
one bounded, fragment-free HTTPS URL without URL user information. Prefer
root ownership plus a dedicated Alertmanager service group with mode `0440`;
the service identity must be able to traverse the parent directories and read
the file. The renderer creates a mode-`0600` candidate atomically and refuses
to overwrite an existing path or dangling symlink.

Create the URL file with the operator's secret manager or an interactive
root-only editor; do not place its value in shell history. Then render a new
candidate path:

```sh
sudo install -d -o root -g kt-alertmanager -m 0750 \
  /etc/kt-wallet/alertmanager/secrets \
  /etc/kt-wallet/alertmanager/candidates
sudo chown root:kt-alertmanager \
  /etc/kt-wallet/alertmanager/secrets/external-webhook-url
sudo chmod 0440 \
  /etc/kt-wallet/alertmanager/secrets/external-webhook-url
sudo sh ops/render-alertmanager-external.sh \
  /etc/kt-wallet/alertmanager/secrets/external-webhook-url \
  /etc/kt-wallet/alertmanager/candidates/alertmanager.external.candidate.yml
sudo sh ops/verify-alertmanager-external.sh \
  /etc/kt-wallet/alertmanager/candidates/alertmanager.external.candidate.yml \
  /etc/kt-wallet/alertmanager/secrets/external-webhook-url
sudo chown root:kt-alertmanager \
  /etc/kt-wallet/alertmanager/candidates/alertmanager.external.candidate.yml
sudo chmod 0640 \
  /etc/kt-wallet/alertmanager/candidates/alertmanager.external.candidate.yml
```

The example assumes a dedicated host group named `kt-alertmanager`; use the
actual service group chosen by the deployment instead of reusing a broad
application or login group.

If Alertmanager runs in a container, mount both the candidate and URL file
read-only at the exact absolute paths referenced by the candidate. Set the URL
file's group and the container's supplemental group to the same dedicated
numeric GID; the pinned image runs as `nobody`, so a root-only `0400` bind mount
is not a valid production setup. Validate that the actual service identity can
read both files, stage the candidate alongside the previous config, reload
Alertmanager, and send a temporary critical canary. The change is not accepted
until the external system shows both firing and resolved delivery; otherwise
restore the previous config and reload. Source-level validation does not prove
runtime file access or that a human was paged.

Run both checks before deployment:

```sh
sh ops/verify-alertmanager.sh
docker run --rm \
  --entrypoint /bin/amtool \
  -v "$PWD/ops/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  prom/alertmanager@sha256:51a825c2a40acc3e338fdd00d622e01ec090f72be2b3ea46be0839cd47a4d286 \
  check-config /etc/alertmanager/alertmanager.yml
```

`make monitoring-container-audit` additionally renders a secret-free fixture
candidate and verifies its exact four routes with the pinned Alertmanager
0.32.1 `amtool`, including the invariant that an untrusted client report marked
critical still remains local. `make audit` runs two positive and fourteen deterministic
negative cases covering missing/HTTP/hostless/userinfo/fragment/oversized URLs,
symlinks, multiline or over-permissive secret files, unsafe paths, inline URLs,
route drift, accidental overwrite and dangling output symlinks.

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
