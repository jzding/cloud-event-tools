#!/usr/bin/env python3

import requests
import re
import sys
from typing import Dict, List, Tuple, Optional

def get_releases(repo_url: str) -> List[Dict]:
    """Fetch release information from GitHub API"""
    api_url = repo_url.replace('github.com', 'api.github.com/repos').rstrip('/')
    releases_url = f"{api_url}/releases"

    try:
        response = requests.get(releases_url)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching releases: {e}", file=sys.stderr)
        return []

def get_tags(repo_url: str) -> List[Dict]:
    """Fetch tag information from GitHub API"""
    api_url = repo_url.replace('github.com', 'api.github.com/repos').rstrip('/')
    tags_url = f"{api_url}/tags"

    try:
        response = requests.get(tags_url)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching tags: {e}", file=sys.stderr)
        return []

def get_branches(repo_url: str) -> List[Dict]:
    """Fetch branch information from GitHub API"""
    api_url = repo_url.replace('github.com', 'api.github.com/repos').rstrip('/')
    branches_url = f"{api_url}/branches"

    all_branches = []
    page = 1

    try:
        while True:
            response = requests.get(branches_url, params={'page': page, 'per_page': 100})
            response.raise_for_status()

            branches = response.json()
            if not branches:
                break

            all_branches.extend(branches)
            page += 1

        return all_branches
    except requests.RequestException as e:
        print(f"Error fetching branches: {e}", file=sys.stderr)
        return []

def get_go_mod_content(repo_url: str, ref: str) -> Optional[str]:
    """Fetch go.mod content for a specific release/tag"""
    api_url = repo_url.replace('github.com', 'api.github.com/repos').rstrip('/')
    go_mod_url = f"{api_url}/contents/go.mod?ref={ref}"

    try:
        response = requests.get(go_mod_url)
        response.raise_for_status()

        import base64
        content_data = response.json()
        if content_data.get('encoding') == 'base64':
            return base64.b64decode(content_data['content']).decode('utf-8')
        else:
            return content_data.get('content', '')
    except requests.RequestException as e:
        print(f"Error fetching go.mod for {ref}: {e}", file=sys.stderr)
        return None

def parse_go_mod(content: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Parse go.mod content to extract golang, rest-api, and sdk-go versions"""
    if not content:
        return None, None, None

    golang_version = None
    rest_api_version = None
    sdk_go_version = None

    # Extract golang version (go directive)
    go_match = re.search(r'^go\s+(\d+\.\d+(?:\.\d+)?)', content, re.MULTILINE)
    if go_match:
        golang_version = go_match.group(1)

    # Extract rest-api version
    rest_api_match = re.search(r'github\.com/redhat-cne/rest-api\s+(v[\d\.]+)', content, re.MULTILINE)
    if rest_api_match:
        rest_api_version = rest_api_match.group(1)

    # Extract sdk-go version
    sdk_go_match = re.search(r'github\.com/redhat-cne/sdk-go\s+(v[\d\.]+)', content, re.MULTILINE)
    if sdk_go_match:
        sdk_go_version = sdk_go_match.group(1)

    return golang_version, rest_api_version, sdk_go_version

def get_main_branch_info(repo_url: str) -> Tuple[Optional[str], Optional[str], Optional[str]]:
    """Get version information from main branch"""
    return parse_go_mod(get_go_mod_content(repo_url, "main"))

def normalize_version_name(tag_name: str) -> str:
    """Normalize tag/release names for display"""
    # Remove 'v' prefix if present
    if tag_name.startswith('v'):
        return tag_name[1:]
    return tag_name

def load_version_notes(notes_file: str = "version-notes.txt") -> Dict[str, str]:
    """Load version notes from file"""
    notes = {}
    try:
        with open(notes_file, 'r') as f:
            for line in f:
                parts = line.strip().split(maxsplit=1)
                if len(parts) == 2:
                    version = parts[0]
                    note = parts[1]
                    notes[version] = note
    except FileNotFoundError:
        print(f"Warning: {notes_file} not found", file=sys.stderr)
    except Exception as e:
        print(f"Error reading {notes_file}: {e}", file=sys.stderr)
    return notes

def generate_version_table(repo_url: str = "https://github.com/redhat-cne/cloud-event-proxy") -> str:
    """Generate markdown table with version mappings"""

    print("Fetching branches, releases and tags...", file=sys.stderr)
    branches = get_branches(repo_url)
    releases = get_releases(repo_url)
    tags = get_tags(repo_url)

    # Load version notes
    version_notes = load_version_notes()

    # Create a mapping of tag names to release info
    tag_to_release = {rel['tag_name']: rel for rel in releases}

    # Collect version information
    version_data = []
    processed_refs = set()

    # Add main branch first
    print("Processing main branch...", file=sys.stderr)
    golang_ver, rest_api_ver, sdk_go_ver = get_main_branch_info(repo_url)
    if golang_ver or rest_api_ver or sdk_go_ver:
        version_data.append({
            'proxy_version': 'main',
            'golang': golang_ver or '',
            'rest_api': rest_api_ver or '',
            'sdk_go': sdk_go_ver or '',
            'note': ''
        })
    processed_refs.add('main')

    # Process all branches
    print(f"Processing {len(branches)} branches...", file=sys.stderr)
    for branch in branches:
        branch_name = branch['name']
        if branch_name in processed_refs:
            continue

        print(f"Processing branch {branch_name}...", file=sys.stderr)
        golang_ver, rest_api_ver, sdk_go_ver = parse_go_mod(get_go_mod_content(repo_url, branch_name))

        if golang_ver or rest_api_ver or sdk_go_ver:
            version_data.append({
                'proxy_version': branch_name,
                'golang': golang_ver or '',
                'rest_api': rest_api_ver or '',
                'sdk_go': sdk_go_ver or '',
                'note': version_notes.get(branch_name, '')
            })

        processed_refs.add(branch_name)

    # Process official releases (if any)
    print("Processing releases...", file=sys.stderr)
    for release in releases[:10]:  # Limit to recent releases
        tag_name = release['tag_name']
        if tag_name in processed_refs:
            continue

        print(f"Processing release {tag_name}...", file=sys.stderr)
        golang_ver, rest_api_ver, sdk_go_ver = parse_go_mod(get_go_mod_content(repo_url, tag_name))

        if golang_ver or rest_api_ver or sdk_go_ver:
            version_data.append({
                'proxy_version': normalize_version_name(tag_name),
                'golang': golang_ver or '',
                'rest_api': rest_api_ver or '',
                'sdk_go': sdk_go_ver or '',
                'note': version_notes.get(tag_name, '')
            })

        processed_refs.add(tag_name)

    # Process additional tags if needed
    print("Processing tags...", file=sys.stderr)
    for tag in tags[:20]:  # Limit to avoid rate limits
        tag_name = tag['name']
        if tag_name in processed_refs:
            continue

        # Skip if it looks like a version we're not interested in
        if not re.match(r'^(v?[\d\.]+|release-[\d\.]+|4\.\d+)$', tag_name):
            continue

        print(f"Processing tag {tag_name}...", file=sys.stderr)
        golang_ver, rest_api_ver, sdk_go_ver = parse_go_mod(get_go_mod_content(repo_url, tag_name))

        if golang_ver or rest_api_ver or sdk_go_ver:
            version_data.append({
                'proxy_version': normalize_version_name(tag_name),
                'golang': golang_ver or '',
                'rest_api': rest_api_ver or '',
                'sdk_go': sdk_go_ver or '',
                'note': version_notes.get(tag_name, '')
            })

        processed_refs.add(tag_name)

    # Generate markdown table
    if not version_data:
        return "No version data found."

    # Create table header
    table = "| cloud-event-proxy | golang | rest-api | sdk-go  | note         |\n"
    table += "| ----------------- | ------ | -------- | ------- | ------------ |\n"

    # Add rows
    for entry in version_data:
        table += f"| {entry['proxy_version']} | {entry['golang']} | {entry['rest_api']} | {entry['sdk_go']} | {entry['note']} |\n"

    return table

def main():
    if len(sys.argv) > 1:
        repo_url = sys.argv[1]
    else:
        repo_url = "https://github.com/redhat-cne/cloud-event-proxy"

    print(f"Generating version table for {repo_url}...", file=sys.stderr)
    table = generate_version_table(repo_url)
    print(table)

if __name__ == "__main__":
    main()
