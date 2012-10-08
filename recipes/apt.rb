include_recipe "apt"

apt_repository "ceph-release" do
  repo_name "ceph"
  uri "http://ceph.newdream.net/debian/"
  distribution node['lsb']['codename']
  components ["main"]
  key "https://raw.github.com/ceph/ceph/master/keys/release.asc"
  notifies :remove, "apt_repository[ceph-autobuild]"
  only_if { node['ceph']['branch'] == "release" }
end

apt_repository "ceph-autobuild" do
  repo_name "ceph-autobuild"
  uri "http://gitbuilder.ceph.com/ceph-deb-#{node['lsb']['codename']}-x86_64-basic/ref/autobuild"
  distribution node['lsb']['codename']
  components ["main"]
  key "https://raw.github.com/ceph/ceph/master/keys/autobuild.asc"
  notifies :remove, "apt_repository[ceph-release]"
  only_if { node['ceph']['branch'] == "autobuild" }
end
