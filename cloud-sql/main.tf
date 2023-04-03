provider "google-beta" {
  project = var.project
  region  = var.region
}

terraform {
  required_version = ">= 0.12.26"

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 3.57.0"
    }
  }
}

resource "random_id" "name" {
  byte_length = 2
}

locals {
  instance_name        = var.name_override == null ? format("%s-%s", var.name_prefix, random_id.name.hex) : var.name_override
  private_network_name = "private-network-${random_id.name.hex}"
  private_ip_name      = "private-ip-${random_id.name.hex}"
}

resource "google_compute_network" "private_network" {
  provider = google-beta
  name     = local.private_network_name
}

resource "google_compute_global_address" "private_ip_address" {
  provider      = google-beta
  name          = local.private_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.private_network.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = google_compute_network.private_network.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

module "postgres" {
  source = "./module/sql"

  dependencies = [google_service_networking_connection.private_vpc_connection.network]

  project = var.project
  region  = var.region
  name    = local.instance_name
  db_name = var.db_name

  engine              = var.postgres_version
  machine_type        = var.machine_type
  deletion_protection = false
  private_network     = google_compute_network.private_network.self_link
  custom_labels = {
    test-id = "postgres"
  }
}