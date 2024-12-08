# instance types
variable "instance_name" {
    type = list(string)
    default = [ "control-node", "worker1-node", "worker2-node" ]
    description = "Instance Names"
}

variable "region" {
    type        = string
    description = "Region Name"
    default     = "us-central1"
}

variable "zone" {
    type        = string
    description = "Zone Name"
    default = "us-central1-f"
}

variable "image" {
    type = string
    description = "OS Image Name"
    default = "ubuntu-minimal-2204-jammy-v20240926"
}

variable "provisioning_model" {
    type = string
    description = "Provisioning model (STANDARD or SPOT)"
    default = "STANDARD"
}

variable "machine_type" {
    type = string
    description = "Machine Type (Flavor)"
    default = "e2-medium"
}

variable "max_run_duration" {
    type = string
    description = "Maximum VM Run Duration (in seconds)"
    # default 8 hours (8 * 60 * 60 = 28800 seconds)
    default = 28800
}

variable "project" {
    type = object({
      name = string
    })
    description = ("Project Name")
    sensitive   = true
}

variable "service_account" {
    type = object({
      name = string
    })
    description = ("Service Account Name")
    sensitive = true
}

variable "init_script_suffix" {
    type = string
    description = "cloudinit script suffix"
    default = ".sh"
}

variable "k8s_version" {
    type = string
    description = "Kubernetes version to use"
    default = "latest"
}