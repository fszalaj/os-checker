#!/bin/bash

# Define the output file path
output_file="/opt/atosans/os-checker/system_verification_report.txt"

# Ensure the directory exists
mkdir -p /opt/atosans/os-checker

# Get the hostname and date
hostname=$(hostname)
current_date=$(date)

# Start the report with hostname and date
echo "System Verification Report" > "$output_file"
echo "----------------------------------------" >> "$output_file"
echo "Hostname: $hostname" >> "$output_file"
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

# Function to check if a service exists
service_exists() {
  systemctl list-unit-files --type=service | grep -qw "$1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to install netcat, curl, telnet, htop if not already installed
install_utilities() {
  log_time "Utilities Installation"
  append_title "Utilities Installation"
  declare -a utilities=("nc" "curl" "telnet" "htop")
  for util in "${utilities[@]}"; do
    if ! command_exists "$util"; then
      echo "$util is not installed. Installing via yum..." >> "$output_file"
      yum install -y "$util" >> "$output_file" 2>&1
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

# 1. Network Interfaces and IPs
log_time "Network Interfaces and IPs"
append_title "Network Interfaces and IPs"
echo "Listing network interfaces and IP addresses..." >> "$output_file"
if command_exists ip; then
  ip addr show >> "$output_file" 2>&1
else
  echo "ip command not found." >> "$output_file"
fi
echo "Disk Usage Information (df -a):" >> "$output_file"
df -a >> "$output_file" 2>&1
end_time

# 2. Timezone Configuration
log_time "Timezone Configuration"
append_title "Timezone Configuration"
echo "Checking timezone configuration..." >> "$output_file"
current_timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
echo "Current Timezone: $current_timezone" >> "$output_file"
if [ "$current_timezone" = "UTC" ]; then
  echo "Timezone is set to UTC. Please set it to the correct timezone." >> "$output_file"
else
  echo "Timezone is set to $current_timezone." >> "$output_file"
fi
end_time

# 3. NTP Configuration
log_time "NTP Configuration"
append_title "NTP Configuration"
echo "Checking NTP server configuration..." >> "$output_file"

if [ -f /etc/chrony.conf ]; then
  default_ntp_servers=$(grep -E '^(server|pool) .*ntp.org' /etc/chrony.conf)
  if [ -n "$default_ntp_servers" ]; then
    echo "Default NTP servers found in /etc/chrony.conf. Please remove them." >> "$output_file"
    echo "$default_ntp_servers" >> "$output_file"
  else
    echo "No default NTP servers found in /etc/chrony.conf." >> "$output_file"
  fi

  atos_ntp_servers=$(grep -E '^server (155\.45|161\.89)' /etc/chrony.conf | awk '{print $2}')
  if [ -n "$atos_ntp_servers" ]; then
    echo "ATOS NTP servers configured:" >> "$output_file"
    echo "$atos_ntp_servers" >> "$output_file"
  else
    echo "ATOS NTP servers are not configured in /etc/chrony.conf." >> "$output_file"
  fi
else
  echo "/etc/chrony.conf not found." >> "$output_file"
fi

echo "Checking NTP synchronization status..." >> "$output_file"
if command_exists chronyc; then
  chronyc sources >> "$output_file" 2>&1
else
  echo "chronyc command not found." >> "$output_file"
fi
end_time

# 4. Firewall Configuration
log_time "Firewall Configuration"
append_title "Firewall Configuration"
echo "Checking firewalld service status..." >> "$output_file"
if service_exists firewalld.service; then
  systemctl status firewalld.service >> "$output_file" 2>&1
  # Check if firewalld is enabled
  if systemctl is-enabled firewalld.service >> /dev/null 2>&1; then
    echo "firewalld is enabled." >> "$output_file"
  else
    echo "firewalld is not enabled. Please enable it with 'systemctl enable firewalld'." >> "$output_file"
  fi
else
  echo "firewalld service not found." >> "$output_file"
fi

echo "Listing active firewall zones and services..." >> "$output_file"
if command_exists firewall-cmd; then
  active_zones=$(firewall-cmd --get-active-zones)
  echo "Active zones:" >> "$output_file"
  echo "$active_zones" >> "$output_file"

  # Check for Management zone
  if echo "$active_zones" | grep -q 'Management'; then
    echo "Management zone is active." >> "$output_file"
    management_services=$(firewall-cmd --zone=Management --list-services)
    if [ -z "$management_services" ]; then
      echo "Management zone has no services applied." >> "$output_file"
    else
      echo "Management zone has services applied:" >> "$output_file"
      echo "$management_services" >> "$output_file"
    fi
  else
    echo "Management zone is not active." >> "$output_file"
  fi

  # Check for Production zone
  if echo "$active_zones" | grep -q 'Production'; then
    echo "Production zone is active." >> "$output_file"
    production_interfaces=$(firewall-cmd --zone=Production --list-interfaces)
    echo "Production zone interfaces: $production_interfaces" >> "$output_file"
    production_services=$(firewall-cmd --zone=Production --list-services)
    echo "Production zone services: $production_services" >> "$output_file"
  else
    echo "Production zone is not active." >> "$output_file"
  fi

  # Check for custom services
  echo "Listing custom services..." >> "$output_file"
  custom_services=$(ls /etc/firewalld/services | grep -E 'bladelogic.xml|networkerclient.xml|netbackup.xml')
  if [ -n "$custom_services" ]; then
    echo "Custom services defined:" >> "$output_file"
    echo "$custom_services" >> "$output_file"
  else
    echo "No custom services found." >> "$output_file"
  fi

else
  echo "firewall-cmd command not found." >> "$output_file"
fi
end_time

# Sudoers Configuration
log_time "Sudoers Configuration"
append_title "Sudoers Configuration"
echo "Checking sudoers configuration..." >> "$output_file"

# Check for NOPASSWD for wheel group
sudoers_files=("/etc/sudoers" "/etc/sudoers.d/*")
found_nopasswd=false
for file in "${sudoers_files[@]}"; do
  if [ -f "$file" ]; then
    if grep -Eq '^%wheel\s+ALL=\(ALL\)\s+NOPASSWD:\s+ALL' "$file"; then
      echo "NOPASSWD for wheel group found in $file" >> "$output_file"
      found_nopasswd=true
    fi
  fi
done
if [ "$found_nopasswd" = false ]; then
  echo "NOPASSWD for wheel group not found in sudoers files. Please configure it." >> "$output_file"
fi
end_time

# 5. CrowdStrike (AV/EDR)
log_time "CrowdStrike (AV/EDR)"
append_title "CrowdStrike (AV/EDR)"
echo "Checking falcon-sensor status..." >> "$output_file"
if service_exists falcon-sensor.service; then
  systemctl status falcon-sensor.service >> "$output_file" 2>&1
else
  echo "falcon-sensor service not found." >> "$output_file"
fi

echo "Checking CrowdStrike proxy connectivity..." >> "$output_file"
if command_exists curl; then
  curl -k --connect-timeout 10 https://ts01-b.cloudsink.net -x http://nlproxy3.atos-srv.net:8080 >> "$output_file" 2>&1 || echo "Failed to connect to CrowdStrike proxy." >> "$output_file"
else
  echo "curl command not found." >> "$output_file"
fi

echo "Getting falcon-sensor status..." >> "$output_file"
if [ -f /opt/CrowdStrike/falconctl ]; then
  /opt/CrowdStrike/falconctl -g --rfm-state >> "$output_file" 2>&1
  /opt/CrowdStrike/falconctl -g --rfm-history >> "$output_file" 2>&1
  /opt/CrowdStrike/falconctl -g --aid --tags --aph --app >> "$output_file" 2>&1
  if command_exists mokutil; then
    mokutil --sb-state >> "$output_file" 2>&1
  else
    echo "mokutil command not found." >> "$output_file"
  fi
else
  echo "falconctl not found." >> "$output_file"
fi
end_time

# 6. AISAAC Agent (MDR)
log_time "AISAAC Agent (MDR)"
append_title "AISAAC Agent (MDR)"
echo "Checking AISAAC agent status..." >> "$output_file"
if service_exists proddefthmdr.service; then
  systemctl status proddefthmdr.service >> "$output_file" 2>&1
else
  echo "AISAAC agent service not found." >> "$output_file"
fi

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

# 7. Nagios CMF Agents
log_time "Nagios CMF Agents"
append_title "Nagios CMF Agents"
echo "Checking ase service status..." >> "$output_file"
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

echo "Checking Nagios cron job..." >> "$output_file"
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

# 8. RSCD (TSSA Agent)
log_time "RSCD (TSSA Agent)"
append_title "RSCD (TSSA Agent)"
echo "Checking RSCD service status..." >> "$output_file"
if service_exists rscd.service; then
  systemctl status rscd.service >> "$output_file" 2>&1
else
  echo "RSCD service not found." >> "$output_file"
fi

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

# 9. CyberArk Accounts
log_time "CyberArk Accounts"
append_title "CyberArk Accounts"
echo "Checking for atosans and atosadm users..." >> "$output_file"
for user in atosans atosadm; do
  if id "$user" >/dev/null 2>&1; then
    echo "User $user exists." >> "$output_file"
    user_groups=$(id -nG "$user")
    echo "User $user is in groups: $user_groups" >> "$output_file"
    # Check if user is in allowssh and wheel groups
    if echo "$user_groups" | grep -qw "allowssh"; then
      echo "User $user is in group allowssh." >> "$output_file"
    else
      echo "User $user is not in group allowssh." >> "$output_file"
    fi
    if echo "$user_groups" | grep -qw "wheel"; then
      echo "User $user is in group wheel." >> "$output_file"
    else
      echo "User $user is not in group wheel." >> "$output_file"
    fi
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

# 10. Alcatraz Scanner
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

# 11. SOXDB Scanner
log_time "SOXDB Scanner"
append_title "SOXDB Scanner"
echo "Checking atosadm user management configuration..." >> "$output_file"
if id "atosadm" >/dev/null 2>&1; then
  grep atosadm /etc/passwd >> "$output_file" 2>&1
  grep wheel /etc/group >> "$output_file" 2>&1 || echo "Group wheel not found." >> "$output_file"
  if command_exists chage; then
    chage -l atosadm >> "$output_file" 2>&1 || echo "Failed to get password aging information for atosadm." >> "$output_file"
  else
    echo "chage command not found." >> "$output_file"
  fi
else
  echo "User atosadm not found." >> "$output_file"
fi
end_time

# 12. Connectivity Checks
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
if [ -z "$paladion_ip" ]; then
  paladion_ip="155.45.244.104"
fi
for port in 443 8443; do
  echo "Testing connection to $paladion_ip:$port..." >> "$output_file"
  if command_exists nc; then
    timeout 5 nc -zv "$paladion_ip" "$port" >> "$output_file" 2>&1 && echo "Connection to $paladion_ip:$port successful." >> "$output_file" || echo "Connection to $paladion_ip:$port failed or timed out." >> "$output_file"
  else
    echo "nc command not found." >> "$output_file"
  fi
done
end_time

# End of report
echo "----------------------------------------" >> "$output_file"
echo "Verification Complete. Report saved to $output_file" >> "$output_file"

# Output the location of the report
echo "Report generated and saved to $output_file"
