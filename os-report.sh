#!/bin/bash

# Define the output file path
output_file="/opt/atosans/os-checker/system_verification_report.txt"

# Ensure the directory exists
mkdir -p /opt/atosans/os-checker

# Function to detect OS and version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$NAME|$VERSION_ID"
    else
        os_name=$(uname -s)
        os_version=$(uname -r)
        echo "$os_name|$os_version"
    fi
}

# Get the OS name and version
os_info=$(detect_os)
OS_NAME=$(echo "$os_info" | cut -d'|' -f1)
OS_VERSION=$(echo "$os_info" | cut -d'|' -f2)

# Get the hostname and date
hostname=$(hostname)
current_date=$(date)

# Start the report with hostname, OS, and date
echo "System Verification Report" > "$output_file"
echo "----------------------------------------" >> "$output_file"
echo "Hostname: $hostname" >> "$output_file"
echo "Operating System: $OS_NAME" >> "$output_file"
echo "OS Version: $OS_VERSION" >> "$output_file"
echo "Date: $current_date" >> "$output_file"
echo "----------------------------------------" >> "$output_file"

# Function to append section title
append_title() {
    echo -e "\n## $1 ##" >> "$output_file"
    echo "----------------------------------------" >> "$output_file"
}

# Function to track time for each section
log_time() {
    section="$1"
    start_time=$(date +%s)
    start_time_human=$(date "+%Y-%m-%d %H:%M:%S")
    echo "Starting: $section at $start_time_human"
    echo "----------------------------------------"
    echo "Starting: $section at $start_time_human" >> "$output_file"
    echo "----------------------------------------" >> "$output_file"
}

end_time() {
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "Completed: $section in $duration seconds"
    echo "----------------------------------------"
    echo "Completed: $section in $duration seconds" >> "$output_file"
    echo "----------------------------------------" >> "$output_file"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install utilities if not already installed
install_utilities() {
    log_time "Utilities Installation"
    append_title "Utilities Installation"
    declare -a utilities=("nc" "curl" "telnet" "htop")
    for util in "${utilities[@]}"; do
        if ! command_exists "$util"; then
            echo "$util is not installed. Installing..." >> "$output_file"
            if command_exists apt-get; then
                apt-get update >> "$output_file" 2>&1
                apt-get install -y "$util" >> "$output_file" 2>&1
            elif command_exists yum; then
                yum install -y "$util" >> "$output_file" 2>&1
            elif command_exists zypper; then
                zypper install -y "$util" >> "$output_file" 2>&1
            else
                echo "No suitable package manager found to install $util." >> "$output_file"
            fi
            if command_exists "$util"; then
                echo "$util installed successfully." >> "$output_file"
            else
                echo "Failed to install $util." >> "$output_file"
            fi
        else
            echo "$util is already installed." >> "$output_file"
        fi
    done
    end_time
}

# Install utilities if needed
install_utilities

# Function to check service status
check_service_status() {
    service_name="$1"
    if command_exists systemctl; then
        systemctl status "$service_name" >> "$output_file" 2>&1
        if systemctl is-enabled "$service_name" >/dev/null 2>&1; then
            echo "$service_name is enabled." >> "$output_file"
        else
            echo "$service_name is not enabled." >> "$output_file"
        fi
    elif [ -x "/etc/init.d/$service_name" ]; then
        "/etc/init.d/$service_name" status >> "$output_file" 2>&1
    else
        echo "$service_name service not found." >> "$output_file"
    fi
}

# Function to check firewall status
check_firewall_status() {
    if command_exists firewall-cmd; then
        # firewalld
        echo "Using firewalld..." >> "$output_file"
        # Add firewalld specific checks
        active_zones=$(firewall-cmd --get-active-zones)
        echo "Active zones:" >> "$output_file"
        echo "$active_zones" >> "$output_file"
        # Additional firewalld checks can be added here
    elif command_exists ufw; then
        # UFW (Ubuntu)
        echo "Using UFW..." >> "$output_file"
        ufw status verbose >> "$output_file" 2>&1
    elif command_exists SuSEfirewall2; then
        # SuSEfirewall2 (SLES)
        echo "Using SuSEfirewall2..." >> "$output_file"
        SuSEfirewall2 status >> "$output_file" 2>&1
    else
        echo "No supported firewall management tool found." >> "$output_file"
    fi
}

# Function to check NTP configuration
check_ntp_status() {
    if [ -f /etc/chrony.conf ]; then
        ntp_config_file="/etc/chrony.conf"
    elif [ -f /etc/ntp.conf ]; then
        ntp_config_file="/etc/ntp.conf"
    else
        echo "No NTP configuration file found." >> "$output_file"
        return
    fi

    default_ntp_servers=$(grep -E '^(server|pool) .*ntp.org' "$ntp_config_file")
    if [ -n "$default_ntp_servers" ]; then
        echo "Default NTP servers found in $ntp_config_file. Please remove them." >> "$output_file"
        echo "$default_ntp_servers" >> "$output_file"
    else
        echo "No default NTP servers found in $ntp_config_file." >> "$output_file"
    fi

    atos_ntp_servers=$(grep -E '^server (155\.45|161\.89)' "$ntp_config_file" | awk '{print $2}')
    if [ -n "$atos_ntp_servers" ]; then
        echo "ATOS NTP servers configured:" >> "$output_file"
        echo "$atos_ntp_servers" >> "$output_file"
    else
        echo "ATOS NTP servers are not configured in $ntp_config_file." >> "$output_file"
    fi

    echo "Checking NTP synchronization status..." >> "$output_file"
    if command_exists chronyc; then
        chronyc sources >> "$output_file" 2>&1
    elif command_exists ntpq; then
        ntpq -p >> "$output_file" 2>&1
    else
        echo "Neither chronyc nor ntpq commands are available." >> "$output_file"
    fi
}

# Function to check admin group
check_admin_group() {
    if getent group wheel >/dev/null; then
        admin_group="wheel"
    elif getent group sudo >/dev/null; then
        admin_group="sudo"
    else
        admin_group=""
    fi
    echo "$admin_group"
}

# Function to check if user is in admin group
is_user_in_admin_group() {
    user="$1"
    admin_group=$(check_admin_group)
    if [ -n "$admin_group" ]; then
        if id -nG "$user" | grep -qw "$admin_group"; then
            echo "User $user is in group $admin_group." >> "$output_file"
        else
            echo "User $user is not in group $admin_group." >> "$output_file"
        fi
    else
        echo "No admin group (wheel or sudo) found." >> "$output_file"
    fi
}

# Filesystems Check
log_time "Filesystems Check"
append_title "Filesystems Check"
echo "Checking filesystem disk space usage..." >> "$output_file"
if command_exists df; then
    df -h >> "$output_file" 2>&1
else
    echo "df command not found." >> "$output_file"
fi
end_time

# Network Interfaces and IPs
log_time "Network Interfaces and IPs"
append_title "Network Interfaces and IPs"
echo "Listing network interfaces and IP addresses..." >> "$output_file"
if command_exists ip; then
    ip addr show >> "$output_file" 2>&1
elif command_exists ifconfig; then
    ifconfig -a >> "$output_file" 2>&1
else
    echo "Neither ip nor ifconfig commands are available." >> "$output_file"
fi
end_time

# Connectivity Checks
log_time "Connectivity Checks"
append_title "Connectivity Checks"
# (Add your connectivity checks here, similar to previous examples)
end_time

# Timezone Configuration
log_time "Timezone Configuration"
append_title "Timezone Configuration"
if command_exists timedatectl; then
    current_timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
elif [ -f /etc/timezone ]; then
    current_timezone=$(cat /etc/timezone)
else
    echo "Unable to determine the current timezone." >> "$output_file"
    current_timezone=""
fi

if [ -n "$current_timezone" ]; then
    echo "Current Timezone: $current_timezone" >> "$output_file"
    if [ "$current_timezone" = "UTC" ]; then
        echo "Timezone is set to UTC. Please set it to the correct timezone." >> "$output_file"
    else
        echo "Timezone is set to $current_timezone." >> "$output_file"
    fi
else
    echo "Current Timezone: Unknown" >> "$output_file"
fi
end_time

# NTP Configuration
log_time "NTP Configuration"
append_title "NTP Configuration"
echo "Checking NTP server configuration..." >> "$output_file"
check_ntp_status
end_time

# Firewall Configuration
log_time "Firewall Configuration"
append_title "Firewall Configuration"
echo "Checking firewall status..." >> "$output_file"
check_firewall_status
end_time

# Sudoers Configuration
log_time "Sudoers Configuration"
append_title "Sudoers Configuration"
echo "Checking sudoers configuration..." >> "$output_file"
sudoers_files=("/etc/sudoers" "/etc/sudoers.d/*")
found_nopasswd=false
for file in "${sudoers_files[@]}"; do
    if [ -f "$file" ]; then
        if grep -Eq '^(%wheel|%sudo)\s+ALL=\(ALL\)\s+NOPASSWD:\s+ALL' "$file"; then
            echo "NOPASSWD for wheel or sudo group found in $file" >> "$output_file"
            found_nopasswd=true
        fi
    fi
done
if [ "$found_nopasswd" = false ]; then
    echo "NOPASSWD for wheel or sudo group not found in sudoers files. Please configure it." >> "$output_file"
fi
end_time

# (Continue with other sections in a similar fashion)

# At the end of the script, trigger the validator script
echo "Running os-report-validator.sh..."
if [ -f "./os-report-validator.sh" ]; then
    chmod +x ./os-report-validator.sh
    ./os-report-validator.sh
else
    echo "os-report-validator.sh not found in the current directory."
fi
