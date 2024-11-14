<h1 align="center">K8s Lab @ GCP<br />
<div align="center">
<a href="https://github.com/andregca/k8s-gcp"><img src="https://kubernetes.io/images/kubernetes.png" title="Logo" style="max-width:100%;" width="128" /></a>
</div>
</h1>



# Kubernetes Lab Environment on Google Cloud Compute with Terraform

This project provides a Terraform configuration to create and manage Virtual Machines (VMs) on Google Cloud Platform (GCP) for running Kubernetes labs.

## Prerequisites

1. **Google Cloud Account**: Ensure you have a Google Cloud account and a project created in the [Google Cloud Console](https://console.cloud.google.com/).
2. **Google Cloud SDK**: Download and install the [GCloud CLI](https://cloud.google.com/sdk/docs/install).
3. **Terraform**: Download and install [Terraform](https://www.terraform.io/downloads.html).

## Getting Started

### Step 1: Create a separate environment for this Lab

1. [Create a separate project](https://developers.google.com/workspace/guides/create-project) for this lab
2. Create a [service account](https://cloud.google.com/iam/docs/service-account-overview) for this lab, with compute admin privileges 
   - On google cloud console, select your project, go to access IAM & Admin / Service Accounts and click on create service account

### Step 2: Initialize Google Cloud SDK

1. **Login to Google Cloud**: Go to terraform directory, open a terminal and execute the following command to log into your Google Cloud account:

   ```bash
   cd terraform
   gcloud init
   ```

   This command will open a browser window for you to authenticate with your Google Cloud account.
   If the terminal you are using doesn't allow it, the you can copy and paste the URL in a browser in another computer.

2. **Set the Default Project**: Select the project id to use (created on step 1).

3. **Enable Required APIs** (if not already enabled):

   ```bash
   gcloud services enable compute.googleapis.com
   ```

   This will enable the Compute Engine API, required for provisioning VMs.

### Step 3: Set Up Terraform Provider for Google Cloud

1. **Initialize terraform**: in the terraform directory, ensure you have application default credentials by running:

   ```bash
   gcloud auth application-default login
   ```

   This command will also open a browser window for authentication. It generates credentials that Terraform will use to interact with Google Cloud.
   If you are running a linux image on WSL (Windows Subsystem for Linux), or on a remote computer, it won't open a browser automatically. Copy the URL and paste it on your computer browser for authorization.

2. **Initialize terraform**: initialize the terraform components with the command below:

   ```bash
   terraform init
   ```

3. **Update Variables**: Copy or rename the `terraform.tfvars.template` file as `terraform.tfvars` and edit it to replace the mandatory parameters, defining project id, service account and image name.

4. **Check for any errors**: use the command below to parse and generate the deployment plan:

  ```bash
  terraform plan
  ```

  This command will parse all the terraform files and generate the deployment plan. If it throws any error message, investigate and fix it before moving forward.

5. **Deploy the VM for test**: use the command below to deploy the plan:

  ```bash
  terraform apply -auto-approve
  ```

  After this commands finishes with success, check if the VMs were successfully created on Google Cloud Console or using the command below:
  
  ```
  gcloud compute instances list
  ```

6. **Terminate all VMs**: clean up all resources created by this terraform deployment with the command below:

  ```bash
  terraform destroy -auto-approve
  ```

  After finished, check if all VMs were destroyed using the Google Cloud Console or the gcloud command listed on item #5 above.


### Step 4: Create all VMs and setup Kubernetes cluster on them

1. **Create the lab environment**: Go to the main project directory and run the create.sh script.

   ```bash
   cd ..
   ./create.sh
   ```

   It should take 5 minutes to complete. After this process is completed without errors, you can ssh to the control-node, worker1-node, and worker2-node directly from the terminal. A custom ssh_config file was updated to make this process easier. You can use `gcloud compute ssh <student@node-name>` instead if you prefer.

   example:
   ```
   ssh control-node
   ```


2. **Delete all resources**: After finishing the lab, use the script below to clean up resources

   ```bash
   ./destroy.sh
   ```


### Step 5: Accessing and Managing the Kubernetes Lab Environment

- **SSH into VMs**: After the VMs are provisioned, you can SSH into each VM for setting up and running Kubernetes labs.

   - Option 1:
   ```bash
   gcloud compute ssh student@<vm-name> --zone=<zone>
   ```

   - Option 2:
   ```
   ssh <vm-name>
   ```

   where vm-name can be control-node, worker1-node, or worker2-node.

### Step 6: Clean Up Lab Environment Resources

- **Destroy Resources**: To delete all resources managed by Terraform, use:

  ```bash
  ./destroy.sh
  ```

## File Structure

```plaintext
├── create.sh                      # Script to create VMs and setup K8s
├── destroy.sh                     # Script to destroy all resources
├── README.md                      # This file
└── terraform
    ├── cloudinit-control.sh       # cloudinit script for control node
    ├── cloudinit-worker.sh        # cloudinit script for worker node
    ├── main.tf                    # Core Terraform configuration for GCP
    ├── terraform.tfvars           # Variable values (add your configuration here)
    └── variables.tf               # Variable definitions for the project
```

## Troubleshooting

- **Authentication Issues**: If you encounter any authentication issues, ensure that you’ve run `gcloud auth application-default login`.
- **API Permissions**: Make sure that the `Compute Engine API` is enabled for your project, as it’s required for VM creation.
- **Firewall Rules**: Ensure any necessary firewall rules are configured to allow access to the VMs.

## Author
[Andre Gustavo Albuquerque](https://github.com/andregca)

## Credits
Sander Van Vugt reference CKA scripts on https://github.com/sandervanvugt/cka

## License
This project is licensed under the MIT License. See the full license text at:  
https://opensource.org/licenses/MIT