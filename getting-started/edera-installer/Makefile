.PHONY: help deploy configure test test-standalone verify clean

# Default target
help:
	@echo "Edera Manual Installation"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy          - Install Edera on a target node (requires INSTALLER_IP)"
	@echo "  test-standalone - Test standalone installation (no Kubernetes)"
	@echo "  configure       - Apply RuntimeClass and label nodes (Kubernetes)"
	@echo "  test            - Test Kubernetes deployment with a test workload"
	@echo "  verify          - Verify Kubernetes cluster configuration"
	@echo "  clean           - Clean up test resources"
	@echo ""
	@echo "Environment variables:"
	@echo "  INSTALLER_IP  - Required. IP address of the target node"
	@echo "  SSH_USER      - SSH username (default: root)"
	@echo "  SSH_KEY       - Path to SSH private key (optional)"
	@echo ""
	@echo "Quick start (standalone):"
	@echo "  1. Save your GAR key as key.json"
	@echo "  2. INSTALLER_IP=<node-ip> make deploy"
	@echo "  3. INSTALLER_IP=<node-ip> make test-standalone"
	@echo ""
	@echo "Quick start (Kubernetes):"
	@echo "  1. Save your GAR key as key.json"
	@echo "  2. INSTALLER_IP=<node-ip> make deploy"
	@echo "  3. make configure"
	@echo "  4. make test"
	@echo ""
	@echo "Example with SSH key (e.g., for EC2):"
	@echo "  INSTALLER_IP=<ip> SSH_USER=ubuntu SSH_KEY=~/.ssh/my-key.pem make deploy"

# Check that key.json exists
check-key:
	@if [ ! -f key.json ]; then \
		echo "Error: key.json not found!"; \
		echo "Please save your Google Artifact Registry key as key.json"; \
		exit 1; \
	fi

# Deploy Edera to a node
deploy: check-key
	@if [ -z "$(INSTALLER_IP)" ]; then \
		echo "Error: INSTALLER_IP is not set"; \
		echo "Usage: INSTALLER_IP=<node-ip> make deploy"; \
		exit 1; \
	fi
	@echo "Installing Edera on $(INSTALLER_IP)..."
	./scripts/install.sh
	@echo ""
	@echo "Installation complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  make configure  # Apply RuntimeClass and label nodes"
	@echo "  make test       # Test the deployment"

# Test standalone installation (no Kubernetes)
test-standalone:
	@if [ -z "$(INSTALLER_IP)" ]; then \
		echo "Error: INSTALLER_IP is not set"; \
		echo "Usage: INSTALLER_IP=<node-ip> make test-standalone"; \
		exit 1; \
	fi
	@echo "Testing Edera installation on $(INSTALLER_IP)..."
	@SSH_OPTS=""; \
	if [ -n "$(SSH_KEY)" ]; then SSH_OPTS="-i $(SSH_KEY)"; fi; \
	SSH_USER=$${SSH_USER:-root}; \
	echo ""; \
	echo "Edera version:"; \
	ssh $$SSH_OPTS $${SSH_USER}@$(INSTALLER_IP) "sudo protect --version"; \
	echo ""; \
	echo "Edera services:"; \
	ssh $$SSH_OPTS $${SSH_USER}@$(INSTALLER_IP) "sudo systemctl status protect-daemon --no-pager | head -5"; \
	echo ""; \
	echo "Zone list:"; \
	ssh $$SSH_OPTS $${SSH_USER}@$(INSTALLER_IP) "sudo protect zone list"; \
	echo ""; \
	echo "Edera is installed and running!"

# Configure kubectl with RuntimeClass
configure:
	@echo "Applying Edera RuntimeClass..."
	kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml
	@echo ""
	@echo "RuntimeClass applied. Label your nodes with:"
	@echo "  kubectl label nodes <node-name> runtime=edera"
	@echo ""
	@echo "Or label all nodes:"
	@echo "  kubectl label nodes --all runtime=edera"

# Test the deployment
test:
	@echo "Testing Edera deployment..."
	@echo ""
	@echo "Node status:"
	kubectl get nodes -o wide
	@echo ""
	@echo "Node labels (checking for runtime=edera):"
	kubectl get nodes --show-labels | grep runtime=edera || echo "No nodes with runtime=edera label found"
	@echo ""
	@echo "RuntimeClass status:"
	kubectl get runtimeclass edera -o wide || echo "RuntimeClass not found"
	@echo ""
	@echo "Deploying test workload..."
	kubectl apply -f kubernetes/test-workload.yaml
	@echo ""
	@echo "Waiting for test pod to be ready..."
	kubectl wait --for=condition=ready pod/edera-test-pod -n edera-test --timeout=300s
	@echo ""
	@echo "Test pod is running!"
	@echo ""
	@echo "Test results:"
	kubectl get pods -n edera-test -o wide
	@echo ""
	@echo "Verifying pod is using Edera runtime:"
	@kubectl get pod edera-test-pod -n edera-test -o jsonpath="{.spec.runtimeClassName}"
	@echo ""
	@echo ""
	@echo "Success! Your node is running with Edera protection."

# Verify the deployment
verify:
	@echo "Verifying Edera installation..."
	@echo ""
	@echo "Cluster nodes:"
	kubectl get nodes
	@echo ""
	@echo "Edera RuntimeClass:"
	kubectl get runtimeclass edera
	@echo ""
	@echo "Test workload:"
	kubectl get pods -n edera-test

# Clean up test resources
clean:
	@echo "Cleaning up test resources..."
	kubectl delete -f kubernetes/test-workload.yaml --ignore-not-found=true
	@echo "Test resources cleaned up"
