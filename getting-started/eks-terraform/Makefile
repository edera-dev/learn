.PHONY: help plan deploy test verify harden harden-clean clean destroy delete

HARDEN_DIR ?= ../../harden

# Auto-detect Terraform or OpenTofu
TF_TOOL := $(shell which terraform 2>/dev/null || which tofu 2>/dev/null)
ifeq ($(TF_TOOL),)
    $(error Neither terraform nor tofu (OpenTofu) found in PATH. Please install one of them: https://terraform.io or https://opentofu.org)
endif

# Default target
help:
	@echo "Available targets:"
	@echo "  plan          - Plan the Terraform/OpenTofu deployment"
	@echo "  deploy        - Deploy the EKS cluster with Edera"
	@echo "  test          - Test the deployment by creating a test workload"
	@echo "  verify        - Verify the cluster and nodes are properly configured"
	@echo "  harden        - Apply production hardening policies (Kyverno + NetworkPolicy)"
	@echo "  harden-clean  - Remove hardening resources"
	@echo "  clean         - Clean up test resources"
	@echo "  destroy       - Destroy the entire infrastructure"
	@echo "  delete        - Alias for destroy (same as destroy)"
	@echo ""
	@echo "Using: $(shell basename $(TF_TOOL)) ($(TF_TOOL))"
	@echo ""
	@echo "Quick start:"
	@echo "  1. cp terraform.tfvars.example terraform.tfvars"
	@echo "  2. Edit terraform.tfvars with the Edera account ID"
	@echo "  3. make deploy"
	@echo "  4. make test"

# Check if terraform.tfvars exists
check-config:
	@if [ ! -f terraform.tfvars ]; then \
		echo "Error: terraform.tfvars not found!"; \
		echo "Please copy terraform.tfvars.example to terraform.tfvars and configure it"; \
		exit 1; \
	fi

# Initialize Terraform/OpenTofu
init:
	$(TF_TOOL) init

# Plan the deployment
plan: check-config init
	$(TF_TOOL) plan

# Deploy the infrastructure
deploy: check-config init
	@echo "Deploying EKS cluster with Edera protection..."
	$(TF_TOOL) apply -auto-approve
	@echo ""
	@echo "🎉 Deployment complete!"
	@echo ""
	@echo "To configure kubectl:"
	@$(TF_TOOL) output -raw configure_kubectl
	@echo ""
	@echo "Next steps:"
	@echo "  make test    # Test the deployment"
	@echo "  make verify  # Verify configuration"

# Configure kubectl and apply RuntimeClass
configure:
	@echo "Configuring kubectl..."
	@eval "$$($(TF_TOOL) output -raw configure_kubectl)"
	@echo "Applying Edera RuntimeClass..."
	kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml
	@echo "✅ Configuration complete"

# Test the deployment
test: configure
	@echo "Testing Edera deployment..."
	@echo ""
	@echo "📋 Cluster information:"
	kubectl cluster-info
	@echo ""
	@echo "🔍 Node status:"
	kubectl get nodes -o wide
	@echo ""
	@echo "🏷️  Node labels (checking for runtime=edera):"
	kubectl get nodes --show-labels | grep runtime=edera || echo "❌ No nodes with runtime=edera label found"
	@echo ""
	@echo "🎯 RuntimeClass status:"
	kubectl get runtimeclass edera -o wide || echo "❌ RuntimeClass not found"
	@echo ""
	@echo "🚀 Deploying test workload..."
	kubectl apply -f kubernetes/test-workload.yaml
	@echo ""
	@echo "⏳ Waiting for test pod to be ready..."
	kubectl wait --for=condition=ready pod/edera-test-pod -n edera-test --timeout=300s
	@echo ""
	@echo "✅ Test pod is running!"
	@echo ""
	@echo "📊 Test results:"
	kubectl get pods -n edera-test -o wide
	@echo ""
	@echo "🔍 Verifying pod is using Edera runtime:"
	kubectl get pod edera-test-pod -n edera-test -o jsonpath="{.spec.runtimeClassName}"
	@echo ""
	@echo ""
	@echo "🎉 Success! Your EKS cluster is running with Edera protection."

# Verify the deployment
verify:
	@echo "🔍 Verifying EKS cluster with Edera..."
	@echo ""
	@echo "Cluster status:"
	kubectl get nodes
	@echo ""
	@echo "Edera RuntimeClass:"
	kubectl get runtimeclass edera
	@echo ""
	@echo "Test workload:"
	kubectl get pods -n edera-test
	@echo ""
	@echo "AMI information:"
	@./scripts/verify-ami.sh

# Apply production hardening: Kyverno policies + NetworkPolicy + verify
harden:
	@echo "Applying production hardening to this cluster..."
	$(MAKE) -C $(HARDEN_DIR) e2e

# Remove hardening resources
harden-clean:
	$(MAKE) -C $(HARDEN_DIR) e2e-clean

# Clean up test resources only
clean:
	@echo "🧹 Cleaning up test resources..."
	kubectl delete -f kubernetes/test-workload.yaml --ignore-not-found=true
	@echo "✅ Test resources cleaned up"

# Destroy everything
destroy:
	@echo "⚠️  This will destroy ALL infrastructure!"
	@read -p "Are you sure? (type 'yes' to confirm): " confirm && [ "$$confirm" = "yes" ]
	@echo "🧨 Destroying infrastructure..."
	make clean
	$(TF_TOOL) destroy -auto-approve
	@echo "💥 Infrastructure destroyed"

# Alias for destroy command
delete: destroy