locals {
  is_postgres = replace(var.engine, "POSTGRES", "") != var.engine
  is_mysql    = replace(var.engine, "MYSQL", "") != var.engine

  actual_binary_log_enabled     = local.is_postgres ? false : var.mysql_binary_log_enabled
  actual_availability_type      = local.is_postgres && var.enable_failover_replica ? "REGIONAL" : "ZONAL"
  actual_failover_replica_count = local.is_postgres ? 0 : var.enable_failover_replica ? 1 : 0
}

resource "google_sql_database_instance" "master" {
  depends_on = [null_resource.dependency_getter]

  provider         = google-beta
  name             = var.name
  project          = var.project
  region           = var.region
  database_version = var.engine

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.machine_type
    activation_policy = var.activation_policy
    disk_autoresize   = var.disk_autoresize

    ip_configuration {
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = lookup(authorized_networks.value, "name", null)
          value = authorized_networks.value.value
        }
      }

      ipv4_enabled    = var.enable_public_internet_access
      private_network = var.private_network
      require_ssl     = var.require_ssl
    }

    dynamic "location_preference" {
      for_each = var.master_zone == null ? [] : [var.master_zone]

      content {
        zone = location_preference.value
      }
    }

    backup_configuration {
      binary_log_enabled             = local.actual_binary_log_enabled
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = local.is_postgres ? var.postgres_point_in_time_recovery_enabled : null
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_track
    }

    disk_size         = var.disk_size
    disk_type         = var.disk_type
    availability_type = local.actual_availability_type

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    user_labels = var.custom_labels
  }

  timeouts {
    create = var.resource_timeout
    delete = var.resource_timeout
    update = var.resource_timeout
  }
}

resource "google_sql_database" "default" {
  depends_on = [google_sql_database_instance.master]

  name      = var.db_name
  project   = var.project
  instance  = google_sql_database_instance.master.name
  charset   = var.db_charset
  collation = var.db_collation
}

resource "null_resource" "dependency_getter" {
  provisioner "local-exec" {
    command = "echo ${length(var.dependencies)}"
  }
}
