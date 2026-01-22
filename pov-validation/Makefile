.PHONY: help setup security-test performance-test operations-test clean

help:
	@echo "POV Validation Test Suite"
	@echo ""
	@echo "Prerequisites:"
	@echo "  make setup              - Install RuntimeClass and verify cluster"
	@echo ""
	@echo "Security Tests:"
	@echo "  make welcome            - Deploy welcome-to-edera test pod"
	@echo "  make leaky-vessel       - Run Leaky Vessel container escape demo"
	@echo "  make falco-install      - Install Falco for security monitoring"
	@echo "  make falco-test         - Run Falco integration test"
	@echo ""
	@echo "Performance Tests:"
	@echo "  make iperf              - Run iperf network benchmark"
	@echo "  make iperf-baseline     - Run iperf baseline (without Edera)"
	@echo "  make kbench             - Run kbench CPU/storage benchmark"
	@echo "  make kbench-baseline    - Run kbench baseline (without Edera)"
	@echo ""
	@echo "Operations Tests:"
	@echo "  make grafana-install    - Install Prometheus/Grafana stack"
	@echo "  make kyverno-install    - Install Kyverno"
	@echo "  make kyverno-test       - Test Kyverno auto-assignment policy"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean-security     - Remove security test resources"
	@echo "  make clean-performance  - Remove performance test resources"
	@echo "  make clean-operations   - Remove operations test resources"
	@echo "  make clean              - Remove all test resources"

# Setup
setup:
	@echo "Installing Edera RuntimeClass..."
	kubectl apply -f https://public.edera.dev/kubernetes/runtime-class.yaml
	@echo ""
	@echo "Verifying setup..."
	kubectl get runtimeclass edera
	kubectl get nodes -l runtime=edera

# Security Tests
welcome:
	kubectl apply -f security/welcome-to-edera.yaml
	@echo "Waiting for pod to be ready..."
	kubectl wait --for=condition=ready pod/welcome-to-edera --timeout=120s
	@echo ""
	@echo "Pod is running. Verify zone on node with: sudo protect zone list"

leaky-vessel:
	kubectl apply -f security/leaky-vessel-test.yaml
	@echo "Waiting for pod to complete..."
	kubectl wait --for=condition=ready pod/leaky-vessel-test --timeout=120s || true
	@echo ""
	@echo "Check logs with: kubectl logs leaky-vessel-test"

leaky-vessel-baseline:
	@echo "WARNING: This demonstrates a container escape on unprotected runtime"
	@echo "Only run on test clusters!"
	kubectl apply -f security/leaky-vessel-no-edera.yaml

falco-install:
	helm repo add falcosecurity https://falcosecurity.github.io/charts
	helm repo update
	helm install falco falcosecurity/falco --namespace falco --create-namespace

falco-test:
	kubectl apply -f security/falco-test.yaml
	kubectl wait --for=condition=ready pod/falco-test --timeout=120s
	@echo ""
	@echo "Trigger alert with: kubectl exec -it falco-test -- cat /etc/shadow"
	@echo "View alerts with: kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50"

# Performance Tests
iperf:
	kubectl apply -f performance/iperf-server.yaml
	kubectl apply -f performance/iperf-client.yaml
	@echo "Waiting for pods to be ready..."
	kubectl wait --for=condition=ready pod/iperf-server --timeout=120s
	kubectl wait --for=condition=ready pod/iperf-client --timeout=120s
	@echo ""
	@echo "Run benchmark with: kubectl exec -it iperf-client -- iperf3 -c iperf-server -t 30"

iperf-baseline:
	kubectl apply -f performance/iperf-baseline.yaml
	@echo "Waiting for pods to be ready..."
	kubectl wait --for=condition=ready pod/iperf-server-baseline --timeout=120s
	kubectl wait --for=condition=ready pod/iperf-client-baseline --timeout=120s
	@echo ""
	@echo "Run benchmark with: kubectl exec -it iperf-client-baseline -- iperf3 -c iperf-server-baseline -t 30"

kbench:
	kubectl apply -f performance/kbench-edera.yaml
	@echo "Waiting for job to complete..."
	kubectl wait --for=condition=complete job/kbench-edera --timeout=300s
	@echo ""
	kubectl logs job/kbench-edera

kbench-baseline:
	kubectl apply -f performance/kbench-baseline.yaml
	@echo "Waiting for job to complete..."
	kubectl wait --for=condition=complete job/kbench-baseline --timeout=300s
	@echo ""
	kubectl logs job/kbench-baseline

# Operations Tests
grafana-install:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
	@echo ""
	@echo "Access Grafana with: kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
	@echo "Default credentials: admin/prom-operator"

kyverno-install:
	helm repo add kyverno https://kyverno.github.io/kyverno/
	helm repo update
	helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace

kyverno-test:
	kubectl create namespace secure-workloads --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f operations/kyverno-edera-policy.yaml
	kubectl apply -f operations/auto-edera-test.yaml
	@echo ""
	@echo "Verify RuntimeClass was added:"
	kubectl get pod auto-edera-test -n secure-workloads -o yaml | grep runtimeClassName

# Cleanup
clean-security:
	-kubectl delete -f security/welcome-to-edera.yaml
	-kubectl delete -f security/leaky-vessel-test.yaml
	-kubectl delete -f security/leaky-vessel-no-edera.yaml
	-kubectl delete -f security/falco-test.yaml
	-helm uninstall falco -n falco
	-kubectl delete namespace falco

clean-performance:
	-kubectl delete -f performance/iperf-server.yaml
	-kubectl delete -f performance/iperf-client.yaml
	-kubectl delete -f performance/iperf-baseline.yaml
	-kubectl delete job kbench-edera kbench-baseline

clean-operations:
	-kubectl delete -f operations/auto-edera-test.yaml
	-kubectl delete -f operations/kyverno-edera-policy.yaml
	-kubectl delete namespace secure-workloads
	-kubectl delete servicemonitor edera-protect -n monitoring
	-helm uninstall kyverno -n kyverno
	-kubectl delete namespace kyverno
	-helm uninstall prometheus -n monitoring
	-kubectl delete namespace monitoring

clean: clean-security clean-performance clean-operations
	@echo "All POV test resources removed"
