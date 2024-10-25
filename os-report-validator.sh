#!/bin/bash

# Define the input report file
report_file="/opt/atosans/os-checker/system_verification_report.txt"

# Check if the report file exists
if [ ! -f "$report_file" ]; then
    echo "Report file not found at $report_file"
    exit 1
fi

# Initialize counters
total_checks=0
passed_checks=0
failed_checks=0

# Function to escape regex special characters in a string
escape_regex() {
    echo "$1" | sed -e 's/[]\/()$*.^|[]/\\&/g'
}

# Function to check for errors in a section
check_section() {
    section_name="$1"
    shift
    error_patterns=("$@")
    section_passed=true
    error_messages=()

    # Escape special regex characters in section_name
    escaped_section_name=$(escape_regex "$section_name")

    # Extract the section from the report
    section_content=$(awk "/## $escaped_section_name ##/,/Completed: $escaped_section_name/" "$report_file")

    # Check for error patterns
    for pattern in "${error_patterns[@]}"; do
        matches=$(echo "$section_content" | grep -iE "$pattern")
        if [ -n "$matches" ]; then
            # Handle acceptable exceptions
            # ... (No changes needed here)
            section_passed=false
            error_messages+=("$matches")
        fi
    }

    total_checks=$((total_checks + 1))
    if [ "$section_passed" = true ]; then
        passed_checks=$((passed_checks + 1))
        echo "[PASS] $section_name"
    else
        failed_checks=$((failed_checks + 1))
        echo "[FAIL] $section_name"
        echo "  Errors found:"
        for msg in "${error_messages[@]}"; do
            echo "    $msg"
        done
    fi
}

echo "Validation Summary:"
echo "----------------------------------------"

# List of sections to validate
sections=(
    "Filesystems Check"
    "Network Interfaces and IPs"
    "Connectivity Checks"
    "Timezone Configuration"
    "NTP Configuration"
    "Firewall Configuration"
    "Sudoers Configuration"
    "CrowdStrike \\(AV/EDR\\)"
    "AISAAC Agent \\(MDR\\)"
    "Nagios CMF Agents"
    "RSCD \\(TSSA Agent\\)"
    "CyberArk Accounts"
    "Alcatraz Scanner"
    "SOXDB Scanner"
)

# Define error patterns for each section
declare -A error_patterns
error_patterns["Filesystems Check"]="df command not found"
error_patterns["Network Interfaces and IPs"]="Neither ip nor ifconfig commands are available"
error_patterns["Connectivity Checks"]="Connection to .* failed|Connection to .* timed out|failed|error|timed out|nc command not found"
error_patterns["Timezone Configuration"]="failed|error|not found|set to UTC|Unable to determine the current timezone"
error_patterns["NTP Configuration"]="No NTP configuration file found|Neither chronyc nor ntpq commands are available|Default NTP servers found|ATOS NTP servers are not configured"
error_patterns["Firewall Configuration"]="failed|error|not found|ERROR|firewalld is not enabled|No supported firewall management tool found|Management zone is not active|Production zone is not active|No custom services found"
error_patterns["Sudoers Configuration"]="NOPASSWD for wheel or sudo group not found"
error_patterns["CrowdStrike \\(AV/EDR\\)"]="falcon-sensor service not found|Failed to connect to CrowdStrike proxy|failed|error|not found"
error_patterns["AISAAC Agent \\(MDR\\)"]="AISAAC agent service not found|Connection to Paladion gateway on port .* failed or timed out|failed|error|timed out"
error_patterns["Nagios CMF Agents"]="Nagios NaCl cron job not found in nagios user's crontab|Connection to Nagios server failed|Connection to Nagios backup server failed|ASE agent not found"
error_patterns["RSCD \\(TSSA Agent\\)"]="RSCD service not found|RSCD is not listening on port 4750|Proper entry not found in /etc/rsc/users.local|Proper entry not found in /etc/rsc/exports|failed|error|not found"
error_patterns["CyberArk Accounts"]="User atosans not found|User atosadm not found|User .+ is not in group allowssh|User .+ is not in group wheel or sudo|Group allowssh not found"
error_patterns["SOXDB Scanner"]="failed|error|not found|User atosadm not found|Group wheel or sudo not found|Failed to get password aging information"

# Validate each section
for section in "${sections[@]}"; do
    if [ "$section" = "Alcatraz Scanner" ]; then
        # Since findings are expected, consider this section as PASS
        passed_checks=$((passed_checks + 1))
        total_checks=$((total_checks + 1))
        echo "[PASS] $section"
    else
        check_section "$section" "${error_patterns[$section]}"
    fi
done

echo "----------------------------------------"
echo "Total Checks: $total_checks"
echo "Passed Checks: $passed_checks"
echo "Failed Checks: $failed_checks"

if [ "$failed_checks" -eq 0 ]; then
    echo "All checks passed successfully!"
else
    echo "Some checks failed. Please review the report for details."
fi
