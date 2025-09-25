# Cloud Event Tools

A collection of tools for working with cloud events, testing, and analysis.

## Tools

### Cloud Event Tester

A standalone tool for testing cloud events by sending HTTP POST requests to webhook endpoints. Originally based on the e2e-tests from [hw-event-proxy](https://github.com/redhat-cne/hw-event-proxy), this tool has been modified to work as a generic cloud event testing utility.

**Features:**
- Basic and performance testing modes
- Configurable message rates and test duration
- Support for multiple event file formats
- Docker containerization support
- Flexible configuration via command-line flags and environment variables

**Location:** [`cloud-event-tester/`](./cloud-event-tester/)

**Quick Start:**
```bash
cd cloud-event-tester
make build
./build/cloud-event-tester -url http://localhost:8080/webhook -help
```

### Version Table Generator

A Python tool for generating version compatibility tables from release notes and version data.

**Location:** [`version-table/`](./version-table/)

## Getting Started

Each tool is self-contained with its own documentation and build instructions. Navigate to the specific tool directory for detailed usage instructions.

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](./LICENSE) file for details.
