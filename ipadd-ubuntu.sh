#!/bin/bash

# Check if dialog is installed and install it if not
if ! command -v dialog >/dev/null 2>&1; then
    echo "Dialog is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y dialog
fi

while true; do
    # Get a list of available network interfaces
    interfaces=($(ip -o link show | awk -F': ' '!/^[0-9]+: lo/{print $2}'))

    # Get MAC addresses for all network interfaces
    mac_addresses=($(ip link show | grep -E 'link/ether' | awk '{print $2}'))

    # Create an associative array to store interface-name and MAC-address pairs
    declare -A interface_mac_map
    for ((i=0; i<${#interfaces[@]}; i++)); do
        interface_mac_map[${interfaces[i]}]=${mac_addresses[i]}
    done

    # Prepare options for the dialog menu
    menu_options=()
    for interface in "${interfaces[@]}"; do
        menu_options+=("$interface" "${interface_mac_map[$interface]}")
    done

    # Use dialog to create a menu for selecting the interface
    selected_interface_mac=$(dialog --stdout --menu "Select a network interface and its MAC address:" 16 60 8 "${menu_options[@]}")

    selected_interface=$(echo "$selected_interface_mac" | awk '{print $1}')
    selected_mac=$(echo "$selected_interface_mac" | awk '{print $2}')

    # Use dialog to ask if DHCP should be used
    dhcp_choice=$(dialog --stdout --menu "Do you want to use DHCP?" 10 40 2 "Yes" "Use DHCP" "No" "Use static IP")

    # Set the configuration based on DHCP choice
    if [ "$dhcp_choice" = "Yes" ]; then
        config="network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      dhcp4: true"
        config_file="/etc/netplan/60-$selected_interface.yaml"
    else
        # Get the additional IP addresses
        ip_input=$(dialog --stdout --inputbox "Enter additional IP addresses (comma-separated):" 10 40)

        # Split the comma-separated input into an array of IP addresses
        IFS=',' read -ra ip_addresses <<< "$ip_input"

        # Prepare the Netplan configuration for static IPs
        config="network:
  version: 2
  renderer: networkd
  ethernets:
    $selected_interface:
      addresses:"
        for ip in "${ip_addresses[@]}"; do
            config+="\n        - $ip"
        done
        config_file="/etc/netplan/additional-ips-$selected_interface.yaml"
    fi

    # Write the configuration to a new Netplan file
    echo -e "$config" | sudo tee "$config_file" > /dev/null

    # Apply the configuration
    sudo netplan apply

    echo "Configuration applied for interface: $selected_interface with MAC address: $selected_mac"

    # Ask if the user wants to configure another interface
    another_choice=$(dialog --stdout --menu "Do you want to configure another interface?" 10 40 2 "Yes" "Configure another interface" "No" "Exit")

    if [ "$another_choice" = "No" ]; then
        break
    fi
done

echo "Exiting the script."
