# Installing Datadog on OpenShift

Ref: [install-openshift](https://github.com/DataDog/datadog-operator/blob/main/docs/install-openshift.md)


Install the Datadog Operator:

```shell
$ helm install \
    datadog-operator \
    datadog/datadog-operator \
    --namespace "datadog" \
    --set image.tag="1.3.0" \
    --set-json podAnnotations='{"consul.hashicorp.com/connect-inject": "false"}' \
    --set replicaCount=1 \
    --kubeconfig openshift/kubeconfig \
    --kube-context "$CLUSTER1_CONTEXT"
  
```

Create Kubernetes secret for DataDog Agent API and App keys:

```shell
$ openshift/oc \
    --kubeconfig openshift/kubeconfig \
    create secret generic datadog-secret \
    --namespace datadog \
    --from-literal api-key="$DATADOG_API_KEY" \
    --from-literal app-key="$DATADOG_APP_KEY"
```

Install Datadog Agent using manifest:

```shell
$ openshift/oc --kubeconfig openshift/kubeconfig apply -f datadog/datadog-agent.yaml
```

