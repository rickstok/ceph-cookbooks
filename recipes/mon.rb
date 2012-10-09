# this recipe creates a monitor cluster
raise "fsid must be set in config" if node['ceph']['config']['fsid'].nil?
raise "mon_initial_members must be set in config" if node['ceph']['config']['mon_initial_members'].nil?


require 'json'

include_recipe "ceph::common"
include_recipe "ceph::conf"

if is_crowbar?
  ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
else
  ipaddress = node['ceph']['mon']['ipaddress']
end

# TODO cluster name
cluster = node['ceph']['cluster']
mon_addresses = get_mon_addresses()

execute 'ceph-mon mkfs' do
  command <<-EOH
set -e
KR='/var/lib/ceph/tmp/#{cluster}-#{node['hostname']}.mon.keyring'
# TODO don't put the key in "ps" output, stdout
ceph-authtool "$KR" --create-keyring --name=mon. --add-key='#{node['ceph']['monitor-secret']}' --cap mon 'allow *'

ceph-mon --mkfs -i #{node['hostname']} --keyring "$KR"
rm -f -- "$KR"
touch /var/lib/ceph/mon/#{cluster}-#{node['hostname']}/done
EOH
  # TODO built-in done-ness flag for ceph-mon?
  notifies :start, "service[ceph-mon]", :immediately
  not_if { node['ceph']['monitor-secret'].nil? or ::File.exists?("/var/lib/ceph/mon/#{cluster}-#{node['hostname']}/done") }
end

ruby_block "tell ceph-mon about its peers" do
  block do
    mon_addresses.each do |addr|
      e = Chef::Resource::Execute.new ("tell ceph-mon #{addr} about its peers", run_context)
      e.command = "ceph --admin-daemon /var/run/ceph/#{cluster}-mon.#{node['hostname']}.asok add_bootstrap_peer_hint #{addr}"
      r.run_action(:run)
    end
  end
end

have_key = ::File.exists?("/etc/ceph/#{cluster}.client.admin.keyring")

ruby_block "wait until quorum is formed" do
  block do
    while not have_key and not have_quorum? do # so, our first run and we have no quorum
      #sleep
      sleep(1)
    end
  end
end

ruby_block "create client.admin keyring" do
  block do
    # TODO --set-uid=0
    key = %x[
    ceph \
      --name mon. \
          --keyring "/var/lib/ceph/mon/#{cluster}-#{node['hostname']}/keyring" \
          auth get-or-create-key client.admin \
          mon 'allow *' \
          osd 'allow *' \
          mds allow
        ]
        raise 'adding or getting admin key failed' unless $?.exitstatus == 0
        # TODO don't put the key in "ps" output, stdout
        system 'ceph-authtool', \
          "/etc/ceph/#{cluster}.client.admin.keyring", \
          '--create-keyring', \
          '--name=client.admin', \
          "--add-key=#{key}"
        raise 'creating admin keyring failed' unless $?.exitstatus == 0
  end
  not_if { have_key }
  only_if { have_quorum? }
end

ruby_block "save bootstrap_osd_key" do
  block do
    osd_key = %x[
          ceph \
            --name mon. \
            --keyring '/var/lib/ceph/mon/#{cluster}-#{node['hostname']}/keyring' \
            auth get-or-create-key client.bootstrap-osd mon \
            "allow command osd create ...; \
            allow command osd crush set ...; \
            allow command auth add * osd allow\\ * mon allow\\ rwx; \
            allow command mon getmap"
        ]
    raise 'adding or getting bootstrap-osd key failed' unless $?.exitstatus == 0
    node.set['ceph']['bootstrap_osd_key'] = osd_key
  end
  only_if { have_quorum? }
  not_if { node['ceph']['bootstrap_osd_key'] }
end

ruby_block "save bootstrap_client_key" do
  block do
    client_key = %x[
          ceph \
            --name mon. \
            --keyring '/var/lib/ceph/mon/#{cluster}-#{node['hostname']}/keyring' \
            auth get-or-create-key client.bootstrap-client mon \
            "allow command auth get-or-create-key * osd * mon *;"
        ]
    raise 'adding or getting bootstrap-client key failed' unless $?.exitstatus == 0
    node.set['ceph']['bootstrap_client_key'] = client_key
    node.save
  end
  only_if { have_quorum? }
  not_if { node['ceph']['bootstrap_client_key'] }
end

service "ceph-mon" do
  provider Chef::Provider::Service::Upstart
  service_name "ceph-mon-all"
  supports :restart => true
  action [:enable, :start]
  subscribes :restart, resources("template[ceph-conf]")
end
