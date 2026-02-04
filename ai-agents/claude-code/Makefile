# Claude Code with Edera Isolation
#
# Usage:
#   make build push deploy exec   # Full workflow
#   make clean                    # Cleanup

IMAGE_NAME ?= claude-code
IMAGE_TAG ?= latest
REGISTRY ?= ttl.sh
FULL_IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: help build push deploy verify tools exec clean

help:
	@echo "Claude Code with Edera Isolation"
	@echo ""
	@echo "Usage:"
	@echo "  make build    Build the container image"
	@echo "  make push     Push image to registry"
	@echo "  make deploy   Deploy Claude Code pod"
	@echo "  make verify   Verify kernel isolation"
	@echo "  make tools    Check all tools are working"
	@echo "  make exec     Launch Claude Code CLI"
	@echo "  make shell    Interactive shell in pod"
	@echo "  make clean    Remove pod"
	@echo ""
	@echo "Variables:"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  IMAGE_TAG=$(IMAGE_TAG)"

build:
	docker build --platform linux/amd64 -t $(IMAGE_NAME):$(IMAGE_TAG) .

push:
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(FULL_IMAGE)
	docker push $(FULL_IMAGE)
	@echo ""
	@echo "Image pushed to: $(FULL_IMAGE)"
	@echo "Update claude-code-pod.yaml with this image before deploying."

deploy:
	kubectl apply -f claude-code-pod.yaml
	kubectl wait --for=condition=Ready pod/claude-code --timeout=120s
	@echo ""
	@echo "Pod ready. Run 'make exec' to launch Claude Code."

verify:
	@echo "Checking kernel isolation..."
	@kubectl exec claude-code -- cat /proc/version
	@echo ""
	@echo "If this shows an Edera zone kernel (6.12.x or 6.15.x), isolation is active."

tools:
	@echo "Verifying development tools..."
	@kubectl exec claude-code -- bash -c "\
		echo '=== Claude Code ===' && claude --version && \
		echo '=== Go ===' && go version && \
		echo '=== Rust ===' && rustc --version && \
		echo '=== Python ===' && python3 --version && \
		echo '=== kubectl ===' && kubectl version --client && \
		echo '=== GitHub CLI ===' && gh --version | head -1 && \
		echo '=== ripgrep ===' && rg --version | head -1 && \
		echo '=== jq ===' && jq --version"

exec:
	kubectl exec -it claude-code -- claude

shell:
	kubectl exec -it claude-code -- bash

clean:
	kubectl delete pod claude-code --ignore-not-found
