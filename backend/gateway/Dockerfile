# --- build stage -------------------------------------------------------------
FROM golang:1.26.5-bookworm@sha256:1ecb7edf62a0408027bd5729dfd6b1b8766e578e8df93995b225dfd0944eb651 AS build
WORKDIR /src

# Dependency manifests are copied first to keep module downloads cached.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/gateway ./cmd/gateway

# --- runtime stage -----------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot@sha256:f5b485ea962d9bd1186b2f6b3a061191539b905b82ec395de78cbfae51f20e35
COPY --from=build /out/gateway /gateway
COPY THIRD_PARTY_NOTICES.md /licenses/THIRD_PARTY_NOTICES.md
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/gateway"]
