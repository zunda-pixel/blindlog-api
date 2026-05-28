variable "database_url" {
  type    = string
  default = ""
}

variable "dev_url" {
  type    = string
  default = "postgres://postgres:postgres@localhost:5432/dev?sslmode=disable&search_path=public"
}

env "local" {
  src = "file://Database/schema.sql"
  dev = var.dev_url

  migration {
    dir = "file://Database/migrations"
  }
}

env "production" {
  url = var.database_url

  migration {
    dir = "file://Database/migrations"
  }
}
