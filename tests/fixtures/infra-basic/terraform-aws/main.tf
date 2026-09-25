# Consumidor de exemplo do autoteste: nenhum provider, nada na AWS.
terraform {
  required_version = ">= 1.14"
}

variable "environment" {
  type = string
}

resource "terraform_data" "marker" {
  input = "autoteste-${var.environment}"
}

output "marker" {
  value = terraform_data.marker.output
}
