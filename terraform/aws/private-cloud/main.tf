variable "access_key" {}
variable "secret_key" {}
variable "public_key_file" { default = "~/.ssh/id_rsa_aws.pub" }
variable "private_key_file" { default = "~/.ssh/id_rsa_aws.pem" }
variable "region" { default = "eu-west-1" }
variable "availability_zones" {
    type = "list"
    default = [ "eu-west-1a", "eu-west-1b", "eu-west-1c" ]
}
variable "vpc_cidr_block" { default = "10.0.0.0/16" }
variable "vpc_private_subnets_list" {
    type = "list"
    default = [ "10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24" ]
}
variable "vpc_public_subnets_list" {
    type = "list"
    default = [ "10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24" ]
}
variable "coreos_channel" { default = "stable" }
variable "etcd_discovery_url_file" { default = "etcd_discovery_url.txt" }
variable "masters" { default = "3" }
variable "master_instance_type" { default = "m3.medium" }
variable "workers" { default = "1" }
variable "worker_instance_type" { default = "m3.medium" }
variable "worker_ebs_volume_size" { default = "30" }
variable "bastion_instance_type" { default = "t2.micro" }
variable "docker_version" { default = "1.9.1-0~trusty" }

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

module "vpc" {
  source              = "./vpc"

  name                = "default"

  cidr                = "${var.vpc_cidr_block}"
  private_subnets     = [ "${var.vpc_private_subnets_list}" ]
  public_subnets      = [ "${var.vpc_public_subnets_list}" ]
  bastion_instance_id = "${aws_instance.bastion.id}"

  azs                 = [ "${var.availability_zones}" ]
}

# ssh keypair for instances
module "aws-keypair" {
  source = "../keypair"

  public_key = "${file("${var.public_key_file}")}"
}

# security group to allow all traffic in and out of the instances in the VPC
module "sg-default" {
  source = "../sg-all-traffic"

  vpc_id = "${module.vpc.vpc_id}"
}

module "elb" {
  source = "../elb"

  security_groups = "${module.sg-default.security_group_id}"
  instances       = "${join(",", aws_instance.worker.*.id)}"
  subnets         = "${module.vpc.public_subnets}"
}

# Generate an etcd URL for the cluster
resource "null_resource" "etcd_discovery_url" {
    provisioner "local-exec" {
        command = "curl -s https://discovery.etcd.io/new?size=${var.masters} > ${var.etcd_discovery_url_file}"
    }

    # To change the cluster size of an existing live cluster, please read:
    # https://coreos.com/etcd/docs/latest/etcd-live-cluster-reconfiguration.html
}

# outputs
output "bastion.ip" {
  value = "${aws_eip.bastion.public_ip}"
}
output "master_ips" {
  value = "${join(",", aws_instance.master.*.private_ip)}"
}
output "worker_ips" {
  value = "${join(",", aws_instance.worker.*.private_ip)}"
}
output "vpc_cidr_block_ip" {
 value = "${module.vpc.vpc_cidr_block}"
}
output "elb.hostname" {
  value = "${module.elb.elb_dns_name}"
}
