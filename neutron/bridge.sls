{% from "neutron/map.jinja" import bridge with context %}
{%- if bridge.enabled %}

{#TBD: prepared role for OpenVSwitch implementation on Network node side#}

net.ipv4.ip_forward:
  sysctl.present:
    - value: 1

net.ipv4.conf.default.rp_filter:
  sysctl.present:
    - value: 0

neutron_network_packages:
  pkg.installed:
  - names: {{ bridge.pkgs }}

{%- if grains.oscodename == 'precise' %}

neutron_network_precise_packages:
  pkg.installed:
  - names: {{ network.precise_pkgs }}

{%- endif %}


{% if bridge.plugin == "contrail" %}
{%- elif bridge.plugin == "ml2"  %}

{%- if not pillar.neutron.server is defined %}

/etc/neutron/neutron.conf:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/neutron-generic.conf.{{ bridge.plugin }}.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: neutron_network_packages

{%- endif %}

neutron_network_ml2_packages:
  pkg.installed:
  - names: {{ bridge.pkgs_ml2 }}

{% if bridge.ml2.ovs.bridge_mappings is defined %}
{% for bridge_mapping in bridge.ml2.ovs.bridge_mappings -%}

create_ovs_bridge_{{ bridge_mapping.bridge }}:
  cmd.run:
    - name: "ovs-vsctl add-br {{ bridge_mapping.bridge }}"
    - unless: "ovs-vsctl br-exists {{ bridge_mapping.bridge }}"

{% if bridge_mapping.get('rstp_enable', false) %}
set_ovs_bridge_{{ bridge_mapping.bridge }}_options:
  cmd.run:
    - name: "ovs-vsctl set Bridge {{ bridge_mapping.bridge }} rstp_enable=true"
    - onlyif: "ovs-vsctl br-exists {{ bridge_mapping.bridge }}"
    - require:
      - cmd: create_ovs_bridge_{{ bridge_mapping.bridge }}
{% endif %}
    
{% if bridge_mapping.physical_interface is defined %}
add_physical_interface_{{ bridge_mapping.physical_interface }}_to_{{ bridge_mapping.bridge }}:
    cmd.run:
    - name: "ovs-vsctl add-port {{ bridge_mapping.bridge }} {{ bridge_mapping.physical_interface }}"
    - unless: "ovs-vsctl list-ports {{ bridge_mapping.bridge }} | grep {{ bridge_mapping.physical_interface }}"
    - onlyif: "ip link list | egrep {{ bridge_mapping.physical_interface }}" 
    - require:
      - cmd: create_ovs_bridge_{{ bridge_mapping.bridge }}
{% endif %}

{% if bridge_mapping.tunnel_interfaces is defined %}
{% for tunnel_interface in bridge_mapping.tunnel_interfaces -%}
add_tunnel_interface_{{ tunnel_interface.name }}_to_{{ bridge_mapping.bridge }}:
    cmd.run:
    - name: "ovs-vsctl add-port {{ bridge_mapping.bridge }} {{ tunnel_interface.name }} \
      -- set interface {{ tunnel_interface.name }} \
      type={{ tunnel_interface.type }} \
      options:{{ tunnel_interface.get('options') | join(' options:') }}"
    - unless: "ovs-vsctl list-ports {{ bridge_mapping.bridge }} | grep {{ tunnel_interface.name }}"
    - require:
      - cmd: create_ovs_bridge_{{ bridge_mapping.bridge }}

set_tunnel_interface_{{ tunnel_interface.name }}_options:
    cmd.run:
    - name: "ovs-vsctl set Interface {{ tunnel_interface.name }} \
      type={{ tunnel_interface.type }} \
      options:{{ tunnel_interface.get('options') | join(' options:') }}"
    - onlyif: "ovs-vsctl list-ports {{ bridge_mapping.bridge }} | grep {{ tunnel_interface.name }}"
#    - require:
#      - cmd: create_ovs_bridge_{{ bridge_mapping.bridge }}

{% endfor %}
{% endif %}

{% endfor %}
{% endif %}

/etc/neutron/plugins/ml2/openvswitch_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/openvswitch_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_network_packages

/etc/neutron/l3_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/l3_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_network_packages

/etc/neutron/dhcp_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/dhcp_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_network_packages

/etc/neutron/metadata_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/metadata_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_network_packages

/etc/neutron/dnsmasq-neutron.conf:
  file.managed:
  - source: salt://neutron/files/{{ bridge.version }}/dnsmasq-neutron.conf
  - template: jinja
  - require:
    - pkg: neutron_network_packages

neutron_network_services:
  service.running:
  - names: {{ bridge.services }}
  - enable: true
  - watch:
    - file: /etc/neutron/neutron.conf
    - file: /etc/neutron/l3_agent.ini
    - file: /etc/neutron/dhcp_agent.ini
    - file: /etc/neutron/metadata_agent.ini
    - file: /etc/neutron/plugins/ml2/openvswitch_agent.ini

#gro_disabled:
#  cmd.run:
#  - name: "ethtool -K eth0 gro off; ethtool -K eth1 gro off; echo 'ethtool -K eth0 gro off; ethtool -K eth1 gro off' >> /etc/rc.local"
#  - unless: "cat /etc/rc.local | grep gro"

# Create neutron networks, based on the bridge_mappings configuration.

# End of plugin ml2
{%- endif %}

# bridge.enabled 
{%- endif %}
