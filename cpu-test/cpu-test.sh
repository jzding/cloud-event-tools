#!/bin/bash

# -------------------------------
# Default values
# -------------------------------
DURATION=$((15 * 60))   # default 15 minutes (in seconds)
INTERVAL=1              # default 1 second
LOG_FILE="cpu-test.log"
CSV_MODE=0
LIVE_CHART=0

# -------------------------------
# Parse parameters
# -------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--duration)
            DURATION=$(( $2 * 60 ))
            shift 2
            ;;
        -i|--interval)
            INTERVAL=$2
            shift 2
            ;;
        -o|--output)
            LOG_FILE="$2"
            shift 2
            ;;
        -c|--csv)
            CSV_MODE=1
            shift 1
            ;;
        -l|--live)
            LIVE_CHART=1
            shift 1
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-d minutes] [-i interval_seconds] [-o outputfile] [-c] [-l]"
            exit 1
            ;;
    esac
done

# -------------------------------
# Auto-discover linuxptp-daemon pod
# -------------------------------
POD=$(oc get pods -n openshift-ptp -l app=linuxptp-daemon \
      -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$POD" ]]; then
    echo "ERROR: No pod found with label app=linuxptp-daemon in openshift-ptp namespace."
    exit 1
fi

# -------------------------------
# Retrieve cluster name
# -------------------------------
CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null)
if [[ -z "$CLUSTER_NAME" ]]; then
    CLUSTER_NAME=$(oc get nodes -o jsonpath='{.items[0].metadata.name}' | cut -d'-' -f1-2)
fi

# -------------------------------
# Retrieve cluster version
# -------------------------------
CLUSTER_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)
[[ -z "$CLUSTER_VERSION" ]] && CLUSTER_VERSION="Unknown"

# -------------------------------
# Retrieve PTP operator version
# -------------------------------
PTP_OPERATOR_VERSION=$(oc get deployment ptp-operator -n openshift-ptp \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | awk -F':' '{print $NF}')
[[ -z "$PTP_OPERATOR_VERSION" ]] && PTP_OPERATOR_VERSION="Unknown"

# -------------------------------
# Retrieve container images
# -------------------------------
IMAGES=$(oc get pod "$POD" -n openshift-ptp -o jsonpath='{range .spec.containers[*]}{.name}{"|"}{.image}{"\n"}{end}')

# -------------------------------
# Prometheus query setup
# -------------------------------
PROM_POD="prometheus-k8s-0"
PROM_NS="openshift-monitoring"
PROM_URL="http://localhost:9090"
QUERY='pod:container_cpu_usage:sum{namespace="openshift-ptp"}'

# -------------------------------
# Print test configuration
# -------------------------------
echo "----------------------------------------------"
echo "CPU Usage Test Configuration"
echo "----------------------------------------------"
echo "Cluster Name:        $CLUSTER_NAME"
echo "Cluster Version:     $CLUSTER_VERSION"
echo "PTP Operator Version: $PTP_OPERATOR_VERSION"
echo "Target Pod:          $POD"
echo "Duration (seconds):  $DURATION"
echo "Interval (seconds):  $INTERVAL"
echo "Output Log File:     $LOG_FILE"
echo "CSV Mode:            $([[ $CSV_MODE -eq 1 ]] && echo Enabled || echo Disabled)"
echo "Live Chart:          $([[ $LIVE_CHART -eq 1 ]] && echo Enabled || echo Disabled)"
echo "PromQL Query:        $QUERY"
echo "CPU Unit:            millicores (m)"
echo "----------------------------------------------"

# -------------------------------
# Ensure logfile exists and add header
# -------------------------------
touch "$LOG_FILE"

if [[ $CSV_MODE -eq 1 ]]; then
    echo "timestamp,cpu_cores" > "$LOG_FILE"
else
    echo "# timestamp cpu_cores" > "$LOG_FILE"
fi

# -------------------------------
# Start live gnuplot chart (optional)
# -------------------------------
if [[ $LIVE_CHART -eq 1 ]]; then
    if command -v gnuplot >/dev/null 2>&1; then
        GNUPLOT_SCRIPT=$(mktemp)

        if [[ $CSV_MODE -eq 1 ]]; then
            cat <<EOF > "$GNUPLOT_SCRIPT"
set terminal qt font "Arial,12"
set title "Live CPU Usage (millicores)"
set xlabel "Time"
set ylabel "CPU (m)"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M:%S"
set grid

while (1) {
    if (system("wc -l < '$LOG_FILE'") < 2) {
        pause $INTERVAL
        continue
    }
    plot "$LOG_FILE" using 1:(\$2*1000) with lines title "CPU (m)"
    pause $INTERVAL
}
EOF
        else
            cat <<EOF > "$GNUPLOT_SCRIPT"
set terminal qt font "Arial,12"
set title "Live CPU Usage (millicores)"
set xlabel "Time"
set ylabel "CPU (m)"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M:%S"
set grid

while (1) {
    if (system("wc -l < '$LOG_FILE'") < 2) {
        pause $INTERVAL
        continue
    }
    plot "$LOG_FILE" using 1:(\$3*1000) with lines title "CPU (m)"
    pause $INTERVAL
}
EOF
        fi

        gnuplot -persist "$GNUPLOT_SCRIPT" &
        GNUPLOT_PID=$!
    else
        echo "gnuplot not found — live chart disabled."
    fi
fi

START=$(date +%s)

# -------------------------------
# Sampling loop with progress indicator
# -------------------------------
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))

    if (( ELAPSED >= DURATION )); then
        break
    fi

    PERCENT=$(( ELAPSED * 100 / DURATION ))
    echo -ne "Progress: ${PERCENT}% (${ELAPSED}s / ${DURATION}s)\r"

    RESULT=$(oc exec "$PROM_POD" -n "$PROM_NS" -- \
        promtool query instant "$PROM_URL" "$QUERY" 2>/dev/null)

    CPU=$(echo "$RESULT" | \
        grep "pod=\"$POD\"" | \
        awk -F '=>' '{print $2}' | \
        awk '{print $1}')

    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    if [[ -n "$CPU" ]]; then
        if [[ $CSV_MODE -eq 1 ]]; then
            echo "$TIMESTAMP,$CPU" >> "$LOG_FILE"
        else
            echo "$TIMESTAMP $CPU" >> "$LOG_FILE"
        fi
    fi

    sleep "$INTERVAL"
done

echo -e "\nData collection complete. Summarizing..."

# -------------------------------
# Summary
# -------------------------------
if [[ $CSV_MODE -eq 1 ]]; then
    CPU_VALUES=$(awk -F',' 'NR>1 {print $2}' "$LOG_FILE")
else
    CPU_VALUES=$(awk 'NR>1 {print $3}' "$LOG_FILE")
fi

MIN=$(echo "$CPU_VALUES" | sort -n | head -1 | awk '{printf "%.3f", $1 * 1000}')
MAX=$(echo "$CPU_VALUES" | sort -n | tail -1 | awk '{printf "%.3f", $1 * 1000}')
AVG=$(echo "$CPU_VALUES" | awk '{sum+=$1} END {if (NR>0) printf "%.3f", (sum/NR)*1000}')

echo "-----------------------------------------------------------"
echo "CPU Usage Summary for pod: $POD"
echo "-----------------------------------------------------------"
echo "Minimum CPU: ${MIN}m"
echo "Maximum CPU: ${MAX}m"
echo "Average CPU: ${AVG}m"
echo "-----------------------------------------------------------"

# -------------------------------
# Export final chart to PNG
# -------------------------------
PNG_FILE="${LOG_FILE%.log}.png"
PNG_FILE="${PNG_FILE%.csv}.png"

if command -v gnuplot >/dev/null 2>&1; then
    GNUPLOT_PNG_SCRIPT=$(mktemp)

    if [[ $CSV_MODE -eq 1 ]]; then
        cat <<EOF > "$GNUPLOT_PNG_SCRIPT"
set terminal pngcairo size 1280,720 enhanced font 'Arial,12'
set output "$PNG_FILE"
set title "CPU Usage (millicores)"
set xlabel "Time"
set ylabel "CPU (m)"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M:%S"
set grid
plot "$LOG_FILE" using 1:(\$2*1000) with lines lw 2 title "CPU (m)"
EOF
    else
        cat <<EOF > "$GNUPLOT_PNG_SCRIPT"
set terminal pngcairo size 1280,720 enhanced font 'Arial,12'
set output "$PNG_FILE"
set title "CPU Usage (millicores)"
set xlabel "Time"
set ylabel "CPU (m)"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M:%S"
set grid
plot "$LOG_FILE" using 1:(\$3*1000) with lines lw 2 title "CPU (m)"
EOF
    fi

    gnuplot "$GNUPLOT_PNG_SCRIPT"
    echo "Chart exported to: $PNG_FILE"
else
    echo "gnuplot not found — PNG export skipped."
fi

# -------------------------------
# Generate HTML report
# -------------------------------
REPORT_FILE="${LOG_FILE%.*}.html"

{
    echo "<!DOCTYPE html>"
    echo "<html><head><meta charset=\"UTF-8\"><title>CPU Usage Report - $POD</title></head><body>"
    echo "<h1>CPU Usage Report</h1>"

    echo "<h2>System Info</h2>"
    echo "<ul>"
    echo "<li><b>Cluster Name:</b> $CLUSTER_NAME</li>"
    echo "<li><b>Cluster Version:</b> $CLUSTER_VERSION</li>"
    echo "<li><b>PTP Operator Version:</b> $PTP_OPERATOR_VERSION</li>"
    echo "</ul>"

    echo "<h2>Test Configuration</h2>"
    echo "<ul>"
    echo "<li><b>Pod:</b> $POD</li>"
    echo "<li><b>Duration (seconds):</b> $DURATION</li>"
    echo "<li><b>Interval (seconds):</b> $INTERVAL</li>"
    echo "<li><b>Log file:</b> $LOG_FILE</li>"
    echo "<li><b>CPU unit:</b> millicores (m)</li>"
    echo "</ul>"

    echo "<h2>CPU Summary</h2>"
    echo "<ul>"
    echo "<li><b>Minimum CPU:</b> ${MIN}m</li>"
    echo "<li><b>Maximum CPU:</b> ${MAX}m</li>"
    echo "<li><b>Average CPU:</b> ${AVG}m</li>"
    echo "</ul>"

    echo "<h2>Container Images (linuxptp-daemon pod)</h2>"
    echo "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\">"
    echo "<tr><th>Container</th><th>Image</th></tr>"
    while IFS='|' read -r cname cimage; do
        [[ -z "$cname" ]] && continue
        echo "<tr><td>${cname}</td><td>${cimage}</td></tr>"
    done <<< "$IMAGES"
    echo "</table>"

    if [[ -f "$PNG_FILE" ]]; then
        echo "<h2>CPU Usage Chart</h2>"
        echo "<img src=\"$(basename "$PNG_FILE")\" alt=\"CPU Usage Chart\" style=\"max-width:100%;height:auto;\"/>"
    fi

    echo "</body></html>"
} > "$REPORT_FILE"

echo "HTML report generated: $REPORT_FILE"

# -------------------------------
# Kill gnuplot if running
# -------------------------------
if [[ -n "$GNUPLOT_PID" ]]; then
    kill "$GNUPLOT_PID" 2>/dev/null
fi

