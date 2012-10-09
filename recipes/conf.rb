template "ceph-conf" do
  source "ceph.conf.erb"
  path "/etc/ceph/ceph.conf"
  variables(
    :mon_addresses => get_mon_addresses()
  )
  mode '0644'
end
