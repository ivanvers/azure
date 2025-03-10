#!/bin/bash

# Get all subscription IDs (only enabled ones)
subscriptions=$(az account list --query "[?state=='Enabled'].id" -o tsv)

# Initialize an empty JSON array
all_vnets="[]"

echo "📡 Fetching all Virtual Networks (VNETs) across all subscriptions..."

# Get all virtual networks across all subscriptions first
for sub in $subscriptions; do
    echo "🔄 Switching to subscription: $sub"
    az account set --subscription "$sub"

    # Get VNETs for the current subscription
    vnets=$(az network vnet list --query "[].{Subscription:'$sub', VNET_Name:name, ResourceGroup:resourceGroup, AddressSpace:join(',', addressSpace.addressPrefixes)}" -o json)

    # Skip if no VNETs found
    if [[ $(echo "$vnets" | jq length) -eq 0 ]]; then
        echo "⚠️  No VNETs found in subscription: $sub"
        continue
    fi

    # Append VNETs to the master list
    all_vnets=$(echo "$all_vnets" | jq -c --argjson new "$vnets" '. + $new')
done

# If no VNETs were found at all, exit early
if [[ $(echo "$all_vnets" | jq length) -eq 0 ]]; then
    echo "🚫 No Virtual Networks found across all subscriptions."
    exit 1
fi

echo "✅ Fetched all Virtual Networks. Now retrieving subnets..."

# Initialize an array for final results (each row will be separate)
all_vnets_with_subnets="[]"

# Loop through all VNETs and fetch their subnets
while IFS= read -r vnet; do
    vnet_name=$(echo "$vnet" | jq -r '.VNET_Name')
    vnet_rg=$(echo "$vnet" | jq -r '.ResourceGroup')
    vnet_sub=$(echo "$vnet" | jq -r '.Subscription')
    vnet_address_space=$(echo "$vnet" | jq -r '.AddressSpace')

    # Skip empty VNET names (prevents issues)
    if [[ -z "$vnet_name" || -z "$vnet_rg" || -z "$vnet_sub" ]]; then
        echo "⚠️  Skipping invalid VNET entry (missing name, resource group, or subscription)"
        continue
    fi

    echo "🔄 Switching to subscription: $vnet_sub"
    az account set --subscription "$vnet_sub"

    echo "✅ Fetching subnets for VNET: $vnet_name (Resource Group: $vnet_rg) in Subscription: $vnet_sub"

    # Get subnets for this VNET
    subnets=$(az network vnet subnet list --vnet-name "$vnet_name" --resource-group "$vnet_rg" --query "[].{SubnetName:name, SubnetAddressPrefix:addressPrefix}" -o json)

    if [[ $(echo "$subnets" | jq length) -eq 0 ]]; then
        echo "⚠️  No subnets found in $vnet_name, adding as None"
        all_vnets_with_subnets=$(echo "$all_vnets_with_subnets" | jq -c --arg sub "$vnet_sub" --arg name "$vnet_name" --arg rg "$vnet_rg" --arg addr "$vnet_address_space" '. + [{"Subscription": $sub, "VNET_Name": $name, "ResourceGroup": $rg, "AddressSpace": $addr, "Subnet": "None", "SubnetAddressPrefix": "None"}]')
    else
        while IFS= read -r subnet; do
            subnet_name=$(echo "$subnet" | jq -r '.SubnetName')
            address_range=$(echo "$subnet" | jq -r '.SubnetAddressPrefix')

            echo "🔹 Subnet: $subnet_name | Address Prefix: $address_range"

            # Add each subnet as a separate row
            all_vnets_with_subnets=$(echo "$all_vnets_with_subnets" | jq -c --arg sub "$vnet_sub" --arg name "$vnet_name" --arg rg "$vnet_rg" --arg addr "$vnet_address_space" --arg subnet "$subnet_name" --arg range "$address_range" '. + [{"Subscription": $sub, "VNET_Name": $name, "ResourceGroup": $rg, "AddressSpace": $addr, "Subnet": $subnet, "SubnetAddressPrefix": $range}]')
        done <<< "$(echo "$subnets" | jq -c '.[]')"
    fi

done <<< "$(echo "$all_vnets" | jq -c '.[]')"

# Ensure the JSON is not empty before printing
if [[ $(echo "$all_vnets_with_subnets" | jq length) -eq 0 ]]; then
    echo "🚫 No VNETs with subnets found."
    exit 1
fi

# Display the consolidated table
echo "📊 Consolidated VNETs & Subnets Across All Subscriptions:"
echo "$all_vnets_with_subnets" | jq -r '["Subscription", "VNET_Name", "ResourceGroup", "AddressSpace", "Subnet", "SubnetAddressPrefix"], 
                           ["------------", "------------", "--------------", "----------------", "------------", "----------------"],
                           (.[] | [.Subscription, .VNET_Name, .ResourceGroup, .AddressSpace, .Subnet, .SubnetAddressPrefix]) 
                           | @tsv' | column -t -s$'\t'
