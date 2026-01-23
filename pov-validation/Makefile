.PHONY: help setup security-test performance-test operations-test clean

help:
	@echo "POV Validation Test Suite"
	@echo ""
	@echo "Prerequisites:"
	@echo "  make setup              - Install RuntimeClass and verify cluster"
	@echo ""
	@echo "Security Tests:"
	@echo "  make welcome            - Deploy welcome-to-edera test pod"
	@echo "  make leaky-vessel       - Show secrets exposed without Edera"
	@echo "  make leaky-vessel-secure - Show secrets protected with Edera"
	@echo "  make falco-install      - Install Falco with Edera plugin"
	@echo "  make falco-test         - Deploy Falco test pod (requires Edera Falco plugin)"
	@echo ""
	@echo "Performance Tests:"
	@echo "  make iperf-compare      - Run iperf benchmark with comparison table"
	@echo "  make iperf              - Run iperf network benchmark (Edera only)"
	@echo "  make iperf-baseline     - Run iperf baseline (without Edera)"
	@echo "  make sysbench           - Run sysbench CPU benchmark (Edera)"
	@echo "  make sysbench-baseline  - Run sysbench CPU baseline (without Edera)"
	@echo "  make sysbench-compare   - Run sysbench with comparison table"
	@echo "  make kcbench            - Run kcbench CPU benchmark (kernel compile)"
	@echo "  make kcbench-baseline   - Run kcbench baseline (without Edera)"
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
	@echo "Pod is running. Verify with:"
	@echo "  kubectl get pod welcome-to-edera -o jsonpath='{.spec.runtimeClassName}' && echo"

leaky-vessel:
	@echo "=== Leaky Vessel Demo: Process Isolation ==="
	@echo ""
	@echo "Step 1: Deploy vulnerable pod (no Edera) and raider pod"
	kubectl apply -f security/leaky-vessel-test.yaml
	@echo "Waiting for pods to be ready..."
	kubectl wait --for=condition=ready pod/vulnerable-pod --timeout=120s
	kubectl wait --for=condition=ready pod/raider --timeout=120s
	@echo ""
	@echo "Step 2: Raider attempts to steal secrets from vulnerable pod..."
	@echo ""
	@PID=$$(kubectl exec raider -- /bin/sh -c "ps faux | grep '[s]leep 5' | head -n1 | awk '{print \$$2}'"); \
	if [ -n "$$PID" ]; then \
		echo "Found vulnerable pod process: $$PID"; \
		echo "Secrets stolen:"; \
		kubectl exec raider -- /bin/sh -c "cat /proc/$$PID/environ | tr '\0' '\n' | grep 'PASSWORD\|SECRET'"; \
	else \
		echo "Could not find process"; \
	fi
	@echo ""
	@echo "=== Without Edera, secrets are exposed! ==="
	@echo ""
	@echo "Now run 'make leaky-vessel-secure' to see Edera's protection"

leaky-vessel-secure:
	@echo "=== Deploying secure pod with Edera ==="
	kubectl delete pod vulnerable-pod --force --ignore-not-found
	kubectl apply -f security/secure-pod.yaml
	@echo "Waiting for secure pod..."
	kubectl wait --for=condition=ready pod/secure-pod --timeout=120s
	@echo ""
	@echo "Step 3: Raider attempts to steal secrets from secure pod..."
	@echo ""
	@PID=$$(kubectl exec raider -- /bin/sh -c "ps faux | grep '[s]leep 5' | head -n1 | awk '{print \$$2}'" 2>/dev/null); \
	if [ -n "$$PID" ]; then \
		echo "Found process: $$PID"; \
		kubectl exec raider -- /bin/sh -c "cat /proc/$$PID/environ | tr '\0' '\n' | grep 'PASSWORD\|SECRET'" || echo "Cannot access secrets!"; \
	else \
		echo "No process found - the container is secure!"; \
	fi
	@echo ""
	@echo "=== With Edera, secrets are protected by zone isolation! ==="

falco-install:
	@echo "Installing Falco with Edera plugin support..."
	@echo "NOTE: This requires Edera Protect to be installed on the nodes."
	@echo "See: https://docs.edera.dev/guides/observability/falco-integration/"
	@echo ""
	helm repo add falcosecurity https://falcosecurity.github.io/charts
	helm repo update
	helm upgrade --install falco falcosecurity/falco \
		--namespace falco \
		--create-namespace \
		-f security/falco/falco-edera-values.yaml
	@echo ""
	@echo "Waiting for Falco pods to be ready..."
	kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=falco -n falco --timeout=120s
	@echo ""
	@echo "Falco installed. Verify with:"
	@echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i edera"

falco-test:
	@echo "NOTE: Monitoring inside Edera zones requires the Edera Falco plugin."
	@echo "See: https://docs.edera.dev/guides/observability/falco-integration/"
	@echo ""
	kubectl apply -f security/falco-test.yaml
	kubectl wait --for=condition=ready pod/falco-test --timeout=120s
	@echo ""
	@echo "Test pod deployed. If Edera Falco plugin is installed:"
	@echo "  Trigger alert: kubectl exec -it falco-test -- cat /etc/shadow"
	@echo "  View alerts:   kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50"

# Performance Tests
iperf:
	kubectl apply -f performance/iperf-edera.yaml
	@echo "Waiting for pod to be ready..."
	kubectl wait --for=condition=ready pod/iperf-edera --timeout=120s
	@echo ""
	@POD_IP=$$(kubectl get pod iperf-edera -o jsonpath='{.status.podIP}'); \
	echo "Run benchmark with: kubectl exec -it iperf-edera -c iperf-client -- iperf3 -c $$POD_IP -t 30"

iperf-baseline:
	kubectl apply -f performance/iperf-baseline.yaml
	@echo "Waiting for pod to be ready..."
	kubectl wait --for=condition=ready pod/iperf-baseline --timeout=120s
	@echo ""
	@echo "Run benchmark with: kubectl exec -it iperf-baseline -c iperf-client -- iperf3 -c localhost -t 30"

iperf-compare:
	@echo "=== iperf Network Performance Comparison ==="
	@echo ""
	@echo "Deploying test pods..."
	@kubectl apply -f performance/iperf-edera.yaml -f performance/iperf-baseline.yaml > /dev/null
	@kubectl wait --for=condition=ready pod/iperf-edera pod/iperf-baseline --timeout=120s > /dev/null
	@echo ""
	@echo "Running Edera benchmark (30s)..."
	@POD_IP=$$(kubectl get pod iperf-edera -o jsonpath='{.status.podIP}'); \
	kubectl exec iperf-edera -c iperf-client -- iperf3 -c $$POD_IP -t 30 -J > /tmp/iperf-edera.json 2>/dev/null; \
	echo "Running Baseline benchmark (30s)..."; \
	kubectl exec iperf-baseline -c iperf-client -- iperf3 -c localhost -t 30 -J > /tmp/iperf-baseline.json 2>/dev/null; \
	EDERA=$$(jq '.end.sum_received.bits_per_second' /tmp/iperf-edera.json); \
	BASELINE=$$(jq '.end.sum_received.bits_per_second' /tmp/iperf-baseline.json); \
	EDERA_GBPS=$$(echo "scale=1; $$EDERA / 1000000000" | bc); \
	BASELINE_GBPS=$$(echo "scale=1; $$BASELINE / 1000000000" | bc); \
	PCT=$$(echo "scale=0; $$EDERA * 100 / $$BASELINE" | bc); \
	echo ""; \
	echo "┌─────────────┬────────────────┬──────────────┐"; \
	echo "│ Test        │ Throughput     │ % of Baseline│"; \
	echo "├─────────────┼────────────────┼──────────────┤"; \
	printf "│ Edera       │ %6.1f Gbps    │ %3d%%         │\n" $$EDERA_GBPS $$PCT; \
	printf "│ Baseline    │ %6.1f Gbps    │ 100%%         │\n" $$BASELINE_GBPS; \
	echo "└─────────────┴────────────────┴──────────────┘"

sysbench:
	kubectl apply -f performance/sysbench-edera.yaml
	@echo "Waiting for job to complete..."
	kubectl wait --for=condition=complete job/sysbench-edera --timeout=300s
	@echo ""
	kubectl logs job/sysbench-edera

sysbench-baseline:
	kubectl apply -f performance/sysbench-baseline.yaml
	@echo "Waiting for job to complete..."
	kubectl wait --for=condition=complete job/sysbench-baseline --timeout=300s
	@echo ""
	kubectl logs job/sysbench-baseline

sysbench-compare:
	@echo "=== sysbench CPU Performance Comparison ==="
	@echo ""
	@echo "Deploying test jobs..."
	@kubectl delete job sysbench-edera sysbench-baseline --ignore-not-found > /dev/null 2>&1 || true
	@kubectl apply -f performance/sysbench-edera.yaml -f performance/sysbench-baseline.yaml > /dev/null
	@echo "Waiting for jobs to complete (~90 seconds)..."
	@kubectl wait --for=condition=complete job/sysbench-edera job/sysbench-baseline --timeout=300s > /dev/null
	@echo ""
	@EDERA_EPS=$$(kubectl logs job/sysbench-edera | grep "events per second" | tail -1 | awk '{print $$NF}'); \
	BASELINE_EPS=$$(kubectl logs job/sysbench-baseline | grep "events per second" | tail -1 | awk '{print $$NF}'); \
	EDERA_LAT=$$(kubectl logs job/sysbench-edera | grep "avg:" | tail -1 | awk '{print $$2}'); \
	BASELINE_LAT=$$(kubectl logs job/sysbench-baseline | grep "avg:" | tail -1 | awk '{print $$2}'); \
	PCT=$$(echo "scale=1; $$EDERA_EPS * 100 / $$BASELINE_EPS" | bc); \
	echo "┌─────────────┬─────────────────┬─────────────┬──────────────┐"; \
	echo "│ Test        │ Events/sec      │ Avg Latency │ % of Baseline│"; \
	echo "├─────────────┼─────────────────┼─────────────┼──────────────┤"; \
	printf "│ Edera       │ %10.2f      │ %6.2f ms   │ %5.1f%%       │\n" $$EDERA_EPS $$EDERA_LAT $$PCT; \
	printf "│ Baseline    │ %10.2f      │ %6.2f ms   │ 100.0%%       │\n" $$BASELINE_EPS $$BASELINE_LAT; \
	echo "└─────────────┴─────────────────┴─────────────┴──────────────┘"

kcbench:
	kubectl apply -f performance/kcbench-edera.yaml
	@echo "Waiting for job to complete (this may take 10+ minutes)..."
	kubectl wait --for=condition=complete job/kcbench-edera --timeout=1800s
	@echo ""
	kubectl logs job/kcbench-edera

kcbench-baseline:
	kubectl apply -f performance/kcbench-baseline.yaml
	@echo "Waiting for job to complete (this may take 10+ minutes)..."
	kubectl wait --for=condition=complete job/kcbench-baseline --timeout=1800s
	@echo ""
	kubectl logs job/kcbench-baseline

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
	-kubectl delete -f security/secure-pod.yaml
	-kubectl delete -f security/falco-test.yaml
	-helm uninstall falco -n falco
	-kubectl delete namespace falco

clean-performance:
	-kubectl delete -f performance/iperf-edera.yaml
	-kubectl delete -f performance/iperf-baseline.yaml
	-kubectl delete job sysbench-edera sysbench-baseline
	-kubectl delete job kcbench-edera kcbench-baseline

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
