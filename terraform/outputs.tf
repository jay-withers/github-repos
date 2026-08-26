output "repository_urls" {
  description = "HTML URL of every managed repository, keyed by name."
  value       = { for name, repo in github_repository.this : name => repo.html_url }
}
