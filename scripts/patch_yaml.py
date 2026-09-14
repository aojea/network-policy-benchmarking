import yaml
import sys

def patch_yaml(file_path):
    with open(file_path, 'r') as f:
        docs = list(yaml.safe_load_all(f))
    
    for doc in docs:
        if not doc:
            continue
        
        # Inject prometheus metrics into CNI configurations
        if doc.get('kind') == 'Cluster':
            if 'spec' in doc:
                if 'containerd' not in doc['spec']:
                    doc['spec']['containerd'] = {}
                doc['spec']['containerd']['version'] = '2.2.4'
                if 'runc' not in doc['spec']['containerd']:
                    doc['spec']['containerd']['runc'] = {}
                doc['spec']['containerd']['runc']['version'] = '1.3.5'
                doc['spec']['containerd']['configOverride'] = "\n[plugins.\"io.containerd.nri.v1.nri\"]\n  disable = false\n"
                if 'nri' not in doc['spec']['containerd']:
                    doc['spec']['containerd']['nri'] = {}
                doc['spec']['containerd']['nri']['enabled'] = True
                
                if 'kubelet' not in doc['spec']:
                    doc['spec']['kubelet'] = {}
                doc['spec']['kubelet']['registryPullQPS'] = 50
                doc['spec']['kubelet']['registryBurst'] = 100
                doc['spec']['kubelet']['kubeAPIQPS'] = 50
                doc['spec']['kubelet']['kubeAPIBurst'] = 100
                
                if 'metrics' not in doc['spec']['containerd']:
                    doc['spec']['containerd']['metrics'] = {}
                doc['spec']['containerd']['metrics']['address'] = "0.0.0.0:1338"
                
                if 'networking' in doc['spec']:
                    if 'calico' in doc['spec']['networking']:
                        doc['spec']['networking']['calico']['prometheusMetricsEnabled'] = True
                    if 'cilium' in doc['spec']['networking']:
                        doc['spec']['networking']['cilium']['enablePrometheusMetrics'] = True
                        doc['spec']['networking']['cilium']['version'] = 'v1.20.1'
                    if 'flannel' in doc['spec']['networking']:
                        doc['spec']['networking']['flannel']['backend'] = 'vxlan'
                        if 'kubeControllerManager' not in doc['spec']:
                            doc['spec']['kubeControllerManager'] = {}
                        doc['spec']['kubeControllerManager']['configureCloudRoutes'] = False
                        if 'cloudControllerManager' not in doc['spec']:
                            doc['spec']['cloudControllerManager'] = {}
                        doc['spec']['cloudControllerManager']['configureCloudRoutes'] = False
                
                if 'etcdClusters' in doc['spec']:
                    for etcd in doc['spec']['etcdClusters']:
                        if 'manager' not in etcd:
                            etcd['manager'] = {}
                        if 'env' not in etcd['manager']:
                            etcd['manager']['env'] = []
                        
                        has_quota = any(e.get('name') == 'ETCD_QUOTA_BACKEND_BYTES' for e in etcd['manager']['env'])
                        if not has_quota:
                            etcd['manager']['env'].append({
                                'name': 'ETCD_QUOTA_BACKEND_BYTES',
                                'value': '8589934592'
                            })
                            


        # Inject explicitly into all control plane InstanceGroups
        if doc.get('kind') == 'InstanceGroup':
            if 'spec' not in doc:
                doc['spec'] = {}
            if 'rootVolume' not in doc['spec']:
                doc['spec']['rootVolume'] = {}
            
            if doc['metadata']['name'].startswith('control-plane'):
                # Nested for v1alpha3
                doc['spec']['rootVolume']['type'] = 'hyperdisk-balanced'
                doc['spec']['rootVolume']['iops'] = 10000
                doc['spec']['rootVolume']['throughput'] = 1000
                doc['spec']['rootVolume']['size'] = 150
                
                # Flat for v1alpha2
                doc['spec']['rootVolumeType'] = 'hyperdisk-balanced'
                doc['spec']['rootVolumeIops'] = 10000
                doc['spec']['rootVolumeThroughput'] = 1000
                doc['spec']['rootVolumeSize'] = 150
                doc['spec']['associatePublicIP'] = True
            elif doc['metadata']['name'].startswith('nodes'):
                doc['spec']['machineType'] = 'n2-standard-4'
                doc['spec']['rootVolume']['type'] = 'pd-ssd'
                doc['spec']['rootVolume']['size'] = 35
                doc['spec']['rootVolumeType'] = 'pd-ssd'
                doc['spec']['rootVolumeSize'] = 35
    
    prometheus_ig = None
    for doc in docs:
        if not doc:
            continue
        
        if doc.get('kind') == 'InstanceGroup' and doc['metadata']['name'].startswith('nodes'):
            import copy
            prometheus_ig = copy.deepcopy(doc)
            prometheus_ig['metadata']['name'] = 'prometheus-nodes'
            prometheus_ig['spec']['machineType'] = 'c4-standard-96'
            prometheus_ig['spec']['maxSize'] = 1
            prometheus_ig['spec']['minSize'] = 1
            prometheus_ig['spec']['nodeLabels'] = {'prometheus-pool': 'true'}
            if 'rootVolume' not in prometheus_ig['spec']:
                prometheus_ig['spec']['rootVolume'] = {}
            prometheus_ig['spec']['rootVolume']['type'] = 'hyperdisk-balanced'
            prometheus_ig['spec']['rootVolume']['iops'] = 3000
            prometheus_ig['spec']['rootVolume']['throughput'] = 140
            prometheus_ig['spec']['rootVolume']['size'] = 64
            prometheus_ig['spec']['rootVolumeType'] = 'hyperdisk-balanced'
            prometheus_ig['spec']['rootVolumeIops'] = 3000
            prometheus_ig['spec']['rootVolumeThroughput'] = 140
            prometheus_ig['spec']['rootVolumeSize'] = 64
            
    if prometheus_ig:
        docs.append(prometheus_ig)
    
    with open(file_path, 'w') as f:
        yaml.dump_all(docs, f, default_flow_style=False)

if __name__ == "__main__":
    patch_yaml(sys.argv[1])
