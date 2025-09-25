FROM golang:1.20-alpine

WORKDIR /app
COPY . .
RUN go build -o cloud-event-tester ./cmd/main.go

ENTRYPOINT ["./scripts/entrypoint.sh"]
