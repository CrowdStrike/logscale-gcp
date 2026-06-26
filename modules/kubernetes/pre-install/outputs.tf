output "logscale_namespace" {
  description = "The kubernetes namespace resource created for logscale"
  value       = kubernetes_namespace_v1.logscale
}
