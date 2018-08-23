resource "aws_launch_configuration" "workers" {
  count                       = "${length(var.worker_groups)}"
  name_prefix                 = "${var.cluster_name}-${lookup(var.worker_groups[count.index], "name", count.index)}-workers"
  security_groups             = ["${local.worker_security_group_id}"]
  iam_instance_profile        = "${aws_iam_instance_profile.workers.id}"
  image_id                    = "${lookup(var.worker_groups[count.index], "ami_id", data.aws_ami.eks_worker.id)}"
  instance_type               = "${lookup(var.worker_groups[count.index], "instance_type", lookup(var.workers_group_defaults, "instance_type"))}"
  user_data_base64            = "${base64encode(element(data.template_file.userdata.*.rendered, count.index))}"
  ebs_optimized               = "${lookup(var.worker_groups[count.index], "ebs_optimized", lookup(local.ebs_optimized, lookup(var.worker_groups[count.index], "instance_type", lookup(var.workers_group_defaults, "instance_type")), false))}"
  key_name                    = "${var.ssh_keypair_name}"
  associate_public_ip_address = false

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_size           = "${lookup(var.worker_groups[count.index], "root_volume_size", lookup(var.workers_group_defaults, "root_volume_size"))}"
    volume_type           = "${lookup(var.worker_groups[count.index], "root_volume_type", lookup(var.workers_group_defaults, "root_volume_type"))}"
    iops                  = "${lookup(var.worker_groups[count.index], "root_iops", lookup(var.workers_group_defaults, "root_iops"))}"
    delete_on_termination = true
  }
}

resource "aws_autoscaling_group" "workers" {
  count                = "${length(var.worker_groups)}"
  name                 = "${var.cluster_name}-${lookup(var.worker_groups[count.index], "name", count.index)}"
  desired_capacity     = "${lookup(var.worker_groups[count.index], "asg_desired_capacity", lookup(var.workers_group_defaults, "asg_desired_capacity"))}"
  max_size             = "${lookup(var.worker_groups[count.index], "asg_max_size",lookup(var.workers_group_defaults, "asg_max_size"))}"
  min_size             = "${lookup(var.worker_groups[count.index], "asg_min_size",lookup(var.workers_group_defaults, "asg_min_size"))}"
  launch_configuration = "${element(aws_launch_configuration.workers.*.id, count.index)}"
  vpc_zone_identifier  = ["${var.subnets}"]

  tags = ["${concat(
    list(
      map("key", "Name", "value", "${var.cluster_name}-${lookup(var.worker_groups[count.index], "name", count.index)}-workers-eks-asg", "propagate_at_launch", true),
      map("key", "kubernetes.io/cluster/${var.cluster_name}", "value", "owned", "propagate_at_launch", true),
      map("key", "KubernetesCluster", "value", "${var.cluster_name}", "propagate_at_launch", true),
      map("key", "k8snode/labels", "value", "${lookup(var.worker_groups[count.index], "labels", "")}", "propagate_at_launch", true),
      map("key", "k8snode/taints", "value", "${lookup(var.worker_groups[count.index], "taints", "")}", "propagate_at_launch", true),
    ),
    local.asg_tags)
  }"]
}

resource "aws_security_group" "workers" {
  count       = "${var.worker_security_group_id == "" ? 1 : 0}"
  name        = "${var.cluster_name}-workers-sg"
  description = "Security group for all nodes in the cluster."
  vpc_id      = "${var.vpc_id}"
  tags        = "${merge(var.tags, map("Name", "${var.cluster_name}-eks_worker_sg", "kubernetes.io/cluster/${var.cluster_name}", "owned"
  ))}"
}

resource "aws_security_group_rule" "workers_egress_internet" {
  count             = "${var.worker_security_group_id == "" ? 1 : 0}"
  description       = "Allow nodes all egress to the Internet."
  type              = "egress"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  to_port           = 0
  security_group_id = "${aws_security_group.workers.id}"
}

resource "aws_security_group_rule" "workers_ingress_self" {
  count                    = "${var.worker_security_group_id == "" ? 1 : 0}"
  description              = "Allow node to communicate with each other."
  type                     = "ingress"
  protocol                 = "-1"
  source_security_group_id = "${aws_security_group.workers.id}"
  from_port                = 0
  to_port                  = 65535
  security_group_id        = "${aws_security_group.workers.id}"
}

resource "aws_security_group_rule" "workers_ingress_cluster" {
  count                    = "${var.worker_security_group_id == "" ? 1 : 0}"
  description              = "Allow workers Kubelets and pods to receive communication from the cluster control plane."
  type                     = "ingress"
  protocol                 = "tcp"
  source_security_group_id = "${local.cluster_security_group_id}"
  from_port                = 1025
  to_port                  = 65535
  security_group_id        = "${aws_security_group.workers.id}"
}

resource "aws_security_group_rule" "workers_ssh" {
  count             = "${var.worker_security_group_id == "" ? 1 : 0}"
  description       = "Allow SSH to workers"
  type              = "ingress"
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 22
  to_port           = 22
  security_group_id = "${aws_security_group.workers.id}"
}

resource "aws_iam_role" "workers" {
  name               = "${var.cluster_name}-workers"
  assume_role_policy = "${data.aws_iam_policy_document.workers_assume_role_policy.json}"
}

resource "aws_iam_instance_profile" "workers" {
  name = "${var.cluster_name}-workers"
  role = "${aws_iam_role.workers.name}"
}

resource "aws_iam_role_policy_attachment" "workers_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.workers.name}"
}

resource "aws_iam_role_policy_attachment" "workers_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.workers.name}"
}

resource "aws_iam_role_policy_attachment" "workers_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.workers.name}"
}

resource "null_resource" "tags_as_list_of_maps" {
  count = "${length(keys(var.tags))}"

  triggers = "${map(
    "key", "${element(keys(var.tags), count.index)}",
    "value", "${element(values(var.tags), count.index)}",
    "propagate_at_launch", "true"
  )}"
}
