provider "google" {    
}

# Reference: https://www.terraform.io/docs/language/values/locals.html
locals {
  subnet_01 = "${var.network_name}-subnet-01"
  subnet_02 = "${var.network_name}-subnet-02"
}

# Reference: https://registry.terraform.io/modules/terraform-google-modules/project-factory/google/latest
module "host-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "11.1.1"
  # insert the 7 required variables here
  name                              = var.host_project_name
  org_id                            = var.organization_id
  billing_account                   = var.billing_account
  folder_id                         = var.folder_id
  enable_shared_vpc_host_project    = true
  random_project_id                 = true
}

# Reference: https://registry.terraform.io/modules/terraform-google-modules/network/google/latest
module "network" {
  source  = "terraform-google-modules/network/google"
  version = "3.4.0"
  # insert the 3 required variables here
  project_id                             = module.host-project.project_id
  network_name                           = var.network_name

  subnets = [
    {
      subnet_name   = local.subnet_01
      subnet_ip     = "10.10.10.0/24"
      subnet_region = "us-central1"
    },
    {
      subnet_name           = local.subnet_02
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = "us-central1"
      subnet_private_access = true
      subnet_flow_logs      = true
    }
  ]    
  firewall_rules = [
    {
      name      = "allow-ssh-icmp-ingress"
      direction = "INGRESS"
      ranges    = ["0.0.0.0/0"]
      allow = [
        {
            protocol = "tcp"
            ports    = ["22"]
        },
        {
            protocol = "icmp",
            ports    = null
        }
      ]
    }
  ]
  routes = [
    {
      name              = "egress-internet"
      description       = "route through IGW to access internet"
      destination_range = "0.0.0.0/0"
      next_hop_internet = "true"
    }
  ]
}

module "service-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "11.1.1"
  # insert the 7 required variables here
  name                              = var.service_project_name
  random_project_id                 = true
  org_id                            = var.organization_id
  billing_account                   = var.billing_account
  folder_id                         = var.folder_id
  svpc_host_project_id              = module.host-project.project_id
  activate_apis	                    = [
      "compute.googleapis.com",
      "container.googleapis.com"
  ]
  disable_services_on_destroy       = false
}

resource "google_compute_instance" "vm_instance1" {
    project = module.service-project.project_id
    zone = "us-central1-a"
    name = "myvm1"
    machine_type = "f1-micro"

    tags = [ "webserver", "development" ]

    boot_disk {
      initialize_params {
        image = "debian-cloud/debian-9"
      }
    }

    network_interface {
      subnetwork_project = module.host-project.project_id
      network = module.network.network_self_link
      subnetwork = local.subnet_01
      access_config {
      }
    }
}

resource "google_storage_bucket" "badara-bucket" {
  name = "bucket1-20210906-2"
  location = "US"
  project = module.service-project.project_id
}