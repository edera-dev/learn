.PHONY: help apply-policies apply-network-policy apply-ai-agent verify clean

NAMESPACE ?= default

help:
	@echo "Edera production hardening examples"
	@echo ""
	@echo "Usage:"
	@echo "  make apply-policies               - Apply Kyverno hardening policies (requires Kyverno)"
	@echo "  make apply-network-policy         - Apply default-deny egress policy to NAMESPACE"
	@echo "  make apply-ai-agent               - Deploy example AI agent pod"
	@echo "  make verify                       - Verify policies are enforced"
	@echo "  make clean                        - Remove all hardening resources"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=<ns>   Target namespace for network policy (default: default)"
	@echo ""
	@echo "Example:"
	@echo "  make apply-network-policy NAMESPACE=tenant-a"

apply-policies:
	@echo "Applying Kyverno hardening policies..."
	@echo "NOTE: Kyverno must be installed. Run 'make kyverno-install' from validate/ if needed."
	kubectl apply -f policies/kyverno-edera-hardening.yaml
	@echo ""
	@echo "Policies applied. Test enforcement with:"
	@echo "  make verify"

apply-network-policy:
	@echo "Applying default-deny egress policy to namespace: $(NAMESPACE)"
	@sed 's/REPLACE_WITH_NAMESPACE/$(NAMESPACE)/' policies/network-policy-default-deny-egress.yaml | kubectl apply -f -
	@echo ""
	@echo "Default-deny egress applied. Add allow rules for workload-specific destinations."

apply-ai-agent:
	@echo "Deploying example AI agent pod..."
	@echo "NOTE: Update examples/ai-agent-pod.yaml with your image before running."
	kubectl apply -f examples/ai-agent-pod.yaml
	@echo ""
	@echo "Verify zone isolation with:"
	@echo "  kubectl get pod ai-agent -o jsonpath='{.spec.runtimeClassName}' && echo"

verify:
	@echo "=== Verifying hardening policies are enforced ==="
	@echo ""
	@echo "Test 1: hostPath should be denied..."
	@kubectl run hostpath-test --image=busybox --dry-run=server \
		--overrides='{"spec":{"volumes":[{"name":"host","hostPath":{"path":"/tmp"}}],"containers":[{"name":"c","image":"busybox","volumeMounts":[{"name":"host","mountPath":"/host"}]}]}}' \
		2>&1 | grep -q "denied" && echo "PASS: hostPath denied" || echo "FAIL: hostPath was not denied"
	@echo ""
	@echo "Test 2: hostNetwork should be denied..."
	@kubectl run hostnet-test --image=busybox --dry-run=server \
		--overrides='{"spec":{"hostNetwork":true}}' \
		2>&1 | grep -q "denied" && echo "PASS: hostNetwork denied" || echo "FAIL: hostNetwork was not denied"
	@echo ""
	@echo "Verification complete."

clean:
	-kubectl delete clusterpolicy edera-hardening
	-kubectl delete networkpolicy default-deny-egress -n $(NAMESPACE)
	-kubectl delete pod ai-agent --ignore-not-found
	@echo "Hardening resources removed."
