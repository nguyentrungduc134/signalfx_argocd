variable "splunk_realm" {
  description = "Splunk Observability Cloud realm"
  type        = string
  default     = "au0"
}

variable "splunk_access_token" {
  description = "Splunk Observability Cloud access token"
  type        = string
  sensitive   = true
  default     = "JZbdumEmqHDjT0W2ncd0qA"
}

