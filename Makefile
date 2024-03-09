IP=$(shell ifconfig en4 | grep -oE 'inet [0-9.]+' | tr -d 'inet\s' | awk '{print $2}' | sed 's/^[[:space:]]*//')

OFFLINE_API_TOKEN=$(shell cat $(PWD)/.secrets/ocm-api-token)
SSH_KEY_LOCAL=$(shell cat $(PWD)/.secrets/openshift-key.pem.pub)
PULL_SECRET=.secrets/pull-secret.txt

OPENSHIFT_VERSION=4.14.12
SHELL=$(PWD)/shell

OPENSHIFT_DOMAIN=openshift.local.io
OPENSHIFT_CLUSTER=consul-openshift-sno
OPENSHIFT_HOSTNAME=consul-openshift-sno

# pull and push non-local image vars
CONSUL_RELEASE_VERSION=1.17.3
CONSUL_K8s_RELEASE_VER=1.3.3
CONSUL_DP_RELEASE_VER=1.3.3

# Enable/disable local helm chart usage
USE_LOCAL_HELM_CHARTS=0
ifeq ($(USE_LOCAL_HELM_CHARTS), 1)
    CHART_DIR=~/HashiCorp/consul-k8s/charts/consul
else
    CHART_DIR=hashicorp/consul
endif

##@ Prerequisites
.PHONY: openshift-tools rhcos-live-iso
openshift-tools: ## install oc and openshift-tools (aarch64) to /usr/local/bin with specific versioning
	@scripts/openshift-tools.sh $(OPENSHIFT_VERSION)

rhcos-live-iso: ## download openshift-install stream version iso/rhcos-live.iso
	@scripts/rhcos-live.sh

##@ Full Configuration Runs
.PHONY: ign-sno-openshift-cluster agent-sno-openshift-cluster
ign-sno-openshift-cluster: teardown local-openshift-dns openshift-coreos-ign-installer ##   Local DNS + SNO Install using coreos ignition

agent-sno-openshift-cluster: teardown local-openshift-dns openshift-agent-installer ## Local DNS + SNO Install using agent-installer

##@ Openshift Agent Installer
.PHONY: openshift-agent-installer
openshift-agent-installer: ##      configure and run podman agent configuration container for agent-based installer
	@scripts/sno-installer.sh "$(OPENSHIFT_VERSION)" "$(SSH_KEY_LOCAL)" "$(PULL_SECRET)" "$(OPENSHIFT_HOSTNAME)" "$(OPENSHIFT_CLUSTER)" "$(OPENSHIFT_DOMAIN)" "$(IP)" agent

.PHONY: openshift-coreos-ign-installer
openshift-coreos-ign-installer: ## configure and run podman agent configuration for ignition-based installer
	@scripts/sno-installer.sh "$(OPENSHIFT_VERSION)" "$(SSH_KEY_LOCAL)" "$(PULL_SECRET)" "$(OPENSHIFT_HOSTNAME)" "$(OPENSHIFT_CLUSTER)" "$(OPENSHIFT_DOMAIN)" "$(IP)" ign

.PHONY: openshift-ai-installer
openshift-ai-installer:
	@scripts/openshift-ai-deployment.sh $(OPENSHIFT_VERSION) $(SSH_KEY_LOCAL) $(PULL_SECRET) $(OPENSHIFT_HOSTNAME) $(OPENSHIFT_CLUSTER) $(OPENSHIFT_DOMAIN) $(IP)

.PHONY: monitor-installation
monitor-installation:
	@openshift-install --dir=ocp agent wait-for bootstrap-complete

##@ OpenShift Configuration

.PHONY: net-attachment-def
net-attachment-def: ## Apply crds/network-attachment-definition.yaml for consul-cni
	@oc apply -f crds/network-attachment-definition.yaml -n consul

.PHONY: scc
scc: ## Update consul namespace SCC to include consul-tproxy-scc | alt. to 'anyuid'
	@oc apply -f scc/consul-tproxy-scc.yaml
	@oc adm policy add-scc-to-group consul-tproxy-scc system:serviceaccounts:consul


##@ DNS (full-config target: local-openshift-dns)
local-openshift-dns: teardown podman disable-podman-dns dnsmasq local-dns-resolvers verify-dns ## rebuild podman vm and fully configure local openshift dns settings

local-dns-resolvers: ## configures /etc/resolver/<openshift_domain> and /etc/hosts with OpenShift local domain
	@./scripts/update-mac-systemd.sh $(IP) $(OPENSHIFT_DOMAIN)

disable-podman-dns: ##  disable DNSStubListener for podman dnsmasq container
	@podman machine ssh sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf
	@podman machine ssh systemctl restart systemd-resolved

dnsmasq: ##     configure dnsmasq.conf with host and domain info, and run dnsmasq podman container
	@scripts/dnsmasq.sh $(OPENSHIFT_HOSTNAME) $(OPENSHIFT_DOMAIN) $(IP)
	@podman machine ssh ss -ltnup
	@read -p 'dnsmasq: confirm port 53 is no longer in use on podman (any key to continue | ctrl+c to cancel)'
	@podman run -d --rm -p 53:53/udp -v ./dnsmasq.conf:/etc/dnsmasq.conf --name dnsmasq quay.io/crcont/dnsmasq:latest

restart-dnsmasq: ##     stop and rm dnsmasq container, apply dnsmasq.conf updates, and re-start dnsmasq podman container
	@printf '%s\n' "restarting dnsmasq podman container"
	@podman restart dnsmasq
	@podman container list
	@scripts/verify-dns.sh $(OPENSHIFT_CLUSTER) $(OPENSHIFT_HOSTNAME) $(OPENSHIFT_DOMAIN)

.PHONY:
verify-dns: ##     run openshift required dns configuration settings with lab dnsmasq configurations set
	@scripts/verify-dns.sh $(OPENSHIFT_CLUSTER) $(OPENSHIFT_HOSTNAME) $(OPENSHIFT_DOMAIN)

##@ Podman
.PHONY: podman
podman: ## preconfigure and start podman vm in root mode
	@printf '%s\n' "podman: initializing and starting podman vm"
	@podman machine init
	@podman machine set --rootful
	@podman machine start

.PHONY: reset-podman
reset-podman: ## terminate and cleanup podman vm files and re-start podman vm
	@printf '%s\n' "podman: resetting any running default podman vm"
	@podman volume prune -f >/dev/null 2>&1 || true
	@podman machine stop >/dev/null 2>&1 || true
	@podman machine rm podman-machine-default -f >/dev/null 2>&1 || true
	@podman machine init
	@podman machine set --rootful
	@podman machine start

##@ Cleanup
.PHONY: rm-podman
rm-podman: ## terminate and cleanup podman vm
	@printf '%s\n' "podman: removing any running default podman vm"
	@podman volume prune -f >/dev/null 2>&1 || true
	@podman machine stop >/dev/null 2>&1 || true
	@podman machine rm podman-machine-default -f >/dev/null 2>&1 || true
	@printf '%s\n' "podman: vm removed!"

clean: ## rm agent-installer cache and ocp/ configurations
	@clear
	@printf '%s\n%s\n%s\n%s\n' "agent-installer cleanup: clearing" "  => .installer_cache/" "  => ocp/ " "  => /etc/resolver/<openshift_domain>"
	@rm -rf ocp .installer_cache/image_cache .installer_cache/files_cache iso.ign &>/dev/null || true
	@mkdir -p ocp .installer_cache/image_cache .installer_cache/files_cache
	@printf '%s\n' "hosts-file: removing $(OPENSHIFT_DOMAIN) entry from /etc/hosts"
	@sudo sed -i '' "/$(OPENSHIFT_DOMAIN)/d" /etc/hosts
	@printf '%s\n' "cleanup complete!"

.PHONY: teardown
teardown: rm-podman clean ## stop podman vm and cleanup agent-installer directories

# //////////////////////////////////////////////////////////////////////////////////// #
# ///////////////////////////// Consul Install  ////////////////////////////////////// #
##@ Consul
.PHONY: consul
consul: consul-versions consul-project pull-secret install-consul ## Verifies consul-specific versioning, creates openshift consul project + pull-secret, and runs helm installation

.PHONY: consul-project
consul-project: ## Create openshift consul project
	@oc new-project consul

.PHONY: pull-secret
pull-secret: ## Create openshift consul pull-secret object
	@oc create -f .secrets/pull-secret.yaml
	@oc create -f .secrets/pull-secret.yaml --namespace consul

.PHONY: install-consul
install-consul: helm-update-repo consul-release proxy-defaults net-attachment-def scc ## Run consul helm installation | Set proxy-defaults | Configure consul-cni network attachment and SCC

.PHONY: upgrade-consul
upgrade-consul: helm-update-repo helm-upgrade-consul ## Run helm upgrade on consul with updates from values-ent.yaml

.PHONY: consul-release
consul-release:
	@scripts/install-consul.sh $(CHART_DIR) $(CONSUL_RELEASE_VERSION) $(CONSUL_K8s_RELEASE_VER)

.PHONY: helm-upgrade-consul
helm-upgrade-consul:
	@scripts/helm-upgrade-consul.sh $(CHART_DIR) $(CONSUL_K8s_RELEASE_VER)

.PHONY: uninstall-consul
uninstall-consul: ## Run helm uninstall on consul
	@scripts/uninstall-consul.sh "$$CLUSTER1_CONTEXT"

.PHONY: cluster-peers
cluster-peers:
	@scripts/cluster-peers.sh

.PHONY: proxy-defaults
proxy-defaults: ## Apply crds/proxy-defaults.yaml to openshift cluster
	@oc apply --context "$$CLUSTER1_CONTEXT" -f crds/proxy-defaults.yaml

.PHONY: consul-core-dns
consul-core-dns: ## Retrieve consul-dns service clusterIP information to update openshift dns.operator for DNS forwarding
	@printf '%s' "consul-dns-cluster-ip: "
	@oc get svc consul-dns --namespace "$$CONSUL_NS" --output jsonpath='{.spec.clusterIP}'
	@printf '\n%s' "    => oc edit dns.operator/default"

.PHONY: bootstrap-token
bootstrap-token: ## Retrieve and print consul bootstrap-token secretID
	@oc get secret --context "$$CLUSTER1_CONTEXT" --namespace consul consul-bootstrap-acl-token -o yaml | yq -r '.data.token' | base64 -d

##@ Test Applications
.PHONY: static-services
static-services: ## Deploy static-server and static-client apps to openshift
	@scripts/static-services.sh

.PHONY: delete-static-services
delete-static-services: ## Delete static-server and static-client apps from openshift
	@scripts/static-services.sh delete

.PHONY: fake-services
fake-services: ## Deploy fake-service frontend + backend apps to openshift | Configure consul intentions, service-defaults, service-resolver for services
	@scripts/fake-services.sh

.PHONY: delete-fake-services
delete-fake-services: ## Delete fake-service frontend + backend apps from openshift | Deletes consul intentions, service-defaults, service-resolver for services
	@scripts/fake-services.sh delete

##@ Misc.
.PHONY: cluster-details
cluster-details: ## Show Openshift Cluster Settings
	@printf 'openshift version: %s\n' $(OPENSHIFT_VERSION)
	@printf 'openshift cluster name: %s\n' $(OPENSHIFT_CLUSTER)
	@printf 'openshift node name: %s\n' $(OPENSHIFT_HOSTNAME)
	@printf 'openshift node ip: %s\n' $(IP)
	@printf 'openshift cluster domain: %s\n' $(OPENSHIFT_DOMAIN)
	@printf 'pull-secret file: %s\n' $(PULL_SECRET)

PHONY: post-install-verify
post-install-verify:
	@oc get co

PHONY: nodes csr
nodes:
	@oc get nodes
csr:
	@oc get csr

.PHONY: helm-update-repo
helm-update-repo:
	@scripts/clean-repo-cache.sh

.PHONY: consul-versions
consul-versions: ## Review and optionally update .k8sImages.env for consul, consul-k8s, and consul-dp image versions
	@printf '%s\n' "CONSUL_RELEASE_VERSION: $(CONSUL_RELEASE_VERSION)"
	@printf '%s\n' "CONSUL_K8s_RELEASE_VER: $(CONSUL_K8s_RELEASE_VER)"
	@printf '%s\n' "CONSUL_DP_RELEASE_VER: $(CONSUL_DP_RELEASE_VER)"
	@read -p 'update k8sImages.env with these versions? (any key to continue | ctrl+c to cancel)'
	@echo "export CONSUL_IMAGE=registry.access.redhat.com/hashicorp/consul-enterprise:${CONSUL_RELEASE_VERSION}-ent-ubi" > .k8sImages.env
	@echo "export CONSUL_K8S_IMAGE=registry.access.redhat.com/hashicorp/consul-k8s-control-plane:${CONSUL_K8s_RELEASE_VER}-ubi" >> .k8sImages.env
	@echo "export CONSUL_K8S_DP_IMAGE=registry.access.redhat.com/hashicorp/consul-dataplane:${CONSUL_DP_RELEASE_VER}-ubi" >> .k8sImages.env
	@printf '%s\n' "k8sImages.env updated!"

.DEFAULT_GOAL := help
##@ Help

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php
.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)