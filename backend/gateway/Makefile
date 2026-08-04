GO      ?= go
BINARY  ?= bin/gateway
IMAGE   ?= ktwallet-gateway:latest
PLATFORM ?= linux/amd64
ALERTMANAGER_IMAGE ?= prom/alertmanager@sha256:51a825c2a40acc3e338fdd00d622e01ec090f72be2b3ea46be0839cd47a4d286
PROMETHEUS_IMAGE ?= prom/prometheus:v3.12.0

.PHONY: all build run test race cover vet vuln proxy-guard alertmanager-guard token-risk-matrix-test monitoring-container-audit audit docker docker-audit docker-run clean

all: audit build

build:
	$(GO) build -trimpath -o $(BINARY) ./cmd/gateway

run: build
	./$(BINARY)

test:
	$(GO) test ./... -count=1

race:
	$(GO) test ./... -race -count=1

cover:
	$(GO) test ./... -race -count=1 -coverpkg=./internal/... -coverprofile=coverage.out
	$(GO) tool cover -func=coverage.out | tail -1

vet:
	$(GO) vet ./...

# Pin the scanner version so local and release evidence use the same analyzer.
# The go directive/toolchain floor in go.mod also prevents a vulnerable
# standard library from silently producing a release binary.
vuln:
	$(GO) run golang.org/x/vuln/cmd/govulncheck@v1.6.0 ./...

proxy-guard:
	sh ops/verify-haproxy.sh

alertmanager-guard:
	sh ops/verify-alertmanager.sh
	sh ops/verify-alertmanager_test.sh
	sh ops/verify-alertmanager-external_test.sh

token-risk-matrix-test:
	sh ops/verify-token-risk-matrix_test.sh

monitoring-container-audit: alertmanager-guard
	docker run --rm --entrypoint /bin/amtool \
		-v "$(CURDIR)/ops/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
		$(ALERTMANAGER_IMAGE) check-config /etc/alertmanager/alertmanager.yml
	sh ops/verify-alertmanager-external-container.sh "$(ALERTMANAGER_IMAGE)"
	docker run --rm --entrypoint /bin/promtool \
		-v "$(CURDIR)/ops/prometheus:/work:ro" -w /work \
		$(PROMETHEUS_IMAGE) check rules kt-wallet-gateway-alerts.yml
	docker run --rm --entrypoint /bin/promtool \
		-v "$(CURDIR)/ops/prometheus:/work:ro" -w /work \
		$(PROMETHEUS_IMAGE) test rules kt-wallet-gateway-alerts.test.yml

audit: vet test vuln proxy-guard alertmanager-guard token-risk-matrix-test

docker:
	docker build --platform $(PLATFORM) -t $(IMAGE) .

docker-audit: docker
	GOTOOLCHAIN=go1.26.5+auto $(GO) run github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.2.4 scan image --format=vertical $(IMAGE)

docker-run: docker
	docker run --rm -p 8080:8080 $(IMAGE)

clean:
	rm -rf bin coverage.out
