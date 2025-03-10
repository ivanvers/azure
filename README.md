# Azure
My Azure repo for scripts and infracode

## cli
I running these scrips from my Azure CloudShell. I created a folder called scripts/az/cli and store them there. Make sure to run chmod +x to make the script executable.
### vnet_getsubnets.sh
This shell script will retreive all virtual networks available.  Loop for getting the subscription id so another loop can be done to retrieve the subnets. At the end list them in a table.
