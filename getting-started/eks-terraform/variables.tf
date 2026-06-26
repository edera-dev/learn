variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "edera_account_id" {
  description = "Edera's AWS account ID (the account that owns the AMI, provided by Edera team)"
  type        = string
  # No default - this must be provided
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "edera-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "hypervisor" {
  description = "Hypervisor backend to use: 'xen' (default, production) or 'kvm' (Early Access). Determines which Edera AMI is selected."
  type        = string
  default     = "xen"

  validation {
    condition     = contains(["xen", "kvm"], var.hypervisor)
    error_message = "hypervisor must be 'xen' or 'kvm'."
  }
}

variable "instance_types" {
  description = "List of instance types for the EKS Node Group. For KVM, use a metal instance or a nested-virtualization-capable type (e.g. m7i.xlarge, c7i.xlarge). For Xen, any supported type works."
  type        = list(string)
  default     = ["m5n.xlarge"]
}

variable "min_size" {
  description = "Minimum number of nodes in the EKS Node Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes in the EKS Node Group"
  type        = number
  default     = 3
}

variable "desired_size" {
  description = "Desired number of nodes in the EKS Node Group"
  type        = number
  default     = 2
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "edera-protect-nodes"
}

variable "enable_ssh_access" {
  description = "Enable SSH access to worker nodes"
  type        = bool
  default     = false
}

variable "ssh_key_name" {
  description = "Name of the EC2 Key Pair for SSH access to worker nodes (required if enable_ssh_access is true)"
  type        = string
  default     = ""
}
