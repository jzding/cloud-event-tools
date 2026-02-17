# CPU Usage Test Script

A diagnostic tool for collecting CPU usage metrics from the **linuxptp-daemon** pod in an OpenShift cluster.
It generates:

- A **log file** (text or CSV)
- An optional **live CPU chart** (gnuplot)
- A **PNG chart**
- A full **HTML report** including:
  - System info (cluster name, version, PTP operator version)
  - Test configuration
  - CPU summary (min/max/avg in millicores)
  - Container images used by the linuxptp-daemon pod
  - Embedded CPU usage chart

This script is designed for performance testing, troubleshooting, and reproducible reporting.

---

## ✨ Features

### ✔ CPU sampling (Prometheus query)
Collects CPU usage every N seconds for a specified duration.

### ✔ Optional live chart (`--live`)
Displays a real‑time CPU usage graph using gnuplot.

### ✔ CSV or text logging
Choose between human‑readable or machine‑friendly formats.

### ✔ Automatic PNG chart export
Generates a high‑resolution CPU usage chart at the end of the test.

### ✔ Automatic HTML report
Includes:
- System info
- Test configuration
- CPU summary
- Container images
- Embedded PNG chart

### ✔ Cluster metadata extraction
Automatically retrieves:
- Cluster name
- Cluster version
- PTP operator version

---

## 🧰 Requirements

- `oc` CLI logged into an OpenShift cluster
- `promtool` available inside the Prometheus pod
- `gnuplot` (optional, required for live chart + PNG export)
- Access to:
  - `openshift-ptp` namespace
  - `openshift-monitoring` namespace

---

## 🚀 Usage

```sh
./cpu-test.sh [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-d, --duration <minutes>` | Duration of the test in minutes (default: 15) |
| `-i, --interval <seconds>` | Sampling interval in seconds (default: 1) |
| `-o, --output <file>` | Output log file (default: cpu-test.log) |
| `-c, --csv` | Enable CSV output instead of text |
| `-l, --live` | Enable live gnuplot chart |
| `-h, --help` | Show usage (if added later) |

---

## 📌 Examples

### 1. Run a 10‑minute test with default interval

```sh
./cpu-test.sh -d 10
```

### 2. Run a 5‑minute test with 2‑second sampling

```sh
./cpu-test.sh -d 5 -i 2
```

### 3. Output to a custom log file

```sh
./cpu-test.sh -o ptp-cpu.log
```

### 4. Generate CSV output

```sh
./cpu-test.sh -c
```

### 5. Enable live chart (requires gnuplot)

```sh
./cpu-test.sh --live
```

### 6. Combine options

```sh
./cpu-test.sh -d 3 -i 1 -c -o results.csv --live
```

---

## 📂 Output Files

After running, the script generates:

| File | Description |
|------|-------------|
| `cpu-test.log` or `.csv` | Raw CPU samples |
| `cpu-test.png` | CPU usage chart (millicores) |
| `cpu-test.html` | Full HTML report |

---

## 📄 HTML Report Contents

The generated report includes:

### **System Info**
- Cluster name
- Cluster version
- PTP operator version

### **Test Configuration**
- Pod name
- Duration
- Interval
- Log file
- CPU unit

### **CPU Summary**
- Minimum CPU (m)
- Maximum CPU (m)
- Average CPU (m)

### **Container Images**
Table of containers + images used by the linuxptp-daemon pod.

### **CPU Usage Chart**
Embedded PNG chart.

---

## 🧪 How It Works

1. Discovers the linuxptp-daemon pod automatically
2. Queries Prometheus for CPU usage using `promtool`
3. Logs CPU values every interval
4. Optionally displays a live chart
5. Computes min/max/avg CPU usage
6. Exports a PNG chart
7. Generates an HTML report with all results

---

## 📝 Notes

- The script assumes the Prometheus pod is named `prometheus-k8s-0`.
  Adjust if your environment differs.
- Live charting requires a GUI environment and gnuplot with Qt support.
- The script is safe to run repeatedly; it overwrites output files.

---

## 📜 License

Use freely within your organization.
Modify as needed for testing or automation.
