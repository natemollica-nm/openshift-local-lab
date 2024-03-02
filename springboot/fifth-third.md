## Consul Kubernetes + Java Springboot Integration (Transparent Proxy)

Testing Conducted w/:

```shell
# Currently used 5/3 Versions
CONSUL_RELEASE_VERSION=1.16.1
CONSUL_K8s_RELEASE_VER=1.2.1
CONSUL_DP_RELEASE_VER=1.2.1
```

### Summary Notes:

* Using L4 ServiceIntentions (applied both ways)
* TCP Protocol Defaults
* Maglev Loadbalancer w/ `HOST` header `hashPolicy`
* Using KubeDNS with `http://spring-boot-admin-server.consul.svc.cluster.local/admin` URL
* Confirmed that SBC requires `dialedDirectly: true` for spring-boot health checks
  * **_Note_**: SBA was fine without this setting
* Confirmed that SBC -> SBA **_and_** SBA -> SBC `ServiceIntentions` allow are **_both_** required
* Confirmed that `ServiceDefaults` default protocol `tcp` is OK
* Tested with and without `ServiceResolver` loadbalancer configurations adjustments:
  * Local reproduction worked with and without `maglev` HOST header hash policy (interesting...)
* Testing with various namespace combinations proved to work in all cases:
  * Deployment of SBA + SBC to `consul` namespace
  * Deployment of SBA + SBC to `spring-boot` namespace (consul deployed to `consul` namespace)
  * Deployment of SBA + SBC to `spring-boot-sba` and `spring-boot-sbc` namespaces (consul deployed to `consul` namespace)

### Transparent Proxy Configuration Settings:

**SBA|SBC - Deployment Annotations**

```yaml
# Local Reproduction Testing
      annotations:
        'consul.hashicorp.com/connect-inject': 'true'
        'consul.hashicorp.com/transparent-proxy': 'true'
        'consul.hashicorp.com/enable-metrics-merging': 'false'
        'consul.hashicorp.com/transparent-proxy-overwrite-probes': 'true'
```

**Consul Overrides**

```yaml
# Local Reproduction Test Repo
global:
  enableConsulNamespaces: true
  adminPartitions:
    enabled: true
    name: "default"
connectInject:
  enabled: true
  default: false
  transparentProxy:
    defaultEnabled: false
    defaultOverwriteProbes: false
  consulNamespaces:
    mirroringK8S: true
```


```yaml
# Fifth-Third Overrides
global:
  enableConsulNamespaces: true
  openshift:
    enabled: true
  datacenter: cash-lab2
  adminPartitions:
    enabled: true
connectInject:
  enabled: true
  default: true
  transparentProxy:
    defaultEnabled: true
  consulNamespaces:
    mirroringK8S: true
  namespaceSelector: |
    matchLabels:
      consulInjector: "true"
```

### To do:

* ✅ Test cross-namespace functionality (deploy SBA + SBC to non-consul namespace)
  * ✅ SBA + SBC in `spring-boot` namespace: **_working_**
  * ✅ SBA in `spring-boot-sba` ns + SBC in `spring-boot-sbc` namespace:  **_working_**
* ✅ Test without `adminParitions.name: "default"` set (as they have): **_working_**
  * ~~Potential issue previously seen where, if this is not set the partition field on some
    CRDs end up empty resulting in various mesh issues.~~
* ✅ Test on consul v1.16.1 | consul-k8s|dp v1.2.1
  * ~~Maybe bug that has since been fixed~~ 
  * **_Results_**: Works on v1.16.1/v1.2.1
* Check with 5/3 on OC Multus CNI Network Attachment Definition being set for the SBA and SBC Namespaces 
  * ✅ OpenShift network isolation **_enabled_**: a Network Attachment Definition will be need per namespace. 
  * ~~OpenShift network isolation **_disabled_**: it is possible to use the Network Attachment Definition created in the namespace 
    where Consul is installed. See [Consul OpenShift CNI Network Attachment Definition](#Consul OpenShift CNI Network Attachment Definition) below.~~
* Follow-up on dynamic cluster spiffe subject alt names finding:
  * Found empty filed in 5/3's SNI match following the datacenter entry
  * Local working SNI matcher: `spiffe://4e5583bd-2b03-1f16-c4a4-9d515595cac4.consul/ns/spring-boot-sba/dc/dc1/svc/spring-boot-admin-server`
  * Example of what 5/3 saw: `spiffe://4e5583bd-2b03-1f16-c4a4-9d515595cac4.consul/ns/spring-boot-sba/dc//svc/spring-boot-admin-server`
* Logs for SBC Clients DEBUG enabled
* Test CORS with "*"
* Consul Dataplane DEBUG log capture from SBA and SBC proxies
* Update ServiceResolver with loadBalancer removed
  * Ensure dialedDirectly: true for both still in place
* Check client URL environment variable setting


### Consul OpenShift CNI Network Attachment Definition

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: consul-cni
spec:
  config: '{
            "cniVersion": "0.3.1",
            "type": "consul-cni",
            "cni_bin_dir": "/var/lib/cni/bin",
            "cni_net_dir": "/etc/kubernetes/cni/net.d",
            "kubeconfig": "ZZZ-consul-cni-kubeconfig",
            "log_level": "info",
            "multus": true,
            "name": "consul-cni",
            "type": "consul-cni"
        }'
```

**Service Deployment Annotation**

```yaml
annotations:
  'k8s.v1.cni.cncf.io/networks': '[{ "name":"consul-cni" }]'
```