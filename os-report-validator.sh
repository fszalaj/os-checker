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
    error_pattern="$2"
    section_passed=true
    error_messages=()

    # Escape special regex characters in section_name
    escaped_section_name=$(escape_regex "$section_name")

    # Extract the section from the report
    section_content=$(awk "/## $escaped_section_name ##/,/Completed: $escaped_section_name/" "$report_file")

    # Check for error patterns
    matches=$(echo "$section_content" | grep -iE "$error_pattern")
    if [ -n "$matches" ]; then
        # Handle acceptable exceptions
        if [ "$section_name" = "Alcatraz Scanner" ]; then
            # Exclude expected findings
            :
        else
            section_passed=false
            error_messages+=("$matches")
        fi
    fi

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

# List of sections to validate and their error patterns
sections=(
    "Filesystems Check|df command not found"
    "Network Interfaces and IPs|Neither ip nor ifconfig commands are available"
    "Connectivity Checks|Connection to .* failed|Connection to .* timed out|failed|error|timed out|nc command not found"
    "Timezone Configuration|failed|error|not found|set to UTC|Unable to determine the current timezone"
    "NTP Configuration|No NTP configuration file found|Neither chronyc nor ntpq commands are available|Default NTP servers found|ATOS NTP servers are not configured"
    "Firewall Configuration|failed|error|not found|ERROR|firewalld is not enabled|No supported firewall management tool found"
    "Sudoers Configuration|NOPASSWD for wheel or sudo group not found"
    "CrowdStrike \\(AV/EDR\\)|falcon-sensor service not found|Failed to connect to CrowdStrike proxy|failed|error|not found"
    "AISAAC Agent \\(MDR\\)|AISAAC agent service not found|Connection to Paladion gateway on port .* failed or timed out|failed|error|timed out"
    "Nagios CMF Agents|Nagios NaCl cron job not found in nagios user's crontab|Connection to Nagios server failed|Connection to Nagios backup server failed|ASE agent not found"
    "RSCD \\(TSSA Agent\\)|RSCD service not found|RSCD is not listening on port 4750|Proper entry not found in /etc/rsc/users.local|Proper entry not found in /etc/rsc/exports|failed|error|not found"
    "CyberArk Accounts|User atosans not found|User atosadm not found|User .+ is not in group allowssh|User .+ is not in group wheel or sudo|Group allowssh not found"
    "Alcatraz Scanner|"
    "SOXDB Scanner|failed|error|not found|User atosadm not found|Group wheel or sudo not found|Failed to get password aging information"
)

# Validate each section
for section_info in "${sections[@]}"; do
    section_name="${section_info%%|*}"
    error_pattern="${section_info#*|}"

    if [ "$section_name" = "Alcatraz Scanner" ]; then
        # Since findings are expected, consider this section as PASS
        passed_checks=$((passed_checks + 1))
        total_checks=$((total_checks + 1))
        echo "[PASS] $section_name"
    else
        check_section "$section_name" "$error_pattern"
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
