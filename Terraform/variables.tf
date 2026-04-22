variable "allow_unauthenticated" {
  description = "Whether to allow public (unauthenticated) invocations of the Cloud Run service."
  type        = bool
  default     = true
}

variable "app_env" {
  description = "Non-sensitive environment variables passed to the app container."
  type        = map(string)
}

variable "artifact_repo_id" {
  description = "Artifact Registry repository ID."
  type        = string
  default     = "blindlog-api"
}

variable "cpu" {
  description = "Cloud Run container CPU limit (vCPU count or millicpu, e.g. \"1\", \"2\", \"500m\")."
  type        = string
  default     = "1"
}

variable "cpu_idle" {
  description = "Whether Cloud Run should allocate CPU only while requests are active."
  type        = bool
  default     = false
}

variable "deploy_branch" {
  description = "Git ref allowed to mint deployer tokens via Workload Identity Federation."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = startswith(var.deploy_branch, "refs/")
    error_message = "deploy_branch must be a fully-qualified ref, e.g. \"refs/heads/main\"."
  }
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deployer service account, in `owner/name` form."
  type        = string
  default     = "zunda-pixel/blindlog-api"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in `owner/name` form, e.g. \"zunda-pixel/blindlog-api\"."
  }
}

variable "image_tag" {
  description = "Initial image tag used on `terraform apply`. After first apply, GitHub Actions updates the running tag; Terraform ignores image drift."
  type        = string
  default     = "bootstrap"
}

variable "max_instance_count" {
  description = "Maximum number of Cloud Run container instances."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instance_count >= 1
    error_message = "max_instance_count must be at least 1."
  }
}

variable "memory" {
  description = "Cloud Run container memory limit (e.g. \"512Mi\", \"1Gi\")."
  type        = string
  default     = "512Mi"
}

variable "min_instance_count" {
  description = "Minimum number of Cloud Run container instances kept warm."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must be non-negative."
  }
}

variable "otel_collector_config_secret_id" {
  description = "Secret Manager secret ID that stores the OpenTelemetry Collector config."
  type        = string
  default     = "blindlog-otel-collector-config"
}

variable "otel_collector_cpu" {
  description = "Cloud Run CPU limit for the OpenTelemetry Collector sidecar."
  type        = string
  default     = "1"
}

variable "otel_collector_image" {
  description = "Container image for the Google-built OpenTelemetry Collector sidecar."
  type        = string
  default     = "us-docker.pkg.dev/cloud-ops-agents-artifacts/google-cloud-opentelemetry-collector/otelcol-google:0.144.0"
}

variable "otel_collector_memory" {
  description = "Cloud Run memory limit for the OpenTelemetry Collector sidecar."
  type        = string
  default     = "256Mi"
}

variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "project_number" {
  description = "Google Cloud project number. Used in the Workload Identity Federation principalSet."
  type        = string
}

variable "region" {
  description = "Google Cloud region for Cloud Run and Artifact Registry."
  type        = string
  default     = "asia-northeast1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must look like a valid GCP region, e.g. \"asia-northeast1\"."
  }
}

variable "service_name" {
  description = "Cloud Run service name."
  type        = string
  default     = "blindlog-api"
}
