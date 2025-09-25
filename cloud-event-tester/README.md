# Cloud Event Tester

A standalone tool for testing cloud events by sending HTTP POST requests to webhook endpoints. Originally based on the e2e-tests from [hw-event-proxy](https://github.com/redhat-cne/hw-event-proxy), this tool has been modified to work as a generic cloud event testing utility.

## Features

- **Basic Testing**: Send individual or multiple event files to a webhook endpoint
- **Performance Testing**: Load test with configurable message rates and duration
- **Flexible Configuration**: Command-line flags and environment variable support
- **Multiple Event Formats**: Supports JSON event files (originally designed for Redfish events but works with any JSON)
- **Docker Support**: Can be run as a container
- **Response Validation**: Optional response checking with different modes

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/jzding/cloud-event-tools.git
cd cloud-event-tools/cloud-event-tester

# Build the tool
make build

# The binary will be available at ./build/cloud-event-tester
```

### Using Docker

```bash
# Build the Docker image
docker build -t cloud-event-tester .

# Run with Docker
docker run --rm cloud-event-tester -help
```

## Usage

### Command Line Options

```bash
./cloud-event-tester [options]
```

**Options:**
- `-url string`: Target webhook URL for cloud events (default "http://localhost:9087/webhook")
- `-rate int`: Average messages per second for performance tests (default 10)
- `-duration int`: Test duration in seconds (default 10)
- `-delay int`: Initial delay in seconds when starting (default 10)
- `-check-resp string`: Check response from server - YES/NO/MULTI_THREAD (default "YES")
- `-with-msg string`: Include message field in events - YES/NO (default "YES")
- `-perf string`: Run performance test - YES/NO (default "NO")
- `-data-dir string`: Directory containing test event files (default "data/")
- `-event-file string`: Specific event file to send (overrides data-dir)
- `-help`: Show help message

### Environment Variables

Environment variables can override command-line flags:

- `TEST_DEST_URL`: Target webhook URL
- `MSG_PER_SEC`: Messages per second
- `TEST_DURATION_SEC`: Test duration in seconds
- `INITIAL_DELAY_SEC`: Initial delay in seconds
- `CHECK_RESP`: Check response (YES/NO/MULTI_THREAD)
- `WITH_MESSAGE_FIELD`: Include message field (YES/NO)
- `PERF`: Performance test mode (YES/NO)
- `LOG_LEVEL`: Log level (debug, info, warn, error)

## Examples

### Basic Testing

Send all event files in the data directory:
```bash
./cloud-event-tester -url http://localhost:8080/webhook
```

Send a specific event file:
```bash
./cloud-event-tester -url http://localhost:8080/webhook -event-file data/TMP0100.json
```

### Performance Testing

Run a performance test with 50 messages per second for 60 seconds:
```bash
./cloud-event-tester -url http://localhost:8080/webhook -perf YES -rate 50 -duration 60
```

Run performance test without checking responses (higher throughput):
```bash
./cloud-event-tester -url http://localhost:8080/webhook -perf YES -rate 100 -duration 30 -check-resp NO
```

### Using Environment Variables

```bash
export TEST_DEST_URL="http://my-webhook-server:8080/events"
export MSG_PER_SEC=25
export TEST_DURATION_SEC=120
export LOG_LEVEL=info

./cloud-event-tester -perf YES
```

### Docker Usage

```bash
# Basic test
docker run --rm -v $(pwd)/data:/app/data cloud-event-tester -url http://host.docker.internal:8080/webhook

# Performance test
docker run --rm cloud-event-tester -url http://host.docker.internal:8080/webhook -perf YES -rate 30 -duration 60
```

## Event Data Format

The tool expects JSON files containing cloud events. The included sample events are in Redfish format, but any JSON structure can be used. Example:

```json
{
  "@odata.context": "/redfish/v1/$metadata#Event.Event",
  "@odata.type": "#Event.v1_3_0.Event",
  "Context": "any string is valid",
  "Events": [
    {
      "EventId": "2162",
      "EventTimestamp": "2021-07-13T15:07:59+0300",
      "EventType": "Alert",
      "Message": "The system board Inlet temperature is less than the lower warning threshold.",
      "MessageId": "TMP0100",
      "Severity": "Warning"
    }
  ],
  "Id": "5e004f5a-e3d1-11eb-ae9c-3448edf18a38",
  "Name": "Event Array"
}
```

## Test Modes

### Basic Test Mode

- Sends each event file sequentially with a 1-second delay
- Reports success/failure for each event
- Provides summary of successful sends

### Performance Test Mode

- Sends events at a specified rate for a configured duration
- Uses a single event file (TMP0100.json by default, or specified with `-event-file`)
- Supports different response checking modes:
  - `YES`: Check each response synchronously
  - `NO`: Send without waiting for response (higher throughput)
  - `MULTI_THREAD`: Check responses in separate goroutines
- Reports total messages sent and average throughput

## Sample Event Files

The `data/` directory contains various sample event files:

- **Temperature Events**: TMP0100.json, TMP0120.json, IDRAC.2.8.TMP0110.json
- **Fan Events**: FAN0001.json
- **Power Events**: PWR1004.json, iLOEvents.0.9.PowerSupplyRemoved.json
- **Memory Events**: MEM0004.json, iLOEvents.2.3.ResourceUpdated.json
- **Storage Events**: STOR1.json
- **Miscellaneous**: RAC1195.json

See `data/README.md` for detailed descriptions of each event type.

## Building and Development

### Prerequisites

- Go 1.20 or later
- Make (optional, for using Makefile)

### Build Commands

```bash
# Format code and build
make build

# Run directly
make run

# Update dependencies
make deps-update

# Run linting (requires golint and golangci-lint)
make lint
```

### Development

The tool is structured as follows:

- `cmd/main.go`: Main application logic
- `data/`: Sample event files
- `scripts/`: Helper scripts for containerized environments
- `Makefile`: Build automation
- `Dockerfile`: Container image definition

## Integration with Testing Frameworks

This tool can be integrated into automated testing pipelines:

1. **Exit Codes**: The tool returns appropriate exit codes for success/failure
2. **Logging**: Structured logging with configurable levels
3. **Docker Support**: Easy integration in containerized environments
4. **Environment Variables**: Configuration through environment for CI/CD

## Migration from hw-event-proxy

If you're migrating from the original hw-event-proxy e2e-tests:

1. **Command Line**: The tool now supports command-line flags in addition to environment variables
2. **Binary Name**: Changed from `redfish-event-test` to `cloud-event-tester`
3. **Enhanced Logging**: Better structured logging and progress reporting
4. **Flexible Event Files**: Can now specify individual event files or use custom data directories
5. **Improved Help**: Built-in help system with `-help` flag

## Contributing

This tool is part of the [cloud-event-tools](https://github.com/jzding/cloud-event-tools) repository. Contributions are welcome!

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
