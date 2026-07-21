# --- build stage -------------------------------------------------------------
FROM golang:1.26 AS build
WORKDIR /src

# Standard library only; go.mod is copied first to keep layer caching sane if
# dependencies ever appear.
COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/gateway ./cmd/gateway

# --- runtime stage -----------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/gateway /gateway
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/gateway"]
