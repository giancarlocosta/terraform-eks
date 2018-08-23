resource "local_file" "kubeconfig" {
  count    = "${var.configure_kubectl_session ? 1 : 0}"
  content  = "${data.template_file.kubeconfig.rendered}"
  filename = "${var.config_output_path}/kubeconfig"
}

resource "local_file" "config_map_aws_auth" {
  count    = "${var.configure_kubectl_session ? 1 : 0}"
  content  = "${data.template_file.config_map_aws_auth.rendered}"
  filename = "${var.config_output_path}/config-map-aws-auth.yaml"
}

resource "null_resource" "configure_kubectl" {
  count = "${var.configure_kubectl_session ? 1 : 0}"

  provisioner "local-exec" {
    command = "kubectl apply -f ${var.config_output_path}/config-map-aws-auth.yaml --kubeconfig ${var.config_output_path}/kubeconfig"
  }

  triggers {
    config_map_rendered = "${data.template_file.config_map_aws_auth.rendered}"
    kubeconfig_rendered = "${data.template_file.kubeconfig.rendered}"
  }
}
