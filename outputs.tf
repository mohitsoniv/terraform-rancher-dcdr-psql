output "rancher_server_public_ip" {
  value = aws_instance.rancher.public_ip
}

output "rancher_url" {
  value = "https://${aws_instance.rancher.public_ip}"
}

output "rancher_ssh" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.rancher.public_ip}"
}

output "dc_node_public_ips" {
  value = aws_instance.dc_node[*].public_ip
}

output "dc_node_ssh" {
  value = [for ip in aws_instance.dc_node[*].public_ip : "ssh -i ${var.key_name}.pem ubuntu@${ip}"]
}

output "s3_dc_bucket" {
  value = aws_s3_bucket.dc.bucket
}

output "s3_dr_bucket" {
  value = aws_s3_bucket.dr.bucket
}

output "pgbackrest_access_key_id" {
  value = aws_iam_access_key.pgbackrest.id
}

output "pgbackrest_secret_access_key" {
  value     = aws_iam_access_key.pgbackrest.secret
  sensitive = true
}
