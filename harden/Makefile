.PHONY: help kyverno-install apply-policies apply-network-policy apply-ai-agent verify e2e e2e-clean clean

NAMESPACE ?= default
E2E_NAMESPACE ?= edera-harden-test

help:
	@echo "Edera production hardening examples"
	@echo ""
	@echo "End-to-end test (requires a running cluster with Edera nodes):"
	@echo "  make e2e                          - Install Kyverno, apply all policies, verify"
	@echo "  make e2e-clean                    - Remove all e2e test resources"
	@echo ""
	@echo "Individual steps:"
	@echo "  make kyverno-install              - Install Kyverno via Helm"
	@echo "  make apply-policies               - Apply Kyverno hardening ClusterPolicy"
	@echo "  make apply-network-policy         - Apply default-deny egress to NAMESPACE"
	@echo "  make apply-ai-agent               - Deploy example AI agent pod"
	@echo "  make verify                       - Verify policies are enforced"
	@echo "  make clean                        - Remove hardening resources from NAMESPACE"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=<ns>       Target namespace for network policy (default: default)"
	@echo "  E2E_NAMESPACE=<ns>   Namespace used for e2e tests (default: edera-harden-test)"

# Install Kyverno via Helm
kyverno-install:
	@echo "Installing Kyverno..."
	helm repo add kyverno https://kyverno.github.io/kyverno/
	helm repo update
	helm upgrade --install kyverno kyverno/kyverno \
		--namespace kyverno \
		--create-namespace \
		--wait
	@echo ""
	@echo "Kyverno installed. Waiting for webhook to be ready..."
	kubectl wait --for=condition=ready pod \
		-l app.kubernetes.io/component=admission-controller \
		-n kyverno \
		--timeout=120s
	@echo "Kyverno ready."

# Apply Kyverno hardening ClusterPolicy
apply-policies:
	@echo "Applying Kyverno hardening policies..."
	kubectl apply -f policies/kyverno-edera-hardening.yaml
	@echo ""
	@echo "Policies applied. Verify enforcement with:"
	@echo "  make verify"

# Apply default-deny egress NetworkPolicy to NAMESPACE
apply-network-policy:
	@echo "Applying default-deny egress policy to namespace: $(NAMESPACE)"
	sed 's/REPLACE_WITH_NAMESPACE/$(NAMESPACE)/' policies/network-policy-default-deny-egress.yaml | kubectl apply -f -
	@echo "Default-deny egress applied."

# Deploy the hardened AI agent example
apply-ai-agent:
	@echo "Deploying example AI agent pod..."
	@echo "NOTE: Update examples/ai-agent-pod.yaml with your image before using in production."
	kubectl apply -f examples/ai-agent-pod.yaml
	@echo ""
	@echo "Verify zone isolation:"
	@echo "  kubectl get pod ai-agent -o jsonpath='{.spec.runtimeClassName}' && echo"

# Verify hardening policies are enforced
verify:
	@echo "=== Verifying hardening policies ==="
	@echo ""
	@echo "Test 1: hostPath volumes must be denied..."
	@kubectl run hostpath-test --image=busybox --dry-run=server \
		--overrides='{"spec":{"volumes":[{"name":"host","hostPath":{"path":"/tmp"}}],"containers":[{"name":"c","image":"busybox","volumeMounts":[{"name":"host","mountPath":"/host"}]}]}}' \
		2>&1 | grep -q "denied" \
		&& echo "  PASS: hostPath denied" \
		|| echo "  FAIL: hostPath was not denied -- is the Kyverno policy applied?"
	@echo ""
	@echo "Test 2: hostNetwork must be denied..."
	@kubectl run hostnet-test --image=busybox --dry-run=server \
		--overrides='{"spec":{"hostNetwork":true}}' \
		2>&1 | grep -q "denied" \
		&& echo "  PASS: hostNetwork denied" \
		|| echo "  FAIL: hostNetwork was not denied"
	@echo ""
	@echo "Test 3: Default-deny egress must be present in $(E2E_NAMESPACE)..."
	@kubectl get networkpolicy default-deny-egress -n $(E2E_NAMESPACE) > /dev/null 2>&1 \
		&& echo "  PASS: default-deny egress NetworkPolicy present" \
		|| echo "  FAIL: NetworkPolicy not found in $(E2E_NAMESPACE)"
	@echo ""
	@echo "=== Verification complete ==="

# Full end-to-end test: install Kyverno, apply all policies, verify
e2e:
	@echo "=== Edera hardening end-to-end test ==="
	@echo ""
	@echo "Step 1: Install Kyverno..."
	$(MAKE) kyverno-install
	@echo ""
	@echo "Step 2: Apply hardening policies..."
	$(MAKE) apply-policies
	@echo ""
	@echo "Step 3: Create test namespace..."
	kubectl create namespace $(E2E_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "Step 4: Apply default-deny egress to test namespace..."
	$(MAKE) apply-network-policy NAMESPACE=$(E2E_NAMESPACE)
	@echo ""
	@echo "Step 5: Verify enforcement..."
	$(MAKE) verify
	@echo ""
	@echo "Hardening e2e complete. Run 'make e2e-clean' to remove test resources."

# Remove all e2e test resources
e2e-clean:
	@echo "Removing hardening test resources..."
	-kubectl delete clusterpolicy edera-hardening
	-kubectl delete namespace $(E2E_NAMESPACE)
	-helm uninstall kyverno -n kyverno
	-kubectl delete namespace kyverno
	@echo "Done."

# Remove hardening resources from NAMESPACE (non-destructive)
clean:
	-kubectl delete clusterpolicy edera-hardening
	-kubectl delete networkpolicy default-deny-egress -n $(NAMESPACE)
	-kubectl delete pod ai-agent --ignore-not-found
	@echo "Hardening resources removed."
