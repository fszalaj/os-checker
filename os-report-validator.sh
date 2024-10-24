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
            # Check if the matches are acceptable exceptions
            if [ "$section_name" = "Alcatraz Scanner" ]; then
                # Exclude expected findings
                continue
            elif [ "$section_name" = "Connectivity Checks" ]; then
                # Exclude expected failed connections
                if echo "$matches" | grep -Eq "Connection to 155\.45\.244\.104.* failed or timed out"; then
                    continue
                fi
            elif [ "$section_name" = "Firewall Configuration" ]; then
                # Exclude expected warnings and errors
                if echo "$matches" | grep -Eq "(AllowZoneDrifting is enabled|ERROR: NAME_CONFLICT: new_zone\(\): 'Production')"; then
                    continue
                fi
            elif [ "$section_name" = "NTP Configuration" ]; then
                # Exclude known acceptable outputs
                if echo "$matches" | grep -Eq "chronyc command not found"; then
                    section_passed=false
                    error_messages+=("$matches")
                else
                    continue
                fi
            elif [ "$section_name" = "Nagios CMF Agents" ]; then
                # Exclude if cron job is found in nagios user's crontab
                if echo "$matches" | grep -Eq "Nagios NaCl cron job not found in nagios user's crontab"; then
                    section_passed=false
                    error_messages+=("$matches")
                else
                    continue
                fi
            fi
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

# 1. Filesystems Check
check_section "Filesystems Check" "df command not found"

# 2. Network Interfaces and IPs
check_section "Network Interfaces and IPs" "ip command not found"

# 3. Connectivity Checks
check_section "Connectivity Checks" "Connection to .* failed|Connection to .* timed out|failed|error|timed out|nc command not found"

# 4. Timezone Configuration
check_section "Timezone Configuration" "failed|error|not found|set to UTC"

# 5. NTP Configuration
check_section "NTP Configuration" "chronyc command not found|Default NTP servers found|ATOS NTP servers are not configured"

# 6. Firewall Configuration
check_section "Firewall Configuration" "failed|error|not found|ERROR|firewalld is not enabled|Management zone is not active|Production zone is not active|No custom services found"

# 7. Sudoers Configuration
check_section "Sudoers Configuration" "NOPASSWD for wheel group not found"

# 8. CrowdStrike \(AV/EDR\)
check_section "CrowdStrike \(AV/EDR\)" "falcon-sensor service not found|Failed to connect to CrowdStrike proxy|failed|error|not found"

# 9. AISAAC Agent \(MDR\)
check_section "AISAAC Agent \(MDR\)" "AISAAC agent service not found|Connection to Paladion gateway on port .* failed or timed out|failed|error|timed out"

# 10. Nagios CMF Agents
check_section "Nagios CMF Agents" "Nagios NaCl cron job not found in nagios user's crontab|Connection to Nagios server failed|Connection to Nagios backup server failed|ASE agent not found"

# 11. RSCD \(TSSA Agent\)
check_section "RSCD \(TSSA Agent\)" "RSCD service not found|RSCD is not listening on port 4750|Proper entry not found in /etc/rsc/users.local|Proper entry not found in /etc/rsc/exports|failed|error|not found"

# 12. CyberArk Accounts
check_section "CyberArk Accounts" "User atosans not found|User atosadm not found|User .+ is not in group allowssh|User .+ is not in group wheel|Group allowssh not found"

# 13. Alcatraz Scanner
# Since findings are expected, consider this section as PASS
passed_checks=$((passed_checks + 1))
total_checks=$((total_checks + 1))
echo "[PASS] Alcatraz Scanner"

# 14. SOXDB Scanner
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
