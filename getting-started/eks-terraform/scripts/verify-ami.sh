#!/bin/bash

# Script to verify that EKS nodes are running the correct Edera AMI
# This script corresponds to the verification code from the docs

set -e

echo "🔍 Verifying Edera AMI on all nodes..."
echo ""

# Get region from Terraform output or default to us-west-2
REGION=${AWS_REGION:-us-west-2}

# Check if we're in a Terraform directory
if [ ! -f "main.tf" ]; then
    echo "❌ This script must be run from the eks-terraform directory"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ kubectl is not configured or cluster is not accessible"
    echo "Run: make configure"
    exit 1
fi

echo "📊 AMI Verification Results:"
echo "=========================="

for node in $(kubectl get nodes -o name); do
    node_name=$(echo "$node" | cut -d'/' -f2)

    # Get instance ID from node's provider ID
    instance_id=$(kubectl get "$node" -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)

    if [ -z "$instance_id" ]; then
        echo "❌ $node_name: Could not get instance ID"
        continue
    fi

    # Get AMI ID from instance
    ami_id=$(aws ec2 describe-instances \
        --instance-ids "$instance_id" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].ImageId' \
        --output text 2>/dev/null)

    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        echo "❌ $node_name: Could not get AMI ID for instance $instance_id"
        continue
    fi

    # Get AMI name from AMI ID
    ami_name=$(aws ec2 describe-images \
        --image-ids "$ami_id" \
        --region "$REGION" \
        --query 'Images[0].Name' \
        --output text 2>/dev/null)

    if [ -z "$ami_name" ] || [ "$ami_name" = "None" ]; then
        echo "❌ $node_name: Could not get AMI name for $ami_id"
        continue
    fi

    # Check if it's an Edera AMI
    if echo "$ami_name" | grep -q "edera-protect"; then
        echo "✅ $node_name: $ami_id ($ami_name)"
    else
        echo "❌ $node_name: $ami_id ($ami_name) - NOT an Edera AMI!"
    fi
done

echo ""
echo "🏷️  Node Labels Verification:"
echo "=========================="

# Check for runtime=edera labels
edera_nodes=$(kubectl get nodes -l runtime=edera --no-headers 2>/dev/null | wc -l | tr -d ' ')
total_nodes=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')

if [ "$edera_nodes" -eq "$total_nodes" ] && [ "$edera_nodes" -gt 0 ]; then
    echo "✅ All $total_nodes nodes have the 'runtime=edera' label"
else
    echo "❌ Only $edera_nodes out of $total_nodes nodes have the 'runtime=edera' label"
    echo ""
    echo "Nodes without 'runtime=edera' label:"
    kubectl get nodes -l '!runtime' --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
    kubectl get nodes -l 'runtime!=edera' --no-headers 2>/dev/null | awk '{print "  - " $1}' || true
fi

echo ""
echo "🎯 RuntimeClass Verification:"
echo "=========================="

if kubectl get runtimeclass edera >/dev/null 2>&1; then
    echo "✅ Edera RuntimeClass is installed"

    # Check nodeSelector in RuntimeClass
    node_selector=$(kubectl get runtimeclass edera -o jsonpath='{.scheduling.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]}' 2>/dev/null)
    if echo "$node_selector" | grep -q '"key":"runtime"' && echo "$node_selector" | grep -q '"values":\["edera"\]'; then
        echo "✅ RuntimeClass has correct nodeSelector (runtime=edera)"
    else
        echo "❌ RuntimeClass nodeSelector configuration is incorrect"
    fi
else
    echo "❌ Edera RuntimeClass is not installed"
    echo "Run: kubectl apply -f kubernetes/runtime-class.yaml"
fi

echo ""
echo "🚀 Test Workload Status:"
echo "======================"

if kubectl get namespace edera-test >/dev/null 2>&1; then
    pod_status=$(kubectl get pod edera-test-pod -n edera-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    runtime_class=$(kubectl get pod edera-test-pod -n edera-test -o jsonpath='{.spec.runtimeClassName}' 2>/dev/null || echo "NotFound")

    if [ "$pod_status" = "Running" ] && [ "$runtime_class" = "edera" ]; then
        echo "✅ Test pod is running with Edera runtime"

        # Show pod details
        echo ""
        kubectl get pods -n edera-test -o wide
    elif [ "$pod_status" = "NotFound" ]; then
        echo "ℹ️  No test workload deployed"
        echo "Run: make test"
    else
        echo "❌ Test pod status: $pod_status, runtime: $runtime_class"
        echo "Run: kubectl describe pod edera-test-pod -n edera-test"
    fi
else
    echo "ℹ️  No test namespace found"
    echo "Run: make test"
fi

echo ""