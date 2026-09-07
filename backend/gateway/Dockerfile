# --- build stage -------------------------------------------------------------
FROM golang:1.26.6-bookworm@sha256:116d58cbd88c1297624acc6e967a060012422bacf9930927e23fb719189c6f36 AS build
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
