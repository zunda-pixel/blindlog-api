resource "google_secret_manager_secret" "app" {
  for_each   = local.secret_env_names
  depends_on = [google_project_service.required]

  secret_id = each.value

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each = local.secret_env_names

  secret_id = google_secret_manager_secret.app[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
