FROM golang:1.26-alpine AS builder

RUN apk add --no-cache curl unzip make

WORKDIR /app
COPY server/go.mod server/go.sum ./
RUN go mod download

COPY server/ .
COPY Makefile pepper.config ./

RUN make .env

# Fetch and extract plate data
RUN mkdir -p data && \
    ZIP_NAME=$(curl -sL "https://www.stopice.net/platetracker/?data=1" \
      | sed -n 's/.*href="\(stopice_platetracker_compiled\/[^"]*\.zip\)".*/\1/p' \
      | head -1) && \
    curl -L "https://www.stopice.net/platetracker/${ZIP_NAME}" -o data/plates.zip && \
    unzip -p data/plates.zip "*.xml" \
      | sed -n 's/.*<vehicle_license>\(.*\)<\/vehicle_license>.*/\1/p' \
      | sed 's/[[:space:]-]//g' \
      | tr '[:lower:]' '[:upper:]' \
      | sort -u \
      | grep -E '^[A-Z0-9]{2,8}$' \
      > data/plates.txt && \
    rm data/plates.zip

RUN CGO_ENABLED=0 GOOS=linux go build -o /server ./cmd/server/...

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /server /server
COPY --from=builder /app/data /data
COPY --from=builder /app/.env /.env
EXPOSE 80
ENTRYPOINT ["/server"]
CMD ["--plates-file", "/data/plates.txt"]
