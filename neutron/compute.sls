{% from "neutron/map.jinja" import compute with context %}
{%- if compute.enabled %}

net.ipv4.ip_forward:
  sysctl.present:
    - value: 1

neutron_compute_packages:
  pkg.installed:
  - names: {{ compute.pkgs }}

{%- if compute.plugin == 'ml2' %}

neutron_compute_packages_ml2:
  pkg.installed:
  - names: {{ compute.pkgs_ml2 }}

/etc/neutron/neutron.conf:
  file.managed:
  - source: salt://neutron/files/{{ compute.version }}/neutron-generic.conf.{{ compute.plugin }}.{{ grains.os_family }}
  - template: jinja
  - require:
    - pkg: neutron_compute_packages

/etc/neutron/plugins/ml2/openvswitch_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ compute.version }}/openvswitch_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_compute_packages
    - pkg: neutron_compute_packages_ml2



{% if compute.ml2.ovs.bridge_mappings is defined %}
{% for bridge_mapping in compute.ml2.ovs.bridge_mappings -%}

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


neutron_compute_services:
  service.running:
  - names: {{ compute.services }}
  - enable: true
  - watch:
    - file: /etc/neutron/neutron.conf
    - file: /etc/neutron/plugins/ml2/openvswitch_agent.ini


{%- if compute.dvr.enabled %}

neutron_compute_packages_dvr:
  pkg.installed:
  - names: {{ compute.pkgs_dvr }}

/etc/neutron/l3_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ compute.version }}/l3_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_compute_packages_dvr

/etc/neutron/metadata_agent.ini:
  file.managed:
  - source: salt://neutron/files/{{ compute.version }}/metadata_agent.ini
  - template: jinja
  - require:
    - pkg: neutron_compute_packages_dvr

neutron_compute_services_dvr:
  service.running:
  - names: {{ compute.services_dvr }}
  - enable: true
  - watch:
    - file: /etc/neutron/l3_agent.ini
    - file: /etc/neutron/metadata_agent.ini

{%- endif %}


{%- endif %}



{%- endif %}
