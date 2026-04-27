resource "google_cloud_run_v2_service" "api" {
  depends_on = [
    google_project_service.required,
    google_secret_manager_secret_iam_member.runtime_access,
  ]

  name                = var.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      name  = "app"
      image = local.image_url

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Non-sensitive env vars (CLOUD_RUN_REGION is auto-injected from var.region).
      dynamic "env" {
        for_each = local.plain_env
        content {
          name  = env.key
          value = env.value
        }
      }

      # Sensitive env vars sourced from Secret Manager.
      dynamic "env" {
        for_each = local.secret_env_names
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.app[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      # Match existing prod probe (long timeout, single attempt). Tuned so a
      # cold start that triggers DB migrations doesn't get killed prematurely.
      startup_probe {
        tcp_socket {
          port = 8080
        }
        timeout_seconds   = 240
        period_seconds    = 240
        failure_threshold = 1
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # GitHub Actions updates the running image via `gcloud run services update`.
      # Keeping this ignored prevents `terraform apply` from reverting prod.
      template[0].containers[0].image,
      # Cloud Build / gcloud deploy auto-stamps these on each revision.
      template[0].labels,
      template[0].annotations,
      client,
      client_version,
    ]
  }
}

# Scope deployer's Cloud Run permissions to the one service rather than project-wide.
# `roles/run.developer` includes `run.services.update` which is what the GHA
# workflow calls via `gcloud run services update --image=...`.
resource "google_cloud_run_v2_service_iam_member" "deployer_developer" {
  project  = google_cloud_run_v2_service.api.project
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = google_cloud_run_v2_service.api.project
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
