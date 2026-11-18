FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /shop-api .

# Distroless: no shell or package manager for an attacker to use, and it runs as non-root.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /shop-api /shop-api
# Numeric IDs so Kubernetes runAsNonRoot can verify the user (65532 = distroless "nonroot").
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/shop-api"]
