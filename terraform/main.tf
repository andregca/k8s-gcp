# main.tf

/*
MIT License

Copyright (c) 2024 Andre Gustavo de C. Albuquerque

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

# add a provider
provider "google" {
  project = var.project.name
  region  = var.region
  zone    = var.zone
}

# Create a VM instance from a public image
# in the `default` VPC network and subnet
resource "google_compute_instance" "default" {
  # iterate on the number of instance_names
  count = length(var.instance_name)
  name                = "${var.instance_name[count.index]}"
  machine_type        = var.machine_type
  description         = "K8s ${var.instance_name[count.index]}"
  desired_status      = "RUNNING"
  hostname            = "${var.instance_name[count.index]}.local"
  can_ip_forward      = false
  deletion_protection = false
  enable_display      = false

  boot_disk {
    device_name = "${var.instance_name[count.index]}"
    auto_delete = true
    mode = "READ_WRITE"
    initialize_params {
      image = var.image
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      network_tier = "PREMIUM"
    }
    queue_count = 0
    stack_type  = "IPV4_ONLY"
  }

  scheduling {
    automatic_restart   = true
    provisioning_model  = var.provisioning_model
    # set to migrate if standard or terminate if spot
    on_host_maintenance = (var.provisioning_model == "STANDARD") ? "MIGRATE" : "TERMINATE"
    preemptible         = (var.provisioning_model == "SPOT") ? true : false
  }

  service_account {
    email  = var.service_account.name
    scopes = ["https://www.googleapis.com/auth/devstorage.read_only", "https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write", "https://www.googleapis.com/auth/service.management.readonly", "https://www.googleapis.com/auth/servicecontrol", "https://www.googleapis.com/auth/trace.append"]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }
  metadata = {
    ssh-keys = var.ssh_keys.value
    startup-script = file("${path.module}/cloudinit-${regex("control|worker", var.instance_name[count.index])}.sh")
  }
}
# [END compute_instances_create]

# [END compute_basic_vm_parent_tag]
