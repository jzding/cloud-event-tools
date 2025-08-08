# Version Table Generator

A Python tool that generates a version compatibility table for the cloud-event-proxy project and its dependencies. The tool automatically fetches and analyzes version information from GitHub repositories to create a markdown-formatted table showing the relationships between different versions of components.

## Features

- Fetches version information from GitHub repositories
- Analyzes `go.mod` files to extract dependency versions
- Supports branches, tags, and releases
- Generates a markdown table with version mappings
- Allows custom version notes through a separate file
- Handles rate limiting and pagination for GitHub API requests

## Prerequisites

- Python 3.x
- `requests` library (install via `pip install -r requirements.txt`)
- Internet connection to access GitHub API

## Installation

1. Clone the repository
2. Navigate to the version-table directory
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## Usage

### Basic Usage

Run the script with default settings (targets cloud-event-proxy repository):

```bash
./generate_version_table.py
```

### Custom Repository

Specify a different repository:

```bash
./generate_version_table.py https://github.com/your-org/your-repo
```

### Version Notes

You can add custom notes for specific versions by creating a `version-notes.txt` file in the same directory. The format is:

```
<version> Your note here
```

Example:
```
v0.1.0 Initial release
4.12 OpenShift 4.12 release
```

## Output

The script generates a markdown table in `versions.md` with the following columns:

- cloud-event-proxy: Version/branch/tag name
- golang: Go version used
- rest-api: Version of redhat-cne/rest-api dependency
- sdk-go: Version of redhat-cne/sdk-go dependency
- note: Custom notes from version-notes.txt

Example output:
```markdown
| cloud-event-proxy | golang | rest-api | sdk-go  | note         |
| ----------------- | ------ | -------- | ------- | ------------ |
| main             | 1.19   | v0.1.0   | v0.1.0  |              |
| 4.12             | 1.18   | v0.0.9   | v0.0.9  | OCP 4.12     |
```

## Error Handling

- The script handles various error conditions gracefully
- Errors are logged to stderr
- Missing version-notes.txt file is handled as a warning
- GitHub API errors are caught and reported
- Rate limiting is handled by limiting the number of processed tags

## Limitations

- GitHub API rate limits may affect the number of versions that can be processed
- Only processes the most recent releases and tags to avoid rate limiting
- Requires public repository access or appropriate GitHub API permissions
