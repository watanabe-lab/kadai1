# load-balancer.rb
#  -- for conf/level-1.conf
#  -- by simple-router.rb

# A router implementation in Trema
#
# Copyright (C) 2013 NEC Corporation
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

require "arp-table"
require "interface"
require "router-utils"
require "routing-table"

class LoadBalancer < Controller
  include RouterUtils

  def start
    @interfaces = Interfaces.new($interface)
    @arp_table = ARPTable.new
    @routing_table = RoutingTable.new($route)
puts "load balancer start!"
    client_connecting_server = IPAddr.new("192.168.0.250")
puts "client_connecting_server " + client_connecting_server
    super_server = IPAddr.new("192.168.0.252")
puts "super_server " + super_server
  end

  def packet_in dpid, message
    if message.arp_request?
      handle_arp_request(dpid, message)
    elsif message.arp_reply?
      handle_arp_reply(message)
    elsif message.ipv4?
      handle_ipv4(dpid, message)
    else
      # noop.
    end
  end

  private

  def handle_arp_request dpid, message
puts "handle_arp_request"
    port = message.in_port
    # arp_tpa: ARPターゲットアドレス (ipv4)
    daddr = message.arp_tpa
    if daddr == client_connecting_server
      interface = @interfaces.find_by_port_and_ipaddr(port, super_server)
      if interface
puts "interface true"
        arp_reply = create_arp_reply_from(message, interface.hwaddr)
        packet_out(dpid, arp_reply, SendOutPort.new(interface.port))
      end
    else
      puts "message.arp_tpa != connecting_server"
    end
  end

  def handle_arp_reply message
    @arp_table.update message.in_port, message.arp_spa, message.arp_sha
  end

  def handle_ipv4 dpid, message
    if go_to_client_connecting?(message)
      send_to_super dpid, message
puts "go to client connecting"
    elsif came_from_super?(message)
      send_to_client dpid, message
puts "came from super"
    else
puts "came from else"
    end
    if should_forward?(message)
      forward dpid, message
    elsif message.icmpv4_echo_request?
      handle_icmpv4_echo_request dpid, message
    else
      # noop.
    end
  end

  def should_forward? message
    not @interfaces.find_by_ipaddr( super_user )
  end

  def go_to_client_connecting? message
    return message.ipv4_daddr == client_connecting_server
  end

  def came_from_super? message
    return message.ipv4_saddr == super_server
  end

  def handle_icmpv4_echo_request dpid, message
    interface = @interfaces.find_by_port( message.in_port )
    saddr = message.ipv4_saddr.value
    arp_entry = @arp_table.lookup( saddr )
    if arp_entry
      icmpv4_reply = create_icmpv4_reply( arp_entry, interface, message )
      packet_out dpid, icmpv4_reply, SendOutPort.new( interface.port )
    else
      handle_unresolved_packet dpid, message, interface, saddr
    end
  end


  def forward dpid, message
    next_hop = resolve_next_hop( message.ipv4_daddr )

    interface = @interfaces.find_by_prefix( next_hop )
puts interface
    if not interface or interface.port == message.in_port
      return
    end

    arp_entry = @arp_table.lookup( next_hop )
    if arp_entry
      macsa = interface.hwaddr
      macda = arp_entry.hwaddr
      action = create_action_from( macsa, macda, interface.port )
      flow_mod dpid, message, action
      packet_out dpid, message.data, action
    else
      handle_unresolved_packet dpid, message, interface, next_hop
    end
  end

  def resolve_next_hop( daddr )
    interface = @interfaces.find_by_prefix( daddr.value )
    if interface
      daddr.value
    else
      @routing_table.lookup( daddr.value )
    end
  end


  def flow_mod( dpid, message, action )
    send_flow_mod_add(
      dpid,
      :match => ExactMatch.from( message ),
      :actions => action
    )
  end


  def packet_out( dpid, packet, action )
    send_packet_out(
      dpid,
      :data => packet,
      :actions => action
    )
  end


  def handle_unresolved_packet( dpid, message, interface, ipaddr )
    arp_request = create_arp_request_from( interface, ipaddr )
    packet_out dpid, arp_request, SendOutPort.new( interface.port )
  end


  def create_action_from( macsa, macda, port )
    [
      SetEthSrcAddr.new( macsa ),
      SetEthDstAddr.new( macda ),
      SendOutPort.new( port )
    ]
  end
end


### Local variables:
### mode: Ruby
### coding: utf-8
### indent-tabs-mode: nil
### End:
