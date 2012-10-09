#
# Author:: Kyle Bader <kyle.bader@dreamhost.com>
# Cookbook Name:: ceph
# Recipe:: radosgw
#
# Copyright 2011, DreamHost Web Hosting
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "apache2"
include_recipe "ceph::conf"

packages = %w{
  radosgw
  radosgw-dbg
  libapache2-mod-fastcgi
}

packages.each do |pkg|
  package pkg do
    action :upgrade
  end
end

if ::File.exist?("/etc/init/radosgw-all.conf")
  service "radosgw" do
    service_name "radosgw-all"
    supports :restart => true
    action[:enable,:start]
    provider Chef::Provider::Service::Upstart
    subscribes :restart, resources("template[ceph-conf]")
  end
else
  cookbook_file "/etc/init.d/radosgw" do
    source "radosgw"
    mode 0755
    owner "root"
    group "root"
    notifies [:stop, :start], "service[radosgw]"
  end

  service "radosgw" do
    service_name "radosgw"
    supports :restart => true
    action[:enable,:start]
    subscribes :restart, resources("template[ceph-conf]")
  end
end

apache_module "fastcgi" do
  conf true
end

apache_module "rewrite" do
  conf false
end

web_app "rgw" do
  template "rgw.conf.erb"
  enable true
  server_aliases node['ceph']['radosgw']['api_fqdn']
  email          node['ceph']['radosgw']['admin_email']
  bind           node['ceph']['radosgw']['rgw_addr']
end
