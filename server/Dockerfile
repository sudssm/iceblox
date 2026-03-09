FROM golang:1.26-alpine AS builder

RUN apk add --no-cache curl unzip make

WORKDIR /app
COPY server/go.mod server/go.sum ./
RUN go mod download

COPY server/ .
COPY Makefile pepper.config ./

RUN make .env

RUN make DATA_DIR=data setup extract && rm -f data/plates.zip

RUN CGO_ENABLED=0 GOOS=linux go build -o /server ./cmd/server/...

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /server /server
COPY --from=builder /app/data /data
COPY --from=builder /app/.env /.env
EXPOSE 80
ENTRYPOINT ["/server"]
CMD ["--plates-file", "/data/plates.txt"]
