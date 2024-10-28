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
skipped_checks=0

# Function to escape regex special characters in a string
escape_regex() {
    echo "$1" | sed -e 's/[]\/()$*.^|[]/\\&/g'
}

# Function to check for errors in a section
check_section() {
    section_name="$1"
    error_pattern="$2"
    skip_pattern="$3"
    section_status="PASS"
    error_messages=()

    # Escape special regex characters in section_name
    escaped_section_name=$(escape_regex "$section_name")

    # Extract the section from the report
    section_content=$(awk "/## $escaped_section_name ##/,/Completed: $escaped_section_name/" "$report_file")

    # Check for skip patterns
    if [ -n "$skip_pattern" ] && echo "$section_content" | grep -iE "$skip_pattern" >/dev/null; then
        section_status="SKIPPED"
    else
        # Check for error patterns
        matches=$(echo "$section_content" | grep -iE "$error_pattern")
        if [ -n "$matches" ]; then
            section_status="FAIL"
            error_messages+=("$matches")
        fi
    fi

    total_checks=$((total_checks + 1))
    if [ "$section_status" = "PASS" ]; then
        passed_checks=$((passed_checks + 1))
        echo "[PASS] $section_name"
    elif [ "$section_status" = "FAIL" ]; then
        failed_checks=$((failed_checks + 1))
        echo "[FAIL] $section_name"
        echo "  Errors found:"
        while read -r line; do
            echo "    $line"
        done <<< "$matches"
    elif [ "$section_status" = "SKIPPED" ]; then
        skipped_checks=$((skipped_checks + 1))
        echo "[SKIPPED] $section_name"
    fi
}

echo "Validation Summary:"
echo "----------------------------------------"

# List of sections to validate and their error patterns
sections=(
    "Filesystems Check|df command not found"
    "Network Interfaces and IPs|Neither ip nor ifconfig commands are available"
    "Connectivity Checks|All Nagios connections failed|Connection to .* failed|Connection to .* timed out|failed|error|timed out|nc command not found"
    "Timezone Configuration|Unable to determine the current timezone"
    "NTP Configuration|Invalid NTP server found|No chrony configuration file found|chronyc command is not available|Unable to determine allowed NTP servers for network zone"
    "Firewall Configuration|failed|error|not found|ERROR|firewalld is not enabled|No supported firewall management tool found"
    "Sudoers Configuration|NOPASSWD entry for .* not found|Sudoers file .* not found"
    "CrowdStrike \\(AV/EDR\\)|falcon-sensor service not found|Failed to connect to CrowdStrike proxy|failed|error|not found"
    "AISAAC Agent \\(MDR\\)|proddefthmdr service not found|proddefthmdr is not enabled|Connection to Paladion Gateway .* failed or timed out|failed|error|timed out|/etc/Paladion/AiSaacServer.conf not found"
    "Nagios CMF Agents|All Nagios connections failed|Nagios NaCl cron job not found in nagios user's crontab|ASE agent not found"
    "RSCD \\(TSSA Agent\\)|RSCD service not found|RSCD is not listening on port 4750|Proper entry not found in /etc/rsc/users.local|Proper entry not found in /etc/rsc/exports|failed|error|not found"
    "CyberArk Accounts|User atosans not found|User atosadm not found|User .+ is not in group allowssh|User .+ is not in group wheel or sudo|Group allowssh not found"
    "Alcatraz Scanner|Errors during Alcatraz scan:\n.*<ERROR>"
    "SOXDB Scanner|failed|error|not found|User atosadm not found|Group wheel or sudo not found|Failed to get password aging information"
)

# Skip patterns for certain sections
declare -A skip_patterns
skip_patterns["AISAAC Agent \\(MDR\\)"]="proddefthmdr service not found|/etc/Paladion/AiSaacServer.conf not found"

# Validate each section
for section_info in "${sections[@]}"; do
    section_name="${section_info%%|*}"
    error_pattern="${section_info#*|}"
    skip_pattern="${skip_patterns[$section_name]}"

    check_section "$section_name" "$error_pattern" "$skip_pattern"
done

echo "----------------------------------------"
echo "Total Checks: $total_checks"
echo "Passed Checks: $passed_checks"
echo "Failed Checks: $failed_checks"
echo "Skipped Checks: $skipped_checks"

if [ "$failed_checks" -eq 0 ]; then
    echo "All checks passed successfully!"
else
    echo "Some checks failed. Please review the report for details."
fi
