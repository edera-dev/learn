# Edera Learning Examples

This repository contains working, tested examples for deploying Edera container security across different platforms and scenarios. Each example is designed to be cloned, configured, and run with minimal setup.

## 🚀 Quick Start

All examples are self-contained and include:

- ✅ Complete, working code (no incomplete snippets)
- ✅ Comprehensive documentation
- ✅ Automated testing and verification
- ✅ Easy cleanup and teardown

## 📋 Prerequisites

Before using any examples, ensure you have:

1. **Edera Account Access**: Contact [support@edera.dev](mailto:support@edera.dev) to get:
   - Access to Edera AMIs
   - Your Edera AWS account ID

2. **AWS CLI**: [Install and configure](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) with appropriate permissions

3. **kubectl**: [Install kubectl](https://kubernetes.io/docs/tasks/tools/) for Kubernetes examples

## 📁 Examples

### Getting Started

| Example | Description | Platform | Time to Deploy |
|---------|-------------|----------|----------------|
| [EKS with Terraform](./getting-started/eks-terraform/) | Complete EKS cluster with Edera protection using Terraform | AWS | ~15 minutes |

### AI Agents

| Example | Description | Platform |
|---------|-------------|----------|
| [Claude Code](./ai-agents/claude-code/) | Run AI coding agents with per-workload kernel isolation | Kubernetes |

## 🛡️ Region Support

Edera AMIs are currently available in:

- **us-west-2** (Oregon) - Primary region
- **us-gov-west-1** (AWS GovCloud US-West) - For government workloads

Contact [support@edera.dev](mailto:support@edera.dev) for access to additional regions.

## 💡 Example Structure

Each example follows a consistent structure:

```
example-name/
├── README.md              # Specific setup instructions
├── Makefile               # Common commands (deploy, test, destroy)
├── main.tf                # Primary infrastructure code
├── variables.tf           # Configurable parameters
├── outputs.tf             # Useful output values
├── terraform.tfvars.example # Configuration template
├── scripts/               # Helper scripts for validation
│   └── verify-ami.sh      # Verify deployment
└── kubernetes/            # K8s manifests
    ├── runtime-class.yaml # Edera runtime configuration
    └── test-workload.yaml # Test pod configuration
```

## 🔧 Common Commands

Every example includes a Makefile with these standard targets:

```bash
make help     # Show available commands
make plan     # Preview changes
make deploy   # Deploy infrastructure
make test     # Deploy test workload and verify
make verify   # Check deployment status
make clean    # Remove test resources
make destroy  # Tear down everything
```

## 🆘 Getting Help

1. **Documentation**: [docs.edera.dev](https://docs.edera.dev)
2. **Issues**: Found a problem? [Create an issue](https://github.com/edera-dev/learn/issues)
3. **Support**: Email [support@edera.dev](mailto:support@edera.dev)

## 🤝 Contributing

We welcome contributions! To add a new example:

1. Fork this repository
2. Create a new directory following the existing structure
3. Include comprehensive README, Makefile, and test coverage
4. Test your example thoroughly
5. Submit a pull request

### Example Requirements

- **Complete**: Must be runnable without external dependencies
- **Tested**: Include validation scripts and test workloads
- **Documented**: Clear README with prerequisites and instructions
- **Clean**: Include proper cleanup/destroy procedures
- **Secure**: Follow security best practices, no hardcoded secrets

## 📄 License

This repository is licensed under the [Apache License 2.0](LICENSE).

## 🔗 Related

- [Edera Documentation](https://docs.edera.dev)
- [Edera Website](https://edera.dev)