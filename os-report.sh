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

    echo "NTP Configuration File: $ntp_config_file" >> "$output_file"

    # Get the server's primary IP address
    ip_addresses=$(hostname -I)
    primary_ip=$(echo $ip_addresses | awk '{print $1}')

    # Determine the network zone
    if [[ $primary_ip == 155.45.* || $primary_ip == 10.* ]]; then
        network_zone="SAACON/STZ"
    elif [[ $primary_ip == 161.* || $primary_ip == 172.* ]]; then
        network_zone="AOSN"
    else
        network_zone="Unknown"
    fi

    echo "Detected Network Zone: $network_zone" >> "$output_file"

    # Define allowed NTP servers based on network zone
    if [[ $network_zone == "SAACON/STZ" ]]; then
        allowed_ntp_servers=(
            "155.45.163.127"
            "155.45.163.128"
            "155.45.163.129"
            "155.45.163.130"
            "155.45.129.18"
            "155.45.129.19"
            "155.45.224.20"
            "155.45.224.21"
        )
    elif [[ $network_zone == "AOSN" ]]; then
        allowed_ntp_servers=(
            "161.89.57.5"
            "161.89.145.75"
            "161.89.224.5"
        )
    else
        echo "Unable to determine allowed NTP servers for network zone: $network_zone" >> "$output_file"
        return
    fi

    # Check configured NTP servers
    configured_servers=$(grep -E '^(server|pool)' "$ntp_config_file" | awk '{print $2}')

    echo "Configured NTP servers:" >> "$output_file"
    echo "$configured_servers" >> "$output_file"

    invalid_servers_found=false
    for server in $configured_servers; do
        if ! [[ " ${allowed_ntp_servers[@]} " =~ " ${server} " ]]; then
            echo "Invalid NTP server found: $server" >> "$output_file"
            invalid_servers_found=true
        fi
    done

    if [ "$invalid_servers_found" = true ]; then
        echo "Please ensure only the following NTP servers are configured:" >> "$output_file"
        printf '%s\n' "${allowed_ntp_servers[@]}" >> "$output_file"
    else
        echo "All configured NTP servers are valid." >> "$output_file"
    fi

    # Check if any allowed NTP servers are missing
    missing_servers=()
    for allowed_server in "${allowed_ntp_servers[@]}"; do
        if ! grep -q "$allowed_server" <<< "$configured_servers"; then
            missing_servers+=("$allowed_server")
        fi
    done

    if [ ${#missing_servers[@]} -ne 0 ]; then
        echo "The following allowed NTP servers are missing from the configuration:" >> "$output_file"
        printf '%s\n' "${missing_servers[@]}" >> "$output_file"
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
echo "Checking connectivity to Nagios gateways..." >> "$output_file"
nagios_servers=("161.89.176.188" "161.89.164.82" "155.45.163.181" "161.89.112.32")
for server in "${nagios_servers[@]}"; do
    echo "Testing connection to $server:443..." >> "$output_file"
    if command_exists nc; then
        timeout 5 nc -zv "$server" 443 >> "$output_file" 2>&1 && echo "Connection to $server:443 successful." >> "$output_file" || echo "Connection to $server:443 failed or timed out." >> "$output_file"
    else
        echo "nc command not found." >> "$output_file"
    fi
done

echo "Checking connectivity to CrowdStrike proxy..." >> "$output_file"
crowdstrike_proxy="161.89.57.59"
echo "Testing connection to $crowdstrike_proxy:8080..." >> "$output_file"
if command_exists nc; then
    timeout 5 nc -zv "$crowdstrike_proxy" 8080 >> "$output_file" 2>&1 && echo "Connection to $crowdstrike_proxy:8080 successful." >> "$output_file" || echo "Connection to $crowdstrike_proxy:8080 failed or timed out." >> "$output_file"
else
    echo "nc command not found." >> "$output_file"
fi

echo "Checking connectivity to RPM Package repository..." >> "$output_file"
rpm_repo="155.45.172.37"
echo "Testing connection to $rpm_repo:443..." >> "$output_file"
if command_exists nc; then
    timeout 5 nc -zv "$rpm_repo" 443 >> "$output_file" 2>&1 && echo "Connection to $rpm_repo:443 successful." >> "$output_file" || echo "Connection to $rpm_repo:443 failed or timed out." >> "$output_file"
else
    echo "nc command not found." >> "$output_file"
fi

echo "Checking connectivity to AISAAC / MDR / Paladion gateway..." >> "$output_file"
paladion_ip="155.45.244.104"
for port in 443 8443; do
    echo "Testing connection to $paladion_ip:$port..." >> "$output_file"
    if command_exists nc; then
        timeout 5 nc -zv "$paladion_ip" "$port" >> "$output_file" 2>&1 && echo "Connection to $paladion_ip:$port successful." >> "$output_file" || echo "Connection to $paladion_ip:$port failed or timed out." >> "$output_file"
    else
        echo "nc command not found." >> "$output_file"
    fi
done
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
    echo "Timezone is set to $current_timezone." >> "$output_file"
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

# CrowdStrike (AV/EDR)
log_time "CrowdStrike (AV/EDR)"
append_title "CrowdStrike (AV/EDR)"
echo "Checking falcon-sensor status..." >> "$output_file"
check_service_status "falcon-sensor"

echo "Checking CrowdStrike proxy connectivity..." >> "$output_file"
if command_exists curl; then
    curl -k --connect-timeout 10 https://ts01-b.cloudsink.net -x http://nlproxy3.atos-srv.net:8080 >> "$output_file" 2>&1 || echo "Failed to connect to CrowdStrike proxy." >> "$output_file"
else
    echo "curl command not found." >> "$output_file"
fi

echo "Getting falcon-sensor configuration..." >> "$output_file"
if [ -f /opt/CrowdStrike/falconctl ]; then
    mgmt_console="https://ts01-b.cloudsink.net"
    cid_output=$(/opt/CrowdStrike/falconctl -g --cid)
    aph_output=$(/opt/CrowdStrike/falconctl -g --aph)
    app_output=$(/opt/CrowdStrike/falconctl -g --app)
    echo "Management Console URL: $mgmt_console" >> "$output_file"
    echo "Service Parameters:" >> "$output_file"
    echo "  $cid_output" >> "$output_file"
    echo "  $aph_output" >> "$output_file"
    echo "  $app_output" >> "$output_file"
else
    echo "falconctl not found." >> "$output_file"
fi
end_time

# AISAAC Agent (MDR)
log_time "AISAAC Agent (MDR)"
append_title "AISAAC Agent (MDR)"
echo "Checking AISAAC agent status..." >> "$output_file"
check_service_status "proddefthmdr"

echo "Checking connectivity to Paladion gateway..." >> "$output_file"
if command_exists nc; then
    paladion_ip=$(grep Address /etc/Paladion/AiSaacServer.conf | sed -n 's/.*<Address>\(.*\)<\/Address>.*/\1/p')
    if [ -z "$paladion_ip" ]; then
        paladion_ip="161.89.16.217" # Default value if not found
    fi
    for port in 443 8443; do
        timeout 10 nc -zv "$paladion_ip" "$port" >> "$output_file" 2>&1 && echo "Connection to Paladion gateway on port $port successful." >> "$output_file" || echo "Connection to Paladion gateway on port $port failed or timed out." >> "$output_file"
    done
else
    echo "nc command not found." >> "$output_file"
fi
end_time

# Nagios CMF Agents
log_time "Nagios CMF Agents"
append_title "Nagios CMF Agents"
echo "Checking ASE agent status..." >> "$output_file"
if [ -f /opt/ASE/bin/ase ]; then
    /opt/ASE/bin/ase status >> "$output_file" 2>&1
else
    echo "ASE agent not found." >> "$output_file"
fi

echo "Checking Nagios connectivity..." >> "$output_file"
if command_exists nc; then
    timeout 10 nc -zv 161.89.176.188 443 >> "$output_file" 2>&1 && echo "Connection to Nagios server successful." >> "$output_file" || echo "Connection to Nagios server failed or timed out." >> "$output_file"
    timeout 10 nc -zv 155.45.163.181 443 >> "$output_file" 2>&1 && echo "Connection to Nagios backup server successful." >> "$output_file" || echo "Connection to Nagios backup server failed or timed out." >> "$output_file"
else
    echo "nc command not found." >> "$output_file"
fi

echo "Checking Nagios NaCl cron job for 'nagios' user..." >> "$output_file"
if command_exists crontab; then
    if crontab -u nagios -l | grep -q NaCl; then
        crontab -u nagios -l | grep NaCl >> "$output_file" 2>&1
    else
        echo "Nagios NaCl cron job not found in nagios user's crontab." >> "$output_file"
    fi
else
    echo "crontab command not found." >> "$output_file"
fi
end_time

# RSCD (TSSA Agent)
log_time "RSCD (TSSA Agent)"
append_title "RSCD (TSSA Agent)"
echo "Checking RSCD service status..." >> "$output_file"
check_service_status "rscd"

echo "Checking if RSCD is listening on port 4750..." >> "$output_file"
if command_exists netstat; then
    netstat -tulpn | grep ':4750' >> "$output_file" 2>&1
    if [ $? -eq 0 ]; then
        echo "RSCD is listening on port 4750." >> "$output_file"
    else
        echo "RSCD is not listening on port 4750." >> "$output_file"
    fi
else
    echo "netstat command not found." >> "$output_file"
fi

echo "Checking /etc/rsc/users.local configuration..." >> "$output_file"
if [ -f /etc/rsc/users.local ]; then
    users_local_content=$(cat /etc/rsc/users.local)
    echo "$users_local_content" >> "$output_file"
    if echo "$users_local_content" | grep -Eq '^(EvidianSN_L3AdminL|SENRG_L3AdminL|ASN-Atos_L3AdminL):\*.*rw,map=root'; then
        echo "Proper entry found in /etc/rsc/users.local." >> "$output_file"
    else
        echo "Proper entry not found in /etc/rsc/users.local. Please add it." >> "$output_file"
    fi
else
    echo "/etc/rsc/users.local not found." >> "$output_file"
fi

echo "Checking /etc/rsc/exports configuration..." >> "$output_file"
if [ -f /etc/rsc/exports ]; then
    exports_content=$(cat /etc/rsc/exports)
    echo "$exports_content" >> "$output_file"
    if echo "$exports_content" | grep -Eq '^\*\s+rw'; then
        echo "Proper entry found in /etc/rsc/exports." >> "$output_file"
    else
        echo "Proper entry not found in /etc/rsc/exports. Please add '*   rw'." >> "$output_file"
    fi
else
    echo "/etc/rsc/exports not found." >> "$output_file"
fi
end_time

# CyberArk Accounts
log_time "CyberArk Accounts"
append_title "CyberArk Accounts"
echo "Checking for atosans and atosadm users..." >> "$output_file"
for user in atosans atosadm; do
    if id "$user" >/dev/null 2>&1; then
        echo "User $user exists." >> "$output_file"
        user_groups=$(id -nG "$user")
        echo "User $user is in groups: $user_groups" >> "$output_file"
        # Check if user is in allowssh group
        if echo "$user_groups" | grep -qw "allowssh"; then
            echo "User $user is in group allowssh." >> "$output_file"
        else
            echo "User $user is not in group allowssh." >> "$output_file"
        fi
        # Check if user is in admin group
        is_user_in_admin_group "$user"
        # Check password expiry
        if command_exists chage; then
            password_expiry=$(chage -l "$user" | grep 'Password expires' | cut -d: -f2 | xargs)
            if [ "$password_expiry" = "never" ]; then
                echo "User $user has non-expiring password." >> "$output_file"
            else
                echo "User $user has password expiry set to: $password_expiry" >> "$output_file"
            fi
        else
            echo "chage command not found." >> "$output_file"
        fi
    else
        echo "User $user not found." >> "$output_file"
    fi
done
# Check if group allowssh exists
if getent group allowssh >/dev/null; then
    echo "Group allowssh exists." >> "$output_file"
else
    echo "Group allowssh not found." >> "$output_file"
fi
end_time

# Alcatraz Scanner
log_time "Alcatraz Scanner"
append_title "Alcatraz Scanner"
echo "Running Alcatraz scan..." >> "$output_file"
if [ -f /opt/atos_tooling/alcatraz_scanner/Alcatraz/os/bin/lsecurity.pl ]; then
    /opt/atos_tooling/alcatraz_scanner/Alcatraz/os/bin/lsecurity.pl -i default > /tmp/alcatraz_report.txt
    findings=$(grep -i finding /tmp/alcatraz_report.txt)
    if [ -n "$findings" ]; then
        echo "Findings in Alcatraz scan:" >> "$output_file"
        echo "$findings" >> "$output_file"
    else
        echo "No findings in Alcatraz scan." >> "$output_file"
    fi
else
    echo "Alcatraz scanner not found." >> "$output_file"
fi
end_time

# SOXDB Scanner
log_time "SOXDB Scanner"
append_title "SOXDB Scanner"
echo "Checking atosadm user management configuration..." >> "$output_file"
if id "atosadm" >/dev/null 2>&1; then
    grep atosadm /etc/passwd >> "$output_file" 2>&1
    admin_group=$(check_admin_group)
    if [ -n "$admin_group" ]; then
        grep "$admin_group" /etc/group >> "$output_file" 2>&1 || echo "Group $admin_group not found." >> "$output_file"
    else
        echo "No admin group (wheel or sudo) found." >> "$output_file"
    fi
    if command_exists chage; then
        chage -l atosadm >> "$output_file" 2>&1 || echo "Failed to get password aging information for atosadm." >> "$output_file"
    else
        echo "chage command not found." >> "$output_file"
    fi
else
    echo "User atosadm not found." >> "$output_file"
fi
end_time

# End of report
echo "----------------------------------------" >> "$output_file"
echo "Verification Complete. Report saved to $output_file" >> "$output_file"

# Output the location of the report
echo "Report generated and saved to $output_file"

# At the end of the script, trigger the validator script
echo "Running os-report-validator.sh..."
if [ -f "./os-report-validator.sh" ]; then
    chmod +x ./os-report-validator.sh
    ./os-report-validator.sh
else
    echo "os-report-validator.sh not found in the current directory."
fi
