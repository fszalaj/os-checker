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
            section_passed=false
            error_messages+=("$matches")
        fi
    done

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

# 1. Timezone Configuration
check_section "Timezone Configuration" "failed|error|not found"

# 2. NTP Configuration
check_section "NTP Configuration" "failed|error|not found"

# 3. Firewall Configuration
check_section "Firewall Configuration" "failed|error|not found|ERROR"

# 4. CrowdStrike (AV/EDR)
check_section "CrowdStrike (AV/EDR)" "rfm-state=false|failed|error|not found"

# 5. AISAAC Agent (MDR)
check_section "AISAAC Agent (MDR)" "AISAAC agent service not found|failed|error|timed out"

# 6. Nagios CMF Agents
check_section "Nagios CMF Agents" "Nagios NaCl cron job not found|Connection to Nagios server failed|Connection to Nagios backup server failed"

# 7. RSCD (TSSA Agent)
check_section "RSCD (TSSA Agent)" "failed|error|not found"

# 8. CyberArk Accounts
check_section "CyberArk Accounts" "Users atosans and atosadm not found"

# 9. Alcatraz Scanner
check_section "Alcatraz Scanner" "failed|error|not found"

# 10. SOXDB Scanner
check_section "SOXDB Scanner" "failed|error|not found|User atosadm not found|Group wheel not found|Failed to get password aging information"

echo "----------------------------------------"
echo "Total Checks: $total_checks"
echo "Passed Checks: $passed_checks"
echo "Failed Checks: $failed_checks"

if [ "$failed_checks" -eq 0 ]; then
    echo "All checks passed successfully!"
else
    echo "Some checks failed. Please review the report for details."
fi
