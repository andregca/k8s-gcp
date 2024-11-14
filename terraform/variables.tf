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

variable "ssh_keys" {
    type = object({
        value = string
    })
    description = ("SSH Key")
    sensitive = true
}