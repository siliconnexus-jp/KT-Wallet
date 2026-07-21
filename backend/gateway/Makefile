GO      ?= go
BINARY  ?= bin/gateway
IMAGE   ?= ktwallet-gateway:latest

.PHONY: all build run test race cover vet docker docker-run clean

all: vet test build

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

docker:
	docker build -t $(IMAGE) .

docker-run: docker
	docker run --rm -p 8080:8080 $(IMAGE)

clean:
	rm -rf bin coverage.out
