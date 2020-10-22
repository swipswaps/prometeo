#!/bin/bash

# set variables
source variables.sh

find . -name "*.sh" -exec chmod u+x {} \;

# check vmid duplicates in file variables.sh
function check_vmid_duplicates() {
    duplicates_num=$(grep "VMID_" variables.sh | awk -F "=" '{print $2}' | sort | uniq -D | wc -l)
    if [[ "$duplicates_num" == "0" ]]; then
        echo -e "${GREEN_COLOUR}check_vmid_duplicates OK${RESET_COLOUR}"
    else
        echo -e "${RED_COLOUR}ct_create_ansible ERROR${RESET_COLOUR}"
        duplicates=$(grep "VMID_" variables.sh | awk -F "=" '{print $2}' | sort | uniq -D | head -n 1)
        echo -e "${RED_COLOUR}$(grep "$duplicates" variables.sh)${RESET_COLOUR}"
        exit 1
    fi
}

function waiting_online() {
    sleep 20 # need becasue script run thread "sleep 5 && reboot" and reboot is slow
    echo -e "${ORANGE_COLOUR}waiting for Server ${PM_HOST}${RESET_COLOUR}"
    while ! timeout 0.2 ping -c 1 -n "$PM_HOST" &>/dev/null; do
        printf "%c" "."
    done
    echo -e "\n${GREEN_COLOUR}Server is back online ${PM_HOST}${RESET_COLOUR}"
    sleep 5 # fix errors
}

function basic_config_proxmox() {
    # Instalacion de la confiugracion basica en Proxmox
    $SSH root@"$PM_HOST" "mkdir -p $MY_PATH/"
    $SCP proxmox_scripts/proxmox_configuration.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP variables.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP "$KEY" root@"$PM_HOST":"$MY_PATH"/
    $SCP "$KEY.pub" root@"$PM_HOST":"$MY_PATH"/
    $SSH root@"$PM_HOST" "cd $MY_PATH && bash proxmox_configuration.sh"
    waiting_online
}

function create_templates() {
    # Download template container alpine
    $SCP templates/proxmox_downloads_templates.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP templates/alpine.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP templates/ansible.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP templates/centos.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP templates/debian.sh root@"$PM_HOST":"$MY_PATH"/
    $SCP templates/health.sh root@"$PM_HOST":"$MY_PATH"/
    #$SCP mk/mikrotik.qcow2 root@"$PM_HOST":"$MY_PATH"/  # FIXME remove comment
    $SSH root@"$PM_HOST" "cd $MY_PATH && bash proxmox_downloads_templates.sh"
}

function create_containers() {
    test -d .terraform/ || terraform init

    directory="lxc"
    plan="lxc.tfplan"

    test -L "$directory/variables.tf" || ln -s ../variables.tf "$directory/"
    test -L "$directory/provider.tf" || ln -s ../provider.tf "$directory/"
    #set -x
    terraform validate "./$directory/" -with-deps || exit 1

    #terraform plan -destroy -state="$TERRAFORM_STATE" --out="$plan" -var-file="terraform.tfvars" "./$directory/" && \
    #  terraform apply -state="$TERRAFORM_STATE" -auto-approve "$plan"

    terraform plan -state="$TERRAFORM_STATE" --out="$plan" -var-file="terraform.tfvars" "./$directory/"

    if terraform apply -state="$TERRAFORM_STATE" -auto-approve "$plan"; then
        $SCP proxmox_scripts/insert_vlan_pct.sh root@"$PM_HOST":"$MY_PATH"/
        $SSH root@"$PM_HOST" "cd $MY_PATH && bash insert_vlan_pct.sh"
    fi
}

function clear() {
    #rm *.tfstate
    #rm *.tfplan
    $SCP proxmox_scripts/delete_vm.sh root@"$PM_HOST":"$MY_PATH"/
    $SSH root@"$PM_HOST" "bash $MY_PATH/delete_vm.sh"
}

function main() {
    check_vmid_duplicates
    python3 update_variables.py

    #basic_config_proxmox

    $SCP variables.sh root@"$PM_HOST":"$MY_PATH"/

    #clear

    #create_templates
    create_containers

}

main "$@"
